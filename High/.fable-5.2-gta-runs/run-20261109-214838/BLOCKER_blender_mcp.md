# Hard blocker — no Blender MCP connection exposed to this session

Run ID: run-20261109-214838
Start: 2026-11-09T21:48:38.597+01:00 (Central European Standard Time)
Blocker recorded: 2026-11-09 ~21:55 +01:00

## What was checked (all read-only)

- Project folder: `G:\YouTube\Fable 5.2 Effort Test GTA\High` (contains `project.godot`, Godot 4.7 / Forward+).
- `GodotFable5.2GTAHigh.blend` exists in that folder (97,553 bytes).
- Blender process PID 29684 (`W:\Blender\blender.exe`) was launched with
  `G:\YouTube\Fable 5.2 Effort Test GTA\High\GodotFable5.2GTAHigh.blend` and owns the listener on `127.0.0.1:9879`.
  So the Blender side (add-on socket) is up.
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (4.7.2 stable).

## The blocker

The agent session has **no MCP server/tool namespace for Blender at all**:

- Session connectors: `claude-artifacts`, `Claude Docs`, `scheduled-tasks` only.
- Tool search for "blender" returns nothing.
- No `.mcp.json` in this folder or its parent; `~/.claude.json` has no `mcpServers` entry for this
  project (the only Blender entries belong to another project, `W:/YouTube/Claude Sonnet 5.5`,
  ports 9889–9891); `claude_desktop_config.json` has no `mcpServers`.

Section 0 step 3 (identify the MCP connection for `localhost:9879`) and step 4 (a real read-only
Blender MCP call) therefore cannot be performed. No Blender change was made, no backup was needed,
nothing in the Godot project was modified.

## Minimum correction (user action — the spec forbids the agent registering servers itself)

Register an MCP server for port 9879 scoped to this project, then restart/reconnect the session, e.g.
from a terminal in this folder:

    claude mcp add blender-godot-high -s project -- uvx mcp-for-blender --port 9879

(or the equivalent `.mcp.json` in this folder; same package the other project already uses).

## Not done on purpose

- Did not talk to the add-on socket on 9879 directly (that would bypass the MCP connection).
- Did not build the game with engine primitives in place of Blender-authored assets.
