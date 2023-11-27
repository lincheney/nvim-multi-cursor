local M = {}

local NAME = 'multiple-cursors'

function M.start(...)
    return require(NAME..'.internal').start(...)
end

function M.stop(...)
    return require(NAME..'.internal').stop(...)
end

function M.visual_block_insert()
    local utils = require(NAME..'.utils')

    local range = utils.get_visual_range()
    local col = range[2][2] - 1
    local first = math.min(range[1][1], range[2][1])
    local last = math.max(range[1][1], range[2][1])
    local lines = vim.api.nvim_buf_get_lines(0, first, last+1, false)

    local positions = {}
    for i, line in ipairs(lines) do
        if #line > col then
            table.insert(positions, {first+i-1, col})
        end
    end

    M.start(positions)
    vim.api.nvim_feedkeys(utils.vim_escape('<esc>i'), 't', true)
    utils.wait_for_normal_mode(M.stop)
end

function M.visual_block_append()
    local utils = require(NAME..'.utils')

    local pos, curswant = utils.getcurpos()
    local end_of_line = (curswant == vim.v.maxcol - 1)
    local range = utils.get_visual_range()

    local positions = {}
    local col = range[2][2] - 1
    local first = math.min(range[1][1], range[2][1])
    local last = math.max(range[1][1], range[2][1])

    local lines = vim.api.nvim_buf_get_lines(0, first, last+1, false)
    for i, line in ipairs(lines) do
        if end_of_line then
            table.insert(positions, {first+i-1, 0})
        else
            if #line <= col then
                -- add padding
                vim.api.nvim_buf_set_lines(0, first+i-1, first+i, true, {line..(' '):rep(col - #line + 1)})
            end
            table.insert(positions, {first+i-1, col})
        end
    end

    M.start(positions)
    if end_of_line then
        vim.api.nvim_feedkeys(utils.vim_escape('<esc>A'), 't', true)
    else
        vim.api.nvim_feedkeys(utils.vim_escape('<esc>a'), 't', true)
    end
    utils.wait_for_normal_mode(M.stop)
end

function M.start_at_regex(regex, replace, range)
    local utils = require(NAME..'.utils')
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor[1] = cursor[1] - 1

    if regex ~= '' then
        vim.fn.setreg('/', regex)
    end
    -- get all substitute matches
    vim.g.multiple_cursors_positions = {}

    local cmd = 's//\\=len(add(g:multiple_cursors_positions, [getcurpos(), submatch(0, 1)]))'
    if range then
        cmd = range[1]..','..range[2]..cmd
    else
        cmd = '%'..cmd
    end

    if replace then
        vim.cmd(cmd..' ? "" : ""')
    else
        vim.cmd(cmd..'/n')
    end
    vim.cmd[[nohlsearch]]

    local index = 1
    -- get all substitute matches
    local positions = {}
    local visuals = {}
    for i, value in ipairs(vim.g.multiple_cursors_positions) do
        local pos = value[1]
        local start = {pos[2]-1, pos[3]-1}
        local lines = value[2]
        local finish = {start[1] + #lines - 1, #lines == 1 and start[2]+#lines[1] or #lines[#lines]}

        if replace then
            table.insert(positions, start)
        else
            table.insert(positions, {finish[1], finish[2]-1})
            table.insert(visuals, {start[1], start[2], finish[1], finish[2]})
        end

        if vim.version.cmp(start, cursor) <= 0 and vim.version.cmp(cursor, finish) < 0 then
            index = i
        end
    end

    if replace then
        vim.api.nvim_win_set_cursor(0, {cursor[1]+1, cursor[2]})
        M.start(positions)
        vim.cmd[[startinsert]]
        utils.wait_for_normal_mode(M.stop)
    else
        utils.set_visual_range(visuals[index], {positions[index][1], positions[index][2]+1}, 'v')
        M.start(positions, visuals)
    end
end

local last_pos = nil
vim.api.nvim_create_user_command(
    'MultipleCursorsRegex',
    function(opts)
        M.start_at_regex(opts.args, opts.bang, {opts.line1, opts.line2})
    end,
    {bang=true, nargs='?', range='%', addr='lines', preview = function(opts, preview_ns, preview_buf)
        if vim.o.incsearch then
            last_pos = last_pos or vim.api.nvim_win_get_cursor(0)
            vim.schedule(function()
                local regex = opts.args
                if opts.args == '' then
                    opts.args = vim.fn.getreg('/')
                end

                -- restore the cursor
                vim.fn.search(opts.args, 'cwz')
                vim.fn.setreg('/', opts.args)
                vim.o.hlsearch = true
                vim.cmd('redraw!')
                vim.api.nvim_win_set_cursor(0, last_pos)
            end)
        end
    end}
)


return M
