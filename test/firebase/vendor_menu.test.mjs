import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  env = await initializeTestEnvironment({projectId: 'demo-smart-canteen', firestore: {
    host:'127.0.0.1', port:8080,
    rules:readFileSync(new URL('../../firestore.rules', import.meta.url),'utf8'),
  }});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); });
const dbFor = uid => env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
const ref = (db, uid, collection, id) => doc(db,'stalls',uid,collection,id);
async function vendor(uid='vendor') {
  const db=dbFor(uid);
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

test('destructive safety gate rejects food and membership deletion, including paired writes',async()=>{
  const db=await vendor();await category(db);await food(db);
  const f=ref(db,'vendor','menuFoods','food'),m=ref(db,'vendor','menuMemberships','food');
  await assertFails(deleteDoc(f));await assertFails(deleteDoc(m));
  const b=writeBatch(db);b.delete(f);b.delete(m);await assertFails(b.commit());
  await assertFails(deleteDoc(ref(db,'vendor','menuCategories','rice')));
  await category(db,'empty','Empty');await assertFails(deleteDoc(ref(db,'vendor','menuCategories','empty')));
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
