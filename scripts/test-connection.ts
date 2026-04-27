const PORT = Number(process.env.LLM_PORT ?? "8080");

const targets = [
  { name: "localhost", host: "127.0.0.1" },
  { name: "gateway (legacy)", host: "172.16.0.1" },
];

// Try to detect default gateway
try {
  const proc = Bun.spawn(["sh", "-c", "ip route show default 2>/dev/null | awk '{print $3}'"], {
    stdout: "pipe",
  });
  const gw = (await new Response(proc.stdout).text()).trim();
  if (gw && gw !== "127.0.0.1" && gw !== "172.16.0.1") {
    targets.push({ name: `gateway (${gw})`, host: gw });
  }
} catch {}

console.log(`\n── LLM Connection Test (port ${PORT}) ──\n`);

let anyPassed = false;

for (const { name, host } of targets) {
  const url = `http://${host}:${PORT}/health`;
  process.stdout.write(`  ${name.padEnd(22)} ${host.padEnd(16)} `);

  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
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
    } else if (msg.includes("timeout") || msg.includes("TimeoutError")) {
      console.log("TIMEOUT — firewall or unreachable");
    } else {
      console.log(`ERROR: ${msg.slice(0, 60)}`);
    }
  }
}

console.log("");

if (anyPassed) {
  console.log("At least one endpoint is reachable.");
} else {
  console.log("ALL FAILED. Checklist:");
  console.log("");
  console.log("  1. Is llama-server running?");
  console.log("     llama-server -m <model> --host 0.0.0.0 --port 8080");
  console.log("");
  console.log("  2. WSL2 mirrored networking enabled?");
  console.log("     Windows: %USERPROFILE%\\.wslconfig");
  console.log("     [wsl2]");
  console.log("     networkingMode=mirrored");
  console.log("     Then: wsl --shutdown (from PowerShell)");
  console.log("");
  console.log("  3. Firewall blocking port 8080?");
  console.log("     Windows: netsh advfirewall firewall add rule name=\"llama\" dir=in action=allow protocol=TCP localport=8080");
}
