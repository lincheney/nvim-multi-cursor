local M = {}

local UTILS = require('nvim-multi-cursor.utils')
local CONSTANTS = require('nvim-multi-cursor.constants')
local REAL_CURSOR = require('nvim-multi-cursor.real-cursor')
local CURSOR = require('nvim-multi-cursor.cursor')

function M.make(buffer, cursors, anchors, options)
    local self = {
        buffer = buffer,
        register = options.register,
        cursors = {},
        real_cursor = REAL_CURSOR.make(),
        done = false,

        autoindent = vim.bo.autoindent,
        indentkeys = vim.bo.indentkeys,
    }

    -- https://github.com/neovim/neovim/issues/26326
    vim.bo.autoindent = false
    vim.bo.indentkeys = ''

    local mode = vim.api.nvim_get_mode().mode
    for i = 1, #cursors do
        table.insert(self.cursors, CURSOR.make(cursors[i], anchors and anchors[i], self.real_cursor.curswant, mode))
    end
    M.save(self, vim.fn.undotree())
    return self
end

function M.remove(self)
    vim.api.nvim_buf_clear_namespace(self.buffer, CONSTANTS.NAMESPACE, 0, -1)
    if self.autocmd then
        pcall(vim.api.nvim_del_autocmd, self.autocmd)
    end
    for i, cursor in ipairs(self.cursors) do
        CURSOR.remove(cursor)
    end
    REAL_CURSOR.remove(self.real_cursor)
    vim.bo.autoindent = self.autoindent
    vim.bo.indentkeys = self.indentkeys
    self.done = true
end


function M.play_keys(self, keys, undojoin, new_mode)
    -- remove nop
    keys = keys:gsub(CONSTANTS.NOP, '')

    if self.mode == 'i' or self.mode == 'R' then
        keys = self.mode .. UTILS.vim_escape(CONSTANTS.RESTORE_PLUG) .. keys
    elseif keys:match('^%s') then
        -- can't start with space, so prefix with 1?
        keys = '1' .. keys
    end

    -- use a plug to get the self pos *before* we leave insert mode
    -- since exiting insert mode moves the cursor
    if new_mode == 'i' or new_mode == 'R' then
        keys = keys .. UTILS.vim_escape(CONSTANTS.RECORD_PLUG .. '<esc>')
    end

    REAL_CURSOR.save_and_restore(self.real_cursor, function()

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
            CURSOR.play_keys(cursor, self.register, keys, undojoin, self.mode, new_mode)
        end

        -- teardown
        vim.cmd('noautocmd call nvim_set_current_win('..window..')')
        vim.api.nvim_win_close(scratch, true)
        vim.wo.winhighlight = winhighlight

        -- reset to normal mode
        vim.cmd(UTILS.vim_escape('normal! <esc>'))

    end, mode)

    REAL_CURSOR._save_and_restore.position.save(self.real_cursor)
end

function M.save(self, undotree, mode)
    mode = mode or vim.api.nvim_get_mode().mode

    -- restore the mode as well
    if mode == 'i' then
        local pos = UTILS.get_mark(self.real_cursor.edit_region)
        if self.mode ~= 'i' then
            self.real_cursor.insert_start = UTILS.create_mark(pos, nil, self.real_cursor.insert_start)
        else
            if not self.real_cursor.insert_start then
                self.real_cursor.insert_start = UTILS.create_mark(UTILS.get_mark(self.real_cursor.edit_region), nil)
            end
            local start = UTILS.get_mark(self.real_cursor.insert_start)
            vim.api.nvim_win_set_cursor(0, {start[1]+1, start[2]})
        end
        -- restart the insert mode
        vim.cmd[[startinsert]]
    end

    -- macro moves cursor, so move it back
    local pos = REAL_CURSOR._save_and_restore.position.restore(self.real_cursor)

    local numlines = vim.api.nvim_buf_line_count(0)
    -- check for overlaps
    local marks = vim.tbl_map(function(c) return UTILS.get_mark(c.pos) end, self.cursors)
    for i = #self.cursors, 1, -1 do
        local delete = false

        if marks[i][1] >= numlines then
            delete = true
        elseif marks[i][1] == pos[1] and marks[i][2] == pos[2] then
            delete = true
        else
            for j = 1, i-1 do
                if marks[i][1] == marks[j][1] and marks[i][2] == marks[j][2] then
                    delete = true
                    break
                end
            end
        end

        if delete then
            CURSOR.remove(self.cursors[i])
            table.remove(self.cursors, i)
        end
    end

    -- record undo positions
    REAL_CURSOR.save_undo_pos(self.real_cursor, undotree.seq_cur, pos)
    for i, cursor in ipairs(self.cursors) do
        CURSOR.save_undo_pos(cursor, undotree.seq_cur, marks[i])
    end

    self.undo_seq = undotree.seq_cur
    self.changedtick = vim.b.changedtick
    self.mode = mode
    self.changes = nil

    return #self.cursors > 0
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

function M.clear_visual(self)
    for i, cursor in ipairs(self.cursors) do
        CURSOR.clear_visual(cursor)
    end
end

return M
