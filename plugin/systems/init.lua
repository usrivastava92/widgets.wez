local wezterm = require("wezterm")

local sys = {}

sys.VERSION = "1.0.0"

sys.cpu = require("systems.cpu")
sys.ram = require("systems.ram")
sys.battery = require("systems.battery")
sys.network = require("systems.network")
sys.disk = require("systems.disk")

function sys.apply_to_config(config, opts)
  opts = opts or {}
  local left_widgets = opts.left or {}
  local right_widgets = opts.right or {}
  local separator = opts.separator or { text = "|", color = "#3b4261" }

  local function build_status(widgets)
    local items = {}
    for i, widget in ipairs(widgets) do
      if i > 1 and separator.text and #separator.text > 0 then
        table.insert(items, { Foreground = { Color = separator.color } })
        table.insert(items, { Text = separator.text })
      end
      local formatted = widget.get_formatted()
      for _, item in ipairs(formatted) do
        table.insert(items, item)
      end
    end
    return items
  end

  if #left_widgets > 0 and #right_widgets > 0 then
    wezterm.on("update-status", function(window, pane)
      window:set_left_status(wezterm.format(build_status(left_widgets)))
      window:set_right_status(wezterm.format(build_status(right_widgets)))
    end)
  elseif #left_widgets > 0 then
    wezterm.on("update-status", function(window, pane)
      window:set_left_status(wezterm.format(build_status(left_widgets)))
    end)
  elseif #right_widgets > 0 then
    wezterm.on("update-status", function(window, pane)
      window:set_right_status(wezterm.format(build_status(right_widgets)))
    end)
  end
end

return sys
