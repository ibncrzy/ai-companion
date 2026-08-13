const { Rcon } = require("rcon-client");

let client = null;
let connecting = null;

async function getClient() {
  if (client) return client;
  if (connecting) return connecting;
  connecting = Rcon.connect({
    host: process.env.RCON_HOST || "127.0.0.1",
    port: Number(process.env.RCON_PORT) || 25575,
    password: process.env.RCON_PASSWORD,
  }).then((c) => {
    client = c;
    connecting = null;
    client.on("end", () => { client = null; });
    return client;
  }).catch((err) => {
    connecting = null;
    throw err;
  });
  return connecting;
}

// fac_* commands print JSON via rcon.print; everything else (plain text) is passed through.
// Factorio's RCON only executes console commands when prefixed with "/" (as if typed in chat).
async function sendCommand(command) {
  const c = await getClient();
  const withSlash = command.startsWith("/") ? command : "/" + command;
  const raw = await c.send(withSlash);
  const trimmed = raw.trim();
  try {
    return { raw: trimmed, json: JSON.parse(trimmed) };
  } catch {
    return { raw: trimmed, json: null };
  }
}

module.exports = { sendCommand };
