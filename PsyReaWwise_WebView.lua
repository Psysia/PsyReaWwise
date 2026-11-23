-- @description PsyReaWwise WebView · Wwise 音频往返工作台
-- @author Psysia
-- @version 0.2.0-beta1
-- @link https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.2.0-beta1

local api = reaper
local title = "PsyReaWwise WebView"
local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]+") or "."
local locale = loadfile(directory .. "/lib/i18n.lua")
local runtime_module = loadfile(directory .. "/lib/runtime.lua")
if not locale or not runtime_module then
    api.ShowMessageBox("PsyReaWwise files are missing. Reinstall the package.\nPsyReaWwise 文件缺失，请重新安装。", title, 0)
    return
end
local i18n = locale()
local web_runtime = runtime_module()
local function show(message)
    api.ShowMessageBox(i18n.translator(i18n.windows_language(api))(message), title, 0)
end
if not web_runtime.available() then
    local t = i18n.translator(i18n.windows_language(api))
    api.ShowMessageBox(web_runtime.prepare(directory, t), title, 0)
    return
end

local runtime = directory .. "/PsyReaWwise_WebView_Runtime.lua"
local key = runtime:gsub("\\", "/"):lower()
local id = tonumber(api.GetExtState("PsyReaWwise.WebView", key))
if id and api.ReaWeb_IsOpen(id) then
    if type(api.ReaWeb_Show) == "function" then api.ReaWeb_Show(id) end
    if type(api.ReaWeb_Focus) == "function" then api.ReaWeb_Focus(id) end
    return
end

local command = api.AddRemoveReaScript(true, 0, runtime, true)
if not command or command == 0 then
    show("无法加载 PsyReaWwise WebView 后台脚本，请重新安装完整版本。")
    return
end
api.Main_OnCommand(command, 0)
