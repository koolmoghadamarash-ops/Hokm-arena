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
