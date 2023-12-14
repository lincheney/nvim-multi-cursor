local M = {}

local CONSTANTS = require('nvim-multi-cursor.constants')

local VISUALMODES = {['v']=true, ['V']=true, ['']=true}

function M.vim_escape(string)
    return vim.api.nvim_replace_termcodes(string, true, true, true)
end

function M.is_visual(mode)
    return VISUALMODES[mode]
end

function M.getcurpos()
    local pos = vim.fn.getcurpos()
    return {pos[2]-1, pos[3]-1}, pos[5]-1
end

function M.get_visual_range()
    local mode = vim.api.nvim_get_mode().mode
    if M.is_visual(mode) then
        local first = vim.fn.getpos('v')
        local last = vim.api.nvim_win_get_cursor(0)
        return {{first[2]-1, first[3]-1}, {last[1]-1, last[2]}}, mode
    end
end

function M.set_visual_range(first, last, mode)
    -- reselect the visual region
    vim.api.nvim_win_set_cursor(0, {first[1]+1, first[2]})
    if vim.api.nvim_get_mode().mode ~= 'v' then
        vim.cmd('normal! v')
    end
    vim.cmd('normal! o')
    vim.api.nvim_win_set_cursor(0, {last[1]+1, last[2]})
    -- change to the correct visual mode
    if mode and mode ~= 'v' then
        vim.cmd('normal! '..mode)
    end
end

function M.get_mark(id, details)
    return vim.api.nvim_buf_get_extmark_by_id(0, CONSTANTS.NAMESPACE, id, {details=details})
end

function M.create_mark(pos, highlight, id)
    local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, true)[1]

    local left = {pos[1], pos[2]}
    -- if right is not given, use same as left
    local right = pos[3] and pos[4] and {pos[3], pos[4]}

    local reverse = right and vim.version.cmp(left, right) > 0
    if reverse then
        left, right = right, left
    end
    right = right or {pos[1], pos[2]-1}

    return vim.api.nvim_buf_set_extmark(
        0, CONSTANTS.NAMESPACE,
        left[1], math.min(left[2], #line),
        {
            id = id,
            hl_group = highlight,
            end_row = right[1],
            end_col = math.min(right[2]+1, #line),
            right_gravity = false,
            end_right_gravity = true,
        }
    ), reverse
end

function M.create_cursor_highlight_mark(pos, id)
    local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, true)[1]
    local past_end = pos[2] + 1 > #line

    return vim.api.nvim_buf_set_extmark(
        0, CONSTANTS.NAMESPACE,
        pos[1],
        past_end and pos[2] or math.min(pos[2], #line-1),
        {
            id = id,
            hl_group = CONSTANTS.CURSOR_HIGHLIGHT,
            end_row = pos[1],
            end_col = not past_end and pos[2]+1 or nil,
            virt_text = past_end and {{' ', CONSTANTS.CURSOR_HIGHLIGHT}} or nil,
            virt_text_pos = 'overlay',
            right_gravity = true,
            end_right_gravity = true,
        }
    )
end

function M.save_and_restore_cursor(callback)
    local pos = vim.fn.getcurpos()
    callback()
    vim.fn.setpos('.', pos)
end

function M.wait_for_normal_mode(callback)
    -- execute callback when switching to normal mode
    local autocmd
    autocmd = vim.api.nvim_create_autocmd('ModeChanged', {pattern='*:n', callback=function()
        -- wait til next cycle because we may be temporarily switching as part of a mapping
        vim.schedule(function()
            if vim.api.nvim_get_mode().mode == 'n' then
                vim.api.nvim_del_autocmd(autocmd)
                callback()
            end
        end)
    end})
end

return M
