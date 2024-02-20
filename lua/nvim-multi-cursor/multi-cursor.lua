local M = {}

local UTILS = require('nvim-multi-cursor.utils')
local CONSTANTS = require('nvim-multi-cursor.constants')
local REAL_CURSOR = require('nvim-multi-cursor.real-cursor')
local CURSOR = require('nvim-multi-cursor.cursor')

local CURRENT_STATE_ARGS = nil
vim.keymap.set('n', CONSTANTS.ESC_PLUG, '', {noremap=true})
vim.keymap.set({'v', 'i'}, CONSTANTS.ESC_PLUG, '<esc>', {noremap=true})
vim.keymap.set({'n', 'v', 'i'}, CONSTANTS.PRE_PLUG, function()
    local state = CURRENT_STATE_ARGS[1]
    local cursor = state.cursors[CURRENT_STATE_ARGS[2]]
    local new_mode = CURRENT_STATE_ARGS[3]
    CURSOR.restore(cursor, state.mode, new_mode)
    -- reset repeat before the cursor is handled, in case it was a dot repeat
    vim.fn['repeat#set'](UTILS.vim_escape(CONSTANTS.REPEAT_PLUG))
end)
vim.keymap.set({'n', 'v', 'i'}, CONSTANTS.POST_PLUG, function()
    local state = CURRENT_STATE_ARGS[1]
    local cursor = state.cursors[CURRENT_STATE_ARGS[2]]
    local new_mode = CURRENT_STATE_ARGS[3]
    CURSOR.save(cursor, state.mode, new_mode)
    -- go to next cursor
    CURRENT_STATE_ARGS[2] = CURRENT_STATE_ARGS[2] + 1
end)

function M.make(buffer, cursors, anchors, options)
    local self = {
        buffer = buffer,
        register = options.register,
        cursors = {},
        real_cursor = REAL_CURSOR.make(),
        done = false,
        process_interval = 50,
        event_queue = {},

        repeat_keys = '',
        repeat_append = true,

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
    M.save(self)
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


function M.play_keys(self, keys, new_mode)
    keys = table.concat({
        UTILS.vim_escape(CONSTANTS.ESC_PLUG),
        UTILS.vim_escape('i<esc>'), -- somehow this prevents extra undo breaks
        (self.mode == 'i' or self.mode == 'R') and self.mode or '',
        UTILS.vim_escape(CONSTANTS.PRE_PLUG),
        keys,
        UTILS.vim_escape(CONSTANTS.POST_PLUG),
    }, '')

    REAL_CURSOR.save_and_restore(self.real_cursor, function()

        keys = keys:rep(#self.cursors)
        CURRENT_STATE_ARGS = {self, 1, new_mode}
        vim.api.nvim_feedkeys(keys, 'itx', false)

        -- reset to normal mode
        vim.cmd(UTILS.vim_escape('normal! <esc>'))

    end)

end

function M.save(self, mode)
    if self.done then
        M.remove(self)
        return
    end

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
            vim.cmd[[noautocmd normal! i]]
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

    local undotree = vim.fn.undotree()
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

function M.restore_undo_pos(self, undotree)
    -- do something like undojoin
    -- find the closest undo state where we actually have position information

    local undo_seq = undotree.seq_cur

    if not self.real_cursor.undo_pos[undo_seq] then
        local redo = undo_seq > self.undo_seq
        local upper = redo and math.huge or undo_seq
        local lower = redo and undo_seq or 0
        local best = nil

        local seqs = vim.tbl_map(function(x) return x.seq end, undotree.entries)
        table.insert(seqs, 0)
        for i, seq in ipairs(seqs) do
            if lower <= seq and seq <= upper and self.real_cursor.undo_pos[seq] then
                if redo then
                    upper = seq
                else
                    lower = seq
                end
                best = seq
            end
        end

        if best and best ~= undo_seq then
            vim.cmd('undo '..best)
            undo_seq = best
        end
    end

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
