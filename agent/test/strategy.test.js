import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { sma, momentumBps, decide } from "../src/strategy.js";

const CFG = { fastPeriod: 3, slowPeriod: 8, momentumBuyBps: 50, momentumSellBps: -100, stopLossBps: 500 };

describe("sma", () => {
  it("needs a full window", () => {
    assert.equal(sma([1, 2], 3), null);
    assert.equal(sma([1, 2, 3], 3), 2);
    assert.equal(sma([1, 2, 3, 4], 3), 3);
  });
});

describe("momentumBps", () => {
  it("computes basis-point change", () => {
    assert.equal(momentumBps([100, 101, 102, 103, 104, 105, 106, 107, 108], 8), 800);
  });
  it("returns null when too short", () => {
    assert.equal(momentumBps([100, 101], 8), null);
  });
});

describe("decide", () => {
  it("HOLDs while warming up", () => {
    const d = decide([150, 151, 152], { entryPrice: null, size: 0 }, CFG);
    assert.equal(d.action, "HOLD");
    assert.match(d.reason, /warming up/);
  });
  it("BUYs a clean uptrend", () => {
    const closes = [150, 151, 152, 153, 154, 155, 156, 157, 158];
    const d = decide(closes, { entryPrice: null, size: 0 }, CFG);
    assert.equal(d.action, "BUY");
    assert.ok(d.confidenceBps >= 5000 && d.confidenceBps <= 9500);
  });
  it("does not BUY a flat market", () => {
    const closes = [150, 150, 150, 150, 150, 150, 150, 150, 150];
    assert.equal(decide(closes, { entryPrice: null, size: 0 }, CFG).action, "HOLD");
  });
  it("SELLs on a trend flip while holding", () => {
    const closes = [150, 152, 154, 156, 158, 160, 158, 155, 152, 149, 146];
    const d = decide(closes, { entryPrice: 155, size: 1 }, CFG);
    assert.equal(d.action, "SELL");
  });
  it("SELLs on stop-loss even before the trend flips", () => {
    // Slow grind down: SMA3 still above SMA8 briefly, but -6% vs entry.
    const closes = [160, 159, 158, 157, 156, 155, 154, 153, 152, 150.4];
    const d = decide(closes, { entryPrice: 160, size: 1 }, CFG);
    assert.equal(d.action, "SELL");
    assert.match(d.reason, /stop-loss/);
  });
  it("HOLDs a winning position in an uptrend", () => {
    const closes = [150, 151, 152, 153, 154, 155, 156, 157, 158];
    const d = decide(closes, { entryPrice: 152, size: 1 }, CFG);
    assert.equal(d.action, "HOLD");
  });
});
