import type { Card, Suit } from "@hokm/shared-types";
import { rankScore } from "./rank.js";
function sortLow(cards: Card[]) { return [...cards].sort((a,b)=>rankScore(a.rank)-rankScore(b.rank)); }
export function pickAutoPlayCard(hand: Card[], leadSuit?: Suit): Card {
  if (!leadSuit) return sortLow(hand)[0];
  const same = hand.filter(c => c.suit === leadSuit);
  return same.length ? sortLow(same)[0] : sortLow(hand)[0];
}
