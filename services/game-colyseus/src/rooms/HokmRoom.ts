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
