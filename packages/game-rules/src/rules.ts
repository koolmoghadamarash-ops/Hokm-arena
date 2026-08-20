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
