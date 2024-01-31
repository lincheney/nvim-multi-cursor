# nvim-multi-cursor

Another multi-cursor plugin for neovim ...

In reality, this works more like a live macro replayer
(which is actually how it works;
the keystrokes recorded into a macro are played back at each "cursor" position in real time).

Why you don't really need multi-cursor:
* simple edits are usually faster with visual(-block) mode
* complex edits are easy to screw up
* vim substitution (`:s/`) + `set incsearch` handles a lot of the use cases where you think you need this
* same with dot-repeat maybe with `cgn`
* maybe you should just learn macros
* or use [live-command.nvim](https://github.com/smjonas/live-command.nvim)

What features (or lack thereof) this plugin has:
* no new modes. Existing vim modes *mostly* just work.
* no new mappings
    * there are [functions](#usage) to add cursors that *you* can assign to mappings though
* many things work
* [many things don't work](#caveats-and-things-that-dont-work-and-workarounds)

## Usage

There are no mappings provided;
however there is one ["main" entrypoint](API) to start using multiple cursors
and several "helpers" that emulate vim features.

All provided arguments should be 0-indexed (i.e. line/column numbers start at 0).

### Example mappings

Here are some example mappings you can use
```lua
local NMC = require('nvim-multi-cursor')

-- cursors on start of each selected line; similar to `:help v_b_I`
vim.keymap.set('x', 'I', NMC.visual_block_insert)

-- cursors on end of each selected line; similar to `:help v_b_A`
vim.keymap.set('x', 'A', function()
    vim.cmd[[normal! $]]
    NMC.visual_block_append()
end)

-- delete selected text and put cursors on each line in insert mode; similar to `:help v_b_c`
vim.keymap.set('x', 'C', NMC.visual_block_change)

-- replace all occurrences of the selected text in this file and put a cursor at each
vim.keymap.set('x', 'gr', function()
    vim.cmd[[normal! y]]
    local text = vim.fn.getreg('"')
    local regex = '\\V'..text:gsub('\\', '\\\\'):gsub('\n', '\\n')
    NMC.start_at_regex(regex, true)
end)

```

### API

* `require('nvim-multi-cursor').start(positions, anchors, options)`
    * this is the "main" entrypoint
    * `positions` is a list of cursor positions
    * `anchors` is an optional list of 2-tuples representing the anchor of a visual selection (where the cursor is on the other end)
        * use this if you are starting in visual mode
        * these are ignored if not in visual mode
        * if in visual mode and anchors are not provided, then each cursor gets a 1-char selection at the cursor position
    * `options` a table of options including:
        * `register` the register that will be used to record the macro (default `y`)
        * `on_leave` a function that will be called when multi cursor is stopped
* `require('nvim-multi-cursor').stop()`
    * deactivates multi cursor
* `require('nvim-multi-cursor').is_active()`
    * returns true if multi cursor is active
* `require('nvim-multi-cursor').visual_block_insert(options)`
    * emulates visual block insert (when you press `I` in visual block mode)
    * you can make a mapping like `vim.keymap.set('x', 'I', require('nvim-multi-cursor').visual_block_insert)`
    * multi cursor stops when insert mode stops
* `require('nvim-multi-cursor').visual_block_append(options)`
    * emulates visual block append (when you press `A` in visual block mode)
    * you can make a mapping like `vim.keymap.set('x', 'A', require('nvim-multi-cursor').visual_block_append)`
    * multi cursor stops when insert mode stops
* `require('nvim-multi-cursor').visual_block_change(options)`
    * emulates visual block change (when you press `c` in visual block mode)
    * you can make a mapping like `vim.keymap.set('x', 'c', require('nvim-multi-cursor').visual_block_change)`
    * multi cursor stops when insert mode stops
* `require('nvim-multi-cursor').start_on_visual(options)`
    * place a cursor on each line in the visual selection
* `require('nvim-multi-cursor').start_at_regex(regex, replace, range, options)`
    * place visual selections where `regex` matches (similar-ish to `:s/`)
    * `regex` the vim regex
    * `replace` set to true to delete the matching text and enter insert mode (as if pressing `c`)
        * multi cursor stops when insert mode stops
    * `range` 2-tuple of a line range to search for matches, otherwise search the whole file
        * these are *1-indexed*

Additionally, there is a `:NvimMultiCursorRegex[!] REGEX` command
* this just calls `require('nvim-multi-cursor').start_at_regex(...)`
* but a live preview is shown of where the regex matches as you type it on the command line
* the bang `!` sets `replace` to true (i.e. it will delete the matching text and enter insert mode)

### Highlights

The following highlight groups can be configured:
* `NvimMultiCursor` the additional cursors. The default is a white underline.
* `NvimMultiCursorVisual` the additional visual ranges. The default is same as `Visual`

## Caveats and things that don't work and workarounds

* mappings/commands that are stateful or contextual or asynchronous
* anything that does not behave well with macros
* anything that relies on asynchronous execution, for example:
    * `vim.schedule()`
    * `feedkeys()`
        * note that `feedkeys("...", "t")` *does* work
* anything that makes and edits and then immediately switches buffer/window
* jumplist, changelist etc will not work well
* undo "works" most of the time, but occasionally it will not
    * there may be more undo breaks/states than expected
    * will not work if you have a mapping that does undo/redo *and* other changes
* pasting works most of the time
    * except maybe inside mappings
* backspacing in replace-mode, and similar, does not work
* autoindent in insert mode does not work
* only the following marks are supported, others will not work well
    * `<`, `>`, `[`, `]`
* anything about "previously inserted" text probably doesn't work
    * e.g. `<c-a>` to `Insert previously inserted text.`
* dot repeat somewhat works
    * you *must* have https://github.com/tpope/vim-repeat
    * but there's probably some broken stuff somewhere
* completion should work most of the time
    * [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) should work most of the time
        * `nvim-cmp` is disabled by default when recording macros, you have to enable it:
            ```lua
            require('cmp').setup{
                enabled = function()
                    local mc = require('nvim-multi-cursor')
                    local disabled = false
                    disabled = disabled or (vim.api.nvim_buf_get_option(0, 'buftype') == 'prompt')
                    disabled = disabled or (vim.fn.reg_recording() ~= '' and not mc.is_active())
                    disabled = disabled or (vim.fn.reg_executing() ~= '' and not mc.is_active())
                    return not disabled
                end,
            }
            ```
        * snippets do not work
* [leap.nvim](https://github.com/ggandor/leap.nvim) should mostly work
    * same goes for [flit.nvim](https://github.com/ggandor/flit.nvim)
* [nvim-surround](https://github.com/kylechui/nvim-surround) mostly works
* probably other stuff
