local wezterm = require("wezterm")
local util = require("systems.util")

local M = {}

local SAMPLE_KEY = "widgets_network_sample"
local THROTTLE_DEFAULT = 2

local function get_sample()
  local sample = wezterm.GLOBAL[SAMPLE_KEY]
  if not sample then
    sample = { rx_bytes = 0, tx_bytes = 0, _ts = 0, _iface = nil }
    wezterm.GLOBAL[SAMPLE_KEY] = sample
  end
  return sample
end

local function resolve_interface()
  local result
  if util.is_macos() then
    result = util.run_command({ "route", "-n", "get", "default" })
    if result and result.success then
      return result.stdout:match("interface: (%S+)")
    end
  elseif util.is_linux() then
    result = util.run_command({ "ip", "-4", "route", "show", "default" })
    if result and result.success then
      return result.stdout:match("dev (%S+)")
    end
  end
  return nil
end

local function fetch_netstats()
  local iface = nil
  if not util.is_windows() then
    iface = resolve_interface()
    if not iface then
      return nil
    end
  end

  local result
  if util.is_macos() then
    result = util.run_command({ "netstat", "-ibn" })
  elseif util.is_linux() then
    result = util.run_command({ "cat", "/proc/net/dev" })
  elseif util.is_windows() then
    result = util.run_command({ "netstat", "-e" })
  end

  if not result or not result.success then
    return nil
  end

  local stdout = result.stdout
  local rx_bytes, tx_bytes

  if util.is_macos() then
    -- netstat -ibn: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll Drop
    for line in stdout:gmatch("[^\n]+") do
      local name = line:match("^(%S+)")
      if name == iface then
        local fields = util.split_fields(line)
        if #fields >= 10 then
          rx_bytes = tonumber(fields[7])
          tx_bytes = tonumber(fields[10])
          break
        end
      end
    end
  elseif util.is_linux() then
    local escaped = iface:gsub("%-", "%%-")
    for line in stdout:gmatch("[^\n]+") do
      local name = line:match("^%s*(" .. escaped .. "):")
      if name then
        local fields = util.split_fields(line)
        if #fields >= 10 then
          rx_bytes = tonumber(fields[2])
          tx_bytes = tonumber(fields[10])
          break
        end
      end
    end
  elseif util.is_windows() then
    rx_bytes = tonumber(stdout:match("Bytes%s*\n%s*(%d+)"))
    local tx1 = stdout:match("Bytes%s*\n%s*%d+%s*\n%s*(%d+)")
    if tx1 then
      tx_bytes = tonumber(tx1)
    end
    if not rx_bytes or not tx_bytes then
      local rx_match = stdout:match("Received%s*\n%s*\n?%s*(%d+)")
      local tx_match = stdout:match("Sent%s*\n%s*\n?%s*(%d+)")
      rx_bytes = rx_match and tonumber(rx_match)
      tx_bytes = tx_match and tonumber(tx_match)
    end
  end

  if not rx_bytes or not tx_bytes then
    return nil
  end

  return { rx_bytes = rx_bytes, tx_bytes = tx_bytes, _iface = iface }
end

local function refresh_sample()
  local sample = get_sample()
  local now = os.time()

  if util.sample_valid(sample, THROTTLE_DEFAULT) then
    return true
  end

  if not util.is_windows() then
    local iface = resolve_interface()
    if sample._iface and iface and sample._iface ~= iface then
      sample.rx_bytes = 0
      sample.tx_bytes = 0
      sample._ts = 0
      sample._iface = nil
    end
  end

  if sample._fetching then
    return true
  end

  sample._fetching = true
  local stats = fetch_netstats()
  sample._fetching = false

  if not stats then
    sample._ts = 0
    return false
  end

  sample._prev_rx_bytes = sample.rx_bytes
  sample._prev_tx_bytes = sample.tx_bytes
  sample._prev_ts = sample._ts
  sample.rx_bytes = stats.rx_bytes
  sample.tx_bytes = stats.tx_bytes
  sample._fetch_time = now
  sample._ts = now
  sample._iface = stats._iface
  return true
end

local function get_rate(metric)
  refresh_sample()
  local sample = get_sample()

  local prev_key = "_prev_" .. metric
  local prev_val = sample[prev_key]
  local prev_ts = sample._prev_ts
  local cur_val = sample[metric]

  if not prev_val or not prev_ts or not cur_val then
    return nil
  end

  local elapsed = sample._fetch_time - prev_ts
  if elapsed <= 0 then
    return nil
  end

  local delta = cur_val - prev_val
  if delta < 0 then
    return nil
  end

  return delta / elapsed
end

M.download = {}

function M.download.widget(opts)
  local w = util.widget_base("network.download", opts, {
    icon = wezterm.nerdfonts.md_arrow_down,
    color = "#f7768e",
    throttle = THROTTLE_DEFAULT,
  })

  return util.make_getter(w, function()
    local rate = get_rate("rx_bytes")
    return util.format_byte_rate(rate)
  end)
end

M.upload = {}

function M.upload.widget(opts)
  local w = util.widget_base("network.upload", opts, {
    icon = wezterm.nerdfonts.md_arrow_up,
    color = "#e0af68",
    throttle = THROTTLE_DEFAULT,
  })

  return util.make_getter(w, function()
    local rate = get_rate("tx_bytes")
    return util.format_byte_rate(rate)
  end)
end

return M
