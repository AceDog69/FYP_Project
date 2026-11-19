import { doc, getDocFromServer, runTransaction, serverTimestamp } from 'firebase/firestore';
import { orderRef } from './checkout_helpers.mjs';
export const queueRef=(db,uid='vendor')=>doc(db,'vendorQueues',uid);
export const progressRef=(db,uid='vendor')=>doc(db,'queueProgress',uid);
export const preparationStatsRef=(db,uid='vendor')=>doc(db,'vendorPreparationStats',uid);
export const progressData=(uid,queue)=>({schemaVersion:2,vendorUid:uid,nextTicket:queue.nextTicket,
  preparingCount:queue.preparingCount,revision:queue.revision,updatedAt:queue.updatedAt});
export const initialQueue=()=>({schemaVersion:2,nextTicket:1,preparingCount:0,revision:0});
export const statuses=['Pending','Preparing','Ready','Completed'];
export function progressWrites(writer,db,order,queue,preparationEstimateMillis=order.preparationMinutes*60000) {
  const next=statuses[statuses.indexOf(order.status)+1];
  const update={status:next,statusRevision:(order.statusRevision??0)+1,statusUpdatedAt:serverTimestamp(),
    [next==='Preparing'?'preparingAt':next==='Ready'?'readyAt':'completedAt']:serverTimestamp()};
  if(next==='Preparing') update.preparationEstimateMillis=preparationEstimateMillis;
  if(next==='Ready') update.preparationSampleRecorded=false;
  writer.update(orderRef(db,order.orderId),update);
  if(next!=='Completed') {
    const starting=next==='Preparing';
    const after={
    schemaVersion:2,vendorUid:order.vendorUid,nextTicket:queue.nextTicket+(starting?1:0),
    preparingCount:(queue.preparingCount??(queue.preparingOrderId?1:0))+(starting?1:-1),
    revision:queue.revision+1,lastTransitionOrderId:order.orderId,updatedAt:serverTimestamp()};
    writer.set(queueRef(db,order.vendorUid),after);
    writer.set(progressRef(db,order.vendorUid),progressData(order.vendorUid,after));
  }
}
const minSampleMillis=1000,maxSampleMillis=12*60*60*1000,maxSamples=2147483647;
function validStats(uid,d) {
  return d?.schemaVersion===1&&d.vendorUid===uid&&Number.isInteger(d.sampleCount)&&d.sampleCount>=1&&d.sampleCount<=maxSamples&&
    Number.isInteger(d.totalDurationMillis)&&d.totalDurationMillis>=d.sampleCount*minSampleMillis&&
    d.totalDurationMillis<=d.sampleCount*maxSampleMillis&&d.revision===d.sampleCount&&
    /^[A-Za-z0-9]{20}$/.test(d.lastOrderId)&&d.updatedAt?.toMillis;
}
export async function recordPreparationSample(db,expected) {
  const ref=orderRef(db,expected.orderId),statsRef=preparationStatsRef(db,expected.vendorUid);
  const publicRef=doc(db,'publicStalls',expected.vendorUid);
  for(let attempt=0;attempt<5;attempt++) {
    let observedSampleCount;
    try {
      await runTransaction(db,async tx=>{
        const saved=await tx.get(ref),order=saved.data();
        if(!order||!['Ready','Completed'].includes(order.status)) throw new Error('ineligible-sample-order');
        if(order.preparationSampleRecorded===true) return;
        const duration=order.readyAt?.toMillis?.()-order.preparingAt?.toMillis?.();
        const valid=Number.isInteger(duration)&&duration>=minSampleMillis&&duration<=maxSampleMillis;
        let statsSnapshot,stats,publicSnapshot;
        if(valid) {
          statsSnapshot=await tx.get(statsRef);stats=statsSnapshot.data();
          publicSnapshot=await tx.get(publicRef);
          if(statsSnapshot.exists()&&!validStats(order.vendorUid,stats)) throw new Error('malformed-preparation-stats');
          if(stats?.sampleCount>=maxSamples) throw new Error('preparation-sample-limit');
          observedSampleCount=stats?.sampleCount??0;
          const listing=publicSnapshot.data(), expectedEstimate=stats
            ? Math.floor((stats.totalDurationMillis+stats.sampleCount-1)/stats.sampleCount)
            : (listing?.preparationMinutes??0)*60000;
          if(!publicSnapshot.exists()||!Number.isInteger(listing?.preparationMinutes)||
             listing.estimatedPreparationMillis!==expectedEstimate||
             listing.preparationStatsRevision!==(stats?.revision??0))
            throw new Error('preparation-projection-mismatch');
        }
        if(valid) {
          const sampleCount=(stats?.sampleCount??0)+1,totalDurationMillis=(stats?.totalDurationMillis??0)+duration;
          const next=stats?{schemaVersion:1,vendorUid:order.vendorUid,sampleCount:stats.sampleCount+1,
            totalDurationMillis:stats.totalDurationMillis+duration,revision:stats.revision+1,lastOrderId:order.orderId,
            updatedAt:serverTimestamp()}:{schemaVersion:1,vendorUid:order.vendorUid,sampleCount:1,
            totalDurationMillis:duration,revision:1,lastOrderId:order.orderId,updatedAt:serverTimestamp()};
          tx.set(statsRef,next);
          tx.update(publicRef,{estimatedPreparationMillis:Math.floor((totalDurationMillis+sampleCount-1)/sampleCount),
            preparationStatsRevision:sampleCount,updatedAt:serverTimestamp()});
        }
        tx.update(ref,{preparationSampleRecorded:true});
      },{maxAttempts:8});
      break;
    } catch(error) {
      if(error?.code!=='permission-denied'||observedSampleCount===undefined||attempt===4) throw error;
      // Retry only when server reads prove another valid sample advanced the
      // shared aggregate, or this order's idempotency marker already landed.
      const currentOrder=await getDocFromServer(ref);
      if(currentOrder.data()?.preparationSampleRecorded===true) break;
      const currentStats=await getDocFromServer(statsRef),stats=currentStats.data();
      if(!currentStats.exists()||!validStats(expected.vendorUid,stats)||stats.sampleCount<=observedSampleCount) throw error;
    }
  }
  const confirmed=await getDocFromServer(orderRef(db,expected.orderId));
  if(confirmed.data()?.preparationSampleRecorded!==true) throw new Error('unconfirmed-preparation-sample');
}
// Executable JS counterpart of the Dart processing transaction. The adversarial
// cases bypass this guard completely and exercise Rules with raw batches.
export async function advance(db,expected,{maxAttempts=8}={}) {
  if(expected.status==='Ready'&&expected.preparationSampleRecorded!==true)
    await recordPreparationSample(db,expected);
  for(let attempt=0;attempt<5;attempt++) {
    let observedQueueRevision;
    try {
      await runTransaction(db,async tx=>{
        observedQueueRevision=undefined;
        const record=await tx.get(orderRef(db,expected.orderId));
        const cursor=await tx.get(queueRef(db,expected.vendorUid));
        const order=record.data(),queue=cursor.data()??initialQueue();
        observedQueueRevision=queue.revision??0;
        if(order?.status!==expected.status||(order.statusRevision??0)!==(expected.statusRevision??0))
          throw new Error('stale-order');
        const preparingCount=queue.preparingCount??(queue.preparingOrderId?1:0);
        if((order.status==='Pending'&&queue.nextTicket!==order.ticket)||
           (order.status==='Preparing'&&(!preparingCount||order.ticket>=queue.nextTicket))||order.status==='Completed')
          throw new Error('ineligible-order');
        let estimate=order.preparationMinutes*60000;
        if(order.status==='Pending') {
          const savedStats=await tx.get(preparationStatsRef(db,order.vendorUid));
          if(savedStats.exists()) {
            const stats=savedStats.data();
            if(!validStats(order.vendorUid,stats)) throw new Error('malformed-preparation-stats');
            estimate=Math.floor((stats.totalDurationMillis+stats.sampleCount-1)/stats.sampleCount);
          }
        }
        progressWrites(tx,db,order,queue,estimate);
      },{maxAttempts});
      break;
    } catch(error) {
      if(error?.code!=='permission-denied'||observedQueueRevision===undefined||attempt===4) throw error;
      const currentOrder=await getDocFromServer(orderRef(db,expected.orderId));
      if(currentOrder.data()?.status!==expected.status||
         (currentOrder.data()?.statusRevision??0)!==(expected.statusRevision??0)) throw new Error('stale-order');
      const currentQueue=await getDocFromServer(queueRef(db,expected.vendorUid));
      const queue=currentQueue.data();
      if(currentQueue.metadata.hasPendingWrites||!queue||(queue.revision??0)<=observedQueueRevision) throw error;
      // Only a server-confirmed cursor revision advance justifies retrying the
      // guarded transition. The order checks above still enforce FCFS/staleness.
    }
  }
  const confirmed=await getDocFromServer(orderRef(db,expected.orderId));
  if(confirmed.metadata.hasPendingWrites) throw new Error('unconfirmed-order');
  if(confirmed.data()?.status==='Ready'&&confirmed.data()?.preparationSampleRecorded!==true)
    await recordPreparationSample(db,confirmed.data());
  return confirmed.data();
}
