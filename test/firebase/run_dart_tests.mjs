import { build } from 'esbuild';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const output = resolve(directory, '.browser-sdk');
await mkdir(output, {recursive:true});
for (const [name, module] of [['core','app'],['auth','auth'],['firestore','firestore']]) {
  await writeFile(resolve(output, `${name}-entry.js`), `export * from 'firebase-sdk-tested/${module}';`);
}
await build({entryPoints: {
  core:resolve(output,'core-entry.js'),auth:resolve(output,'auth-entry.js'),
  firestore:resolve(output,'firestore-entry.js')},
  bundle:true,splitting:true,format:'esm',platform:'browser',outdir:output});
const server = createServer(async (request,response) => {
  response.setHeader('Access-Control-Allow-Origin','*');
  response.setHeader('Content-Type','application/javascript');
  const name = new URL(request.url, 'http://localhost').pathname.slice(1);
  if (!/^[a-zA-Z0-9_-]+\.js$/.test(name)) { response.writeHead(404); response.end(); return; }
  try { response.end(await readFile(resolve(output,name))); }
  catch { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(9190,'127.0.0.1',resolve));
try {
  const child = spawn('flutter',['test','--platform','chrome','test/firebase_repository_browser_test.dart'],
    {cwd:resolve(directory,'../..'),stdio:'inherit',env:process.env});
  const code = await new Promise((resolve,reject) => {
    child.on('error',reject);child.on('exit',resolve);
  });
  process.exitCode = code ?? 1;
} finally { server.close(); }
