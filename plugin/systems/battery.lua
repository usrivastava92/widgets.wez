local wezterm = require("wezterm")
local util = require("systems.util")

local M = {}

M.charge = {}

function M.charge.widget(opts)
  local w = util.widget_base("battery.charge", opts, {
    icon = wezterm.nerdfonts.md_battery,
    color = "#9ece6a",
    throttle = 5,
  })

  return util.make_getter(w, function()
    local ok, battery = pcall(wezterm.battery_info)
    if not ok or not battery or type(battery) ~= "table" or #battery == 0 then
      return "--%"
    end
    local info = battery[1]
    if not info or info.state_of_charge == nil then
      return "--%"
    end
    return util.format_percent(info.state_of_charge * 100)
  end)
end

return M
