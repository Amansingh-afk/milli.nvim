# milli.nvim

Animated ASCII splash screens for Neovim. get a playable
splash you can wire into dashboard-nvim, alpha-nvim, mini.starter, or a
raw `VimEnter` autocmd.

Ships with a runtime + a set of bundled splashes.

![demo](demo.gif)

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
    local splash = require("milli").load({ splash = "finger" })
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
    require("milli").dashboard({ splash = "finger", loop = true })
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

## Snacks.nvim dashboard

```lua
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  dependencies = { "amansingh-afk/milli.nvim" },
  opts = function()
    local splash = require("milli").load({ splash = "fire" })
    return {
      dashboard = {
        enabled = true,
        sections = {
          { section = "header", text = table.concat(splash.frames[1], "\n") },
          { section = "keys",   gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    }
  end,
  config = function(_, opts)
    require("snacks").setup(opts)
    require("milli").snacks({ splash = "fire", loop = true })
  end,
}
```

## No dashboard plugin (raw VimEnter)

```lua
require("milli").vimenter({ splash = "fire", loop = true })
```

## Using your own splash (Coming soon)

## Previewing a splash

```
:MilliPreview <name>
```

Opens a scratch buffer, plays the splash in a loop. `q` or `<Esc>` dismisses.
Tab-completes against bundled splashes. Run `:MilliPreview` with no arg to
list what's available.

## Bundled splashes

| | | |
|---|---|---|
| **aiface** <br> ![](previews/aiface.gif) | **badge** <br> ![](previews/badge.gif) | **blackhole** <br> ![](previews/blackhole.gif) |
| **cactus** <br> ![](previews/cactus.gif) | **catwoman** <br> ![](previews/catwoman.gif) | **dancer** <br> ![](previews/dancer.gif) |
| **dancerramp** <br> ![](previews/dancerramp.gif) | **finger** <br> ![](previews/finger.gif) | **fire** <br> ![](previews/fire.gif) |
| **flyingcat** <br> ![](previews/flyingcat.gif) | **flyingdragon** <br> ![](previews/flyingdragon.gif) | **ididnot** <br> ![](previews/ididnot.gif) |
| **lighningtornado** <br> ![](previews/lighningtornado.gif) | **lights** <br> ![](previews/lights.gif) | **retrocircle** <br> ![](previews/retrocircle.gif) |
| **robot** <br> ![](previews/robot.gif) | **shader** <br> ![](previews/shader.gif) | **shadertwo** <br> ![](previews/shadertwo.gif) |
| **skullone** <br> ![](previews/skullone.gif) | **skulltwo** <br> ![](previews/skulltwo.gif) | **skullthree** <br> ![](previews/skullthree.gif) |
| **spinner** <br> ![](previews/spinner.gif) | **vibecat** <br> ![](previews/vibecat.gif) | **vibecattwo** <br> ![](previews/vibecattwo.gif) |

## API

```lua
require("milli").play(buf, opts)       -- paint/animate into buf
require("milli").load(opts)            -- just return the data table
require("milli").list()                -- array of bundled splash names

require("milli").dashboard(opts)       -- autocmd preset
require("milli").alpha(opts)
require("milli").starter(opts)
require("milli").snacks(opts)
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
