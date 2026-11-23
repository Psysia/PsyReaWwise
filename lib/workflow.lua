local files, project, wwise, samples, t = ...
local workflow = {}

local function same_origin(first, second)
    return first.id:lower() == second.id:lower() and files.key(first.path) == files.key(second.path)
end

local function verify_origin(expected)
    local actual = wwise.project()
    assert(same_origin(expected, actual), t("Wwise 已切换工程，请重新读取或预览。"))
    return actual
end

function workflow.read_selection(port)
    return wwise.session(port, function()
        return {origin = wwise.project(), sources = wwise.selected_sources()}
    end)
end

local function current_sources(port, origin, selected)
    return wwise.session(port, function()
        verify_origin(origin)
        local ids = {}
        for index, source in ipairs(selected) do ids[index] = source.id end
        local actual, sorted = wwise.sources(ids), {}
        for index, source in ipairs(selected) do
            local current = actual[source.id:lower()]
            assert(current and current.wav ~= "", t("找不到 Wwise 原始音频\n") .. source.path)
            assert(files.key(current.wav) == files.key(source.wav), t("Wwise 原始音频路径发生变化，请重新读取选择。"))
            sorted[index] = current
        end
        return sorted
    end)
end

function workflow.pull(current, port, origin, selected, make_regions)
    assert(#selected > 0, t("请勾选要导入的音源。"))
    return project.import_sources(current, origin, current_sources(port, origin, selected), make_regions)
end

function workflow.bind(current, port, origin, source, mode)
    local entries = project.selection(current, mode)
    local label = mode == "items" and t("素材") or t("区间")
    assert(#entries == 1 and entries[1].can_render, (t("请在 REAPER 中只选一个可渲染的%s。")):format(label))
    local found = current_sources(port, origin, {source})[1]
    reaper.Undo_BeginBlock2(current)
    local ok, problem = pcall(project.bind, current, mode, entries[1], origin, found)
    reaper.Undo_EndBlock2(current, t("PsyReaWwise · 绑定 Wwise 音源"), -1)
    if not ok then error(problem, 0) end
end

local function source_location(source)
    local relative = source.relative:gsub("/", "\\")
    local parts = {}
    for part in relative:gmatch("[^\\]+") do
        assert(part ~= "." and part ~= ".." and not part:find(":", 1, true), t("Wwise 原始音频相对路径无效\n") .. relative)
        parts[#parts + 1] = part
    end

    local first
    if #parts >= 2 and parts[1]:lower() == "sfx" and source.language:lower() == "sfx" then
        first = 2
    elseif #parts >= 3 and parts[1]:lower() == "voices" and parts[2]:lower() == source.language:lower() then
        first = 3
    end
    assert(first, t("无法判断 Wwise 音源的语言目录\n") .. relative)
    return {language = source.language, root = table.concat(parts, "\\", 1, first - 1),
        subfolder = table.concat(parts, "\\", first, #parts - 1)}
end

local function prepare_target(origin, source, known_usage)
    assert(source.parent ~= "" and source.name ~= "" and not source.name:find("[\\/<>]"),
        t("无法定位 Wwise 原始音频\n") .. source.path)
    assert(source.relative:lower():match("%.wav$"), t("更新现有音源目前支持 WAV\n") .. source.relative)
    local location = source_location(source)
    assert(files.key(source.wav) == files.key(files.join(origin.originals, source.relative)),
        t("Wwise 音源路径与当前工程的 Originals 不一致\n") .. source.wav)
    source.subfolder = location.subfolder

    local usage = known_usage or wwise.file_usage(source.relative)
    local keys, found = {}, false
    for index, use in ipairs(usage) do
        keys[index] = use.id:lower()
        if keys[index] == source.id:lower() then found = true end
    end
    assert(found, t("Wwise 无法确认此 Originals 文件的引用\n") .. source.relative)
    table.sort(keys)
    return usage, table.concat(keys, "\n")
end

local function existing_entry(selection, source, usage, usage_key)
    local info = project.audio_info(source.wav)
    assert(info.channels <= 2, t("更新现有音源目前支持单声道或立体声 WAV\n") .. source.wav)
    return {selection = selection, source = source, info = info, usage = usage, usage_key = usage_key}
end

local function selection_ids(entries, origin)
    local ids, seen = {}, {}
    for index, entry in ipairs(entries) do
        local bound = entry.binding
        assert(entry.can_render, t("选中内容无法渲染\n") .. entry.name)
        assert(bound, t("选中内容尚未绑定 Wwise 音源\n") .. entry.name)
        assert(same_origin(origin, {id = bound.project_id, path = bound.project_path}),
            t("选中内容绑定的是另一个 Wwise 工程\n") .. entry.name)
        local key = bound.source_id:lower()
        assert(not seen[key], t("多个选中内容指向同一个 Wwise 音源\n") .. entry.name)
        seen[key] = true
        ids[index] = bound.source_id
    end
    return ids
end

local function make_plan(current, port, mode, sample_directory)
    local selection = project.selection(current, mode)
    assert(#selection > 0, mode == "items" and t("请先在 REAPER 中选中素材。") or t("请先在 REAPER 中选中区间。"))
    return wwise.session(port, function()
        local origin = wwise.project()
        local ids = selection_ids(selection, origin)
        local sources, entries, paths = wwise.sources(ids), {}, {}
        for index, id in ipairs(ids) do
            local source = assert(sources[id:lower()], t("找不到绑定的 Wwise 音源\n") .. selection[index].name)
            local usage, usage_key = prepare_target(origin, source)
            local path_key = files.key(source.wav)
            assert(not paths[path_key], t("多个选中内容指向同一个 Originals 文件\n") .. source.wav)
            paths[path_key] = true
            entries[#entries + 1] = existing_entry(selection[index], source, usage, usage_key)
        end
        samples.plan(entries, sample_directory)
        return {current = current, port = port, mode = mode, origin = origin, entries = entries,
            sample_directory = sample_directory}
    end)
end

workflow.preview = make_plan

local function same_target(first, second)
    return first.id:lower() == second.id:lower() and first.parent:lower() == second.parent:lower()
        and first.name == second.name and first.path == second.path and first.language == second.language
        and files.key(first.wav) == files.key(second.wav) and files.key(first.relative) == files.key(second.relative)
end

local function check_preview(before, current)
    assert(same_origin(before.origin, current.origin), t("Wwise 已切换工程，请重新预览。"))
    assert(#before.entries == #current.entries, t("REAPER 选择发生变化，请重新预览。"))
    local by_id = {}
    for _, entry in ipairs(before.entries) do by_id[entry.selection.id] = entry end
    for _, entry in ipairs(current.entries) do
        local previous = by_id[entry.selection.id]
        assert(previous, t("REAPER 选择发生变化，请重新预览。"))
        assert(same_target(previous.source, entry.source) and previous.usage_key == entry.usage_key
            and previous.info.rate == entry.info.rate and previous.info.channels == entry.info.channels,
            t("Wwise 音源或文件引用发生变化，请重新预览。"))
        assert(samples.same(previous.sample, entry.sample), t("Samples 目录或同名文件状态发生变化，请重新预览。"))
    end
end

local function verify_sample_directory(preview)
    if not preview.sample_directory then return end
    local current = samples.directory(preview.current)
    assert(current and files.key(current) == files.key(preview.sample_directory), t("Samples 目录已变化，请重新预览。"))
end

local function publish_existing(plan)
    local directory = project.directory(plan.current, "Transfers")
    local completed, mirrored = 0, 0

    local ok, problem = pcall(function()
        for index, entry in ipairs(plan.entries) do
            local name = files.name(entry.source.wav)
            local stage = files.join(directory, "Render/" .. index)
            local backup = files.join(directory, "Backup/" .. index)
            local publish = files.join(stage, "Publish")
            reaper.RecursiveCreateDirectory(backup, 0)
            reaper.RecursiveCreateDirectory(publish, 0)
            entry.stage = stage
            entry.backup = files.join(backup, name)
            entry.replacement = files.join(publish, name)
            files.copy(entry.source.wav, entry.backup)
            samples.backup(entry, directory, index)
        end

        project.render(plan.current, plan.mode, plan.entries)
        assert(reaper.EnumProjects(-1, "") == plan.current, t("REAPER 已切换工程，请重新预览。"))

        wwise.session(plan.port, function()
            local origin = verify_origin(plan.origin)
            local ids, usage_cache = {}, {}
            for index, entry in ipairs(plan.entries) do ids[index] = entry.source.id end
            local sources = wwise.sources(ids)

            for _, entry in ipairs(plan.entries) do
                local current = sources[entry.source.id:lower()]
                assert(current and same_target(entry.source, current), t("Wwise 音源目标发生变化\n") .. entry.source.path)
                local _, usage_key = prepare_target(origin, current, wwise.file_usage(current.relative, usage_cache))
                assert(usage_key == entry.usage_key, t("Wwise 文件引用发生变化\n") .. current.path)
                assert(files.equal(current.wav, entry.backup), t("Originals 文件在渲染期间发生变化\n") .. current.wav)
            end

            for _, entry in ipairs(plan.entries) do
                verify_origin(plan.origin)
                local current = wwise.sources({entry.source.id})[entry.source.id:lower()]
                assert(current and same_target(entry.source, current), t("Wwise 音源目标发生变化\n") .. entry.source.path)
                assert(files.equal(current.wav, entry.backup), t("Originals 文件已变化\n") .. current.wav)
                samples.verify(entry)
                local results = wwise.update_source(entry.source, entry.replacement)
                local verified = false
                for _, row in ipairs(results) do
                    if row.id:lower() == current.id:lower() and files.key(row.wav) == files.key(current.wav) then
                        verified = true
                    end
                end
                assert(verified and files.equal(current.wav, entry.replacement), t("Wwise 未确认原音源的更新\n") .. current.wav)
                completed = completed + 1
                if entry.sample then
                    samples.publish(entry)
                    mirrored = mirrored + 1
                end
            end
        end)
    end)

    if plan.region_draft and completed > 0 then
        local renamed, rename_error = pcall(project.rename_regions, plan.current, plan.entries, completed)
        if not renamed then
            problem = ok and rename_error or (tostring(problem) .. "\n" .. tostring(rename_error))
            ok = false
        end
    end

    if not ok then
        local summary = (t("已核验 %d / %d 个更新。")):format(completed, #plan.entries)
        if plan.sample_directory then summary = summary .. (t(" Samples 已同步 %d 个。")):format(mirrored) end
        error(summary .. "\n" .. tostring(problem) .. t("\n暂存与备份目录\n") .. directory, 0)
    end
    return {count = completed, mirrored = mirrored, directory = directory, sample_directory = plan.sample_directory}
end

function workflow.update(preview)
    assert(reaper.EnumProjects(-1, "") == preview.current, t("REAPER 已切换工程，请重新预览。"))
    verify_sample_directory(preview)
    local plan = make_plan(preview.current, preview.port, preview.mode, preview.sample_directory)
    check_preview(preview, plan)
    return publish_existing(plan)
end

local function selected_wav_sources(origin, cache)
    local selected_files = wwise.selected_files()
    if #selected_files == 0 then return wwise.selected_sources() end

    local prefix = files.key(origin.originals) .. "/"
    local wanted, ids, seen = {}, {}, {}
    for _, path in ipairs(selected_files) do
        local key = files.key(path)
        if key:sub(1, #prefix) == prefix and key:match("%.wav$") and not wanted[key] then
            wanted[key] = true
            local relative = path:sub(#prefix + 1):gsub("/", "\\")
            for _, use in ipairs(wwise.file_usage(relative, cache)) do
                if not seen[use.id:lower()] then
                    ids[#ids + 1] = use.id
                    seen[use.id:lower()] = true
                end
            end
        end
    end
    local sources = {}
    for _, source in pairs(wwise.sources(ids)) do
        if wanted[files.key(source.wav)] then sources[#sources + 1] = source end
    end
    return sources
end

local function read_region_transfer(current, port, regions, expected_origin)
    return wwise.session(port, function()
        local origin = expected_origin and verify_origin(expected_origin) or wwise.project()
        local usage_cache, seen, targets, by_id = {}, {}, {}, {}
        local sources = selected_wav_sources(origin, usage_cache)
        table.sort(sources, function(a, b)
            if a.path ~= b.path then return a.path < b.path end
            return a.id < b.id
        end)
        for _, source in ipairs(sources) do
            local key = files.key(source.wav)
            if key:match("%.wav$") and source.relative ~= "" and not seen[key] then
                local usage, usage_key = prepare_target(origin, source, wwise.file_usage(source.relative, usage_cache))
                local target = {source = source, name = files.name(source.wav), usage = usage, usage_key = usage_key}
                targets[#targets + 1], by_id[source.id], seen[key] = target, target, true
            end
        end
        assert(#targets > 0, t("请在 Wwise 中选择工程已引用的 WAV 或对应的 Sound。"))
        return {current = current, port = port, origin = origin, regions = regions, targets = targets, by_id = by_id}
    end)
end

function workflow.read_region_transfer(current, port)
    local regions = project.selection(current, "regions")
    if #regions > 0 then return read_region_transfer(current, port, regions) end
end

local function wav_stem(name)
    return name:lower():gsub("%.wav$", "")
end

function workflow.match_regions(draft)
    local regions, wavs, links = {}, {}, {}
    for _, region in ipairs(draft.regions) do
        local key = wav_stem(region.name)
        if region.can_render and key ~= "" then regions[key] = regions[key] == nil and region.id end
    end
    for _, target in ipairs(draft.targets) do
        local key = wav_stem(target.name)
        wavs[key] = wavs[key] == nil and target.source.id
    end
    for name, id in pairs(regions) do
        if id and wavs[name] then links[id] = wavs[name] end
    end
    return links
end

function workflow.preview_region_transfer(draft, links, sample_directory)
    local invalid = t("区间和 Wwise WAV 必须一对一连接。请检查连线。")
    assert(type(links) == "table", invalid)
    local entries, seen, validated = {}, {}, {}
    for _, region in ipairs(draft.regions) do
        local id = links[region.id]
        if id ~= nil then
            local target = draft.by_id[id]
            assert(target and not seen[id], invalid)
            assert(region.can_render, t("选中内容无法渲染\n") .. region.name)
            entries[#entries + 1] = existing_entry(region, target.source, target.usage, target.usage_key)
            validated[region.id], seen[id] = id, true
        end
    end
    for region in pairs(links) do assert(validated[region], invalid) end
    samples.plan(entries, sample_directory)
    return {current = draft.current, port = draft.port, mode = "regions", origin = draft.origin, entries = entries,
        sample_directory = sample_directory, region_draft = draft, links = validated}
end

local function refresh_region_plan(preview)
    local before = preview.region_draft
    local actual = project.selection(preview.current, "regions")
    local original = {}
    for _, region in ipairs(before.regions) do original[region.id] = region end
    assert(#actual == #before.regions, t("REAPER 选择发生变化，请重新预览。"))
    for _, region in ipairs(actual) do
        local previous = original[region.id]
        assert(previous and region.name == previous.name and region.first == previous.first and region.last == previous.last,
            t("REAPER 区间选择、名称或范围已变化，请重新预览。"))
    end

    local refreshed = read_region_transfer(preview.current, preview.port, actual, before.origin)
    assert(#refreshed.targets == #before.targets, t("Wwise 选中的 WAV 已变化，请重新预览。"))
    for _, target in ipairs(before.targets) do
        assert(refreshed.by_id[target.source.id], t("Wwise 选中的 WAV 已变化，请重新预览。"))
    end

    local plan = workflow.preview_region_transfer(refreshed, preview.links, preview.sample_directory)
    check_preview(preview, plan)
    return plan
end

local container_types = {
    WorkUnit = true, Folder = true, ActorMixer = true, PropertyContainer = true,
    RandomSequenceContainer = true, SwitchContainer = true, BlendContainer = true,
}

local function transfer_destination(mode)
    local selected = wwise.selected_objects()
    assert(#selected > 0, t("请先在 Wwise 中选择音源、Sound 或容器。"))
    local cache, target = {}, nil
    local function get(id)
        local key = id:lower()
        if id == "" then return end
        if cache[key] == nil then cache[key] = wwise.objects({id})[key] end
        return cache[key]
    end

    for _, entry in ipairs(selected) do
        local object = assert(get(entry.id), t("读不到 Wwise 选中对象，请重新选择。"))
        if object.type == "AudioFileSource" then object = assert(get(object.parent), t("找不到 Wwise 音源的父对象。")) end
        if object.type == "Sound" then object = assert(get(object.parent), t("找不到 Sound 所在的容器。")) end
        if mode == "parent" then object = assert(get(object.parent), t("选中位置没有上一级导入容器。")) end
        assert(container_types[object.type] and (object.path:find("\\Containers\\", 1, true) == 1
            or object.path:find("\\Actor-Mixer Hierarchy\\", 1, true) == 1),
            t("选中位置无法直接导入 Sound\n") .. object.path)
        assert(not target or target.id:lower() == object.id:lower(), t("Wwise 选中对象指向多个容器，请选择同一容器内的对象。"))
        target = object
    end

    local location
    for _, source in ipairs(wwise.selected_sources(selected)) do
        if source.relative ~= "" and source.language ~= "" then
            local candidate = source_location(source)
            if mode == "parent" then candidate.subfolder = files.directory(candidate.subfolder) or "" end
            assert(not location or (location.language == candidate.language
                and files.key(location.subfolder) == files.key(candidate.subfolder)),
                t("Wwise 选中对象包含多个 Originals 目录，请选择一个具体音源作为参照。"))
            location = candidate
        end
    end
    return target, location or {language = "SFX", root = "SFX", subfolder = ""}
end

function workflow.originals_directory(location)
    return location.root .. (location.subfolder == "" and "" or "\\" .. location.subfolder)
end

local function transfer_entries(origin, target, location, paths, sample_directory)
    local entries, seen, children, sounds = {}, {}, {}, {}
    for _, object in ipairs(wwise.children(target.id)) do
        children[object.name:lower()] = object
        if object.type == "Sound" then sounds[object.id:lower()] = true end
    end

    for _, path in ipairs(paths) do
        local filename = files.name(path)
        local stem = filename:sub(1, -5)
        assert(stem ~= "" and not stem:find("[<>]"), t("渲染名不能作为 Wwise Sound 名称\n") .. filename)
        assert(not seen[filename:lower()], t("多个渲染文件同名\n") .. filename)
        seen[filename:lower()] = true

        local relative = workflow.originals_directory(location) .. "\\" .. filename
        local original = files.join(origin.originals, relative)
        local original_exists = reaper.file_exists(original)
        local named = children[stem:lower()]
        local existing, usage, usage_key
        if named or original_exists then
            usage = wwise.file_usage(relative)
            local ids = {}
            for _, use in ipairs(usage) do ids[#ids + 1] = use.id end
            for _, source in pairs(wwise.sources(ids)) do
                if sounds[source.parent:lower()] and (not named or source.parent:lower() == named.id:lower())
                    and files.key(source.wav) == files.key(original) and source.language == location.language then
                    assert(not existing, t("有多个 Wwise 音源能匹配同一个 Originals 文件，请先绑定指定音源\n") .. relative)
                    existing = source
                end
            end
            assert(existing, t("Wwise 有同名对象或 WAV，无法确定要替换的源\n") .. relative)
            usage, usage_key = prepare_target(origin, existing, usage)
        end

        entries[#entries + 1] = {name = stem, replacement = path, existing = existing ~= nil,
            source = existing or {wav = original, relative = relative}, usage = usage or {}, usage_key = usage_key,
            original_exists = original_exists}
    end
    samples.plan(entries, sample_directory)
    return entries
end

local function make_transfer_plan(current, port, mode, sample_directory, directory)
    local stage = files.join(directory, "Render")
    local paths = project.transfer_render(current, stage)
    return wwise.session(port, function()
        local origin = wwise.project()
        local target, location = transfer_destination(mode)
        return {current = current, port = port, mode = mode, sample_directory = sample_directory,
            directory = directory, stage = stage, paths = paths, origin = origin, target = target, location = location,
            entries = transfer_entries(origin, target, location, paths, sample_directory)}
    end)
end

function workflow.preview_transfer(current, port, mode, sample_directory)
    return make_transfer_plan(current, port, mode, sample_directory, project.directory(current, "Transfers"))
end

local function check_transfer_entries(before, after)
    assert(#before == #after, t("REAPER 渲染目标发生变化，请重新预览。"))
    for index, entry in ipairs(before) do
        local actual = after[index]
        assert(files.key(entry.replacement) == files.key(actual.replacement), t("REAPER 渲染文件名发生变化，请重新预览。"))
        assert(entry.existing == actual.existing and entry.original_exists == actual.original_exists
            and files.key(entry.source.wav) == files.key(actual.source.wav)
            and (not entry.existing or (same_target(entry.source, actual.source) and entry.usage_key == actual.usage_key)),
            t("Wwise 传输目标或 Originals 文件状态发生变化，请重新预览。"))
        assert(samples.same(entry.sample, actual.sample), t("Samples 目录或同名文件状态发生变化，请重新预览。"))
    end
end

local function verify_original(entry)
    if entry.original_exists then
        assert(files.equal(entry.source.wav, entry.backup), t("Originals 文件已变化\n") .. entry.source.wav)
    else
        assert(not reaper.file_exists(entry.source.wav), t("Originals 中已新增同名文件\n") .. entry.source.wav)
    end
end

function workflow.transfer(preview)
    assert(reaper.EnumProjects(-1, "") == preview.current, t("REAPER 已切换工程，请重新预览。"))
    verify_sample_directory(preview)
    if preview.region_draft then
        return publish_existing(refresh_region_plan(preview))
    end
    assert(#project.selection(preview.current, "regions") == 0, t("REAPER 选择发生变化，请重新预览。"))
    local plan = make_transfer_plan(preview.current, preview.port, preview.mode, preview.sample_directory, preview.directory)
    assert(same_origin(preview.origin, plan.origin) and preview.target.id:lower() == plan.target.id:lower()
        and preview.target.path == plan.target.path and preview.location.language == plan.location.language
        and files.key(workflow.originals_directory(preview.location)) == files.key(workflow.originals_directory(plan.location)),
        t("Wwise 的选中位置已变化，请重新预览。"))
    check_transfer_entries(preview.entries, plan.entries)

    local completed, mirrored = 0, 0
    local ok, problem = pcall(function()
        for index, entry in ipairs(plan.entries) do
            if entry.original_exists then
                local directory = files.join(plan.directory, "Backup/" .. index)
                reaper.RecursiveCreateDirectory(directory, 0)
                entry.backup = files.join(directory, files.name(entry.source.wav))
                files.copy(entry.source.wav, entry.backup)
            end
            samples.backup(entry, plan.directory, index)
        end

        project.transfer_render(plan.current, plan.stage, plan.paths)

        wwise.session(plan.port, function()
            local origin = verify_origin(plan.origin)
            local target = wwise.objects({plan.target.id})[plan.target.id:lower()]
            assert(target and target.path == plan.target.path and target.type == plan.target.type, t("Wwise 目标容器已变化。"))
            local actual = transfer_entries(origin, target, plan.location, plan.paths, plan.sample_directory)
            check_transfer_entries(plan.entries, actual)
            for _, entry in ipairs(plan.entries) do verify_original(entry) end

            for _, entry in ipairs(plan.entries) do
                verify_origin(plan.origin)
                verify_original(entry)
                samples.verify(entry)
                local results, parent
                if entry.existing then
                    local source = wwise.sources({entry.source.id})[entry.source.id:lower()]
                    assert(source and same_target(source, entry.source), t("Wwise 音源目标已变化\n") .. entry.source.relative)
                    results = wwise.update_source(entry.source, entry.replacement)
                    parent = entry.source.parent
                else
                    results = wwise.create_sound(target.id, entry.name, plan.location.language, plan.location.subfolder, entry.replacement)
                    for _, row in ipairs(results) do
                        if row.type == "Sound" and row.parent:lower() == target.id:lower() then parent = row.id end
                    end
                end

                local verified = false
                for _, row in ipairs(results) do
                    if row.type == "AudioFileSource" and parent and row.parent:lower() == parent:lower()
                        and files.key(row.wav) == files.key(entry.source.wav)
                        and (not entry.existing or row.id:lower() == entry.source.id:lower()) then
                        verified = true
                    end
                end
                assert(verified and files.equal(entry.replacement, entry.source.wav), t("Wwise 未确认目标音源\n") .. entry.source.wav)
                completed = completed + 1
                if entry.sample then
                    samples.publish(entry)
                    mirrored = mirrored + 1
                end
            end
        end)
    end)

    if not ok then
        error((t("Wwise 已核验 %d / %d 个，Samples 已同步 %d 个。\n%s\n暂存与备份目录\n%s"))
            :format(completed, #plan.entries, mirrored, tostring(problem), plan.directory), 0)
    end
    return {count = completed, mirrored = mirrored, directory = plan.directory, sample_directory = plan.sample_directory}
end

return workflow
