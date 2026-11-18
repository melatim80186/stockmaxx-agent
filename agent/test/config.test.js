import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { loadConfig } from "../src/config.js";

// Regression: STOP_LOSS_BPS defaulted to -500 while strategy.js negates it
// (pnlBps <= -cfg.stopLossBps), so EVERY position sold the next cycle.
// The default must be a positive magnitude.
describe("config defaults", () => {
  it("stopLossBps is a positive magnitude (500 = 5%)", () => {
    delete process.env.STOP_LOSS_BPS;
    const cfg = loadConfig([]);
    assert.equal(cfg.stopLossBps, 500);
    assert.ok(cfg.stopLossBps > 0);
  });
  it("momentum thresholds have the documented signs", () => {
    const cfg = loadConfig([]);
    assert.ok(cfg.momentumBuyBps > 0);
    assert.ok(cfg.momentumSellBps < 0);
  });
});
