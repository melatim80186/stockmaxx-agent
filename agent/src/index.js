// Long-running agent: runs one cycle every CYCLE_SECONDS and serves the
// dashboard on PORT. `node src/index.js [--demo]`
import { loadConfig } from "./config.js";
import { runCycle } from "./run-cycle.js";
import { startServer } from "./server.js";

const cfg = loadConfig();
console.log(`[agent] starting (${cfg.demo ? "DEMO" : "LIVE"} mode, chain ${cfg.chainId}, cycle ${cfg.cycleSeconds}s)`);
console.log(`[agent] vault ${cfg.addresses.vault || "(not deployed yet)"}`);

startServer(cfg);

async function loop() {
  try {
    const s = await runCycle(cfg);
    console.log(`[cycle] ${new Date().toISOString()} decisions=${s.decisions.map((d) => `${d.symbol}:${d.action}`).join(",")} trades=${s.trades.length} errors=${s.errors.length}`);
    for (const e of s.errors) console.warn(`[cycle] warn: ${e}`);
  } catch (e) {
    console.error(`[cycle] failed: ${e.message}`);
  }
  setTimeout(loop, cfg.cycleSeconds * 1000);
}
loop();
