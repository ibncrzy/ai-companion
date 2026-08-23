// Polls the ai-companion mod's unread chat queue over RCON, forwards each
// message to claude-brain, and prints the reply back into the game via
// fac_chat_say so a player typing "/fac <message>" in Factorio gets a live
// reply in normal chat (and in the in-game chat GUI, which mirrors the same
// storage.chat_log that fac_chat_say writes to).
require("dotenv").config();
const { sendCommand } = require("./rcon");
const { chat } = require("./claude-brain");

const POLL_MS = Number(process.env.CHAT_BRIDGE_POLL_MS) || 3000;

// One shared history per companion id (0 = untargeted/general chat), so
// conversations with different companions don't bleed into each other.
const historyByTarget = new Map();

async function sayInGame(targetId, text) {
  // fac_chat_say sends one RCON console command per call; a literal newline
  // in the argument would truncate the line, so split multi-line replies.
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  for (const line of lines.length ? lines : [text]) {
    await sendCommand(`fac_chat_say ${targetId} ${line}`);
  }
}

async function handleMessage(m) {
  const targetId = m.target_companion || 0;
  const history = historyByTarget.get(targetId) || [];
  console.log(`[in-game] ${m.player}${m.target_companion ? ` -> #${m.target_companion}` : ""}: ${m.message}`);
  try {
    const result = await chat({ message: m.message, companionId: m.target_companion, history });
    historyByTarget.set(targetId, result.history || history);
    const reply = result.reply && result.reply.trim() ? result.reply.trim() : "(no reply)";
    console.log(`[claude -> ${targetId}] ${reply}`);
    await sayInGame(targetId, reply);
  } catch (err) {
    console.error("chat error:", err.message);
    await sayInGame(targetId, `(error: ${err.message})`).catch(() => {});
  }
}

async function poll() {
  try {
    const result = await sendCommand("fac_chat_get");
    const messages = Array.isArray(result.json) ? result.json : [];
    for (const m of messages) {
      await handleMessage(m);
    }
  } catch (err) {
    console.error("poll error:", err.message);
  }
}

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set in remote-control/.env — chat replies will fail until it is.");
}

console.log(`Chat bridge running. Polling fac_chat_get every ${POLL_MS}ms. Type /fac <message> in Factorio to talk.`);
setInterval(poll, POLL_MS);
poll();
