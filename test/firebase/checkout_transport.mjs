import { createServer, connect } from 'node:net';

// Test-only classification, after a verified online path has deliberately been
// cut. grpc-js 1.9.16 maps NGHTTP2_CANCEL to this exact status/message. Do not
// accept generic cancellation, permission errors or deadlines as offline proof.
export function expectedOfflineRejection(error,{onlineVerified,transportCut}) {
  return onlineVerified===true&&transportCut===true&&(error?.code==='unavailable'||
    (error?.code==='cancelled'&&error.message==='1 CANCELLED: Call cancelled'));
}

export async function boundedOfflineCleanup(cleanup,timeoutMs=5000) {
  let timer;
  try {
    await Promise.race([Promise.resolve().then(cleanup),new Promise((_,reject)=>{
      timer=setTimeout(()=>reject(new Error('Offline test cleanup timed out')),timeoutMs);
    })]);
  } finally {clearTimeout(timer);}
}

// A local transport cut, not just disableNetwork(): some JS SDK transaction RPCs
// bypass the listener network switch. Never reconnect a pending transaction.
export async function checkoutTransport({upstreamPort=8080}={}) {
  let offline=false;
  const stats={forwardedConnections:0,blockedConnections:0,forwardedBytes:0};
  const sockets=new Set();
  const server=createServer(client=>{
    if(offline) {stats.blockedConnections++;client.destroy();return;}
    stats.forwardedConnections++;
    const upstream=connect(upstreamPort,'127.0.0.1');
    for(const socket of [client,upstream]) {
      sockets.add(socket);socket.on('close',()=>sockets.delete(socket));
      socket.on('error',()=>{client.destroy();upstream.destroy();});
    }
    client.on('data',chunk=>{stats.forwardedBytes+=chunk.length;});
    client.pipe(upstream);upstream.pipe(client);
    client.on('close',()=>upstream.destroy());upstream.on('close',()=>client.destroy());
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const cut=()=>{offline=true;for(const socket of sockets) socket.destroy();};
  return {port:server.address().port,stats,cut,
    close:async()=>{cut();await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));}};
}
