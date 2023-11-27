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

return M
