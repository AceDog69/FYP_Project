import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc,
  writeBatch, serverTimestamp } from 'firebase/firestore';

let env;
before(async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
  env=await initializeTestEnvironment({projectId:'demo-smart-canteen',firestore:{host:'127.0.0.1',port:8080,
    rules:readFileSync(new URL('../../firestore.rules',import.meta.url),'utf8')}});
});
beforeEach(async()=>{await env.clearFirestore();});
after(async()=>{await env?.cleanup();});
const ref=(db,uid,c,id)=>doc(db,'stalls',uid,c,id);
async function account(uid,role) {
  const db=env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
  await setDoc(doc(db,'users',uid),{uid,fullName:'Synthetic Account',email:`${uid}@example.com`,
    phoneNumber:'0123456789',role,createdAt:serverTimestamp(),stallSetupComplete:false,stallId:null});
  return db;
}
async function vendor(uid='vendor') {
  const db=await account(uid,'vendor'),b=writeBatch(db);
  b.set(doc(db,'stalls',uid),{ownerUid:uid,name:'Rice Kitchen',category:'Malay',
    preparationMinutes:15,status:'open',createdAt:serverTimestamp()});
  b.update(doc(db,'users',uid),{stallSetupComplete:true,stallId:uid});await b.commit();return db;
}
const listing=(uid='vendor',values={})=>({vendorUid:uid,name:'Rice Kitchen',category:'Malay',
  preparationMinutes:15,status:'open',updatedAt:serverTimestamp(),...values});
async function publish(db,uid='vendor',values={}) {
  await setDoc(doc(db,'publicStalls',uid),listing(uid,values));
}
async function menu(db) {
  const b=writeBatch(db);
  b.set(ref(db,'vendor','menuCategories','rice'),{vendorUid:'vendor',name:'Rice',nameKey:'rice',
    revision:1,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  b.set(ref(db,'vendor','menuCategoryNames','rice'),{vendorUid:'vendor',categoryId:'rice'});
  await b.commit();
  for(const [id,available] of [['visible',true],['hidden',false]]) {
    const f=writeBatch(db);
    f.set(ref(db,'vendor','menuFoods',id),{vendorUid:'vendor',name:'Rice Bowl',description:'Fresh rice',
      priceSen:850,categoryId:'rice',pictureId:'nasi_lemak',available,revision:1,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    f.set(ref(db,'vendor','menuMemberships',id),{vendorUid:'vendor',categoryId:'rice'});await f.commit();
  }
}

test('only public listing and constrained available-food queries are readable by Students',async()=>{
  const owner=await vendor();await publish(owner);await menu(owner);const student=await account('student','student');
  const listings=await assertSucceeds(getDocs(collection(student,'publicStalls')));
  assert.equal(listings.size,1);assert.equal(listings.docs[0].data().name,'Rice Kitchen');
  await assertSucceeds(getDocs(collection(student,'stalls','vendor','menuCategories')));
  const foods=await assertSucceeds(getDocs(query(collection(student,'stalls','vendor','menuFoods'),where('available','==',true))));
  assert.deepEqual(foods.docs.map(d=>d.id),['visible']);
  await assertSucceeds(getDoc(ref(student,'vendor','menuFoods','visible')));
  await assertFails(getDoc(ref(student,'vendor','menuFoods','hidden')));
  await assertFails(getDocs(collection(student,'stalls','vendor','menuFoods')));
  await assertFails(getDocs(query(collection(student,'stalls','vendor','menuFoods'),where('available','==',false))));
});

test('private users, raw stalls, memberships and name reservations stay private',async()=>{
  const owner=await vendor();await publish(owner);await menu(owner);const student=await account('student','student');
  await env.withSecurityRulesDisabled(async c=>{
    await updateDoc(doc(c.firestore(),'stalls','vendor'),{protectedLegacyField:'synthetic-private'});
  });
  for(const target of [doc(student,'users','vendor'),doc(student,'stalls','vendor'),
    ref(student,'vendor','menuMemberships','visible'),ref(student,'vendor','menuCategoryNames','rice')]) {
    await assertFails(getDoc(target));
  }
  await assertFails(getDocs(collection(student,'users')));await assertFails(getDocs(collection(student,'stalls')));
  const data=(await getDoc(doc(student,'publicStalls','vendor'))).data();
  assert.deepEqual(Object.keys(data).sort(),['vendorUid','name','category','preparationMinutes','status','updatedAt'].sort());
});

test('Students, foreign Vendors, anonymous and unconfigured accounts cannot publish or edit listings',async()=>{
  const owner=await vendor();await publish(owner);const other=await vendor('other');
  const student=await account('student','student'),incomplete=await account('incomplete','vendor');
  for(const db of [other,student,incomplete,env.unauthenticatedContext().firestore()]) {
    await assertFails(publish(db));await assertFails(deleteDoc(doc(db,'publicStalls','vendor')));
  }
  await assertFails(publish(incomplete,'incomplete'));
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),'publicStalls')));
  await assertFails(getDoc(doc(other,'publicStalls','vendor')));
});

test('owner publication cannot forge fields, leak source extras or publish a missing stall',async()=>{
  const owner=await vendor();
  for(const values of [{vendorUid:'other'},{name:'Invented'},{category:'Western'},{preparationMinutes:1},
    {status:'closed'},{pictureId:'sushi'},{email:'synthetic@example.com'},{protectedLegacyField:'leak'},
    {ownerUid:'vendor'},{updatedAt:new Date(0)}]) {
    await assertFails(publish(owner,'vendor',values));
  }
  await assertSucceeds(publish(owner));
  await assertFails(deleteDoc(doc(owner,'publicStalls','vendor')));
});

test('published status/settings changes require an atomic matching listing update',async()=>{
  const owner=await vendor();await publish(owner);const student=await account('student','student');
  await assertFails(updateDoc(doc(owner,'stalls','vendor'),{status:'closed',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(owner,'publicStalls','vendor'),{status:'closed',updatedAt:serverTimestamp()}));
  const b=writeBatch(owner);
  b.update(doc(owner,'stalls','vendor'),{name:'New Kitchen',status:'closed',pictureId:'sushi',updatedAt:serverTimestamp()});
  b.set(doc(owner,'publicStalls','vendor'),listing('vendor',{name:'New Kitchen',status:'closed',pictureId:'sushi'}));
  await assertSucceeds(b.commit());
  const data=(await getDoc(doc(student,'publicStalls','vendor'))).data();
  assert.equal(data.status,'closed');assert.equal(data.name,'New Kitchen');assert.equal(data.pictureId,'sushi');
});

test('unpublished existing stalls stay private until owner safely publishes; no backfill privilege',async()=>{
  const owner=await vendor();await menu(owner);const student=await account('student','student');
  await assertFails(getDoc(ref(student,'vendor','menuFoods','visible')));
  assert.equal((await getDocs(collection(student,'publicStalls'))).size,0);
  await assertFails(publish(student));await publish(owner);
  await assertSucceeds(getDoc(ref(student,'vendor','menuFoods','visible')));
});

test('Student writes to every menu collection and vendor source remain denied',async()=>{
  const owner=await vendor();await publish(owner);await menu(owner);const student=await account('student','student');
  await assertFails(updateDoc(doc(student,'stalls','vendor'),{status:'closed',updatedAt:serverTimestamp()}));
  for(const [c,id] of [['menuCategories','rice'],['menuFoods','visible'],['menuMemberships','visible'],['menuCategoryNames','rice']]) {
    await assertFails(updateDoc(ref(student,'vendor',c,id),{vendorUid:'student'}));
    await assertFails(deleteDoc(ref(student,'vendor',c,id)));
    await assertFails(setDoc(ref(student,'vendor',c,'forged'),{vendorUid:'student'}));
  }
});

test('availability revocation and both owner deletion gates remain enforced after publication',async()=>{
  const owner=await vendor();await publish(owner);await menu(owner);const student=await account('student','student');
  await updateDoc(ref(owner,'vendor','menuFoods','visible'),{available:false,revision:2,updatedAt:serverTimestamp()});
  assert.equal((await getDocs(query(collection(student,'stalls','vendor','menuFoods'),where('available','==',true)))).size,0);
  await assertFails(getDoc(ref(student,'vendor','menuFoods','visible')));
  const b=writeBatch(owner);b.delete(ref(owner,'vendor','menuFoods','visible'));
  b.delete(ref(owner,'vendor','menuMemberships','visible'));await assertFails(b.commit());
  await assertFails(deleteDoc(ref(owner,'vendor','menuCategories','rice')));
});
