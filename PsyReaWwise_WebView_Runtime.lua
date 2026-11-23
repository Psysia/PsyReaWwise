-- @description PsyReaWwise WebView Lua backend · Lua 后端
-- @version 0.2.0-beta1

local api = reaper
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]+") or "."
local title, section = "PsyReaWwise WebView", "PsyReaWwise.WebView"
local locale = loadfile(root .. "/lib/i18n.lua")
if not locale then
    api.ShowMessageBox("PsyReaWwise files are missing. Reinstall the package.\nPsyReaWwise 文件缺失，请重新安装。", title, 0)
    return
end
local i18n = locale()
local language = i18n.app_language(api)
local t = i18n.translator(language)
local function module(name, ...)
    local chunk, reason = loadfile(root .. "/lib/" .. name .. ".lua")
    assert(chunk, t("无法加载 PsyReaWwise 模块 %s。请重新安装。\n"):format(name) .. tostring(reason or ""))
    return chunk(...)
end

local web_runtime = module("runtime")
if not web_runtime.available() then
    api.ShowMessageBox(i18n.translator(i18n.windows_language(api))(
        "请运行 PsyReaWwise WebView 动作以准备随包运行时。"), title, 0)
    return
end
if not api.APIExists("GetRegionOrMarker") then
    api.ShowMessageBox(t("请使用支持区间选择接口的 REAPER 7。此版本以 REAPER 7.86 为目标。"), title, 0)
    return
end

local files = module("files", t)
local wwise = module("wwise", t)
local project = module("project", files, t)
local samples = module("samples", files, t)
local workflow = module("workflow", files, project, wwise, samples, t)
local json = module("json")
local backend = module("webview").new(t, files, project, wwise, samples, workflow, language)

local key = (root .. "/PsyReaWwise_WebView_Runtime.lua"):gsub("\\", "/"):lower()
local previous = tonumber(api.GetExtState(section, key))
if previous and api.ReaWeb_IsOpen(previous) then return end
local window = api.ReaWeb_Open(root .. "/web/index.html", key)
if not window or window == 0 then
    local detail = type(api.ReaWeb_GetLastError) == "function" and api.ReaWeb_GetLastError() or ""
    api.ShowMessageBox(t("无法创建 PsyReaWwise WebView 窗口。\n") .. tostring(detail), title, 0)
    return
end

local owner = tostring(window)
api.SetExtState(section, key, owner, false)
api.atexit(function()
    if api.GetExtState(section, key) == owner then
        api.DeleteExtState(section, key, false)
        if api.ReaWeb_IsOpen(window) then api.ReaWeb_Close(window) end
    end
end)
if type(api.ReaWeb_SetShortcutRouting) == "function" then api.ReaWeb_SetShortcutRouting(window, false) end

local function handle(raw)
    if #raw > 900000 then return end
    local decoded, request = pcall(json.decode, raw, true)
    if not decoded or type(request) ~= "table" or request.protocol ~= 1 or type(request.id) ~= "string"
        or #request.id == 0 or #request.id > 80 then return end

    local parameters = request.params
    local params_meta = type(parameters) == "table" and getmetatable(parameters)
    local response = {protocol = 1, id = request.id}
    if type(request.method) ~= "string" or not params_meta or params_meta.__json_kind ~= "object" then
        response.ok, response.error = false, t("工作台收到无效的操作。")
    else
        local ok, result = pcall(backend.receive, request.method, parameters)
        response.ok = ok
        if ok then response.result = result else response.error = tostring(result) end
    end
    local encoded = json.encode(response)
    if #encoded > 900000 then
        return json.encode({protocol = 1, id = request.id, ok = false,
            error = t("所选内容过多。请在 Wwise 中缩小选择范围后重试。")})
    end
    return encoded
end

local pending, polling_at, connected = nil, 0, false
local function loop()
    if not api.ReaWeb_IsOpen(window) then return end
    if api.ReaWeb_IsReady(window) then
        if pending and api.ReaWeb_Send(window, pending) then pending = nil end
        if not pending then
            local raw = api.ReaWeb_Receive(window)
            if type(raw) == "string" and raw ~= "" then
                connected = true
                pending = handle(raw)
            elseif connected and api.time_precise() >= polling_at then
                polling_at = api.time_precise() + 0.25
                if backend.refresh() then
                    pending = json.encode({protocol = 1, event = "project", data = backend.project()})
                end
            end
        end
    end
    api.defer(loop)
end

loop()
