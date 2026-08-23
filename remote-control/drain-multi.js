require("dotenv").config();
const { Rcon } = require("rcon-client");

const positions = [
  [-14, -51],
  [-12, -51],
  [-10, -51],
  [-8, -51],
];
const PER_FURNACE = 20;
const ITEM = "iron-plate";
const ID = 3;

async function main() {
  const c = await Rcon.connect({ host: process.env.RCON_HOST, port: Number(process.env.RCON_PORT), password: process.env.RCON_PASSWORD });
  const totals = positions.map(() => 0);
  while (totals.some((t, i) => t < PER_FURNACE)) {
    for (let i = 0; i < positions.length; i++) {
      if (totals[i] >= PER_FURNACE) continue;
      const [x, y] = positions[i];
      const raw = await c.send(`/fac_building_empty ${ID} ${ITEM} ${PER_FURNACE - totals[i]} ${x} ${y}`);
      let extracted = 0;
      try { extracted = JSON.parse(raw.trim()).extracted || 0; } catch {}
      totals[i] += extracted;
    }
    console.log(`totals: ${totals.join(",")} (target ${PER_FURNACE} each)`);
    if (totals.every((t) => t >= PER_FURNACE)) break;
    await new Promise((r) => setTimeout(r, 4000));
  }
  console.log("DONE total extracted:", totals.reduce((a, b) => a + b, 0));
  c.end();
}
main().catch((e) => { console.error("ERR", e); process.exit(1); });
