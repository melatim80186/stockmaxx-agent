# Demo video script — StockMaxx Agent (target: 2–3 minutes)

Record with a screen recorder (Loom / OBS / phone). The agent runs on a
local Anvil chain for the demo; the same commands work on Base Sepolia once
the agent wallet is funded (see SUBMIT.md). Speak in English (judges) or
add English captions.

## Setup (before recording, ~2 min)

1. Terminal 1: `anvil --port 8545 --mnemonic "test test test test test test test test test test test junk"`
2. Terminal 2: deploy (see README Quickstart §1) — vault funded 1,000 test USDC.
3. Terminal 3: `cd agent && npm install` and `.env` with the operator key.
4. Open `http://127.0.0.1:8080` in a browser tab (dashboard) — start the
   server with `node src/index.js --demo` AFTER the scripted run, or keep it
   stopped and open the page after the cycles (it reads `state.json`).

## Script

**[0:00–0:20] Hook — what this is.**
> "This is StockMaxx Agent, an autonomous agent for the Base Stocks Maxxing
> quest, Agentic Stock Finance track. It watches real tokenized stocks on
> Base — the Coinbase B20 tokens like NVDAc and AAPLc, and Bankr stock
> indexes — and it trades them on-chain through a vault that the agent
> cannot drain."

Show: README architecture diagram / dashboard.

**[0:20–0:50] The contracts.**
> "Four contracts on Base Sepolia. An oracle with Chainlink-compatible
> feeds, an exchange that mints and burns tokenized stocks against USDC,
> the stock tokens themselves — 8 decimals, like the real B20 tokens — and
> the vault. The vault is the key part: the agent key can only trade inside
> guardrails — max one hundred dollars a trade, ten trades a day — it can
> never withdraw. The owner can pause or pull funds at any time."

Show: `forge test` output (24/24 pass) or Basescan Sepolia contract pages.

**[0:50–1:40] The agent running — live.**
Run the demo loop on camera:
```bash
for i in $(seq 1 13); do node src/run-cycle.js --demo; done
```
Narrate as it prints:
> "Cycle nine — the uptrend triggers: it buys twenty dollars of NVDA at
> 158 and twenty of TSLA at 384. Cycles ten and eleven, it holds. Cycle
> twelve, NVDA momentum breaks — it sells at 150. Every decision, even the
> holds, is logged on-chain."

Show: the cycle JSON output (decisions + trades + zero errors).

**[1:40–2:20] Proof — verify on-chain, not screenshots.**
> "Don't trust the terminal — check the chain."

- Query the vault events (65 `DecisionLogged`, 3 `TradeExecuted`) — show
  the ethers query output or the dashboard's decision table.
- Show vault balances: USDC $978.95, TSLA 0.052 shares, NVDA zero —
  "a thousand minus forty in buys plus eighteen-ninety-five back from the
  NVDA sale. The arithmetic closes to the cent."
- Open the dashboard at `http://127.0.0.1:8080`: positions, P&L, decision
  log with explorer links.

**[2:20–2:40] Mainnet path + close.**
> "On mainnet nothing about the strategy or the vault changes — MockUSDC
> becomes real USDC, the mirrors become the real B20 tokens, the
> agent-posted oracle becomes Chainlink feeds, and the exchange becomes
> Aerodrome pools. Same guardrails, same on-chain decision log. Repo link
> in the post. Thanks — built for Stocks Maxxing on Base."

## Shots checklist (for editing)

- [ ] Terminal: `forge test` 24/24 pass
- [ ] Terminal: 13 demo cycles, cycle 9 BUY + cycle 12 SELL visible
- [ ] Dashboard: positions + decision table + trade tx links
- [ ] On-chain event query: 65 DecisionLogged / 3 TradeExecuted
- [ ] Vault balances: $978.95 USDC, TSLA 0.05203125, NVDA 0

## Notes for the recorder

- The demo uses scripted synthetic prices (`--demo`) so the BUY → SELL
  loop plays out in ~2 minutes. This is labelled DEMO MODE in the
  dashboard and in the code — say so on camera; the live-price path (Yahoo
  + Bankr) is shown in `demo/EVIDENCE.md`.
- Do NOT show the operator private key on screen. `.env` is gitignored;
  keep the terminal scrolled past it.
- Video must be public on X and tag `@buildonbase` (rules §5).
