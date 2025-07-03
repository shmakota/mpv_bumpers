# MPV Bumper Inserter

This is a Lua script for [mpv](https://mpv.io/) that automatically inserts randomized **Adult Swim-style bumpers** between videos in your playlist, sourced from a custom list or [archive.org](https://archive.org/details/AdultswimBumps) by default.

It also includes a **toggle key (`b`)** to pause/resume bumpers on the fly.

![image](https://github.com/user-attachments/assets/b673708a-3a93-44b6-a35c-62adcd95592b)

---

## Features

- Random bumper selection from a customizable list
- Automatically inserts bumpers *after* each non-bumper playlist item
- Skips bumpers on EOF (no manual skipping needed)
- Toggle bumpers with a keybind (`b`)

---

## Installation

1. Copy the Lua script to your mpv `scripts/` directory:

```
~/.config/mpv/scripts/bumpers.lua
```

2. Create a config file at:

```
~/.config/mpv/script-opts/bumpers.conf
```

### Example `bumpers.conf`:

```ini
bumper_list = bump1.mp4,bump2.mkv,bump3.webm
base_url = https://archive.org/download/AdultswimBumps/
```

- `bumper_list` is a comma-separated list of bumper filenames
- `base_url` is prepended to each filename (can be a local path or remote URL)

---

## Usage

- Just play a playlist in mpv and let the script do its thing.
- Press **`b`** to toggle bumper insertion on/off. An OSD message will confirm the state.

---

## How It Works

- When a new file is loaded, the script checks if it's a bumper.
- If not, a random bumper is inserted *after* it in the playlist.
- When a bumper ends, it's automatically skipped to the next real video.
- Duplicate bumper insertions are avoided.

---

## Dependencies

- [mpv](https://mpv.io/) with Lua support (default in most builds)
- Works with both local and remote bumper sources

---

## Credits

- Bumpers archive hosted via [archive.org](https://archive.org/details/AdultswimBumps)
- ChatGPT vibe coding
