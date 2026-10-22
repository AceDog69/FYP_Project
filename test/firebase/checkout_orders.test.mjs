import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { test, before, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocFromServer, getDocs, getDocsFromServer, query, where, setDoc, updateDoc, deleteDoc, writeBatch,
  serverTimestamp, disableNetwork } from 'firebase/firestore';
import { account, vendor, draft, prepare, directCheckout, submit, discard, orderRef, requestRef, counterRef, payload, writePayload } from './checkout_helpers.mjs';

import { budgetDiagnostic } from './checkout_budget.mjs';
import { checkoutTransport, expectedOfflineRejection, boundedOfflineCleanup } from './checkout_transport.mjs';

const checked=readFileSync(new URL('../../firestore.rules',import.meta.url),'utf8');
const closed='function checkoutWritesEnabled() { return false; }';
assert.equal(checked.split(closed).length,2,'Expected exactly one closed checkout gate');
const candidate=checked.replace(closed,'function checkoutWritesEnabled() { return true; }');
const runId=randomBytes(5).toString('hex');
let env,sequence=0;
async function deny(operation) {
  const error=await assertFails(operation);
  assert.equal(error.code,'permission-denied',`Expected Rules denial, received ${error.code}: ${error.message}`);
  assert.equal(budgetDiagnostic.test(error.message),false,'Budget exhaustion is not an intended denial');
  return error;
}
async function allSucceeded(operations) {
  const results=await Promise.allSettled(operations); // Drain siblings before reporting a failure.
  const errors=results.filter(r=>r.status==='rejected').map(r=>r.reason);
  if(errors.length) throw new AggregateError(errors,'Parallel checkout failed after every operation settled');
  return results.map(r=>r.value);
}
before(async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
});
beforeEach(async()=>{
  // Separate emulator databases avoid destructive clears while an emulator
  // transaction is releasing locks. Never reuse a failed race's database.
  env=undefined;
  env=await initializeTestEnvironment({projectId:`demo-co-${runId}-${++sequence}`,
    firestore:{host:'127.0.0.1',port:8080,rules:candidate}});
});
afterEach(async()=>{
  // Raw emulator evidence only: aggregate coverage is NOT a per-request access
  // count. Preserve it for review; do not invent measured expression totals.
  try {
    const response=await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${env.projectId}:ruleCoverage`);
    if(!response.ok) throw new Error(`HTTP ${response.status}`);
    const report=await response.json();mkdirSync(new URL('./artifacts/',import.meta.url),{recursive:true});
    writeFileSync(new URL(`./artifacts/checkout-rule-coverage-${sequence}.json`,import.meta.url),JSON.stringify(report,null,2));
    process.stdout.write('Raw Rules coverage saved; exact per-write access/expression counts still need review.\n');
  } catch(error) {process.stdout.write(`Rules coverage unavailable: ${error.message}\n`);}
  await env?.cleanup();
});
async function setup(count=1) {
  const owner=await vendor(env),student=await account(env,'student'),q=await draft(student,'student','vendor',count);
  await prepare(student,q);return {owner,student,q};
}

for(const count of [1,2]) test(`valid ${count}-item checkout in ${count} distinct categories is atomic and exact`,async()=>{
  const {student,q}=await setup(count);const order=await assertSucceeds(submit(student,'student',q.submissionId));
  assert.equal(order.ticket,1);assert.equal(order.itemCount,count);assert.equal(order.totalSen,q.totalSen);
  assert.equal(order.status,'Pending');assert.equal(order.paymentStatus,'simulated');
  assert.equal((await getDoc(requestRef(student,'student',q.submissionId))).data().state,'confirmed');
  assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);
  assert.equal((await getDocs(collection(student,'orders',q.submissionId,'items'))).size,count-1);
  if(count===2) {
    const maximum=await draft(student,'student','vendor',2);
    for(const item of maximum.items) item.quantity=20;
    maximum.totalSen=maximum.items.reduce((sum,item)=>sum+item.priceSen*item.quantity,0);
    await prepare(student,maximum);const receipt=await assertSucceeds(submit(student,'student',maximum.submissionId));
    assert.equal(receipt.totalSen,35100);assert.equal(receipt.ticket,2);
  }
});

for(const count of [3,4,5]) test(`${count} distinct foods are rejected before preparation and cannot consume a ticket`,async()=>{
  await vendor(env);const student=await account(env,'student'),q=await draft(student,'student','vendor',count);
  await deny(prepare(student,q));
  assert.equal((await getDocFromServer(requestRef(student,'student',q.submissionId))).exists(),false);
  await deny(directCheckout(student,q,p=>p.omitRequest=true));
  // A legacy/privileged oversized draft cannot bypass the independent header
  // bound by skipping the now-stricter preparation rule.
  await env.withSecurityRulesDisabled(async context=>{
    await setDoc(requestRef(context.firestore(),'student',q.submissionId),q);
  });
  await deny(directCheckout(student,q));
  assert.equal((await getDocFromServer(requestRef(student,'student',q.submissionId))).data().state,'pending');
  assert.equal((await getDocFromServer(counterRef(student))).exists(),false);
  assert.equal((await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size,0);
});

test('duplicate foods, bad quantity and draft totals are rejected',async()=>{
  await vendor(env);const db=await account(env,'student');
  for(const slot of [0,1]) {
    for(const quantity of [0,21,1.5,-1]) {
      const q=await draft(db,'student','vendor',2);q.items[slot].quantity=quantity;
      q.totalSen=q.items.reduce((sum,item)=>sum+item.priceSen*item.quantity,0);
      await deny(prepare(db,q));
    }
  }
  const duplicate=await draft(db,'student','vendor',2);duplicate.items[1]={...duplicate.items[0]};
  duplicate.totalSen=duplicate.items[0].priceSen*2;await deny(prepare(db,duplicate));
  const total=await draft(db);total.totalSen=1;await deny(prepare(db,total));
});

test('stale expected prices/revisions and forged authoritative item snapshots are rejected directly',async()=>{
  const {owner,student,q}=await setup();
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{priceSen:999,revision:2,updatedAt:serverTimestamp()});
  await deny(directCheckout(student,q));
  for(const values of [{name:'Forged'},{description:'Forged'},{priceSen:1},{pictureId:'burger'},
    {foodRevision:99},{categoryName:'Forged'},{quantity:21},{subtotalSen:1},{vendorUid:'other'}]) {
    const fresh=await draft(student);await prepare(student,fresh);
    await deny(directCheckout(student,fresh,p=>Object.assign(p.header.firstItem,values)));
  }
});

test('forged headers, totals, timestamps, payment, ticket and ownership fail',async()=>{
  const {student,q}=await setup();
  for(const values of [{totalSen:1},{ticket:9},{studentUid:'other'},{vendorUid:'other'},
    {orderId:'forged'},{submissionId:'forged'},{stallName:'Forged'}, {preparationMinutes:999},
    {status:'Ready'},{itemCount:0},{itemCount:3},{itemCount:4},{itemCount:5},{paymentStatus:'paid'},{paymentMethod:'realMoney'},{createdAt:new Date(0)}, {extra:true}]) {
    await deny(directCheckout(student,q,p=>Object.assign(p.header,values)));
  }
});

test('malicious prepared drafts cannot turn client-chosen names/prices/revisions into authoritative snapshots',async()=>{
  await vendor(env);const db=await account(env,'student');
  for(const values of [{name:'Forged name'},{description:'Forged description'},{pictureId:'burger'},
    {priceSen:1},{foodRevision:99},{categoryId:'cat1'}]) {
    const q=await draft(db);Object.assign(q.items[0],values);
    q.totalSen=q.items[0].priceSen*q.items[0].quantity;
    await assertSucceeds(prepare(db,q)); // An unconfirmed draft is not authoritative.
    await deny(directCheckout(db,q));
  }
});

test('missing request, omitted counter/request/child or forged child cannot create an order',async()=>{
  const {student,q}=await setup(2);
  for(const mutate of [p=>p.omitCounter=true,p=>p.omitRequest=true,p=>p.omitChild=1,
    p=>p.lines[1].priceSen=1,p=>p.lines[1].foodId='food0']) {
    await deny(directCheckout(student,q,mutate));
  }
  const absent=await draft(student);await deny(directCheckout(student,absent,p=>p.omitRequest=true));
  await deny(prepare(student,{...absent,state:'confirmed'}));
  // Positive control using exactly the same two-product fixture, not a smaller
  // cart that could accidentally conceal the original budget failure.
  await assertSucceeds(submit(student,'student',q.submissionId));
});

test('two-product snapshots reject every forged slot and missing/extra fields without consuming tickets',async()=>{
  const {student,q}=await setup(2);
  for(let slot=0;slot<2;slot++) {
    for(const values of [{name:'Forged'},{description:'Forged'},{categoryId:'cat4'},
      {categoryName:'Forged'},{pictureId:'burger'},{priceSen:2},{quantity:20},
      {foodRevision:99},{subtotalSen:1},{unapproved:true}]) {
      await deny(directCheckout(student,q,p=>Object.assign(p.lines[slot],values)));
    }
    await deny(directCheckout(student,q,p=>{delete p.lines[slot].description;}));
    await deny(directCheckout(student,q,p=>{delete p.lines[slot].categoryName;}));
  }
  assert.equal((await getDoc(counterRef(student))).exists(),false);
  assert.equal((await getDoc(requestRef(student,'student',q.submissionId))).data().state,'pending');
  assert.equal((await assertSucceeds(submit(student,'student',q.submissionId))).itemCount,2);
});

test('two-product canonical category and membership checks reject corruption at every slot',async()=>{
  const {student,q}=await setup(2);const p=await payload(student,q);
  const commit=()=>{const batch=writeBatch(student);writePayload(batch,student,p);return batch.commit();};
  for(let slot=0;slot<2;slot++) {
    await env.withSecurityRulesDisabled(async context=>{
      const admin=context.firestore(),ref=doc(admin,'stalls','vendor','menuCategories',`cat${slot}`);
      const saved=(await getDoc(ref)).data();
      for(const values of [{vendorUid:'other'},{name:'Forged'},{nameKey:'forged'},
        {revision:0},{createdAt:'forged'},{updatedAt:'forged'}]) {
        await setDoc(ref,{...saved,...values});await deny(commit());
      }
      await deleteDoc(ref);await deny(commit());await setDoc(ref,saved);
      const member=doc(admin,'stalls','vendor','menuMemberships',`food${slot}`);
      for(const values of [{vendorUid:'other',categoryId:`cat${slot}`},
        {vendorUid:'vendor',categoryId:'cat4'}, {vendorUid:'vendor'},
        {vendorUid:'vendor',categoryId:`cat${slot}`,extra:true}]) {
        await setDoc(member,values);await deny(commit());
      }
      await deleteDoc(member);await deny(commit());
      await setDoc(member,{vendorUid:'vendor',categoryId:`cat${slot}`});
    });
  }
  assert.equal((await assertSucceeds(submit(student,'student',q.submissionId))).ticket,1);
});

test('stable-input permission failures are not converted into successful contention recovery',async()=>{
  await vendor(env);const student=await account(env,'student'),q=await draft(student,'student','vendor',2);
  q.items[1].priceSen=1;q.totalSen=q.items.reduce((sum,item)=>sum+item.priceSen*item.quantity,0);
  await prepare(student,q);await deny(submit(student,'student',q.submissionId));
  assert.equal((await getDoc(counterRef(student))).exists(),false);
  assert.equal((await getDoc(requestRef(student,'student',q.submissionId))).data().state,'pending');
  assert.equal((await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size,0);
});

test('child existence implies canonical creation with its header; detached and extra slots are denied',async()=>{
  const {student,q}=await setup(2),p=await payload(student,q);
  for(let slot=1;slot<2;slot++) {
    await deny(setDoc(doc(student,'orders',q.submissionId,'items',`${slot}`),p.lines[slot]));
  }
  // Atomic after-state verification must not depend on the client's write order.
  const batch=writeBatch(student);
  for(let slot=1;slot>=1;slot--) batch.set(doc(student,'orders',q.submissionId,'items',`${slot}`),p.lines[slot]);
  batch.set(counterRef(student),p.counter);
  batch.update(requestRef(student,'student',q.submissionId),{state:'confirmed',updatedAt:serverTimestamp()});
  batch.set(orderRef(student,q.submissionId),p.header);await assertSucceeds(batch.commit());
  for(const slot of ['0','2','3','4','arbitrary']) {
    await deny(setDoc(doc(student,'orders',q.submissionId,'items',slot),p.lines[0]));
  }
});

test('canonical Closed stall, unavailable food and mixed-vendor mutations are rejected',async()=>{
  const {owner,student,q}=await setup();await vendor(env,'other');
  await deny(directCheckout(student,q,p=>p.header.vendorUid='other'));
  const close=writeBatch(owner);
  close.update(doc(owner,'stalls','vendor'),{status:'closed',updatedAt:serverTimestamp()});
  close.update(doc(owner,'publicStalls','vendor'),{status:'closed',updatedAt:serverTimestamp()});await close.commit();
  await deny(directCheckout(student,q));
  const open=writeBatch(owner);open.update(doc(owner,'stalls','vendor'),{status:'open',updatedAt:serverTimestamp()});
  open.update(doc(owner,'publicStalls','vendor'),{status:'open',updatedAt:serverTimestamp()});await open.commit();
  // Build the malicious request before revoking client food read permission.
  const p=await payload(student,q);
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{available:false,revision:2,updatedAt:serverTimestamp()});
  const b=writeBatch(student);writePayload(b,student,p);await deny(b.commit());
});

test('missing, forged and cross-vendor canonical memberships/categories fail closed',async()=>{
  const {student,q}=await setup();const p=await payload(student,q);
  for(const values of [null,{vendorUid:'other',categoryId:'cat0'},{vendorUid:'vendor',categoryId:'cat1'}]) {
    await env.withSecurityRulesDisabled(async c=>{
      const ref=doc(c.firestore(),'stalls','vendor','menuMemberships','food0');
      if(values===null) await deleteDoc(ref);else await setDoc(ref,values);
    });
    const b=writeBatch(student);writePayload(b,student,p);await deny(b.commit());
  }
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'stalls','vendor','menuMemberships','food0'),{vendorUid:'vendor',categoryId:'cat0'});
    await deleteDoc(doc(c.firestore(),'stalls','vendor','menuCategories','cat0'));
  });
  const b=writeBatch(student);writePayload(b,student,p);await deny(b.commit());
});

test('cross-Student, foreign Vendor and anonymous order/request access is denied',async()=>{
  const {owner,student,q}=await setup(2);await submit(student,'student',q.submissionId);
  const otherStudent=await account(env,'otherStudent'),otherVendor=await vendor(env,'otherVendor');
  const anonymous=env.unauthenticatedContext().firestore();
  for(const db of [otherStudent,otherVendor,anonymous]) {
    await deny(getDoc(orderRef(db,q.submissionId)));
    await deny(getDoc(doc(db,'orders',q.submissionId,'items','1')));
    await deny(getDoc(requestRef(db,'student',q.submissionId)));
    await deny(updateDoc(orderRef(db,q.submissionId),{status:'Ready'}));
  }
  await assertSucceeds(getDoc(orderRef(owner,q.submissionId)));
  await deny(getDocs(collection(student,'orders')));
  const own=await assertSucceeds(getDocs(query(collection(student,'orders'),where('studentUid','==','student'))));
  assert.equal(own.size,1);
  const inbox=await assertSucceeds(getDocs(query(collection(owner,'orders'),where('vendorUid','==','vendor'))));
  assert.equal(inbox.size,1);
  const data=(await getDoc(counterRef(student))).data();
  assert.deepEqual(Object.keys(data).sort(),['schemaVersion','vendorUid','lastTicket','lastOrderId','updatedAt'].sort());
});

test('Vendor/anonymous order creation, detached counter increments and immutable mutations fail',async()=>{
  const {owner,student,q}=await setup(2);const p=await payload(student,q);
  for(const db of [owner,env.unauthenticatedContext().firestore()]) {
    const b=writeBatch(db);writePayload(b,db,p);await deny(b.commit());
  }
  await submit(student,'student',q.submissionId);
  for(const db of [student,owner]) {
    await deny(updateDoc(orderRef(db,q.submissionId),{status:'Ready'}));
    await deny(deleteDoc(orderRef(db,q.submissionId)));
    await deny(updateDoc(doc(db,'orders',q.submissionId,'items','1'),{priceSen:1}));
    await deny(deleteDoc(doc(db,'orders',q.submissionId,'items','1')));
  }
  await deny(updateDoc(counterRef(student),{lastTicket:2,updatedAt:serverTimestamp()}));
  await deny(deleteDoc(counterRef(student)));
  await deny(setDoc(doc(student,'orders',q.submissionId,'items','3'),p.lines[1]));
  await deny(updateDoc(requestRef(student,'student',q.submissionId),{state:'pending',updatedAt:serverTimestamp()}));
});

test('same-ID parallel submission and recovery produce exactly one order and ticket',async()=>{
  const {student,q}=await setup(2);
  const result=await allSucceeded([submit(student,'student',q.submissionId),submit(
    env.authenticatedContext('student',{email:'student@example.com'}).firestore(),'student',q.submissionId)]);
  assert.deepEqual(result.map(o=>o.ticket),[1,1]);
  assert.equal((await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size,1);
  await submit(student,'student',q.submissionId);
  assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);
  assert.equal(await discard(student,q),'confirmed');
});

test('parallel Students receive unique sequential tickets; stalls have independent counters',async()=>{
  await vendor(env);await vendor(env,'other');const students=[];
  for(let i=0;i<4;i++) {const uid=`student${i}`,db=await account(env,uid),q=await draft(db,uid,'vendor',2);await prepare(db,q);students.push({uid,db,q});}
  const orders=await allSucceeded(students.map(({db,uid,q})=>submit(db,uid,q.submissionId)));
  assert.deepEqual(orders.map(o=>o.ticket).sort((a,b)=>a-b),[1,2,3,4]);
  const q=await draft(students[0].db,'student0','other');await prepare(students[0].db,q);
  assert.equal((await submit(students[0].db,'student0',q.submissionId,'other')).ticket,1);
  assert.equal((await getDoc(counterRef(students[0].db))).data().lastTicket,4);
});

test('discard tombstones prevent delayed preparation; confirm versus discard has one terminal outcome',async()=>{
  const {student,q}=await setup(2);
  const peer=env.authenticatedContext('student',{email:'student@example.com'}).firestore();
  const [confirmation,discarding]=await Promise.allSettled([submit(student,'student',q.submissionId),discard(peer,q)]);
  assert.equal(discarding.status,'fulfilled',String(discarding.reason));
  const saved=(await getDoc(requestRef(student,'student',q.submissionId))).data();
  const count=(await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size;
  if(saved.state==='confirmed') {
    assert.equal(confirmation.status,'fulfilled',String(confirmation.reason));assert.equal(discarding.value,'confirmed');
    assert.equal(count,1);assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);
  } else {
    assert.equal(saved.state,'cancelled');assert.equal(discarding.value,'cancelled');
    assert.equal(confirmation.status,'rejected');assert.match(confirmation.reason.message,/cancelled/);
    assert.equal(count,0);assert.equal((await getDoc(counterRef(student))).exists(),false);
  }
  const absent=await draft(student);await assertSucceeds(discard(student,absent));
  await deny(prepare(student,absent));
  await assert.rejects(submit(student,'student',absent.submissionId),/cancelled/);
});

test('order snapshots survive Vendor menu edits without order writes',async()=>{
  const {owner,student,q}=await setup(2);const before=await submit(student,'student',q.submissionId);
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{name:'Renamed',priceSen:999,available:false,revision:2,updatedAt:serverTimestamp()});
  const after=(await getDoc(orderRef(student,q.submissionId))).data();assert.deepEqual(after,before);
  assert.equal(after.firstItem.name,'Food 0');assert.equal(after.firstItem.priceSen,850);
});

test('actual offline checkout cannot report an order or consume a ticket', {timeout:120000},async()=>{
  const {student,q}=await setup(2);const transport=await checkoutTransport();let offline;
  let onlineVerified=false,transportCut=false,reportedSuccess=false;
  try {
    const counterBefore=await getDocFromServer(counterRef(student));
    const requestBefore=await getDocFromServer(requestRef(student,'student',q.submissionId));
    offline=await initializeTestEnvironment({projectId:env.projectId,
      firestore:{host:'127.0.0.1',port:transport.port}});
    const db=offline.authenticatedContext('student',{email:'student@example.com'}).firestore();
    await getDocFromServer(requestRef(db,'student',q.submissionId)); // Prove the transport works first.
    assert.ok(transport.stats.forwardedConnections>0&&transport.stats.forwardedBytes>0,
      'Online control must use this transport, not a direct emulator connection');
    onlineVerified=true;
    await disableNetwork(db);transport.cut(); // Real loss of RPC connectivity, including transactions.
    transportCut=true;
    await assert.rejects(async()=>{
      await submit(db,'student',q.submissionId,'vendor',{maxAttempts:1});reportedSuccess=true;
    },error=>expectedOfflineRejection(error,{onlineVerified,transportCut}),
    'Offline checkout requires unavailability or the exact transport-induced RPC cancellation');
    assert.equal(reportedSuccess,false);
    // These use the original, independently connected client, never the cut
    // client or cached query results. Execute before teardown can cancel calls.
    const counterAfter=await getDocFromServer(counterRef(student));
    assert.equal(counterAfter.exists(),counterBefore.exists());
    assert.deepEqual(counterAfter.data(),counterBefore.data());
    assert.equal(counterAfter.exists(),false);
    assert.equal((await getDocsFromServer(query(collection(student,'orders'),where('studentUid','==','student')))).size,0);
    const requestAfter=await getDocFromServer(requestRef(student,'student',q.submissionId));
    assert.equal(requestAfter.data().state,'pending');
    assert.deepEqual(requestAfter.data(),requestBefore.data());
  } finally {
    // Close the already-cut listener first; no queued RPC can reconnect. Each
    // cleanup has a bounded deadline that FAILS the test rather than counting
    // as an expected offline error. Attempt SDK cleanup even if close fails.
    try {await boundedOfflineCleanup(()=>transport.close());}
    finally {await boundedOfflineCleanup(()=>offline?.cleanup());}
  }
});

test('checked-in gate rejects request/order/counter writes and both Vendor delete gates stay closed',async()=>{
  const gated=await initializeTestEnvironment({projectId:`demo-co-gate-${runId}`,firestore:{host:'127.0.0.1',port:8080,rules:checked}});
  try {
    const owner=await vendor(gated),student=await account(gated,'student'),q=await draft(student);
    await deny(prepare(student,q));
    await gated.withSecurityRulesDisabled(async c=>{await setDoc(requestRef(c.firestore(),'student',q.submissionId),q);});
    await deny(directCheckout(student,q));
    const b=writeBatch(owner);b.delete(doc(owner,'stalls','vendor','menuFoods','food0'));
    b.delete(doc(owner,'stalls','vendor','menuMemberships','food0'));await deny(b.commit());
    await deny(deleteDoc(doc(owner,'stalls','vendor','menuCategories','cat0')));
  } finally {await gated.cleanup();}
});
