# MPV Bumper Inserter

This is a Lua script for [mpv](https://mpv.io/) that automatically inserts randomized **Adult Swim-style bumpers** between videos in your playlist, sourced from a custom list or [archive.org](https://archive.org/details/AdultswimBumps) by default.

It also includes a **toggle key (`b`)** to pause/resume bumpers on the fly, and a few more useful keybinds.

![image](https://github.com/user-attachments/assets/1518b52a-a6a1-44d3-bd02-60fe960100b4)
![image](https://github.com/user-attachments/assets/bc74d90b-3e1a-4166-bc22-4aaf3fc79050)

---

## Features

- 🎲 **Random bumper selection** from a customizable list
- 🔄 **Automatic insertion** of bumpers after each non-bumper playlist item
- ⌨️ **Toggle bumpers** with a keybind (`b`) - works instantly
- 💾 **Persistent settings** - save your bumper preferences across sessions
- 🔀 **Config file cycling** - easily switch between different bumper sets
- 🎬 **Smart playlist handling** - inserts bumpers without stopping or rebuilding the active playlist

---

## Installation

1. Copy the Lua script to your mpv `scripts/` directory:

```bash
~/.config/mpv/scripts/bumpers/main.lua
```

   **Note:** The script must be in a `bumpers/` subdirectory within `scripts/`.

2. Create a config file at:

```bash
~/.config/mpv/script-opts/bumpers.conf
```

### Example `bumpers.conf`:

```ini
# Base URL or local path where bumpers are located
base_url=https://archive.org/download/AdultswimBumps/

# Comma-separated list of bumper filenames
bumper_list=bump1.mp4,bump2.mkv,bump3.webm

# Avoid shifting the active playlist item by only inserting after it
insert_after_current_only=yes

# Keep odd-resolution/old-aspect bumpers from resizing the mpv window
prevent_bumper_resize=yes
```

**Configuration options:**
- `base_url` - Base URL or local directory path prepended to each bumper filename
  - Can be a remote URL (e.g., `https://archive.org/download/AdultswimBumps/`)
  - Can be a local path (e.g., `/path/to/bumpers/` or `file:///path/to/bumpers/`)
- `bumper_list` - Comma-separated list of bumper filenames (no spaces around commas)
- `insert_after_current_only` - Defaults to `yes`. Avoids shifting the active playlist item when mpv is already playing.
- `prevent_bumper_resize` - Defaults to `yes`. Temporarily sets `auto-window-resize=no` and `keepaspect-window=no` while a bumper is playing, then restores your previous values.

**Multiple config files:**
You can create multiple config files (e.g., `bumpers-as.conf`, `bumpers-bumpworthy.conf`) and cycle between them using `Shift+B`.

---

## Usage

1. **Start playing a playlist** in mpv - the script will automatically process it and insert bumpers.

2. **Keybindings:**
   - **`b`** - Toggle bumpers on/off (temporary, works immediately)
     - Shows "Bumpers enabled" or "Bumpers paused" in OSD
   - **`Ctrl+B`** - Toggle bumpers persistently (saves to settings file, requires restart)
   - **`Shift+B`** - Cycle between different config files (requires restart)

3. **Bumpers finish like normal playlist entries** - mpv advances to the next item at EOF.

---

## How It Works

The script uses an in-place playlist insertion approach that:

1. **On file load:** The script inspects the current playlist and inserts missing bumpers after valid video files.
2. **Playback preservation:** The script uses in-place `loadfile ... insert-at` commands instead of `stop`, `playlist-clear`, and reload.
3. **Smart detection:** If the next item is already a configured bumper, the script leaves that entry alone.
4. **Normal EOF behavior:** Bumpers are ordinary playlist entries, so mpv advances naturally when they end.

**Supported video formats:** mp4, mkv, avi, mov, webm, m4v, flv, wmv, mpg, mpeg

---

## Dependencies

- [mpv](https://mpv.io/) with Lua support (default in most builds)
- Works with both local and remote bumper sources

---

## Troubleshooting

**Bumpers not appearing:**
- Check that `bumpers.conf` exists in `~/.config/mpv/script-opts/`
- Verify `bumper_list` is not empty and filenames are correct
- Ensure `base_url` is correct (trailing slash recommended for URLs)
- Check that the script file is at `~/.config/mpv/scripts/bumpers/main.lua`

**Playlist not updating:**
- Try restarting mpv
- Check that bumpers are enabled (press `b` to toggle)
- Verify your video files have supported extensions

**Bumpers playing but not advancing:**
- Check that mpv is allowed to advance through the playlist normally
- Check that bumper filenames in your config match the actual files

---

## Tests

The repository includes a small Lua test harness at `tests/bumpers_spec.lua`. Run it from the repository root with:

```bash
lua tests/bumpers_spec.lua
```

The local machine used for this audit did not have `lua` or `luajit` on PATH, so the test file was added but could not be executed here.

---

## Credits

- Bumpers archive hosted via [archive.org](https://archive.org/details/AdultswimBumps)
- Cursor vibe coding
