// Agent configuration. All secrets / addresses come from env or the
// deployment manifest written by `forge script` (contracts/deployments/<chainId>.json).
// Never commit a real .env file; see .env.example.
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

export const SYMBOLS = ["NVDA", "AAPL", "TSLA", "MSFT", "AMZN"];

// Real Coinbase B20 tokenized-stock contracts on Base mainnet, for reference
// (verified 2026-11-18 via the Bankr components API). The agent READS these
// on mainnet for data; it never moves them. Testnet trades use our mirrors.
export const MAINNET_TOKENS = {
  NVDA: "0xb20000000000000000000078ee7ce2fe4908108c",
  AAPL: "0xb200000000000000000000c2e324d24d7eecd1fb",
  TSLA: "0xb2000000000000000000001e800a7f5189430cd0",
  MSFT: "0xb200000000000000000000ab99cfa739e253872b",
  AMZN: "0xb200000000000000000000d9192b6b456483c2e8",
};

export function loadConfig(argv = process.argv.slice(2)) {
  const demo = argv.includes("--demo");
  const chainId = Number(process.env.CHAIN_ID || (demo ? 31337 : 84532));
  const manifestPath = path.join(ROOT, "..", "contracts", "deployments", `${chainId}.json`);
  let manifest = {};
  if (existsSync(manifestPath)) manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

  return {
    demo,
    chainId,
    rpcUrl: process.env.RPC_URL || (demo ? "http://127.0.0.1:8545" : "https://sepolia.base.org"),
    explorer: process.env.EXPLORER_URL || (demo ? "" : "https://sepolia.basescan.org"),
    privateKey: process.env.AGENT_PRIVATE_KEY || "",
    addresses: {
      usdc: process.env.USDC_ADDRESS || manifest.usdc || "",
      oracle: process.env.ORACLE_ADDRESS || manifest.oracle || "",
      exchange: process.env.EXCHANGE_ADDRESS || manifest.exchange || "",
      vault: process.env.VAULT_ADDRESS || manifest.vault || "",
      stocks: manifest.stocks || {},
    },
    // Strategy knobs (see src/strategy.js for the rules).
    fastPeriod: Number(process.env.FAST_PERIOD || 3),
    slowPeriod: Number(process.env.SLOW_PERIOD || 8),
    momentumBuyBps: Number(process.env.MOMENTUM_BUY_BPS || 50), // +0.50%
    momentumSellBps: Number(process.env.MOMENTUM_SELL_BPS || -100), // -1.00%
    stopLossBps: Number(process.env.STOP_LOSS_BPS || 500), // +500 = sell at -5.00% vs entry (positive magnitude; strategy negates it)
    tradeUsd: Number(process.env.TRADE_USD || 20), // USDC per trade (testnet demo size)
    maxPositionUsd: Number(process.env.MAX_POSITION_USD || 400),
    cycleSeconds: Number(process.env.CYCLE_SECONDS || 300),
    port: Number(process.env.PORT || 8080),
    stateFile: process.env.STATE_FILE || path.join(ROOT, "state.json"),
    // Price sources (both free, no API key).
    yahooEnabled: process.env.YAHOO_ENABLED !== "0",
    bankrEnabled: process.env.BANKR_ENABLED !== "0",
  };
}
