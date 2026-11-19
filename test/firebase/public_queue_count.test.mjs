import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { before, beforeEach, afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDocFromServer, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';
import { account, vendor, draft, prepare, submit, counterRef, orderRef, requestRef } from './checkout_helpers.mjs';
import { queueRef, progressRef, progressWrites, initialQueue } from './fcfs_helpers.mjs';
import { countRef, countData, bootstrapCount, countPayload, countWrites, submitCount, advanceCount } from './public_queue_count_helpers.mjs';
import { budgetDiagnostic } from './checkout_budget.mjs';
import { boundedOfflineCleanup } from './checkout_transport.mjs';

const integrated = process.env.SMART_CANTEEN_INTEGRATED_RULES === 'true';
const candidate = readFileSync(new URL(integrated
  ? '../../pilot/firestore.stage4-integrated.rules' : '../../pilot/firestore.stage4b.rules', import.meta.url), 'utf8');
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
async function rawProgressAndCount(db, order, queue, summary) {
  const batch = writeBatch(db); progressWrites(batch,db,order,queue);
  batch.set(countRef(db,order.vendorUid),summary); return batch.commit();
}

async function seedVendorWithoutHistory() {
  const db = existingDb('vendor'), now = Timestamp.now();
  await env.withSecurityRulesDisabled(async context => {
    const admin = context.firestore();
    await setDoc(doc(admin,'users','vendor'),{uid:'vendor',fullName:'Synthetic Vendor',
      email:'vendor@example.com',phoneNumber:'0123456789',role:'vendor',createdAt:now,
      stallSetupComplete:true,stallId:'vendor'});
    await setDoc(doc(admin,'stalls','vendor'),{ownerUid:'vendor',name:'Campus Kitchen',
      category:'Malay',preparationMinutes:10,status:'closed',createdAt:now});
    // Model the existing pre-projection listing shape. Updating this stall
    // must publish the new, validated fields atomically.
    await setDoc(doc(admin,'publicStalls','vendor'),{vendorUid:'vendor',name:'Campus Kitchen',
      category:'Malay',preparationMinutes:10,status:'closed',updatedAt:now});
  });
  return db;
}

async function updateStallAndPublicProjection(db, changes) {
  const sourceRef = doc(db,'stalls','vendor'), userRef = doc(db,'users','vendor');
  const statsRef = doc(db,'vendorPreparationStats','vendor');
  const publicRef = doc(db,'publicStalls','vendor');
  await runTransaction(db, async tx => {
    const user = await tx.get(userRef), source = await tx.get(sourceRef);
    const statsSnapshot = await tx.get(statsRef);
    assert.equal(user.data()?.role,'vendor');
    assert.equal(user.data()?.stallSetupComplete,true);
    assert.equal(user.data()?.stallId,'vendor');
    const next = {...source.data(),...changes};
    const stats = statsSnapshot.data();
    const sampleCount = stats?.sampleCount ?? 0;
    const estimate = stats
      ? Math.floor((stats.totalDurationMillis + sampleCount - 1) / sampleCount)
      : next.preparationMinutes * 60000;
    tx.update(sourceRef,{...changes,updatedAt:serverTimestamp()});
    tx.set(publicRef,{vendorUid:'vendor',name:next.name,category:next.category,
      preparationMinutes:next.preparationMinutes,status:next.status,
      estimatedPreparationMillis:estimate,preparationStatsRevision:stats?.revision ?? 0,
      updatedAt:serverTimestamp()});
  });
}

test('Vendor status/settings preserve the public preparation projection and private history', async () => {
  const owner = await seedVendorWithoutHistory();
  const sourceRef = doc(owner,'stalls','vendor'), publicRef = doc(owner,'publicStalls','vendor');
  const historyRef = doc(owner,'vendorPreparationStats','vendor');
  assert.equal((await getDocFromServer(historyRef)).exists(),false);

  for (const status of ['open','closed','open']) {
    await updateStallAndPublicProjection(owner,{status});
    const source = (await getDocFromServer(sourceRef)).data();
    const listing = (await getDocFromServer(publicRef)).data();
    assert.equal(source.status,status);
    assert.equal(listing.status,status);
    assert.equal(listing.estimatedPreparationMillis,600000);
    assert.equal(listing.preparationStatsRevision,0);
  }

  await updateStallAndPublicProjection(owner,{name:'Updated Kitchen',category:'Japanese',preparationMinutes:20});
  let listing = (await getDocFromServer(publicRef)).data();
  assert.equal(listing.name,'Updated Kitchen');
  assert.equal(listing.category,'Japanese');
  assert.equal(listing.estimatedPreparationMillis,1200000);
  assert.equal(listing.preparationStatsRevision,0);

  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(),'vendorPreparationStats','vendor'),{
      schemaVersion:1,vendorUid:'vendor',sampleCount:2,totalDurationMillis:840000,
      revision:2,lastOrderId:'abcdefghijklmnopqrst',updatedAt:Timestamp.now(),
    });
  });
  await updateStallAndPublicProjection(owner,{preparationMinutes:30});
  listing = (await getDocFromServer(publicRef)).data();
  assert.equal(listing.preparationMinutes,30);
  assert.equal(listing.estimatedPreparationMillis,420000);
  assert.equal(listing.preparationStatsRevision,2);

  for (const status of ['closed','open']) {
    await updateStallAndPublicProjection(owner,{status});
    listing = (await getDocFromServer(publicRef)).data();
    assert.equal(listing.status,status);
    assert.equal(listing.estimatedPreparationMillis,420000);
    assert.equal(listing.preparationStatsRevision,2);
  }

  const student = await account(env,'projection-reader','student');
  const visible = await getDocFromServer(doc(student,'publicStalls','vendor'));
  assert.equal(visible.data().estimatedPreparationMillis,420000);
  await deny(getDocFromServer(doc(student,'vendorPreparationStats','vendor')));
  await deny(getDocFromServer(doc(student,'stalls','vendor')));
});

test('no-order Student reads missing as unavailable and verified empty queue as zero', async () => {
  const owner = await vendor(env), student = await account(env, 'newStudent');
  assert.equal((await getDocFromServer(countRef(student))).exists(), false);
  await bootstrapCount(owner); assert.equal(await count(student), 0);
  const data = (await getDocFromServer(countRef(student))).data();
  assert.deepEqual(Object.keys(data).sort(), ['schemaVersion','vendorUid','lastTicket','nextTicket','pendingCount','preparingCount','count','updatedAt'].sort());
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
  await deny(setDoc(countRef(student),countData('vendor',0,1,0)));
  await deny(updateDoc(countRef(student),{count:7,updatedAt:serverTimestamp()}));
  await deny(setDoc(countRef(otherVendor),countData('vendor',0,1,0)));
  await deny(deleteDoc(countRef(owner))); await deny(getDocFromServer(countRef(env.unauthenticatedContext().firestore())));
  await deny(getDocs(collection(student,'stallQueueCounts'))); await deny(getDocs(collection(student,'checkoutCounters')));
});
test('direct order/FCFS forgery cannot bypass count coupling or Student/Vendor boundaries', async () => {
  const {owner,student,q} = await setup(); const order = await submitCount(student,q), wrong = await vendor(env,'wrong');
  await deny(updateDoc(orderRef(student,order.orderId),{status:'Ready',readyAt:serverTimestamp()}));
  await deny(updateDoc(orderRef(wrong,order.orderId),{status:'Preparing',statusRevision:1,statusUpdatedAt:serverTimestamp(),preparingAt:serverTimestamp()}));
  const batch = writeBatch(owner); progressWrites(batch,owner,order,initialQueue()); await deny(batch.commit());
  const invalid = writeBatch(owner); progressWrites(invalid,owner,order,initialQueue());
  invalid.set(countRef(owner),countData('vendor',1,3,1)); await deny(invalid.commit());
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
  const {owner,student,q} = await setup(); const pending = await submitCount(student,q);
  // Seed a valid historical single-slot cursor/order snapshot as existing data;
  // no production migration or history reset is performed by this test.
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore(), at = serverTimestamp();
    const revision = {Pending:0,Preparing:1,Ready:2,Completed:3}[state];
    const fields = {status:state,statusRevision:revision,statusUpdatedAt:at};
    if (state !== 'Pending') fields.preparingAt = at;
    if (['Ready','Completed'].includes(state)) fields.readyAt = at;
    if (state === 'Completed') fields.completedAt = at;
    await updateDoc(orderRef(db,pending.orderId),fields);
    if (state !== 'Pending') await setDoc(queueRef(db),{
      schemaVersion:1,vendorUid:'vendor',nextTicket:2,
      preparingOrderId:state === 'Preparing' ? pending.orderId : null,
      revision:state === 'Preparing' ? 1 : 2,updatedAt:at,
    });
    await deleteDoc(countRef(db));
  });
  await bootstrapCount(existingDb('vendor'));
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
test(integrated ? 'integrated candidate denies partial Food Delete and all Category Delete'
  : 'ordering Stage 4B candidate keeps Food and Category Delete closed', async () => {
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
test('parallel count permits consecutive starts but rejects skipping a Pending ticket', async () => {
  const {owner,student,q} = await setup(); const first = await submitCount(student,q);
  const q2 = await draft(student); await prepare(student,q2); const second = await submitCount(student,q2);
  const q3 = await draft(student); await prepare(student,q3); const third = await submitCount(student,q3);
  await deny(rawProgressAndCount(owner,third,initialQueue(),countData('vendor',3,2,1)));
  const firstPreparing = await advanceCount(owner,first);
  const cursor = (await getDocFromServer(queueRef(owner))).data();
  await deny(rawProgressAndCount(owner,third,cursor,countData('vendor',3,3,2)));
  const secondPreparing = await advanceCount(owner,second);
  assert.equal((await getDocFromServer(queueRef(owner))).data().preparingCount,2);
  assert.equal(await count(student),3);
  const thirdPreparing = await advanceCount(owner,third);
  assert.equal((await getDocFromServer(queueRef(owner))).data().preparingCount,3);
  const firstReady = await advanceCount(owner,firstPreparing);
  assert.equal(await count(student),2);
  await advanceCount(owner,firstReady); await advanceCount(owner,secondPreparing); await advanceCount(owner,thirdPreparing);
  assert.equal(await count(student),0);
});
test('numeric equality cannot disguise malformed double-valued projection fields as canonical integers', async () => {
  const {owner,student,q} = await setup(); await submitCount(student,q);
  assert.ok(env.projectId.startsWith('demo-s4b-'));
  for (const field of ['schemaVersion','lastTicket','nextTicket','pendingCount','preparingCount','count']) {
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
