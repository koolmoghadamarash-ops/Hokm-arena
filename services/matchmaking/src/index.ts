import Redis from "ioredis";
import { nanoid } from "nanoid";
const redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");
const REGION="me";
async function tick(){
  const key=`mm:queue:solo:${REGION}`;
  const ids=await redis.zrange(key,0,20);
  if(ids.length<4) return;
  const picked=ids.slice(0,4);
  const proposalId=nanoid();
  await redis.hset(`mm:proposed:${proposalId}`,{players:JSON.stringify(picked),status:"created",createdAt:String(Date.now())});
  await redis.zrem(key,...picked);
  console.log("proposal created",{proposalId,picked});
}
setInterval(()=>{ tick().catch(e=>console.error("mm tick error",e)); },1000);
console.log("matchmaking worker started");
