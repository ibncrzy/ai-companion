const Anthropic = require("@anthropic-ai/sdk");
const { sendCommand } = require("./rcon");

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const MODEL = process.env.CLAUDE_BRAIN_MODEL || "claude-haiku-4-5-20251001";
const MAX_HISTORY_TURNS = Number(process.env.CLAUDE_BRAIN_MAX_HISTORY_TURNS) || 12;

// Keep only the last MAX_HISTORY_TURNS real user messages (and everything after
// the oldest one kept), so a long chat session doesn't grow the request forever.
// Tool-result messages are also role:"user" but have array content, not a string,
// so they don't count as turn boundaries and never get split from their tool_use.
function capHistory(history) {
  const userTurnIndices = history
    .map((m, i) => (m.role === "user" && typeof m.content === "string" ? i : -1))
    .filter((i) => i !== -1);
  if (userTurnIndices.length <= MAX_HISTORY_TURNS) return history;
  const cutIndex = userTurnIndices[userTurnIndices.length - MAX_HISTORY_TURNS];
  return history.slice(cutIndex);
}

const COMMAND_REFERENCE = `
All commands take a companion id as their first argument (unless noted). Send the exact command text, e.g. "fac_move_to 28 100 200".

action: fac_action_attack <id> <x> <y> | fac_action_flee <id> [dist] | fac_action_wololo <id> | fac_action_attack_start <id> <x> <y> | fac_action_attack_status <id> | fac_action_attack_stop <id> | fac_action_defend <id> <on|off>
building: fac_building_can_place <id> <entity> <x> <y> [dir] | fac_building_place <id> <entity> <x> <y> [dir] | fac_building_place_start <id> <entity> <x> <y> [dir] | fac_building_place_status <id> | fac_building_remove <id> <entity> <x> <y> | fac_building_rotate <id> <x> <y> <dir 0-3> | fac_building_info <id> <entity> <x> <y> | fac_building_recipe <id> <recipe> <x> <y> | fac_building_fuel <id> <fuel_item> [amount] | fac_building_empty <id> <item> [count] [x] [y] | fac_building_fill <id> <item> [count] [x] [y]
companion: fac_companion_list | fac_companion_spawn [id] | fac_companion_disappear <id> | fac_companion_position <id> | fac_companion_health <id> [target] | fac_companion_inventory <id> [x] [y]
goal: fac_goal_create <id|-> [watch_type] [description] | fac_goal_update <id> <status> [note] | fac_goal_list [id|status] | fac_goal_get <id> | fac_goal_delete <id>
item: fac_item_craft <id> <item> [count] | fac_item_craft_start <id> <recipe> [count] | fac_item_craft_status <id> | fac_item_craft_stop <id> | fac_item_pick <id> [filter] [radius] | fac_item_recipes <id> [filter|active]
move: fac_move_to <id> <x> <y> | fac_move_follow <id> <player_name> | fac_move_stop <id>
research: fac_research_get <id> | fac_research_progress <id> [tech_name] | fac_research_set <id> <tech_name>
resource: fac_resource_list <id> [resource_name] [radius] | fac_resource_mine <id> <x> <y> [count] [resource_name] | fac_resource_mine_status <id> | fac_resource_mine_stop <id> | fac_resource_nearest <id> <name>  (aliases: copper,iron,coal,stone,uranium,oil)
world: fac_world_nearest <id> <name> (aliases: copper,iron,coal,stone,uranium,wood,water) | fac_world_scan <id> [radius] [filter] | fac_world_enemies <id> [radius]
chat: fac_chat_say <id|0> <msg>  (id=0 speaks as [Claude] in game chat, visible to the player)

Prefer the tick-based *_start/*_status/*_stop commands for anything that takes time (mining, crafting, building, attacking) rather than instant variants, unless the user clearly wants it done instantly.
`.trim();

const TOOLS = [
  {
    name: "run_fac_command",
    description:
      "Run a single ai-companion mod console command over RCON and get its JSON response back. Only fac_* commands are accepted.",
    input_schema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: 'Full command text, e.g. "fac_move_to 28 100 200" or "fac_companion_list".',
        },
      },
      required: ["command"],
    },
    cache_control: { type: "ephemeral" },
  },
];

function systemPrompt(companionId) {
  return `You are the in-game brain for a Factorio "AI companion" — a controllable character in the player's base. The player is chatting with you from their phone while playing on their PC.

Default companion id to act on (unless the player names a different one): ${companionId ?? "ask the player, or use fac_companion_list to find one"}.

You control the companion by calling the run_fac_command tool with exact ai-companion mod commands. Command reference:

${COMMAND_REFERENCE}

Rules:
- Take action via tool calls rather than just describing what you'd do.
- Keep replies short and conversational — this is a phone chat window, not a report.
- If a command's JSON response has an "error" field, explain briefly what went wrong and try a sensible fix (e.g. companion not found -> fac_companion_list first).
- Don't spawn/kill companions unless asked.`;
}

async function runTool(toolUse) {
  const { command } = toolUse.input || {};
  if (typeof command !== "string" || !/^fac[_ ]/.test(command.trim())) {
    return { error: "Only fac_* commands are allowed" };
  }
  try {
    const result = await sendCommand(command);
    return result.json !== null ? result.json : { raw: result.raw };
  } catch (err) {
    return { error: err.message };
  }
}

async function chat({ message, companionId, history }) {
  const messages = [...capHistory(history), { role: "user", content: message }];
  const commandLog = [];

  for (let turn = 0; turn < 6; turn++) {
    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: [{ type: "text", text: systemPrompt(companionId), cache_control: { type: "ephemeral" } }],
      tools: TOOLS,
      messages,
    });

    messages.push({ role: "assistant", content: response.content });

    const toolUses = response.content.filter((b) => b.type === "tool_use");
    if (toolUses.length === 0) {
      const text = response.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("\n");
      return { reply: text, commandLog, history: messages };
    }

    const toolResults = [];
    for (const toolUse of toolUses) {
      const output = await runTool(toolUse);
      commandLog.push({ command: toolUse.input?.command, output });
      toolResults.push({
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: JSON.stringify(output),
      });
    }
    messages.push({ role: "user", content: toolResults });
  }

  return { reply: "(stopped after too many tool calls — try a simpler request)", commandLog, history: messages };
}

module.exports = { chat };
