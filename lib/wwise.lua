local t = ...
local wwise = {}
local api = reaper

local source_fields = {
    "id", "name", "type", "path", "parent", "originalFilePath", "originalRelativeFilePath", "audioSourceLanguage",
}

function wwise.available()
    return api.APIExists("AK_Waapi_Connect") and api.APIExists("AK_AkJson_Clear")
end

local function call(uri, arguments, options, read_result)
    local handles, tracked = {}, {}
    local function keep(handle)
        if handle and not tracked[handle] then
            handles[#handles + 1] = handle
            tracked[handle] = true
        end
        return handle
    end

    local function encode(value)
        if type(value) == "string" then return keep(api.AK_AkVariant_String(value)) end
        if type(value) == "boolean" then return keep(api.AK_AkVariant_Bool(value)) end
        if #value > 0 then
            local array = keep(api.AK_AkJson_Array())
            for _, entry in ipairs(value) do
                assert(api.AK_AkJson_Array_Add(array, encode(entry)), t("无法生成 WAAPI 参数。请重新打开工作台。"))
            end
            return array
        end
        local map = keep(api.AK_AkJson_Map())
        for key, entry in pairs(value) do
            assert(api.AK_AkJson_Map_Set(map, key, encode(entry)), t("无法生成 WAAPI 参数。请重新打开工作台。"))
        end
        return map
    end

    local function member(map, key)
        if map then return keep(api.AK_AkJson_Map_Get(map, key)) end
    end

    local function string_value(handle)
        if handle then return api.AK_AkVariant_GetString(handle) or "" end
        return ""
    end

    local function field(map, key)
        return string_value(member(map, key))
    end

    local function rows(map, key, read_row)
        local result = {}
        local array = member(map, key)
        if array then
            for index = 0, api.AK_AkJson_Array_Size(array) - 1 do
                result[#result + 1] = read_row(keep(api.AK_AkJson_Array_Get(array, index)))
            end
        end
        return result
    end

    local ok, result = pcall(function()
        local response = api.AK_Waapi_Call(uri, encode(arguments), encode(options))
        assert(keep(response), t("WAAPI 未返回结果。"))
        if not api.AK_AkJson_GetStatus(response) then
            local message = field(response, "message")
            error(t("WAAPI 请求失败。请核对当前 Wwise 工程和操作目标。\n") .. uri .. "\n" .. message, 0)
        end
        return read_result(response, field, rows, member, string_value)
    end)

    -- Nested handles point into their parent maps and arrays.
    for index = #handles, 1, -1 do api.AK_AkJson_Clear(handles[index]) end
    if not ok then error(result, 0) end
    return result
end

function wwise.session(port, operation)
    assert(wwise.available(), t("需要安装 ReaWwise 1.0.4 或以上版本。"))
    local already_connected = api.APIExists("AK_Waapi_IsConnected") and api.AK_Waapi_IsConnected()
    if not api.AK_Waapi_Connect("127.0.0.1", port) then
        error((t("无法连接 WAAPI 127.0.0.1:%d。请打开 Wwise 工程并启用 WAAPI。")):format(port), 0)
    end
    local ok, result = pcall(operation)
    if not already_connected then api.AK_Waapi_Disconnect() end
    if not ok then error(result, 0) end
    return result
end

function wwise.project()
    return call("ak.wwise.core.getProjectInfo", {}, {}, function(result, field, _, member)
        local project = {
            id = field(result, "id"),
            name = field(result, "name"),
            path = field(result, "path"),
            originals = field(member(result, "directories"), "originals"),
        }
        assert(project.id ~= "" and project.path ~= "" and project.originals ~= "", t("请在 Wwise 中打开一个工程。"))
        return project
    end)
end

local function read_sources(result, field, rows, member)
    return rows(result, "return", function(row)
        return {
            id = field(row, "id"),
            name = field(row, "name"),
            type = field(row, "type"),
            path = field(row, "path"),
            parent = field(member(row, "parent"), "id"),
            wav = field(row, "originalFilePath"),
            relative = field(row, "originalRelativeFilePath"),
            language = field(member(row, "audioSourceLanguage"), "name"),
        }
    end)
end

local function query(ids, suffix)
    if #ids == 0 then return {} end
    local quoted = {}
    for index, id in ipairs(ids) do
        assert(id:match("^%{[%x%-]+%}$"), t("无效的 Wwise 对象 GUID。"))
        quoted[index] = '"' .. id .. '"'
    end
    local waql = "$ from object " .. table.concat(quoted, ", ") .. suffix
    return call("ak.wwise.core.object.get", {waql = waql}, {['return'] = source_fields}, read_sources)
end

function wwise.objects(ids)
    local objects = {}
    for _, source in ipairs(query(ids, "")) do
        objects[source.id:lower()] = source
    end
    return objects
end

function wwise.sources(ids)
    local objects = wwise.objects(ids)
    for key, object in pairs(objects) do
        if object.type ~= "AudioFileSource" then objects[key] = nil end
    end
    return objects
end

function wwise.children(id)
    return query({id}, " select children")
end

function wwise.selected_objects()
    return call("ak.wwise.ui.getSelectedObjects", {}, {['return'] = {"id", "type"}},
        function(result, field, rows)
            return rows(result, "objects", function(row)
                return {id = field(row, "id"), type = field(row, "type")}
            end)
        end)
end

function wwise.selected_files()
    -- Older versions of Wwise and WwiseConsole may not expose this UI procedure.
    local ok, paths = pcall(call, "ak.wwise.ui.getSelectedFiles", {}, {}, function(result, _, rows, _, string_value)
        return rows(result, "files", string_value)
    end)
    return ok and paths or {}
end

function wwise.selected_sources(selected)
    selected = selected or wwise.selected_objects()
    local selected_sources, selected_parents = {}, {}
    for _, entry in ipairs(selected) do
        local ids = entry.type == "AudioFileSource" and selected_sources or selected_parents
        ids[#ids + 1] = entry.id
    end

    local unique = wwise.sources(selected_sources)
    for _, source in ipairs(query(selected_parents, ' select descendants where type = "AudioFileSource"')) do
        unique[source.id:lower()] = source
    end
    local sources = {}
    for _, source in pairs(unique) do sources[#sources + 1] = source end
    table.sort(sources, function(a, b) return a.path < b.path end)
    return sources
end

function wwise.file_usage(relative, cache)
    local folder = relative:match("^(.*)[\\/][^\\/]+$")
    local key = folder and folder:gsub("/", "\\"):lower() or ""
    local by_file = cache and cache[key]
    if not by_file then
        by_file = call("ak.wwise.core.sourceControl.getSourceFiles", {folder = folder, recursive = false, filter = "used"},
            {['return'] = {"file", "usage"}, objectReturn = {"id", "path"}}, function(result, field, rows)
                local indexed = {}
                for _, row in ipairs(rows(result, "return", function(item)
                    return {
                        file = field(item, "file"),
                        usage = rows(item, "usage", function(use) return {id = field(use, "id"), path = field(use, "path")} end),
                    }
                end)) do
                    indexed[row.file:gsub("/", "\\"):lower()] = row.usage
                end
                return indexed
            end)
        if cache then cache[key] = by_file end
    end
    return by_file[relative:gsub("/", "\\"):lower()] or {}
end

local function import_audio(target_id, object_path, language, subfolder, wav_path)
    local args = {
        importOperation = "useExisting",
        autoAddToSourceControl = false,
        autoCheckOutToSourceControl = true,
        imports = {{
            audioFile = wav_path,
            importLocation = target_id,
            objectPath = object_path,
            importLanguage = language,
            originalsSubFolder = subfolder,
        }},
    }
    return call("ak.wwise.core.audio.import", args, {['return'] = {"id", "type", "parent", "originalFilePath"}},
        function(result, field, rows, member)
            local log = rows(result, "log", function(row)
                return {severity = field(row, "severity"), message = field(row, "message")}
            end)
            for _, entry in ipairs(log) do
                if entry.severity:lower():find("error", 1, true) then
                    error(t("Wwise 导入失败\n") .. entry.message, 0)
                end
            end
            return rows(result, "objects", function(row)
                return {id = field(row, "id"), type = field(row, "type"), wav = field(row, "originalFilePath"),
                    parent = field(member(row, "parent"), "id")}
            end)
        end)
end

function wwise.update_source(source, wav_path)
    return import_audio(source.parent, "<AudioFileSource>" .. source.name, source.language, source.subfolder, wav_path)
end

function wwise.create_sound(target_id, name, language, subfolder, wav_path)
    local object_type = language:lower() == "sfx" and "<Sound SFX>" or "<Sound Voice>"
    return import_audio(target_id, object_type .. name, language, subfolder, wav_path)
end

return wwise
