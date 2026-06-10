local wezterm = require("wezterm")

local function get_plugin_dir()
  for _, plugin in ipairs(wezterm.plugin.list()) do
    if plugin.component:find("widgets%.wez") then
      return plugin.plugin_dir
    end
  end
  return nil
end

local plugin_dir = get_plugin_dir()
if plugin_dir then
  package.path = plugin_dir .. "/plugin/?.lua;"
    .. plugin_dir .. "/plugin/systems/?.lua;"
    .. (package.path or "")
end

return require("systems.init")
