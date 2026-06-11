local wezterm = require("wezterm")
local util = require("systems.util")

local M = {}

M.utilization = {}

function M.utilization.widget(opts)
  local w = util.widget_base("ram.utilization", opts, {
    icon = wezterm.nerdfonts.md_chip,
    color = "#bb9af7",
    throttle = 3,
  })

  return util.make_getter(w, function()
    if util.is_macos() then
      return M._fetch_macos()
    elseif util.is_linux() then
      return M._fetch_linux()
    elseif util.is_windows() then
      return M._fetch_windows()
    end
    return "--%"
  end)
end

function M._fetch_macos()
  local memsize = util.run_command({ "sysctl", "-n", "hw.memsize" })
  if not memsize or not memsize.success then
    return "--%"
  end
  local total = util.parse_number(memsize.stdout)
  if not total then
    return "--%"
  end

  local vm = util.run_command({ "vm_stat" })
  if not vm or not vm.success then
    return "--%"
  end

  local page_size = 16384
  local ps_match = vm.stdout:match("page size of (%d+) bytes")
  if ps_match then
    page_size = tonumber(ps_match) or 16384
  end

  local pages = {}
  for line in vm.stdout:gmatch("[^\r\n]+") do
    local label, value = line:match('^"?([^":]+)"?:%s*(%d+)%.?$')
    if label and value then
      pages[label] = tonumber(value) or 0
    end
  end

  local free = pages["Pages free"] or 0
  local speculative = pages["Pages speculative"] or 0
  local file_backed = pages["File-backed pages"] or 0

  local reclaimable = (free + speculative + file_backed) * page_size
  local used = math.max(0, total - reclaimable)

  return util.format_percent((used / total) * 100)
end

function M._fetch_linux()
  local result = util.run_command({ "cat", "/proc/meminfo" })
  if not result or not result.success then
    return "--%"
  end

  local total = result.stdout:match("MemTotal:%s*(%d+)")
  local available = result.stdout:match("MemAvailable:%s*(%d+)")
  if not total or not available then
    return "--%"
  end

  total = tonumber(total) * 1024
  available = tonumber(available) * 1024

  return util.format_percent(((total - available) / total) * 100)
end

function M._fetch_windows()
  local result = util.run_command({
    "powershell.exe",
    "-NoProfile",
    "-Command",
    "$os = Get-CimInstance Win32_OperatingSystem; Write-Output ($os.TotalVisibleMemorySize); Write-Output ($os.FreePhysicalMemory)",
  })
  if not result or not result.success then
    return "--%"
  end

  local lines = {}
  for line in result.stdout:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local total = tonumber(lines[1])
  local free = tonumber(lines[2])
  if not total or not free or total == 0 then
    return "--%"
  end

  return util.format_percent(((total - free) / total) * 100)
end

return M
