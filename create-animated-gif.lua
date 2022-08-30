-- Script: create-animated-gif.lua

-- Create animated gif from your OBS recordings on the fly

description = [[<span>
Stop recording automatically after given video length, then call postprocessing command with (x, y, width, height) of the selected group.
For easier handling, use the script hotkey in Settings→Hotkeys.
</span>]]

-- global variables
obs = obslua
script_version            = "1.00"
hotkey_id                 = obs.OBS_INVALID_HOTKEY_ID

font_dimmed               = "#b0b020"

scene_name                = ""
source_name               = ""
video_start               = 0.0
video_length              = 0.0
video_fps                 = 0
output_directory          = ""
postprocessing_command    = ""
postprocessing_filename   = ""
postprocessing_ext        = ""
postprocessing_gif_colors = 0
postprocessing_variations = false
postprocessing_drop_audio = false
postprocessing_active       = false
postprocess_recording = false

recording_start_time = 0
my_settings = nil
my_props = nil

DEBUG = false
-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------

log = {
    debug = function(message) if DEBUG then obs.script_log(obs.LOG_DEBUG, "[DEBUG] " .. message) end end,
    info  = function(message) obs.script_log(obs.LOG_INFO, message) end,
    warn  = function(message) obs.script_log(obs.LOG_WARNING, "[WARNING] " .. message) end, -- triggers script log window popup
    error = function(message) obs.script_log(obs.LOG_ERROR, "[ERROR] " .. message) end  -- triggers script log window popup
}


function get_scene_by_name(scene_name)

    local scene_source = obs.obs_get_source_by_name(scene_name) -- creates reference that has to be released
    local scene_context = obs.obs_scene_from_source(scene_source) -- uses the same reference as scene_source

    return scene_context
end


function get_sceneitem_by_name(scene_name, source_name)

    local scene = get_scene_by_name(scene_name)
    local source = obs.obs_get_source_by_name(source_name)
    local scene_item = obs.obs_scene_sceneitem_from_source(scene, source)
    obs.obs_source_release(source)
    obs.obs_scene_release(scene)

    return scene_item
end


function is_hotkey_configured()
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    local have_hotkey = obs.obs_data_array_count(hotkey_save_array) ~= 0
    obs.obs_data_array_release(hotkey_save_array)
    return have_hotkey
end


-- populate given combo box list with all existing scenes
function populate_scene_list(scene_property)

    obs.obs_property_list_clear(scene_property)

    local scenes = obs.obs_frontend_get_scenes()
    if scenes ~= nil then

        obs.obs_property_list_add_string(scene_property, "", "")
        for _, scene in ipairs(scenes) do
            local name = obs.obs_source_get_name(scene)
            obs.obs_property_list_add_string(scene_property, name, name)
        end

        obs.source_list_release(scenes)
    end

end


-- populate given combo box list with all existing sources from a given scene
function populate_source_list(source_property, scene_name)

    log.debug("populate_sources_list begin scene_name='" .. scene_name .. "'")
    obs.obs_property_list_clear(source_property)

    if scene_name ~= "" then
        local scene = get_scene_by_name(scene_name)
        local scene_items = obs.obs_scene_enum_items(scene)
        if scene_items ~= nil then
            for _, scene_item in ipairs(scene_items) do
                local source = obs.obs_sceneitem_get_source(scene_item)
                local name = obs.obs_source_get_name(source)
                local source_id = obs.obs_source_get_unversioned_id(source) -- source_id is source type like "text_gdiplus", "text_ft2_source" etc.
                log.debug("populate_sources_list add source name='" .. name .. "' source_id='" .. source_id .. "'")
                obs.obs_property_list_add_string(source_property, name, name)
            end
        end
        obs.sceneitem_list_release(scene_items)
        obs.obs_scene_release(scene)
    end

    log.debug("populate_sources_list end")

end


-- Determine if current recording output is active
--
-- Cannot use obs.obs_frontend_recording_active(), because that may return false
-- but the output is actually still active (after stop command) or already active
-- (after start command)
function is_recording_output_active()

    local output = obs.obs_frontend_get_recording_output()
    local active = obs.obs_output_active(output)
    obs.obs_output_release(output)
    return active
end


-- get current recording filename from current recording output
function get_recording_filename()

    local output = obs.obs_frontend_get_recording_output()
    local settings = obs.obs_output_get_settings(output)

    -- filename is either in the "path" or in the "url" field
    local filename = obs.obs_data_get_string(settings, "path")
    if filename == "" then
        filename = obs.obs_data_get_string(settings, "url")
    end
    if filename == "" then
        local json = obs.obs_data_get_json(settings)
        log.warn("unable to get filename; settings=" .. json)
    end
    obs.obs_data_release(settings)
    obs.obs_output_release(output)

    return filename
end


-- perform postprocessing
function run_postprocessing()

    if postprocessing_filename == "" then
        log.warn("Postprocessing requested by user, but no recording video file known")
        return
    end

    if postprocessing_command == "" then
        log.warn("Postprocessing requested by user, but no postprocessing command defined in script settings")
        return
    end

    -- get sceneitem for the section
    local scene_item = get_sceneitem_by_name(scene_name, source_name)
    if scene_item then

        -- get section position and size
        local info = obs.obs_transform_info()
        obs.obs_sceneitem_get_info(scene_item, info)

        local size = obs.vec2()
        if info.bounds_type == obs.OBS_BOUNDS_NONE then
            local source = obs.obs_sceneitem_get_source(scene_item)
            local source_size = obs.vec2()

            source_size.x = obs.obs_source_get_width(source)
            source_size.y = obs.obs_source_get_height(source)

            obs.vec2_mul(size, source_size, info.scale)
            obs.vec2_addf(size, size, 0.5)
            log.debug("run_postprocessing no bounding box; source_size=(" .. source_size.x .. "," .. source_size.y .. ") * scale=(" .. info.scale.x .. "," .. info.scale.y .. ") => scaled_size=(" .. size.x .. "," .. size.y .. ")")
        else
            size = info.bounds
        end
        log.info("Postprocessing uses " .. scene_name .. "." .. source_name .. ": section=(" .. info.pos.x .. "," .. info.pos.y .. "," .. size.x .. "," .. size.y .. ")")

        obs.obs_sceneitem_release(scene_item)

        local dir = output_directory ~= "" and output_directory or obs.obs_frontend_get_current_record_output_path()

        local cmd = string.format([[""%s" "%s" "%s" %d %d %d %d %.2f %.2f %d %s %d %s %s"]],
            postprocessing_command,
            postprocessing_filename,
            dir,
            info.pos.x, info.pos.y, size.x, size.y, video_start, video_length, video_fps,
            postprocessing_ext,
            postprocessing_gif_colors,
            tostring(postprocessing_variations),
            tostring(not postprocessing_drop_audio)
        )

        log.info("Postprocessing executing >>" .. cmd .. "<<")
        local rc = os.execute(cmd)
        log.info("Postprocessing return code=" .. rc)

    else
        log.warn("Postprocessing unable to find given source '" .. source_name .. "' in scene '" .. scene_name .. "'")
    end

end


-- set notice according to hotkey and auto processing
function set_notice_visibility(props, settings)

    if props == nil then
        return
    end

    local active = obs.obs_data_get_bool(settings, "postprocessing_active")
    local hotkey_configured = is_hotkey_configured()

    local info = obs.obs_properties_get(props, "info1")
    obs.obs_property_set_visible(info, not active and not hotkey_configured)

    info = obs.obs_properties_get(props, "info2")
    obs.obs_property_set_visible(info, not active and hotkey_configured)

    info = obs.obs_properties_get(props, "info3")
    obs.obs_property_set_visible(info, active)

end


-------------------------------------------------------------------------------
-- event handlers
-------------------------------------------------------------------------------

-- recording timer elapsed: stop recording, so postprocessing can begin
function on_recording_timer_elapsed()

    obs.remove_current_callback()

    if is_recording_output_active() then
        log.info("Stopping recording due to timer that was started " .. ((obs.os_gettime_ns() - recording_start_time)  / 1000 / 1000 / 1000) .. " seconds ago" )
        obs.obs_frontend_recording_stop()
    end

end


-- restart timer elapsed: if the output has stopped, call the hotkey function to start recording
function on_try_restart_recording()

    if not is_recording_output_active() then

        obs.remove_current_callback()
        on_hotkey_start(true)

    end

end


-- the hotkey for starting video was pressed
function on_hotkey_start(pressed)

    if not pressed then
        return
    end

    obs.timer_remove(on_try_restart_recording)
    obs.timer_remove(on_recording_timer_elapsed)

    if is_recording_output_active() or postprocess_recording then

        log.info("Hotkey pressed, but OBS is already recording! Will stop recording and try to restart.")
        postprocess_recording = false
        obs.obs_frontend_recording_stop()

        -- schedule restart in 100 ms
        obs.timer_add(on_try_restart_recording, 100)

    else

        obs.obs_frontend_recording_start()
        postprocess_recording = true
        log.info("User pressed hotkey for recording start and automated postprocessing")

    end

end


-- recording has started and is now capturing
-- task: start timer for stop and postprocessing
function on_recording_activate(cd)

    log.debug("on_recording_activate recording has been activated")

    recording_start_time = obs.os_gettime_ns()

    if postprocessing_active and not postprocess_recording then
        postprocess_recording = true
        log.info("Script is configured to do automatic recording stop and postprocessing")
    end

    if postprocess_recording then

        local duration = video_start + video_length + 10.0
        if duration < 30.0 and postprocessing_variations then
            duration = 30.0
        end

        obs.timer_remove(on_recording_timer_elapsed)
        obs.timer_add(on_recording_timer_elapsed, duration * 1000)

        log.info("Automated postprocessing activated: will stop recording in " .. duration .. " seconds.")
    end

end


-- recording was stopped, so do postprocessing
function on_recording_stopped(cd_output, cd)

    -- remove timer if recording was stopped prematurely
    obs.timer_remove(on_recording_timer_elapsed)

    local code = obs.calldata_int(cd, "code")
    if code == 0 then -- OBS_OUTPUT_SUCCESS, but it's not defined for lua

        postprocessing_filename = get_recording_filename()
        log.debug("on_recording_stopped successful recording; filename='" .. postprocessing_filename .. "'")

        if postprocess_recording then
            if (obs.os_gettime_ns() - recording_start_time)  / 1000 / 1000 / 1000 >= video_start + video_length then
                run_postprocessing()
            end
        end

    end

    postprocess_recording = false

end


-- user selected some scene from the scene list
-- populate the source list with sources from the selected scene
function on_scene_modified(props, prop, settings)

    local scene_name = obs.obs_data_get_string(settings, "scene")
    local source_list = obs.obs_properties_get(props, "source")
    populate_source_list(source_list, scene_name)
    obs.obs_data_set_string(settings, "source", "")

    set_notice_visibility(props, settings)

    return true
end


-- if the video extension (gif, mp4, ...) was changed, set visibility for corresponding properties
function on_video_ext_modified(props, prop, settings)

    local ext = obs.obs_data_get_string(settings, "postprocessing_ext")

    -- toggle debug logging
    if ext == "debug" then
        DEBUG = not DEBUG
        obs.obs_data_set_string(settings, "postprocessing_ext", "gif")
        ext = "gif"
    end

    -- offer drop audio only if not picture format
    local audio = obs.obs_properties_get(props, "postprocessing_drop_audio")
    obs.obs_property_set_visible(audio, ext ~= "gif" and ext ~= "webp")

    -- offer variations for gif only
--    local variations = obs.obs_properties_get(props, "postprocessing_variations")
--    obs.obs_property_set_visible(variations, ext == "gif")

    -- offer gif colors for gif only
    local colors = obs.obs_properties_get(props, "postprocessing_gif_colors")
    obs.obs_property_set_visible(colors, ext == "gif")

    set_notice_visibility(props, settings)

    return true
end


-- set notice according to hotkey and auto processing
function on_property_modified(props, prop, settings)
    set_notice_visibility(props, settings)
    return true
end


function properties_add_info(props, name, label, text)

    local p = obs.obs_properties_add_text(props, name, "<font color=".. font_dimmed ..">".. label .."</font>", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(p, "<font color=".. font_dimmed ..">".. text .."</font>")
    obs.obs_property_text_set_info_type(p, obs.OBS_TEXT_INFO_NORMAL)
    return p

end

-------------------------------------------------------------------------------
-- main script hooks
-------------------------------------------------------------------------------

-- Define properties the user can change for this script module
-- This builds the script settings GUI in Tools->Scripts
function script_properties()

    local props = obs.obs_properties_create()

    -- determine current fps for convenience
    local ovi = obs.obs_video_info()
    obs.obs_get_video_info(ovi)
    local curfps = ovi.fps_num / ovi.fps_den

    local info1 = properties_add_info(props, "info1", "Passive:", "No Auto Postprocessing and no hotkey (use Process Again)")
    local info2 = properties_add_info(props, "info2", "Hotkey:", "Hotkey set for Auto Postprocessing")
    local info3 = properties_add_info(props, "info3", "Automatic:", "Auto stop recordings after Offset+Length seconds")

    -- create and populate drop-down list for scenes
    local scene = obs.obs_properties_add_list(props, "scene", "Scene", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_scene_list(scene)

    -- create and populate drop-down list for source
    local source = obs.obs_properties_add_list(props, "source", "Section", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_source_list(source, scene_name)
    obs.obs_property_set_long_description(source,
        "\nThe size of this section (group or source) will determine\nthe rectangle (x, y, width, height) given as parameter\nto the postprocessing command.\n")

    -- start of postprocessed video
    -- increment for start and length is time for 1 frame
    local start = obs.obs_properties_add_float_slider(props, "start", "Start Offset", 0, 60, 1/curfps)
    obs.obs_property_float_set_suffix(start, " s") -- undocumented API call
    obs.obs_property_set_long_description(start, "\nPostprocessed video starts at this offset (seconds)\n")

    -- length of postprocessed video
    local length = obs.obs_properties_add_float_slider(props, "length", "Video Length", 0, 60, 1/curfps)
    obs.obs_property_float_set_suffix(length, " s") -- undocumented API call
    obs.obs_property_set_long_description(length, "\nPostprocessed video length (seconds)\n")

    -- fps of postprocessed video
    local fps = obs.obs_properties_add_list(props, "fps", "Frame Rate", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    local curfps_text = "Current (" .. string.format((ovi.fps_den == 1 and "%d" or "%.2f"), curfps) .. " fps)"
    obs.obs_property_list_add_int(fps, curfps_text, 0)
    obs.obs_property_list_add_int(fps, "5", 5)
    obs.obs_property_list_add_int(fps, "10", 10)
    obs.obs_property_list_add_int(fps, "15", 15)
    obs.obs_property_list_add_int(fps, "20", 20)
    obs.obs_property_list_add_int(fps, "30", 30)
    obs.obs_property_list_add_int(fps, "60", 60)

    -- postprocessing script location
    local cmd = obs.obs_properties_add_path(props, "postprocessing_command", "Command", obs.OBS_PATH_FILE,
        "Command (*.bat *.cmd *.exe *.ps1)", script_path())
    obs.obs_property_set_long_description(cmd,
        "\nExternal OS command for postprocessing. Called as\n\n<postprocessing command> <video file> <output directory> <x> <y> <width> <height> <start> <length> <fps> <ext> <colors> <variations> <drop audio>\n")

    -- output directory
    local dir = obs.obs_properties_add_path(props, "output_directory", "Output Dir", obs.OBS_PATH_DIRECTORY,
        "Output directory", obs.obs_frontend_get_current_record_output_path())
    obs.obs_property_set_long_description(dir, "\nSecond parameter for the postprocessing command.\n")

    -- output type drop-down list
    local ext = obs.obs_properties_add_list(props, "postprocessing_ext", "Output Type", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(ext, "gif", "gif")
    obs.obs_property_list_add_string(ext, "mp4", "mp4")
    obs.obs_property_list_add_string(ext, "webm", "webm")
    obs.obs_property_list_add_string(ext, "webp", "webp")

    -- gif palette
    local palette = obs.obs_properties_add_list(props, "postprocessing_gif_colors", "GIF Colors", obs.OBS_COMBO_TYPE_LIST , obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(palette, "2", 2)
    obs.obs_property_list_add_int(palette, "4", 4)
    obs.obs_property_list_add_int(palette, "16", 16)
    obs.obs_property_list_add_int(palette, "64", 64)
    obs.obs_property_list_add_int(palette, "256", 256)
    obs.obs_property_set_long_description(palette, "\nSize of GIF palette; affects final gif size.\n")

    -- button "process again"
    local again = obs.obs_properties_add_button(props, "button_again", "Process Again",
        function() run_postprocessing() return true end)
    obs.obs_property_set_long_description(again, "\nProcess last video again with updated settings\n")

    -- checkbox for creating video variations
    local variations = obs.obs_properties_add_bool(props, "postprocessing_variations", "Create additional Variations")
    obs.obs_property_set_long_description(variations,
        "\nCreate a number of additional files\nvariated in length and fps.\n")

    -- checkbox for dropping audio
    local audio = obs.obs_properties_add_bool(props, "postprocessing_drop_audio", "Drop Audio")

    -- checkbox for enabling postprocess
    local active = obs.obs_properties_add_bool(props, "postprocessing_active", "Auto Postprocessing Active")
    obs.obs_property_set_long_description(active,
        "\nAutomated recording stop and postprocessing.\nIf deactivated, the hotkey will initiate auto recording stop and processing for one video.\nIf deactivated and no hotkey, stop recording manually and use the Process Again button.\n")

    -- setup callbacks on values modified
    obs.obs_property_set_modified_callback(scene, on_scene_modified)
    obs.obs_property_set_modified_callback(ext, on_video_ext_modified)

    -- try to keep notice up to date; unfortunately there is no way to trigger a refresh
    -- on hotkey changes directly.
    obs.obs_property_set_modified_callback(source, on_property_modified)
    obs.obs_property_set_modified_callback(fps, on_property_modified)
    obs.obs_property_set_modified_callback(variations, on_property_modified)
    obs.obs_property_set_modified_callback(active, on_property_modified)

    -- initially set visibility according to stored settings
    on_video_ext_modified(props, ext, my_settings)
    set_notice_visibility(props, my_settings)

    my_props = props
    return props
end


-- Return the description shown to the user
function script_description()
    return string.format(description, tostring(script_version))
end


-- Whenever settings are changed, script_update is called
function script_update(settings)

    scene_name = obs.obs_data_get_string(settings, "scene")
    source_name = obs.obs_data_get_string(settings, "source")
    video_start = obs.obs_data_get_double(settings, "start")
    video_length = obs.obs_data_get_double(settings, "length")
    video_fps = obs.obs_data_get_int(settings, "fps")
    postprocessing_command = obs.obs_data_get_string(settings, "postprocessing_command")
    output_directory = obs.obs_data_get_string(settings, "output_directory")
    postprocessing_ext = obs.obs_data_get_string(settings, "postprocessing_ext")
    postprocessing_gif_colors = obs.obs_data_get_int(settings, "postprocessing_gif_colors")
    postprocessing_variations = obs.obs_data_get_bool(settings, "postprocessing_variations")
    postprocessing_drop_audio = obs.obs_data_get_bool(settings, "postprocessing_drop_audio")
    postprocessing_active = obs.obs_data_get_bool(settings, "postprocessing_active")

    log.debug("script_update got scene_name='" .. scene_name .. "'")
    log.debug("script_update got source_name='" .. source_name .. "'")
    log.debug("script_update got video_start=" .. video_start)
    log.debug("script_update got video_length=" .. video_length)
    log.debug("script_update got video_fps=" .. video_fps)
    log.debug("script_update got postprocessing_command='" .. postprocessing_command .. "'")
    log.debug("script_update got output_directory='" .. output_directory .. "'")
    log.debug("script_update got postprocessing_ext='" .. postprocessing_ext .. "'")
    log.debug("script_update got postprocessing_gif_colors=" .. postprocessing_gif_colors)
    log.debug("script_update got postprocessing_variations=" .. tostring(postprocessing_variations))
    log.debug("script_update got postprocessing_drop_audio=" .. tostring(postprocessing_drop_audio))
    log.debug("script_update got postprocessing_active=" .. tostring(postprocessing_active))

    my_settings = settings
end


-- Called to set default settings
function script_defaults(settings)

    local source = obs.obs_frontend_get_current_scene() -- we get a source actually, not a scene(!)
    local name = obs.obs_source_get_name(source)
    obs.obs_source_release(source)

    local pcmd = script_path() .. "postprocess-from-obs.cmd"
    if not obs.os_file_exists(pcmd) then
        pcmd = ""
    end

    obs.obs_data_set_default_string(settings, "scene", name)
    obs.obs_data_set_default_string(settings, "source", "")
    obs.obs_data_set_default_double(settings, "start", 1.00)
    obs.obs_data_set_default_double(settings, "length", 5.00)
    obs.obs_data_set_default_int(settings, "fps", 10)
    obs.obs_data_set_default_string(settings, "postprocessing_command", pcmd)
    obs.obs_data_set_default_string(settings, "output_directory", obs.obs_frontend_get_current_record_output_path())
    obs.obs_data_set_default_string(settings, "postprocessing_ext", "gif")
    obs.obs_data_set_default_int(settings, "postprocessing_gif_colors", 64)
    obs.obs_data_set_default_bool(settings, "postprocessing_variations", true)
    obs.obs_data_set_default_bool(settings, "postprocessing_drop_audio", false)
    obs.obs_data_set_default_bool(settings, "postprocessing_active", false)

end


-- Called on OBS startup
function script_load(settings)

    -- register hotkey(s)
    hotkey_id = obs.obs_hotkey_register_frontend("create_gif_recording_start.trigger", "Start recording for animated GIF", on_hotkey_start)
    local hotkey_save_array = obs.obs_data_get_array(settings, "create_gif_recording_start.trigger")
    obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    -- register signal callbacks
    local output = obs.obs_frontend_get_recording_output()
    local sh = obs.obs_output_get_signal_handler(output)

    obs.signal_handler_connect(sh, "activate", on_recording_activate)
    obs.signal_handler_connect(sh, "stop", on_recording_stopped)

    obs.obs_output_release(output)

end


-- Called when OBS configuration is saved
-- Settings from script properties are saved automatically, but hotkey
-- configuration has to be saved here.
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "create_gif_recording_start.trigger", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    set_notice_visibility(my_props, settings)
end


-- Called on OBS shutdown
-- Notice: must not call obs.script_log(...) from this callback - OBS crash
function script_unload(settings)
end
