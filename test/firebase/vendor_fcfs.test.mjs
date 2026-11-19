import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { test, before, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDocFromServer, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp,
  onSnapshot, disableNetwork, Timestamp } from 'firebase/firestore';
import { account, vendor, draft, prepare, submit, orderRef, counterRef, requestRef } from './checkout_helpers.mjs';
import { queueRef, progressRef, progressData, initialQueue, progressWrites, advance,
  preparationStatsRef, recordPreparationSample } from './fcfs_helpers.mjs';
import { checkoutTransport, expectedOfflineRejection, boundedOfflineCleanup } from './checkout_transport.mjs';
import { budgetDiagnostic } from './checkout_budget.mjs';

const checked=readFileSync(new URL('../../firestore.rules',import.meta.url),'utf8');
const closed='function checkoutWritesEnabled() { return false; }';
assert.equal(checked.split(closed).length,2);
const candidate=checked.replace(closed,'function checkoutWritesEnabled() { return true; }');
const runId=randomBytes(5).toString('hex');let env,sequence=0;
before(()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
});
beforeEach(async()=>{
  env=await initializeTestEnvironment({projectId:`demo-fcfs-${runId}-${++sequence}`,
    firestore:{host:'127.0.0.1',port:8080,rules:candidate}});
});
afterEach(async()=>{
  try {
    const response=await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${env.projectId}:ruleCoverage`,{signal:AbortSignal.timeout(5000)});
    assert.equal(response.ok,true);
    mkdirSync(new URL('./artifacts/',import.meta.url),{recursive:true});
    writeFileSync(new URL(`./artifacts/fcfs-rule-coverage-${sequence}.json`,import.meta.url),JSON.stringify(await response.json()));
  } finally {await boundedOfflineCleanup(()=>env?.cleanup());}
});
async function deny(operation) {
  const error=await assertFails(operation);
  assert.equal(error.code,'permission-denied',`Not an intended Rules denial: ${error.code} ${error.message}`);
  assert.equal(budgetDiagnostic.test(error.message),false,'Rules exhaustion is not security proof');
}
async function setup(count=2,foods=2) {
  const owner=await vendor(env),student=await account(env,'student'),orders=[];
  for(let i=0;i<count;i++) {
    const q=await draft(student,'student','vendor',foods);await prepare(student,q);
    orders.push(await assertSucceeds(submit(student,'student',q.submissionId)));
  }
  return {owner,student,orders};
}
const read=(db,order)=>getDocFromServer(orderRef(db,order.orderId)).then(s=>s.data());
async function fixtureReadyAfter(owner,order,durationMillis) {
  const preparing=await read(owner,order),readyAt=Timestamp.fromMillis(preparing.preparingAt.toMillis()+durationMillis);
  await env.withSecurityRulesDisabled(async context=>updateDoc(orderRef(context.firestore(),order.orderId),{
    status:'Ready',statusRevision:2,statusUpdatedAt:readyAt,readyAt,preparationSampleRecorded:false}));
  return read(owner,order);
}
async function raw(db,order,queue,mutate=()=>{}) {
  const batch=writeBatch(db);progressWrites(batch,db,order,queue);mutate(batch);return batch.commit();
}
const queueData=(uid,nextTicket,preparingCount,lastTransitionOrderId,revision)=>({schemaVersion:2,vendorUid:uid,nextTicket,
  preparingCount,lastTransitionOrderId,revision,updatedAt:serverTimestamp()});

test('own Vendor progresses legacy Pending through all four states with exact immutable two-food receipt',async()=>{
  const {owner,student,orders:[pending]}=await setup(1);const id=pending.orderId;
  assert.equal((await getDocFromServer(queueRef(owner))).exists(),false);
  let order=pending;
  for(const [index,status] of ['Preparing','Ready','Completed'].entries()) {
    order=await assertSucceeds(advance(owner,order));assert.equal(order.status,status);assert.equal(order.statusRevision,index+1);
    assert.ok(order.statusUpdatedAt.toMillis()>=order.createdAt.toMillis());
    const immutable={...order};for(const key of ['status','statusRevision','statusUpdatedAt','preparingAt','readyAt','completedAt',
      'preparationEstimateMillis','preparationSampleRecorded']) delete immutable[key];
    const original={...pending};delete original.status;assert.deepEqual(immutable,original);
    assert.equal((await read(student,pending)).status,status);
  }
  assert.ok(order.preparingAt.toMillis()<=order.readyAt.toMillis());assert.ok(order.readyAt.toMillis()<=order.completedAt.toMillis());
  assert.equal((await getDocFromServer(doc(owner,'orders',id,'items','1'))).data().quantity,2);
  assert.equal((await getDocFromServer(counterRef(owner))).data().lastTicket,1);
  assert.equal((await getDocFromServer(requestRef(student,'student',id))).data().state,'confirmed');
});

test('initial allowance falls back, historical average is per stall, and each start keeps its snapshot',async()=>{
  const {owner,student,orders:[first,second,third]}=await setup(3);
  let preparing=await advance(owner,first);
  assert.equal(preparing.preparationEstimateMillis,preparing.preparationMinutes*60000);
  const ready=await fixtureReadyAfter(owner,preparing,6000);await recordPreparationSample(owner,ready);
  const otherOwner=await vendor(env,'other'),otherRequest=await draft(student,'student','other',1);
  await prepare(student,otherRequest);
  const otherFirst=await assertSucceeds(submit(student,'student',otherRequest.submissionId));
  const otherStart=await advance(otherOwner,otherFirst);
  assert.equal(otherStart.preparationEstimateMillis,otherStart.preparationMinutes*60000);
  const otherReady=await fixtureReadyAfter(otherOwner,otherStart,30000);await recordPreparationSample(otherOwner,otherReady);
  const otherNextRequest=await draft(student,'student','other',1);
  await prepare(student,otherNextRequest);
  const otherNext=await assertSucceeds(submit(student,'student',otherNextRequest.submissionId));
  assert.equal((await advance(otherOwner,otherNext)).preparationEstimateMillis,30000);
  let secondStart=await advance(owner,second);assert.equal(secondStart.preparationEstimateMillis,6000);
  let thirdStart=await advance(owner,third);assert.equal(thirdStart.preparationEstimateMillis,6000);
  const secondReady=await fixtureReadyAfter(owner,secondStart,18000);await recordPreparationSample(owner,secondReady);
  const stats=(await getDocFromServer(preparationStatsRef(owner))).data();
  assert.equal(stats.sampleCount,2);assert.equal(stats.totalDurationMillis,24000);
  assert.equal(Math.ceil(stats.totalDurationMillis/stats.sampleCount),12000);
  thirdStart=await read(owner,third);assert.equal(thirdStart.preparationEstimateMillis,6000);
});

test('concurrent Ready samples and duplicate retries increment history exactly once',async()=>{
  const {owner,orders:[first,second]}=await setup(2);
  const firstStart=await advance(owner,first),secondStart=await advance(owner,second);
  const firstReady=await fixtureReadyAfter(owner,firstStart,5000),secondReady=await fixtureReadyAfter(owner,secondStart,7000);
  await Promise.all([recordPreparationSample(owner,firstReady),recordPreparationSample(owner,secondReady),
    recordPreparationSample(owner,firstReady),recordPreparationSample(owner,secondReady)]);
  const stats=(await getDocFromServer(preparationStatsRef(owner))).data();
  assert.equal(stats.sampleCount,2);assert.equal(stats.totalDurationMillis,12000);assert.equal(stats.revision,2);
  assert.equal((await read(owner,first)).preparationSampleRecorded,true);
  assert.equal((await read(owner,second)).preparationSampleRecorded,true);
});

test('parallel Preparing tickets can transition to Ready concurrently without losing queue releases',async()=>{
  const {owner,orders:[first,second]}=await setup(2);
  const firstPreparing=await advance(owner,first),secondPreparing=await advance(owner,second);
  await new Promise(resolve=>setTimeout(resolve,1100));
  const settled=await Promise.allSettled([advance(owner,firstPreparing),advance(owner,secondPreparing)]);
  const failures=settled.filter(result=>result.status==='rejected').map(result=>result.reason);
  assert.equal(failures.length,0,failures.map(error=>`${error.name} ${error.code??''}: ${error.message}`).join('\n'));
  const ready=settled.map(result=>result.value);
  assert.deepEqual(ready.map(order=>order.status),['Ready','Ready']);
  const cursor=(await getDocFromServer(queueRef(owner))).data();
  assert.equal(cursor.nextTicket,3);assert.equal(cursor.preparingCount,0);
  const stats=(await getDocFromServer(preparationStatsRef(owner))).data();
  assert.equal(stats.sampleCount,2);assert.equal(stats.revision,2);
  assert.equal((await read(owner,first)).preparationSampleRecorded,true);
  assert.equal((await read(owner,second)).preparationSampleRecorded,true);
});

test('implausible preparation durations are finalized once but never enter the historical average',async()=>{
  const {owner,orders:[first,second]}=await setup(2);
  const firstStart=await advance(owner,first),secondStart=await advance(owner,second);
  const tooShort=await fixtureReadyAfter(owner,firstStart,500);
  const tooLong=await fixtureReadyAfter(owner,secondStart,12*60*60*1000+1);
  await recordPreparationSample(owner,tooShort);await recordPreparationSample(owner,tooLong);
  assert.equal((await read(owner,first)).preparationSampleRecorded,true);
  assert.equal((await read(owner,second)).preparationSampleRecorded,true);
  assert.equal((await getDocFromServer(preparationStatsRef(owner))).exists(),false);
});

test('historical preparation statistics are private and cannot be client-forged',async()=>{
  const {owner,student,orders:[first]}=await setup(1);
  const preparing=await advance(owner,first),ready=await fixtureReadyAfter(owner,preparing,5000);
  await deny(updateDoc(orderRef(owner,first.orderId),{preparationSampleRecorded:true}));
  await recordPreparationSample(owner,ready);
  const ref=preparationStatsRef(owner),wrong=await vendor(env,'other');
  assert.equal((await getDocFromServer(ref)).data().sampleCount,1);
  await deny(getDocFromServer(preparationStatsRef(student)));
  await deny(getDocFromServer(preparationStatsRef(wrong,'vendor')));
  await deny(getDocs(collection(student,'vendorPreparationStats')));
  await deny(updateDoc(ref,{sampleCount:0,totalDurationMillis:1}));
});

test('direct owning Vendor batch is allowed only for the exact paired transition',async()=>{
  const {owner,orders:[order]}=await setup(1);
  await assertSucceeds(raw(owner,order,initialQueue()));
  assert.equal((await read(owner,order)).status,'Preparing');
});

test('ticket 2 cannot start before ticket 1 even with a forged initial cursor',async()=>{
  const {owner,orders:[first,second]}=await setup();
  await deny(raw(owner,second,initialQueue()));
  await deny(raw(owner,second,{...initialQueue(),nextTicket:2}));
  assert.equal((await read(owner,first)).status,'Pending');
  assert.equal((await getDocFromServer(queueRef(owner))).exists(),false);
  await assertSucceeds(advance(owner,first));
});

test('sequential starts allow parallel preparation and Ready transitions complete out of order',async()=>{
  const {owner,orders:[first,second,third]}=await setup(3);
  const firstPreparing=await advance(owner,first);
  await assert.rejects(advance(owner,third),/ineligible-order/);
  const secondPreparing=await advance(owner,second);
  let cursor=(await getDocFromServer(queueRef(owner))).data();
  assert.equal(cursor.nextTicket,3); assert.equal(cursor.preparingCount,2);
  const secondReady=await advance(owner,secondPreparing); // Ticket 2 may become Ready before ticket 1.
  cursor=(await getDocFromServer(queueRef(owner))).data();
  assert.equal(cursor.preparingCount,1);
  const thirdPreparing=await advance(owner,third);
  assert.equal((await getDocFromServer(queueRef(owner))).data().nextTicket,4);
  const firstReady=await advance(owner,firstPreparing);
  const thirdReady=await advance(owner,thirdPreparing);
  cursor=(await getDocFromServer(queueRef(owner))).data();
  assert.equal(cursor.preparingCount,0);
  await advance(owner,firstReady);
  await advance(owner,secondReady);
  await advance(owner,thirdReady);
  assert.deepEqual((await Promise.all([first,second,third].map(o=>read(owner,o)))).map(o=>o.status),
    ['Completed','Completed','Completed']);
});

test('cursor cannot be pre-created, advanced, cleared, reset or deleted without its actual paired order',async()=>{
  const {owner,orders:[first,second]}=await setup();
  for(const cursor of [queueData('vendor',1,0,first.orderId,1),queueData('vendor',2,0,first.orderId,1),
    queueData('vendor',3,1,second.orderId,1),queueData('vendor',2,1,first.orderId,1)]) await deny(setDoc(queueRef(owner),cursor));
  await advance(owner,first);
  for(const values of [{preparingCount:0},{nextTicket:1},{nextTicket:3},{revision:99},{vendorUid:'other'}])
    await deny(updateDoc(queueRef(owner),{...values,updatedAt:serverTimestamp()}));
  await deny(deleteDoc(queueRef(owner)));
});

test('order-only and cursor-only writes cannot bypass atomic membership of the preparation slot',async()=>{
  const {owner,orders:[first]}=await setup(1);
  await deny(updateDoc(orderRef(owner,first.orderId),{status:'Preparing',statusRevision:1,
    statusUpdatedAt:serverTimestamp(),preparingAt:serverTimestamp()}));
  const preparing=await advance(owner,first);
  await deny(updateDoc(orderRef(owner,first.orderId),{status:'Ready',statusRevision:2,
    statusUpdatedAt:serverTimestamp(),readyAt:serverTimestamp()}));
  await assertSucceeds(advance(owner,preparing));
});

test('Students, wrong Vendors, unconfigured Vendors and anonymous clients cannot process or mutate a cursor',async()=>{
  const {owner,student,orders:[first]}=await setup(1);
  const other=await vendor(env,'other'),unconfigured=await account(env,'unconfigured','vendor');
  const anonymous=env.unauthenticatedContext().firestore();
  for(const attacker of [student,other,unconfigured,anonymous]) {
    await deny(raw(attacker,first,initialQueue()));
    await deny(setDoc(queueRef(attacker),queueData('vendor',2,1,first.orderId,1)));
    await deny(getDocFromServer(queueRef(attacker)));
  }
  let order=await assertSucceeds(advance(owner,first));
  const queue=(await getDocFromServer(queueRef(owner))).data();
  for(const attacker of [student,other,unconfigured,anonymous]) await deny(raw(attacker,order,queue));
  order=await advance(owner,order);
  for(const attacker of [student,other,unconfigured,anonymous]) await deny(raw(attacker,order,queue));
  await assertSucceeds(advance(owner,order));
});

test('invalid transitions, unknown states, missing revisions and forged server times are denied',async()=>{
  const {owner,orders:[first]}=await setup(1);
  for(const status of ['Ready','Completed','Cancelled','Queued','Pending']) {
    await deny(raw(owner,first,initialQueue(),b=>b.update(orderRef(owner,first.orderId),{status})));
  }
  for(const values of [{statusRevision:0},{statusRevision:2},{statusRevision:1.5},
    {statusUpdatedAt:new Date(0)},{preparingAt:new Date(0)},{readyAt:serverTimestamp()},{completedAt:serverTimestamp()}]) {
    await deny(raw(owner,first,initialQueue(),b=>b.update(orderRef(owner,first.orderId),values)));
  }
  for(const fields of [
    {status:'Preparing',statusUpdatedAt:serverTimestamp(),preparingAt:serverTimestamp()},
    {status:'Preparing',statusRevision:1,preparingAt:serverTimestamp()},
    {status:'Preparing',statusRevision:1,statusUpdatedAt:serverTimestamp()},
  ]) {
    const batch=writeBatch(owner);batch.update(orderRef(owner,first.orderId),fields);
    const cursor=queueData('vendor',2,1,first.orderId,1);
    batch.set(queueRef(owner),cursor);batch.set(progressRef(owner),progressData('vendor',cursor));await deny(batch.commit());
  }
  await assertSucceeds(advance(owner,first));
});

test('every immutable header field and item snapshot survives attempted forgery during a legitimate transition',async()=>{
  const {owner,orders:[first]}=await setup(1);
  const attacks=[{studentUid:'vendor'},{vendorUid:'other'},{ticket:2},{createdAt:new Date(0)},
    {firstItem:{...first.firstItem,priceSen:1}},{totalSen:1},{itemCount:1},
    {paymentStatus:'paid'},{paymentMethod:'card'},{stallName:'Forged'},{preparationMinutes:1},
    {preparationEstimateMillis:1000},{preparationSampleRecorded:true},
    {schemaVersion:2},{orderId:'forged'},{submissionId:'forged'},{extra:true}];
  for(const values of attacks) await deny(raw(owner,first,initialQueue(),b=>b.update(orderRef(owner,first.orderId),values)));
  await deny(raw(owner,first,initialQueue(),b=>b.update(doc(owner,'orders',first.orderId,'items','1'),{quantity:20})));
  await deny(deleteDoc(orderRef(owner,first.orderId)));await deny(deleteDoc(doc(owner,'orders',first.orderId,'items','1')));
  await assertSucceeds(advance(owner,first));
});

test('transition timestamps and revision remain immutable on subsequent transitions',async()=>{
  const {owner,orders:[first]}=await setup(1);const preparing=await advance(owner,first);
  const queue=(await getDocFromServer(queueRef(owner))).data();
  await deny(raw(owner,preparing,queue,b=>b.update(orderRef(owner,first.orderId),{preparingAt:new Date(0)})));
  const ready=await advance(owner,preparing);
  await deny(raw(owner,ready,queue,b=>b.update(orderRef(owner,first.orderId),{readyAt:new Date(0)})));
  const completed=await advance(owner,ready);
  await deny(updateDoc(orderRef(owner,first.orderId),{status:'Pending',statusRevision:0,statusUpdatedAt:serverTimestamp()}));
  await assert.rejects(advance(owner,completed),/ineligible-order/);
});

test('forged cursor revision, extra fields, skipped ticket and mismatched order ID fail in paired writes',async()=>{
  const {owner,orders:[first,second]}=await setup();
  for(const values of [{nextTicket:3},{revision:2},{preparingCount:2},
    {vendorUid:'other'},{updatedAt:new Date(0)},{extra:true}]) {
    await deny(raw(owner,first,initialQueue(),b=>b.set(queueRef(owner),{...queueData('vendor',2,1,first.orderId,1),...values})));
  }
  await assertSucceeds(advance(owner,first));
});

test('one atomic batch cannot pair two status transitions with a single cursor update',async()=>{
  const {owner,orders:[first,second]}=await setup();
  await deny(raw(owner,first,initialQueue(),b=>progressWrites(b,owner,second,initialQueue())));
  const preparing=await advance(owner,first),queue=(await getDocFromServer(queueRef(owner))).data();
  await deny(raw(owner,preparing,queue,b=>progressWrites(b,owner,second,queue)));
  await assertSucceeds(advance(owner,preparing));await assertSucceeds(advance(owner,second));
});

test('parallel attempts to start the same ticket yield one transition and reject stale replays',async()=>{
  const {owner,orders:[first]}=await setup(1);
  const secondClient=env.authenticatedContext('vendor').firestore();
  const results=await Promise.allSettled([advance(owner,first),advance(secondClient,first)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const error=results.find(r=>r.status==='rejected').reason;
  assert.ok(error.message==='stale-order'||error.code==='permission-denied');
  assert.equal(budgetDiagnostic.test(error.message),false);
  assert.equal((await read(owner,first)).statusRevision,1);
  assert.equal((await getDocFromServer(queueRef(owner))).data().revision,1);
  await assert.rejects(advance(owner,first),/stale-order/);
  await deny(raw(owner,first,initialQueue())); // Raw replay must fail at Rules too.
});

test('concurrent direct starts of different tickets cannot skip or create two Preparing orders',async()=>{
  const {owner,orders:[first,second]}=await setup();
  const secondClient=env.authenticatedContext('vendor').firestore();
  const results=await Promise.allSettled([raw(owner,first,initialQueue()),raw(secondClient,second,initialQueue())]);
  assert.equal(results[0].status,'fulfilled');assert.equal(results[1].status,'rejected');
  assert.equal(results[1].reason.code,'permission-denied');assert.equal(budgetDiagnostic.test(results[1].reason.message),false);
  assert.equal((await read(owner,first)).status,'Preparing');assert.equal((await read(owner,second)).status,'Pending');
});

test('Ready/start race leaves a valid slot and a safe explicit retry for ticket 2',async()=>{
  const {owner,orders:[first,second]}=await setup();const preparing=await advance(owner,first);
  const secondClient=env.authenticatedContext('vendor').firestore();
  const results=await Promise.allSettled([advance(owner,preparing),advance(secondClient,second)]);
  const rejected=results.filter(r=>r.status==='rejected');
  assert.ok(rejected.length<=1, 'The queue serialized both competing transitions');
  for(const result of rejected) {
    assert.ok(result.reason.message==='stale-order'||result.reason.code==='permission-denied',
      JSON.stringify({message:result.reason.message,code:result.reason.code,name:result.reason.name,stack:result.reason.stack}));
    assert.equal(budgetDiagnostic.test(result.reason.message),false);
  }
  let firstNow=await read(owner,first),secondNow=await read(owner,second);
  if(firstNow.status==='Preparing') firstNow=await advance(owner,firstNow);
  if(secondNow.status==='Pending') secondNow=await advance(secondClient,secondNow);
  assert.equal(firstNow.status,'Ready');assert.equal(secondNow.status,'Preparing');
  assert.equal((await getDocFromServer(queueRef(owner))).data().nextTicket,3);
  assert.equal((await getDocFromServer(queueRef(owner))).data().preparingCount,1);
});

test('stalls have independent FCFS cursors and cross-stall pairing is rejected',async()=>{
  const {owner,student,orders:[first]}=await setup(1);const other=await vendor(env,'other');
  const q=await draft(student,'student','other',1);await prepare(student,q);const second=await submit(student,'student',q.submissionId,'other');
  await deny(raw(owner,first,initialQueue(),b=>b.set(queueRef(owner),queueData('vendor',2,1,second.orderId,1))));
  const results=await Promise.allSettled([advance(owner,first),advance(other,second)]);
  assert.ok(results.every(r=>r.status==='fulfilled'));
  assert.equal((await getDocFromServer(queueRef(owner))).data().preparingCount,1);
  assert.equal((await getDocFromServer(queueRef(other,'other'))).data().preparingCount,1);
});

test('new checkout and processing serialize independently without changing ticket allocation or same-ID recovery',async()=>{
  const {owner,student,orders:[first]}=await setup(1);
  const q=await draft(student);await prepare(student,q);
  const results=await Promise.allSettled([advance(owner,first),submit(student,'student',q.submissionId)]);
  assert.ok(results.every(r=>r.status==='fulfilled'));
  assert.equal(results[1].value.ticket,2);assert.equal(results[0].value.ticket,1);
  const recovered=await submit(student,'student',first.orderId);assert.equal(recovered.status,'Preparing');assert.equal(recovered.ticket,1);
  assert.equal((await getDocFromServer(counterRef(owner))).data().lastTicket,2);
});

test('Student live listener receives confirmed progression and immutable totals',async()=>{
  const {owner,student,orders:[first]}=await setup(1);const seen=[];let resolve,reject;
  const finished=new Promise((yes,no)=>{resolve=yes;reject=no;});
  finished.catch(()=>{});
  const timer=setTimeout(()=>reject(new Error('Student status stream timed out')),15000);
  const stop=onSnapshot(orderRef(student,first.orderId),{includeMetadataChanges:true},s=>{
    if(s.metadata.fromCache||s.metadata.hasPendingWrites) return;
    const order=s.data();seen.push(order.status);
    if(order.totalSen!==first.totalSen) {reject(new Error('Live total changed'));return;}
    if(order.status==='Completed') resolve();
  },reject);
  try {
    let order=first;for(let i=0;i<3;i++) order=await advance(owner,order);
    await finished;assert.equal(seen.at(-1),'Completed');
  } finally {clearTimeout(timer);stop();}
});

test('offline processing rejects without claiming a slot or reporting a successful transition', {timeout:120000},async()=>{
  const {owner,orders:[first]}=await setup(1);
  const transport=await checkoutTransport();let offline;
  let onlineVerified=false,transportCut=false,success=false;
  try {
    offline=await initializeTestEnvironment({projectId:env.projectId,
      firestore:{host:'127.0.0.1',port:transport.port}});
    const disconnected=offline.authenticatedContext('vendor').firestore();
    assert.equal((await read(disconnected,first)).status,'Pending');
    assert.ok(transport.stats.forwardedConnections>0&&transport.stats.forwardedBytes>0);
    onlineVerified=true;await disableNetwork(disconnected);transport.cut();transportCut=true;
    await assert.rejects(async()=>{await advance(disconnected,first,{maxAttempts:1});success=true;},
      error=>expectedOfflineRejection(error,{onlineVerified,transportCut}));
    // The original connected client verifies server state BEFORE teardown. A
    // timeout, permission error or arbitrary cancellation never passes here.
    assert.equal(success,false);assert.equal((await read(owner,first)).status,'Pending');
    assert.equal((await getDocFromServer(queueRef(owner))).exists(),false);
    assert.equal((await getDocFromServer(counterRef(owner))).data().lastTicket,1);
  } finally {
    try {await boundedOfflineCleanup(()=>transport.close());}
    finally {await boundedOfflineCleanup(()=>offline?.cleanup());}
  }
});
