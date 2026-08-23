require("dotenv").config();
const { Rcon } = require("rcon-client");

async function main() {
  const c = await Rcon.connect({ host: process.env.RCON_HOST, port: Number(process.env.RCON_PORT), password: process.env.RCON_PASSWORD });

  const ironFurnaces = [[-14, -51], [-12, -51], [-10, -51], [-8, -51]];
  let ironTotal = 0;
  for (const [x, y] of ironFurnaces) {
    const raw = await c.send(`/fac_building_empty 3 iron-plate 60 ${x} ${y}`);
    try { ironTotal += JSON.parse(raw.trim()).extracted || 0; } catch {}
  }

  const raw2 = await c.send("/fac_building_empty 3 copper-plate 30 46 -153");
  let copperTotal = 0;
  try { copperTotal = JSON.parse(raw2.trim()).extracted || 0; } catch {}

  console.log(`collected iron-plate=${ironTotal} copper-plate=${copperTotal}`);
  c.end();
}
main().catch((e) => { console.error("ERR", e); process.exit(1); });
