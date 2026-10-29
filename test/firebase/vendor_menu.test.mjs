import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp } from 'firebase/firestore';

let env;
const checkedInRules=readFileSync(new URL('../../firestore.rules', import.meta.url),'utf8');
const closedGate='function menuDeletesEnabled() { return false; }';
// These are candidate-rule proofs, not permission to enable the application.
// Fail if the gate changes unexpectedly; test the checked-in closed gate below.
assert.equal(checkedInRules.split(closedGate).length,2,'Expected one closed food-delete gate');
const candidateRules=checkedInRules.replace(closedGate,'function menuDeletesEnabled() { return true; }');
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  env = await initializeTestEnvironment({projectId: 'demo-smart-canteen', firestore: {
    host:'127.0.0.1', port:8080,
    rules:candidateRules,
  }});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); });
const dbFor = (uid,testEnv=env) => testEnv.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
const ref = (db, uid, collection, id) => doc(db,'stalls',uid,collection,id);
async function vendor(uid='vendor',testEnv=env) {
  const db=dbFor(uid,testEnv);
  await setDoc(doc(db,'users',uid),{uid,fullName:'Synthetic Vendor',email:`${uid}@example.com`,
    phoneNumber:'0123456789',role:'vendor',createdAt:serverTimestamp(),stallSetupComplete:false,stallId:null});
  const b=writeBatch(db);
  b.set(doc(db,'stalls',uid),{ownerUid:uid,name:'Synthetic Kitchen',category:'Malay',
    preparationMinutes:15,status:'closed',createdAt:serverTimestamp()});
  b.update(doc(db,'users',uid),{stallSetupComplete:true,stallId:uid}); await b.commit(); return db;
}
function category(db,id='rice',name='Rice',uid='vendor') {
  const b=writeBatch(db);
  b.set(ref(db,uid,'menuCategories',id),{vendorUid:uid,name,nameKey:name.toLowerCase(),revision:1,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  b.set(ref(db,uid,'menuCategoryNames',name.toLowerCase()),{vendorUid:uid,categoryId:id});
  return b.commit();
}
const fields=(uid='vendor',categoryId='rice')=>({vendorUid:uid,name:'Rice Bowl',description:'Fresh rice',
  priceSen:850,categoryId,pictureId:'nasi_lemak',available:true,revision:1,
  createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
function food(db,id='food',categoryId='rice',uid='vendor',override={}) {
  const b=writeBatch(db); b.set(ref(db,uid,'menuFoods',id),{...fields(uid,categoryId),...override});
  b.set(ref(db,uid,'menuMemberships',id),{vendorUid:uid,categoryId}); return b.commit();
}
async function edit(db,id,values) {
  const f=ref(db,'vendor','menuFoods',id), previous=(await getDoc(f)).data();
  const b=writeBatch(db);
  b.update(f,{...values,revision:previous.revision+1,updatedAt:serverTimestamp()});
  b.set(ref(db,'vendor','menuMemberships',id),{vendorUid:'vendor',categoryId:values.categoryId??previous.categoryId});
  return b.commit();
}
function deletePair(db,id='food',uid='vendor') {
  const b=writeBatch(db);
  b.delete(ref(db,uid,'menuFoods',id));
  b.delete(ref(db,uid,'menuMemberships',id));
  return b.commit();
}
// Mirrors the service's optimistic revision contract. Firestore deletes carry
// no request.resource/revision: rules protect integrity, while the transaction
// rejects a stale screen. Direct owning-client paired deletes have no draft.
function deleteAtRevision(db,revision,id='food') {
  return runTransaction(db,async tx=>{
    const f=ref(db,'vendor','menuFoods',id),m=ref(db,'vendor','menuMemberships',id);
    const current=await tx.get(f),membership=await tx.get(m);
    if(!current.exists() || current.data().revision!==revision) throw new Error('Stale menu revision');
    const d=current.data();
    const c=await tx.get(ref(db,'vendor','menuCategories',d.categoryId));
    if(d.vendorUid!=='vendor' || membership.data()?.vendorUid!=='vendor' ||
      membership.data()?.categoryId!==d.categoryId || c.data()?.vendorUid!=='vendor') {
      throw new Error('Invalid menu membership');
    }
    tx.delete(f);tx.delete(m);
  });
}
function editAtRevision(db,revision,values) {
  return runTransaction(db,async tx=>{
    const f=ref(db,'vendor','menuFoods','food'),current=await tx.get(f);
    if(!current.exists() || current.data().revision!==revision) throw new Error('Stale menu revision');
    tx.update(f,{...values,revision:revision+1,updatedAt:serverTimestamp()});
  });
}

test('normal creation, edit, availability and reassignment preserve one active membership',async()=>{
  const db=await vendor();await category(db);await category(db,'drinks','Drinks');await food(db);
  const before=(await getDoc(ref(db,'vendor','menuFoods','food'))).data();
  await assertSucceeds(edit(db,'food',{name:'New Rice',priceSen:901,available:false}));
  assert.equal((await getDoc(ref(db,'vendor','menuMemberships','food'))).data().categoryId,'rice');
  await assertSucceeds(edit(db,'food',{categoryId:'drinks'}));
  const after=(await getDoc(ref(db,'vendor','menuFoods','food'))).data();
  assert.equal(after.categoryId,'drinks');assert.equal(after.available,false);
  assert.equal(after.vendorUid,before.vendorUid);assert.ok(after.createdAt.isEqual(before.createdAt));
  assert.equal((await getDoc(ref(db,'vendor','menuMemberships','food'))).data().categoryId,'drinks');
});

test('category rename keeps ID and requires atomic old/new name reservations',async()=>{
  const db=await vendor();await category(db);
  const c=ref(db,'vendor','menuCategories','rice');
  await assertFails(updateDoc(c,{name:'Bowls',nameKey:'bowls',revision:2,updatedAt:serverTimestamp()}));
  const b=writeBatch(db);b.update(c,{name:'Bowls',nameKey:'bowls',revision:2,updatedAt:serverTimestamp()});
  b.delete(ref(db,'vendor','menuCategoryNames','rice'));
  b.set(ref(db,'vendor','menuCategoryNames','bowls'),{vendorUid:'vendor',categoryId:'rice'});
  await assertSucceeds(b.commit());assert.equal((await getDoc(c)).data().name,'Bowls');
});

test('duplicate category race has one winner; Vendors may reuse names independently',async()=>{
  const db=await vendor();
  const results=await Promise.allSettled([category(db,'a','Rice'),category(db,'b','Rice')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const other=await vendor('other');await assertSucceeds(category(other,'rice','Rice','other'));
});

test('food without membership, nonexistent category and ghost/duplicate references are denied',async()=>{
  const db=await vendor();await category(db);
  await assertFails(setDoc(ref(db,'vendor','menuFoods','missing'),fields()));
  await assertFails(food(db,'bad','not-a-category'));
  await assertFails(setDoc(ref(db,'vendor','menuMemberships','ghost'),{vendorUid:'vendor',categoryId:'rice'}));
  await food(db);
  await assertFails(setDoc(ref(db,'vendor','menuMemberships','duplicate'),{vendorUid:'vendor',categoryId:'rice'}));
  await category(db,'drinks','Drinks');
  await assertFails(updateDoc(ref(db,'vendor','menuMemberships','food'),{categoryId:'drinks'}));
  await assertFails(updateDoc(ref(db,'vendor','menuFoods','food'),{categoryId:'drinks',revision:2,updatedAt:serverTimestamp()}));
});

test('malicious prices, IDs, pictures, fields, ownership, timestamps and stale revisions fail',async()=>{
  const db=await vendor();await category(db);await food(db);
  for(const v of [{priceSen:1.5},{priceSen:0},{priceSen:100001},{pictureId:'https://example.com/a.png'},
    {vendorUid:'other'},{categoryId:'a/b'},{createdAt:serverTimestamp()},{extra:true},{name:'   '}]) {
    await assertFails(edit(db,'food',v));
  }
  await assertFails(updateDoc(ref(db,'vendor','menuFoods','food'),{priceSen:10,updatedAt:serverTimestamp()}));
});

test('Students, other Vendors and unauthenticated clients cannot modify menu',async()=>{
  const db=await vendor();await category(db);await food(db);const other=await vendor('other');
  const student=dbFor('student');await setDoc(doc(student,'users','student'),{uid:'student',fullName:'Synthetic Student',
    email:'student@example.com',phoneNumber:'0123456789',role:'student',createdAt:serverTimestamp(),stallSetupComplete:false,stallId:null});
  for(const client of [other,student,env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(ref(client,'vendor','menuFoods','food')));
    await assertFails(updateDoc(ref(client,'vendor','menuFoods','food'),{priceSen:1,revision:2,updatedAt:serverTimestamp()}));
    await assertFails(deleteDoc(ref(client,'vendor','menuCategories','rice')));
  }
});

test('only an atomic matching food/membership pair can be deleted',async()=>{
  const db=await vendor();await category(db);await food(db);
  const f=ref(db,'vendor','menuFoods','food'),m=ref(db,'vendor','menuMemberships','food');
  await assertFails(deleteDoc(f));await assertFails(deleteDoc(m));
  assert.equal((await getDoc(f)).exists(),true);assert.equal((await getDoc(m)).exists(),true);
  await assertSucceeds(deletePair(db));
  assert.equal((await getDoc(f)).exists(),false);assert.equal((await getDoc(m)).exists(),false);
  await assertFails(deletePair(db)); // Missing before-state cannot authorize a repeat.
});

test('category deletion and reservation cleanup stay blocked, even when empty or unavailable',async()=>{
  const db=await vendor();await category(db);await food(db,'food','rice','vendor',{available:false});
  await assertFails(deleteDoc(ref(db,'vendor','menuCategories','rice')));
  await assertFails(deleteDoc(ref(db,'vendor','menuCategoryNames','rice')));
  const b=writeBatch(db);b.delete(ref(db,'vendor','menuCategories','rice'));
  b.delete(ref(db,'vendor','menuCategoryNames','rice'));await assertFails(b.commit());
  await category(db,'empty','Empty');await assertFails(deleteDoc(ref(db,'vendor','menuCategories','empty')));
  await assertSucceeds(deleteAtRevision(db,1)); // Unavailable foods can be deleted.
  await assertFails(deleteDoc(ref(db,'vendor','menuCategories','rice')));
});

test('foreign Vendors, Students and anonymous clients cannot delete a food pair',async()=>{
  const db=await vendor();await category(db);await food(db);const other=await vendor('other');
  const student=dbFor('student');await setDoc(doc(student,'users','student'),{
    uid:'student',fullName:'Synthetic Student',email:'student@example.com',phoneNumber:'0123456789',
    role:'student',createdAt:serverTimestamp(),stallSetupComplete:false,stallId:null});
  for(const client of [other,student,env.unauthenticatedContext().firestore()]) {
    await assertFails(deletePair(client));
  }
  assert.equal((await getDoc(ref(db,'vendor','menuFoods','food'))).exists(),true);
});

test('orphaned, mismatched and foreign-owned before-states cannot be deleted',async()=>{
  const db=await vendor();await category(db);
  // Deliberately corrupt emulator-only data with admin bypass to prove failure
  // is closed. No migration/repair or production write is performed.
  const cases=[
    [null,{vendorUid:'vendor',categoryId:'rice'}],
    [fields(),null],
    [fields(),{vendorUid:'vendor',categoryId:'drinks'}],
    [fields(),{vendorUid:'other',categoryId:'rice'}],
    [{...fields(),vendorUid:'other'},{vendorUid:'vendor',categoryId:'rice'}],
    [fields(),{vendorUid:'vendor',categoryId:'rice',extra:true}],
  ];
  for(let i=0;i<cases.length;i++) {
    const id=`broken-${i}`,[f,m]=cases[i];
    await env.withSecurityRulesDisabled(async context=>{
      if(f) await setDoc(ref(context.firestore(),'vendor','menuFoods',id),f);
      if(m) await setDoc(ref(context.firestore(),'vendor','menuMemberships',id),m);
    });
    await assertFails(deletePair(db,id));
    if(m) await assertFails(deleteDoc(ref(db,'vendor','menuMemberships',id)));
  }
});

test('deleting one food with another food membership is denied atomically',async()=>{
  const db=await vendor();await category(db);await food(db,'one');await food(db,'two');
  const b=writeBatch(db);b.delete(ref(db,'vendor','menuFoods','one'));
  b.delete(ref(db,'vendor','menuMemberships','two'));await assertFails(b.commit());
  for(const id of ['one','two']) {
    assert.equal((await getDoc(ref(db,'vendor','menuFoods',id))).exists(),true);
    assert.equal((await getDoc(ref(db,'vendor','menuMemberships',id))).exists(),true);
  }
});

test('stale and repeated revision deletes fail; fresh unavailable food delete succeeds',async()=>{
  const db=await vendor();await category(db);await food(db);
  await edit(db,'food',{available:false});
  await assert.rejects(deleteAtRevision(db,1),/Stale menu revision/);
  assert.equal((await getDoc(ref(db,'vendor','menuFoods','food'))).data().revision,2);
  await assertSucceeds(deleteAtRevision(db,2));
  await assert.rejects(deleteAtRevision(db,2),/Stale menu revision/);
});

test('concurrent edit versus delete has exactly one winner at the displayed revision',async()=>{
  const db=await vendor();await category(db);await food(db);
  const results=await Promise.allSettled([
    editAtRevision(db,1,{name:'Concurrent edit'}),deleteAtRevision(db,1),
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const f=await getDoc(ref(db,'vendor','menuFoods','food'));
  const m=await getDoc(ref(db,'vendor','menuMemberships','food'));
  assert.equal(f.exists(),m.exists());
  if(f.exists()) {
    assert.equal(f.data().revision,2);assert.equal(f.data().name,'Concurrent edit');
  }
});

test('simultaneous reassignment versus delete preserves the canonical reference or deletes both',async()=>{
  const db=await vendor();await category(db);await category(db,'drinks','Drinks');await food(db);
  const move=runTransaction(db,async tx=>{
    const f=ref(db,'vendor','menuFoods','food'),s=await tx.get(f);
    if(!s.exists() || s.data().revision!==1) throw new Error('Stale menu revision');
    tx.update(f,{categoryId:'drinks',revision:2,updatedAt:serverTimestamp()});
    tx.set(ref(db,'vendor','menuMemberships','food'),{vendorUid:'vendor',categoryId:'drinks'});
  });
  const results=await Promise.allSettled([move,deleteAtRevision(db,1)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const f=await getDoc(ref(db,'vendor','menuFoods','food'));
  const m=await getDoc(ref(db,'vendor','menuMemberships','food'));
  assert.equal(f.exists(),m.exists());
  if(f.exists()) {assert.equal(f.data().categoryId,'drinks');assert.equal(m.data().categoryId,'drinks');}
});

test('forged category counts, revision, names and timestamps cannot unlock deletion',async()=>{
  const db=await vendor();await category(db);await food(db);
  const c=ref(db,'vendor','menuCategories','rice');
  for(const v of [{foodCount:0},{membershipCount:0},{revision:0},{vendorUid:'other'},
    {nameKey:'forged'},{createdAt:serverTimestamp()},{updatedAt:new Date(0)}]) {
    await assertFails(updateDoc(c,{revision:2,updatedAt:serverTimestamp(),...v}));
  }
  await assertFails(updateDoc(ref(db,'vendor','menuMemberships','food'),{revision:0}));
  await assertFails(deleteDoc(c));
});

test('food deletion never grants writes to order history namespaces',async()=>{
  const db=await vendor();await category(db);await food(db);
  // No order fixture or workflow is created. Reject an attempted history write
  // in the same batch and verify the menu pair survives the failed batch.
  for(const target of [doc(db,'orders','uncreated'),ref(db,'vendor','orders','uncreated')]) {
    const b=writeBatch(db);b.delete(ref(db,'vendor','menuFoods','food'));
    b.delete(ref(db,'vendor','menuMemberships','food'));
    b.set(target,{name:'Forged snapshot',priceSen:1,quantity:1});
    await assertFails(b.commit());
    assert.equal((await getDoc(ref(db,'vendor','menuFoods','food'))).exists(),true);
  }
  await assertSucceeds(deletePair(db));
});

test('food deletion leaves an existing confirmed order snapshot byte-for-byte unchanged',async()=>{
  const db=await vendor();await category(db);await food(db);
  const order=doc(db,'orders','confirmed-history');
  const snapshot={studentUid:'student',vendorUid:'vendor',ticket:7,totalSen:850,
    items:[{foodId:'food',name:'Rice Bowl',priceSen:850,quantity:1}],status:'Completed'};
  await env.withSecurityRulesDisabled(context=>setDoc(doc(context.firestore(),'orders','confirmed-history'),snapshot));
  await assertSucceeds(deleteAtRevision(db,1));
  assert.deepEqual((await getDoc(order)).data(),snapshot);
  assert.equal((await getDoc(ref(db,'vendor','menuFoods','food'))).exists(),false);
  assert.equal((await getDoc(ref(db,'vendor','menuMemberships','food'))).exists(),false);
});

test('creation/reassignment versus category deletion races preserve current deletion gate',async()=>{
  const db=await vendor();await category(db);await category(db,'drinks','Drinks');
  const first=await Promise.allSettled([food(db),deleteDoc(ref(db,'vendor','menuCategories','rice'))]);
  assert.equal(first[0].status,'fulfilled');assert.equal(first[1].status,'rejected');
  const second=await Promise.allSettled([edit(db,'food',{categoryId:'drinks',available:false}),
    deleteDoc(ref(db,'vendor','menuCategories','drinks'))]);
  assert.equal(second[0].status,'fulfilled');assert.equal(second[1].status,'rejected');
  assert.equal((await getDoc(ref(db,'vendor','menuMemberships','food'))).data().categoryId,'drinks');
});

test('checked-in rules keep food and category deletion disabled pending reviewed proof',async()=>{
  const gated=await initializeTestEnvironment({projectId:'demo-smart-canteen-menu-gate',firestore:{
    host:'127.0.0.1',port:8080,rules:checkedInRules,
  }});
  try {
    await gated.clearFirestore();
    const db=await vendor('vendor',gated);await category(db);await food(db);
    await assertFails(deletePair(db));
    await assertFails(deleteDoc(ref(db,'vendor','menuFoods','food')));
    await assertFails(deleteDoc(ref(db,'vendor','menuMemberships','food')));
    await assertFails(deleteDoc(ref(db,'vendor','menuCategories','rice')));
    assert.equal((await getDoc(ref(db,'vendor','menuFoods','food'))).exists(),true);
  } finally {await gated.clearFirestore();await gated.cleanup();}
});
