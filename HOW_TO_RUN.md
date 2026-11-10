# How to run the games (beginner-friendly)

🇷🇺 [Читать на русском](HOW_TO_RUN_RU.md)

Every game is **one single `.exe` file**. You do **not** need to install anything: no Godot, no Blender, no Python.
Download one file, double-click it, play.

## What you need

- **Windows 10 or 11, 64-bit.**
- A graphics card with **Vulkan** support and an up-to-date driver (practically any NVIDIA or AMD card from the last
  ~8 years; recent Intel graphics usually work too, just slower).
- About **8 GB of RAM** and **~500 MB of free disk space** per game.
- A keyboard and a mouse.

## Step 1 - Download one file

Open the **Releases** page: **https://github.com/Prokopiy8247/Fable5-2-Effort-Test-GTA/releases/tag/v1.0**

Scroll down to **Assets** and click the file of the game you want to try. You only need **one** file.

| Folder / effort level | Game | File to download |
|---|---|---|
| `Low` | Port Fable | `Low_PortFable.exe` |
| `Medium` | Port Cinder | `Medium_PortCinder.exe` |
| `High` | Marlow Bay | `High_MarlowBay.exe` |
| `Extra` | Cinder Bay | `Extra_CinderBay.exe` |
| `Max` | Neon Tide: Vesper Bay | `Max_NeonTide.exe` |
| `Ultracode` | Halcyon Bay | `Ultracode_HalcyonBay.exe` |

Each file is roughly 105-150 MB, so the download can take a minute.

## Step 2 - Start the game

1. Open your **Downloads** folder.
2. **Double-click** the `.exe` file you downloaded.

### "Windows protected your PC" / browser warning - this is normal

The games are small hobby builds and are **not digitally signed**, so Windows and browsers show a warning.

- **Browser** (Chrome / Edge) says the file "isn't commonly downloaded": click the `...` next to the download ->
  **Keep** -> **Keep anyway**.
- **Windows SmartScreen** shows a blue "Windows protected your PC" window: click **More info** -> **Run anyway**.
- Some antivirus programs may scan the file for a few seconds the first time. That is fine.

If you do not want to run an unsigned file, you can build and run the game yourself from the source code - see
"Advanced" at the bottom.

## Step 3 - Play

The first start can take from a few seconds up to **~30 seconds** while the city is built. Please wait, the window may look frozen for a moment.

Basic controls (they are almost the same in all six games):

| Key | Action |
|---|---|
| `W` `A` `S` `D` | Move / drive |
| Mouse | Look around, `LMB` shoot, `RMB` aim |
| `Shift` | Sprint |
| `Space` | Jump (handbrake in a car) |
| `F` | Get in / out of a vehicle (steal a car) |
| `E` | Interact (shops, doors, ...) |
| `Tab` | Weapon wheel |
| `M` | Map |
| `Esc` | Pause menu |
| `F1` | Admin / test menu (spawn vehicles, weapons and more) |
| `F5` / `F9` | Quick save / quick load |

Small differences exist between the games (for example the phone key). The exact controls are listed in `DEVELOPMENT.md` inside each game's folder (and in the pause menu in most of them). In `High` you can also press `F11` for
fullscreen.

## Something went wrong?

- **Nothing happens, or the window closes immediately:** update your graphics driver (NVIDIA, AMD or Intel website),
  restart the PC and try again.
- **Black screen or crash:** close other heavy programs (browsers with many tabs, other games) and try again. Try
  another game from the list - they differ in size and complexity.
- **Low FPS:** close other programs. These are large open-world games made by an AI agent in a single session, so performance differs from game to game.
- **Antivirus deleted the file:** it is a false positive for unsigned programs. Restore it from quarantine and add an
  exception, or use the "Advanced" option below.
- **How do I remove a game?** Just delete the `.exe`. Saves (if any) are stored in
  `%APPDATA%\Godot\app_userdata\` - delete the game's folder there if you want to wipe them.

## Advanced - run from source (optional)

1. Install **Godot 4.7.2 stable** from https://godotengine.org/download/archive/ (the standard, non-.NET version).
2. Download or clone this repository.
3. Start Godot, click **Import**, choose the `project.godot` file inside one of the folders (`Low`, `Medium`, `High`,
   `Extra`, `Max`, `Ultracode`) and press **F5** to play.

Blender is needed only if you want to edit the 3D assets (the `.blend` file in each folder).
