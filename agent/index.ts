const LLM_BASE = process.env.LLM_URL ?? "http://172.16.0.1:8080";
const LLM_URL = LLM_BASE.replace(/\/+$/, "") + "/v1/chat/completions";
const MODEL = process.env.LLM_MODEL ?? "gemma-4";
const BROWSER_BIN = process.env.BROWSER_BIN ?? "/usr/local/bin/browser_skill";

interface Message {
  role: "system" | "user" | "assistant";
  content: string;
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

async function agentLoop() {
  const systemPrompt: Message = {
    role: "system",
    content: `You are a minimal coding agent running in a MicroVM.
You can browse URLs — the result is an accessibility tree (JSON).
Respond with actions: [browse:URL] or [done].`,
  };

  const messages: Message[] = [systemPrompt];
  const reader = (await import("readline")).createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const prompt = (q: string): Promise<string> =>
    new Promise((res) => reader.question(q, res));

  console.log(`Connecting to LLM at: ${LLM_URL}`);
  console.log(`Model: ${MODEL}`);
  console.log(`Browser: ${BROWSER_BIN}`);
  console.log("pi-agent-smol ready. Type a task or 'exit'.");

  while (true) {
    const input = await prompt("> ");
    if (input.trim() === "exit") break;

    messages.push({ role: "user", content: input });
    const reply = await llm(messages);
    messages.push({ role: "assistant", content: reply });

    const browseMatch = reply.match(/\[browse:(.*?)\]/);
    if (browseMatch) {
      console.log(`Browsing: ${browseMatch[1]}`);
      const tree = await browse(browseMatch[1]);
      messages.push({ role: "user", content: `Accessibility tree:\n${tree}` });
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
