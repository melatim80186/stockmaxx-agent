// On-chain executor — ethers v6. Talks to the deployed StockMaxx contracts.
// The agent key is ONLY the vault operator: it can log decisions and trade
// inside the vault guardrails. It cannot withdraw or change limits.
import { ethers } from "ethers";

const ORACLE_ABI = [
  "function updatePrices(bytes32[] symbols, int256[] prices)",
  "function getPrice(bytes32 symbol) view returns (int256)",
];
const VAULT_ABI = [
  "function logDecision(bytes32 symbol, uint8 action, int256 price, uint256 confidenceBps, bytes32 reasonHash)",
  "function logDecisions(bytes32[] symbols, uint8[] actions, int256[] prices, uint256[] confidencesBps, bytes32[] reasonHashes)",
  "function executeBuy(bytes32 symbol, uint256 usdcAmount)",
  "function executeSell(bytes32 symbol, uint256 stockAmount)",
  "function usdc() view returns (address)",
  "function tradesToday() view returns (uint256)",
  "function maxTradeUsd() view returns (uint256)",
  "function maxTradesPerDay() view returns (uint256)",
  "function maxPositionUsd() view returns (uint256)",
  "function positionUsd(bytes32 symbol) view returns (uint256)",
  "function allowedSymbols(bytes32 symbol) view returns (bool)",
];
const EXCHANGE_ABI = [
  "function quoteBuy(bytes32 symbol, uint256 usdcAmount) view returns (uint256 stockOut, uint256 fee)",
  "function quoteSell(bytes32 symbol, uint256 stockAmount) view returns (uint256 usdcOut, uint256 fee)",
];
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

export const ACTION = { HOLD: 0, BUY: 1, SELL: 2 };

export function symBytes(symbol) {
  return ethers.encodeBytes32String(symbol);
}

export function priceToOracle(priceUsd) {
  return BigInt(Math.round(priceUsd * 1e8));
}

export function connect(cfg) {
  const provider = new ethers.JsonRpcProvider(cfg.rpcUrl);
  // NonceManager serializes nonce assignment for back-to-back txs from one
  // cycle; without it, rapid sequential sends can reuse a stale nonce.
  const wallet = new ethers.NonceManager(new ethers.Wallet(cfg.privateKey, provider));
  const oracle = new ethers.Contract(cfg.addresses.oracle, ORACLE_ABI, wallet);
  const vault = new ethers.Contract(cfg.addresses.vault, VAULT_ABI, wallet);
  const exchange = new ethers.Contract(cfg.addresses.exchange, EXCHANGE_ABI, provider);
  const usdc = new ethers.Contract(cfg.addresses.usdc, ERC20_ABI, provider);
  return { provider, wallet, oracle, vault, exchange, usdc };
}

export async function updateOraclePrices(cx, prices) {
  const symbols = Object.keys(prices);
  if (!symbols.length) return null;
  const tx = await cx.oracle.updatePrices(
    symbols.map(symBytes),
    symbols.map((s) => priceToOracle(prices[s]))
  );
  const rc = await tx.wait();
  return { hash: tx.hash, blockNumber: rc.blockNumber };
}

export async function logDecisionsOnChain(cx, decisions) {
  const tx = await cx.vault.logDecisions(
    decisions.map((d) => symBytes(d.symbol)),
    decisions.map((d) => ACTION[d.action]),
    decisions.map((d) => priceToOracle(d.price)),
    decisions.map((d) => d.confidenceBps),
    decisions.map((d) => ethers.keccak256(ethers.toUtf8Bytes(d.reason)))
  );
  const rc = await tx.wait();
  return { hash: tx.hash, blockNumber: rc.blockNumber };
}

export async function logDecisionOnChain(cx, symbol, action, priceUsd, confidenceBps, reason) {
  const tx = await cx.vault.logDecision(
    symBytes(symbol),
    ACTION[action],
    priceToOracle(priceUsd),
    confidenceBps,
    ethers.keccak256(ethers.toUtf8Bytes(reason))
  );
  const rc = await tx.wait();
  return { hash: tx.hash, blockNumber: rc.blockNumber };
}

export async function executeBuy(cx, symbol, usdcAmount) {
  const tx = await cx.vault.executeBuy(symBytes(symbol), usdcAmount);
  const rc = await tx.wait();
  return { hash: tx.hash, blockNumber: rc.blockNumber };
}

export async function executeSell(cx, symbol, stockAmount) {
  const tx = await cx.vault.executeSell(symBytes(symbol), stockAmount);
  const rc = await tx.wait();
  return { hash: tx.hash, blockNumber: rc.blockNumber };
}

export async function vaultSnapshot(cx, cfg) {
  const [usdcBal, tradesToday, maxTrade, maxTrades, maxPos] = await Promise.all([
    cx.usdc.balanceOf(cfg.addresses.vault),
    cx.vault.tradesToday(),
    cx.vault.maxTradeUsd(),
    cx.vault.maxTradesPerDay(),
    cx.vault.maxPositionUsd(),
  ]);
  const positions = {};
  for (const [sym, addr] of Object.entries(cfg.addresses.stocks)) {
    const token = new ethers.Contract(addr, ERC20_ABI, cx.provider);
    const [bal, posUsd, allowed] = await Promise.all([
      token.balanceOf(cfg.addresses.vault),
      cx.vault.positionUsd(symBytes(sym)),
      cx.vault.allowedSymbols(symBytes(sym)),
    ]);
    positions[sym] = {
      stockBalance: bal.toString(),
      stockBalanceUi: Number(bal) / 1e8,
      positionUsd: Number(posUsd) / 1e6,
      allowed,
    };
  }
  return {
    usdcBalance: Number(usdcBal) / 1e6,
    tradesToday: Number(tradesToday),
    maxTradeUsd: Number(maxTrade) / 1e6,
    maxTradesPerDay: Number(maxTrades),
    maxPositionUsd: Number(maxPos) / 1e6,
    positions,
  };
}
