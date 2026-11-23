import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pilotRules, validateArgs, project } from './prepare_ordering_pilot.mjs';
import { stage4bRules } from './prepare_stage4b.mjs';
const source = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
test('V2 candidate is the Stage 4B Rules with checkout on and both deletion gates closed', () => {
  const candidate = readFileSync(new URL('../pilot/firestore.stage4b.rules', import.meta.url), 'utf8');
  assert.equal(candidate, pilotRules(source));
  assert.equal(candidate, stage4bRules(source, true));
  assert.ok(candidate.includes('function checkoutWritesEnabled() { return true; }'));
  assert.ok(candidate.includes('function menuDeletesEnabled() { return false; }'));
  assert.ok(source.includes('function checkoutWritesEnabled() { return false; }'));
  assert.ok(source.includes('function menuDeletesEnabled() { return false; }'));
});
test('Stage 4B candidate is the Rules file selected by the emulator test suite', () => {
  const firebaseConfig = JSON.parse(readFileSync(new URL('../firebase.stage4b.json', import.meta.url)));
  assert.equal(firebaseConfig.firestore.rules, 'pilot/firestore.stage4b.rules');
  const publicQueue = readFileSync(new URL('../test/firebase/public_queue_count.test.mjs', import.meta.url), 'utf8');
  assert.ok(publicQueue.includes("'../../pilot/firestore.stage4b.rules'"));
  assert.ok(publicQueue.includes("'../../pilot/firestore.stage4b.closed.rules'"));
});
test('existing checkout and FCFS security suites retain coverage against their in-memory gate candidate', () => {
  for (const file of ['checkout_orders.test.mjs', 'vendor_fcfs.test.mjs', 'student_queue.test.mjs']) {
    const suite = readFileSync(new URL('../test/firebase/' + file, import.meta.url), 'utf8');
    assert.ok(suite.includes("function checkoutWritesEnabled() { return false; }"));
    assert.ok(suite.includes("function checkoutWritesEnabled() { return true; }"));
  }
  // The public-queue suite additionally exercises the exact V2 deployment file.
});
test('generation refuses missing, duplicated or already-enabled gates', () => {
  for (const bad of [source + source, source.replace('checkoutWritesEnabled', 'wrongGate'),
    source.replace('function checkoutWritesEnabled() { return false; }', 'function checkoutWritesEnabled() { return true; }'),
    source.replace('function menuDeletesEnabled() { return false; }', 'function menuDeletesEnabled() { return true; }')]) {
    assert.throws(() => pilotRules(bad));
  }
});
test('generator accepts only V2 and cannot accept the old project or deploy arguments', () => {
  validateArgs(['--project', project]);
  for (const args of [[], ['--project', 'fyp-app-9d78a'], ['--project', 'other'], ['--project', 'demo-smart-canteen'], ['deploy'],
    ['--project', project, '--deploy']]) assert.throws(() => validateArgs(args));
});
test('V2 deployment config selects only Stage 4B Rules and local emulator config stays unchanged', () => {
  assert.deepEqual(JSON.parse(readFileSync(new URL('../firebase.v2.pilot.json', import.meta.url))),
    {firestore: {rules: 'pilot/firestore.stage4b.rules'}});
  assert.equal(JSON.parse(readFileSync(new URL('../firebase.json', import.meta.url))).firestore.rules, 'firestore.rules');
  assert.equal(JSON.parse(readFileSync(new URL('../firebase.stage4b.json', import.meta.url))).emulators.firestore.port, 8080);
});
