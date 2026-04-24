# Splash data modules live here.

Each `*.lua` file in this directory returns a table with the shape:

```lua
return {
  cols = <n>,
  rows = <n>,
  delays = { <ms>, <ms>, ... },
  frames = {
    { "line1", "line2", ... },   -- frame 0
    { "line1", "line2", ... },   -- frame 1
    ...
  },
  colors = {                     -- optional
    { { {sb, eb, "#fg", "#bg"|"NONE"}, ... }, ... },   -- frame 0 row runs
    ...
  },
}
```

That is exactly the shape of `frames.lua` emitted by:

```bash
milli export -t lua --no-helper -m braille --no-bg -w 60 <src> /tmp/out
```

Drop the emitted `/tmp/out/frames.lua` into this directory, renaming to
`<name>.lua`. It becomes referenceable as `{ splash = "<name>" }`.
