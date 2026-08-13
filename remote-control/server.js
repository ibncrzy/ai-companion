require("dotenv").config();
const express = require("express");
const path = require("path");
const { sendCommand } = require("./rcon");
const { chat } = require("./claude-brain");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Only fac_* mod commands may be sent — never arbitrary console/admin commands.
function isAllowedCommand(command) {
  return typeof command === "string" && /^fac[_ ]/.test(command.trim());
}

app.post("/api/command", async (req, res) => {
  const { command } = req.body || {};
  if (!isAllowedCommand(command)) {
    return res.status(400).json({ error: "Only fac_* commands are allowed" });
  }
  try {
    const result = await sendCommand(command);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/companions", async (req, res) => {
  try {
    const result = await sendCommand("fac_companion_list");
    const companions = result.json?.companions || [];
    // fac_companion_list returns {position:{x,y}, health: <pct 0-100>} — flatten for the UI.
    const normalized = companions.map((c) => ({
      id: c.id,
      x: c.position?.x,
      y: c.position?.y,
      health: c.health,
      max_health: 100,
      name: c.name,
    }));
    res.json(normalized);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/chat", async (req, res) => {
  const { message, companionId, history } = req.body || {};
  if (!message) return res.status(400).json({ error: "message is required" });
  if (!process.env.ANTHROPIC_API_KEY) {
    return res.status(400).json({ error: "ANTHROPIC_API_KEY not configured on server" });
  }
  try {
    const result = await chat({ message, companionId, history: history || [] });
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = Number(process.env.PORT) || 4173;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI Companion remote control listening on http://0.0.0.0:${PORT}`);
});
