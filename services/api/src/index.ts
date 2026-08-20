import express from "express";
import Redis from "ioredis";
import { nanoid } from "nanoid";
const app = express(); app.use(express.json());
const redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");
const REGION="me";
app.get("/health", (_req,res)=>res.json({ok:true,service:"api"}));
app.post("/matchmaking/enqueue", async (req,res)=>{
  const userId=String(req.body.userId??""); const elo=Number(req.body.elo??1200);
  if(!userId) return res.status(400).json({error:"userId required"});
  const ticketId=nanoid(); const now=Date.now();
  await redis.hset(`mm:ticket:${ticketId}`,{ticketId,userId,elo:String(elo),createdAt:String(now),status:"queued"});
  await redis.zadd(`mm:queue:solo:${REGION}`, now, ticketId);
  res.json({ok:true,ticketId});
});
app.post("/matchmaking/cancel", async (req,res)=>{
  const ticketId=String(req.body.ticketId??"");
  if(!ticketId) return res.status(400).json({error:"ticketId required"});
  await redis.zrem(`mm:queue:solo:${REGION}`, ticketId);
  await redis.hset(`mm:ticket:${ticketId}`, {status:"cancelled"});
  res.json({ok:true});
});
const port=Number(process.env.PORT??3000);
app.listen(port, ()=>console.log(`api listening on :${port}`));
