local commands = {}
local properties = {
    path = "episode 01.mkv",
    ["auto-window-resize"] = "yes",
    ["keepaspect-window"] = "yes",
    ["stream-open-filename"] = "episode 01.mkv",
}
local playlist = {
    { filename = "episode 01.mkv" },
    { filename = "episode 02.mkv" },
    { filename = "notes.txt" },
}

package.preload["mp"] = function()
    return {
        get_property_native = function(name)
            if name == "playlist" then return playlist end
            return nil
        end,
        get_property_number = function(name, default)
            if name == "playlist-pos" then return 0 end
            return default
        end,
        get_property = function(name)
            return properties[name]
        end,
        set_property = function(name, value)
            properties[name] = value
        end,
        commandv = function(...)
            table.insert(commands, {...})
            local args = {...}
            if args[1] == "loadfile" and args[3] == "insert-at" then
                table.insert(playlist, args[4] + 1, { filename = args[2] })
            elseif args[1] == "loadfile" and args[3] == "insert-next" then
                table.insert(playlist, 2, { filename = args[2] })
            end
        end,
        command_native = function(args)
            if args[1] == "expand-path" then return "C:/mpv/script-opts/" end
            if args[1] == "loadfile" and args[3] == "insert-at" then
                table.insert(commands, args)
                table.insert(playlist, args[4] + 1, { filename = args[2] })
            end
            return nil
        end,
        command = function(value)
            table.insert(commands, { value })
        end,
        add_timeout = function(_, fn) fn() end,
        osd_message = function() end,
        add_key_binding = function() end,
        add_hook = function(_, _, fn) fn() end,
        register_event = function(_, fn) fn({ reason = "eof" }) end,
        observe_property = function() end,
    }
end

package.preload["mp.options"] = function()
    return {
        read_options = function(opts, name)
            if name == "bumpers" then
                opts.base_url = "https://example.test/bumpers"
                opts.bumper_list = "bumper one.mp4, bumper-two.webm"
            elseif name == "bumpers_options" then
                opts.chapter_bumper_blacklist = "intro,op,opening,ed,ending,preview,recap,next"
            end
        end,
    }
end

package.preload["mp.utils"] = function()
    return {
        readdir = function() return {} end,
    }
end

local bumpers = dofile("scripts/bumpers/main.lua")

assert(#bumpers.parse_csv_list("a.mp4, b.mkv,, c.webm") == 3)
assert(bumpers.join_base_and_name("https://example.test/root", "b.mp4") == "https://example.test/root/b.mp4")
assert(bumpers.join_base_and_name("https://example.test/root/", "b.mp4") == "https://example.test/root/b.mp4")
assert(bumpers.is_valid_video_file("episode 01.mkv") == true)
assert(bumpers.is_valid_video_file("notes.txt") == false)
assert(bumpers.is_bumper("https://example.test/bumpers/bumper one.mp4") == true)
assert(bumpers.chapter_title_is_blacklisted("Intro") == true)
assert(bumpers.chapter_title_is_blacklisted("Opening Theme") == true)
assert(bumpers.chapter_title_is_blacklisted("Part A") == false)

assert(#commands == 2)
assert(commands[1][1] == "loadfile")
assert(commands[1][3] == "insert-at")
assert(commands[1][4] == 2)
assert(commands[2][4] == 1)
assert(#playlist == 5)
assert(playlist[1].filename == "episode 01.mkv")
assert(playlist[3].filename == "episode 02.mkv")
assert(properties["auto-window-resize"] == "yes")
assert(properties["keepaspect-window"] == "yes")

print("bumpers_spec.lua: ok")
