-- MPV bumper‑inserter, playlist‑rebuild approach

local mp      = require("mp")
local options = require("mp.options")

-- Default options
local opts = {
    bumper_list = "",  -- CSV: "b1.mp4,b2.mp4,b3.mp4"
    base_url    = "https://archive.org/download/AdultswimBumps/",
}

-- Read script‑opts/bumpers.conf
options.read_options(opts, "bumpers")

-- Parse bumpers into a table of filenames
local insert_paths = {}
for name in opts.bumper_list:gmatch("([^,]+)") do
    if name then
        name = name:match("^%s*(.-)%s*$") or ""
        if name ~= "" then table.insert(insert_paths, name) end
    end
end

-- Helper: is this path one of our bumpers?
local function is_bumper(path)
    if not path then return false end
    for _, name in ipairs(insert_paths) do
        if path:sub(-#name) == name then
            return true
        end
    end
    return false
end

-- Helper: is this a “real” video that should get a bumper after it?
local function is_valid_video_file(path)
    if not path or path == "" then return false end
    if is_bumper(path) then return false end
    local ext = path:match("%.([^.]+)$")
    if not ext then return false end
    ext = ext:lower()
    local good = {
      mp4=true, mkv=true, avi=true, mov=true, webm=true,
      m4v=true, flv=true, wmv=true, mpg=true, mpeg=true,
    }
    return good[ext] == true
end

-- Pick a random bumper (seed once)
math.randomseed(os.time())
local function pick_random_bumper()
    if #insert_paths == 0 then return nil end
    return insert_paths[math.random(#insert_paths)]
end

-- OSD helper
local function show_osd(msg)
    mp.osd_message(msg, 2)
end

-- State
local bumpers_inserted = false
local bumpers_enabled  = true

-- Rebuild playlist exactly once, interleaving bumpers
local function rebuild_playlist()
    if bumpers_inserted then return end
    bumpers_inserted = true

    local orig = mp.get_property_native("playlist")
    if not orig or #orig == 0 then return end

    -- Build new playlist array
    local newlist = {}
    for _, entry in ipairs(orig) do
        table.insert(newlist, entry.filename)
        if is_valid_video_file(entry.filename) then
            local b = pick_random_bumper()
            if b then
                table.insert(newlist, opts.base_url .. b)
            end
        end
    end

    -- Stop playback, clear, and re‑append everything
    mp.command("stop")
    mp.command("playlist-clear")
    for _, url in ipairs(newlist) do
        mp.commandv("loadfile", url, "append")
    end

    -- Start playing at the very first item
    mp.command("playlist-play-index 0")
end

-- Skip bumpers automatically at end of file
local function on_end_file(event)
    if event.reason ~= "eof" and event.reason ~= 0 then return end
    local path = mp.get_property("path")
    if is_bumper(path) then
        mp.command("playlist-next")
    end
end

-- Toggle bumpers on/off
local function toggle_bumpers()
    bumpers_enabled = not bumpers_enabled
    show_osd(bumpers_enabled and "Bumpers paused" or "Bumpers resumed")
end

local config_dir = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/mpv/script-opts/"
local bumpers_settings_file = config_dir .. "bumpers-settings.conf"

-- Persistent bumpers enabled state (requires restart)
local function save_bumpers_enabled_state(state)
    local f = io.open(bumpers_settings_file, "w")
    if f then
        f:write(state and "1" or "0")
        f:close()
    end
end

local function load_bumpers_enabled_state()
    local f = io.open(bumpers_settings_file, "r")
    if f then
        local val = f:read("*l")
        f:close()
        return val == "1"
    end
    return true -- default: enabled
end

bumpers_enabled = load_bumpers_enabled_state()

-- CTRL+B: persistently enable/disable bumpers (requires restart)
local function toggle_bumpers_persistent()
    bumpers_enabled = not bumpers_enabled
    save_bumpers_enabled_state(bumpers_enabled)
    show_osd((bumpers_enabled and "Bumpers enabled (restart required)") or "Bumpers disabled (restart required)")
end

-- SHIFT+B: cycle config files in config dir
local config_files = {}
local config_index = 1
local utils = require("mp.utils")

local function scan_config_files()
    config_files = {}
    local files = utils.readdir(config_dir, "files")
    if files then
        for _, file in ipairs(files) do
            if file:match("^bumpers.*%.conf$") and file ~= "bumpers-settings.conf" then
                table.insert(config_files, file)
            end
        end
        table.sort(config_files)
    end
end

scan_config_files()

local function cycle_config_file()
    if #config_files == 0 then
        show_osd("No config files found")
        return
    end
    config_index = config_index % #config_files + 1
    local selected = config_files[config_index]
    -- Only copy if not already the main config
    if selected ~= "bumpers.conf" then
        -- Copy selected config to bumpers.conf
        local src = config_dir .. selected
        local dst = config_dir .. "bumpers.conf"
        local infile = io.open(src, "r")
        if infile then
            local content = infile:read("*a")
            infile:close()
            local outfile = io.open(dst, "w")
            if outfile then
                outfile:write(content)
                outfile:close()
                show_osd("Config: " .. selected .. " (restart required)")
            else
                show_osd("Failed to write bumpers.conf")
            end
        else
            show_osd("Failed to read " .. selected)
        end
    else
        show_osd("Config: bumpers.conf (restart required)")
    end
end

-- Hook: once we’ve loaded the very first file, rebuild the playlist
mp.register_event("start-file", function()
    -- give MPV a few ticks to populate `playlist`
    mp.add_timeout(0.05, rebuild_playlist)
end)

-- Hook: skip bumpers if enabled
mp.register_event("end-file", function(event)
    if bumpers_enabled then on_end_file(event) end
end)

mp.add_key_binding("b", "toggle_bumpers", toggle_bumpers)
mp.add_key_binding("Ctrl+b", "toggle_bumpers_persistent", toggle_bumpers_persistent)
mp.add_key_binding("Shift+b", "cycle_config_file", cycle_config_file)
