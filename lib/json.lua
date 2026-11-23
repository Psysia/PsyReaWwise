-- JSON codec adapted from the Psysia REAPER Tools Lua backend.
local json = {}

local function escape(value)
  return tostring(value or ""):gsub('[%z\1-\31\\"]', function(character)
    local escapes = {
      ['"'] = '\\"',
      ['\\'] = '\\\\',
      ['\b'] = '\\b',
      ['\f'] = '\\f',
      ['\n'] = '\\n',
      ['\r'] = '\\r',
      ['\t'] = '\\t',
    }
    return escapes[character]
      or string.format("\\u%04x", string.byte(character))
  end)
end

function json.encode(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode a non-finite JSON number")
    end
    return tostring(value)
  end
  if kind == "string" then return '"' .. escape(value) .. '"' end
  if kind ~= "table" then error("unsupported JSON value: " .. kind) end

  local maximum = 0
  local count = 0
  local array = true
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      array = false
      break
    end
    maximum = math.max(maximum, key)
  end
  if array and maximum == count then
    local output = {}
    for index = 1, maximum do
      output[index] = json.encode(value[index])
    end
    return "[" .. table.concat(output, ",") .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then error("JSON object keys must be strings") end
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local output = {}
  for _, key in ipairs(keys) do
    output[#output + 1] = json.encode(key)
      .. ":" .. json.encode(value[key])
  end
  return "{" .. table.concat(output, ",") .. "}"
end

-- Single-character escapes of a JSON string (shared, allocated once).
local unescape_map = {
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
  b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

function json.decode(text, preserve_container_kinds)
  text = tostring(text or "")
  local position = 1
  local length = #text
  if length > 8 * 1024 * 1024 then error("JSON document exceeds the size limit") end
  local depth = 0
  local array_meta = preserve_container_kinds and { __json_kind = "array" } or nil
  local unescape = unescape_map
  local function skip_space()
    -- Every JSON whitespace byte is <= 32, so anything above stops here.
    local current = text:byte(position)
    if not current or current > 32 then return end
    local _, last = text:find("^[ \t\r\n]*", position)
    position = (last or position - 1) + 1
  end
  local parse_value
  local function parse_string()
    if text:byte(position) ~= 34 then error("expected JSON string") end
    position = position + 1
    -- Plain runs are copied in bulk; only quotes, backslashes and control
    -- characters need individual handling.
    local output = nil
    local count = 0
    while true do
      local stop = text:find('["\\%z\1-\31]', position)
      if not stop then error("unterminated JSON string") end
      local character = text:byte(stop)
      if character == 34 then
        local segment = text:sub(position, stop - 1)
        position = stop + 1
        if not output then return segment end
        count = count + 1
        output[count] = segment
        return table.concat(output)
      elseif character ~= 92 then
        error("invalid JSON string character")
      end
      output = output or {}
      if stop > position then
        count = count + 1
        output[count] = text:sub(position, stop - 1)
      end
      position = stop
      local escape = text:sub(position + 1, position + 1)
      local mapped = unescape[escape]
      if mapped then
        count = count + 1
        output[count] = mapped
        position = position + 2
      elseif escape == "u" then
        local hex = text:sub(position + 2, position + 5)
        local code = tonumber(hex, 16)
        if not hex:match("^%x%x%x%x$") then error("invalid JSON unicode escape") end
        position = position + 6
        if code >= 0xd800 and code <= 0xdbff then
          if text:sub(position, position + 1) ~= "\\u" then
            error("incomplete JSON surrogate pair")
          end
          local low_hex = text:sub(position + 2, position + 5)
          local low = tonumber(low_hex, 16)
          if not low_hex:match("^%x%x%x%x$") or low < 0xdc00 or low > 0xdfff then
            error("invalid JSON surrogate pair")
          end
          code = 0x10000 + (code - 0xd800) * 0x400 + (low - 0xdc00)
          position = position + 6
        elseif code >= 0xdc00 and code <= 0xdfff then
          error("invalid JSON low surrogate")
        end
        count = count + 1
        output[count] = utf8.char(code)
      else
        error("invalid JSON escape")
      end
    end
  end
  local function parse_array()
    position = position + 1
    local output = array_meta and setmetatable({}, array_meta) or {}
    local count = 0
    skip_space()
    if text:byte(position) == 93 then position = position + 1 return output end
    while true do
      local value = parse_value()
      -- null elements are dropped, exactly like assigning nil at #output + 1
      if value ~= nil then
        count = count + 1
        output[count] = value
      end
      skip_space()
      local character = text:byte(position)
      if character == 93 then position = position + 1 return output end
      if character ~= 44 then error("expected JSON array separator") end
      position = position + 1
    end
  end
  local function parse_object()
    position = position + 1
    local output = {}
    local seen = {}
    if preserve_container_kinds then
      setmetatable(output, { __json_kind = "object", __json_members = seen })
    end
    skip_space()
    if text:byte(position) == 125 then position = position + 1 return output end
    while true do
      skip_space()
      local key = parse_string()
      if seen[key] then error("duplicate JSON property") end
      seen[key] = true
      skip_space()
      if text:byte(position) ~= 58 then error("expected JSON property separator") end
      position = position + 1
      output[key] = parse_value()
      skip_space()
      local character = text:byte(position)
      if character == 125 then position = position + 1 return output end
      if character ~= 44 then error("expected JSON object separator") end
      position = position + 1
    end
  end
  function parse_value()
    skip_space()
    local character = text:byte(position)
    if character == 34 then return parse_string() end
    if character == 91 or character == 123 then
      depth = depth + 1
      if depth > 64 then error("JSON nesting exceeds the depth limit") end
      local value = character == 91 and parse_array() or parse_object()
      depth = depth - 1
      return value
    end
    if character == 116 and text:sub(position, position + 3) == "true" then
      position = position + 4
      return true
    end
    if character == 102 and text:sub(position, position + 4) == "false" then
      position = position + 5
      return false
    end
    if character == 110 and text:sub(position, position + 3) == "null" then
      position = position + 4
      return nil
    end
    local first = position
    if character == 45 then position = position + 1 end
    local digit = text:byte(position)
    if digit == 48 then
      position = position + 1
      digit = text:byte(position)
      if digit and digit >= 48 and digit <= 57 then error("leading zero in JSON number") end
    elseif digit and digit >= 49 and digit <= 57 then
      local _, last = text:find("^%d+", position)
      position = last + 1
    else
      error("invalid JSON value")
    end
    if text:byte(position) == 46 then
      position = position + 1
      local _, last = text:find("^%d+", position)
      if not last then error("invalid JSON fraction") end
      position = last + 1
    end
    local exponent = text:byte(position)
    if exponent == 69 or exponent == 101 then
      position = position + 1
      local sign = text:byte(position)
      if sign == 43 or sign == 45 then position = position + 1 end
      local _, last = text:find("^%d+", position)
      if not last then error("invalid JSON exponent") end
      position = last + 1
    end
    local number = tonumber(text:sub(first, position - 1))
    if not number or number == math.huge or number == -math.huge then error("invalid JSON number") end
    return number
  end
  local value = parse_value()
  skip_space()
  if position <= length then error("trailing JSON data") end
  return value
end

return json
