# Demo evidence — verified local end-to-end run

Run date: 2026-11-18 (WIB). Chain: local Anvil (chain 31337, ephemeral —
addresses below are valid only while that Anvil instance runs; the run was
reproduced twice with identical results).

## Deployment (Anvil run 2 — the recorded run)

| Contract | Address |
|---|---|
| MockUSDC | `0xfbC22278A96299D91d41C453234d97b4F5Eb9B2d` |
| StockOracle | `0x46b142DD1E924FAb83eCc3c08e4D46E82f005e0E` |
| StockExchange | `0xC9a43158891282A2B1475592D5719c001986Aaec` |
| AgentVault | `0x1c85638e118b37167e9298c2268758e058DdfDA0` |
| Operator (agent) | `0xF345f6E619443DEF293383FD515aD3DFE26a1357` |
| NVDAc mirror | `0x367761085BF3C12e5DA2Df99AC6E1a824612b8fb` |
| AAPLc mirror | `0x4631BCAbD6dF18D94796344963cB60d44a4136b6` |
| TSLAc mirror | `0xAA292E8611aDF267e563f334Ee42320aC96D0463` |
| MSFTc mirror | `0x5067457698Fd6Fa1C6964e416b3f42713513B3dD` |
| AMZNc mirror | `0xD5ac451B0c50B9476107823Af206eD814a2e2580` |

Vault funded with 1,000.00 test USDC at deploy.

## 13-cycle demo run (scripted synthetic prices, `--demo`)

| Cycle | NVDA | AAPL | TSLA | MSFT | AMZN | Trades | Errors |
|---|---|---|---|---|---|---|---|
| 1–8 | HOLD | HOLD | HOLD | HOLD | HOLD | — | 0 |
| 9 | **BUY @ $158** | HOLD | **BUY @ $384** | HOLD | HOLD | NVDA+TSLA BUY | 0 |
| 10–11 | HOLD | HOLD | HOLD | HOLD | HOLD | — | 0 |
| 12 | **SELL @ $150** | HOLD | HOLD | HOLD | HOLD | NVDA SELL | 0 |
| 13 | HOLD | HOLD | HOLD | HOLD | HOLD | — | 0 |

- **On-chain, verified by direct query:** 65 `DecisionLogged` events
  (13 cycles × 5 symbols) + 3 `TradeExecuted` events, `tradesToday() == 3`.
- **Trade txs:** NVDA BUY
  `0x4b5ce0d7803846638172d1e42fbb308aa0a9c8fcdc5dfb77b7c52a6aa71d0cf1`,
  TSLA BUY
  `0x4d30242be67c452da0c50c5711ead2b02075c45a05bf3b85b334f88545fb58f5`,
  NVDA SELL
  `0xe8563572d8cfe374871adce108af68342e0dd1f34503907ade512060eecaeb57`.
- **Vault final state (verified by `cast call`):** USDC **$978.95**,
  NVDA 0 shares, TSLA 0.05203125 shares.
  Arithmetic: $1,000 − $20 (NVDA buy) − $20 (TSLA buy) + $18.95 (NVDA sale
  at $150, net of 0.10% fee) = $978.95. Exact.
- **NVDA round trip:** bought $20 @ $158 → sold @ $150 = −5.1% (momentum
  exit, per strategy). TSLA still held, +0.5% at close.
- **Errors: 0 across all 13 cycles** (asserted per cycle).

## Live-price cycle (same deploy, real market data)

One `--demo`-free cycle against the same Anvil contracts, prices from Yahoo
Finance + Bankr (2026-11-18 ~15:22 WIB):

- NVDA $152.98, AAPL $353.50, TSLA $382.59, MSFT $504.72, AMZN $264.45
- Bankr on-Base index NAVs: MAG7 $82.66, SPACE $144.39, CSUITE $120.98
- Oracle updated on-chain (tx
  `0x4a9f3bbfcc48f98149059229dfe9df36b5ec8b9be0913ba18c001d06c4a7d95e`),
  all 5 decisions HOLD (warm-up: < 8 closes), 0 errors.

## Tests

- Foundry: **24/24 pass** (`forge test` in `contracts/`)
- Node: **11/11 pass** (`npm test` in `agent/`)

## Reproduce

```bash
anvil --port 8545 --mnemonic "test test test test test test test test test test test junk"
cd contracts && OPERATOR=0xF345f6E619443DEF293383FD515aD3DFE26a1357 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cd ../agent && for i in $(seq 1 13); do node src/run-cycle.js --demo; done
```
