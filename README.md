# milli.nvim

Animated ASCII splash screens for Neovim. Drop a GIF in, get a playable
splash you can wire into dashboard-nvim, alpha-nvim, mini.starter, or a
raw `VimEnter` autocmd.

Ships with a runtime + a set of bundled splashes. Generate your own from
any image or GIF with the [`milli`](https://github.com/amansingh-afk/milli)
CLI.

## Install

### lazy.nvim

```lua
{
  "amansingh-afk/milli.nvim",
  lazy = false,
}
```

### packer.nvim

```lua
use "amansingh-afk/milli.nvim"
```

## Quick start — bundled splash

```lua
-- plays on dashboard-nvim's dashboard buffer
require("milli").dashboard({ splash = "fire", loop = true })
```

List what's bundled:

```lua
:lua print(vim.inspect(require("milli").list()))
```

## Dashboard-nvim setup (end-to-end)

```lua
return {
  "nvimdev/dashboard-nvim",
  event = "VimEnter",
  dependencies = { "amansingh-afk/milli.nvim" },
  opts = function()
    local splash = require("milli").load({ splash = "fire" })
    return {
      theme = "doom",
      config = {
        header = splash.frames[1],         -- seed header with frame 0
        center = {
          { icon = "  ", desc = "Find File", key = "f", action = "Telescope find_files" },
          { icon = "  ", desc = "Quit",      key = "q", action = "qa" },
        },
      },
    }
  end,
  config = function(_, opts)
    require("dashboard").setup(opts)
    require("milli").dashboard({ splash = "fire", loop = true })
  end,
}
```

## Alpha-nvim

```lua
require("milli").alpha({ splash = "fire", loop = true })
```

## Mini.starter

```lua
require("milli").starter({ splash = "fire", loop = true })
```

## No dashboard plugin (raw VimEnter)

```lua
require("milli").vimenter({ splash = "fire", loop = true })
```

## Using your own splash

1. Export with the milli CLI:

   ```bash
   milli export -t lua --no-helper -m braille --no-bg -w 60 \
     my-source.gif /tmp/my_splash
   ```

   That writes `/tmp/my_splash/frames.lua`.

2. Drop it into the plugin, renamed to `<name>.lua`:

   ```bash
   cp /tmp/my_splash/frames.lua \
     ~/.local/share/nvim/lazy/milli.nvim/lua/milli/splashes/vision.lua
   ```

   Now referenceable as `{ splash = "vision" }`.

   (If you prefer not to modify the plugin, put the file somewhere on your
   `runtimepath` and use `{ module = "vision" }` instead of
   `{ splash = "vision" }`.)

## Previewing a splash

```
:MilliPreview <name>
```

Opens a scratch buffer, plays the splash in a loop. `q` or `<Esc>` dismisses.
Tab-completes against bundled splashes. Run `:MilliPreview` with no arg to
list what's available.

## API

```lua
require("milli").play(buf, opts)       -- paint/animate into buf
require("milli").load(opts)            -- just return the data table
require("milli").list()                -- array of bundled splash names

require("milli").dashboard(opts)       -- autocmd preset
require("milli").alpha(opts)
require("milli").starter(opts)
require("milli").vimenter(opts)
```

### `opts`

```lua
{
  splash = "fire",   -- bundled splash name, OR
  module = "mysplash", -- require path to an external splash module, OR
  data = { ... },    -- the data table directly
  loop = true,       -- repeat forever (default: false — play once)
}
```

A plain string is sugar for `{ splash = <string> }`. So
`require("milli").dashboard("fire")` works.

## Requirements

- Neovim 0.10+ (extmarks, namespaces)
- `termguicolors` enabled (`vim.opt.termguicolors = true`)

## Why extmarks and not ANSI escapes?

Neovim buffers strip ANSI. Colors are applied via extmarks + per-color
highlight groups generated on demand. The groups are keyed on quantized
fg/bg so a truecolor splash doesn't blow through Neovim's highlight-group
cap (E849).

## License

MIT.
