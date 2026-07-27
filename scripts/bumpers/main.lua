--[[ 
MPV Bumper Inserter

Automatically interleaves "bumper" videos between valid videos in your playlist.
Supports:
    - Random bumper selection
    - Persistent bumper enable/disable
    - Config file cycling
    - In-place playlist insertion without interrupting playback
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
    insert_after_current_only = true,
    prevent_bumper_resize = true,
    chapter_bumpers_enabled = false,
    chapter_bumper_chance = 25,
    chapter_bumper_blacklist = "intro,op,opening,ed,ending,preview,recap,next",
    interval_bumpers_enabled = false,
    interval_bumper_minutes = 15,
    interval_bumper_jitter_minutes = 2,
    interval_bumper_min_duration_minutes = 45,
}

-- Load options from 'bumpers.conf'
options.read_options(opts, "bumpers")

-- Parse bumper CSV into a Lua table
local insert_paths = {}
local function parse_csv_list(value)
    local result = {}
    for name in tostring(value or ""):gmatch("([^,]+)") do
        name = name:match("^%s*(.-)%s*$") or ""
        if name ~= "" then
            table.insert(result, name)
        end
    end
    return result
end

insert_paths = parse_csv_list(opts.bumper_list)
local chapter_blacklist = parse_csv_list(opts.chapter_bumper_blacklist)

----------------------------------------
-- 2. HELPER FUNCTIONS
----------------------------------------

-- Check if a given path corresponds to a bumper
local function is_bumper(path)
    if not path then return false end
    for _, name in ipairs(insert_paths) do
        if path == name or path:sub(-#name) == name then
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

local function join_base_and_name(base, name)
    if not base or base == "" then return name end
    if base:sub(-1) == "/" or base:sub(-1) == "\\" then
        return base .. name
    end
    return base .. "/" .. name
end

local function clamp_percent(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

local function chance_passes(percent)
    return math.random(100) <= clamp_percent(percent)
end

local function chapter_title_is_blacklisted(title)
    title = tostring(title or ""):lower()
    if title == "" then return false end
    for _, blocked in ipairs(chapter_blacklist) do
        blocked = tostring(blocked or ""):lower()
        if blocked ~= "" and title:find(blocked, 1, true) then
            return true
        end
    end
    return false
end

local function minutes_to_seconds(minutes)
    return math.max(0, (tonumber(minutes) or 0) * 60)
end

local last_bumper_time = nil

local function get_interval_delay()
    local base = minutes_to_seconds(opts.interval_bumper_minutes)
    local jitter = minutes_to_seconds(opts.interval_bumper_jitter_minutes)
    if jitter <= 0 then return base end

    return math.max(1, base + math.random(-jitter, jitter))
end

local function mark_bumper_played()
    last_bumper_time = os.time()
end

-- Show OSD messages
local function show_osd(msg)
    mp.osd_message(msg, 2)
end

----------------------------------------
-- 3. STATE VARIABLES
----------------------------------------
local bumpers_enabled = true
local processing_playlist = false
local saved_window_options = nil
local last_chapter_key = nil
local chapter_interruption_state = nil
local allow_interval_schedule_during_resume = false
local interval_timer = nil

local function ensure_trailing_separator(path)
    if not path or path == "" then return path end
    if path:sub(-1) == "/" or path:sub(-1) == "\\" then return path end
    return path .. "/"
end

local function get_config_dir()
    if mp.command_native then
        local path = mp.command_native({"expand-path", "~~home/script-opts/"})
        if path and path ~= "" then
            return ensure_trailing_separator(path)
        end
    end

    local xdg = os.getenv("XDG_CONFIG_HOME")
    if xdg and xdg ~= "" then
        return ensure_trailing_separator(xdg .. "/mpv/script-opts")
    end

    local appdata = os.getenv("APPDATA")
    if appdata and appdata ~= "" then
        return ensure_trailing_separator(appdata .. "/mpv/script-opts")
    end

    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
    return ensure_trailing_separator(home .. "/.config/mpv/script-opts")
end

local config_dir = get_config_dir()
local bumpers_settings_file = config_dir .. "bumpers-settings.conf"

local function save_window_options()
    return {
        auto_window_resize = mp.get_property("auto-window-resize"),
        keepaspect_window = mp.get_property("keepaspect-window"),
    }
end

local function apply_window_options(options_table)
    if not options_table then return end
    if options_table.auto_window_resize ~= nil then
        mp.set_property("auto-window-resize", options_table.auto_window_resize)
    end
    if options_table.keepaspect_window ~= nil then
        mp.set_property("keepaspect-window", options_table.keepaspect_window)
    end
end

local function update_bumper_window_guard(path)
    if not opts.prevent_bumper_resize then return end

    if path and is_bumper(path) then
        mark_bumper_played()
        if interval_timer and interval_timer.kill then
            interval_timer:kill()
        end
        interval_timer = nil
        if not saved_window_options then
            saved_window_options = save_window_options()
        end
        mp.set_property("auto-window-resize", "no")
        mp.set_property("keepaspect-window", "no")
    elseif saved_window_options then
        apply_window_options(saved_window_options)
        saved_window_options = nil
    end
end

----------------------------------------
-- 4. IMPROVED PLAYLIST REBUILDING
----------------------------------------

-- Insert bumpers in-place. Avoid stop/clear/reload because that interrupts the
-- active file and can interfere with mpv watch-later/resume state.
local function insert_bumpers_into_playlist()
    if not bumpers_enabled then return end
    if chapter_interruption_state and not allow_interval_schedule_during_resume then return end
    if processing_playlist then return end
    if #insert_paths == 0 then return end
    
    local playlist = mp.get_property_native("playlist")
    if not playlist or #playlist == 0 then return end

    local current_pos = mp.get_property_number("playlist-pos", 0)
    local first_index = opts.insert_after_current_only and (current_pos + 1) or 1

    processing_playlist = true
    for i = #playlist, first_index, -1 do
        local entry = playlist[i]
        local next_entry = playlist[i + 1]
        local filename = entry and entry.filename
        if is_valid_video_file(filename)
            and not (next_entry and is_bumper(next_entry.filename)) then
            local bumper_name = pick_random_bumper()
            if bumper_name then
                mp.commandv("loadfile", join_base_and_name(opts.base_url, bumper_name), "insert-at", i)
            end
        end
    end
    processing_playlist = false
end

local function get_chapter_entry(chapter_index)
    if chapter_index == nil or chapter_index < 0 then return nil end
    local chapters = mp.get_property_native("chapter-list")
    if not chapters then return nil end
    return chapters[chapter_index + 1]
end

local function insert_interruption_bumper(path, resume_time)
    local bumper_name = pick_random_bumper()
    if not bumper_name then return false end

    if interval_timer and interval_timer.kill then
        interval_timer:kill()
    end
    interval_timer = nil

    local current_pos = mp.get_property_number("playlist-pos", 0)
    local resume_options = { start = tostring(resume_time) }

    chapter_interruption_state = "bumper"
    mp.commandv("loadfile", join_base_and_name(opts.base_url, bumper_name), "insert-next")
    mark_bumper_played()
    if mp.command_native then
        mp.command_native({"loadfile", path, "insert-at", current_pos + 2, resume_options})
    else
        mp.commandv("loadfile", path, "insert-at", current_pos + 2, "start=" .. tostring(resume_time))
    end
    mp.command("playlist-next")
    return true
end

local function maybe_insert_chapter_bumper(_, chapter_index)
    if not opts.chapter_bumpers_enabled then return end
    if not bumpers_enabled then return end
    if chapter_interruption_state then return end
    if #insert_paths == 0 then return end
    if chapter_index == nil or chapter_index < 1 then return end

    local path = mp.get_property("path")
    if not is_valid_video_file(path) then return end

    local chapter_entry = get_chapter_entry(chapter_index)
    if not chapter_entry then return end

    local chapter_title = chapter_entry.title or ""
    if chapter_title_is_blacklisted(chapter_title) then return end

    local chapter_time = tonumber(chapter_entry.time) or mp.get_property_number("time-pos", 0)
    local chapter_key = tostring(path) .. "#" .. tostring(chapter_index) .. "@" .. tostring(chapter_time)
    if chapter_key == last_chapter_key then return end
    last_chapter_key = chapter_key

    if not chance_passes(opts.chapter_bumper_chance) then return end

    insert_interruption_bumper(path, chapter_time)
end

local function kill_interval_timer()
    if interval_timer and interval_timer.kill then
        interval_timer:kill()
    end
    interval_timer = nil
end

local function maybe_insert_interval_bumper()
    interval_timer = nil

    if not opts.interval_bumpers_enabled then return end
    if not bumpers_enabled then return end
    if chapter_interruption_state then return end
    if #insert_paths == 0 then return end

    local path = mp.get_property("path")
    if not is_valid_video_file(path) then return end

    local duration = mp.get_property_number("duration", 0)
    if duration < minutes_to_seconds(opts.interval_bumper_min_duration_minutes) then return end

    local resume_time = mp.get_property_number("time-pos", 0)
    if resume_time <= 0 or resume_time >= duration then return end

    insert_interruption_bumper(path, resume_time)
end

local function schedule_interval_bumper()
    kill_interval_timer()

    if not opts.interval_bumpers_enabled then return end
    if not bumpers_enabled then return end
    if chapter_interruption_state then return end

    local path = mp.get_property("path")
    if not is_valid_video_file(path) then return end

    local duration = mp.get_property_number("duration", 0)
    if duration < minutes_to_seconds(opts.interval_bumper_min_duration_minutes) then return end

    local delay = get_interval_delay()
    if last_bumper_time then
        local elapsed = os.time() - last_bumper_time
        delay = math.max(delay - elapsed, 1)
    end

    interval_timer = mp.add_timeout(delay, maybe_insert_interval_bumper)
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

mp.add_hook("on_load", 50, function()
    update_bumper_window_guard(mp.get_property("stream-open-filename"))
end)

-- Process playlist when first file loads
mp.register_event("file-loaded", function()
    -- Use a small delay to ensure playlist is stable
    mp.add_timeout(0.1, function()
        insert_bumpers_into_playlist()
        schedule_interval_bumper()
        if allow_interval_schedule_during_resume then
            allow_interval_schedule_during_resume = false
            chapter_interruption_state = nil
        end
    end)
end)

mp.register_event("end-file", function()
    kill_interval_timer()
    if chapter_interruption_state == "bumper" then
        chapter_interruption_state = "resume"
        allow_interval_schedule_during_resume = true
    elseif chapter_interruption_state == "resume" then
        allow_interval_schedule_during_resume = false
        chapter_interruption_state = nil
    end
end)

mp.observe_property("chapter", "number", maybe_insert_chapter_bumper)

mp.register_event("shutdown", function()
    kill_interval_timer()
    apply_window_options(saved_window_options)
end)

----------------------------------------
-- 8. KEYBINDINGS
----------------------------------------
mp.add_key_binding("b",        "toggle_bumpers",          toggle_bumpers)
mp.add_key_binding("Ctrl+b",   "toggle_bumpers_persistent", toggle_bumpers_persistent)
mp.add_key_binding("Shift+b",  "cycle_config_file",       cycle_config_file)

return {
    parse_csv_list = parse_csv_list,
    is_bumper = is_bumper,
    is_valid_video_file = is_valid_video_file,
    join_base_and_name = join_base_and_name,
    chapter_title_is_blacklisted = chapter_title_is_blacklisted,
    chance_passes = chance_passes,
    minutes_to_seconds = minutes_to_seconds,
}
