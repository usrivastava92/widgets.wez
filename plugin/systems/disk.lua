local wezterm = require("wezterm")
local util = require("systems.util")

local M = {}

M.space = {}

function M.space.widget(opts)
  local w = util.widget_base("disk.space", opts, {
    icon = wezterm.nerdfonts.md_harddisk,
    color = "#ff9e64",
    throttle = 30,
  })

  return util.make_getter(w, function()
    local result = util.run_os_command({
      macos = { "df", "-g", "/" },
      linux = { "df", "-h", "/" },
      windows = {
        "powershell.exe",
        "-NoProfile",
        "-Command",
        "$disk = Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\"; Write-Output ($disk.Size); Write-Output ($disk.FreeSpace)",
      },
    })

    if not result or not result.success then
      return "--%"
    end

    local stdout = result.stdout

    if util.is_macos() or util.is_linux() then
      local lines = {}
      for line in stdout:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      if #lines < 2 then
        return "--%"
      end
      local fields = util.split_fields(lines[2])
      local cap_field
      if util.is_macos() then
        cap_field = fields[#fields - 1]
      else
        cap_field = fields[#fields]
        if cap_field and not cap_field:match("%d") then
          cap_field = fields[#fields - 1]
        end
      end
      local pct = util.parse_number(cap_field)
      if pct then
        return util.format_percent(pct)
      end
    elseif util.is_windows() then
      local lines = {}
      for line in stdout:gmatch("[^\r\n]+") do
        if line:match("^%d") then
          table.insert(lines, line)
        end
      end
      local size = tonumber(lines[1])
      local free = tonumber(lines[2])
      if size and free and size > 0 then
        return util.format_percent(((size - free) / size) * 100)
      end
    end

    return "--%"
  end)
end

-- Disk I/O

local IO_SAMPLE_KEY = "widgets_disk_io_sample"
local IO_THROTTLE = 3

local function get_io_sample()
  local sample = wezterm.GLOBAL[IO_SAMPLE_KEY]
  if not sample then
    sample = { read_rate = 0, write_rate = 0, _ts = 0 }
    wezterm.GLOBAL[IO_SAMPLE_KEY] = sample
  end
  return sample
end

-- Fetch current disk I/O rates in bytes/sec.
-- Returns { read_rate, write_rate } or nil on failure.
-- macOS: iostat reports instantaneous rate, so we return it directly.
-- Linux/Windows: cumulative counters, so we compute delta from previous sample.
local function fetch_disk_io_rates()
  if util.is_macos() then
    local result = util.run_command({ "iostat", "-Id" })
    if result and result.success then
      local kb = result.stdout:match("(%d+%.?%d*)%s+KB/s")
      if kb then
        local rate = tonumber(kb) * 1024
        return rate, rate
      end
    end
    return nil

  elseif util.is_linux() then
    local root_dev = nil
    local mount = util.run_command({ "df", "/" })
    if mount and mount.success then
      local lines = {}
      for line in mount.stdout:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      if #lines >= 2 then
        local fields = util.split_fields(lines[2])
        root_dev = fields[1]
      end
    end

    if not root_dev then
      return nil
    end

    local device = root_dev:match("/dev/([%w]+)")
      or root_dev:match("/dev/mapper/([%w%-]+)")
      or (root_dev:match("([%w]+)p?%d+$"))
    if not device then
      return nil
    end

    local result = util.run_command({ "cat", "/proc/diskstats" })
    if not result or not result.success then
      return nil
    end

    local sectors_read, sectors_written
    for line in result.stdout:gmatch("[^\n]+") do
      local fields = util.split_fields(line)
      if #fields >= 14 and fields[3] == device then
        sectors_read = tonumber(fields[6])
        sectors_written = tonumber(fields[10])
        break
      end
    end

    if not sectors_read or not sectors_written then
      return nil
    end

    local read_bytes = sectors_read * 512
    local write_bytes = sectors_written * 512
    local now = os.time()

    local G_KEY = IO_SAMPLE_KEY .. "_linux_prev"
    local prev = wezterm.GLOBAL[G_KEY]
    local read_rate, write_rate

    if prev and prev.read_bytes and prev._ts then
      local elapsed = now - prev._ts
      if elapsed > 0 then
        local dr = read_bytes - prev.read_bytes
        local dw = write_bytes - prev.write_bytes
        if dr >= 0 and dw >= 0 then
          read_rate = dr / elapsed
          write_rate = dw / elapsed
        end
      end
    end

    wezterm.GLOBAL[G_KEY] = {
      read_bytes = read_bytes,
      write_bytes = write_bytes,
      _ts = now,
    }

    if not read_rate then
      return nil
    end

    return read_rate, write_rate

  elseif util.is_windows() then
    local result = util.run_command({
      "powershell.exe",
      "-NoProfile",
      "-Command",
      "$disk = Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter \"Name='_Total'\"; Write-Output ($disk.DiskReadBytesPersec); Write-Output ($disk.DiskWriteBytesPersec)",
    })
    if not result or not result.success then
      return nil
    end

    local lines = {}
    for line in result.stdout:gmatch("[^\r\n]+") do
      local n = tonumber(line)
      if n then
        table.insert(lines, n)
      end
    end
    if #lines < 2 then
      return nil
    end

    local cur_read = lines[1]
    local cur_write = lines[2]
    local now = os.time()

    local G_KEY = IO_SAMPLE_KEY .. "_win_prev"
    local prev = wezterm.GLOBAL[G_KEY]
    local read_rate, write_rate

    if prev and prev.read_bytes and prev._ts then
      local elapsed = now - prev._ts
      if elapsed > 0 then
        local dr = cur_read - prev.read_bytes
        local dw = cur_write - prev.write_bytes
        if dr >= 0 and dw >= 0 then
          read_rate = dr / elapsed
          write_rate = dw / elapsed
        end
      end
    end

    wezterm.GLOBAL[G_KEY] = {
      read_bytes = cur_read,
      write_bytes = cur_write,
      _ts = now,
    }

    if not read_rate then
      return nil
    end

    return read_rate, write_rate
  end

  return nil
end

local function refresh_io_sample()
  local sample = get_io_sample()
  local now = os.time()

  if util.sample_valid(sample, IO_THROTTLE) then
    return true
  end

  if sample._fetching then
    return true
  end

  sample._fetching = true
  local read_rate, write_rate = fetch_disk_io_rates()
  sample._fetching = false

  if not read_rate or not write_rate then
    sample._ts = 0
    return false
  end

  sample.read_rate = read_rate
  sample.write_rate = write_rate
  sample._ts = now
  return true
end

M.read = {}

function M.read.widget(opts)
  local w = util.widget_base("disk.read", opts, {
    icon = wezterm.nerdfonts.md_arrow_down_right,
    color = "#73daca",
    throttle = IO_THROTTLE,
  })

  return util.make_getter(w, function()
    refresh_io_sample()
    local sample = get_io_sample()
    return util.format_byte_rate(sample.read_rate)
  end)
end

M.write = {}

function M.write.widget(opts)
  local w = util.widget_base("disk.write", opts, {
    icon = wezterm.nerdfonts.md_arrow_up_right,
    color = "#ff9e64",
    throttle = IO_THROTTLE,
  })

  return util.make_getter(w, function()
    refresh_io_sample()
    local sample = get_io_sample()
    return util.format_byte_rate(sample.write_rate)
  end)
end

return M
