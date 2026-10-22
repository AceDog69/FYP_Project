import { createServer, connect } from 'node:net';

// A local transport cut, not just disableNetwork(): some JS SDK transaction RPCs
// bypass the listener network switch. Never reconnect a pending transaction.
export async function checkoutTransport() {
  let offline=false;
  const sockets=new Set();
  const server=createServer(client=>{
    if(offline) {client.destroy();return;}
    const upstream=connect(8080,'127.0.0.1');
    for(const socket of [client,upstream]) {
      sockets.add(socket);socket.on('close',()=>sockets.delete(socket));
      socket.on('error',()=>{client.destroy();upstream.destroy();});
    }
    client.pipe(upstream);upstream.pipe(client);
    client.on('close',()=>upstream.destroy());upstream.on('close',()=>client.destroy());
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const cut=()=>{offline=true;for(const socket of sockets) socket.destroy();};
  return {port:server.address().port,cut,close:async()=>{cut();await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));}};
}
