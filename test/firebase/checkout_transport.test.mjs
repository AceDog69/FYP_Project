import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, connect } from 'node:net';
import { checkoutTransport, expectedOfflineRejection, boundedOfflineCleanup } from './checkout_transport.mjs';

test('offline error classification requires the verified cut and exact RPC cancellation',()=>{
  const cut={onlineVerified:true,transportCut:true};
  const cancelled={code:'cancelled',message:'1 CANCELLED: Call cancelled'};
  assert.equal(expectedOfflineRejection(cancelled,cut),true);
  assert.equal(expectedOfflineRejection({code:'unavailable'},cut),true);
  for(const state of [{onlineVerified:false,transportCut:true},{onlineVerified:true,transportCut:false}]) {
    assert.equal(expectedOfflineRejection(cancelled,state),false);
    assert.equal(expectedOfflineRejection({code:'unavailable'},state),false);
  }
  for(const error of [undefined,new Error('Call cancelled'),{code:1,message:cancelled.message},
    {code:'cancelled',message:'Discarded checkout'}, {code:'cancelled',message:'Cancelled on client'},
    {code:'permission-denied',message:cancelled.message}, {code:'deadline-exceeded'},
    {code:'unknown',message:cancelled.message}, {code:'internal'}, {code:'aborted'}]) {
    assert.equal(expectedOfflineRejection(error,cut),false);
  }
});

test('offline cleanup completes normally or fails on a deadline; deadlines are not offline proof',async()=>{
  let finished=false;await boundedOfflineCleanup(async()=>{finished=true;});assert.equal(finished,true);
  await assert.rejects(boundedOfflineCleanup(()=>new Promise(()=>{}),10),/cleanup timed out/);
});

test('offline transport forwards a real RPC path then blocks existing and new connections', {timeout:5000},async()=>{
  let connections=0,transport,client;
  const upstream=createServer(socket=>{
    connections++;socket.on('error',()=>{});socket.on('data',data=>socket.write(data));
  });
  await new Promise((resolve,reject)=>{upstream.once('error',reject);upstream.listen(0,'127.0.0.1',resolve);});
  try {
    transport=await checkoutTransport({upstreamPort:upstream.address().port});
    client=connect(transport.port,'127.0.0.1');client.on('error',()=>{});
    const echoed=new Promise((resolve,reject)=>{client.once('data',resolve);client.once('error',reject);});
    client.write('checkout-online-control');assert.equal((await echoed).toString(),'checkout-online-control');
    assert.equal(connections,1);assert.equal(transport.stats.forwardedConnections,1);
    assert.ok(transport.stats.forwardedBytes>0);
    const closed=new Promise(resolve=>client.once('close',resolve));transport.cut();await closed;
    const blocked=connect(transport.port,'127.0.0.1');blocked.on('error',()=>{});
    await new Promise(resolve=>blocked.once('close',resolve));
    assert.equal(transport.stats.blockedConnections,1);assert.equal(connections,1);
    assert.equal(transport.stats.forwardedConnections,1);
  } finally {
    client?.destroy();await transport?.close();await new Promise(resolve=>upstream.close(resolve));
  }
});
