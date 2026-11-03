import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { beforeEach, afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDocFromServer, updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp } from 'firebase/firestore';
import { account, vendor, draft, prepare, orderRef, counterRef, requestRef } from './checkout_helpers.mjs';
import { progressWrites, initialQueue } from './fcfs_helpers.mjs';
import { countRef, bootstrapCount, countPayload, countWrites, submitCount, advanceCount } from './public_queue_count_helpers.mjs';
import { budgetDiagnostic } from './checkout_budget.mjs';
import { boundedOfflineCleanup } from './checkout_transport.mjs';

const rules = readFileSync(new URL('../../pilot/firestore.stage4-integrated.rules', import.meta.url),'utf8');
const runId = randomBytes(5).toString('hex'); let env, sequence = 0;
beforeEach(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
  assert.equal(process.env.SMART_CANTEEN_INTEGRATED_RULES,'true');
  env = await initializeTestEnvironment({projectId:`demo-integrated-${runId}-${++sequence}`,
    firestore:{host:'127.0.0.1',port:8080,rules}});
});
afterEach(async () => { await boundedOfflineCleanup(() => env?.cleanup()); });
const menuRef = (db, collection, id = 'food0', uid = 'vendor') => doc(db,'stalls',uid,collection,id);
const get = async ref => (await getDocFromServer(ref)).data();
async function deny(operation) {
  const error = await assertFails(operation);
  assert.equal(error.code,'permission-denied',error.message);
  assert.equal(budgetDiagnostic.test(error.message),false,'Rules budget exhaustion is not authorization proof');
}
async function setup(size = 2, uid = 'student', stall = 'vendor') {
  const owner = await vendor(env,stall), student = await account(env,uid);
  await bootstrapCount(owner,stall);
  const q = await draft(student,uid,stall,size); await prepare(student,q);
  return {owner,student,q};
}
function deletePair(db, food = 'food0', uid = 'vendor') {
  const batch = writeBatch(db);
  batch.delete(menuRef(db,'menuFoods',food,uid)); batch.delete(menuRef(db,'menuMemberships',food,uid));
  return batch.commit();
}
// Mirrors the production transaction's optimistic draft-revision and membership
// checks. Direct malicious batches below bypass it and exercise the Rules.
function deleteAtRevision(db, revision, food = 'food0') {
  return runTransaction(db, async tx => {
    const f = menuRef(db,'menuFoods',food), m = menuRef(db,'menuMemberships',food);
    const current = await tx.get(f), membership = await tx.get(m), data = current.data();
    if (!data || data.revision !== revision) throw new Error('stale-menu-revision');
    const category = await tx.get(menuRef(db,'menuCategories',data.categoryId));
    if (data.vendorUid !== 'vendor' || membership.data()?.vendorUid !== 'vendor' ||
        membership.data()?.categoryId !== data.categoryId || category.data()?.vendorUid !== 'vendor') {
      throw new Error('invalid-menu-membership');
    }
    tx.delete(f); tx.delete(m);
  }, {maxAttempts:8});
}
async function assertPendingWithoutTicket(student, owner, q) {
  assert.equal((await get(requestRef(student,q.studentUid,q.submissionId))).state,'pending');
  // No order resource means Rules cannot establish a reader owner. Use a
  // separate connected emulator-only privileged observer to prove absence;
  // never relax the real order-reader policy for this test assertion.
  await env.withSecurityRulesDisabled(async context => {
    assert.equal((await getDocFromServer(orderRef(context.firestore(),q.submissionId))).exists(),false);
  });
  assert.equal((await getDocFromServer(counterRef(owner,q.vendorUid))).exists(),false);
  assert.equal((await get(countRef(student,q.vendorUid))).count,0);
}

for (const available of [true,false]) test(`integrated owner deletes matched food/membership (available=${available}) while preserving category and count`, async () => {
  const {owner,student} = await setup();
  if (!available) await updateDoc(menuRef(owner,'menuFoods'),{available:false,revision:2,updatedAt:serverTimestamp()});
  const category = await get(menuRef(owner,'menuCategories','cat0'));
  await deny(deleteDoc(menuRef(owner,'menuFoods'))); await deny(deleteDoc(menuRef(owner,'menuMemberships')));
  await deleteAtRevision(owner,available?1:2);
  assert.equal((await getDocFromServer(menuRef(owner,'menuFoods'))).exists(),false);
  assert.equal((await getDocFromServer(menuRef(owner,'menuMemberships'))).exists(),false);
  assert.deepEqual(await get(menuRef(owner,'menuCategories','cat0')),category);
  await deny(deleteDoc(menuRef(owner,'menuCategories','cat0')));
  assert.equal((await get(countRef(student))).count,0);
});
test('integrated deletion rejects Students, foreign Vendors, anonymous clients and mismatched pairs', async () => {
  const {owner,student} = await setup(), other = await vendor(env,'otherVendor');
  for (const client of [student,other,env.unauthenticatedContext().firestore()]) await deny(deletePair(client));
  const mismatched = writeBatch(owner);
  mismatched.delete(menuRef(owner,'menuFoods','food0')); mismatched.delete(menuRef(owner,'menuMemberships','food1'));
  await deny(mismatched.commit());
  const categoryAttack = writeBatch(owner);
  categoryAttack.delete(menuRef(owner,'menuFoods')); categoryAttack.delete(menuRef(owner,'menuMemberships'));
  categoryAttack.delete(menuRef(owner,'menuCategories','cat0')); await deny(categoryAttack.commit());
  assert.equal((await getDocFromServer(menuRef(owner,'menuFoods'))).exists(),true);
});
test('real confirmed two-food snapshots survive deletion and continue through exact FCFS/count progression', async () => {
  const {owner,student,q} = await setup(); const first = await submitCount(student,q);
  const q2 = await draft(student); await prepare(student,q2); await submitCount(student,q2);
  const header = await get(orderRef(student,q.submissionId));
  const child = await get(doc(student,'orders',q.submissionId,'items','1'));
  const request = await get(requestRef(student,'student',q.submissionId));
  await deleteAtRevision(owner,1); await deleteAtRevision(owner,1,'food1');
  assert.deepEqual(await get(orderRef(student,q.submissionId)),header);
  assert.deepEqual(await get(doc(student,'orders',q.submissionId,'items','1')),child);
  assert.deepEqual(await get(requestRef(student,'student',q.submissionId)),request);
  assert.equal((await get(countRef(student))).count,2);
  const preparing = await advanceCount(owner,first); assert.equal((await get(countRef(student))).count,2);
  const ready = await advanceCount(owner,preparing); assert.equal((await get(countRef(student))).count,1);
  await advanceCount(owner,ready); assert.equal((await get(countRef(student))).count,1);
  const completed = await get(orderRef(student,q.submissionId));
  for (const field of ['studentUid','vendorUid','ticket','totalSen','firstItem','createdAt','paymentMethod','paymentStatus']) {
    assert.deepEqual(completed[field],header[field]);
  }
  assert.deepEqual(await get(doc(student,'orders',q.submissionId,'items','1')),child);
  assert.equal((await submitCount(student,q)).ticket,1); assert.equal((await get(countRef(student))).count,1);
});
test('outdated Cart/prepared request cannot confirm deleted food even with prebuilt canonical payload', async () => {
  const {owner,student,q} = await setup(); const p = await countPayload(student,q);
  await deleteAtRevision(owner,1);
  const batch = writeBatch(student); countWrites(batch,student,p); await deny(batch.commit());
  await deny(submitCount(student,q)); await assertPendingWithoutTicket(student,owner,q);
});
test('food revision changes reject stale checkout and stale Delete; refreshed draft remains valid', async () => {
  const {owner,student,q} = await setup(); const p = await countPayload(student,q);
  await updateDoc(menuRef(owner,'menuFoods'),{name:'Edited Food',priceSen:900,revision:2,updatedAt:serverTimestamp()});
  await assert.rejects(deleteAtRevision(owner,1),/stale-menu-revision/);
  const batch = writeBatch(student); countWrites(batch,student,p); await deny(batch.commit());
  await assertPendingWithoutTicket(student,owner,q);
  const fresh = await draft(student); await prepare(student,fresh);
  const order = await submitCount(student,fresh); assert.equal(order.firstItem.name,'Edited Food');
  assert.equal(order.totalSen,900); await deleteAtRevision(owner,2);
  assert.equal((await get(countRef(student))).count,1);
});
test('concurrent checkout versus Food Delete has only valid serial outcomes and never consumes a phantom ticket', async () => {
  const {owner,student,q} = await setup();
  const results = await Promise.allSettled([deleteAtRevision(owner,1),submitCount(student,q)]);
  assert.equal(results[0].status,'fulfilled',results[0].reason?.message);
  assert.equal((await getDocFromServer(menuRef(owner,'menuFoods'))).exists(),false);
  assert.equal((await getDocFromServer(menuRef(owner,'menuMemberships'))).exists(),false);
  if (results[1].status === 'fulfilled') {
    assert.equal(results[1].value.ticket,1); assert.equal((await get(countRef(student))).count,1);
    assert.equal((await get(requestRef(student,'student',q.submissionId))).state,'confirmed');
    assert.equal((await get(counterRef(owner))).lastTicket,1);
  } else {
    assert.equal(results[1].reason.code,'permission-denied',results[1].reason.message);
    assert.equal(budgetDiagnostic.test(results[1].reason.message),false);
    await assertPendingWithoutTicket(student,owner,q);
  }
});
test('deleting food from one stall cannot change another stall menu or queue', async () => {
  const a = await setup(1,'alice','alpha'), b = await setup(1,'bob','beta');
  await submitCount(a.student,a.q); await submitCount(b.student,b.q);
  await deletePair(a.owner,'food0','alpha');
  assert.equal((await getDocFromServer(menuRef(b.owner,'menuFoods','food0','beta'))).exists(),true);
  assert.equal((await get(countRef(a.student,'alpha'))).count,1);
  assert.equal((await get(countRef(b.student,'beta'))).count,1);
  await deny(deletePair(a.owner,'food0','beta'));
});
test('old-style checkout/processing without the Stage 4B projection fails safely under integrated policy', async () => {
  const {owner,student,q} = await setup(); const p = await countPayload(student,q); p.omitSummary = true;
  const old = writeBatch(student); countWrites(old,student,p); await deny(old.commit());
  await assertPendingWithoutTicket(student,owner,q);
  const order = await submitCount(student,q), processing = writeBatch(owner);
  progressWrites(processing,owner,order,initialQueue()); await deny(processing.commit());
  assert.equal((await get(orderRef(student,q.submissionId))).status,'Pending');
  assert.equal((await get(countRef(student))).count,1);
});
test('Food Delete does not grant private counter, foreign request or order reads', async () => {
  const {owner,student,q} = await setup(); await submitCount(student,q);
  const observer = await account(env,'observer'); await deleteAtRevision(owner,1);
  assert.equal((await get(countRef(observer))).count,1);
  for (const ref of [counterRef(student),counterRef(observer),orderRef(observer,q.submissionId),
    requestRef(observer,'student',q.submissionId),doc(observer,'orders',q.submissionId,'items','1')]) {
    await deny(getDocFromServer(ref));
  }
});
test('combining paired deletion with forged order history or a forged public count rejects the entire batch', async () => {
  const {owner,student,q} = await setup(); await submitCount(student,q);
  for (const target of ['order','count']) {
    const batch = writeBatch(owner); batch.delete(menuRef(owner,'menuFoods')); batch.delete(menuRef(owner,'menuMemberships'));
    if (target === 'order') batch.update(orderRef(owner,q.submissionId),{totalSen:1});
    else batch.update(countRef(owner),{count:0,updatedAt:serverTimestamp()});
    await deny(batch.commit());
    assert.equal((await getDocFromServer(menuRef(owner,'menuFoods'))).exists(),true);
    assert.equal((await get(countRef(student))).count,1);
  }
});
