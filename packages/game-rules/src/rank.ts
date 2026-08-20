import type { Rank } from "@hokm/shared-types";
const HIGH_TO_LOW: Rank[] = ["A","K","Q","J","10","9","8","7","6","5","4","3","2"];
const SCORE = new Map(HIGH_TO_LOW.map((r,i)=>[r, HIGH_TO_LOW.length-i]));
export function rankScore(rank: Rank): number { return SCORE.get(rank)!; }
