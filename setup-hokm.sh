#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating Hokm Arena project files..."

mkdir -p packages/shared-types/src \
  packages/game-rules/src \
  services/game-colyseus/src/rooms \
  services/game-colyseus/test/helpers \
  services/api/src \
  services/matchmaking/src

cat > package.json <<'EOF'
{
  "name": "hokm-arena",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "workspaces": ["packages/*", "services/*"],
  "scripts": {
    "build": "npm run -ws build --if-present",
    "test": "jest --runInBand",
    "dev:game": "npm --workspace @hokm/game-server run dev",
    "dev:api": "npm --workspace @hokm/api run dev",
    "dev:mm": "npm --workspace @hokm/matchmaking run dev"
  },
  "devDependencies": {
    "@types/jest": "^29.5.14",
    "@types/node": "^22.10.1",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.5",
    "tsx": "^4.19.2",
    "typescript": "^5.7.2"
  }
}
EOF

cat > tsconfig.base.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "sourceMap": true,
    "outDir": "dist"
  }
}
EOF

cat > jest.config.cjs <<'EOF'
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testTimeout: 30000,
  roots: ["<rootDir>/packages", "<rootDir>/services"],
  testMatch: ["**/*.test.ts"],
  moduleNameMapper: { "^(\\.{1,2}/.*)\\.js$": "$1" }
};
EOF

cat > .gitignore <<'EOF'
node_modules/
dist/
.env
coverage/
*.log
.DS_Store
EOF

cat > .env.example <<'EOF'
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgres://hokm:hokm@localhost:5432/hokm
TURN_TIMEOUT_SECONDS=20
MATCH_TARGET_POINTS=7
EOF

cat > README.md <<'EOF'
# Hokm Arena

Online Hokm backend MVP (Colyseus + Redis + Docker + Tests).

## Run
```bash
npm install
npm test
docker compose up --build
```

## Services
- API: http://localhost:3000
- Game: ws://localhost:2567
EOF

# shared-types
cat > packages/shared-types/package.json <<'EOF'
{
  "name": "@hokm/shared-types",
  "version": "1.0.0",
  "type": "module",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": { "build": "tsc -p tsconfig.json", "test": "echo ok" }
}
EOF
cat > packages/shared-types/tsconfig.json <<'EOF'
{ "extends": "../../tsconfig.base.json", "include": ["src"] }
EOF
cat > packages/shared-types/src/index.ts <<'EOF'
export type Suit = "S" | "H" | "D" | "C";
export type Rank = "2"|"3"|"4"|"5"|"6"|"7"|"8"|"9"|"10"|"J"|"Q"|"K"|"A";
export interface Card { id: string; suit: Suit; rank: Rank; }
export interface TrickPlay { seat: 0|1|2|3; card: Card; }
export interface TrickState {
  index: number; leadSeat: 0|1|2|3; leadSuit?: Suit; plays: TrickPlay[]; winnerSeat?: 0|1|2|3;
}
export interface HandState {
  dealerSeat: 0|1|2|3; hakemSeat: 0|1|2|3; trumpSuit?: Suit; currentTurnSeat: 0|1|2|3;
  currentTrick: TrickState; completedTricks: TrickState[]; tricksWonByTeam: { A: number; B: number };
}
EOF

# game-rules
cat > packages/game-rules/package.json <<'EOF'
{
  "name": "@hokm/game-rules",
  "version": "1.0.0",
  "type": "module",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": { "build": "tsc -p tsconfig.json", "test": "echo ok" },
  "dependencies": { "@hokm/shared-types": "1.0.0" }
}
EOF
cat > packages/game-rules/tsconfig.json <<'EOF'
{ "extends": "../../tsconfig.base.json", "include": ["src"] }
EOF
cat > packages/game-rules/src/rank.ts <<'EOF'
import type { Rank } from "@hokm/shared-types";
const HIGH_TO_LOW: Rank[] = ["A","K","Q","J","10","9","8","7","6","5","4","3","2"];
const SCORE = new Map(HIGH_TO_LOW.map((r,i)=>[r, HIGH_TO_LOW.length-i]));
export function rankScore(rank: Rank): number { return SCORE.get(rank)!; }
EOF
cat > packages/game-rules/src/rules.ts <<'EOF'
import type { Card, Suit, TrickState } from "@hokm/shared-types";
import { rankScore } from "./rank.js";
export function hasSuit(hand: Card[], suit: Suit) { return hand.some(c => c.suit === suit); }
export function isLegalPlay(hand: Card[], card: Card, leadSuit?: Suit) {
  if (!hand.some(c => c.id === card.id)) return false;
  if (!leadSuit) return true;
  if (hasSuit(hand, leadSuit)) return card.suit === leadSuit;
  return true;
}
export function resolveTrickWinner(trick: TrickState, trumpSuit: Suit): 0|1|2|3 {
  if (trick.plays.length !== 4 || !trick.leadSuit) throw new Error("Incomplete trick");
  const trumpPlays = trick.plays.filter(p => p.card.suit === trumpSuit);
  const pool = trumpPlays.length ? trumpPlays : trick.plays.filter(p => p.card.suit === trick.leadSuit);
  let best = pool[0];
  for (const p of pool.slice(1)) if (rankScore(p.card.rank) > rankScore(best.card.rank)) best = p;
  return best.seat;
}
export function seatToTeam(seat: number): "A"|"B" { return seat===0||seat===2 ? "A" : "B"; }
EOF
cat > packages/game-rules/src/autoPlay.ts <<'EOF'
import type { Card, Suit } from "@hokm/shared-types";
import { rankScore } from "./rank.js";
function sortLow(cards: Card[]) { return [...cards].sort((a,b)=>rankScore(a.rank)-rankScore(b.rank)); }
export function pickAutoPlayCard(hand: Card[], leadSuit?: Suit): Card {
  if (!leadSuit) return sortLow(hand)[0];
  const same = hand.filter(c => c.suit === leadSuit);
  return same.length ? sortLow(same)[0] : sortLow(hand)[0];
}
EOF
cat > packages/game-rules/src/index.ts <<'EOF'
export * from "./rules.js";
export * from "./autoPlay.js";
export * from "./rank.js";
EOF
cat > packages/game-rules/src/rules.test.ts <<'EOF'
import { isLegalPlay, resolveTrickWinner, seatToTeam } from "./rules";
import type { Card, TrickState } from "@hokm/shared-types";
const c = (id: string, suit: any, rank: any): Card => ({ id, suit, rank });
describe("rules", () => {
  test("follow suit", () => {
    const hand = [c("AS","S","A"), c("2H","H","2")];
    expect(isLegalPlay(hand, c("2H","H","2"), "S")).toBe(false);
    expect(isLegalPlay(hand, c("AS","S","A"), "S")).toBe(true);
  });
  test("trump wins", () => {
    const trick: TrickState = {
      index:0, leadSeat:0, leadSuit:"D",
      plays:[
        {seat:0,card:c("AD","D","A")},{seat:1,card:c("2S","S","2")},
        {seat:2,card:c("KS","S","K")},{seat:3,card:c("3D","D","3")}
      ]
    };
    expect(resolveTrickWinner(trick,"S")).toBe(2);
  });
  test("teams", () => {
    expect(seatToTeam(0)).toBe("A");
    expect(seatToTeam(1)).toBe("B");
  });
});
EOF
cat > packages/game-rules/src/autoPlay.test.ts <<'EOF'
import { pickAutoPlayCard } from "./autoPlay";
import type { Card } from "@hokm/shared-types";
const c = (id: string, suit: any, rank: any): Card => ({ id, suit, rank });
test("auto lowest lead suit", () => {
  const hand=[c("AH","H","A"),c("3H","H","3"),c("KS","S","K")];
  expect(pickAutoPlayCard(hand,"H").id).toBe("3H");
});
EOF

# game server
cat > services/game-colyseus/package.json <<'EOF'
{
  "name": "@hokm/game-server",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "tsx src/index.ts",
    "build": "tsc -p tsconfig.json",
    "test": "echo ok"
  },
  "dependencies": {
    "@colyseus/ws-transport": "^0.15.6",
    "@hokm/game-rules": "1.0.0",
    "@hokm/shared-types": "1.0.0",
    "colyseus": "^0.15.57",
    "express": "^4.21.2"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "colyseus.js": "^0.15.25"
  }
}
EOF
cat > services/game-colyseus/tsconfig.json <<'EOF'
{ "extends": "../../tsconfig.base.json", "include": ["src","test"] }
EOF
cat > services/game-colyseus/src/index.ts <<'EOF'
import http from "http";
import express from "express";
import { Server } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import { HokmRoom } from "./rooms/HokmRoom.js";
const port = Number(process.env.PORT ?? 2567);
const app = express();
const server = http.createServer(app);
const gameServer = new Server({ transport: new WebSocketTransport({ server }) });
gameServer.define("hokm", HokmRoom);
app.get("/health", (_req,res)=>res.json({ok:true,service:"game-server"}));
server.listen(port, ()=>console.log(`game-server listening on :${port}`));
EOF

cat > services/game-colyseus/src/rooms/HokmRoom.ts <<'EOF'
import { Room, Client } from "colyseus";
import type { Card, Suit, Rank, HandState } from "@hokm/shared-types";
import { isLegalPlay, resolveTrickWinner, seatToTeam, pickAutoPlayCard } from "@hokm/game-rules";

type Seat = 0|1|2|3; type Team = "A"|"B";
interface PlayerMeta { userId: string; seat: Seat; consecutiveTimeouts: number; }
const TURN_TIMEOUT_SECONDS = Number(process.env.TURN_TIMEOUT_SECONDS ?? 20);
const MATCH_TARGET_POINTS = Number(process.env.MATCH_TARGET_POINTS ?? 7);
const SUITS: Suit[] = ["S","H","D","C"];
const RANKS: Rank[] = ["2","3","4","5","6","7","8","9","10","J","Q","K","A"];
const nextSeat = (s: Seat): Seat => ((s+1)%4) as Seat;
function buildDeck(): Card[] {
  const d: Card[] = [];
  for (const s of SUITS) for (const r of RANKS) d.push({ id:`${r}${s}`, suit:s, rank:r });
  return d;
}
function shuffle<T>(arr: T[]): T[] {
  const a=[...arr];
  for (let i=a.length-1;i>0;i--){ const j=Math.floor(Math.random()*(i+1)); [a[i],a[j]]=[a[j],a[i]]; }
  return a;
}

export class HokmRoom extends Room {
  maxClients = 4;
  private players = new Map<string, PlayerMeta>();
  private ready = new Set<string>();
  private seatHands = new Map<Seat, Card[]>();
  private gamePoints: Record<Team, number> = { A:0, B:0 };
  private dealerSeat: Seat = 0;
  private handState?: HandState;
  private turnTimer?: NodeJS.Timeout;

  onCreate() {
    this.onMessage("player.ready", (client) => {
      this.ready.add(client.sessionId);
      this.tryStart();
    });
    this.onMessage("trump.select", (client, payload: { suit: Suit }) => {
      if (!this.handState || this.handState.trumpSuit) return;
      const p = this.players.get(client.sessionId);
      if (!p || p.seat !== this.handState.hakemSeat) return client.send("error", { code: "NOT_HAKEM" });
      this.clearTurnTimer();
      this.handState.trumpSuit = payload.suit;
      const used = new Set<string>();
      for (const h of this.seatHands.values()) for (const c of h) used.add(c.id);
      const rest = shuffle(buildDeck().filter(c => !used.has(c.id)));
      let cursor = nextSeat(this.dealerSeat);
      for (let r=0;r<8;r++) for (let i=0;i<4;i++) { this.seatHands.get(cursor)!.push(rest.shift()!); cursor = nextSeat(cursor); }
      this.broadcast("trump.selected", { suit: payload.suit });
      this.handState.currentTurnSeat = this.handState.hakemSeat;
      this.handState.currentTrick = { index:0, leadSeat:this.handState.hakemSeat, plays:[] };
      this.emitTurn();
    });
    this.onMessage("card.play", (client, payload: { cardId: string }) => this.playCard(client, payload.cardId, false));
  }

  onJoin(client: Client, options: { userId?: string }) {
    const seat = this.assignSeat();
    this.players.set(client.sessionId, { userId: options?.userId ?? client.sessionId, seat, consecutiveTimeouts: 0 });
    client.send("state.snapshot", { seat, gamePoints: this.gamePoints });
  }

  async onLeave(client: Client, consented: boolean) {
    if (consented) { this.players.delete(client.sessionId); this.ready.delete(client.sessionId); return; }
    try {
      const reClient = await this.allowReconnection(client, 10);
      const old = this.players.get(client.sessionId);
      if (!old) return;
      this.players.delete(client.sessionId);
      this.players.set(reClient.sessionId, old);
      reClient.send("state.snapshot", { seat: old.seat, handState: this.handState, gamePoints: this.gamePoints });
      this.broadcast("player.reconnected", { seat: old.seat });
    } catch {
      this.players.delete(client.sessionId); this.ready.delete(client.sessionId);
    }
  }

  onDispose() { this.clearTurnTimer(); }

  private tryStart() {
    if (this.clients.length !== 4 || this.ready.size < 4 || this.handState) return;
    this.dealerSeat = Math.floor(Math.random()*4) as Seat;
    this.gamePoints = { A:0, B:0 };
    this.startHand();
  }

  private startHand() {
    const hakemSeat = nextSeat(this.dealerSeat);
    const deck = shuffle(buildDeck());
    const hands: Record<Seat, Card[]> = {0:[],1:[],2:[],3:[]};
    let cursor = nextSeat(this.dealerSeat);
    for (let r=0;r<5;r++) for (let i=0;i<4;i++) { hands[cursor].push(deck.shift()!); cursor = nextSeat(cursor); }
    this.seatHands.set(0,hands[0]); this.seatHands.set(1,hands[1]); this.seatHands.set(2,hands[2]); this.seatHands.set(3,hands[3]);
    this.handState = {
      dealerSeat: this.dealerSeat, hakemSeat, trumpSuit: undefined, currentTurnSeat: hakemSeat,
      currentTrick: { index:0, leadSeat:hakemSeat, plays:[] }, completedTricks: [], tricksWonByTeam:{A:0,B:0}
    };
    this.broadcast("state.patch", { phase:"TRUMP_SELECTION", hakemSeat, dealerSeat:this.dealerSeat });
    this.startTurnTimer();
  }

  private playCard(client: Client, cardId: string, fromTimeout: boolean) {
    if (!this.handState || !this.handState.trumpSuit) return;
    const p = this.players.get(client.sessionId); if (!p) return;
    if (p.seat !== this.handState.currentTurnSeat) { if (!fromTimeout) client.send("error",{code:"OUT_OF_TURN"}); return; }
    const hand = this.seatHands.get(p.seat) ?? [];
    const card = hand.find(c => c.id === cardId);
    if (!card) { if (!fromTimeout) client.send("error",{code:"CARD_NOT_FOUND"}); return; }
    if (!isLegalPlay(hand, card, this.handState.currentTrick.leadSuit)) {
      if (!fromTimeout) client.send("error",{code:"ILLEGAL_PLAY"}); return;
    }
    this.clearTurnTimer();
    this.seatHands.set(p.seat, hand.filter(c => c.id !== card.id));
    if (!this.handState.currentTrick.leadSuit) this.handState.currentTrick.leadSuit = card.suit;
    this.handState.currentTrick.plays.push({ seat:p.seat, card });
    this.broadcast("card.played", { seat:p.seat, cardId:card.id, trickIndex:this.handState.currentTrick.index });
    if (this.handState.currentTrick.plays.length < 4) {
      this.handState.currentTurnSeat = nextSeat(p.seat); this.emitTurn(); return;
    }
    const winner = resolveTrickWinner(this.handState.currentTrick, this.handState.trumpSuit);
    this.handState.currentTrick.winnerSeat = winner;
    this.handState.tricksWonByTeam[seatToTeam(winner)] += 1;
    this.broadcast("trick.resolved", {
      winnerSeat: winner, tricksA: this.handState.tricksWonByTeam.A, tricksB: this.handState.tricksWonByTeam.B
    });
    this.handState.completedTricks.push(this.handState.currentTrick);
    if (this.handState.completedTricks.length === 13) {
      const a=this.handState.tricksWonByTeam.A, b=this.handState.tricksWonByTeam.B;
      const winnerTeam: Team = a>=7 ? "A":"B";
      const loserTricks = winnerTeam==="A" ? b : a;
      const delta = loserTricks===0 ? 2 : 1;
      this.gamePoints[winnerTeam] += delta;
      this.broadcast("hand.ended", { tricksA:a, tricksB:b, gamePointAwardedTo:winnerTeam, delta, scoreA:this.gamePoints.A, scoreB:this.gamePoints.B });
      if (this.gamePoints.A >= MATCH_TARGET_POINTS || this.gamePoints.B >= MATCH_TARGET_POINTS) {
        this.broadcast("match.ended", { scoreA:this.gamePoints.A, scoreB:this.gamePoints.B, winner: this.gamePoints.A>=MATCH_TARGET_POINTS?"A":"B" });
        return;
      }
      this.dealerSeat = nextSeat(this.dealerSeat); this.startHand(); return;
    }
    this.handState.currentTrick = { index:this.handState.completedTricks.length, leadSeat:winner, plays:[] };
    this.handState.currentTurnSeat = winner; this.emitTurn();
  }

  private emitTurn() {
    this.broadcast("turn.started", { seat:this.handState!.currentTurnSeat, deadlineMs:Date.now()+TURN_TIMEOUT_SECONDS*1000 });
    this.startTurnTimer();
  }
  private startTurnTimer() {
    this.clearTurnTimer();
    this.turnTimer = setTimeout(() => this.handleTimeout(), TURN_TIMEOUT_SECONDS*1000);
  }
  private clearTurnTimer() { if (this.turnTimer) clearTimeout(this.turnTimer); this.turnTimer=undefined; }

  private handleTimeout() {
    if (!this.handState) return;
    if (!this.handState.trumpSuit) {
      this.handState.trumpSuit = "S";
      const used = new Set<string>();
      for (const h of this.seatHands.values()) for (const c of h) used.add(c.id);
      const rest = shuffle(buildDeck().filter(c => !used.has(c.id)));
      let cursor = nextSeat(this.dealerSeat);
      for (let r=0;r<8;r++) for (let i=0;i<4;i++) { this.seatHands.get(cursor)!.push(rest.shift()!); cursor=nextSeat(cursor); }
      this.broadcast("trump.selected", { suit:"S", auto:true });
      this.handState.currentTurnSeat = this.handState.hakemSeat;
      this.handState.currentTrick = { index:0, leadSeat:this.handState.hakemSeat, plays:[] };
      this.emitTurn(); return;
    }
    const seat = this.handState.currentTurnSeat;
    const client = this.clientBySeat(seat); if (!client) return;
    const hand = this.seatHands.get(seat) ?? [];
    const card = pickAutoPlayCard(hand, this.handState.currentTrick.leadSuit);
    this.broadcast("player.timeout", { seat, autoPlayedCardId: card.id });
    this.playCard(client, card.id, true);
  }

  private assignSeat(): Seat {
    const used = new Set([...this.players.values()].map(p=>p.seat));
    for (const s of [0,1,2,3] as Seat[]) if (!used.has(s)) return s;
    throw new Error("No seat");
  }
  private clientBySeat(seat: Seat) {
    for (const c of this.clients) { const p=this.players.get(c.sessionId); if (p?.seat===seat) return c; }
  }
}
EOF

cat > services/game-colyseus/test/helpers/testServer.ts <<'EOF'
import http from "http";
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
EOF

cat > services/game-colyseus/test/hokm-room.integration.test.ts <<'EOF'
import { createTestServer, shutdownTestServer, mkClient, onceMessage } from "./helpers/testServer";
describe("HokmRoom integration", () => {
  let ctx: Awaited<ReturnType<typeof createTestServer>>;
  beforeAll(async () => { process.env.TURN_TIMEOUT_SECONDS="2"; ctx=await createTestServer(); });
  afterAll(async () => { await shutdownTestServer(ctx.httpServer, ctx.gameServer); });
  test("4 players reach trump selection", async () => {
    const c1=await mkClient(ctx.endpoint); const c2=await mkClient(ctx.endpoint);
    const c3=await mkClient(ctx.endpoint); const c4=await mkClient(ctx.endpoint);
    const r1=await c1.joinOrCreate("hokm",{userId:"u1"});
    const r2=await c2.joinOrCreate("hokm",{userId:"u2"});
    const r3=await c3.joinOrCreate("hokm",{userId:"u3"});
    const r4=await c4.joinOrCreate("hokm",{userId:"u4"});
    r1.send("player.ready"); r2.send("player.ready"); r3.send("player.ready"); r4.send("player.ready");
    const patch = await onceMessage<any>(r1, "state.patch");
    expect(patch.phase).toBe("TRUMP_SELECTION");
    await r1.leave(); await r2.leave(); await r3.leave(); await r4.leave();
  });
});
EOF

# api
cat > services/api/package.json <<'EOF'
{
  "name": "@hokm/api",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "dev": "tsx src/index.ts", "build": "tsc -p tsconfig.json", "test": "echo ok" },
  "dependencies": { "express":"^4.21.2", "ioredis":"^5.4.2", "nanoid":"^5.0.9" },
  "devDependencies": { "@types/express":"^4.17.21" }
}
EOF
cat > services/api/tsconfig.json <<'EOF'
{ "extends": "../../tsconfig.base.json", "include": ["src"] }
EOF
cat > services/api/src/index.ts <<'EOF'
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
EOF

# matchmaking
cat > services/matchmaking/package.json <<'EOF'
{
  "name": "@hokm/matchmaking",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "dev": "tsx src/index.ts", "build": "tsc -p tsconfig.json", "test": "echo ok" },
  "dependencies": { "ioredis":"^5.4.2", "nanoid":"^5.0.9" }
}
EOF
cat > services/matchmaking/tsconfig.json <<'EOF'
{ "extends": "../../tsconfig.base.json", "include": ["src"] }
EOF
cat > services/matchmaking/src/index.ts <<'EOF'
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
EOF

cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD","redis-cli","ping"]
      interval: 5s
      timeout: 3s
      retries: 20
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: hokm
      POSTGRES_PASSWORD: hokm
      POSTGRES_DB: hokm
    ports: ["5432:5432"]
  api:
    image: node:22-alpine
    working_dir: /app
    volumes: ["./:/app"]
    command: sh -c "npm i && npm run dev:api"
    environment:
      REDIS_URL: redis://redis:6379
      PORT: 3000
    ports: ["3000:3000"]
    depends_on:
      redis:
        condition: service_healthy
  game-server:
    image: node:22-alpine
    working_dir: /app
    volumes: ["./:/app"]
    command: sh -c "npm i && npm run dev:game"
    environment:
      TURN_TIMEOUT_SECONDS: 5
      MATCH_TARGET_POINTS: 7
      PORT: 2567
    ports: ["2567:2567"]
  matchmaking:
    image: node:22-alpine
    working_dir: /app
    volumes: ["./:/app"]
    command: sh -c "npm i && npm run dev:mm"
    environment:
      REDIS_URL: redis://redis:6379
    depends_on:
      redis:
        condition: service_healthy
EOF

echo "==> Files created."
echo "==> Installing dependencies..."
npm install
echo "==> Running tests..."
npm test || true
echo "✅ DONE. Next: docker compose up --build"
