local files, t = ...
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
    assert(media_path and media_path ~= "", t("找不到 REAPER 工程的媒体目录。"))
    local token = api.genGuid():gsub("[^%x]", "")
    return files.join(media_path, ("PsyReaWwise/%s/%s-%s"):format(purpose, os.date("%Y%m%d-%H%M%S"), token))
end

local function new_audio_source(path)
    local source = api.PCM_Source_CreateFromFileEx(path, true)
    assert(source, t("REAPER 无法打开音频\n") .. path)
    local length, is_qn = api.GetMediaSourceLength(source)
    local rate = api.GetMediaSourceSampleRate(source)
    local channels = api.GetMediaSourceNumChannels(source)
    if not length or length <= 0 or is_qn or not rate or rate <= 0 or not channels or channels <= 0 then
        api.PCM_Source_Destroy(source)
        error(t("不是可用的音频文件\n") .. path, 0)
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
                name = take and api.GetTakeName(take) or t("空素材"),
                can_render = take ~= nil and not api.TakeIsMIDI(take)
                    and api.GetMediaItemInfo_Value(item, "D_LENGTH") > 0,
            }
        end
    else
        local settings = api.GetSetProjectInfo(current, "RENDER_SETTINGS", 0, false)
        local use_matrix = math.floor(settings / 8) % 2 == 1
        for index = 0, api.GetNumRegionsOrMarkers(current) - 1 do
            local region = api.GetRegionOrMarker(current, index, "")
            if region and api.GetRegionOrMarkerInfo_Value(current, region, "B_ISREGION") == 1
                and api.GetRegionOrMarkerInfo_Value(current, region, "B_UISEL") == 1 then
                local _, id = api.GetSetRegionOrMarkerInfo_String(current, region, "GUID", "", false)
                local _, name = api.GetSetRegionOrMarkerInfo_String(current, region, "P_NAME", "", false)
                local _, value = api.GetProjExtState(current, region_section, id)
                local first = api.GetRegionOrMarkerInfo_Value(current, region, "D_STARTPOS")
                local last = api.GetRegionOrMarkerInfo_Value(current, region, "D_ENDPOS")
                local number = api.GetRegionOrMarkerInfo_Value(current, region, "I_NUMBER")
                local entry = {
                    handle = region, id = id, binding = unpack_binding(value or ""), name = name,
                    number = number, first = first, last = last, can_render = last > first,
                }
                local track = api.EnumRegionRenderMatrix(current, number, 0)
                if track then
                    use_matrix = true
                    entry.render_track = api.GetTrackGUID(track)
                    local _, track_name = api.GetTrackName(track, "")
                    entry.render_label = track == api.GetMasterTrack(current) and t("主混音") or track_name
                    if api.EnumRegionRenderMatrix(current, number, 1) then
                        entry.render_error = t("矩阵中有多个输出，请为此区间选一个。")
                    end
                end
                entries[#entries + 1] = entry
            end
        end
        for _, entry in ipairs(entries) do
            if not entry.render_track then
                if use_matrix then entry.render_error = t("请在渲染矩阵中为此区间选一个输出。")
                else entry.render_label = t("主混音") end
            end
        end
    end
    return entries
end

function project.bind(current, mode, entry, origin, source)
    local value = pack_binding(origin, source)
    if mode == "items" then
        assert(api.GetSetMediaItemInfo_String(entry.handle, item_key, value, true), t("无法保存素材的 Wwise 绑定。"))
    else
        assert(api.SetProjExtState(current, region_section, entry.id, value) > 0, t("无法保存区间的 Wwise 绑定。"))
    end
    api.MarkProjectDirty(current)
end

function project.rename_regions(current, entries, count)
    local changes, target_counts = {}, {}
    for _, entry in ipairs(entries) do
        local id = entry.selection.id
        target_counts[id] = (target_counts[id] or 0) + 1
    end

    for index = 1, count do
        local entry = entries[index]
        local previous, name = entry.selection, files.name(entry.source.wav):sub(1, -5)
        if target_counts[previous.id] == 1 and previous.name ~= name then
            local region = api.GetRegionOrMarker(current, -1, previous.id)
            assert(region and api.GetRegionOrMarkerInfo_Value(current, region, "B_ISREGION") == 1,
                t("找不到需要改名的 REAPER 区间\n") .. previous.name)
            local _, actual = api.GetSetRegionOrMarkerInfo_String(current, region, "P_NAME", "", false)
            assert(actual == previous.name, t("REAPER 区间名称已变化\n") .. previous.name)
            changes[#changes + 1] = {region = region, name = name}
        end
    end
    if #changes == 0 then return end

    api.Undo_BeginBlock2(current)
    local ok, problem = pcall(function()
        for _, change in ipairs(changes) do
            assert(api.GetSetRegionOrMarkerInfo_String(current, change.region, "P_NAME", change.name, true),
                t("无法更新 REAPER 区间名\n") .. change.name)
        end
    end)
    api.Undo_EndBlock2(current, t("PsyReaWwise · 同步 Wwise 文件名到 REAPER 区间"), -1)
    api.UpdateArrange()
    if not ok then error(problem, 0) end
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
        track = assert(api.GetTrack(current, index), t("无法创建 REAPER 轨道。"))
        api.GetSetMediaTrackInfo_String(track, "P_NAME", "Wwise · " .. origin.name, true)
        local cursor = api.GetCursorPositionEx(current)
        for _, entry in ipairs(copied) do
            local item = assert(api.AddMediaItemToTrack(track), t("无法创建音频素材。"))
            local take = assert(api.AddTakeToMediaItem(item), t("无法为音频素材创建 Take。"))
            local pcm, info = new_audio_source(entry.path)
            if not api.SetMediaItemTake_Source(take, pcm) then
                api.PCM_Source_Destroy(pcm)
                error(t("无法将音频分配给 Take\n") .. entry.path, 0)
            end
            api.SetMediaItemInfo_Value(item, "D_POSITION", cursor)
            api.SetMediaItemInfo_Value(item, "D_LENGTH", info.length)
            api.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
            api.GetSetMediaItemTakeInfo_String(take, "P_NAME", files.name(entry.path), true)
            project.bind(current, "items", {handle = item}, origin, entry.source)
            api.SetMediaItemSelected(item, true)

            if make_regions then
                local region = assert(api.AddRegionOrMarker(current, true, cursor, cursor + info.length,
                    entry.source.name, -1, 0), t("无法创建 REAPER 区间。"))
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
    api.Undo_EndBlock2(current, t("PsyReaWwise · 导入 Wwise 音频"), -1)
    api.UpdateArrange()
    if not ok then error(result, 0) end
    return directory
end

local render_numbers = {
    "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG",
    "RENDER_SRATE", "RENDER_CHANNELS", "RENDER_ADDTOPROJ", "RENDER_NORMALIZE", "RENDER_DITHER",
}
local render_strings = {"RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2"}

local function write_metadata(current, tags)
    local _, keys = api.GetSetProjectInfo_String(current, "RENDER_METADATA", "", false)
    for key in (keys or ""):gmatch("[^;]+") do
        api.GetSetProjectInfo_String(current, "RENDER_METADATA", key .. "|", true)
    end
    for _, tag in ipairs(tags) do
        api.GetSetProjectInfo_String(current, "RENDER_METADATA", tag.key .. "|" .. tag.value, true)
    end
end

local function with_render_settings(current, number_keys, string_keys, operation, preset)
    local values, strings = {}, {}
    for _, key in ipairs(number_keys) do values[key] = api.GetSetProjectInfo(current, key, 0, false) end
    for _, key in ipairs(string_keys) do
        local valid, value = api.GetSetProjectInfo_String(current, key, "", false)
        assert(valid, t("无法读取 REAPER 渲染设置 ") .. key)
        strings[key] = value
    end
    local function number(key, value) api.GetSetProjectInfo(current, key, value, true) end
    local function string_setting(key, value)
        assert(api.GetSetProjectInfo_String(current, key, value, true), t("无法写入 REAPER 渲染设置 ") .. key)
    end

    local config, metadata = {}, nil
    if preset then
        for key in pairs(preset.numbers) do
            if values[key] == nil then values[key] = api.GetSetProjectInfo(current, key, 0, false) end
        end
        if api.SNM_GetIntConfigVar and api.SNM_SetIntConfigVar then
            local missing = -2147483648
            for key in pairs(preset.config) do
                local value = api.SNM_GetIntConfigVar(key, missing)
                if value ~= missing then config[key] = value end
            end
        end
        if preset.metadata then
            metadata = {}
            local _, keys = api.GetSetProjectInfo_String(current, "RENDER_METADATA", "", false)
            for key in (keys or ""):gmatch("[^;]+") do
                local _, value = api.GetSetProjectInfo_String(current, "RENDER_METADATA", key, false)
                metadata[#metadata + 1] = {key = key, value = value or ""}
            end
        end
    end
    local ok, result = pcall(function()
        if preset then
            for key, value in pairs(preset.numbers) do number(key, value) end
            for key in pairs(config) do api.SNM_SetIntConfigVar(key, preset.config[key]) end
            if metadata then write_metadata(current, preset.metadata) end
        end
        return operation(number, string_setting, values.RENDER_SETTINGS)
    end)
    if metadata then write_metadata(current, metadata) end
    for key, value in pairs(config) do api.SNM_SetIntConfigVar(key, value) end
    for key, value in pairs(values) do number(key, value) end
    for _, key in ipairs(string_keys) do string_setting(key, strings[key]) end
    if not ok then error(result, 0) end
    return result
end

-- Render-source bits and the option to combine selected items or razor edits.
local source_bits = {1, 2, 8, 32, 64, 128, 4096, 262144}
local function source_flags(settings)
    local selected = 0
    for _, bit in ipairs(source_bits) do
        if math.floor(settings / bit) % 2 == 1 then selected = selected + bit end
    end
    return selected
end

local function set_formats(string_setting, preset)
    string_setting("RENDER_FORMAT2", preset and preset.formats[2] or "")
    string_setting("RENDER_FORMAT", preset and preset.formats[1] or wave_24_bit)
end

local function set_region_selected(current, entry, selected)
    local region = assert(api.GetRegionOrMarker(current, -1, entry.id), t("REAPER 选择发生变化，请重新预览。"))
    api.SetRegionOrMarkerInfo_Value(current, region, "B_UISEL", selected)
    assert(api.GetRegionOrMarkerInfo_Value(current, region, "B_UISEL") == selected,
        t("无法设置 REAPER 的渲染区间选择\n") .. entry.name)
end

local render_targets

local function render_region_batch(current, entries, stage, number, string_setting)
    api.RecursiveCreateDirectory(stage, 0)
    number("RENDER_BOUNDSFLAG", 5)
    string_setting("RENDER_FILE", stage)
    string_setting("RENDER_PATTERN", "PRW-R$regionnumber")
    local by_id = {}
    for _, entry in ipairs(entries) do
        assert(not by_id[entry.selection.number], t("REAPER 区间编号重复，请重新预览。"))
        by_id[entry.selection.number] = entry
        set_region_selected(current, entry.selection, 1)
    end

    local paths = render_targets(current, stage, true)
    local by_entry = {}
    assert(#paths == #entries, t("REAPER 的 WAV 输出数量与配对区间不一致。"))
    for _, path in ipairs(paths) do
        local id = tonumber(files.name(path):match("^PRW%-R(%d+)"))
        local entry = by_id[id]
        assert(entry and not by_entry[entry], t("无法确认渲染文件所属的 REAPER 区间\n") .. path)
        by_entry[entry] = path
    end
    api.Main_OnCommandEx(render_command, 0, current)
    for _, entry in ipairs(entries) do
        local path = by_entry[entry]
        project.audio_info(path)
        files.copy(path, entry.replacement)
    end
end

function project.render(current, mode, entries, preset)
    local selection = mode == "items" and selected_items(current) or {}
    local use_matrix = mode == "regions" and entries[1].selection.render_track ~= nil
    local selected_bounds = mode == "regions" and (use_matrix or preset ~= nil)
    local regions = selected_bounds and project.selection(current, "regions") or {}
    local item_in_render
    local ok, problem = pcall(with_render_settings, current, render_numbers, render_strings, function(number, string_setting)
        local source = mode == "items" and 32 or use_matrix and 8 or 0
        local options = preset and preset.options - source_flags(preset.options) or 0
        number("RENDER_SETTINGS", source + options)
        number("RENDER_BOUNDSFLAG", mode == "items" and 4 or selected_bounds and 5 or 0)
        number("RENDER_ADDTOPROJ", 0)
        if not preset then
            number("RENDER_TAILFLAG", 0)
            number("RENDER_NORMALIZE", 262144)
            number("RENDER_DITHER", 16)
        end
        set_formats(string_setting, preset)
        for _, item in ipairs(selection) do api.SetMediaItemSelected(item, false) end
        for _, region in ipairs(regions) do set_region_selected(current, region, 0) end

        if preset and mode == "regions" then
            render_region_batch(current, entries, files.join(files.directory(entries[1].stage), "Preset"), number, string_setting)
            return
        end

        string_setting("RENDER_PATTERN", "Render")
        for _, entry in ipairs(entries) do
            if not preset then
                number("RENDER_SRATE", entry.info.rate)
                number("RENDER_CHANNELS", entry.info.channels)
            end
            string_setting("RENDER_FILE", entry.stage)
            if mode == "items" then
                item_in_render = entry.selection.handle
                api.SetMediaItemSelected(item_in_render, true)
            elseif use_matrix then
                set_region_selected(current, entry.selection, 1)
            else
                number("RENDER_STARTPOS", entry.selection.first)
                number("RENDER_ENDPOS", entry.selection.last)
            end
            local rendered = files.join(entry.stage, "Render.wav")
            if use_matrix or preset then
                local paths = render_targets(current, entry.stage, preset ~= nil)
                assert(#paths == 1, t("REAPER 的 WAV 输出数量与配对区间不一致。") .. "\n" .. entry.selection.name)
                rendered = paths[1]
            end
            api.Main_OnCommandEx(render_command, 0, current)
            local actual = project.audio_info(rendered)
            assert(preset or (actual.rate == entry.info.rate and actual.channels == entry.info.channels),
                t("渲染格式与 Wwise 原文件不一致\n") .. entry.source.wav)
            files.copy(rendered, entry.replacement)
            if item_in_render then api.SetMediaItemSelected(item_in_render, false) end
            if use_matrix then set_region_selected(current, entry.selection, 0) end
            item_in_render = nil
        end
    end, preset)

    if item_in_render then api.SetMediaItemSelected(item_in_render, false) end
    for _, item in ipairs(selection) do api.SetMediaItemSelected(item, true) end
    for _, region in ipairs(regions) do set_region_selected(current, region, 1) end
    api.UpdateArrange()
    if not ok then error(problem, 0) end
end

render_targets = function(current, directory, allow_extra)
    local _, raw = api.GetSetProjectInfo_String(current, "RENDER_TARGETS", "", false)
    local paths, first, quoted = {}, 1, false
    local prefix = files.key(directory) .. "/"
    local function append(last)
        local path = raw:sub(first, last):gsub('^%s*"?', ""):gsub('"?%s*$', "")
        if path == "" then return end
        assert(files.key(path):sub(1, #prefix) == prefix and not path:gsub("\\", "/"):find("/../", 1, true),
            t("REAPER 的渲染文件路径超出暂存目录\n") .. path)
        if path:lower():match("%.wav$") then
            paths[#paths + 1] = path
        elseif not allow_extra then
            error(t("传输到 Wwise 需要 WAV 渲染文件\n") .. path, 0)
        end
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
    assert(#paths > 0, t("REAPER 没有可渲染的文件。请检查 Render 的渲染范围和输出命名。"))
    return paths
end

function project.transfer_render(current, directory, expected, preset)
    return with_render_settings(current, {"RENDER_ADDTOPROJ", "RENDER_SETTINGS"}, {"RENDER_FILE", "RENDER_FORMAT", "RENDER_FORMAT2"},
        function(number, string_setting, settings)
            if preset then
                number("RENDER_SETTINGS", source_flags(settings) + preset.options - source_flags(preset.options))
            end
            number("RENDER_ADDTOPROJ", 0)
            string_setting("RENDER_FILE", directory)
            set_formats(string_setting, preset)
            local paths = render_targets(current, directory, preset ~= nil)
            if not expected then return paths end

            assert(#paths == #expected, t("REAPER 渲染目标发生变化，请重新预览。"))
            for index, path in ipairs(paths) do
                assert(files.key(path) == files.key(expected[index]), t("REAPER 渲染文件名发生变化，请重新预览。"))
                assert(not api.file_exists(path), t("暂存目录中已有同名文件，请重新预览\n") .. path)
            end
            api.RecursiveCreateDirectory(directory, 0)
            api.Main_OnCommandEx(render_command, 0, current)
            for _, path in ipairs(paths) do project.audio_info(path) end
            return paths
        end, preset)
end

return project
