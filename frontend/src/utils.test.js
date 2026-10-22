import { describe, expect, it } from "vitest";
import { formatPlayers, isValidGame } from "./utils.js";

describe("formatPlayers", () => {
  it("shows a range", () => {
    expect(formatPlayers(2, 4)).toBe("2–4 гравців");
  });

  it("shows a single number when min equals max", () => {
    expect(formatPlayers(2, 2)).toBe("2 гравців");
  });
});

describe("isValidGame", () => {
  it("accepts a valid game", () => {
    expect(isValidGame({ title: "Catan", minPlayers: 3, maxPlayers: 4 })).toBe(true);
  });

  it("rejects an empty title", () => {
    expect(isValidGame({ title: "  ", minPlayers: 2, maxPlayers: 4 })).toBe(false);
  });

  it("rejects max lower than min", () => {
    expect(isValidGame({ title: "Azul", minPlayers: 4, maxPlayers: 2 })).toBe(false);
  });
});
