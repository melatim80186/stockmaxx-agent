// Price sources — all public, read-only, no API key.
//
// 1. Yahoo Finance chart API: live + daily closes for the 5 underlying
//    equities (NVDA/AAPL/TSLA/MSFT/AMZN). Unofficial endpoint; used as the
//    testnet oracle feed. Mainnet path: real Chainlink feeds per token
//    (see README "Mainnet path").
// 2. Bankr public API: live NAVs of on-Base stock index tokens (MAG7,
//    SPACE, C-Suite) — baskets of the real Coinbase B20 tokenized stocks.
//    Used as a Base-ecosystem confirmation signal, not for execution prices.
import { SYMBOLS } from "./config.js";

const UA = { "User-Agent": "Mozilla/5.0 (StockMaxxAgent/1.0)" };

export async function fetchYahooPrices() {
  const out = {};
  await Promise.all(
    SYMBOLS.map(async (sym) => {
      try {
        const res = await fetch(
          `https://query1.finance.yahoo.com/v8/finance/chart/${sym}?range=5d&interval=1d`,
          { headers: UA, signal: AbortSignal.timeout(15000) }
        );
        if (!res.ok) return;
        const data = await res.json();
        const result = data?.chart?.result?.[0];
        const meta = result?.meta;
        const closes = result?.indicators?.quote?.[0]?.close?.filter((x) => x != null) ?? [];
        if (!meta?.regularMarketPrice) return;
        out[sym] = {
          price: meta.regularMarketPrice,
          closes: closes.length ? closes : [meta.regularMarketPrice],
          changePct: meta.regularMarketChangePercent ?? null,
          asOf: meta.regularMarketTime ? meta.regularMarketTime * 1000 : Date.now(),
          source: "yahoo",
        };
      } catch (e) {
        console.warn(`[prices] yahoo ${sym} failed: ${e.message}`);
      }
    })
  );
  return out;
}

export async function fetchBankrIndexes() {
  try {
    const res = await fetch("https://api.bankr.bot/indexes?chain=base&kind=stocks&limit=10", {
      headers: UA,
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return [];
    const data = await res.json();
    return (data.items ?? []).map((i) => ({
      symbol: i.symbol,
      name: i.name,
      navUsd: i.navUsd,
      change24hPct: i.change24hPct,
      components: (i.componentsPreview ?? []).map((c) => c.symbol),
      address: i.address,
    }));
  } catch (e) {
    console.warn(`[prices] bankr failed: ${e.message}`);
    return [];
  }
}
