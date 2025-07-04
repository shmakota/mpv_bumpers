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
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then table.insert(insert_paths, name) end
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
