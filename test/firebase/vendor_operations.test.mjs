import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection,
  writeBatch, serverTimestamp, Timestamp, deleteField } from 'firebase/firestore';

let env;
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  env = await initializeTestEnvironment({projectId: 'demo-smart-canteen', firestore: {
    host: '127.0.0.1', port: 8080,
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  }});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); });
const dbFor = uid => env.authenticatedContext(uid, {email: `${uid}@example.com`}).firestore();
async function account(uid, role = 'vendor') {
  const db = dbFor(uid);
  await setDoc(doc(db, 'users', uid), {uid, fullName: 'Synthetic Vendor',
    email: `${uid}@example.com`, phoneNumber: '0123456789', role,
    createdAt: serverTimestamp(), stallSetupComplete: false, stallId: null});
  return db;
}
async function vendor(uid = 'vendor') {
  const db = await account(uid), batch = writeBatch(db);
  batch.set(doc(db, 'stalls', uid), {ownerUid: uid, name: 'Synthetic Kitchen',
    category: 'Malay', preparationMinutes: 15, status: 'closed', createdAt: serverTimestamp()});
  batch.update(doc(db, 'users', uid), {stallSetupComplete: true, stallId: uid});
  await batch.commit();
  return db;
}
const change = (db, uid, values) => updateDoc(doc(db, 'stalls', uid), {
  ...values, updatedAt: serverTimestamp(),
});

test('owner can open and close stall without a picture ID or data migration', async () => {
  const db = await vendor(), ref = doc(db, 'stalls', 'vendor');
  const before = (await getDoc(ref)).data();
  for (const status of ['open', 'closed']) {
    await assertSucceeds(change(db, 'vendor', {status}));
    const data = (await getDoc(ref)).data();
    assert.equal(data.status, status);
    assert.equal(data.ownerUid, before.ownerUid);
    assert.ok(data.createdAt.isEqual(before.createdAt));
    assert.ok(data.updatedAt instanceof Timestamp);
    assert.equal('pictureId' in data, false);
  }
});

test('settings permit seven exact categories, preparation bounds and 23 picture IDs', async () => {
  const db = await vendor();
  for (const category of ['Malay','Western','Chinese','Japanese','Korean','Beverage','Dessert']) {
    await assertSucceeds(change(db, 'vendor', {name: 'Updated Kitchen', category, preparationMinutes: 1}));
  }
  const ids = ['bento','bibimbap','burger','cake','chinese_food_1','chinese_food_2',
    'chinese_food_3','chinese_food_4','coffee','dessert','drink','fruit_juice','icecream',
    'japanese_1','japanese_curry','korean_ramen','malay_drinks','malay_food','nasi_lemak',
    'sushi','teh_ais','tteokbokki','western_food'];
  for (const pictureId of ids) {
    await assertSucceeds(change(db, 'vendor', {pictureId, preparationMinutes: 180}));
    assert.equal((await getDoc(doc(db, 'stalls', 'vendor'))).data().pictureId, pictureId);
  }
});

test('invalid fields, categories, prep times, picture IDs and timestamps are rejected', async () => {
  const db = await vendor(), ref = doc(db, 'stalls', 'vendor');
  const before = (await getDoc(ref)).data();
  for (const values of [
    {name: ''}, {name: '   '}, {name: 'x'.repeat(101)}, {name: 12},
    {category: 'Other'}, {category: 'All'}, {category: 'malay'}, {category: 'Malay '}, {category: null},
    {preparationMinutes: 0}, {preparationMinutes: 181}, {preparationMinutes: 1.5},
    {status: 'busy'}, {status: true}, {pictureId: 'unknown'}, {pictureId: null},
    {pictureId: 'https://example.com/image.png'}, {pictureId: 'assets/predefined_pictures/Bento.png'},
    {ownerUid: 'other'}, {createdAt: serverTimestamp()}, {admin: true},
    {name: deleteField()},
  ]) { await assertFails(change(db, 'vendor', values)); }
  await assertFails(updateDoc(ref, {name: 'Missing timestamp'}));
  await assertFails(updateDoc(ref, {status: 'open', updatedAt: Timestamp.fromMillis(1)}));
  await assertFails(updateDoc(ref, {updatedAt: deleteField()}));
  assert.deepEqual((await getDoc(ref)).data(), before);
  await assertFails(deleteDoc(ref));
});

test('cross-Vendor, Student and unauthenticated writes are denied', async () => {
  await vendor('owner');
  const other = await vendor('other'), student = await account('student', 'student');
  for (const db of [other, student, env.unauthenticatedContext().firestore()]) {
    await assertFails(change(db, 'owner', {status: 'open'}));
    await assertFails(change(db, 'owner', {name: 'Hijacked', pictureId: 'sushi'}));
  }
  // No catalog read expansion is introduced in this milestone.
  await assertFails(getDoc(doc(student, 'stalls', 'owner')));
  await assertFails(getDoc(doc(other, 'stalls', 'owner')));
  await assertFails(getDocs(collection(student, 'stalls')));
});

test('profile name/phone permissions and immutable user/stall association remain', async () => {
  const db = await vendor(), ref = doc(db, 'users', 'vendor');
  await assertSucceeds(updateDoc(ref, {fullName: 'Updated Vendor', phoneNumber: '987654321'}));
  for (const values of [{role: 'student'}, {email: 'other@example.com'},
    {stallSetupComplete: false, stallId: null}, {stallId: 'other'}]) {
    await assertFails(updateDoc(ref, values));
  }
});

test('unconfigured vendors cannot update stalls and protected legacy fields stay unchanged', async () => {
  const unconfigured = await account('incomplete');
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'stalls', 'incomplete'), {
      ownerUid: 'incomplete', name: 'Legacy Kitchen', category: 'Malay',
      preparationMinutes: 15, status: 'closed', createdAt: Timestamp.now(),
    });
  });
  await assertFails(change(unconfigured, 'incomplete', {status: 'open'}));
  const db = await vendor();
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'stalls', 'vendor'), {protectedLegacyField: 'preserve'});
  });
  await assertSucceeds(change(db, 'vendor', {name: 'New Kitchen'}));
  await assertFails(change(db, 'vendor', {protectedLegacyField: 'changed'}));
  await assertFails(change(db, 'vendor', {protectedLegacyField: deleteField()}));
  assert.equal((await getDoc(doc(db, 'stalls', 'vendor'))).data().protectedLegacyField, 'preserve');
});
