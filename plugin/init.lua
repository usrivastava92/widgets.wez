local wezterm = require("wezterm")

-- Resolve plugin directory for module loading.
-- When loaded via wezterm.plugin.require (GitHub URL), this resolves the
-- installed plugin path. When loaded via dofile from a local dev config,
-- the caller should pre-configure package.path.
local function get_plugin_dir()
  local ok, debug = pcall(require, "debug")
  if not ok then
    return nil
  end
  local info = debug.getinfo(1, "S")
  local source = info.source
  return source:match("@(.*/)plugin/init%.lua$")
end

local plugin_dir = get_plugin_dir()
if plugin_dir then
  package.path = plugin_dir .. "?.lua;" .. plugin_dir .. "systems/?.lua;" .. (package.path or "")
end

return require("systems.init")
