const PORT = Number(process.env.LLM_PORT ?? "8080");
const TIMEOUT_MS = 2000;

const targets: { name: string; host: string }[] = [
  { name: "localhost", host: "127.0.0.1" },
];

// Detect default gateway (informational — may differ from localhost in non-mirrored mode)
try {
  const proc = Bun.spawn(["sh", "-c", "ip route show default 2>/dev/null | awk '{print $3}'"], {
    stdout: "pipe",
  });
  const gw = (await new Response(proc.stdout).text()).trim();
  if (gw && gw !== "127.0.0.1") {
    targets.push({ name: `gateway (${gw})`, host: gw });
  }
} catch {}

console.log(`\n── LLM Connection Test (port ${PORT}, timeout ${TIMEOUT_MS}ms) ──\n`);

let anyPassed = false;

for (const { name, host } of targets) {
  const url = `http://${host}:${PORT}/health`;
  process.stdout.write(`  ${name.padEnd(22)} ${host.padEnd(16)} `);

  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (res.ok) {
      console.log(`PASS (${res.status})`);
      anyPassed = true;
    } else {
      console.log(`HTTP ${res.status}`);
    }
  } catch (err: any) {
    const msg = err?.message ?? String(err);
    if (msg.includes("ConnectionRefused") || msg.includes("ECONNREFUSED")) {
      console.log("REFUSED — port closed");
    } else if (msg.includes("timeout") || msg.includes("TimeoutError") || msg.includes("aborted")) {
      console.log("TIMEOUT — firewall or unreachable");
    } else {
      console.log(`ERROR: ${msg.slice(0, 60)}`);
    }
  }
}

console.log("");

if (anyPassed) {
  console.log("PASS: LLM is reachable.");
  process.exit(0);
} else {
  console.log("FAIL: No endpoints reachable.\n");
  console.log("Checklist:");
  console.log("  1. llama-server running with --host 0.0.0.0 --port 8080?");
  console.log("  2. WSL2 mirrored networking enabled in %USERPROFILE%\\.wslconfig?");
  console.log("       [wsl2]");
  console.log("       networkingMode=mirrored");
  console.log("     Then: wsl --shutdown (PowerShell)");
  console.log("  3. Windows firewall allowing TCP 8080?");
  process.exit(1);
}
