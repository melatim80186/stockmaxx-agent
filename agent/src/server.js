// Tiny dashboard server: no dependencies, serves the static dashboard and
// a JSON status endpoint (state file + live on-chain vault snapshot).
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { loadState } from "./state.js";
import { connect, vaultSnapshot } from "./executor.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

export function startServer(cfg) {
  let cached = null;
  let cachedAt = 0;
  const server = createServer(async (req, res) => {
    try {
      if (req.url === "/" || req.url === "/index.html") {
        res.writeHead(200, { "Content-Type": "text/html" });
        res.end(readFileSync(path.join(ROOT, "public", "index.html"), "utf8"));
        return;
      }
      if (req.url === "/api/status") {
        const now = Date.now();
        if (!cached || now - cachedAt > 10000) {
          const state = loadState(cfg.stateFile);
          let onchain = null;
          let onchainError = null;
          let operator = null;
          try {
            const cx = connect(cfg);
            operator = await cx.wallet.getAddress();
            onchain = await vaultSnapshot(cx, cfg);
          } catch (e) {
            onchainError = e.message;
          }
          cached = {
            mode: cfg.demo ? "demo" : "live",
            chainId: cfg.chainId,
            explorer: cfg.explorer,
            addresses: cfg.addresses,
            operator,
            state,
            onchain,
            onchainError,
            generatedAt: new Date().toISOString(),
          };
          cachedAt = now;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(cached));
        return;
      }
      res.writeHead(404);
      res.end("not found");
    } catch (e) {
      res.writeHead(500);
      res.end(`error: ${e.message}`);
    }
  });
  server.listen(cfg.port, () => console.log(`[dashboard] http://127.0.0.1:${cfg.port}`));
  return server;
}
