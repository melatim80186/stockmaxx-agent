// One agent cycle:
//   1. fetch live prices (Yahoo) + Base stock-index NAVs (Bankr, confirmation)
//   2. update the on-chain oracle with fresh prices
//   3. run the strategy per symbol, log EVERY decision on-chain (incl. HOLD)
//   4. execute BUY/SELL through the vault guardrails when signalled
//   5. persist state + print a machine-readable summary
//
// Demo mode (--demo): prices come from a fixed scripted series (labelled
// SYNTHETIC) so the full BUY -> HOLD -> SELL loop plays out in minutes
// against a local Anvil chain. Nothing in demo mode touches real markets.
import { loadConfig, SYMBOLS } from "./config.js";
import { fetchYahooPrices, fetchBankrIndexes } from "./prices.js";
import { decide } from "./strategy.js";
import { loadState, saveState, pushClose, recordDecision, recordTrade } from "./state.js";
import * as ex from "./executor.js";

// Scripted demo series (USD). NVDA rises 8 ticks (BUY setup) then falls
// hard (SELL via trend flip + stop-loss). Others drift sideways (HOLD).
const DEMO_SERIES = {
  NVDA: [150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 156, 150, 144, 140, 141, 142],
  AAPL: [350, 351, 350, 351, 350, 351, 350, 351, 350, 351, 350, 351, 350, 351, 350, 351],
  TSLA: [380, 382, 381, 383, 382, 384, 383, 385, 384, 386, 385, 387, 386, 388, 387, 389],
  MSFT: [505, 506, 505, 506, 505, 506, 505, 506, 505, 506, 505, 506, 505, 506, 505, 506],
  AMZN: [264, 265, 264, 265, 264, 265, 264, 265, 264, 265, 264, 265, 264, 265, 264, 265],
};

function demoPrices(state) {
  const tick = state.demoTick ?? 0;
  const out = {};
  for (const sym of SYMBOLS) {
    const series = DEMO_SERIES[sym];
    out[sym] = { price: series[Math.min(tick, series.length - 1)], source: "demo-synthetic" };
  }
  state.demoTick = tick + 1;
  return out;
}

export async function runCycle(cfg = loadConfig()) {
  if (!cfg.privateKey) throw new Error("AGENT_PRIVATE_KEY is not set (see agent/.env.example)");
  if (!cfg.addresses.vault || !cfg.addresses.oracle || !cfg.addresses.exchange) {
    throw new Error("Contract addresses missing: deploy first (forge script) or set *_ADDRESS env vars");
  }
  const state = loadState(cfg.stateFile);
  const cx = ex.connect(cfg);
  const summary = { mode: cfg.demo ? "demo" : "live", chainId: cfg.chainId, decisions: [], trades: [], errors: [] };

  // 1. Prices
  let quotes;
  if (cfg.demo) {
    quotes = demoPrices(state);
  } else {
    quotes = cfg.yahooEnabled ? await fetchYahooPrices() : {};
    summary.bankr = cfg.bankrEnabled ? await fetchBankrIndexes() : [];
  }
  const symbols = Object.keys(quotes);
  if (!symbols.length) {
    summary.errors.push("no prices fetched");
    saveState(cfg.stateFile, state);
    return summary;
  }

  // Seed history from Yahoo's daily closes on first run (live mode).
  for (const sym of symbols) {
    const q = quotes[sym];
    if (!cfg.demo && q.closes?.length > 1 && !(state.history[sym]?.length)) {
      state.history[sym] = [...q.closes];
    }
    pushClose(state, sym, q.price);
  }

  // 2. Oracle update (one tx for all symbols).
  try {
    const prices = Object.fromEntries(symbols.map((s) => [s, quotes[s].price]));
    const r = await ex.updateOraclePrices(cx, prices);
    summary.oracleTx = r.hash;
  } catch (e) {
    summary.errors.push(`oracle update failed: ${e.message}`);
  }

  // 3. Decide per symbol (pure strategy, no I/O).
  const recs = [];
  for (const sym of symbols) {
    const closes = state.history[sym] ?? [];
    const pos = state.positions[sym] ?? { entryPrice: null, size: 0 };
    const d = decide(closes, pos, cfg);
    const price = quotes[sym].price;
    recs.push({ symbol: sym, action: d.action, price, confidenceBps: d.confidenceBps, reason: d.reason, source: quotes[sym].source, tx: null });
  }

  // 4. Log the whole cycle's decisions on-chain in ONE tx (incl. HOLDs).
  try {
    const r = await ex.logDecisionsOnChain(cx, recs);
    for (const rec of recs) rec.tx = r.hash;
    summary.decisionTx = r.hash;
  } catch (e) {
    summary.errors.push(`logDecisions failed: ${e.message}`);
  }
  for (const rec of recs) {
    recordDecision(state, rec);
    summary.decisions.push(rec);
  }

  // 5. Execute BUY/SELL through the vault guardrails when signalled.
  let snap;
  try {
    snap = await ex.vaultSnapshot(cx, cfg);
  } catch (e) {
    summary.errors.push(`vault snapshot failed: ${e.message}`);
    saveState(cfg.stateFile, state);
    return summary;
  }
  for (const rec of recs) {
    const sym = rec.symbol;
    const price = rec.price;
    const pos = state.positions[sym] ?? { entryPrice: null, size: 0 };
    try {
      if (rec.action === "BUY") {
        const headroom = cfg.maxPositionUsd - (snap.positions[sym]?.positionUsd ?? 0);
        const buyUsd = Math.min(cfg.tradeUsd, snap.usdcBalance * 0.2, headroom);
        if (buyUsd >= 1) {
          const [stockOut] = await cx.exchange.quoteBuy(ex.symBytes(sym), BigInt(Math.round(buyUsd * 1e6)));
          const r = await ex.executeBuy(cx, sym, BigInt(Math.round(buyUsd * 1e6)));
          state.positions[sym] = { entryPrice: price, size: Number(stockOut) / 1e8 };
          const t = { symbol: sym, side: "BUY", usdc: buyUsd, stock: Number(stockOut) / 1e8, price, tx: r.hash };
          recordTrade(state, t);
          summary.trades.push(t);
          snap.usdcBalance -= buyUsd;
        } else {
          summary.errors.push(`BUY ${sym} skipped: size ${buyUsd.toFixed(2)} USDC below minimum`);
        }
      } else if (rec.action === "SELL" && pos.size > 0) {
        const stockBal = snap.positions[sym]?.stockBalanceUi ?? pos.size;
        const r = await ex.executeSell(cx, sym, BigInt(Math.round(stockBal * 1e8)));
        const t = { symbol: sym, side: "SELL", stock: stockBal, price, tx: r.hash };
        recordTrade(state, t);
        summary.trades.push(t);
        state.positions[sym] = { entryPrice: null, size: 0 };
      }
    } catch (e) {
      summary.errors.push(`trade ${sym} failed: ${e.message}`);
    }
  }

  summary.vault = snap;
  saveState(cfg.stateFile, state);
  return summary;
}

// CLI: `node src/run-cycle.js [--demo]`
if (import.meta.url === `file://${process.argv[1]}`) {
  runCycle()
    .then((s) => {
      console.log(JSON.stringify(s, null, 2));
      process.exit(0);
    })
    .catch((e) => {
      console.error(`cycle failed: ${e.message}`);
      process.exit(1);
    });
}
