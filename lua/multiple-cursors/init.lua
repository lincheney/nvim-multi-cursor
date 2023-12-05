local M = {}

local function UTILS() return require('multiple-cursors.utils') end
local function INTERNAL() return require('multiple-cursors.internal') end
local function CONSTANTS() return require('multiple-cursors.constants') end

function M.start(...)
    return INTERNAL().start(...)
end

function M.stop(...)
    return INTERNAL().stop(...)
end

function M.is_active(...)
    return INTERNAL().is_active(...)
end

local function get_visual_block_ranges()
    local range, mode = UTILS().get_visual_range()
    if not range then
        return
    end

    local first = math.min(range[1][1], range[2][1])
    local last = math.max(range[1][1], range[2][1])

    local first_col = math.min(range[1][2], range[2][2])
    local last_col = math.max(range[1][2], range[2][2])

    local cursors = {}
    local anchors = {}
    local lines = vim.api.nvim_buf_get_lines(0, first, last+1, false)
    for i, line in ipairs(lines) do
        if first_col == 0 then
            table.insert(cursors, {first+i-1, 0})
            table.insert(anchors, {first+i-1, 0})
        elseif first_col < #line then
            table.insert(cursors, {first+i-1, math.min(range[2][2], #line-1)})
            table.insert(anchors, {first+i-1, math.min(range[1][2], #line-1)})
        end
    end

    local i = range[2][1] == first and 1 or #anchors
    return cursors, anchors, {cursors[i], anchors[i]}, mode
end

function M.start_on_visual_block(options)
    local cursors, anchors, current, mode = get_visual_block_ranges()
    if cursors then
        UTILS().set_visual_range(current[1], current[2], mode)
        return M.start(cursors, anchors, options)
    end
end

function M.start_on_visual(options)
    local cursors, anchors, current, mode = get_visual_block_ranges()
    if cursors then
        vim.api.nvim_win_set_cursor(0, {current[1][1]+1, current[1][2]})
        return M.start(cursors, nil, options)
    end
end

function M.visual_block_insert(options)
    if M.start_on_visual(options) then
        vim.api.nvim_feedkeys(UTILS().vim_escape('<esc>i'), 't', true)
        UTILS().wait_for_normal_mode(M.stop)
    end
end

function M.visual_block_change(options)
    if M.start_on_visual_block(options) then
        vim.api.nvim_feedkeys('c', 't', false)
        UTILS().wait_for_normal_mode(M.stop)
    end
end

function M.visual_block_append(options)
    local range = UTILS().get_visual_range()
    if not range then
        return
    end
    local pos, curswant = UTILS().getcurpos()
    local end_of_line = (curswant == CONSTANTS().EOL)

    local cursors = {}
    local col = end_of_line and 0 or range[2][2] - 1
    local first = math.min(range[1][1], range[2][1])
    local last = math.max(range[1][1], range[2][1])

    local lines = vim.api.nvim_buf_get_lines(0, first, last+1, false)
    for i, line in ipairs(lines) do
        if #line <= col then
            -- add padding
            vim.api.nvim_buf_set_lines(0, first+i-1, first+i, true, {line..(' '):rep(col - #line + 1)})
        end
        table.insert(cursors, {first+i-1, col})
    end

    M.start(cursors, nil, options)
    if end_of_line then
        vim.api.nvim_feedkeys(UTILS().vim_escape('<esc>A'), 't', true)
    else
        vim.api.nvim_feedkeys(UTILS().vim_escape('<esc>a'), 't', true)
    end
    UTILS().wait_for_normal_mode(M.stop)
end

function M.start_at_regex(regex, replace, range, options)
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
    local cursors = {}
    local anchors = {}
    for i, value in ipairs(vim.g.multiple_cursors_positions) do
        local pos = value[1]
        local start = {pos[2]-1, pos[3]-1}
        local lines = value[2]
        local finish = {start[1] + #lines - 1, #lines == 1 and start[2]+#lines[1] or #lines[#lines]}

        table.insert(cursors, {finish[1], finish[2]-1})
        table.insert(anchors, {start[1], start[2]})

        if vim.version.cmp(cursor, cursors[i]) <= 0 and (not index or vim.version.cmp(cursors[i], cursors[index]) < 0) then
            index = i
        end
    end
    index = index or 1

    UTILS().set_visual_range(anchors[index], {cursors[index][1], cursors[index][2]}, 'v')
    M.start(cursors, anchors, options)

    if replace then
        vim.api.nvim_feedkeys('c', 't', false)
        UTILS().wait_for_normal_mode(M.stop)
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
