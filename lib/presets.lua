local files, t = ...
local presets = {}
local api = reaper

local postprocess = {
    "RENDER_NORMALIZE", "RENDER_NORMALIZE_TARGET", "RENDER_BRICKWALL", "RENDER_FADEIN", "RENDER_FADEOUT",
    "RENDER_FADEINSHAPE", "RENDER_FADEOUTSHAPE", "RENDER_TRIMSTART", "RENDER_TRIMEND", "RENDER_PADSTART", "RENDER_PADEND",
}
local modes = {[0] = "LUFS-I", "RMS", "Peak", "True Peak", "LUFS-M", "LUFS-S"}

local function fields(line)
    local values, index = {}, 1
    while index <= #line do
        local first = line:find("%S", index)
        if not first then break end
        local quote = line:sub(first, first)
        if quote == '"' or quote == "'" or quote == string.char(96) then
            local last = line:find(quote, first + 1, true)
            if not last then return {} end
            values[#values + 1], index = line:sub(first + 1, last - 1), last + 1
        else
            local last = line:find("%s", first) or #line + 1
            values[#values + 1], index = line:sub(first, last - 1), last + 1
        end
    end
    return values
end

local function get_preset(result, name)
    local setup = result[name]
    if not setup then
        setup = {name = name, numbers = {RENDER_NORMALIZE = 0}, config = {}, formats = {"", ""}, options = 0}
        result[name] = setup
    end
    return setup
end

local function read_formats(content, result)
    local block, sink
    for raw in content:gmatch("[^\r\n]+") do
        local line = raw:match("^%s*(.-)%s*$")
        if block then
            if line == ">" then
                block, sink = nil, nil
            else
                block.formats[sink] = block.formats[sink] .. line
            end
        else
            local row = fields(line)
            local kind, name = row[1], row[2]
            if name and kind == "<RENDERPRESET" then
                block, sink = get_preset(result, name), 1
                block.formats = {"", ""}
                local numbers = block.numbers
                numbers.RENDER_SRATE, numbers.RENDER_CHANNELS = tonumber(row[3]), tonumber(row[4])
                block.config = {projrenderlimit = tonumber(row[5]), projrenderrateinternal = tonumber(row[6]),
                    projrenderresample = tonumber(row[7])}
                numbers.RENDER_DITHER = tonumber(row[8])
                block.options = tonumber(row[9]) or 0
            elseif name and kind == "<RENDERPRESET2" then
                block, sink = get_preset(result, name), 2
                block.formats[2] = ""
            elseif name and kind == "RENDERPRESET_OUTPUT" then
                local setup = get_preset(result, name)
                setup.all = true
                setup.numbers.RENDER_TAILFLAG = tonumber(row[9]) == 1 and 255 or 0
                setup.numbers.RENDER_TAILMS = tonumber(row[11])
            elseif name and kind == "RENDERPRESET_EXT" then
                local setup = get_preset(result, name)
                for index, key in ipairs(postprocess) do setup.numbers[key] = tonumber(row[index + 2]) end
            end
        end
    end
end

local function read_metadata(content, result)
    local setup, record
    for raw in content:gmatch("[^\r\n]+") do
        local line = raw:match("^%s*(.-)%s*$")
        if record then
            if line == ">" then record = nil
            else record.value = record.value .. line end
        elseif line == ">" then
            setup = nil
        else
            local row = fields(line)
            if row[1] == "<RENDERPRESETMETADATA" and row[2] then
                setup = result[row[2]]
                if setup then setup.metadata = {} end
            elseif setup and row[2] and (row[1] == "TAG" or row[1] == "<TAG") then
                local tag = {key = row[2], value = row[3] or ""}
                setup.metadata[#setup.metadata + 1] = tag
                if row[1] == "<TAG" then record = tag end
            end
        end
    end
end

local function read_ini(filename)
    local path = files.join(api.GetResourcePath(), filename)
    if not api.file_exists(path) then return "" end
    local valid, reason = files.read_text(path)
    assert(valid, t("无法读取 REAPER 渲染预设\n") .. path .. "\n" .. tostring(reason))
    return valid:gsub("^\239\187\191", "")
end

local function db(ratio)
    if ratio and ratio > 0 then return math.floor(20 * math.log(ratio) / math.log(10) * 10 + 0.5) / 10 end
end

local function describe(setup)
    local numbers = setup.numbers
    local normalized = numbers.RENDER_NORMALIZE or 0
    local wav_count, depth = 0
    for _, format in ipairs(setup.formats) do
        local data = files.decode_base64(format)
        if data and data:sub(1, 4) == "evaw" then
            wav_count, depth = wav_count + 1, data:byte(5)
        end
    end
    local valid = wav_count == 1 and numbers.RENDER_SRATE and numbers.RENDER_SRATE >= 0
        and numbers.RENDER_CHANNELS and numbers.RENDER_CHANNELS > 0
    return {
        name = setup.name, valid = valid == true, bits = depth,
        rate = numbers.RENDER_SRATE, channels = numbers.RENDER_CHANNELS,
        normalization = normalized % 2 == 1 and (modes[math.floor(normalized / 2) % 8] or "LUFS-I"),
        target = db(numbers.RENDER_NORMALIZE_TARGET),
        limiter = math.floor(normalized / 64) % 4 ~= 0 and db(numbers.RENDER_BRICKWALL),
        tail = (numbers.RENDER_TAILFLAG or 0) ~= 0 and numbers.RENDER_TAILMS,
        fadeIn = math.floor(normalized / 512) % 2 == 1 and numbers.RENDER_FADEIN,
        fadeOut = math.floor(normalized / 1024) % 2 == 1 and numbers.RENDER_FADEOUT,
    }
end

function presets.read()
    local result = {}
    read_formats(read_ini("reaper-render.ini"), result)
    read_metadata(read_ini("reaper-render2.ini"), result)
    local listed = {}
    for _, setup in pairs(result) do
        if setup.all and setup.formats[1] ~= "" then
            setup.view = describe(setup)
            listed[#listed + 1] = setup.view
        end
    end
    table.sort(listed, function(first, second) return first.name:lower() < second.name:lower() end)
    return listed, result
end

function presets.resolve(name)
    if name == nil or name == "" then return end
    assert(type(name) == "string", t("无效的 REAPER 渲染预设。"))
    local _, by_name = presets.read()
    local setup = by_name[name]
    assert(setup and setup.view, t("REAPER 渲染预设已变化，请刷新预设列表。"))
    assert(setup.view.valid, t("用于回写的渲染预设需要且只能有一个 WAV 输出。"))
    return setup
end

return presets
