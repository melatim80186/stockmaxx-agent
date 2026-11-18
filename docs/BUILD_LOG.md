# Build log — StockMaxx Agent (Base Stocks Maxxing)

Builder: subagent base-stocks, 2026-11-18. Coordinator: hackathon-push.

## Sources verified (live, 2026-11-18)

- Rules: https://www.base.org/stocksmaxxing/rules — quest Nov 5–Dec 5 2026,
  3 tracks, entry = X post with video demo tagging @buildonbase + form,
  testnet allowed and "will not be judged less favorably", 18+, teams ≤ 5,
  prizes in USDC on Base.
- Quest page: https://www.base.org/stocksmaxxing — $100,000+ rewards,
  partners o1 Exchange, Bankr, Stonks Exchange, BaseStonk, Feel.cash,
  Hydropump by Hydrex.
- Base docs: Tokenized Stocks API (read-only, no key); B20 standard,
  8 decimals, Chainlink feeds 24/5, Onchain Registry
  `0x3f3E8cf41cdd3b1D118c16471aB0113DfDDd5CaD`.
- Bankr public API (live, no key): stock index NAVs (MAG7 $82.66, SPACE
  $144.39, CSUITE $120.98 at check time) + B20 token registry (12 stocks,
  addresses `0xb200…`).
- Yahoo Finance chart API (live, no key): NVDA $155.33, AAPL $354.18,
  TSLA $384.74, MSFT $506.93, AMZN $264.17 (first check; moved during the
  day — live cycle later read NVDA $152.98).
- Coinbase Tokenized Stocks API base URL could NOT be recovered from the
  docs pages (cURL examples render without the host; guessed
  `api.base.org/...` paths 404). Not used; Bankr + Yahoo cover the data
  need. Do not cite a base URL for it.
- Faucets: Alchemy + QuickNode Base Sepolia faucets exist but require
  account login / wallet connect (browser step). Coinbase faucet 403s bots.
  pk910 PoW faucet gives Ethereum Sepolia ETH, not Base Sepolia — bridging
  was not attempted (time-boxed; parent can do the 2-minute browser claim).

## What was built

- `contracts/src`: MockUSDC, TokenizedStock (B20 mirror), StockOracle
  (Chainlink-compatible), StockExchange, AgentVault.
- `contracts/test/StockMaxx.t.sol`: 24 tests. `script/Deploy.s.sol`:
  deploys + seeds + funds vault (1,000 mUSDC) + funds exchange reserve
  (100,000 mUSDC) + writes `deployments/<chainId>.json`.
- `agent/src`: config, prices (Yahoo + Bankr), strategy (pure, tested),
  state, executor (ethers v6), run-cycle, index (loop), server (dashboard),
  `public/index.html`. `agent/test`: 11 tests.
- Docs: README, demo/DEMO_SCRIPT.md, demo/EVIDENCE.md, SUBMIT.md.

## Review rounds

### Round 1 — first full run (Anvil, 13 cycles)

- **Found:** nonce collisions (`NONCE_EXPIRED`) on back-to-back txs from
  one wallet — 4 of 5 per-symbol `logDecision` txs failed in cycle 1.
- **Found:** `STOP_LOSS_BPS` config default was `-500` while `strategy.js`
  negates it (`pnlBps <= -cfg.stopLossBps`), so every position "stop-lossed"
  the next cycle (fired at +26 bps!). Caused churn: NVDA sold @ $159 one
  cycle after buying @ $158.
- **Found:** exchange sell-side illiquidity — back-to-back sells reverted
  with `ERC20InsufficientBalance` once buy proceeds minus fees drained the
  till (cycle 10 TSLA sell).
- **Found:** deploy script `OnlyUpdater` failure — oracle updater was the
  operator, but the deployer seeds prices. Fixed by seeding as deployer
  then `setUpdater(operator)`.
- **Found:** "stack too deep" in first Deploy script — refactored into
  helpers.
- **Found:** anvil deployer-key confusion — the deployer key I typed from
  memory had one wrong hex digit (`…f3ff80` vs the real `…f2ff80` in the
  anvil log), so txs came from an unfunded address. Lesson: always read the
  key from the anvil log, never from memory.
- **Fixed:** batch `logDecisions` (1 tx/cycle) + `NonceManager` in the
  executor; config default `stopLossBps: 500`; 100k mUSDC exchange reserve
  in deploy script; updater handover; helpers refactor.
- **Regression tests added:** `test_BatchDecisionLogging`,
  `test_MultiTradeSellLiquidity`, `test/config.test.js` (stop-loss sign).

### Round 2 — clean rerun after fixes

- 24/24 Foundry + 11/11 Node pass.
- 13 demo cycles: 65 decisions, 3 trades, **0 errors**. NVDA BUY @ $158 →
  SELL @ $150 (correct momentum exit); TSLA BUY @ $384 held.
- Vault arithmetic verified to the cent ($978.95).
- Live-price cycle (real Yahoo + Bankr): oracle updated on-chain, all
  HOLD (warm-up), 0 errors.
- Dashboard served and `/api/status` verified (vault, positions, decisions).
- Deterministic reproduction: redeploy + rerun gave identical results
  (65 decisions, 3 trades, $978.95).

### Round 3 — docs + honesty check

- README/SUBMIT/EVIDENCE re-checked against live sources; no invented
  prizes/deadlines/requirements. Sepolia status stated plainly as
  NOT done (blocked on faucet funding, a browser step).
- Demo script labels synthetic demo prices as synthetic; dashboard shows a
  DEMO MODE banner.
- Known limitations documented in README (oracle trust on testnet,
  `positionUsd` approximation, Yahoo unofficial endpoint, partial
  Chainlink single-feed compat).

## Open items (not agent-fixable from here)

1. Base Sepolia ETH (~0.02) for the agent wallet — browser faucet claim.
2. Sepolia deploy + a few hours of live agent cycles (traction for the 50%).
3. Demo video recording (needs a screen) + X post + form submit (user).
