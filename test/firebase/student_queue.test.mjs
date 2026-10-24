import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { test, before, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDocFromServer, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction,
  serverTimestamp, collection, getDocs, onSnapshot } from 'firebase/firestore';
import { account, vendor, draft, prepare, submit, orderRef } from './checkout_helpers.mjs';
import { queueRef, progressRef, progressData, initialQueue, progressWrites, advance } from './fcfs_helpers.mjs';
import { budgetDiagnostic } from './checkout_budget.mjs';
import { boundedOfflineCleanup } from './checkout_transport.mjs';

const checked=readFileSync(new URL('../../firestore.rules',import.meta.url),'utf8');
const closed='function checkoutWritesEnabled() { return false; }';assert.equal(checked.split(closed).length,2);
const candidate=checked.replace(closed,'function checkoutWritesEnabled() { return true; }');
const runId=randomBytes(5).toString('hex');let env,sequence=0;
before(()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
});
beforeEach(async()=>{
  env=await initializeTestEnvironment({projectId:`demo-sq-${runId}-${++sequence}`,
    firestore:{host:'127.0.0.1',port:8080,rules:candidate}});
});
afterEach(async()=>{
  try {
    const response=await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${env.projectId}:ruleCoverage`,{signal:AbortSignal.timeout(5000)});
    assert.equal(response.ok,true);mkdirSync(new URL('./artifacts/',import.meta.url),{recursive:true});
    writeFileSync(new URL(`./artifacts/student-queue-coverage-${sequence}.json`,import.meta.url),JSON.stringify(await response.json()));
  } finally {await boundedOfflineCleanup(()=>env?.cleanup());}
});
async function deny(operation) {
  const error=await assertFails(operation);assert.equal(error.code,'permission-denied',error.message);
  assert.equal(budgetDiagnostic.test(error.message),false,'Budget exhaustion cannot count as a security denial');
}
async function setup(count=2) {
  const owner=await vendor(env),student=await account(env,'student'),orders=[];
  for(let i=0;i<count;i++) {
    const q=await draft(student,'student','vendor',2);await prepare(student,q);orders.push(await submit(student,'student',q.submissionId));
  }
  return {owner,student,orders};
}
async function bootstrap(db,uid='vendor') {
  await runTransaction(db,async tx=>{
    const cursor=await tx.get(queueRef(db,uid)),projection=await tx.get(progressRef(db,uid));
    if(projection.exists()) return;
    const queue=cursor.data()??{...initialQueue(),updatedAt:serverTimestamp()};
    tx.set(progressRef(db,uid),progressData(uid,queue));
  });
}
const progress=db=>getDocFromServer(progressRef(db)).then(s=>s.data());
const readOrder=(db,order)=>getDocFromServer(orderRef(db,order.orderId)).then(s=>s.data());
async function raw(db,order,queue,mutate=()=>{}) {
  const batch=writeBatch(db);progressWrites(batch,db,order,queue);mutate(batch);return batch.commit();
}

test('own Vendor can publish verified initial no-start progress; absent is distinguishable',async()=>{
  const {owner,student}=await setup(1);
  assert.equal((await getDocFromServer(progressRef(student))).exists(),false);
  await assertSucceeds(bootstrap(owner));const d=await progress(student);
  assert.equal(d.nextTicket,1);assert.equal(d.preparing,false);assert.equal(d.revision,0);
  assert.deepEqual(Object.keys(d).sort(),['schemaVersion','vendorUid','nextTicket','preparing','revision','updatedAt'].sort());
  await assertSucceeds(bootstrap(owner)); // Idempotent read/no write.
});

test('one-time legacy cursor bootstrap mirrors existing authoritative progress without advancing it',async()=>{
  const {owner,student,orders:[first]}=await setup(1);await advance(owner,first);
  // Simulate the accepted Stage 3A data shape before queueProgress existed.
  await env.withSecurityRulesDisabled(c=>deleteDoc(progressRef(c.firestore())));
  const before=(await getDocFromServer(queueRef(owner))).data();
  await assertSucceeds(bootstrap(owner));const d=await progress(student);
  assert.equal(d.nextTicket,before.nextTicket);assert.equal(d.preparing,true);assert.equal(d.revision,before.revision);
  assert.deepEqual(d.updatedAt,before.updatedAt);assert.deepEqual((await getDocFromServer(queueRef(owner))).data(),before);
});

test('every Start/Ready requires the exact sanitized projection atomically; Completed leaves progress unchanged',async()=>{
  const {owner,student,orders:[first,second]}=await setup();
  let order=await advance(owner,first);assert.deepEqual((({nextTicket,preparing,revision})=>({nextTicket,preparing,revision}))(await progress(student)),
    {nextTicket:2,preparing:true,revision:1});
  order=await advance(owner,order);assert.equal((await progress(student)).preparing,false);
  await advance(owner,second);const before=await progress(student);await advance(owner,order);
  assert.deepEqual(await progress(student),before);assert.equal(before.nextTicket,3);assert.equal(before.preparing,true);
});

test('omitted projection cannot create or release the preparation slot',async()=>{
  const {owner,orders:[first]}=await setup(1);
  async function withoutProjection(order,queue) {
    const batch=writeBatch(owner),next=order.status==='Pending'?'Preparing':'Ready';
    batch.update(orderRef(owner,order.orderId),{status:next,statusRevision:(order.statusRevision??0)+1,
      statusUpdatedAt:serverTimestamp(),[next==='Preparing'?'preparingAt':'readyAt']:serverTimestamp()});
    batch.set(queueRef(owner),{schemaVersion:1,vendorUid:'vendor',nextTicket:queue.nextTicket+(next==='Preparing'?1:0),
      preparingOrderId:next==='Preparing'?order.orderId:null,revision:queue.revision+1,updatedAt:serverTimestamp()});
    return batch.commit();
  }
  await deny(withoutProjection(first,initialQueue()));const preparing=await advance(owner,first);
  await deny(withoutProjection(preparing,(await getDocFromServer(queueRef(owner))).data()));
  assert.equal((await readOrder(owner,first)).status,'Preparing');await assertSucceeds(advance(owner,preparing));
});

test('forged initial advancement, preparation, owner, revision and extra identity fields are denied',async()=>{
  const {owner}=await setup(1);
  for(const values of [{nextTicket:2},{preparing:true},{revision:1},{vendorUid:'other'},
    {preparingOrderId:'secret'},{studentUid:'student'},{orderId:'secret'},{extra:true},{updatedAt:new Date(0)}]) {
    await deny(setDoc(progressRef(owner),{schemaVersion:1,vendorUid:'vendor',nextTicket:1,preparing:false,
      revision:0,updatedAt:serverTimestamp(),...values}));
  }
  await assertSucceeds(bootstrap(owner));
});

test('a paired Start cannot publish a forged ticket, false preparation flag, wrong revision/time or private field',async()=>{
  const {owner,orders:[first]}=await setup(1);
  for(const values of [{nextTicket:3},{preparing:false},{revision:2},{vendorUid:'other'},
    {updatedAt:new Date(0)},{preparingOrderId:first.orderId},{studentUid:'student'}]) {
    await deny(raw(owner,first,initialQueue(),b=>b.set(progressRef(owner),{
      schemaVersion:1,vendorUid:'vendor',nextTicket:2,preparing:true,revision:1,updatedAt:serverTimestamp(),...values})));
  }
  await assertSucceeds(advance(owner,first));
});

test('detached updates, decreases, same-revision timestamp refreshes, stale replay and deletion fail',async()=>{
  const {owner,orders:[first]}=await setup(1);await bootstrap(owner);const initial=await progress(owner);
  for(const values of [{nextTicket:2,preparing:true,revision:1},{updatedAt:serverTimestamp()}])
    await deny(updateDoc(progressRef(owner),values));
  const preparing=await advance(owner,first);const old=await progress(owner);await advance(owner,preparing);
  await deny(setDoc(progressRef(owner),old));await deny(setDoc(progressRef(owner),initial));
  await deny(updateDoc(progressRef(owner),{nextTicket:1,revision:0}));await deny(deleteDoc(progressRef(owner)));
});

test('wrong Students, Vendors, unconfigured users and anonymous clients cannot publish or mutate progress',async()=>{
  const {owner,student,orders:[first]}=await setup(1);const other=await vendor(env,'other');
  const unconfigured=await account(env,'unconfigured','vendor'),anonymous=env.unauthenticatedContext().firestore();
  for(const attacker of [student,other,unconfigured,anonymous]) await deny(setDoc(progressRef(attacker),{
    schemaVersion:1,vendorUid:'vendor',nextTicket:1,preparing:false,revision:0,updatedAt:serverTimestamp()}));
  await advance(owner,first);
  for(const attacker of [student,other,unconfigured,anonymous]) await deny(updateDoc(progressRef(attacker),{preparing:false,revision:2,updatedAt:serverTimestamp()}));
});

test('Students read published aggregates but never another Student order, private cursor or source stall',async()=>{
  const {owner,student,orders:[first]}=await setup(1);await advance(owner,first);
  const stranger=await account(env,'stranger');await assertSucceeds(getDocFromServer(progressRef(stranger)));
  await deny(getDocFromServer(orderRef(stranger,first.orderId)));await deny(getDocFromServer(queueRef(student)));
  await deny(getDocFromServer(doc(student,'stalls','vendor')));await deny(getDocs(collection(student,'queueProgress')));
  await deny(getDocFromServer(progressRef(env.unauthenticatedContext().firestore())));
});

test('bootstrap cannot forge an existing private cursor or repair it by trusting client-supplied values',async()=>{
  const {owner,orders:[first]}=await setup(1);await advance(owner,first);
  await env.withSecurityRulesDisabled(c=>deleteDoc(progressRef(c.firestore())));
  for(const values of [{nextTicket:1,preparing:false,revision:0},{nextTicket:3,preparing:false,revision:4},
    {updatedAt:serverTimestamp()}]) {
    const cursor=(await getDocFromServer(queueRef(owner))).data();
    await deny(setDoc(progressRef(owner),{...progressData('vendor',cursor),...values}));
  }
  await assertSucceeds(bootstrap(owner));
});

test('concurrent bootstrap and Start cannot leave an initial or stale projection behind',async()=>{
  const {owner,student,orders:[first]}=await setup(1);const second=env.authenticatedContext('vendor').firestore();
  const results=await Promise.allSettled([bootstrap(owner),advance(second,first)]);
  assert.equal(results[1].status,'fulfilled');
  if(results[0].status==='rejected') {
    assert.equal(results[0].reason.code,'permission-denied');assert.equal(budgetDiagnostic.test(results[0].reason.message),false);
    await bootstrap(owner); // Explicit retry observes the winning projection.
  }
  const d=await progress(student),q=(await getDocFromServer(queueRef(owner))).data();
  assert.equal(d.revision,q.revision);assert.equal(d.nextTicket,2);assert.equal(d.preparing,true);
});

test('parallel Vendors cannot double-start or detach the projection; stale raw replay fails',async()=>{
  const errors=[];
  for(let iteration=1;iteration<=3;iteration++) {
    if(iteration>1) await env.clearFirestore();
    const {owner,student,orders:[first]}=await setup(1);const second=env.authenticatedContext('vendor').firestore();
    const results=await Promise.allSettled([advance(owner,first),advance(second,first)]);
    console.log(`FCFS_CONCURRENCY_DIAGNOSTIC ${JSON.stringify({iteration,results:results.map(result=>result.status==='fulfilled'
      ? {status:result.status,value:result.value}
      : {status:result.status,error:{message:result.reason?.message,code:result.reason?.code,
        name:result.reason?.name,stack:result.reason?.stack}})})}`);
    assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
    const error=results.find(r=>r.status==='rejected').reason;errors.push(error);
    assert.equal(budgetDiagnostic.test(error.message),false);
    const d=await progress(student),q=(await getDocFromServer(queueRef(owner))).data(),order=await readOrder(owner,first);
    assert.equal(order.status,'Preparing');assert.equal(order.statusRevision,1);
    assert.equal(q.revision,1);assert.equal(q.nextTicket,2);assert.equal(q.preparingOrderId,first.orderId);
    assert.equal(d.revision,q.revision);assert.equal(d.nextTicket,q.nextTicket);assert.equal(d.preparing,true);
    await deny(raw(owner,first,initialQueue()));
  }
  assert.ok(errors.every(error=>error.message==='stale-order'||error.code==='permission-denied'),
    `Unexpected parallel transition rejections: ${JSON.stringify(errors.map(error=>({message:error.message,
      code:error.code,name:error.name,stack:error.stack})))}`);
});

test('Ready/start contention converges to exact per-stall progress without skipped Pending tickets',async()=>{
  const {owner,student,orders:[first,second]}=await setup();const preparing=await advance(owner,first);
  const client=env.authenticatedContext('vendor').firestore();
  const results=await Promise.allSettled([advance(owner,preparing),advance(client,second)]);
  assert.equal(results[0].status,'fulfilled');
  if(results[1].status==='rejected') {
    const error=results[1].reason;assert.ok(error.message==='ineligible-order'||error.code==='permission-denied');
    assert.equal(budgetDiagnostic.test(error.message),false);await advance(owner,second);
  }
  const d=await progress(student);assert.equal(d.nextTicket,3);assert.equal(d.preparing,true);assert.equal(d.revision,3);
});

test('multiple stalls retain independent numeric projections and cross-stall publication is rejected',async()=>{
  const {owner,student,orders:[first]}=await setup(1);const other=await vendor(env,'other');
  const q=await draft(student,'student','other',2);await prepare(student,q);const order=await submit(student,'student',q.submissionId,'other');
  const results=await Promise.allSettled([advance(owner,first),advance(other,order)]);assert.ok(results.every(r=>r.status==='fulfilled'));
  await deny(setDoc(progressRef(owner,'other'),{...(await progress(owner)),vendorUid:'other'}));
  assert.equal((await progress(student)).nextTicket,2);
  assert.equal((await getDocFromServer(progressRef(student,'other'))).data().nextTicket,2);
});

test('real-time Student projection is synchronized with server-confirmed cursor states and contains no IDs',async()=>{
  const {owner,student,orders:[first]}=await setup(1);let resolve,reject;
  const done=new Promise((yes,no)=>{resolve=yes;reject=no;});done.catch(()=>{});
  const seen=[],timer=setTimeout(()=>reject(new Error('Queue projection stream timed out')),15000);
  const stop=onSnapshot(progressRef(student),{includeMetadataChanges:true},snapshot=>{
    if(snapshot.metadata.hasPendingWrites||snapshot.metadata.fromCache||!snapshot.exists()) return;
    const d=snapshot.data();seen.push(d.revision);
    if(Object.keys(d).length!==6||'preparingOrderId' in d||'studentUid' in d) {reject(new Error('Private fields exposed'));return;}
    if(d.revision===2) resolve();
  },reject);
  try {await advance(owner,await advance(owner,first));await done;assert.equal(seen.at(-1),2);}
  finally {clearTimeout(timer);stop();}
});
