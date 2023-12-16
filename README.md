# nvim-multi-cursor

Another multi-cursor plugin for neovim ...

In reality, this works more like a live macro replayer
(which is actually how it works;
the keystrokes recorded into a macro are played back at each "cursor" position in real time).

Why you don't really need multi-cursor:
* simple edits are usually faster with visual(-block) mode
* complex edits are easy to screw up
* vim substitution (`:s/`) handles a lot of the use cases where you think you need this
* same with dot-repeat maybe with `cgn`
* maybe you should just learn macros

What features (or lack thereof) this plugin has:
* no new modes. Existing vim modes *mostly* just work.
* no new mappings
    * there are [functions](#usage) to add cursors that *you* can assign to mappings though
* many things work
* [many things don't work](#caveats-and-things-that-dont-work-and-workarounds)

## Usage

There are no mappings provided;
however there is one "main" entrypoint to start using multiple cursors
and several "helpers" that emulate vim features.

All provided arguments should be 0-indexed (i.e. line/column numbers start at 0).

* `require('nvim-multi-cursor').start(positions, anchors, options)`
    * this is the "main" entrypoint
    * `positions` is a list of cursor positions
    * `anchors` is an optional list of 2-tuples representing the anchor of a visual selection (where the cursor is on the other end)
        * use this if you are starting in visual mode
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
* anything that does not behave well with `silent!` (which ignores mapping errors)
* anything that relies on asynchronous execution, for example:
    * `vim.schedule()`
    * `feedkeys()`
        * note that `feedkeys("...", "t")` *does* work
* undo works "most of the time", but rarely it will not
* backspacing in replace-mode, and similar, does not work
* only the following marks are supported, others will not work well
    * `<`, `>`, `[`, `]`
* completion should work most of the time
    * `nvim-cmp` should work most of the time
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
* `leap.nvim` works sometimes, but mostly not so you should disable it while using multiple cursors
    * same goes for `flit.nvim`
    * TODO how to disable it temporarily?
* `nvim-surround` does not work in visual mode
* probably other stuff
