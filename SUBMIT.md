# Submission checklist — Base Stocks Maxxing (Agentic Stock Finance)

Quest: Nov 5 – Dec 5, 2026. Rules: https://www.base.org/stocksmaxxing/rules
Track: **Agentic Stock Finance**. Prizes: $100,000+ total (track pools on
the quest page). Entry = X post + submission form. Testnet allowed.

## What is ready (agent side)

- [x] Repo: `melatim80186/stockmaxx-agent` (to be created — see "Push" below)
- [x] Contracts build + 24/24 Foundry tests pass
- [x] Agent: 11/11 Node tests pass; local demo end-to-end verified
      (65 on-chain decisions, 3 trades, 0 errors — see `demo/EVIDENCE.md`)
- [x] README with architecture, quickstart, mainnet path
- [x] Demo video script (`demo/DEMO_SCRIPT.md`) — recording needs a human
      (see "Still needed" below)
- [x] Live-price path verified (Yahoo + Bankr, real data, 0 errors)

## Still needed — Base Sepolia on-chain traction (before submitting)

The demo above runs on a local Anvil chain. For the strongest entry the
same stack should run live on **Base Sepolia** (50% of the score is
on-chain traction). Everything is prepared; only funding is missing:

1. **Fund the agent wallet with ~0.02 Base Sepolia ETH** (browser step —
   the agent cannot do faucet logins). Address:
   `0xF345f6E619443DEF293383FD515aD3DFE26a1357`
   Faucet: Alchemy (https://www.alchemy.com/faucets/base-sepolia) or
   QuickNode (https://faucet.quicknode.com/base/sepolia). 0.02 ETH covers
   deploy gas + many agent cycles (Base Sepolia txs are sub-cent).
2. **Deploy to Sepolia** (one command, VM). Deploy with the **agent wallet
   key as deployer** — then it is owner + operator in one funded wallet
   (testnet only; on mainnet the owner must be a separate cold wallet /
   multisig — see README security notes):
   ```bash
   cd contracts
   forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org \
     --broadcast --private-key <agent-operator-key>
   ```
   (`OPERATOR` defaults to the deployer, so it can be omitted.)
   Then in `agent/.env`: `RPC_URL=https://sepolia.base.org`,
   `CHAIN_ID=84532`, `AGENT_PRIVATE_KEY=<operator key>`, then `npm start`.
   Let it run a few hours (cycle 300s) so decisions + trades accumulate on
   Sepolia; link the vault address + a Basescan tx in the X post.
3. **Record the demo video** following `demo/DEMO_SCRIPT.md` (2–3 min).
   Needs a human with a screen recorder — the agent has no screen/browser.
4. **User posts on X** (from @singakuuu): public post + video demo,
   tagging `@buildonbase`. Draft below.
5. **User submits the official form** linked on
   https://www.base.org/stocksmaxxing (Google form "Apply Now"):
   X post link, track = Agentic Stock Finance, repo link, vault + Sepolia
   contract addresses, short description of what was built during the
   quest period.

## Push the repo (parent/agent step, no user action)

```bash
cd ~/workspace/bug-bounty/makefun/hackathon-push/base-stocks
gh repo create melatim80186/stockmaxx-agent --public --source=. --push
# .env, .agent-wallet.json, state.json, deployments/ are gitignored.
# The operator private key lives ONLY in agent/.agent-wallet.json + agent/.env (mode 600).
```

## X post draft (user posts; edit freely)

> StockMaxx Agent 🤖📈 — my entry for @base Stocks Maxxing, Agentic Stock
> Finance track.
>
> An autonomous agent that watches real tokenized stocks on Base (Coinbase
> B20 NVDAc/AAPLc/TSLA… + @bankrbot stock indexes), decides with a
> documented momentum strategy, and trades on-chain through a guardrailed
> vault — every decision, even HOLD, logged on-chain.
>
> The agent key can trade but can NEVER withdraw. Owner can pause/pull
> anytime. Mainnet-ready: Chainlink feeds + Aerodrome pools + real B20s.
>
> Demo (testnet): 65 on-chain decisions, 3 trades, 0 errors. Vault math
> closes to the cent.
>
> Repo: https://github.com/melatim80186/stockmaxx-agent
> @buildonbase #StocksMaxxing
>
> [attach demo video]

## Honest assessment (for the coordinator)

- **Strong:** real Base data integration (Bankr live NAVs + B20 registry),
  genuine on-chain decision journal, guardrailed custody model, full
  test coverage, mainnet path with zero strategy changes, reproducible demo.
- **Weak / to be fixed before submit:** no live Sepolia deployment yet
  (blocked only on faucet funding — see above). Without it, "on-chain
  traction" is a local-Anvil story, which is much weaker for 50% of the
  score. **Do not submit before the Sepolia run.**
- **Not claimed:** no mainnet trading, no real-money P&L, no partnership
  with Base/Bankr/o1 (integrations are public read-only APIs + mirrors of
  public contracts). The demo video must say testnet + synthetic demo
  prices where applicable.
