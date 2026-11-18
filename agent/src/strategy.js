// Strategy engine — pure functions, no I/O, fully unit-tested.
// Rule set (documented in README):
//   BUY  when flat AND fast SMA > slow SMA AND momentum > +threshold
//   SELL when holding AND (fast SMA < slow SMA OR momentum < threshold
//        OR price < entry * (1 - stopLoss))
//   HOLD otherwise.
// Confidence is a bounded function of momentum strength (50-95%).
// The agent NEVER trades on a single tick: it needs slowPeriod closes.

export function sma(values, period) {
  if (!values || values.length < period) return null;
  const slice = values.slice(-period);
  return slice.reduce((a, b) => a + b, 0) / period;
}

export function momentumBps(values, lookback) {
  if (!values || values.length <= lookback) return null;
  const now = values[values.length - 1];
  const then = values[values.length - 1 - lookback];
  if (!then) return null;
  return ((now - then) / then) * 10000;
}

/// @param closes number[] — oldest..newest closes for one symbol
/// @param position { entryPrice: number|null, size: number } — current holding
/// @param cfg strategy knobs
/// @returns { action: 'BUY'|'SELL'|'HOLD', confidenceBps, reason, fast, slow, momentumBps }
export function decide(closes, position, cfg) {
  const fast = sma(closes, cfg.fastPeriod);
  const slow = sma(closes, cfg.slowPeriod);
  const mom = momentumBps(closes, cfg.slowPeriod);
  const price = closes[closes.length - 1];
  const base = { fast, slow, momentumBps: mom, price };

  if (fast === null || slow === null || mom === null) {
    return { ...base, action: "HOLD", confidenceBps: 0, reason: `warming up: need ${cfg.slowPeriod} closes, have ${closes.length}` };
  }

  const holding = position && position.size > 0 && position.entryPrice;
  if (holding) {
    const pnlBps = ((price - position.entryPrice) / position.entryPrice) * 10000;
    if (pnlBps <= -cfg.stopLossBps) {
      return { ...base, action: "SELL", confidenceBps: 9000, reason: `stop-loss: ${pnlBps.toFixed(0)} bps vs entry $${position.entryPrice}` };
    }
    if (fast < slow) {
      return { ...base, action: "SELL", confidenceBps: 7500, reason: `trend flip: SMA${cfg.fastPeriod} ${fast.toFixed(2)} < SMA${cfg.slowPeriod} ${slow.toFixed(2)}` };
    }
    if (mom <= cfg.momentumSellBps) {
      return { ...base, action: "SELL", confidenceBps: 7000, reason: `momentum ${mom.toFixed(0)} bps <= ${cfg.momentumSellBps} bps` };
    }
    return { ...base, action: "HOLD", confidenceBps: 6000, reason: `holding: trend up, momentum ${mom.toFixed(0)} bps` };
  }

  if (fast > slow && mom > cfg.momentumBuyBps) {
    const confidenceBps = Math.min(9500, Math.max(5000, 5000 + Math.round(mom * 10)));
    return { ...base, action: "BUY", confidenceBps, reason: `SMA${cfg.fastPeriod} ${fast.toFixed(2)} > SMA${cfg.slowPeriod} ${slow.toFixed(2)}, momentum +${mom.toFixed(0)} bps` };
  }
  return { ...base, action: "HOLD", confidenceBps: 5000, reason: `no setup: SMA${cfg.fastPeriod} ${fast?.toFixed(2)} vs SMA${cfg.slowPeriod} ${slow?.toFixed(2)}, momentum ${mom?.toFixed(0)} bps` };
}
