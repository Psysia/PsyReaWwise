local api, title = ...

if not api.GetOS():match("^Win") then return end
for _, name in ipairs({"JS_Window_Find", "JS_Window_GetClassName", "JS_Window_GetRelated",
    "JS_Window_GetLong", "JS_Window_SetLong", "JS_Window_Show", "JS_Window_IsVisible"}) do
    if type(api[name]) ~= "function" then return end
end

local child, minimized = 0x40000000, 0x20000000
local app_window, tool_window = 0x40000, 0x80
local next_check, taskbar_window = 0, nil

local function has_flag(style, flag)
    return math.floor(style / flag) % 2 == 1
end

-- Same taskbar policy as PsyReaSFX. The floating window keeps its REAPER owner.
return function(now)
    if now < next_check then return end
    next_check = now + 1

    local hwnd = api.JS_Window_Find(title, true)
    if not hwnd or api.JS_Window_GetClassName(hwnd) ~= "ReaWebAPI.Window" then return end

    local style = api.JS_Window_GetLong(hwnd, "STYLE")
    local extended = api.JS_Window_GetLong(hwnd, "EXSTYLE")
    if has_flag(style, child) then
        if hwnd == taskbar_window and has_flag(extended, app_window) then
            api.JS_Window_SetLong(hwnd, "EXSTYLE", extended - app_window)
        end
        return
    end
    if api.JS_Window_GetRelated(hwnd, "OWNER") ~= api.GetMainHwnd() then return end

    local desired = has_flag(extended, app_window) and extended or extended + app_window
    if has_flag(desired, tool_window) then desired = desired - tool_window end
    if desired ~= extended then
        local visible = api.JS_Window_IsVisible(hwnd)
        if visible then api.JS_Window_Show(hwnd, "HIDE") end
        local ok, problem = pcall(api.JS_Window_SetLong, hwnd, "EXSTYLE", desired)
        if visible then
            api.JS_Window_Show(hwnd, has_flag(style, minimized) and "SHOWMINIMIZED" or "SHOWNA")
        end
        if not ok then error(problem, 0) end
    end
    taskbar_window = hwnd
end
