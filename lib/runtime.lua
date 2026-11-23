local api = reaper
local runtime = {}
local filename = "reaper_reawebapi-x64.dll"
local missing = "随包 WebView 组件文件缺失。请在 ReaPack 重新安装 PsyReaWwise WebView，或重新解压完整安装包。"

function runtime.available()
    for _, name in ipairs({"ReaWeb_Open", "ReaWeb_IsOpen", "ReaWeb_IsReady", "ReaWeb_Send", "ReaWeb_Receive", "ReaWeb_Close"}) do
        if type(api[name]) ~= "function" then return false end
    end
    return true
end

function runtime.prepare(root, t)
    if api.GetOS() ~= "Win64" then return t("此版本需要 Windows x64。") end
    local plugins = api.GetResourcePath():gsub("[\\/]+$", "") .. "/UserPlugins"
    local target = plugins .. "/" .. filename
    if api.file_exists(target) then
        return t("已检测到 ReaWebAPI。请完全退出并重新打开 REAPER。如果仍出现此提示，请更新到兼容的 ReaWebAPI。")
    end

    local bundle = root .. "/runtime/reawebapi/"
    local module = loadfile(root .. "/lib/files.lua")
    if not module or not api.file_exists(bundle .. filename) or not api.file_exists(bundle .. "runtime-lock.json") then
        return t(missing)
    end

    api.RecursiveCreateDirectory(plugins, 0)
    local ok, detail = module(t).install_runtime(bundle .. filename, target)
    if ok or api.file_exists(target) then
        return t("随包 WebView 运行时已准备好。请完全退出并重新打开 REAPER，再运行 PsyReaWwise WebView。")
    end
    if tostring(detail):match("^2[%s]") then
        return t("随包 WebView 运行时校验失败。请重新安装 PsyReaWwise WebView。")
    end
    return t("无法准备随包 WebView 运行时。请检查 REAPER 资源目录的写入权限，或在 ReaPack 重新安装本包。\n")
        .. tostring(detail or "")
end

return runtime
