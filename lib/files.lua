local t = ...
local files = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(bytes)
    local out = {}
    for index = 1, #bytes, 3 do
        local a, b, c = bytes:byte(index, index + 2)
        local number = a * 65536 + (b or 0) * 256 + (c or 0)
        local first = math.floor(number / 262144) + 1
        local second = math.floor(number / 4096) % 64 + 1
        local third = math.floor(number / 64) % 64 + 1
        local fourth = number % 64 + 1
        out[#out + 1] = alphabet:sub(first, first) .. alphabet:sub(second, second)
            .. (b and alphabet:sub(third, third) or "=") .. (c and alphabet:sub(fourth, fourth) or "=")
    end
    return table.concat(out)
end

function files.decode_base64(encoded)
    local output, value, bits = {}, 0, 0
    for character in encoded:gsub("%s", ""):gsub("=+$", ""):gmatch(".") do
        local digit = alphabet:find(character, 1, true)
        if not digit then return end
        value, bits = value * 64 + digit - 1, bits + 6
        if bits >= 8 then
            bits = bits - 8
            local remainder = 2 ^ bits
            output[#output + 1] = string.char(math.floor(value / remainder))
            value = value % remainder
        end
    end
    return table.concat(output)
end

local function windows_file_operation(command, first, second)
    local function literal(path)
        return "'" .. path:gsub("'", "''") .. "'"
    end

    local script = "$ErrorActionPreference='Stop'\n$a=" .. literal(first) .. "\n$b=" .. literal(second) .. "\n" .. command
    local characters = {}
    local function write_word(number)
        characters[#characters + 1] = string.char(number % 256, math.floor(number / 256))
    end
    for _, point in utf8.codes(script) do
        if point < 65536 then
            write_word(point)
        else
            local rest = point - 65536
            write_word(55296 + math.floor(rest / 1024))
            write_word(56320 + rest % 1024)
        end
    end
    local output = reaper.ExecProcess("powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand "
        .. base64(table.concat(characters)), 120000)
    local code = output and output:match("^(-?%d+)")
    return tonumber(code) == 0, output
end

local function needs_unicode_io(first, second)
    return first:find("[\128-\255]") or second:find("[\128-\255]")
end

function files.read_text(path)
    if needs_unicode_io(path, path) then
        local ok, output = windows_file_operation("[Convert]::ToBase64String([IO.File]::ReadAllBytes($a))", path, path)
        local encoded = ok and output:match("^0[\r\n]+([%w+/=]*)")
        if encoded then return files.decode_base64(encoded) end
        return nil, output
    end
    local stream, reason = io.open(path, "rb")
    if not stream then return nil, reason end
    local content = stream:read("*a")
    stream:close()
    return content
end

function files.join(base, name)
    return base:gsub("[\\/]+$", "") .. "/" .. name
end

function files.name(path)
    return path:match("([^\\/]+)$")
end

function files.directory(path)
    return path:match("^(.*)[\\/][^\\/]+$")
end

function files.key(path)
    return path:gsub("\\", "/"):gsub("/+$", ""):lower()
end

function files.copy(source, destination)
    if needs_unicode_io(source, destination) then
        local ok, reason = windows_file_operation("[IO.File]::Copy($a, $b, $false)", source, destination)
        assert(ok, t("无法复制 ") .. source .. "\n" .. tostring(reason))
        return
    end
    local input, reason = io.open(source, "rb")
    assert(input, t("无法读取 ") .. source .. "\n" .. tostring(reason))
    local output, open_error = io.open(destination, "wb")
    if not output then
        input:close()
        error(t("无法写入 ") .. destination .. "\n" .. tostring(open_error), 0)
    end

    local ok, copy_error = pcall(function()
        while true do
            local bytes, read_error = input:read(1024 * 1024)
            assert(not read_error, read_error)
            if not bytes then break end
            assert(output:write(bytes))
        end
    end)
    input:close()
    local closed, close_error = output:close()
    if not ok or not closed then
        os.remove(destination)
        error(t("复制失败 ") .. source .. "\n" .. tostring(copy_error or close_error), 0)
    end
end

local windows_hash = [[
function Read-Hash([string]$path) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($path)
        try { [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
    }
    finally { $hash.Dispose() }
}
]]

function files.equal(first_path, second_path)
    if needs_unicode_io(first_path, second_path) then
        return windows_file_operation(windows_hash .. [[
if ((Read-Hash $a) -cne (Read-Hash $b)) { exit 1 }
]], first_path, second_path)
    end
    local first = io.open(first_path, "rb")
    if not first then return false end
    local second = io.open(second_path, "rb")
    if not second then
        first:close()
        return false
    end

    local equal = true
    while true do
        local a, a_error = first:read(1024 * 1024)
        local b, b_error = second:read(1024 * 1024)
        if a_error or b_error or a ~= b then
            equal = false
            break
        end
        if not a then break end
    end
    first:close()
    second:close()
    return equal
end

local function publish_staged(source, destination, action)
    return windows_file_operation([[
$temp = [IO.Path]::Combine([IO.Path]::GetDirectoryName($b), '.psyreawwise-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::Copy($a, $temp, $false)
    ]] .. action .. [[

} finally {
    if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
}
]], source, destination)
end

function files.publish(source, destination, replace)
    local action = replace
        and "[IO.File]::Replace($temp, $b, [System.Management.Automation.Language.NullString]::Value)"
        or "[IO.File]::Move($temp, $b)"
    local ok, reason = publish_staged(source, destination, action)
    assert(ok, t("无法写入 Samples 文件\n") .. destination .. "\n" .. tostring(reason))
end

function files.install_runtime(source, destination)
    return publish_staged(source, destination, windows_hash .. [[
    $lockPath = Join-Path ([IO.Path]::GetDirectoryName($a)) 'runtime-lock.json'
    $lock = ConvertFrom-Json ([IO.File]::ReadAllText($lockPath))
    if ((Read-Hash $temp) -ine $lock.binary.sha256) { exit 2 }
    [IO.File]::Move($temp, $b)
]])
end

return files
