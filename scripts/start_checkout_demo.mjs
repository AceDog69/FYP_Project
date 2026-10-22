// Local emulators ONLY. No deploy command or arbitrary Firebase args are exposed.
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdtemp, rm, realpath, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, resolve, relative, isAbsolute, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const demoProject = 'demo-smart-canteen';
export const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const closedGate = 'function checkoutWritesEnabled() { return false; }';
const openGate = 'function checkoutWritesEnabled() { return true; }';

function requireDemo(project) {
  if (project !== demoProject) throw new Error('Refusing any project other than demo-smart-canteen.');
}

export function parseDemoArguments(args) {
  if (args.length === 0) return demoProject;
  if (args.length === 2 && args[0] === '--project') {
    requireDemo(args[1]); return args[1];
  }
  throw new Error('Use no arguments, or --project demo-smart-canteen. Other CLI arguments are refused.');
}

export function checkoutDemoRules(source, project = demoProject) {
  requireDemo(project);
  if (source.split(closedGate).length !== 2 ||
      (source.match(/function\s+checkoutWritesEnabled\s*\(/g) ?? []).length !== 1) {
    throw new Error('Expected exactly one checked-in closed checkout gate.');
  }
  if (source.split('function menuDeletesEnabled() { return false; }').length !== 2 ||
      (source.match(/function\s+menuDeletesEnabled\s*\(/g) ?? []).length !== 1) {
    throw new Error('Vendor Food Delete must remain disabled.');
  }
  const categoryStart = source.indexOf('match /menuCategories/{categoryId} {');
  const categoryEnd = source.indexOf('match /menuCategoryNames/', categoryStart);
  if (categoryStart < 0 || categoryEnd < 0 ||
      !/allow\s+delete\s*:\s*if\s+false\s*;/.test(source.slice(categoryStart, categoryEnd))) {
    throw new Error('Vendor Category Delete must remain disabled.');
  }
  const enabled = source.replace(closedGate, openGate);
  if (enabled.split(openGate).length !== 2 || enabled.replace(openGate, closedGate) !== source) {
    throw new Error('Demo generation must change only the one checkout gate.');
  }
  return enabled;
}

function inside(parent, child) {
  const path = relative(parent, child);
  return path === '' || (path !== '..' && !path.startsWith(`..${sep}`) && !isAbsolute(path));
}

export async function prepareCheckoutDemo({project = demoProject, temporaryRoot = tmpdir()} = {}) {
  requireDemo(project);
  const root = await realpath(repositoryRoot), temp = await realpath(temporaryRoot);
  if (inside(root, temp)) throw new Error('Generated demo files must be outside the repository.');
  const source = await readFile(join(root, 'firestore.rules'), 'utf8');
  const enabled = checkoutDemoRules(source, project);
  const directory = await mkdtemp(join(temp, 'smart-canteen-checkout-demo-'));
  try {
    const rulesPath = join(directory, 'firestore.checkout-demo-only.rules');
    const configPath = join(directory, 'firebase.checkout-demo-only.json');
    const config = {
      firestore: {rules: 'firestore.checkout-demo-only.rules'},
      emulators: {
        auth: {host: '127.0.0.1', port: 9099},
        firestore: {host: '127.0.0.1', port: 8080},
        ui: {enabled: false}, singleProjectMode: true,
      },
    };
    await writeFile(rulesPath, enabled, {flag: 'wx'});
    await writeFile(configPath, JSON.stringify(config, null, 2) + '\n', {flag: 'wx'});
    // Even a manually opened terminal in this directory defaults to the demo.
    // There is deliberately no default firebase.json deployment configuration.
    await writeFile(join(directory, '.firebaserc'), JSON.stringify({projects: {default: demoProject}}), {flag: 'wx'});
    if (await readFile(rulesPath, 'utf8') !== enabled ||
        await readFile(join(root, 'firestore.rules'), 'utf8') !== source) {
      throw new Error('Rules changed during demo generation; stop and review.');
    }
    return {directory, rulesPath, configPath};
  } catch (error) {
    await rm(directory, {recursive: true, force: true}); throw error;
  }
}

export function demoFirebaseArguments(configPath, project = demoProject) {
  requireDemo(project);
  return ['emulators:start', '--project', demoProject, '--only', 'auth,firestore', '--config', configPath];
}

export async function startCheckoutDemo(args = process.argv.slice(2)) {
  const project = parseDemoArguments(args);
  const cli = join(repositoryRoot, 'test', 'firebase', 'node_modules', 'firebase-tools', 'lib', 'bin', 'firebase.js');
  try {await access(cli);} catch {
    throw new Error('Local Firebase CLI missing. Run npm ci in test/firebase first.');
  }
  const demo = await prepareCheckoutDemo({project});
  let stopping = false;
  // Ctrl+C in CMD/PowerShell reaches the inherited-console Firebase CLI too.
  // Keep this parent alive for its graceful shutdown and temporary-file cleanup.
  const onInterrupt = () => {
    if (!stopping) console.log('\nWaiting for local Firebase emulators to stop...');
    stopping = true;
  };
  process.on('SIGINT', onInterrupt);
  try {
    console.log(`Checkout-enabled LOCAL demo only: ${demoProject}`);
    console.log(`Temporary rules/config/logs: ${demo.directory}`);
    console.log('Production rules and both Vendor deletion gates are unchanged. Stop with Ctrl+C.');
    const child = spawn(process.execPath, [cli, ...demoFirebaseArguments(demo.configPath, project)], {
      cwd: demo.directory, stdio: 'inherit',
      env: {...process.env, GCLOUD_PROJECT: demoProject, GOOGLE_CLOUD_PROJECT: demoProject,
        FIREBASE_CONFIG: JSON.stringify({projectId: demoProject})},
    });
    return await new Promise((resolve, reject) => {
      child.once('error', reject);child.once('close', code => resolve(code ?? 1));
    });
  } finally {
    process.off('SIGINT', onInterrupt);
    await rm(demo.directory, {recursive: true, force: true});
    console.log('Temporary checkout demo files removed.');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  startCheckoutDemo().then(code => {process.exitCode = code;}).catch(error => {
    console.error(error.message);process.exitCode = 1;
  });
}
