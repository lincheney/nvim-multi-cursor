local M = {}

local NAME = 'multiple-cursors'

function M.start(...)
    return require(NAME..'.internal').start(...)
end

function M.stop(...)
    return require(NAME..'.internal').stop(...)
end

function M.is_active(...)
    return require(NAME..'.internal').is_active(...)
end

local function get_visual_block_ranges()
    local utils = require(NAME..'.utils')
    local range, mode = utils.get_visual_range()
    if not range then
        return
    end

    local first = math.min(range[1][1], range[2][1])
    local last = math.max(range[1][1], range[2][1])

    local first_col = math.min(range[1][2], range[2][2] - 1)
    local last_col = math.max(range[1][2], range[2][2] - 1)

    local positions = {}
    local visuals = {}
    local lines = vim.api.nvim_buf_get_lines(0, first, last+1, false)
    for i, line in ipairs(lines) do
        if first_col < #line then
            local col = math.min(last_col, #line - 1)
            if first_col == range[1][2] then
                table.insert(positions, {first+i-1, col})
                table.insert(visuals, {first+i-1, first_col, first+i-1, col + 1})
            else
                table.insert(positions, {first+i-1, first_col})
                table.insert(visuals, {first+i-1, col, first+i-1, first_col + 1})
            end
        end
    end

    return positions, visuals, visuals[range[2][1] == first and 1 or #visuals], mode
end

function M.start_on_visual_block(options)
    local positions, visuals, current, mode = get_visual_block_ranges()
    if positions then
        local utils = require(NAME..'.utils')
        utils.set_visual_range({current[1], current[2]}, {current[3], current[4]}, mode)
        return M.start(positions, visuals, options)
    end
end

function M.start_on_visual(options)
    local positions, visuals, current, mode = get_visual_block_ranges()
    if positions then
        vim.api.nvim_win_set_cursor(0, {current[3]+1, current[4]-1})
        return M.start(positions, nil, options)
    end
end

function M.visual_block_insert(options)
    if M.start_on_visual(options) then
        local utils = require(NAME..'.utils')
        vim.api.nvim_feedkeys(utils.vim_escape('<esc>i'), 't', true)
        utils.wait_for_normal_mode(M.stop)
    end
end

function M.visual_block_change(options)
    if M.start_on_visual_block(options) then
        local utils = require(NAME..'.utils')
        vim.api.nvim_feedkeys('c', 't', false)
        utils.wait_for_normal_mode(M.stop)
    end
end

function M.visual_block_append(options)
    local utils = require(NAME..'.utils')
    local constants = require(NAME..'.constants')

    local range = utils.get_visual_range()
    if not range then
        return
    end
    local pos, curswant = utils.getcurpos()
    local end_of_line = (curswant == constants.EOL)

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

    M.start(positions, nil, options)
    if end_of_line then
        vim.api.nvim_feedkeys(utils.vim_escape('<esc>A'), 't', true)
    else
        vim.api.nvim_feedkeys(utils.vim_escape('<esc>a'), 't', true)
    end
    utils.wait_for_normal_mode(M.stop)
end

function M.start_at_regex(regex, replace, range, options)
    local utils = require(NAME..'.utils')
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor[1] = cursor[1] - 1

    if regex ~= '' then
        vim.fn.setreg('/', regex)
    end
    -- get all substitute matches
    vim.g.multiple_cursors_positions = {}

    local cmd = 's//\\=len(add(g:multiple_cursors_positions, [getcurpos(), submatch(0, 1)]))/n'
    if range then
        cmd = range[1]..','..range[2]..cmd
    else
        cmd = '%'..cmd
    end

    if not pcall(function() vim.cmd(cmd) end) then
        return
    end
    vim.cmd[[nohlsearch]]

    local index = nil
    -- get all substitute matches
    local positions = {}
    local visuals = {}
    for i, value in ipairs(vim.g.multiple_cursors_positions) do
        local pos = value[1]
        local start = {pos[2]-1, pos[3]-1}
        local lines = value[2]
        local finish = {start[1] + #lines - 1, #lines == 1 and start[2]+#lines[1] or #lines[#lines]}

        table.insert(positions, {finish[1], finish[2]-1})
        table.insert(visuals, {start[1], start[2], finish[1], finish[2]})

        if vim.version.cmp(cursor, positions[i]) <= 0 and (not index or vim.version.cmp(positions[i], positions[index]) < 0) then
            index = i
        end
    end
    index = index or 1

    utils.set_visual_range(visuals[index], {positions[index][1], positions[index][2]+1}, 'v')
    M.start(positions, visuals, options)

    if replace then
        vim.api.nvim_feedkeys('c', 't', false)
        utils.wait_for_normal_mode(M.stop)
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


return M
