vim.api.nvim_set_hl(0, 'NvimMultiCursor', {default=true, underline=true, special='White'})
vim.api.nvim_set_hl(0, 'NvimMultiCursorVisual', {default=true, link='Visual'})

local last_pos = nil
vim.api.nvim_create_user_command(
    'NvimMultiCursorRegex',
    function(opts)
        require('nvim-multi-cursor').start_at_regex(opts.args, opts.bang, {opts.line1, opts.line2})
    end,
    {bang=true, nargs='?', range='%', addr='lines', preview = function(opts, preview_ns, preview_buf)
        if vim.o.incsearch then
            last_pos = last_pos or vim.api.nvim_win_get_cursor(0)
            vim.schedule(function()
                local regex = opts.args
                if regex == '' then
                    regex = vim.fn.getreg('/')
                end

                -- restore the cursor
                vim.fn.search(regex, 'cwz')
                vim.fn.setreg('/', regex)
                vim.o.hlsearch = true
                vim.cmd('redraw!')
                vim.api.nvim_win_set_cursor(0, last_pos)
            end)
        end
    end}
)
