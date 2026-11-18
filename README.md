# StockMaxx Agent — Autonomous Tokenized-Stock Agent on Base

**Entry for the [Base Stocks Maxxing Builder Quest](https://www.base.org/stocksmaxxing/rules) — Track: Agentic Stock Finance.**

An autonomous agent that monitors tokenized equities on Base, runs a
documented momentum strategy, and trades them through an on-chain vault
with hard guardrails. Every decision — including HOLD — is logged on-chain,
so the agent's full reasoning trail is verifiable without trusting its logs.

- Quest: Nov 5 – Dec 5, 2026 · $100,000+ in rewards · free entry · online
- Entry: public X post with video demo tagging `@buildonbase` + submission form
- Testnet explicitly allowed ("will not be judged less favorably")

## What the agent does

1. **Reads real tokenized-equity data on Base mainnet** (read-only, no key):
   - [Bankr public API](https://api.bankr.bot) — live NAVs of on-Base stock
     index tokens (MAG7, SPACE, C-Suite), baskets of the real Coinbase B20
     tokenized stocks (AAPLc, NVDAc, MSFTc, TSLAc, GOOGLc, AMZNc).
   - Yahoo Finance chart API — live + daily closes for the 5 underlying
     equities (NVDA, AAPL, TSLA, MSFT, AMZN). Unofficial endpoint; used as
     the testnet oracle feed.
2. **Decides** with a transparent SMA-crossover + momentum strategy
   (`agent/src/strategy.js`, unit-tested): BUY on uptrend + positive
   momentum, SELL on trend flip / momentum collapse / -5% stop-loss, else HOLD.
3. **Posts prices to the on-chain oracle** and **logs every decision on-chain**
   (`AgentVault.logDecisions`, one tx per cycle for all symbols).
4. **Trades through the vault** (`AgentVault.executeBuy/executeSell`) inside
   hard guardrails: allowlisted symbols only, max $100/trade, max $400/symbol,
   max 10 trades/day, owner-pausable. The agent key **cannot withdraw funds,
   change limits, or pause** — worst case for a buggy/compromised agent is
   bounded trading, never loss of custody.
5. **Serves a dashboard** (`http://127.0.0.1:8080`) with positions, P&L,
   decision log and explorer links.

## Architecture

```
                ┌────────────────────┐  read-only, no key
                │ Bankr API (Base)   │  index NAVs (MAG7/SPACE/…)
                │ Yahoo Finance      │  per-stock prices
                └────────┬───────────┘
                         │  Node.js agent (agent/src)
                         ▼
        ┌─────────────────────────────────────────┐
        │ strategy.js  decide() — pure, tested    │
        │ run-cycle.js fetch → oracle → log → trade│
        │ server.js    dashboard + /api/status    │
        └────────┬────────────────────────────────┘
                 │ ethers v6, operator EOA
                 ▼
   Base Sepolia (testnet) — Foundry contracts (contracts/src)
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │ StockOracle  │  │StockExchange │  │ TokenizedStock│ │ AgentVault   │
   │ Chainlink-   │  │ buy/sell vs  │  │ ERC-20, 8dec │  │ holds funds, │
   │ compatible   │  │ USDC at      │  │ B20 mirror:  │  │ guardrails,  │
   │ per-symbol   │  │ oracle price │  │ multiplier + │  │ on-chain     │
   │ feeds        │  │ + 0.10% fee  │  │ balanceOfUI  │  │ decision log │
   └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
        MockUSDC (6 dec, testnet stand-in for real USDC)
```

### Contracts

| Contract | Role |
|---|---|
| `MockUSDC` | Testnet USDC stand-in (6 decimals, like real USDC). |
| `TokenizedStock` | ERC-20 mirror of a Coinbase B20 tokenized stock: 8 decimals, `multiplier` (corporate actions), `balanceOfUI` (share-equivalent balance), mint/burn only by the exchange. **Not the real token — no claim on any share.** |
| `StockOracle` | Chainlink `AggregatorV3`-compatible per-symbol feeds (8-dec USD). Prices posted by the agent updater; consumers enforce a `maxAge` staleness bound. |
| `StockExchange` | Primary buy/sell venue: buy mints stock vs USDC at oracle price, sell burns and pays USDC; 0.10% fee; per-trade cap; pausable. Holds a funded sell-side reserve on testnet. |
| `AgentVault` | The agent's wallet: holds USDC + stocks, only the operator EOA may trade/log, only inside guardrails; owner can pause, withdraw, rotate operator, set limits. |

Real Coinbase B20 tokenized-stock contracts on Base mainnet (verified
2026-11-18 via the Bankr components API — the agent reads these for data):

| Symbol | Base mainnet contract |
|---|---|
| NVDAc | `0xb20000000000000000000078ee7ce2fe4908108c` |
| AAPLc | `0xb200000000000000000000c2e324d24d7eecd1fb` |
| TSLAc | `0xb2000000000000000000001e800a7f5189430cd0` |
| MSFTc | `0xb200000000000000000000ab99cfa739e253872b` |
| AMZNc | `0xb200000000000000000000d9192b6b456483c2e8` |

### Strategy (documented, deterministic)

- **BUY** (flat only): SMA(3) > SMA(8) **and** 8-period momentum > +0.50%.
  Confidence 50–95% scaled from momentum strength.
- **SELL** (holding): SMA(3) < SMA(8), **or** momentum ≤ −1.00%, **or**
  price ≤ entry × 0.95 (stop-loss).
- **HOLD** otherwise, including the warm-up period (< 8 closes).
- Sizing: ≤ $20/trade, ≤ 20% of vault USDC, ≤ $400/symbol.

## Verified state (2026-11-18)

- **Contracts:** `forge build` clean; **24/24 Foundry tests pass**
  (`contracts/test/StockMaxx.t.sol`) — oracle staleness, quote math,
  round-trip, caps, pause, operator rotation, batch logging, multi-sell
  liquidity regression.
- **Agent:** **11/11 Node tests pass** (`agent/test/`, `npm test`) —
  strategy rules + config regression (see `docs/BUILD_LOG.md`).
- **Local end-to-end demo (Anvil, 13 cycles):** 65 decisions logged on-chain,
  3 trades executed, **0 errors**. NVDA BUY $20 @ $158 → SELL @ $150
  (momentum exit, −5.1%); TSLA BUY $20 @ $384, still held (+0.5%).
  Vault: $1,000.00 → $978.95 (exact: −$40 buys + $18.95 NVDA sale).
  On-chain check: 65 `DecisionLogged` + 3 `TradeExecuted` events, vault
  balances verified by `cast call`. See `demo/EVIDENCE.md`.
- **Live-price cycle (same Anvil deploy, real Yahoo + Bankr data):**
  NVDA $152.98, AAPL $353.50, TSLA $382.59, MSFT $504.72, AMZN $264.45;
  Bankr MAG7 NAV $82.66, SPACE $144.39, CSUITE $120.98. Oracle updated
  on-chain, all HOLD (warm-up), 0 errors.
- **Base Sepolia deployment: ready, not yet executed.** It needs ~0.02
  Base Sepolia ETH for the agent wallet (faucet claim is a browser step —
  see `SUBMIT.md`). Deploy command is one line; contracts + agent need no
  code changes for Sepolia.

## Quickstart

### 1. Local demo (no faucet, no keys — full BUY → SELL loop in ~2 min)

```bash
# Terminal 1 — local chain
anvil --port 8545 --mnemonic "test test test test test test test test test test test junk"

# Terminal 2 — deploy (deployer = anvil account 0)
cd contracts
forge install   # first run only (OpenZeppelin + forge-std)
OPERATOR=<agent-address> forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# ^ writes contracts/deployments/31337.json (addresses for the agent)

# Fund the agent operator with test ETH (Anvil only)
cast send <agent-address> --value 1ether \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://127.0.0.1:8545

# Terminal 3 — run 13 demo cycles (scripted synthetic prices)
cd ../agent
npm install
cp .env.example .env   # set AGENT_PRIVATE_KEY to the operator key, RPC_URL=http://127.0.0.1:8545
for i in $(seq 1 13); do node src/run-cycle.js --demo; done

# Dashboard (live loop + web UI)
node src/index.js --demo   # http://127.0.0.1:8080
```

Generate a fresh agent operator key with `cast wallet new` (testnet-only
throwaway; it can trade inside the vault but can never withdraw).

### 2. Live mode (real prices, any chain)

```bash
node src/run-cycle.js            # one cycle: Yahoo + Bankr → oracle → log → trade
node src/index.js                # loop every CYCLE_SECONDS (default 300s) + dashboard
```

Live mode needs 8 closes before the first real signal (Yahoo seeds 5 daily
closes; each cycle adds one sample). It HOLDs while warming up — by design.

### 3. Base Sepolia deploy

```bash
cd contracts
OPERATOR=<agent-address> forge script script/Deploy.s.sol \
  --rpc-url https://sepolia.base.org --broadcast --private-key <deployer-key> \
  --verify --etherscan-api-key <basescan-key>   # --verify optional
# writes contracts/deployments/84532.json
cd ../agent
# .env: RPC_URL=https://sepolia.base.org, CHAIN_ID=84532, AGENT_PRIVATE_KEY=<operator-key>
npm start
```

The agent wallet needs ~0.02 Base Sepolia ETH. Deploy with the agent key
(see `SUBMIT.md`) so one funded wallet covers deploy gas + agent cycles
(all sub-cent on Base Sepolia). Claim from the Alchemy or QuickNode Base Sepolia
faucet (browser step) to the operator address.

## Mainnet path (no code changes to strategy/vault logic)

| Testnet piece | Mainnet replacement |
|---|---|
| `MockUSDC` | Real USDC on Base `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| `TokenizedStock` mirrors | Real Coinbase B20 tokens (table above) |
| `StockOracle` (agent-posted) | Real Chainlink feeds per token (24/5, last-close held off-hours) |
| `StockExchange` (primary venue) | Aerodrome / Uniswap pools for the B20 tokens |
| `AgentVault` | Same contract, same guardrails, real addresses |

## Security notes / known limitations

- **Operator key scope:** the agent EOA can only trade inside vault
  guardrails and log decisions. It cannot withdraw, change limits, or pause.
  The owner (user) holds those powers. Rotate the operator with
  `vault.setOperator(newOperator)`; pause with `vault.pause()`.
  **Testnet simplification:** the Sepolia deploy uses the agent key as
  deployer (= owner) so one funded wallet suffices. On mainnet the owner
  MUST be a separate cold wallet / multisig — never the agent key.
- **Oracle trust (testnet):** prices are posted by the agent from public
  APIs. On mainnet this role is replaced by Chainlink feeds; the vault never
  trusts a price older than `maxAge` (default 1 day).
- **`positionUsd` is a notional tracker** (buy-price based), used only for
  the per-symbol cap; the authoritative position is the token balance.
- **Yahoo Finance chart API is unofficial** and may rate-limit; the agent
  logs a warning and skips the cycle's price update rather than trading on
  stale data (oracle staleness reverts trades).
- **Testnet tokens are mirrors**, not the real B20 tokens, and confer no
  rights in any underlying company. The demo never claims otherwise
  (rules §6.7).
- **No real money** is used anywhere in this repo. All demo funds are
  testnet-only `MockUSDC` minted by the deploy script.

## Repo layout

```
contracts/   Foundry: src/*.sol, test/StockMaxx.t.sol, script/Deploy.s.sol
agent/       Node.js + ethers v6: src/{config,prices,strategy,state,executor,run-cycle,index,server}.js
             public/index.html (dashboard), test/*.test.js
demo/        DEMO_SCRIPT.md (video script), EVIDENCE.md (verified demo run)
docs/        BUILD_LOG.md (build + review rounds, bugs found & fixed)
SUBMIT.md    Submission checklist + X post draft + remaining user steps
```

## Hackathon mapping

Built for **Base Stocks Maxxing — Agentic Stock Finance**: an agent that
interacts with tokenized equities on Base. Real Base data in (Bankr index
NAVs + B20 token registry), autonomous on-chain decisions + trades out,
guardrailed custody, and a mainnet-ready path (Chainlink feeds + Aerodrome
pools + real B20 tokens). 50% of the score is on-chain traction: the
traction here is every decision and trade as a queryable on-chain event,
not a screenshot.
