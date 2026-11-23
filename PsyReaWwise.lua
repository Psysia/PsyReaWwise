-- @description PsyReaWwise - REAPER/Wwise audio workbench · Wwise 音频往返工作台
-- @version 0.1.0
-- @link https://github.com/Psysia/PsyReaWwise
-- @about
--   Pull Wwise sources into REAPER and transfer rendered WAVs to Wwise and Samples.
--   将 Wwise 音源取回 REAPER，并将渲染后的 WAV 同步到 Wwise 与 Samples。

local api = reaper
local title = "PsyReaWwise"
if not api.APIExists("ImGui_GetBuiltinPath") then
    api.ShowMessageBox("请先通过 ReaPack 安装 ReaImGui 0.10 或以上版本。", title, 0)
    return
end
if not api.APIExists("GetRegionOrMarker") then
    api.ShowMessageBox("请使用支持区间选择接口的 REAPER 7。此版本以 REAPER 7.86 为目标。", title, 0)
    return
end

local ImGui
do
    package.path = api.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
    local ok, module = pcall(function() return require("imgui")("0.10") end)
    if not ok then
        api.ShowMessageBox("无法加载 ReaImGui 0.10。请更新 ReaImGui 后重试。", title, 0)
        return
    end
    ImGui = module
end

local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]")
local function load_module(name, ...)
    return assert(loadfile(root .. "/lib/" .. name .. ".lua"))(...)
end
local files = load_module("files")
local wwise = load_module("wwise")
local project = load_module("project", files)
local samples = load_module("samples", files)
local workflow = load_module("workflow", files, project, wwise, samples)

local context = ImGui.CreateContext(title)
local font = ImGui.CreateFont("Microsoft YaHei")
ImGui.Attach(context, font)

local stored_port = tonumber(api.GetExtState(title, "port"))
local state = {
    port = stored_port or 8080,
    current = api.EnumProjects(-1, ""),
    mode = "items",
    placement = "same",
    make_regions = true,
    checked = {},
}

local function status(message, failed)
    state.message = message
    state.failed = failed
end

local function enqueue(label, operation)
    if state.pending then return end
    status(label)
    state.pending = function()
        local ok, message = pcall(operation)
        status(tostring(message), not ok)
    end
    state.wait_frame = true
end

local function button(name, enabled, primary)
    if primary then
        ImGui.PushStyleColor(context, ImGui.Col_Button, 0x235B56FF)
        ImGui.PushStyleColor(context, ImGui.Col_ButtonHovered, 0x2A756CFF)
        ImGui.PushStyleColor(context, ImGui.Col_ButtonActive, 0x205047FF)
    end
    ImGui.BeginDisabled(context, not enabled or state.pending ~= nil)
    local pressed = ImGui.Button(context, name)
    ImGui.EndDisabled(context)
    if primary then ImGui.PopStyleColor(context, 3) end
    return pressed
end

local function help_path(path)
    if ImGui.IsItemHovered(context) then ImGui.SetTooltip(context, path) end
end

local function check_project(current)
    assert(api.EnumProjects(-1, "") == current, "REAPER 已切换工程，请重新选择。")
end

local function checked_sources()
    local sources = {}
    if state.selection then
        for _, source in ipairs(state.selection.sources) do
            if state.checked[source.id] then sources[#sources + 1] = source end
        end
    end
    return sources
end

local table_flags = ImGui.TableFlags_BordersInnerH + ImGui.TableFlags_RowBg
    + ImGui.TableFlags_Resizable + ImGui.TableFlags_ScrollY

local function table_height()
    local _, space = ImGui.GetContentRegionAvail(context)
    return math.max(105, space - 70)
end

local function draw_samples(current)
    local directory, custom = samples.directory(current)
    if button("选择 Samples 目录", true, false) then
        enqueue("正在选择导出目录…", function()
            check_project(current)
            local accepted, path = api.GetUserFileName(3, "选择 REAPER 工程的 Samples 导出目录", directory or "", "")
            if not accepted then return "已取消目录选择。" end
            samples.set_directory(current, path)
            state.plan, state.transfer = nil, nil
            return "Samples 目录已设置。"
        end)
    end
    if custom then
        ImGui.SameLine(context)
        if button("使用默认 Samples", true, false) then
            samples.set_directory(current, "")
            state.plan, state.transfer = nil, nil
            directory = samples.directory(current)
        end
    end
    if directory then
        ImGui.TextWrapped(context, "Samples · " .. directory)
    else
        ImGui.TextWrapped(context, "保存 REAPER 工程后将使用 .rpp 同级的 Samples，也可以选择已有导出目录。")
    end
    return directory
end

local function draw_pull(current)
    local available = wwise.available()
    if button("读取 Wwise 选中项", available, false) then
        local port = state.port
        enqueue("正在读取 Wwise 选中项…", function()
            state.selection, state.checked = nil, {}
            state.selection = workflow.read_selection(port)
            for _, source in ipairs(state.selection.sources) do
                state.checked[source.id] = source.wav ~= ""
            end
            return ("%s · 读到 %d 个音源"):format(state.selection.origin.name, #state.selection.sources)
        end)
    end

    local selection = state.selection
    local chosen = checked_sources()
    ImGui.SameLine(context)
    if button(("导入 %d 个音源"):format(#chosen), available and #chosen > 0, true) then
        local port, regions = state.port, state.make_regions
        enqueue("正在导入到 REAPER…", function()
            check_project(current)
            local directory = workflow.pull(current, port, selection.origin, chosen, regions)
            state.plan = nil
            return ("已导入 %d 个音源。工作副本在\n%s"):format(#chosen, directory)
        end)
    end
    ImGui.SameLine(context)
    local changed, regions = ImGui.Checkbox(context, "创建区间", state.make_regions)
    if changed then state.make_regions = regions end

    if not selection then
        ImGui.TextWrapped(context, available and "在 Wwise 里选中音源、Sound 或容器，然后读取选中项。"
            or "此流程需要 ReaWwise 1.0.4 或以上版本提供 WAAPI 接口。")
        return
    end

    if #selection.sources == 0 then
        ImGui.TextWrapped(context, "当前选择下没有 AudioFileSource。")
        return
    end
    if button("全选", true, false) then
        for _, source in ipairs(selection.sources) do state.checked[source.id] = source.wav ~= "" end
    end
    ImGui.SameLine(context)
    if button("清空勾选", true, false) then state.checked = {} end
    ImGui.SameLine(context)
    local label = state.mode == "items" and "素材" or "区间"
    if button("绑定到 REAPER 选中" .. label, available and #chosen == 1, false) then
        local port, mode = state.port, state.mode
        enqueue("正在绑定 Wwise 音源…", function()
            check_project(current)
            workflow.bind(current, port, selection.origin, chosen[1], mode)
            state.plan = nil
            return "已绑定 " .. chosen[1].path
        end)
    end
    if ImGui.IsItemHovered(context) then ImGui.SetTooltip(context, "在“更新现有音源”页切换素材或区间模式。") end

    if ImGui.BeginTable(context, "WwiseSources", 4, table_flags, 0, table_height()) then
        ImGui.TableSetupColumn(context, "导入", ImGui.TableColumnFlags_WidthFixed, 46)
        ImGui.TableSetupColumn(context, "Wwise 音源")
        ImGui.TableSetupColumn(context, "语言", ImGui.TableColumnFlags_WidthFixed, 100)
        ImGui.TableSetupColumn(context, "Originals 路径")
        ImGui.TableSetupScrollFreeze(context, 0, 1)
        ImGui.TableHeadersRow(context)
        for _, source in ipairs(selection.sources) do
            ImGui.TableNextRow(context)
            ImGui.TableSetColumnIndex(context, 0)
            ImGui.BeginDisabled(context, source.wav == "")
            local toggled, checked = ImGui.Checkbox(context, "##" .. source.id, state.checked[source.id] == true)
            ImGui.EndDisabled(context)
            if toggled then state.checked[source.id] = checked end
            ImGui.TableSetColumnIndex(context, 1)
            ImGui.Text(context, source.name)
            help_path(source.path)
            ImGui.TableSetColumnIndex(context, 2)
            ImGui.Text(context, source.language ~= "" and source.language or "—")
            ImGui.TableSetColumnIndex(context, 3)
            ImGui.Text(context, source.relative ~= "" and source.relative or "缺少原文件路径")
            help_path(source.wav)
        end
        ImGui.EndTable(context)
    end
end

local function draw_update(current)
    local sample_directory = draw_samples(current)
    local item_mode = ImGui.RadioButton(context, "选中素材", state.mode == "items")
    ImGui.SameLine(context)
    local region_mode = ImGui.RadioButton(context, "选中区间", state.mode == "regions")
    if (item_mode and state.mode ~= "items") or (region_mode and state.mode ~= "regions") then
        state.mode = item_mode and "items" or "regions"
        state.plan = nil
    end
    ImGui.SameLine(context)
    if button("预览更新", wwise.available() and sample_directory ~= nil, false) then
        local port, mode = state.port, state.mode
        enqueue("正在核对 Wwise 音源…", function()
            check_project(current)
            state.plan = nil
            state.plan = workflow.preview(current, port, mode, sample_directory)
            return ("%s · 待更新 %d 个原始文件"):format(state.plan.origin.name, #state.plan.entries)
        end)
    end

    local plan = state.plan
    if not plan then
        ImGui.TextWrapped(context, state.mode == "items" and "选中已绑定 Wwise 音源的素材。更新时逐个渲染。"
            or "在 REAPER 标尺上选中已绑定的区间。更新时按区间渲染主混音。")
        return
    end

    ImGui.SameLine(context)
    if button(("渲染并覆盖 %d 个 WAV"):format(#plan.entries), true, true) then
        enqueue("正在备份、渲染并更新 Wwise…", function()
            state.plan = nil
            local report = workflow.update(plan)
            return ("Wwise 已更新 %d 个音源，Samples 已同步 %d 个。备份在\n%s")
                :format(report.count, report.mirrored, report.directory)
        end)
    end
    ImGui.TextWrapped(context, "更新前将备份原 WAV。共享同一 Originals 文件的音源会使用更新后的文件。")

    if ImGui.BeginTable(context, "UpdateTargets", 5, table_flags, 0, table_height()) then
        ImGui.TableSetupColumn(context, "REAPER")
        ImGui.TableSetupColumn(context, "Wwise Originals")
        ImGui.TableSetupColumn(context, "渲染格式", ImGui.TableColumnFlags_WidthFixed, 140)
        ImGui.TableSetupColumn(context, "引用数", ImGui.TableColumnFlags_WidthFixed, 66)
        ImGui.TableSetupColumn(context, "Samples", ImGui.TableColumnFlags_WidthFixed, 75)
        ImGui.TableSetupScrollFreeze(context, 0, 1)
        ImGui.TableHeadersRow(context)
        for _, entry in ipairs(plan.entries) do
            ImGui.TableNextRow(context)
            ImGui.TableSetColumnIndex(context, 0)
            ImGui.Text(context, entry.selection.name)
            ImGui.TableSetColumnIndex(context, 1)
            ImGui.Text(context, entry.source.relative)
            help_path(entry.source.path .. "\n" .. entry.source.wav)
            ImGui.TableSetColumnIndex(context, 2)
            ImGui.Text(context, ("%g kHz · %s"):format(entry.info.rate / 1000, entry.info.channels == 1 and "单声道" or "立体声"))
            ImGui.TableSetColumnIndex(context, 3)
            ImGui.Text(context, tostring(#entry.usage))
            local references = {}
            for _, use in ipairs(entry.usage) do references[#references + 1] = use.path end
            help_path(table.concat(references, "\n"))
            ImGui.TableSetColumnIndex(context, 4)
            ImGui.Text(context, entry.sample.exists and "替换" or "新增")
            help_path(entry.sample.path)
        end
        ImGui.EndTable(context)
    end
end

local function draw_transfer(current)
    local sample_directory = draw_samples(current)
    local open = api.NamedCommandLookup("_AK_ReaWwise_Open")
    if button("打开 REAPER 渲染设置", true, false) then
        enqueue("正在打开渲染设置…", function()
            check_project(current)
            api.Main_OnCommandEx(40015, 0, current)
            state.transfer = nil
            return "设置渲染范围和文件命名后，回到工作台预览传输。"
        end)
    end
    ImGui.SameLine(context)
    if button("打开 ReaWwise 高级传输", open ~= 0, false) then
        enqueue("正在打开 ReaWwise…", function()
            check_project(current)
            api.Main_OnCommandEx(open, 0, current)
            return "在 ReaWwise 中设置目标层级和 Originals 子目录，预览后执行传输。"
        end)
    end
    if open == 0 then
        ImGui.TextWrapped(context, "安装 ReaWwise 并重启 REAPER 后，可在这里打开官方传输面板。")
    end

    local same = ImGui.RadioButton(context, "Wwise 同级 / 容器内", state.placement == "same")
    ImGui.SameLine(context)
    local parent = ImGui.RadioButton(context, "Wwise 上一级", state.placement == "parent")
    if (same and state.placement ~= "same") or (parent and state.placement ~= "parent") then
        state.placement = same and "same" or "parent"
        state.transfer = nil
    end
    ImGui.SameLine(context)
    if button("预览传输", wwise.available() and sample_directory ~= nil, false) then
        local port, placement = state.port, state.placement
        enqueue("正在读取 Wwise 位置和 REAPER 渲染目标…", function()
            check_project(current)
            state.transfer = nil
            state.transfer = workflow.preview_transfer(current, port, placement, sample_directory)
            return ("待传输 %d 个 WAV"):format(#state.transfer.entries)
        end)
    end

    local plan = state.transfer
    if not plan then
        ImGui.TextWrapped(context, "在 Wwise 选择参照音源、Sound 或容器。预览会列出 Wwise 和 Samples 的落点。")
        return
    end
    ImGui.SameLine(context)
    if button(("渲染并传输 %d 个 WAV"):format(#plan.entries), true, true) then
        enqueue("正在渲染并同步 Wwise 与 Samples…", function()
            state.transfer = nil
            local report = workflow.transfer(plan)
            return ("Wwise 已核验 %d 个 WAV，Samples 已同步 %d 个。暂存与备份在\n%s")
                :format(report.count, report.mirrored, report.directory)
        end)
    end

    ImGui.TextWrapped(context, plan.origin.name .. " · " .. plan.target.path)
    ImGui.TextWrapped(context, "Originals · " .. workflow.originals_directory(plan.location))
    if ImGui.BeginTable(context, "TransferTargets", 4, table_flags, 0, table_height()) then
        ImGui.TableSetupColumn(context, "WAV")
        ImGui.TableSetupColumn(context, "Originals")
        ImGui.TableSetupColumn(context, "Wwise", ImGui.TableColumnFlags_WidthFixed, 100)
        ImGui.TableSetupColumn(context, "Samples", ImGui.TableColumnFlags_WidthFixed, 80)
        ImGui.TableSetupScrollFreeze(context, 0, 1)
        ImGui.TableHeadersRow(context)
        for _, entry in ipairs(plan.entries) do
            ImGui.TableNextRow(context)
            ImGui.TableSetColumnIndex(context, 0)
            ImGui.Text(context, files.name(entry.replacement))
            ImGui.TableSetColumnIndex(context, 1)
            ImGui.Text(context, entry.source.relative)
            help_path(entry.source.wav)
            ImGui.TableSetColumnIndex(context, 2)
            local operation = entry.existing and "更新音源" or "新建 Sound"
            if #entry.usage > 1 then operation = operation .. " · 共享" end
            ImGui.Text(context, operation)
            local references = {}
            for _, use in ipairs(entry.usage) do references[#references + 1] = use.path end
            help_path(table.concat(references, "\n"))
            ImGui.TableSetColumnIndex(context, 3)
            ImGui.Text(context, entry.sample.exists and "替换" or "新增")
            help_path(entry.sample.path)
        end
        ImGui.EndTable(context)
    end
end

local function loop()
    if state.pending then
        if state.wait_frame then
            state.wait_frame = false
        else
            local operation = state.pending
            state.pending = nil
            operation()
        end
    end

    local current = api.EnumProjects(-1, "")
    if current ~= state.current then
        state.current = current
        state.plan, state.transfer = nil, nil
    end
    ImGui.SetNextWindowSize(context, 860, 510, ImGui.Cond_FirstUseEver)
    local visible, open = ImGui.Begin(context, title, true)
    if visible then
        ImGui.PushFont(context, font, 16)
        ImGui.BeginDisabled(context, state.pending ~= nil)
        ImGui.SetNextItemWidth(context, 88)
        local changed, port = ImGui.InputInt(context, "WAAPI 端口", state.port, 0, 0)
        ImGui.EndDisabled(context)
        if changed then
            state.port = math.max(1, math.min(65535, port))
            api.SetExtState(title, "port", tostring(state.port), true)
            state.selection, state.plan, state.transfer, state.checked = nil, nil, nil, {}
        end
        ImGui.SameLine(context)
        ImGui.TextDisabled(context, "127.0.0.1")
        ImGui.Spacing(context)

        if ImGui.BeginTabBar(context, "Workflows") then
            if ImGui.BeginTabItem(context, "导入到 REAPER") then
                draw_pull(current)
                ImGui.EndTabItem(context)
            end
            if ImGui.BeginTabItem(context, "更新现有音源") then
                draw_update(current)
                ImGui.EndTabItem(context)
            end
            if ImGui.BeginTabItem(context, "传输到 Wwise") then
                draw_transfer(current)
                ImGui.EndTabItem(context)
            end
            ImGui.EndTabBar(context)
        end

        if state.message then
            ImGui.Spacing(context)
            ImGui.Separator(context)
            ImGui.PushStyleColor(context, ImGui.Col_Text, state.failed and 0xF2AD9CFF or 0xB7D6CEFF)
            ImGui.TextWrapped(context, state.message)
            ImGui.PopStyleColor(context)
        end
        ImGui.PopFont(context)
        ImGui.End(context)
    end
    if open then api.defer(loop) end
end

loop()
