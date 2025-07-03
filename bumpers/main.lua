local insert_paths = require("bumpers")

local busy = false
local bumpers_enabled = true  -- bumper toggle flag

-- Show OSD message for 2 seconds
local function show_osd(msg)
    mp.osd_message(msg, 2)
end

-- Check if the given path matches one of the bumper videos
local function is_bumper(path)
    if not path then return false end
    for _, bumper in ipairs(insert_paths) do
        if path == bumper then
            return true
        end
    end
    return false
end

-- Select a random bumper video from the list
local function pick_random_bumper()
    if #insert_paths == 0 then return nil end
    math.randomseed(os.time() + os.clock() * 1000)
    return insert_paths[math.random(#insert_paths)]
end

local BASE_URL = "https://archive.org/download/AdultswimBumps/"

-- Insert a bumper video immediately after the current one in the playlist
local function insert_bumper()
    if not bumpers_enabled then return end  -- don't insert if paused
    if busy then return end
    busy = true

    local current_path = mp.get_property("path")
    local current_pos = mp.get_property_number("playlist-pos", 0)

    if is_bumper(current_path) then
        busy = false
        return
    end

    local playlist = mp.get_property_native("playlist")
    local next_entry = playlist[current_pos + 2]
    if next_entry and is_bumper(next_entry.filename) then
        busy = false
        return
    end

    local bumper = pick_random_bumper()
    if not bumper then
        busy = false
        return
    end

    local bumper_url = BASE_URL .. bumper
    mp.commandv("loadfile", bumper_url, "append")

    mp.observe_property("playlist-count", "number", function()
        mp.unobserve_property("playlist-count")

        local playlist_count = #mp.get_property_native("playlist")
        local bumper_pos = playlist_count - 1
        local insert_pos = current_pos + 1

        if bumper_pos ~= insert_pos then
            mp.commandv("playlist-move", bumper_pos, insert_pos)
        end

        busy = false
    end)
end

-- Handle the end of file event to skip over bumper videos automatically
local function on_end_file(event)
    if event.reason ~= 0 then return end  -- Only act on normal end-of-file (not errors or manual stops)

    local path = mp.get_property("path")
    if is_bumper(path) then
        mp.command("playlist-next")

        local playlist = mp.get_property_native("playlist")
        local pos = mp.get_property_number("playlist-pos", 0)
        local next_entry = playlist[pos + 2]

        if next_entry and is_bumper(next_entry.filename) then
            mp.command("playlist-next")
        end
    end
end

-- Toggle bumpers on/off and show OSD message
local function toggle_bumpers()
    bumpers_enabled = not bumpers_enabled
    if bumpers_enabled then
        show_osd("Bumpers resumed")
    else
        show_osd("Bumpers paused")
    end
end

-- Register events
mp.register_event("file-loaded", insert_bumper)
mp.register_event("end-file", on_end_file)

-- Bind B key to toggle bumpers
mp.add_key_binding("b", "toggle_bumpers", toggle_bumpers)