// Persistent agent state (JSON file): price history, positions, decision log.
// Positions track entry price + size so the strategy can stop-loss and the
// dashboard can show P&L. The on-chain DecisionLogged events are the source
// of truth for what the agent did; this file is the off-chain mirror.
import { readFileSync, writeFileSync, existsSync } from "node:fs";

export function loadState(file) {
  if (existsSync(file)) {
    try {
      return JSON.parse(readFileSync(file, "utf8"));
    } catch {
      // fall through to fresh state
    }
  }
  return { history: {}, positions: {}, decisions: [], trades: [], startedAt: new Date().toISOString() };
}

export function saveState(file, state) {
  writeFileSync(file, JSON.stringify(state, null, 2));
}

export function pushClose(state, symbol, price, maxLen = 200) {
  state.history[symbol] ??= [];
  const last = state.history[symbol][state.history[symbol].length - 1];
  // One sample per cycle; skip exact duplicates of the last close.
  if (last !== price) state.history[symbol].push(price);
  if (state.history[symbol].length > maxLen) {
    state.history[symbol] = state.history[symbol].slice(-maxLen);
  }
}

export function recordDecision(state, d) {
  state.decisions.unshift({ ...d, at: new Date().toISOString() });
  state.decisions = state.decisions.slice(0, 200);
}

export function recordTrade(state, t) {
  state.trades.unshift({ ...t, at: new Date().toISOString() });
  state.trades = state.trades.slice(0, 200);
}
