import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithEmailAndPassword, signOut, sendPasswordResetEmail } from 'firebase/auth';
import { getFirestore, connectFirestoreEmulator, doc, setDoc, getDoc,
  updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp } from 'firebase/firestore';

// Synthetic configuration is exclusively for local demo emulators. Tests
// refuse to run without both emulators and never use the live Firebase project.
const projectId = 'demo-smart-canteen';
let env;
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  env = await initializeTestEnvironment({ projectId, firestore: {
    host: '127.0.0.1', port: 8080,
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  }});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); });
const dbFor = (uid) => env.authenticatedContext(uid, {email: `${uid}@example.com`}).firestore();
const profile = (uid, role = 'student') => ({ uid, fullName: 'Alex Lee',
  email: `${uid}@example.com`, phoneNumber: '0123456789', role,
  createdAt: serverTimestamp(), stallSetupComplete: false, stallId: null });
const stall = (uid) => ({ ownerUid: uid, name: 'Campus Kitchen', category: 'Rice',
  preparationMinutes: 15, status: 'closed', createdAt: serverTimestamp() });
async function create(db, uid, role = 'student') {
  await assertSucceeds(setDoc(doc(db, 'users', uid), profile(uid, role)));
}
function setup(db, uid, overrides = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'stalls', uid), {...stall(uid), ...overrides});
  batch.update(doc(db, 'users', uid), {stallSetupComplete: true, stallId: uid});
  return batch.commit();
}

test('unauthenticated profile access and creation are denied', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', 'student')));
  await assertFails(setDoc(doc(db, 'users', 'student'), profile('student')));
});
test('users may create only their own UID profile', async () => {
  const db = dbFor('student');
  await create(db, 'student');
  await assertFails(setDoc(doc(db, 'users', 'other'), profile('student')));
});
test('invalid roles, impersonated UID/email, and extra privileges are denied', async () => {
  const db = dbFor('student'), ref = doc(db, 'users', 'student');
  for (const change of [{role:'admin'}, {uid:'other'}, {email:'other@example.com'}, {admin:true}]) {
    await assertFails(setDoc(ref, {...profile('student'), ...change}));
  }
});
test('role, UID, email and creation timestamp are immutable; name/phone may update', async () => {
  const db = dbFor('student'), ref = doc(db, 'users', 'student');
  await create(db, 'student');
  for (const change of [{role:'vendor'}, {uid:'other'}, {email:'other@example.com'}, {createdAt:serverTimestamp()}]) {
    await assertFails(updateDoc(ref, change));
  }
  await assertSucceeds(updateDoc(ref, {fullName:'Updated Name', phoneNumber:'987654321'}));
});
test('another user cannot read or edit profiles', async () => {
  await create(dbFor('student'), 'student');
  const ref = doc(dbFor('other'), 'users', 'student');
  await assertFails(getDoc(ref)); await assertFails(updateDoc(ref, {fullName:'Impersonated'}));
});
test('profile deletion and a completed stall during profile creation are denied', async () => {
  const db = dbFor('vendor'), ref = doc(db, 'users', 'vendor');
  await assertFails(setDoc(ref, {...profile('vendor','vendor'), stallSetupComplete:true, stallId:'vendor'}));
  await create(db, 'vendor', 'vendor'); await assertFails(deleteDoc(ref));
});
test('stall setup must atomically create and associate the stall', async () => {
  const db = dbFor('vendor'); await create(db,'vendor','vendor');
  await assertFails(updateDoc(doc(db,'users','vendor'), {stallSetupComplete:true,stallId:'vendor'}));
  await assertFails(setDoc(doc(db,'stalls','vendor'),stall('vendor')));
  await assertSucceeds(setup(db,'vendor'));
  assert.equal((await getDoc(doc(db,'stalls','vendor'))).data().status,'closed');
  assert.equal((await getDoc(doc(db,'users','vendor'))).data().stallId,'vendor');
});
test('students cannot create a stall or promote themselves in a batch', async () => {
  const db = dbFor('student'); await create(db,'student');
  await assertFails(setup(db,'student'));
  const batch = writeBatch(db);
  batch.update(doc(db,'users','student'), {role:'vendor',stallSetupComplete:true,stallId:'student'});
  batch.set(doc(db,'stalls','student'),stall('student'));
  await assertFails(batch.commit());
});
test('stall ownership, closed status and preparation bounds are enforced', async () => {
  const db = dbFor('vendor'); await create(db,'vendor','vendor');
  for (const change of [{ownerUid:'other'}, {status:'open'}, {preparationMinutes:0},
    {preparationMinutes:181}, {preparationMinutes:1.5}, {name:''}]) {
    await assertFails(setup(db,'vendor',change));
  }
  assert.equal((await getDoc(doc(db,'users','vendor'))).data().stallSetupComplete,false);
  assert.equal((await getDoc(doc(db,'stalls','vendor'))).exists(),false);
});
test('completed stalls cannot be reassigned, reset, duplicated or edited', async () => {
  const db = dbFor('vendor'); await create(db,'vendor','vendor'); await setup(db,'vendor');
  await assertFails(updateDoc(doc(db,'users','vendor'),{stallSetupComplete:false,stallId:null}));
  await assertFails(updateDoc(doc(db,'users','vendor'),{stallId:'other'}));
  await assertFails(setDoc(doc(db,'stalls','another-stall'),stall('vendor')));
  await assertFails(updateDoc(doc(db,'stalls','vendor'),{ownerUid:'other'}));
  await assertFails(deleteDoc(doc(db,'stalls','vendor')));
});

test('real Auth emulator accounts: registration, login, profiles, stall transaction, reset, logout', async () => {
  const app = initializeApp({projectId, apiKey:'demo-emulator-only', appId:'demo-emulator-only'}, 'stage-one');
  const auth = getAuth(app); connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings:true});
  const db = getFirestore(app); connectFirestoreEmulator(db, '127.0.0.1', 8080);
  try {
    for (const role of ['student','vendor']) {
      const email = `${role}-${Date.now()}@example.com`, password = 'EmulatorPassword123';
      const user = (await createUserWithEmailAndPassword(auth,email,password)).user;
      const ref = doc(db,'users',user.uid);
      await setDoc(ref,{...profile(user.uid,role),email});
      await signOut(auth); assert.equal(auth.currentUser,null);
      await assert.rejects(signInWithEmailAndPassword(auth,email,'WrongPassword123'));
      await signInWithEmailAndPassword(auth,email,password);
      assert.equal((await getDoc(ref)).data().role,role);
      if (role === 'vendor') {
        const stallRef = doc(db,'stalls',user.uid);
        // Same read-before-write transaction shape used by the Dart service.
        await runTransaction(db, async tx => {
          const savedProfile = await tx.get(ref), savedStall = await tx.get(stallRef);
          assert.equal(savedProfile.data().stallSetupComplete,false);
          assert.equal(savedStall.exists(),false);
          tx.set(stallRef,stall(user.uid)); tx.update(ref,{stallId:user.uid,stallSetupComplete:true});
        });
        await signOut(auth); await signInWithEmailAndPassword(auth,email,password);
        assert.equal((await getDoc(ref)).data().stallSetupComplete,true);
        assert.equal((await getDoc(stallRef)).data().status,'closed');
      }
      await sendPasswordResetEmail(auth,email);
      const codes = await (await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${projectId}/oobCodes`)).json();
      assert.ok(codes.oobCodes.some(code => code.email === email && code.requestType === 'PASSWORD_RESET'));
      await signOut(auth); await assertFails(getDoc(ref));
    }
  } finally { await deleteApp(app); }
});
