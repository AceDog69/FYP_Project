import { spawn } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { budgetFailures } from './checkout_budget.mjs';

// Only synthetic local emulators. First preserve the complete accepted run,
// then rerun menu and public-count contracts against the SAME combined policy,
// followed by explicit delete/checkout/processing integration attacks and races.
if (process.env.GCLOUD_PROJECT !== 'demo-smart-canteen' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
  throw new Error('Only the local demo emulators are allowed');
}
const directory = dirname(fileURLToPath(import.meta.url));
const paths = [resolve(directory,'firestore-debug.log'), resolve(directory,'../../firestore-debug.log')];
const offsets = new Map(paths.map(path => [path, existsSync(path) ? readFileSync(path).length : 0]));
const phases = process.argv.includes('--focused') ? [] : [{name:'preserved-stage4b', integrated:false, files:[
  'stage_one.test.mjs','vendor_operations.test.mjs','vendor_menu.test.mjs','student_catalog.test.mjs',
  'checkout_orders.test.mjs','vendor_fcfs.test.mjs','student_queue.test.mjs','public_queue_count.test.mjs']}];
phases.push({name:'combined-policy', integrated:true, files:process.argv.includes('--focused')
  ? ['stage4_integrated.test.mjs']
  : ['vendor_menu.test.mjs','public_queue_count.test.mjs','stage4_integrated.test.mjs']});
let output = ''; const results = [];
for (const phase of phases) {
  process.stdout.write(`\nRunning ${phase.name}\n`);
  const child = spawn(process.execPath,['--test','--test-concurrency=1',...phase.files], {
    cwd:directory, env:{...process.env, SMART_CANTEEN_INTEGRATED_RULES:String(phase.integrated)},
    stdio:['inherit','pipe','pipe']});
  let phaseOutput = '';
  for (const [stream, target] of [[child.stdout,process.stdout],[child.stderr,process.stderr]]) {
    stream.on('data', chunk => {phaseOutput += chunk.toString(); target.write(chunk);});
  }
  const code = await new Promise((resolve,reject) => {child.on('error',reject); child.on('close',resolve);});
  output += phaseOutput;
  results.push({phase:phase.name, childExitCode:code,
    tests:Number(phaseOutput.match(/^ℹ tests (\d+)/m)?.[1] ?? phaseOutput.match(/^# tests (\d+)/m)?.[1] ?? 0)});
}
const logs = paths.filter(existsSync).map(path => {
  const data = readFileSync(path), start = offsets.get(path);
  return {path, text:data.subarray(data.length >= start ? start : 0).toString()};
});
const failures = [...budgetFailures(output), ...logs.flatMap(log => budgetFailures(log.text))];
const evidence = logs.some(log => log.text.length > 0);
mkdirSync(resolve(directory,'artifacts'), {recursive:true});
writeFileSync(resolve(directory,'artifacts/stage4-integrated-budget-diagnostics.json'), JSON.stringify({
  results, debugLogEvidence:evidence, budgetDiagnostics:failures,
  note:'Preserved baseline runs with its accepted policies; combined menu/count/integration cases load the integrated candidate. Log silence is not an exact per-request expression/access measurement.'
},null,2));
if (!evidence) process.stderr.write('FAIL: Firestore debug log missing/empty.\n');
if (failures.length) process.stderr.write(`FAIL: ${failures.length} Rules budget diagnostics.\n`);
process.exitCode = results.every(r => r.childExitCode === 0 && r.tests > 0) && evidence && failures.length === 0 ? 0 : 1;
