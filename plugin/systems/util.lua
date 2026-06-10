local wezterm = require("wezterm")

local M = {}

local _os = nil
M.os = function()
  if _os then
    return _os
  end
  local triple = wezterm.target_triple or ""
  if triple:match("apple") then
    _os = "macos"
  elseif triple:match("linux") then
    _os = "linux"
  elseif triple:match("windows") then
    _os = "windows"
  else
    _os = "unknown"
  end
  return _os
end

M.is_macos = function()
  return M.os() == "macos"
end

M.is_linux = function()
  return M.os() == "linux"
end

M.is_windows = function()
  return M.os() == "windows"
end

function M.run_command(args)
  local success, stdout, stderr = wezterm.run_child_process(args)
  return {
    success = success,
    stdout = stdout or "",
    stderr = stderr or "",
  }
end

function M.run_os_command(cmd_map)
  local os_name = M.os()
  local args = cmd_map[os_name]
  if not args then
    return nil
  end
  return M.run_command(args)
end

function M.parse_number(s)
  if s == nil then
    return nil
  end
  local n = tonumber(s)
  if n then
    return n
  end
  local match = s:match("([%d%.%-]+)")
  if match then
    return tonumber(match)
  end
  return nil
end

function M.format_byte_rate(bytes_per_sec)
  if not bytes_per_sec or bytes_per_sec < 0 then
    return "00 kB"
  end

  local units = { "kB", "MB", "GB", "TB" }
  local value = bytes_per_sec / 1024
  local unit_index = 1

  while value >= 99.5 and unit_index < #units do
    value = value / 1024
    unit_index = unit_index + 1
  end

  if value < 1 and unit_index > 1 then
    return (string.format("%.1f %s", value, units[unit_index]):gsub("^0", ""))
  end

  return string.format("%02d %s", math.floor(value + 0.5), units[unit_index])
end

function M.format_percent(value)
  if value == nil or value ~= value then
    return "--%"
  end
  local pct = math.floor(value + 0.5)
  if pct < 0 then
    pct = 0
  elseif pct > 100 then
    pct = 100
  end
  return string.format("%02d%%", pct)
end

function M.split_fields(line)
  local fields = {}
  for field in line:gmatch("%S+") do
    table.insert(fields, field)
  end
  return fields
end

function M.sample_valid(sample, interval_seconds)
  if not sample or not sample._ts then
    return false
  end
  return (os.time() - sample._ts) < interval_seconds
end

function M.widget_base(name, opts, defaults)
  local resolved = {}
  for k, v in pairs(defaults) do
    resolved[k] = v
  end
  if opts then
    for k, v in pairs(opts) do
      resolved[k] = v
    end
  end
  return {
    name = name,
    opts = resolved,
  }
end

function M.make_getter(w, fetch_fn, format_fn)
  local cached_value = nil
  local cached_time = 0

  local get_text = function()
    local now = os.time()
    if cached_value ~= nil and (now - cached_time) < w.opts.throttle then
      return cached_value
    end
    cached_value = fetch_fn()
    cached_time = now
    return cached_value
  end

  local get_formatted = function()
    local text = get_text()
    local icon = w.opts.icon
    local parts = {}
    if icon and icon ~= false then
      parts[1] = { Foreground = { Color = w.opts.color } }
      parts[2] = { Text = " " .. icon .. " " .. text .. " " }
    else
      parts[1] = { Foreground = { Color = w.opts.color } }
      parts[2] = { Text = " " .. text .. " " }
    end
    return parts
  end

  w.get_text = get_text
  w.get_formatted = get_formatted
  return w
end

return M
