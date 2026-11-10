# Fable 5.2 Effort Test - GTA-style game in Godot + Blender MCP

🇷🇺 [Читать на русском](README_RU.md)

The same task was given to **Claude Fable 5.2** six times, each time with a different **effort (thinking) level**:
build a missionless GTA-style open-world sandbox in **Godot 4.7** with all 3D assets made in **Blender** through
**Blender MCP**. Each level worked in its own folder, with its own Blender instance and port, completely independently.

## Just want to play?

Every game is a single `.exe` - nothing to install.
**-> [How to run the games (simple guide)](HOW_TO_RUN.md)** | **[Releases (download)](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/tag/v1.0)**

## Results by effort level

| Folder | Effort level | Game | Blender MCP port | Download |
|---|---|---|---|---|
| [`Low`](Low) | Low | Port Fable | 9877 | [`Low_PortFable.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Low_PortFable.exe) |
| [`Medium`](Medium) | Medium | Port Cinder | 9878 | [`Medium_PortCinder.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Medium_PortCinder.exe) |
| [`High`](High) | High | Marlow Bay | 9879 | [`High_MarlowBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/High_MarlowBay.exe) |
| [`Extra`](Extra) | Extra | Cinder Bay | 9880 | [`Extra_CinderBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Extra_CinderBay.exe) |
| [`Max`](Max) | Max | Neon Tide: Vesper Bay | 9881 | [`Max_NeonTide.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Max_NeonTide.exe) |
| [`Ultracode`](Ultracode) | Ultracode | Halcyon Bay | 9882 | [`Ultracode_HalcyonBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Ultracode_HalcyonBay.exe) |

## What is inside each folder

Each folder is a complete, standalone Godot 4.7.2 project:

| File / folder | What it is |
|---|---|
| `project.godot`, `gta/` | The Godot project: GDScript code, scenes and imported assets |
| `GodotFable5.2GTA<Level>.blend` | The master Blender file that the agent worked in through Blender MCP |
| `tools/` | Scripts the agent used for Blender asset generation, checks and metrics |
| `Claude_Fable_5.2_Godot_GTA_BlenderMCP_Prompt.md` | The full task prompt given to the agent (identical for all levels except the port and file name) |
| `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, `FABLE_5.2_FINAL_REPORT.md` | Notes written by the agent: controls, feature checklist, final report with session metrics |
| `.fable-5.2-gta-runs/` | Start / end timestamps and usage records of the session |
| `export_presets.cfg` | Windows export preset (embedded PCK, single `.exe`) |

Not included in the repository: compiled `.exe` files (they are in [Releases](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/tag/v1.0)
because of GitHub's file size limit), Godot cache (`.godot/`), Blender backups, and the agents' QA screenshots and logs.

## Guides

- **Blender MCP setup guide** - how to connect Blender to Claude Code / Codex through MCP (one project, one `.blend`
  file, one port):
  [Русский (PDF)](Blender_MCP_Guide_RU.pdf) | [English (PDF)](Blender_MCP_Guide_EN.pdf)
  The guide uses Unity as its example; the same steps apply to Godot.
- **How to run the games:** [English](HOW_TO_RUN.md) | [Русский](HOW_TO_RUN_RU.md)

## Notes

- The games are meant to be **original**: the task forbids using assets from GTA or any other game, and the 3D assets were authored in Blender through MCP.
- Each game was made by an AI agent in a single autonomous session. Expect rough edges and bugs.
- The `.exe` files are unsigned, so Windows SmartScreen will warn you - see the [run guide](HOW_TO_RUN.md).
