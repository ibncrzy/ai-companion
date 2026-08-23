require("dotenv").config();
const { Rcon } = require("rcon-client");

const [, , item, target, id, x, y] = process.argv;

async function main() {
  const c = await Rcon.connect({ host: process.env.RCON_HOST, port: Number(process.env.RCON_PORT), password: process.env.RCON_PASSWORD });
  let total = 0;
  while (total < Number(target)) {
    const raw = await c.send(`/fac_building_empty ${id} ${item} ${Number(target) - total} ${x} ${y}`);
    let extracted = 0;
    try { extracted = JSON.parse(raw.trim()).extracted || 0; } catch {}
    total += extracted;
    console.log(`extracted ${extracted}, total ${total}/${target}`);
    if (total >= Number(target)) break;
    await new Promise((r) => setTimeout(r, 4000));
  }
  c.end();
}
main().catch((e) => { console.error("ERR", e); process.exit(1); });
