import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { integratedRules } from './prepare_stage4_integrated.mjs';
import { stage4bRules } from './prepare_stage4b.mjs';
const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

test('integrated candidate differs from verified Stage 4B by exactly the paired Food Delete gate', () => {
  const source = read('firestore.rules'), base = read('pilot/firestore.stage4b.rules');
  const candidate = read('pilot/firestore.stage4-integrated.rules');
  assert.equal(base, stage4bRules(source));
  assert.equal(candidate, integratedRules(base));
  assert.equal(candidate.replace('function menuDeletesEnabled() { return true; }',
    'function menuDeletesEnabled() { return false; }'), base);
  const categories = candidate.slice(candidate.indexOf('match /menuCategories/'), candidate.indexOf('match /menuCategoryNames/'));
  assert.ok(categories.includes('allow delete: if false;'));
  assert.ok(source.includes('function checkoutWritesEnabled() { return false; }'));
  assert.ok(source.includes('function menuDeletesEnabled() { return false; }'));
  for (const file of ['pilot/firestore.ordering.rules', 'pilot/firestore.stage4b.rules', 'pilot/firestore.stage4b.closed.rules']) {
    assert.ok(read(file).includes('function menuDeletesEnabled() { return false; }'));
  }
});
test('integrated generation rejects enabled, duplicated or closed-checkout sources', () => {
  const base = read('pilot/firestore.stage4b.rules');
  assert.throws(() => integratedRules(base + base));
  assert.throws(() => integratedRules(integratedRules(base)));
  assert.throws(() => integratedRules(read('pilot/firestore.stage4b.closed.rules')));
});
test('isolated configuration uses the combined candidate and loopback demo endpoints', () => {
  const config = JSON.parse(read('firebase.stage4-integrated.json'));
  assert.deepEqual(config, {...JSON.parse(read('firebase.stage4b.json')),
    firestore: {rules: 'pilot/firestore.stage4-integrated.rules'}});
});
test('emulator Food Delete is wired only through its guarded synthetic entry point', () => {
  const emulator = read('lib/main_emulator.dart');
  assert.ok(emulator.includes("bool.fromEnvironment('EMULATOR_FOOD_DELETE', defaultValue: false)"));
  assert.ok(emulator.includes('checkoutAllowed: _demoOrders.canCheckout'));
  assert.ok(emulator.includes('publicQueueCountsEnabled: _demoOrders.usesPublicQueueCounts'));
  assert.ok(!read('lib/services/real_ordering_pilot.dart').includes('EMULATOR_FOOD_DELETE'));
  assert.ok(!read('lib/main.dart').includes('EMULATOR_FOOD_DELETE'));
});
