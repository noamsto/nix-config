-- Shared catppuccin opts for the colorscheme spec and the dark/light switcher.
--
-- transparent_background is the ONLY thing that differs by mode: it looks good
-- in mocha (dark) but washes out latte (light) because the terminal background
-- bleeds through and surfaces/cursorline/floats lose contrast. So light mode
-- runs opaque (and uses solid floats for extra contrast).
--
-- catppuccin's setup() merges user_conf over its *defaults* (not the previous
-- setup), so the dark/light switcher must pass the FULL opts on every re-setup
-- or it silently resets term_colors/show_end_of_buffer. Hence this one source.
local M = {}

function M.opts(transparent)
  return {
    transparent_background = transparent,
    float = {
      transparent = transparent,
      solid = not transparent,
    },
    show_end_of_buffer = false,
    term_colors = true,
  }
end

return M
