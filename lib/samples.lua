local files = ...
local samples = {}
local section, key = "PsyReaWwise", "SamplesFolder"

function samples.directory(project)
    local _, custom = reaper.GetProjExtState(project, section, key)
    if custom and custom ~= "" then return custom, true end
    local active, path = reaper.EnumProjects(-1, "")
    local folder = active == project and path and files.directory(path)
    if folder then return files.join(folder, "Samples"), false end
end

function samples.set_directory(project, path)
    reaper.SetProjExtState(project, section, key, path)
    reaper.MarkProjectDirty(project)
end

function samples.plan(entries, directory)
    if not directory then return end
    local seen, originals = {}, {}
    for _, entry in ipairs(entries) do originals[files.key(entry.source.wav)] = true end
    for _, entry in ipairs(entries) do
        local path = files.join(directory, files.name(entry.source.wav))
        local path_key = files.key(path)
        assert(not originals[path_key], "Samples 和 Wwise Originals 指向同一个文件\n" .. path)
        assert(not seen[path_key], "多个渲染目标在 Samples 中重名\n" .. path)
        seen[path_key] = true
        entry.sample = {path = path, exists = reaper.file_exists(path)}
    end
end

function samples.same(first, second)
    if not first or not second then return first == second end
    return files.key(first.path) == files.key(second.path) and first.exists == second.exists
end

function samples.backup(entry, directory, index)
    local sample = entry.sample
    if not sample then return end
    assert(reaper.file_exists(sample.path) == sample.exists, "Samples 文件状态发生变化，请重新预览\n" .. sample.path)
    if sample.exists then
        local folder = files.join(directory, "SamplesBackup/" .. index)
        reaper.RecursiveCreateDirectory(folder, 0)
        sample.backup = files.join(folder, files.name(sample.path))
        files.copy(sample.path, sample.backup)
    end
    reaper.RecursiveCreateDirectory(files.directory(sample.path), 0)
end

function samples.verify(entry)
    local sample = entry.sample
    if not sample then return end
    if sample.exists then
        assert(files.equal(sample.path, sample.backup), "Samples 文件在传输期间发生变化\n" .. sample.path)
    else
        assert(not reaper.file_exists(sample.path), "Samples 文件在传输期间新增\n" .. sample.path)
    end
end

function samples.publish(entry)
    local sample = entry.sample
    if not sample then return end
    samples.verify(entry)
    files.publish(entry.replacement, sample.path, sample.exists)
    assert(files.equal(entry.replacement, sample.path), "Samples 的 WAV 校验失败\n" .. sample.path)
end

return samples
