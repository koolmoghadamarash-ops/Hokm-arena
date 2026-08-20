import * as http from "http";
import { Server } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import { Client } from "colyseus.js";
import { HokmRoom } from "../../src/rooms/HokmRoom";
export async function createTestServer() {
  const httpServer = http.createServer();
  const gameServer = new Server({ transport: new WebSocketTransport({ server: httpServer }) });
  gameServer.define("hokm", HokmRoom);
  await new Promise<void>(r => httpServer.listen(0, r));
  const address = httpServer.address();
  if (!address || typeof address === "string") throw new Error("address failed");
  return { httpServer, gameServer, endpoint: `ws://127.0.0.1:${address.port}` };
}
export async function shutdownTestServer(httpServer: http.Server, gameServer: Server) {
  await gameServer.gracefullyShutdown();
  await new Promise<void>((resolve, reject) => httpServer.close(e => e ? reject(e) : resolve()));
}
export function onceMessage<T=any>(room:any, type:string, timeoutMs=5000): Promise<T> {
  return new Promise((resolve,reject)=>{
    const t=setTimeout(()=>reject(new Error(`timeout waiting ${type}`)), timeoutMs);
    room.onMessage(type,(msg:T)=>{ clearTimeout(t); resolve(msg); });
  });
}
export async function mkClient(endpoint:string){ return new Client(endpoint); }
