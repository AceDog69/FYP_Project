import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pilotRules, validateArgs, project } from './prepare_ordering_pilot.mjs';
const source = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
test('committed candidate differs only at checkout gate, preserving every authorization and FCFS expression', () => {
  const candidate = readFileSync(new URL('../pilot/firestore.ordering.rules', import.meta.url), 'utf8');
  assert.equal(candidate, pilotRules(source));
  assert.equal(candidate.replace('function checkoutWritesEnabled() { return true; }',
    'function checkoutWritesEnabled() { return false; }'), source);
  assert.ok(candidate.includes('function menuDeletesEnabled() { return false; }'));
});
test('pilot candidate equals the checkout-enabled Rules exercised by the existing security suite', () => {
  for (const file of ['checkout_orders.test.mjs', 'vendor_fcfs.test.mjs', 'student_queue.test.mjs']) {
    const suite = readFileSync(new URL('../test/firebase/' + file, import.meta.url), 'utf8');
    assert.ok(suite.includes("function checkoutWritesEnabled() { return false; }"));
    assert.ok(suite.includes("function checkoutWritesEnabled() { return true; }"));
  }
  // Byte equality above is the link to those executable integrity/forgery/FCFS
  // cases, not a replacement for running them and inspecting budget diagnostics.
});
test('generation refuses missing, duplicated or already-enabled gates', () => {
  for (const bad of [source + source, source.replace('checkoutWritesEnabled', 'wrongGate'),
    source.replace('function checkoutWritesEnabled() { return false; }', 'function checkoutWritesEnabled() { return true; }'),
    source.replace('function menuDeletesEnabled() { return false; }', 'function menuDeletesEnabled() { return true; }')]) {
    assert.throws(() => pilotRules(bad));
  }
});
test('generator accepts only the exact authorized project and cannot accept deploy arguments', () => {
  validateArgs(['--project', project]);
  for (const args of [[], ['--project', 'other'], ['--project', 'demo-smart-canteen'], ['deploy'],
    ['--project', project, '--deploy']]) assert.throws(() => validateArgs(args));
});
test('pilot config only targets its explicit rules candidate, default config stays closed', () => {
  assert.deepEqual(JSON.parse(readFileSync(new URL('../firebase.pilot.json', import.meta.url))),
    {firestore: {rules: 'pilot/firestore.ordering.rules'}});
  assert.equal(JSON.parse(readFileSync(new URL('../firebase.json', import.meta.url))).firestore.rules, 'firestore.rules');
});
