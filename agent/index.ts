import {
  activeCapabilities,
  GROUP_ORDER,
  GROUP_TITLES,
  type Capability,
} from "./capabilities";

const LLM_BASE = process.env.LLM_URL ?? "http://127.0.0.1:8080";
const LLM_URL = LLM_BASE.replace(/\/+$/, "") + "/v1/chat/completions";
const MODEL = process.env.LLM_MODEL ?? "gemma-4";
const BROWSER_BIN = process.env.BROWSER_BIN ?? "/usr/local/bin/browser_skill";
const APPEND_PATH = process.env.APPEND_SYSTEM_PATH ?? "/app/.pi/APPEND_SYSTEM.md";

interface Message {
  role: "system" | "user" | "assistant";
  content: string;
}

async function generatePrompt(): Promise<string> {
  const active = await activeCapabilities();

  const groups = new Map<string, Capability[]>();
  for (const cap of active) {
    const list = groups.get(cap.group) ?? [];
    list.push(cap);
    groups.set(cap.group, list);
  }

  const lines: string[] = [];
  lines.push("You are a Pi Coding Agent running inside a Debian MicroVM.");
  lines.push("You have access to a high-performance Linux toolkit. Prefer these over basic ls/cat for speed.");
  lines.push("");

  for (const g of GROUP_ORDER) {
    const caps = groups.get(g);
    if (!caps?.length) continue;
    lines.push(`### ${GROUP_TITLES[g]}`);
    for (const cap of caps) {
      lines.push(`- ${cap.snippet}`);
    }
    lines.push("");
  }

  lines.push("Emit shell commands as [sh:COMMAND] and URLs as [browse:URL].");
  lines.push("Respond with one action per turn, or [done] when finished.");
  lines.push("");
  lines.push("---");
  lines.push(`Current Time: ${new Date().toISOString()}`);
  lines.push(`PWD: ${process.cwd()}`);
  lines.push(`OS: ${process.platform} ${process.arch}`);

  // Project-specific override
  const appendFile = Bun.file(APPEND_PATH);
  if (await appendFile.exists()) {
    const extra = (await appendFile.text()).trim();
    if (extra) {
      lines.push("");
      lines.push("---");
      lines.push(extra);
    }
  }

  return lines.join("\n");
}

async function llm(messages: Message[]): Promise<string> {
  const res = await fetch(LLM_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: MODEL, messages, max_tokens: 2048 }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`LLM error ${res.status}: ${text}`);
  }
  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "";
}

async function browse(url: string): Promise<string> {
  const proc = Bun.spawn([BROWSER_BIN, url], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = await new Response(proc.stdout).text();
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`browser_skill failed (${exitCode}): ${stderr}`);
  }
  return stdout;
}

async function shell(cmd: string): Promise<string> {
  const proc = Bun.spawn(["bash", "-c", cmd], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  await proc.exited;
  let out = stdout.trim();
  if (stderr.trim()) out += `\n[stderr]\n${stderr.trim()}`;
  // Cap to 4000 chars to protect ctx
  if (out.length > 4000) out = out.slice(0, 4000) + "\n…[truncated]";
  return out;
}

async function agentLoop() {
  const systemPrompt: Message = {
    role: "system",
    content: await generatePrompt(),
  };

  const messages: Message[] = [systemPrompt];
  const reader = (await import("readline")).createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const prompt = (q: string): Promise<string> =>
    new Promise((res) => reader.question(q, res));

  const active = await activeCapabilities();
  console.log(`Connecting to LLM at: ${LLM_URL}`);
  console.log(`Model: ${MODEL}`);
  console.log(`Capabilities (${active.length}): ${active.map((c) => c.name).join(", ")}`);
  console.log("pi-agent-smol ready. Type a task or 'exit'.");

  while (true) {
    const input = await prompt("> ");
    if (input.trim() === "exit") break;

    messages.push({ role: "user", content: input });
    const reply = await llm(messages);
    messages.push({ role: "assistant", content: reply });

    const browseMatch = reply.match(/\[browse:(.*?)\]/);
    const shMatch = reply.match(/\[sh:(.*?)\]/);

    let toolResult: string | null = null;
    let toolLabel = "";
    if (browseMatch) {
      toolLabel = `Browsing: ${browseMatch[1]}`;
      toolResult = await browse(browseMatch[1].trim());
    } else if (shMatch) {
      toolLabel = `$ ${shMatch[1]}`;
      toolResult = await shell(shMatch[1].trim());
    }

    if (toolResult !== null) {
      console.log(toolLabel);
      messages.push({ role: "user", content: `Tool output:\n${toolResult}` });
      const followUp = await llm(messages);
      messages.push({ role: "assistant", content: followUp });
      console.log(followUp);
    } else {
      console.log(reply);
    }
  }

  reader.close();
}

agentLoop().catch(console.error);
