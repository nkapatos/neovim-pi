--- Compatibility alias so `:checkhealth neovim-pi` resolves.
---
--- `:checkhealth {name}` maps the requested name to `lua/<name>/health.lua`,
--- while the plugin's Lua namespace is the short `pi`. The real check lives in
--- `lua/pi/health.lua`; this file only re-exports it. `:checkhealth pi` also
--- works.
return require("pi.health")
