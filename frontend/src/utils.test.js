import { describe, expect, it } from "vitest";
import { footerText, formatPlayers, isValidGame, shelfStats, statsText } from "./utils.js";

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

describe("footerText", () => {
  it("shows web and api versions with the pod name", () => {
    const info = { version: "1.1.0", instance: "backend-abc", maxBorrowDays: 7 };
    expect(footerText("1.1.0", info)).toBe("web v1.1.0 · API v1.1.0 · под backend-abc · видача до 7 дн.");
  });

  it("handles a missing API", () => {
    expect(footerText(undefined, null)).toBe("web vdev · API недоступне");
  });
});

describe("shelfStats", () => {
  it("counts total, borrowed and available games", () => {
    const games = [{ isBorrowed: true }, { isBorrowed: false }, { isBorrowed: false }];
    expect(shelfStats(games)).toEqual({ total: 3, borrowed: 1, available: 2 });
  });

  it("formats the stats line", () => {
    expect(statsText({ total: 0, borrowed: 0, available: 0 })).toBe("На полиці: 0 · доступно: 0 · видано: 0");
  });
});
