local wezterm = require("wezterm")
local util = require("systems.util")

local M = {}

M.utilization = {}

function M.utilization.widget(opts)
  local w = util.widget_base("cpu.utilization", opts, {
    icon = wezterm.nerdfonts.md_memory,
    color = "#7dcfff",
    throttle = 3,
  })

  return util.make_getter(w, function()
    local result = util.run_os_command({
      -- macOS top's first sample can be an initialization sample; use the
      -- second CPU line so this tracks Activity Monitor's current usage.
      macos = { "top", "-l", "2", "-n", "0", "-s", "1" },
      linux = { "cat", "/proc/stat" },
      windows = {
        "powershell.exe",
        "-NoProfile",
        "-Command",
        "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average",
      },
    })

    if not result or not result.success then
      return "--%"
    end

    local stdout = result.stdout

    if util.is_macos() then
      local idle
      for line in stdout:gmatch("[^\r\n]+") do
        local match = line:match("CPU usage:.*,%s*([%d%.]+)%%%s+idle")
          or line:match("CPU usage:.*%s([%d%.]+)%%%s+idle")
        if match then
          idle = match
        end
      end
      if idle then
        return util.format_percent(100 - util.parse_number(idle))
      end
    elseif util.is_linux() then
      local line = stdout:match("^(cpu .-)$")
      if not line then
        return "--%"
      end
      local fields = util.split_fields(line)
      local idle = (tonumber(fields[5]) or 0) + (tonumber(fields[6]) or 0)
      local total = 0
      -- guest/guest_nice are already included in user/nice in /proc/stat.
      for i = 2, math.min(#fields, 9) do
        local v = tonumber(fields[i])
        if v then
          total = total + v
        end
      end
      local prev = wezterm.GLOBAL.widgets_cpu_sample
      if not prev then
        wezterm.GLOBAL.widgets_cpu_sample = { idle = idle, total = total, _ts = os.time() }
        return "--%"
      end
      local idle_delta = idle - prev.idle
      local total_delta = total - prev.total
      wezterm.GLOBAL.widgets_cpu_sample = { idle = idle, total = total, _ts = os.time() }
      if total_delta <= 0 then
        return "--%"
      end
      return util.format_percent(100 * (1 - idle_delta / total_delta))
    elseif util.is_windows() then
      local pct = util.parse_number(stdout)
      if pct then
        return util.format_percent(pct)
      end
    end

    return "--%"
  end)
end

return M
