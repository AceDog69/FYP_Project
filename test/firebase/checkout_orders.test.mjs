import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc, writeBatch,
  serverTimestamp, disableNetwork, enableNetwork, runTransaction } from 'firebase/firestore';
import { account, vendor, draft, prepare, directCheckout, submit, discard, orderRef, requestRef, counterRef, payload, writePayload } from './checkout_helpers.mjs';

const checked=readFileSync(new URL('../../firestore.rules',import.meta.url),'utf8');
const closed='function checkoutWritesEnabled() { return false; }';
assert.equal(checked.split(closed).length,2,'Expected exactly one closed checkout gate');
const candidate=checked.replace(closed,'function checkoutWritesEnabled() { return true; }');
let env;
before(async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
  env=await initializeTestEnvironment({projectId:'demo-smart-canteen',firestore:{host:'127.0.0.1',port:8080,rules:candidate}});
});
beforeEach(async()=>{await env.clearFirestore();});
after(async()=>{
  // Raw emulator evidence only: aggregate coverage is NOT a per-request access
  // count. Preserve it for review; do not invent measured expression totals.
  try {
    const response=await fetch('http://127.0.0.1:8080/emulator/v1/projects/demo-smart-canteen:ruleCoverage');
    if(!response.ok) throw new Error(`HTTP ${response.status}`);
    const report=await response.json();mkdirSync(new URL('./artifacts/',import.meta.url),{recursive:true});
    writeFileSync(new URL('./artifacts/checkout-rule-coverage.json',import.meta.url),JSON.stringify(report,null,2));
    process.stdout.write('Raw Rules coverage saved; exact per-write access/expression counts still need review.\n');
  } catch(error) {process.stdout.write(`Rules coverage unavailable: ${error.message}\n`);}
  await env?.cleanup();
});
async function setup(count=1) {
  const owner=await vendor(env),student=await account(env,'student'),q=await draft(student,'student','vendor',count);
  await prepare(student,q);return {owner,student,q};
}

for(const count of [1,2,3,4]) test(`valid ${count}-item checkout in ${count} distinct categories is atomic and exact`,async()=>{
  const {student,q}=await setup(count);const order=await assertSucceeds(submit(student,'student',q.submissionId));
  assert.equal(order.ticket,1);assert.equal(order.itemCount,count);assert.equal(order.totalSen,q.totalSen);
  assert.equal(order.status,'Pending');assert.equal(order.paymentStatus,'simulated');
  assert.equal((await getDoc(requestRef(student,'student',q.submissionId))).data().state,'confirmed');
  assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);
  assert.equal((await getDocs(collection(student,'orders',q.submissionId,'items'))).size,count-1);
});

test('fifth product, duplicate foods, bad quantity and draft totals are rejected',async()=>{
  await vendor(env);const db=await account(env,'student');
  const fifth=await draft(db,'student','vendor',5);await assertFails(prepare(db,fifth));
  for(const quantity of [0,21,1.5,-1]) {
    const q=await draft(db);q.items[0].quantity=quantity;q.totalSen=q.items[0].priceSen*quantity;
    await assertFails(prepare(db,q));
  }
  const duplicate=await draft(db,'student','vendor',2);duplicate.items[1]={...duplicate.items[0]};
  duplicate.totalSen=duplicate.items[0].priceSen*2;await assertFails(prepare(db,duplicate));
  const total=await draft(db);total.totalSen=1;await assertFails(prepare(db,total));
});

test('stale expected prices/revisions and forged authoritative item snapshots are rejected directly',async()=>{
  const {owner,student,q}=await setup();
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{priceSen:999,revision:2,updatedAt:serverTimestamp()});
  await assertFails(directCheckout(student,q));
  for(const values of [{name:'Forged'},{description:'Forged'},{priceSen:1},{pictureId:'burger'},
    {foodRevision:99},{categoryName:'Forged'},{quantity:21},{subtotalSen:1},{vendorUid:'other'}]) {
    const fresh=await draft(student);await prepare(student,fresh);
    await assertFails(directCheckout(student,fresh,p=>Object.assign(p.header.firstItem,values)));
  }
});

test('forged headers, totals, timestamps, payment, ticket and ownership fail',async()=>{
  const {student,q}=await setup();
  for(const values of [{totalSen:1},{ticket:9},{studentUid:'other'},{vendorUid:'other'},
    {orderId:'forged'},{submissionId:'forged'},{stallName:'Forged'}, {preparationMinutes:999},
    {status:'Ready'},{itemCount:5},{paymentStatus:'paid'},{paymentMethod:'realMoney'},{createdAt:new Date(0)}, {extra:true}]) {
    await assertFails(directCheckout(student,q,p=>Object.assign(p.header,values)));
  }
});

test('malicious prepared drafts cannot turn client-chosen names/prices/revisions into authoritative snapshots',async()=>{
  await vendor(env);const db=await account(env,'student');
  for(const values of [{name:'Forged name'},{description:'Forged description'},{pictureId:'burger'},
    {priceSen:1},{foodRevision:99},{categoryId:'cat1'}]) {
    const q=await draft(db);Object.assign(q.items[0],values);
    q.totalSen=q.items[0].priceSen*q.items[0].quantity;
    await assertSucceeds(prepare(db,q)); // An unconfirmed draft is not authoritative.
    await assertFails(directCheckout(db,q));
  }
});

test('missing request, omitted counter/request/child or forged child cannot create an order',async()=>{
  const {student,q}=await setup(4);
  for(const mutate of [p=>p.omitCounter=true,p=>p.omitRequest=true,p=>p.omitChild=2,
    p=>p.lines[2].priceSen=1,p=>p.lines[3].foodId='food0']) {
    await assertFails(directCheckout(student,q,mutate));
  }
  const absent=await draft(student);await assertFails(directCheckout(student,absent,p=>p.omitRequest=true));
  await assertFails(prepare(student,{...absent,state:'confirmed'}));
});

test('canonical Closed stall, unavailable food and mixed-vendor mutations are rejected',async()=>{
  const {owner,student,q}=await setup();await vendor(env,'other');
  await assertFails(directCheckout(student,q,p=>p.header.vendorUid='other'));
  const close=writeBatch(owner);
  close.update(doc(owner,'stalls','vendor'),{status:'closed',updatedAt:serverTimestamp()});
  close.update(doc(owner,'publicStalls','vendor'),{status:'closed',updatedAt:serverTimestamp()});await close.commit();
  await assertFails(directCheckout(student,q));
  const open=writeBatch(owner);open.update(doc(owner,'stalls','vendor'),{status:'open',updatedAt:serverTimestamp()});
  open.update(doc(owner,'publicStalls','vendor'),{status:'open',updatedAt:serverTimestamp()});await open.commit();
  // Build the malicious request before revoking client food read permission.
  const p=await payload(student,q);
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{available:false,revision:2,updatedAt:serverTimestamp()});
  const b=writeBatch(student);writePayload(b,student,p);await assertFails(b.commit());
});

test('missing, forged and cross-vendor canonical memberships/categories fail closed',async()=>{
  const {student,q}=await setup();const p=await payload(student,q);
  for(const values of [null,{vendorUid:'other',categoryId:'cat0'},{vendorUid:'vendor',categoryId:'cat1'}]) {
    await env.withSecurityRulesDisabled(async c=>{
      const ref=doc(c.firestore(),'stalls','vendor','menuMemberships','food0');
      if(values===null) await deleteDoc(ref);else await setDoc(ref,values);
    });
    const b=writeBatch(student);writePayload(b,student,p);await assertFails(b.commit());
  }
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'stalls','vendor','menuMemberships','food0'),{vendorUid:'vendor',categoryId:'cat0'});
    await deleteDoc(doc(c.firestore(),'stalls','vendor','menuCategories','cat0'));
  });
  const b=writeBatch(student);writePayload(b,student,p);await assertFails(b.commit());
});

test('cross-Student, foreign Vendor and anonymous order/request access is denied',async()=>{
  const {owner,student,q}=await setup(2);await submit(student,'student',q.submissionId);
  const otherStudent=await account(env,'otherStudent'),otherVendor=await vendor(env,'otherVendor');
  const anonymous=env.unauthenticatedContext().firestore();
  for(const db of [otherStudent,otherVendor,anonymous]) {
    await assertFails(getDoc(orderRef(db,q.submissionId)));
    await assertFails(getDoc(doc(db,'orders',q.submissionId,'items','1')));
    await assertFails(getDoc(requestRef(db,'student',q.submissionId)));
    await assertFails(updateDoc(orderRef(db,q.submissionId),{status:'Ready'}));
  }
  await assertSucceeds(getDoc(orderRef(owner,q.submissionId)));
  await assertFails(getDocs(collection(student,'orders')));
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
    const b=writeBatch(db);writePayload(b,db,p);await assertFails(b.commit());
  }
  await submit(student,'student',q.submissionId);
  for(const db of [student,owner]) {
    await assertFails(updateDoc(orderRef(db,q.submissionId),{status:'Ready'}));
    await assertFails(deleteDoc(orderRef(db,q.submissionId)));
    await assertFails(updateDoc(doc(db,'orders',q.submissionId,'items','1'),{priceSen:1}));
    await assertFails(deleteDoc(doc(db,'orders',q.submissionId,'items','1')));
  }
  await assertFails(updateDoc(counterRef(student),{lastTicket:2,updatedAt:serverTimestamp()}));
  await assertFails(deleteDoc(counterRef(student)));
  await assertFails(setDoc(doc(student,'orders',q.submissionId,'items','3'),p.lines[1]));
  await assertFails(updateDoc(requestRef(student,'student',q.submissionId),{state:'pending',updatedAt:serverTimestamp()}));
});

test('same-ID parallel submission and recovery produce exactly one order and ticket',async()=>{
  const {student,q}=await setup();
  const result=await Promise.all([submit(student,'student',q.submissionId),submit(student,'student',q.submissionId)]);
  assert.deepEqual(result.map(o=>o.ticket),[1,1]);
  assert.equal((await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size,1);
  await submit(student,'student',q.submissionId);
  assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);
  assert.equal(await discard(student,q),'confirmed');
});

test('parallel Students receive unique sequential tickets; stalls have independent counters',async()=>{
  await vendor(env);await vendor(env,'other');const students=[];
  for(let i=0;i<4;i++) {const uid=`student${i}`,db=await account(env,uid),q=await draft(db,uid);await prepare(db,q);students.push({uid,db,q});}
  const orders=await Promise.all(students.map(({db,uid,q})=>submit(db,uid,q.submissionId)));
  assert.deepEqual(orders.map(o=>o.ticket).sort((a,b)=>a-b),[1,2,3,4]);
  const q=await draft(students[0].db,'student0','other');await prepare(students[0].db,q);
  assert.equal((await submit(students[0].db,'student0',q.submissionId)).ticket,1);
  assert.equal((await getDoc(counterRef(students[0].db))).data().lastTicket,4);
});

test('discard tombstones prevent delayed preparation; confirm versus discard has one terminal outcome',async()=>{
  const {student,q}=await setup();
  await Promise.allSettled([submit(student,'student',q.submissionId),discard(student,q)]);
  const saved=(await getDoc(requestRef(student,'student',q.submissionId))).data();
  const count=(await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size;
  if(saved.state==='confirmed') {assert.equal(count,1);assert.equal((await getDoc(counterRef(student))).data().lastTicket,1);}
  else {assert.equal(saved.state,'cancelled');assert.equal(count,0);assert.equal((await getDoc(counterRef(student))).exists(),false);}
  const absent=await draft(student);await assertSucceeds(discard(student,absent));
  await assertFails(prepare(student,absent));
  await assert.rejects(submit(student,'student',absent.submissionId),/cancelled/);
});

test('order snapshots survive Vendor menu edits without order writes',async()=>{
  const {owner,student,q}=await setup(2);const before=await submit(student,'student',q.submissionId);
  await updateDoc(doc(owner,'stalls','vendor','menuFoods','food0'),{name:'Renamed',priceSen:999,available:false,revision:2,updatedAt:serverTimestamp()});
  const after=(await getDoc(orderRef(student,q.submissionId))).data();assert.deepEqual(after,before);
  assert.equal(after.firstItem.name,'Food 0');assert.equal(after.firstItem.priceSen,850);
});

test('offline transactions cannot report an order or consume a ticket', {timeout:20000},async()=>{
  const {student,q}=await setup();await disableNetwork(student);
  try {await assert.rejects(runTransaction(student,async tx=>{await tx.get(requestRef(student,'student',q.submissionId));},{maxAttempts:1}));}
  finally {await enableNetwork(student);}
  assert.equal((await getDoc(counterRef(student))).exists(),false);
  assert.equal((await getDocs(query(collection(student,'orders'),where('studentUid','==','student')))).size,0);
});

test('checked-in gate rejects request/order/counter writes and both Vendor delete gates stay closed',async()=>{
  const gated=await initializeTestEnvironment({projectId:'demo-smart-canteen-checkout-gate',firestore:{host:'127.0.0.1',port:8080,rules:checked}});
  try {
    const owner=await vendor(gated),student=await account(gated,'student'),q=await draft(student);
    await assertFails(prepare(student,q));
    await gated.withSecurityRulesDisabled(async c=>{await setDoc(requestRef(c.firestore(),'student',q.submissionId),q);});
    await assertFails(directCheckout(student,q));
    const b=writeBatch(owner);b.delete(doc(owner,'stalls','vendor','menuFoods','food0'));
    b.delete(doc(owner,'stalls','vendor','menuMemberships','food0'));await assertFails(b.commit());
    await assertFails(deleteDoc(doc(owner,'stalls','vendor','menuCategories','cat0')));
  } finally {await gated.clearFirestore();await gated.cleanup();}
});
