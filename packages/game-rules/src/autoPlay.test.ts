import { pickAutoPlayCard } from "./autoPlay";
import type { Card } from "@hokm/shared-types";
const c = (id: string, suit: any, rank: any): Card => ({ id, suit, rank });
test("auto lowest lead suit", () => {
  const hand=[c("AH","H","A"),c("3H","H","3"),c("KS","S","K")];
  expect(pickAutoPlayCard(hand,"H").id).toBe("3H");
});
