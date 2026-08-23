require("dotenv").config();
const { Rcon } = require("rcon-client");
(async () => {
  const c = await Rcon.connect({ host: process.env.RCON_HOST, port: Number(process.env.RCON_PORT), password: process.env.RCON_PASSWORD });
  const r = await c.send(`/fac_research_progress 1 ${process.argv[2]}`);
  console.log(r.trim());
  c.end();
})().catch((e) => { console.error("ERR", e); process.exit(1); });
