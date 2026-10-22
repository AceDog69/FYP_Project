import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir, rm, access } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { join, relative, isAbsolute, sep } from 'node:path';
import { checkoutDemoRules, parseDemoArguments, prepareCheckoutDemo,
  demoFirebaseArguments, demoProject, repositoryRoot } from './start_checkout_demo.mjs';

const source = await readFile(join(repositoryRoot, 'firestore.rules'), 'utf8');
const closed = 'function checkoutWritesEnabled() { return false; }';
const enabled = 'function checkoutWritesEnabled() { return true; }';
async function productionFiles() {
  return Promise.all(['firestore.rules', 'firebase.json', '.firebaserc'].map(async path => {
    try {return await readFile(join(repositoryRoot, path));}
    catch (error) {if (error.code === 'ENOENT') return null;throw error;}
  }));
}

test('arguments permit only the fixed demo project and no arbitrary Firebase operation', () => {
  assert.equal(parseDemoArguments([]), demoProject);
  assert.equal(parseDemoArguments(['--project', demoProject]), demoProject);
  for (const args of [['--project', 'production-project'], ['--project=production-project'],
    ['deploy'], ['--config', 'firebase.json'], ['--project', demoProject, '--only', 'functions']]) {
    assert.throws(() => parseDemoArguments(args));
  }
  assert.deepEqual(demoFirebaseArguments('/temporary/firebase.checkout-demo-only.json'), [
    'emulators:start', '--project', demoProject, '--only', 'auth,firestore',
    '--config', '/temporary/firebase.checkout-demo-only.json']);
  assert.throws(() => demoFirebaseArguments('firebase.json', 'production-project'), /Refusing/);
});

test('temporary rules differ from checked-in rules only at the checkout gate', () => {
  const rules = checkoutDemoRules(source);
  assert.equal(rules, source.replace(closed, enabled));
  assert.equal(rules.replace(enabled, closed), source);
  assert.equal(rules.split(enabled).length, 2);
  assert.ok(rules.includes('function menuDeletesEnabled() { return false; }'));
  assert.throws(() => checkoutDemoRules(source, 'production-project'), /Refusing/);
});

test('missing, duplicated or already-enabled checkout gates are refused', () => {
  for (const rules of [source.replace(closed, ''), source + '\n' + closed,
    source.replace(closed, enabled), source + '\n' + enabled]) {
    assert.throws(() => checkoutDemoRules(rules), /exactly one/);
  }
});

test('generator refuses either Vendor deletion gate being opened', () => {
  assert.throws(() => checkoutDemoRules(source.replace(
    'function menuDeletesEnabled() { return false; }',
    'function menuDeletesEnabled() { return true; }')), /Food Delete/);
  const categoryOpen = source.replace(
    /(match \/menuCategories\/\{categoryId\}[\s\S]*?allow delete: if )false;/, '$1true;');
  assert.notEqual(categoryOpen, source);
  assert.throws(() => checkoutDemoRules(categoryOpen), /Category Delete/);
});

test('generated files are disposable, outside the repository and scoped only to local demo services', async t => {
  const production = await productionFiles();
  const demo = await prepareCheckoutDemo();
  t.after(() => rm(demo.directory, {recursive: true, force: true}));
  const path = relative(repositoryRoot, demo.directory);
  assert.ok(path === '..' || path.startsWith(`..${sep}`) || isAbsolute(path));
  assert.deepEqual((await readdir(demo.directory)).sort(), [
    '.firebaserc', 'firebase.checkout-demo-only.json', 'firestore.checkout-demo-only.rules']);
  assert.equal(await readFile(demo.rulesPath, 'utf8'), checkoutDemoRules(source));
  const config = JSON.parse(await readFile(demo.configPath, 'utf8'));
  assert.deepEqual(config, {
    firestore: {rules: 'firestore.checkout-demo-only.rules'},
    emulators: {auth: {host: '127.0.0.1', port: 9099}, firestore: {host: '127.0.0.1', port: 8080},
      ui: {enabled: false}, singleProjectMode: true},
  });
  assert.deepEqual(JSON.parse(await readFile(join(demo.directory, '.firebaserc'), 'utf8')),
    {projects: {default: demoProject}});
  assert.deepEqual(await productionFiles(), production);
  await rm(demo.directory, {recursive: true, force: true});
  await assert.rejects(access(demo.directory), {code: 'ENOENT'});
});

test('generation refuses a real project or an output location inside the repository', async () => {
  await assert.rejects(prepareCheckoutDemo({project: 'production-project'}), /Refusing/);
  await assert.rejects(prepareCheckoutDemo({temporaryRoot: repositoryRoot}), /outside the repository/);
});

test('actual launcher process rejects a non-demo project before Firebase can start', () => {
  const child = spawnSync(process.execPath, [join(repositoryRoot, 'scripts', 'start_checkout_demo.mjs'),
    '--project', 'production-project'], {encoding: 'utf8'});
  assert.equal(child.status, 1);assert.match(child.stderr, /Refusing any project other than demo-smart-canteen/);
});
