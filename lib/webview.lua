local api = reaper
local webview = {}
local section = "PsyReaWwise.WebView"

local label_keys = {
    port = "WAAPI 端口",
    project = "REAPER 工程",
    unsaved = "未保存的工程",
    pullTab = "导入到 REAPER",
    updateTab = "更新现有音源",
    transferTab = "传输到 Wwise",
    readSelection = "读取 Wwise 选中项",
    pullHint = "在 Wwise 里选中音源、Sound 或容器，然后读取选中项。",
    emptySelection = "当前选择下没有 AudioFileSource。",
    needWaapi = "此流程需要 ReaWwise 1.0.4 或以上版本提供 WAAPI 接口。",
    importCount = "导入 %d 个音源",
    chooseAll = "全选",
    clear = "清空勾选",
    regions = "创建区间",
    source = "Wwise 音源",
    language = "语言",
    originals = "Originals 路径",
    noOriginal = "缺少原文件路径",
    bindTo = "绑定到 REAPER 选中%s",
    bindHint = "在“更新现有音源”页切换素材或区间模式。",
    item = "素材",
    region = "区间",
    items = "选中素材",
    selectedRegions = "选中区间",
    syncSamples = "同步到 Samples",
    samplesChoose = "选择 Samples 目录",
    samplesDefault = "使用默认 Samples",
    samplesHint = "保存 REAPER 工程后将使用 .rpp 同级的 Samples，也可以选择已有导出目录。",
    itemUpdateHint = "选中已绑定 Wwise 音源的素材。更新时逐个渲染。",
    regionUpdateHint = "在 REAPER 标尺上选中已绑定的区间。预览会读取区间渲染矩阵。",
    previewUpdate = "预览更新",
    updateCount = "渲染并覆盖 %d 个 WAV",
    updateNote = "更新前将备份原 WAV。共享同一 Originals 文件的音源会使用更新后的文件。",
    renderFormat = "渲染格式",
    referenceCount = "引用数",
    mono = "单声道",
    stereo = "立体声",
    replace = "替换",
    add = "新增",
    sameLevel = "Wwise 同级 / 容器内",
    parentLevel = "Wwise 上一级",
    previewTransfer = "预览传输",
    transferHint = "选中 REAPER 区间和 Wwise WAV 后点预览。同名自动配对，其他可手动连线。",
    transferCount = "渲染并传输 %d 个 WAV",
    replaceCount = "渲染并替换 %d 个 WAV",
    regionNodes = "REAPER 区间",
    wavNodes = "Wwise WAV",
    pairHint = "从区间拖到 WAV，或依次点击两端。选中连线后按 Delete 可断开。",
    pairCount = "%d 个区间 → %d 个 WAV",
    disconnect = "断开 %s",
    clearLinks = "断开全部",
    reuseName = "%d 个目标 · 共用区间名",
    renameTo = "区间将改名为 %s",
    unnamedRegion = "未命名区间",
    newSoundLocation = "新增音源的导入位置",
    renderSetup = "渲染设置",
    renderPreset = "REAPER 预设",
    defaultPreset = "PRW 默认设置",
    refreshPresets = "刷新预设",
    noPresets = "在 REAPER 的 Render 面板将预设保存为「所有设置」。",
    wavPresetOnly = "需要一个 WAV 输出",
    renderSource = "源",
    renderBounds = "范围",
    regionMatrix = "区间渲染矩阵",
    projectRender = "REAPER 当前渲染设置",
    connectedRegions = "已配对区间",
    renderOutput = "输出",
    renderSampleRate = "采样率",
    renderChannels = "声道",
    renderNormalize = "标准化",
    renderLimiter = "限制器",
    renderTail = "尾音",
    renderFade = "淡入 / 淡出",
    retainOriginal = "按目标 WAV",
    projectRate = "工程采样率",
    off = "关闭",
    mainMix = "主混音",
    updateSource = "更新音源",
    newSound = "新建 Sound",
    shared = " · 共享",
    reading = "正在读取 Wwise 选中项…",
    importing = "正在导入到 REAPER…",
    binding = "正在绑定 Wwise 音源…",
    choosing = "正在选择导出目录…",
    checking = "正在核对 Wwise 音源…",
    updating = "正在备份、渲染并更新 Wwise…",
    previewing = "正在读取 REAPER 区间和 Wwise 选择…",
    transferring = "正在渲染并传输到 Wwise…",
    requestFailed = "无法将操作送到 REAPER。请重新打开工作台。",
}

function webview.new(t, files, project, wwise, samples, workflow, language, presets)
    local labels = {}
    for key, text in pairs(label_keys) do labels[key] = t(text) end
    local port = tonumber(api.GetExtState(section, "port"))
        or tonumber(api.GetExtState("PsyReaWwise", "port")) or 8080
    local state = {port = math.max(1, math.min(65535, math.floor(port))), epoch = 0, revision = 0}
    local handlers = {}

    local function refresh()
        local current, filename = api.EnumProjects(-1, "")
        local folder, custom = samples.directory(current)
        local changed = state.current ~= current or state.filename ~= filename or state.folder ~= folder
        if changed then
            state.current, state.filename, state.folder = current, filename, folder
            state.epoch = state.epoch + 1
            state.pull, state.update, state.transfer = nil, nil, nil
        end
        return changed, custom
    end

    local function project_view()
        local _, custom = refresh()
        return {
            epoch = state.epoch, port = state.port,
            project = (state.filename and files.name(state.filename)) or labels.unsaved,
            samples = state.folder or "", customSamples = custom == true,
            waapi = wwise.available() == true,
        }
    end

    local function require_current(params)
        assert(params.epoch == state.epoch, t("REAPER 已切换工程，请重新选择。"))
        return state.current
    end

    local function ready_sources(ids)
        assert(state.pull and type(ids) == "table", t("请先读取 Wwise 选中项。"))
        local chosen, seen = {}, {}
        for _, id in ipairs(ids) do
            local source = state.pull.by_id[id]
            assert(source and source.wav ~= "" and not seen[id], t("Wwise 选择已变化，请重新读取。"))
            chosen[#chosen + 1], seen[id] = source, true
        end
        assert(#chosen > 0, t("请勾选要导入的音源。"))
        return chosen
    end

    local function mode(params)
        assert(params.mode == "items" or params.mode == "regions", t("无效的 REAPER 素材或区间模式。"))
        return params.mode
    end

    local function store_preview(kind, plan)
        state.revision = state.revision + 1
        local saved = state[kind] or {}
        saved.id, saved.plan = state.revision, plan
        state[kind] = saved
        local rows = {}
        for index, entry in ipairs(plan.entries) do
            local references = {}
            for _, use in ipairs(entry.usage) do references[#references + 1] = use.path end
            local info = plan.preset and plan.preset.view or entry.info
            local format
            if info then
                local rate = info.rate == 0 and labels.projectRate or ("%g kHz"):format(info.rate / 1000)
                local channels = info.channels == 1 and labels.mono
                    or info.channels == 2 and labels.stereo or tostring(info.channels)
                format = rate .. " · " .. channels
            end
            rows[index] = {
                name = entry.selection and entry.selection.name or files.name(entry.replacement),
                targetId = plan.region_draft and entry.source.id,
                originals = entry.source.relative, originalsPath = entry.source.wav,
                references = references, existing = entry.existing == true,
                format = format,
                sample = entry.sample and entry.sample.path,
                replace = entry.sample and entry.sample.exists == true,
            }
        end
        return {
            id = state.revision, rows = rows, project = plan.origin.name,
            matrix = plan.mode == "regions" and plan.entries[1].selection.render_track ~= nil,
            syncSamples = plan.sample_directory ~= nil,
            target = plan.target and plan.target.path,
            folder = plan.location and workflow.originals_directory(plan.location),
        }
    end

    local function publish_preview(kind, params, operation)
        require_current(params)
        local prepared = state[kind]
        assert(prepared and prepared.plan and prepared.id == params.preview, t("请先重新预览。"))
        state[kind] = nil
        local report = operation(prepared.plan)
        if report.sample_directory then
            return {message = t("Wwise 已核验 %d 个 WAV，Samples 已同步 %d 个。暂存与备份在\n%s")
                :format(report.count, report.mirrored, report.directory)}
        end
        return {message = t("Wwise 已核验 %d 个 WAV。暂存与备份在\n%s"):format(report.count, report.directory)}
    end

    local function sample_destination(params)
        if params.syncSamples == false then return nil end
        return assert(state.folder, labels.samplesHint)
    end

    local function map_regions(params, links)
        local saved = state.transfer
        saved.id, saved.plan = nil, nil
        local plan = workflow.preview_region_transfer(saved.draft, links, sample_destination(params),
            presets.resolve(params.renderPreset))
        if #plan.entries > 0 then return store_preview("transfer", plan) end
    end

    handlers["session"] = function()
        state.pull, state.update, state.transfer = nil, nil, nil
        local ok, list = pcall(presets.read)
        return {labels = labels, language = language, project = project_view(),
            renderPresets = ok and list or {}, presetError = not ok and tostring(list) or nil}
    end

    handlers["project.read"] = project_view

    handlers["render.presets"] = function(params)
        require_current(params)
        local list = presets.read()
        return {renderPresets = list}
    end

    handlers["port.set"] = function(params)
        local value = params.port
        assert(type(value) == "number" and value >= 1 and value <= 65535 and value % 1 == 0,
            t("WAAPI 端口必须是 1 到 65535 的整数。"))
        state.port = value
        state.pull, state.update, state.transfer = nil, nil, nil
        api.SetExtState(section, "port", tostring(value), true)
        return project_view()
    end

    handlers["pull.read"] = function(params)
        require_current(params)
        state.pull = nil
        local selection = workflow.read_selection(state.port)
        local by_id = {}
        for _, source in ipairs(selection.sources) do by_id[source.id] = source end
        state.pull = {origin = selection.origin, by_id = by_id}
        return {sources = selection.sources, project = selection.origin.name,
            message = t("%s · 读到 %d 个音源"):format(selection.origin.name, #selection.sources)}
    end

    handlers["pull.import"] = function(params)
        local current = require_current(params)
        local sources = ready_sources(params.ids)
        local directory = workflow.pull(current, state.port, state.pull.origin, sources, params.regions == true)
        state.update, state.transfer = nil, nil
        return {message = t("已导入 %d 个音源。工作副本在\n%s"):format(#sources, directory)}
    end

    handlers["pull.bind"] = function(params)
        local current = require_current(params)
        local sources = ready_sources(params.ids)
        assert(#sources == 1, t("请只勾选一个 Wwise 音源进行绑定。"))
        workflow.bind(current, state.port, state.pull.origin, sources[1], mode(params))
        state.update = nil
        return {message = t("已绑定 %s"):format(sources[1].path)}
    end

    handlers["samples.choose"] = function(params)
        local current = require_current(params)
        local accepted, path = api.GetUserFileName(3, t("选择 REAPER 工程的 Samples 导出目录"), state.folder or "", "")
        if not accepted then return {project = project_view(), message = t("已取消目录选择。")} end
        refresh()
        require_current(params)
        samples.set_directory(current, path)
        return {project = project_view(), message = t("Samples 目录已设置。")}
    end

    handlers["samples.reset"] = function(params)
        samples.set_directory(require_current(params), "")
        return {project = project_view(), message = t("Samples 目录已设置。")}
    end

    handlers["update.preview"] = function(params)
        local current = require_current(params)
        state.update = nil
        return store_preview("update", workflow.preview(current, state.port, mode(params), sample_destination(params),
            presets.resolve(params.renderPreset)))
    end

    handlers["update.publish"] = function(params)
        return publish_preview("update", params, workflow.update)
    end

    handlers["transfer.preview"] = function(params)
        local current = require_current(params)
        state.transfer = nil
        local draft = workflow.read_region_transfer(current, state.port)
        if draft then
            state.revision = state.revision + 1
            local key = state.revision
            state.transfer = {key = key, draft = draft}
            local regions, targets = {}, {}
            for index, region in ipairs(draft.regions) do
                regions[index] = {id = region.id, name = region.name, number = region.number,
                    renderable = region.can_render and not region.render_error, renderLabel = region.render_label,
                    renderError = region.render_error, matrix = region.render_track ~= nil or region.render_error ~= nil}
            end
            for index, target in ipairs(draft.targets) do
                targets[index] = {id = target.source.id, name = target.name, originals = target.source.relative,
                    originalsPath = target.source.wav, references = #target.usage}
            end
            local links = workflow.match_regions(draft)
            local ok, plan = pcall(map_regions, params, links)
            return {kind = "regions", draft = key, regions = regions, targets = targets, links = links,
                plan = ok and plan or nil, message = not ok and tostring(plan) or nil, error = not ok or nil}
        end
        assert(params.placement == "same" or params.placement == "parent", t("无效的 Wwise 传输层级。"))
        return store_preview("transfer",
            workflow.preview_transfer(current, state.port, params.placement, sample_destination(params),
                presets.resolve(params.renderPreset)))
    end

    handlers["transfer.map"] = function(params)
        require_current(params)
        local saved = state.transfer
        assert(saved and saved.draft and saved.key == params.draft, t("请先重新预览。"))
        return {plan = map_regions(params, params.links)}
    end

    handlers["transfer.publish"] = function(params)
        return publish_preview("transfer", params, workflow.transfer)
    end

    return {
        project = project_view,
        refresh = refresh,
        receive = function(method, params)
            refresh()
            local handler = assert(handlers[method], t("工作台收到不支持的操作。"))
            return handler(params)
        end,
    }
end

return webview
