local files = ...
local api = reaper
local project = {}

local item_key = "P_EXT:PsyReaWwise_Source"
local region_section = "PsyReaWwise_Regions"
local render_command = 42230  -- Render using current settings, then close the render dialog.
local wave_24_bit = "ZXZhdxgAAA=="

local function pack_binding(origin, source)
    return table.concat({origin.id, origin.path, source.id}, "|")
end

local function unpack_binding(value)
    local project_id, project_path, source_id = value:match("^([^|]+)|([^|]+)|([^|]+)$")
    if source_id then return {project_id = project_id, project_path = project_path, source_id = source_id} end
end

function project.directory(current, purpose)
    local media_path = api.GetProjectPathEx(current)
    assert(media_path and media_path ~= "", "找不到 REAPER 工程的媒体目录。")
    local token = api.genGuid():gsub("[^%x]", "")
    return files.join(media_path, ("PsyReaWwise/%s/%s-%s"):format(purpose, os.date("%Y%m%d-%H%M%S"), token))
end

local function new_audio_source(path)
    local source = api.PCM_Source_CreateFromFileEx(path, true)
    assert(source, "REAPER 无法打开音频\n" .. path)
    local length, is_qn = api.GetMediaSourceLength(source)
    local rate = api.GetMediaSourceSampleRate(source)
    local channels = api.GetMediaSourceNumChannels(source)
    if not length or length <= 0 or is_qn or not rate or rate <= 0 or not channels or channels <= 0 then
        api.PCM_Source_Destroy(source)
        error("不是可用的音频文件\n" .. path, 0)
    end
    return source, {length = length, rate = rate, channels = channels}
end

function project.audio_info(path)
    local source, info = new_audio_source(path)
    api.PCM_Source_Destroy(source)
    return info
end

local function selected_items(current)
    local items = {}
    for index = 0, api.CountSelectedMediaItems(current) - 1 do
        items[#items + 1] = api.GetSelectedMediaItem(current, index)
    end
    return items
end

function project.selection(current, mode)
    local entries = {}
    if mode == "items" then
        for _, item in ipairs(selected_items(current)) do
            local _, id = api.GetSetMediaItemInfo_String(item, "GUID", "", false)
            local _, value = api.GetSetMediaItemInfo_String(item, item_key, "", false)
            local take = api.GetActiveTake(item)
            entries[#entries + 1] = {
                handle = item, id = id, binding = unpack_binding(value or ""),
                name = take and api.GetTakeName(take) or "空素材",
                can_render = take ~= nil and not api.TakeIsMIDI(take)
                    and api.GetMediaItemInfo_Value(item, "D_LENGTH") > 0,
            }
        end
    else
        for index = 0, api.GetNumRegionsOrMarkers(current) - 1 do
            local region = api.GetRegionOrMarker(current, index, "")
            if region and api.GetRegionOrMarkerInfo_Value(current, region, "B_ISREGION") == 1
                and api.GetRegionOrMarkerInfo_Value(current, region, "B_UISEL") == 1 then
                local _, id = api.GetSetRegionOrMarkerInfo_String(current, region, "GUID", "", false)
                local _, name = api.GetSetRegionOrMarkerInfo_String(current, region, "P_NAME", "", false)
                local _, value = api.GetProjExtState(current, region_section, id)
                local first = api.GetRegionOrMarkerInfo_Value(current, region, "D_STARTPOS")
                local last = api.GetRegionOrMarkerInfo_Value(current, region, "D_ENDPOS")
                entries[#entries + 1] = {
                    handle = region, id = id, binding = unpack_binding(value or ""), name = name,
                    first = first, last = last, can_render = last > first,
                }
            end
        end
    end
    return entries
end

function project.bind(current, mode, entry, origin, source)
    local value = pack_binding(origin, source)
    if mode == "items" then
        assert(api.GetSetMediaItemInfo_String(entry.handle, item_key, value, true), "无法保存素材的 Wwise 绑定。")
    else
        assert(api.SetProjExtState(current, region_section, entry.id, value) > 0, "无法保存区间的 Wwise 绑定。")
    end
    api.MarkProjectDirty(current)
end

function project.import_sources(current, origin, sources, make_regions)
    local directory = project.directory(current, "Sources")
    local copied = {}
    local track, regions
    local previous_items = selected_items(current)

    local ok, result = pcall(function()
        for index, source in ipairs(sources) do
            local folder = files.join(directory, tostring(index))
            api.RecursiveCreateDirectory(folder, 0)
            local path = files.join(folder, files.name(source.wav))
            files.copy(source.wav, path)
            copied[#copied + 1] = {path = path, source = source}
            project.audio_info(path)
        end
    end)
    if not ok then error(result, 0) end

    api.Undo_BeginBlock2(current)
    api.PreventUIRefresh(1)
    regions = {}
    ok, result = pcall(function()
        local index = api.CountTracks(current)
        api.InsertTrackAtIndex(index, true)
        track = assert(api.GetTrack(current, index), "无法创建 REAPER 轨道。")
        api.GetSetMediaTrackInfo_String(track, "P_NAME", "Wwise · " .. origin.name, true)
        local cursor = api.GetCursorPositionEx(current)
        for _, entry in ipairs(copied) do
            local item = assert(api.AddMediaItemToTrack(track), "无法创建音频素材。")
            local take = assert(api.AddTakeToMediaItem(item), "无法为音频素材创建 Take。")
            local pcm, info = new_audio_source(entry.path)
            if not api.SetMediaItemTake_Source(take, pcm) then
                api.PCM_Source_Destroy(pcm)
                error("无法将音频分配给 Take\n" .. entry.path, 0)
            end
            api.SetMediaItemInfo_Value(item, "D_POSITION", cursor)
            api.SetMediaItemInfo_Value(item, "D_LENGTH", info.length)
            api.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
            api.GetSetMediaItemTakeInfo_String(take, "P_NAME", files.name(entry.path), true)
            project.bind(current, "items", {handle = item}, origin, entry.source)
            api.SetMediaItemSelected(item, true)

            if make_regions then
                local region = assert(api.AddRegionOrMarker(current, true, cursor, cursor + info.length,
                    entry.source.name, -1, 0), "无法创建 REAPER 区间。")
                local _, guid = api.GetSetRegionOrMarkerInfo_String(current, region, "GUID", "", false)
                regions[#regions + 1] = {id = guid, number = api.GetRegionOrMarkerInfo_Value(current, region, "I_NUMBER")}
                project.bind(current, "regions", {id = guid}, origin, entry.source)
            end
            cursor = cursor + info.length + 0.5
        end
        for _, item in ipairs(previous_items) do api.SetMediaItemSelected(item, false) end
    end)

    if not ok then
        for _, region in ipairs(regions) do
            api.DeleteProjectMarker(current, region.number, true)
            api.SetProjExtState(current, region_section, region.id, "")
        end
        if track then api.DeleteTrack(track) end
    end
    api.PreventUIRefresh(-1)
    api.Undo_EndBlock2(current, "PsyReaWwise · 导入 Wwise 音频", -1)
    api.UpdateArrange()
    if not ok then error(result, 0) end
    return directory
end

local render_numbers = {
    "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG",
    "RENDER_SRATE", "RENDER_CHANNELS", "RENDER_ADDTOPROJ", "RENDER_NORMALIZE", "RENDER_DITHER",
}
local render_strings = {"RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2"}

local function with_render_settings(current, number_keys, string_keys, operation)
    local values, strings = {}, {}
    for _, key in ipairs(number_keys) do values[key] = api.GetSetProjectInfo(current, key, 0, false) end
    for _, key in ipairs(string_keys) do
        local valid, value = api.GetSetProjectInfo_String(current, key, "", false)
        assert(valid, "无法读取 REAPER 渲染设置 " .. key)
        strings[key] = value
    end
    local function number(key, value) api.GetSetProjectInfo(current, key, value, true) end
    local function string_setting(key, value)
        assert(api.GetSetProjectInfo_String(current, key, value, true), "无法写入 REAPER 渲染设置 " .. key)
    end

    local ok, result = pcall(operation, number, string_setting)
    for _, key in ipairs(number_keys) do number(key, values[key]) end
    for _, key in ipairs(string_keys) do string_setting(key, strings[key]) end
    if not ok then error(result, 0) end
    return result
end

function project.render(current, mode, entries)
    local selection = mode == "items" and selected_items(current) or {}
    local item_in_render
    local ok, problem = pcall(with_render_settings, current, render_numbers, render_strings, function(number, string_setting)
        number("RENDER_SETTINGS", mode == "items" and 32 or 0)
        number("RENDER_BOUNDSFLAG", mode == "items" and 4 or 0)
        number("RENDER_TAILFLAG", 0)
        number("RENDER_ADDTOPROJ", 0)
        number("RENDER_NORMALIZE", 262144)  -- Disable render post-processing.
        number("RENDER_DITHER", 16)
        string_setting("RENDER_FORMAT", wave_24_bit)
        string_setting("RENDER_FORMAT2", "")
        string_setting("RENDER_PATTERN", "Render")
        for _, item in ipairs(selection) do api.SetMediaItemSelected(item, false) end

        for _, entry in ipairs(entries) do
            number("RENDER_SRATE", entry.info.rate)
            number("RENDER_CHANNELS", entry.info.channels)
            string_setting("RENDER_FILE", entry.stage)
            if mode == "items" then
                item_in_render = entry.selection.handle
                api.SetMediaItemSelected(item_in_render, true)
            else
                number("RENDER_STARTPOS", entry.selection.first)
                number("RENDER_ENDPOS", entry.selection.last)
            end
            api.Main_OnCommandEx(render_command, 0, current)
            local rendered = files.join(entry.stage, "Render.wav")
            local actual = project.audio_info(rendered)
            assert(actual.rate == entry.info.rate and actual.channels == entry.info.channels,
                "渲染格式与 Wwise 原文件不一致\n" .. entry.source.wav)
            files.copy(rendered, entry.replacement)
            if item_in_render then api.SetMediaItemSelected(item_in_render, false) end
            item_in_render = nil
        end
    end)

    if item_in_render then api.SetMediaItemSelected(item_in_render, false) end
    for _, item in ipairs(selection) do api.SetMediaItemSelected(item, true) end
    api.UpdateArrange()
    if not ok then error(problem, 0) end
end

local function render_targets(current, directory)
    local _, raw = api.GetSetProjectInfo_String(current, "RENDER_TARGETS", "", false)
    local paths, first, quoted = {}, 1, false
    local prefix = files.key(directory) .. "/"
    local function append(last)
        local path = raw:sub(first, last):gsub('^%s*"?', ""):gsub('"?%s*$', "")
        if path == "" then return end
        assert(files.key(path):sub(1, #prefix) == prefix and not path:gsub("\\", "/"):find("/../", 1, true),
            "REAPER 的渲染文件路径超出暂存目录\n" .. path)
        assert(path:lower():match("%.wav$"), "传输到 Wwise 需要 WAV 渲染文件\n" .. path)
        paths[#paths + 1] = path
    end
    raw = raw or ""
    for index = 1, #raw do
        local char = raw:sub(index, index)
        if char == '"' then quoted = not quoted end
        if char == ";" and not quoted then
            append(index - 1)
            first = index + 1
        end
    end
    append(#raw)
    assert(#paths > 0, "REAPER 没有可渲染的文件。请检查 Render 的渲染范围和输出命名。")
    return paths
end

function project.transfer_render(current, directory, expected)
    return with_render_settings(current, {"RENDER_ADDTOPROJ"}, {"RENDER_FILE", "RENDER_FORMAT", "RENDER_FORMAT2"},
        function(number, string_setting)
            number("RENDER_ADDTOPROJ", 0)
            string_setting("RENDER_FILE", directory)
            string_setting("RENDER_FORMAT", wave_24_bit)
            string_setting("RENDER_FORMAT2", "")
            local paths = render_targets(current, directory)
            if not expected then return paths end

            assert(#paths == #expected, "REAPER 渲染目标发生变化，请重新预览。")
            for index, path in ipairs(paths) do
                assert(files.key(path) == files.key(expected[index]), "REAPER 渲染文件名发生变化，请重新预览。")
                assert(not api.file_exists(path), "暂存目录中已有同名文件，请重新预览\n" .. path)
            end
            api.RecursiveCreateDirectory(directory, 0)
            api.Main_OnCommandEx(render_command, 0, current)
            for _, path in ipairs(paths) do project.audio_info(path) end
            return paths
        end)
end

return project
