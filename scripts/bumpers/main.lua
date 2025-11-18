--[[ 
MPV Bumper Inserter (Improved Dynamic Approach)

Automatically interleaves "bumper" videos between valid videos in your playlist.
Supports:
    - Random bumper selection
    - Skip bumper automatically at EOF
    - Persistent bumper enable/disable
    - Config file cycling
    - Dynamic playlist insertion (no full rebuild)
--]]

local mp      = require("mp")
local options = require("mp.options")
local utils   = require("mp.utils")

----------------------------------------
-- 1. DEFAULT CONFIGURATION & OPTIONS
----------------------------------------
local opts = {
    bumper_list = "",  -- CSV of bumper filenames, e.g. "b1.mp4,b2.mp4"
    base_url    = "https://archive.org/download/AdultswimBumps/",
}

-- Load options from 'bumpers.conf'
options.read_options(opts, "bumpers")

-- Parse bumper CSV into a Lua table
local insert_paths = {}
for name in opts.bumper_list:gmatch("([^,]+)") do
    if name then
        name = name:match("^%s*(.-)%s*$") or ""
        if name ~= "" then
            table.insert(insert_paths, name)
        end
    end
end

----------------------------------------
-- 2. HELPER FUNCTIONS
----------------------------------------

-- Check if a given path corresponds to a bumper
local function is_bumper(path)
    if not path then return false end
    for _, name in ipairs(insert_paths) do
        -- Check if path ends with the bumper name (handles both full URLs and filenames)
        if path:sub(-#name) == name or path:find(name, 1, true) then
            return true
        end
    end
    return false
end

-- Check if a file is a "valid" video to have bumpers inserted after
local function is_valid_video_file(path)
    if not path or path == "" then return false end
    if is_bumper(path) then return false end

    local ext = path:match("%.([^.]+)$")
    if not ext then return false end
    ext = ext:lower()

    local valid_exts = {
        mp4=true, mkv=true, avi=true, mov=true, webm=true,
        m4v=true, flv=true, wmv=true, mpg=true, mpeg=true,
    }
    return valid_exts[ext] == true
end

-- Pick a random bumper from the list
math.randomseed(os.time())
local function pick_random_bumper()
    if #insert_paths == 0 then return nil end
    return insert_paths[math.random(#insert_paths)]
end

-- Show OSD messages
local function show_osd(msg)
    mp.osd_message(msg, 2)
end

----------------------------------------
-- 3. STATE VARIABLES
----------------------------------------
local bumpers_enabled = true
local playlist_processed = false  -- Track if we've already processed the current playlist

local config_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/mpv/script-opts/"
local bumpers_settings_file = config_dir .. "bumpers-settings.conf"

----------------------------------------
-- 4. IMPROVED PLAYLIST REBUILDING
----------------------------------------

-- Rebuild playlist with bumpers inserted, preserving playback state
local function rebuild_playlist_with_bumpers()
    if not bumpers_enabled then return end
    if playlist_processed then return end
    if #insert_paths == 0 then return end
    
    local orig_playlist = mp.get_property_native("playlist")
    if not orig_playlist or #orig_playlist == 0 then return end
    
    -- Check if playlist already has bumpers (avoid double-processing)
    local has_bumpers = false
    for _, entry in ipairs(orig_playlist) do
        if is_bumper(entry.filename) then
            has_bumpers = true
            break
        end
    end
    
    if has_bumpers then
        playlist_processed = true
        return
    end
    
    -- Save current playback state
    local current_pos = mp.get_property_number("playlist-pos", 0)
    local current_path = mp.get_property("path")
    local was_playing = mp.get_property("pause") == "no"
    local time_pos = mp.get_property_number("time-pos", 0)
    
    -- Build new playlist with bumpers
    local new_playlist = {}
    local new_current_pos = 0
    
    for i, entry in ipairs(orig_playlist) do
        table.insert(new_playlist, entry.filename)
        
        -- Track the new position of the current file
        if i - 1 == current_pos then
            new_current_pos = #new_playlist - 1
        end
        
        -- Insert bumper after valid video files
        if is_valid_video_file(entry.filename) then
            local bumper_name = pick_random_bumper()
            if bumper_name then
                local bumper_url = opts.base_url .. bumper_name
                table.insert(new_playlist, bumper_url)
            end
        end
    end
    
    -- Rebuild the playlist
    mp.command("stop")
    mp.command("playlist-clear")
    
    for _, url in ipairs(new_playlist) do
        mp.commandv("loadfile", url, "append")
    end
    
    -- Restore playback position
    mp.set_property("playlist-pos", new_current_pos)
    
    -- Restore playback state
    if was_playing and current_path then
        mp.add_timeout(0.1, function()
            if time_pos > 0 then
                mp.set_property("time-pos", time_pos)
            end
            mp.set_property("pause", "no")
        end)
    end
    
    playlist_processed = true
end

----------------------------------------
-- 5. BUMPER HANDLING
----------------------------------------

-- Skip bumpers automatically at the end of file
local function on_end_file(event)
    -- Only process EOF events (reason 0 or "eof")
    if event.reason ~= "eof" and event.reason ~= 0 then return end
    
    local path = mp.get_property("path")
    if is_bumper(path) then
        -- Automatically skip to next item when bumper ends
        mp.command("playlist-next")
    end
end

-- Toggle bumpers on/off (temporary)
local function toggle_bumpers()
    bumpers_enabled = not bumpers_enabled
    show_osd(bumpers_enabled and "Bumpers enabled" or "Bumpers paused")
end

-- Persistent enable/disable bumpers (requires restart)
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
    return true
end

bumpers_enabled = load_bumpers_enabled_state()

local function toggle_bumpers_persistent()
    bumpers_enabled = not bumpers_enabled
    save_bumpers_enabled_state(bumpers_enabled)
    show_osd((bumpers_enabled and "Bumpers enabled (restart required)") or
             "Bumpers disabled (restart required)")
end

----------------------------------------
-- 6. CONFIG FILE CYCLING
----------------------------------------
local config_files = {}
local config_index = 1

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

    if selected ~= "bumpers.conf" then
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

----------------------------------------
-- 7. EVENT HOOKS
----------------------------------------

-- Process playlist when first file loads
mp.register_event("file-loaded", function()
    -- Use a small delay to ensure playlist is stable
    mp.add_timeout(0.1, function()
        rebuild_playlist_with_bumpers()
    end)
end)

-- Automatically skip bumpers at EOF
mp.register_event("end-file", function(event)
    -- Only process EOF events (reason 0 or "eof")
    if event.reason ~= "eof" and event.reason ~= 0 then return end
    
    local path = mp.get_property("path")
    if path and is_bumper(path) and bumpers_enabled then
        -- Automatically skip to next item when bumper ends
        mp.command("playlist-next")
    end
end)

-- Reset processed flag when playlist is cleared or significantly changed
mp.register_event("playlist-reloaded", function()
    playlist_processed = false
end)

----------------------------------------
-- 8. KEYBINDINGS
----------------------------------------
mp.add_key_binding("b",        "toggle_bumpers",          toggle_bumpers)
mp.add_key_binding("Ctrl+b",   "toggle_bumpers_persistent", toggle_bumpers_persistent)
mp.add_key_binding("Shift+b",  "cycle_config_file",       cycle_config_file)
