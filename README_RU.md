# Fable 5.2 Effort Test - игра в стиле GTA на Godot + Blender MCP

🇬🇧 [Read in English](README.md)

Одна и та же задача была выдана **Claude Fable 5.2** шесть раз, каждый раз с другим **уровнем мышления (effort)**:
сделать GTA-подобную «песочницу» с открытым миром без миссий на **Godot 4.7**, причём все 3D-ассеты создаются в
**Blender** через **Blender MCP**. Каждый уровень работал в своей папке, со своим экземпляром Blender и своим портом,
полностью независимо от остальных.

## Просто хотите поиграть?

Каждая игра - один `.exe`, ничего устанавливать не нужно.
**-> [Как запустить игры (простая инструкция)](HOW_TO_RUN_RU.md)** | **[Releases (скачать)](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/tag/v1.0)**

## Результаты по уровням мышления

| Папка | Уровень | Игра | Порт Blender MCP | Скачать |
|---|---|---|---|---|
| [`Low`](Low) | Low | Port Fable | 9877 | [`Low_PortFable.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Low_PortFable.exe) |
| [`Medium`](Medium) | Medium | Port Cinder | 9878 | [`Medium_PortCinder.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Medium_PortCinder.exe) |
| [`High`](High) | High | Marlow Bay | 9879 | [`High_MarlowBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/High_MarlowBay.exe) |
| [`Extra`](Extra) | Extra | Cinder Bay | 9880 | [`Extra_CinderBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Extra_CinderBay.exe) |
| [`Max`](Max) | Max | Neon Tide: Vesper Bay | 9881 | [`Max_NeonTide.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Max_NeonTide.exe) |
| [`Ultracode`](Ultracode) | Ultracode | Halcyon Bay | 9882 | [`Ultracode_HalcyonBay.exe`](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/download/v1.0/Ultracode_HalcyonBay.exe) |

## Что внутри каждой папки

Каждая папка - полноценный самостоятельный проект Godot 4.7.2:

| Файл / папка | Что это |
|---|---|
| `project.godot`, `gta/` | Проект Godot: код на GDScript, сцены и импортированные ассеты |
| `GodotFable5.2GTA<Уровень>.blend` | Главный Blender-файл, в котором агент работал через Blender MCP |
| `tools/` | Скрипты агента для генерации ассетов в Blender, проверок и метрик |
| `Claude_Fable_5.2_Godot_GTA_BlenderMCP_Prompt.md` | Полный промпт задачи для агента (одинаковый для всех уровней, кроме порта и имени файла) |
| `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, `FABLE_5.2_FINAL_REPORT.md` | Заметки агента: управление, список возможностей, итоговый отчёт с метриками сессии |
| `.fable-5.2-gta-runs/` | Время старта / окончания и данные об использовании за сессию |
| `export_presets.cfg` | Пресет экспорта под Windows (PCK внутри, один `.exe`) |

В репозиторий не включены: готовые `.exe` (они лежат в [Releases](https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/tag/v1.0)
из-за ограничения GitHub на размер файла), кэш Godot (`.godot/`), резервные копии Blender, а также скриншоты и логи
проверок агентов.

## Гайды

- **Гайд по настройке Blender MCP** - как подключить Blender к Claude Code / Codex через MCP (один проект, один
  `.blend`-файл, один порт):
  [Русский (PDF)](Blender_MCP_Guide_RU.pdf) | [English (PDF)](Blender_MCP_Guide_EN.pdf)
  В гайде в качестве примера используется Unity; для Godot шаги те же.
- **Как запустить игры:** [Русский](HOW_TO_RUN_RU.md) | [English](HOW_TO_RUN.md)

## Примечания

- Игры задуманы как **оригинальные**: задача запрещает использовать ассеты из GTA и других игр, а 3D-ассеты создавались в Blender через MCP.
- Каждую игру сделал ИИ-агент за одну автономную сессию. Возможны шероховатости и баги.
- `.exe`-файлы не подписаны, поэтому Windows SmartScreen покажет предупреждение - см. [инструкцию по запуску](HOW_TO_RUN_RU.md).
