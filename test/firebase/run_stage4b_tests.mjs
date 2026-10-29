import { spawn } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { budgetFailures } from './checkout_budget.mjs';

// Runs INSIDE firebase emulators:exec. Preserve every existing suite and fail even
// when assertFails would otherwise accept expression/access exhaustion.
if (process.env.GCLOUD_PROJECT !== 'demo-smart-canteen' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') throw new Error('Only the local demo emulators are allowed');
const directory=dirname(fileURLToPath(import.meta.url));
const paths=[resolve(directory,'firestore-debug.log'),resolve(directory,'../../firestore-debug.log')];
const offsets=new Map(paths.map(path=>[path,existsSync(path)?readFileSync(path).length:0]));
const selected = process.argv.includes('--focused') ? ['public_queue_count.test.mjs'] : [
  'stage_one.test.mjs','vendor_operations.test.mjs','vendor_menu.test.mjs',
  'student_catalog.test.mjs','checkout_orders.test.mjs','vendor_fcfs.test.mjs','student_queue.test.mjs',
  'public_queue_count.test.mjs'];
const child=spawn(process.execPath,['--test','--test-concurrency=1',...selected],
  {cwd:directory,env:process.env,stdio:['inherit','pipe','pipe']});
let output='';
for(const [stream,target] of [[child.stdout,process.stdout],[child.stderr,process.stderr]]) {
  stream.on('data',chunk=>{output+=chunk.toString();target.write(chunk);});
}
const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',resolve);});
const logs=paths.filter(existsSync).map(path=>{
  const data=readFileSync(path),start=offsets.get(path);
  return {path,text:data.subarray(data.length>=start?start:0).toString()};
});
const failures=[...budgetFailures(output),...logs.flatMap(log=>budgetFailures(log.text))];
const evidence=logs.some(log=>log.text.length>0);
mkdirSync(resolve(directory,'artifacts'),{recursive:true});
writeFileSync(resolve(directory,'artifacts/stage4b-budget-diagnostics.json'),JSON.stringify({
  childExitCode:code,logs:logs.map(log=>log.path),budgetDiagnostics:failures,
  note:'No per-request expression count is inferred from log silence. Positive 1–2-food, over-limit rejection and all integrity/concurrency tests must also pass.'
},null,2));
if(!evidence) process.stderr.write('FAIL: Firestore debug log missing/empty; budget evidence unavailable.\n');
if(failures.length) process.stderr.write(`FAIL: ${failures.length} Rules budget diagnostics; negative assertions do not count as proof.\n`);
process.exitCode=code===0&&evidence&&failures.length===0?0:1;
