local M = {}

local UTILS = require('multiple-cursors.utils')
local CONSTANTS = require('multiple-cursors.constants')
local REAL_CURSOR = require('multiple-cursors.real-cursor')
local CURSOR = require('multiple-cursors.cursor')

function M.make(buffer, positions, visuals, options)
    local self = {
        buffer = buffer,
        register = options.register,
        cursors = {},
        real_cursor = REAL_CURSOR.make(),
        done = false,
    }
    for i = 1, #positions do
        table.insert(self.cursors, CURSOR.make(positions[i], visuals and visuals[i], self.real_cursor.curswant))
    end
    M.save(self, vim.fn.undotree())
    return self
end

function M.remove(self)
    vim.api.nvim_buf_clear_namespace(self.buffer, CONSTANTS.NAMESPACE, 0, -1)
    if self.autocmd then
        vim.api.nvim_del_autocmd(self.autocmd)
    end
    self.done = true
end


function M.play_keys(self, keys, undojoin, new_mode)
    -- remove nop
    keys = keys:gsub(CONSTANTS.NOP, '')

    if self.mode == 'i' then
        keys = 'i' .. keys
    elseif self.mode == 'R' then
        keys = 'R' .. keys
    elseif keys:match('^%s') then
        -- can't start with space, so prefix with 1?
        keys = '1' .. keys
    end

    -- use a plug to get the self pos *before* we leave insert mode
    -- since exiting insert mode moves the cursor
    if new_mode == 'i' then
        keys = keys .. UTILS.vim_escape(CONSTANTS.RECORD_PLUG)
    end

    REAL_CURSOR.save_and_restore(self, function()

        -- make scratch window to apply our changes in
        local scratch = vim.api.nvim_open_win(0, false, {
            relative='editor',
            row=0,
            col=vim.o.columns,
            height=1,
            width=3,
            focusable=false,
            style='minimal',
            zindex=1,
        })
        vim.wo[scratch].winblend = 100

        local winhighlight = vim.wo.winhighlight
        vim.wo.winhighlight = 'NormalNC:Normal'

        -- visual range seems to be lost with nvim_win_call()
        local window = vim.api.nvim_get_current_win()
        vim.cmd('noautocmd call nvim_set_current_win('..scratch..')')

        for i, cursor in ipairs(self.cursors) do
            CURSOR.play_keys(cursor, keys, undojoin, self.mode, new_mode)
        end

        -- teardown
        vim.cmd('noautocmd call nvim_set_current_win('..window..')')
        vim.api.nvim_win_close(scratch, true)
        vim.wo.winhighlight = winhighlight

        -- reset to normal mode
        vim.cmd(UTILS.vim_escape('normal! <esc>'))

    end, mode)
end

function M.save(self, undotree)
    self.undo_seq = undotree.seq_cur
    self.changedtick = vim.b.changedtick
    self.mode = vim.api.nvim_get_mode().mode
    self.changes = nil

    local pos = vim.api.nvim_win_get_cursor(0)
    pos[1] = pos[1] - 1

    -- check for overlaps
    local marks = vim.tbl_map(function(c) return UTILS.get_mark(c.pos) end, self.cursors)
    for i = #self.cursors, 1, -1 do
        local overlap = false

        if marks[i][1] == pos[1] and marks[i][2] == pos[2] then
            overlap = true
        else
            for j = 1, i-1 do
                if marks[i][1] == marks[j][1] and marks[i][2] == marks[j][2] then
                    overlap = true
                    break
                end
            end
        end

        if overlap then
            CURSOR.remove(self.cursors[i])
            table.remove(self.cursors, i)
        end
    end

    REAL_CURSOR.save_undo_pos(self.real_cursor, undotree.seq_cur, pos)
    for i, cursor in ipairs(self.cursors) do
        CURSOR.save_undo_pos(cursor, undotree.seq_cur, marks[i])
    end
end

function M.restore_undo_pos(self, undo_seq)
    for i, cursor in ipairs(self.cursors) do
        CURSOR.restore_undo_pos(cursor, undo_seq, CONSTANTS.CHANGED_HIGHLIGHT)
    end
    local _, pos = REAL_CURSOR.restore_undo_pos(self.real_cursor, undo_seq)
    if pos then
        vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
    end
end

return M
