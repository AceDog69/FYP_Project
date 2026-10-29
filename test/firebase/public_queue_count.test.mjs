import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { before, beforeEach, afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDocFromServer, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { account, vendor, draft, prepare, submit, counterRef, orderRef, requestRef } from './checkout_helpers.mjs';
import { queueRef, progressRef, progressWrites, initialQueue } from './fcfs_helpers.mjs';
import { countRef, countData, bootstrapCount, countPayload, countWrites, submitCount, advanceCount } from './public_queue_count_helpers.mjs';
import { budgetDiagnostic } from './checkout_budget.mjs';
import { boundedOfflineCleanup } from './checkout_transport.mjs';

const candidate = readFileSync(new URL('../../pilot/firestore.stage4b.rules', import.meta.url), 'utf8');
const closed = readFileSync(new URL('../../pilot/firestore.stage4b.closed.rules', import.meta.url), 'utf8');
const legacy = readFileSync(new URL('../../pilot/firestore.ordering.rules', import.meta.url), 'utf8');
const runId = randomBytes(5).toString('hex'); let env, sequence = 0;
before(() => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
});
beforeEach(async () => {
  env = await initializeTestEnvironment({projectId:`demo-s4b-${runId}-${++sequence}`,
    firestore:{host:'127.0.0.1',port:8080,rules:candidate}});
});
afterEach(async () => {
  try {
    const response = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${env.projectId}:ruleCoverage`, {signal:AbortSignal.timeout(5000)});
    assert.equal(response.ok, true); mkdirSync(new URL('./artifacts/', import.meta.url), {recursive:true});
    writeFileSync(new URL(`./artifacts/stage4b-rule-coverage-${sequence}.json`, import.meta.url), JSON.stringify(await response.json()));
  } finally { await boundedOfflineCleanup(() => env?.cleanup()); }
});
async function deny(operation) {
  const error = await assertFails(operation);
  assert.equal(error.code, 'permission-denied', error.message);
  assert.equal(budgetDiagnostic.test(error.message), false, 'Budget exhaustion is not a security denial');
}
async function switchRules(rules) {
  // v6 exposes rule loading through initializeTestEnvironment, not an instance
  // loadFirestoreRules method. Cleanup closes clients, NEVER clears documents.
  const projectId = env.projectId;
  await boundedOfflineCleanup(() => env.cleanup());
  env = await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,rules}});
}
const existingDb = uid => env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
async function settled(operations) {
  const results = await Promise.allSettled(operations);
  const errors = results.filter(r => r.status === 'rejected').map(r => r.reason);
  if (errors.length) throw new AggregateError(errors, 'Concurrency failed after all siblings settled');
  return results.map(r => r.value);
}
async function setup(count = 1, uid = 'student', stall = 'vendor') {
  const owner = await vendor(env, stall), student = await account(env, uid);
  await bootstrapCount(owner, stall); const q = await draft(student, uid, stall, count); await prepare(student, q);
  return {owner,student,q};
}
async function count(db, uid = 'vendor') { return (await getDocFromServer(countRef(db, uid))).data().count; }
async function malicious(db, q, mutate) {
  const p = await countPayload(db, q); mutate(p); const batch = writeBatch(db); countWrites(batch, db, p); return batch.commit();
}

test('no-order Student reads missing as unavailable and verified empty queue as zero', async () => {
  const owner = await vendor(env), student = await account(env, 'newStudent');
  assert.equal((await getDocFromServer(countRef(student))).exists(), false);
  await bootstrapCount(owner); assert.equal(await count(student), 0);
  const data = (await getDocFromServer(countRef(student))).data();
  assert.deepEqual(Object.keys(data).sort(), ['schemaVersion','vendorUid','lastTicket','nextTicket','preparing','count','updatedAt'].sort());
});
for (const size of [1,2]) test(`confirmed ${size}-food checkout increments once; same-ID retry preserves counter and count`, async () => {
  const {owner,student,q} = await setup(size); const order = await submitCount(student, q);
  assert.equal(order.ticket, 1); assert.equal(await count(student), 1);
  await submitCount(student, q); assert.equal(await count(student), 1);
  assert.equal((await getDocFromServer(counterRef(owner))).data().lastTicket, 1);
  if (size === 2) {
    const max = await draft(student, 'student', 'vendor', 2); for (const item of max.items) item.quantity = 20;
    max.totalSen = max.items.reduce((s,i) => s+i.quantity*i.priceSen,0); await prepare(student,max);
    assert.equal((await submitCount(student,max)).ticket,2); assert.equal(await count(student),2);
  }
});
test('multiple Pending, Preparing unchanged, Ready decreases once and Completed unchanged', async () => {
  const {owner,student,q} = await setup(); const first = await submitCount(student,q);
  const second = await draft(student); await prepare(student,second); await submitCount(student,second);
  assert.equal(await count(student),2);
  const preparing = await advanceCount(owner,first); assert.equal(await count(student),2);
  const ready = await advanceCount(owner,preparing); assert.equal(await count(student),1);
  await assert.rejects(advanceCount(owner,preparing), /stale-order/); assert.equal(await count(student),1);
  await advanceCount(owner,ready); assert.equal(await count(student),1);
});
test('independent stalls expose separate counts to a Student with no orders', async () => {
  const a = await setup(1,'alice','alpha'), b = await setup(1,'bob','beta');
  await submitCount(a.student,a.q); await submitCount(b.student,b.q);
  const observer = await account(env,'observer'); assert.equal(await count(observer,'alpha'),1); assert.equal(await count(observer,'beta'),1);
  const preparing = await advanceCount(a.owner,(await getDocFromServer(orderRef(a.owner,a.q.submissionId))).data());
  await advanceCount(a.owner,preparing); assert.equal(await count(observer,'alpha'),0); assert.equal(await count(observer,'beta'),1);
});
test('same-ID parallel submissions cannot increment count twice', async () => {
  const {student,q} = await setup(); const orders = await settled([submitCount(student,q),submitCount(student,q)]);
  assert.deepEqual(orders.map(o => o.ticket),[1,1]); assert.equal(await count(student),1);
});
test('parallel Students allocate unique tickets and neither can inspect the private counter', async () => {
  const {student,q} = await setup(); const other = await account(env,'other'), q2 = await draft(other,'other'); await prepare(other,q2);
  const orders = await settled([submitCount(student,q),submitCount(other,q2)]);
  assert.deepEqual(orders.map(o => o.ticket).sort(),[1,2]); assert.equal(await count(other),2);
  await deny(getDocFromServer(counterRef(student))); await deny(getDocFromServer(counterRef(other)));
});
test('concurrent checkout and Start/Ready serialize without losing count updates', async () => {
  const {owner,student,q} = await setup(); let first = await submitCount(student,q);
  const q2 = await draft(student); await prepare(student,q2);
  [first] = await settled([advanceCount(owner,first),submitCount(student,q2)]); assert.equal(await count(student),2);
  const q3 = await draft(student); await prepare(student,q3);
  await settled([advanceCount(owner,first),submitCount(student,q3)]); assert.equal(await count(student),2);
});
test('bootstrap can race checkout without fabricating zero or overwriting a ticket', async () => {
  const {owner,student,q} = await setup(); await settled([bootstrapCount(owner),submitCount(student,q)]);
  assert.equal(await count(student),1);
});

for (const [name, mutate] of [
  ['missing summary', p => p.omitSummary = true],
  ['forged summary count', p => p.summary.count = 0],
  ['forged last ticket', p => p.summary.lastTicket = 100],
  ['extra private ID', p => p.summary.lastOrderId = p.q.submissionId],
  ['wrong vendor', p => p.summary.vendorUid = 'other'],
  ['forged next ticket', p => p.summary.nextTicket = 2],
  ['forged timestamp', p => p.summary.updatedAt = new Date(0)],
  ['missing counter', p => p.omitCounter = true],
  ['forged price', p => p.header.firstItem.priceSen++],
  ['forged category', p => p.header.firstItem.categoryId = 'cat1'],
  ['forged snapshot name', p => p.header.firstItem.name = 'Forged'],
  ['forged availability snapshot revision', p => p.header.firstItem.foodRevision++],
  ['forged total', p => p.header.totalSen++],
  ['forged owner', p => p.header.studentUid = 'other'],
  ['forged Ready status', p => p.header.status = 'Ready'],
  ['forged quantity', p => p.header.firstItem.quantity = 21],
  ['missing child', p => p.omitChild = 1],
]) test(`atomic checkout rejects ${name} for authorization/integrity, never a budget error`, async () => {
  const {student,q} = await setup(2); await deny(malicious(student,q,mutate));
  assert.equal(await count(student),0); assert.equal((await getDocFromServer(requestRef(student,'student',q.submissionId))).data().state,'pending');
});
test('direct summary writes/deletes, anonymous reads and collection listing are denied', async () => {
  const {owner,student} = await setup(); const otherVendor = await vendor(env,'otherVendor');
  await deny(setDoc(countRef(student),countData('vendor',0,1,false)));
  await deny(updateDoc(countRef(student),{count:7,updatedAt:serverTimestamp()}));
  await deny(setDoc(countRef(otherVendor),countData('vendor',0,1,false)));
  await deny(deleteDoc(countRef(owner))); await deny(getDocFromServer(countRef(env.unauthenticatedContext().firestore())));
  await deny(getDocs(collection(student,'stallQueueCounts'))); await deny(getDocs(collection(student,'checkoutCounters')));
});
test('direct order/FCFS forgery cannot bypass count coupling or Student/Vendor boundaries', async () => {
  const {owner,student,q} = await setup(); const order = await submitCount(student,q), wrong = await vendor(env,'wrong');
  await deny(updateDoc(orderRef(student,order.orderId),{status:'Ready',readyAt:serverTimestamp()}));
  await deny(updateDoc(orderRef(wrong,order.orderId),{status:'Preparing',statusRevision:1,statusUpdatedAt:serverTimestamp(),preparingAt:serverTimestamp()}));
  const batch = writeBatch(owner); progressWrites(batch,owner,order,initialQueue()); await deny(batch.commit());
  const invalid = writeBatch(owner); progressWrites(invalid,owner,order,initialQueue());
  invalid.set(countRef(owner),countData('vendor',1,3,true)); await deny(invalid.commit());
});
test('privacy denies other Students orders, requests and items while allowing public counts', async () => {
  const {student,q} = await setup(2); await submitCount(student,q); const observer = await account(env,'observer');
  assert.equal(await count(observer),1);
  for (const ref of [counterRef(observer),orderRef(observer,q.submissionId),requestRef(observer,'student',q.submissionId),
    doc(observer,'orders',q.submissionId,'items','1'),queueRef(observer)]) await deny(getDocFromServer(ref));
  await deny(getDocs(query(collection(observer,'orders'),where('vendorUid','==','vendor'))));
});
test('stale/malformed projections cannot be read as confirmed; owner repairs from authority', async () => {
  const {owner,student,q} = await setup(); await submitCount(student,q);
  for (const bad of [{count:0},{lastTicket:0},{studentUid:'secret'},{preparing:true},{count:'1'}]) {
    await env.withSecurityRulesDisabled(context => updateDoc(countRef(context.firestore()),bad));
    await deny(getDocFromServer(countRef(student))); await bootstrapCount(owner); assert.equal(await count(student),1);
  }
});
for (const state of ['Pending','Preparing','Ready','Completed']) test(`existing-stall bootstrap from legacy ${state} preserves tickets and derives exact count`, async () => {
  await switchRules(legacy); const owner = await vendor(env), student = await account(env,'student');
  const q = await draft(student); await prepare(student,q); let order = await submit(student,'student',q.submissionId);
  // Use the legacy processing helper until the requested pre-migration state.
  const {advance} = await import('./fcfs_helpers.mjs');
  while (order.status !== state) order = await advance(owner,order);
  await switchRules(candidate); await bootstrapCount(existingDb('vendor'));
  assert.equal(await count(existingDb('student')),['Ready','Completed'].includes(state)?0:1);
  assert.equal((await getDocFromServer(counterRef(existingDb('vendor')))).data().lastTicket,1);
});
test('bootstrap rejects malformed/missing boundary order authority and impossible cursor', async () => {
  const {owner,student} = await setup();
  await env.withSecurityRulesDisabled(context => setDoc(counterRef(context.firestore()),{schemaVersion:1,vendorUid:'vendor',
    lastTicket:1,lastOrderId:'00000000000000000000',updatedAt:serverTimestamp()}));
  await deny(bootstrapCount(owner)); await deny(getDocFromServer(countRef(student)));
});
test('closed Stage 4B candidate preserves default-disabled ordering and deletion', async () => {
  await switchRules(closed); const owner = await vendor(env), student = await account(env,'student');
  await bootstrapCount(owner); assert.equal(await count(student),0); const q = await draft(student);
  await deny(prepare(student,q)); await deny(deleteDoc(doc(owner,'stalls','vendor','menuFoods','food0')));
});
test('ordering Stage 4B candidate keeps Food and Category Delete closed', async () => {
  const {owner} = await setup(); await deny(deleteDoc(doc(owner,'stalls','vendor','menuFoods','food0')));
  await deny(deleteDoc(doc(owner,'stalls','vendor','menuCategories','cat0')));
});
for (const missing of ['menuFoods/food0','menuCategories/cat0','menuMemberships/food0']) test(`canonical ${missing} remains mandatory despite a valid public count`, async () => {
  const {student,q} = await setup(); const p = await countPayload(student,q);
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(),'stalls','vendor',...missing.split('/'))));
  const batch = writeBatch(student); countWrites(batch,student,p); await deny(batch.commit()); assert.equal(await count(student),0);
});
test('unavailable canonical food cannot be ordered by replaying a formerly valid snapshot', async () => {
  const {owner,student,q} = await setup(); const p = await countPayload(student,q);
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{available:false,revision:2,updatedAt:serverTimestamp()});
  const batch = writeBatch(student); countWrites(batch,student,p); await deny(batch.commit()); assert.equal(await count(student),0);
});
test('over-limit, duplicate foods and invalid quantities cannot enter a prepared checkout', async () => {
  const {student} = await setup();
  for (const size of [3,4,5]) await deny(prepare(student,await draft(student,'student','vendor',size)));
  const duplicate = await draft(student,'student','vendor',2); duplicate.items[1] = {...duplicate.items[0]};
  duplicate.totalSen = duplicate.items.reduce((s,i) => s+i.priceSen*i.quantity,0); await deny(prepare(student,duplicate));
  for (const quantity of [0,21]) {
    const q = await draft(student); q.items[0].quantity = quantity; q.totalSen = q.items[0].priceSen*quantity; await deny(prepare(student,q));
  }
  assert.equal(await count(student),0);
});
test('a mathematically matching projection cannot authorize FCFS skip or a second Preparing slot', async () => {
  const {owner,student,q} = await setup(); const first = await submitCount(student,q);
  const q2 = await draft(student); await prepare(student,q2); const second = await submitCount(student,q2);
  const skip = writeBatch(owner); progressWrites(skip,owner,second,initialQueue());
  skip.set(countRef(owner),countData('vendor',2,2,true)); await deny(skip.commit());
  const preparing = await advanceCount(owner,first), cursor = (await getDocFromServer(queueRef(owner))).data();
  const parallel = writeBatch(owner); progressWrites(parallel,owner,second,cursor);
  parallel.set(countRef(owner),countData('vendor',2,3,true)); await deny(parallel.commit());
  assert.equal(await count(student),2); await advanceCount(owner,preparing); assert.equal(await count(student),1);
});
test('numeric equality cannot disguise malformed double-valued projection fields as canonical integers', async () => {
  const {owner,student,q} = await setup(); await submitCount(student,q);
  assert.ok(env.projectId.startsWith('demo-s4b-'));
  for (const field of ['schemaVersion','lastTicket','nextTicket','count']) {
    // An emulator-only privileged fixture forces doubleValue=1.0. The JS SDK
    // normally serializes integer-valued JS Numbers as integerValue, so a plain
    // setDoc(...1.0) would NOT test Firestore's cross-numeric equality boundary.
    const response = await fetch(`http://127.0.0.1:8080/v1/projects/${env.projectId}/databases/(default)/documents/stallQueueCounts/vendor?updateMask.fieldPaths=${field}`, {
      method:'PATCH',headers:{Authorization:'Bearer owner','Content-Type':'application/json'},
      body:JSON.stringify({fields:{[field]:{doubleValue:1.0}}}),signal:AbortSignal.timeout(5000),
    });
    assert.equal(response.ok,true,await response.text());
    await deny(getDocFromServer(countRef(student))); await bootstrapCount(owner); assert.equal(await count(student),1);
  }
});
