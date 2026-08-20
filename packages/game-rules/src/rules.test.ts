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
