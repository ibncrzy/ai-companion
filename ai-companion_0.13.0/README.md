# AI Companion - Factorio Mod

Topics: [factorio](https://github.com/topics/factorio) · [factorio-mod](https://github.com/topics/factorio-mod) · [lua](https://github.com/topics/lua) · [rcon](https://github.com/topics/rcon) · [ai-agent](https://github.com/topics/ai-agent) · [game-automation](https://github.com/topics/game-automation)

## Installation

### Windows
```bash
xcopy /E /I factorio-mod "%APPDATA%\Factorio\mods\ai-companion"
```

### Linux
```bash
cp -r factorio-mod ~/.factorio/mods/ai-companion
```

### Mac
```bash
cp -r factorio-mod ~/Library/Application\ Support/factorio/mods/ai-companion
```

## Enable the Mod

1. Launch Factorio
2. Main Menu → Mods
3. Find "AI Companion" in the list
4. ✅ Enable it
5. Restart Factorio

## Usage

### In-Game Chat Commands

**Send message to AI:**
```
/companion Hello! Can you help me?
```

### RCON Commands (for MCP server)

**Get unread messages:**
```
/companion_get_messages
```

**Send response to chat:**
```
/companion_send Your message here
```

**Cleanup old messages:**
```
/companion_cleanup
```

## Features

- ✅ Chat message capture with `/companion` prefix
- ✅ Safe error handling (pcall wrappers)
- ✅ JSON serialization for RCON
- ✅ Auto-cleanup of old messages
- ✅ Compatible with Factorio 2.x and 1.1+

## Requirements

- Factorio must be started with "Start as server" option
- RCON must be enabled (port 25575, password: factorio)

## RCON Connection Requirements

The mod's `fac_*` commands only work over RCON (or typed directly in-game) — they can't be reached by anything that just runs arbitrary Lua against the game (see below). An external orchestrator/AI needs a working RCON connection to control companions at all.

- **RCON is a Factorio launch-time flag, not something this mod sets.** Start the server with `--start-server <save> --rcon-port <port> --rcon-password <password>` (or the equivalent `server-settings.json` fields). The port/password above are just this mod's documented defaults — always confirm against your actual launch config.
- **The port can change** any time the server is restarted with different flags. If RCON connections start failing, re-verify rather than assuming the documented port still applies:
  - Find the server process: `Get-Process factorio | Select-Object Id,StartTime` (Windows)
  - Find its actual listening port: `Get-NetTCPConnection -State Listen -OwningProcess <pid> | Select-Object LocalPort`
  - Confirm it accepts connections: `Test-NetConnection -ComputerName 127.0.0.1 -Port <port> | Select-Object TcpTestSucceeded`
- **A tool that only runs raw Lua via RCON (`/sc`/`/c`-style execution) cannot invoke `fac_*` console commands**, and that execution context has its own separate `storage` — it can't read this mod's state directly either. The one thing that works from raw Lua is `remote.call("ai_companion_bridge", "function_name", ...)`, since `remote.call` runs inside the mod's own environment. Use the bridge, not `fac_*`, when driving the mod from that kind of tool.
- **Mod code changes don't take effect until the mod reloads** (reload the save or restart Factorio) — editing `control.lua` live has no effect on a running game until then.
