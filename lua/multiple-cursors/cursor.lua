local M = {}

local UTILS = require('multiple-cursors.utils')
local CONSTANTS = require('multiple-cursors.constants')

local RECORDED_POS = nil
vim.keymap.set('i', CONSTANTS.RECORD_POS_PLUG, function()
    RECORDED_POS = vim.api.nvim_win_get_cursor(0)
end)


function M.make(pos, visual, curswant)
    local reverse_region
    if visual then
        visual, reverse_region = UTILS.create_mark(visual, CONSTANTS.VISUAL_HIGHLIGHT)
    end
    local self = {
        pos = UTILS.create_cursor_highlight_mark(pos),
        curswant = curswant,
        edit_region = UTILS.create_mark(pos, CONSTANTS.CHANGED_HIGHLIGHT),
        visual = visual,
        reverse_region = reverse_region,
        undo_pos = {},
    }
    M._save_and_restore.marks.save(self)
    M._save_and_restore.registers.save(self)
    return self
end

function M.remove(self)
    vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.pos)
    vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.edit_region)
    if self.visual then
        vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.visual)
    end
end

function M.set_pos(self, pos, highlight)
    self.edit_region = UTILS.create_mark(pos, highlight, self.edit_region)
    if highlight then
        self.pos = UTILS.create_cursor_highlight_mark(pos, self.pos)
    end
end

function M.get_pos(self)
    -- get the cursor pos from the mark
    local mark = UTILS.get_mark(self.edit_region, true)
    return {mark[3].end_row, mark[3].end_col}
end

M._save_and_restore = {
    position = {
        save = function(self, args)
            local pos = args.pos
            if pos then
                self.curswant = pos[2]
            else
                pos, self.curswant = UTILS.getcurpos()
            end
            M.set_pos(self, pos, CONSTANTS.CHANGED_HIGHLIGHT)
        end,
        restore = function(self)
            local pos = M.get_pos(self)
            vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
            if self.curswant ~= pos[2] then
                vim.fn.winrestview({curswant=self.curswant})
            end
        end,
    },

    visual = {
        save = function(self)
            local visual = UTILS.get_visual_range()
            if visual then
                self.visual, self.reverse_region = UTILS.create_mark({visual[1][1], visual[1][2], visual[2][1], visual[2][2]}, CONSTANTS.VISUAL_HIGHLIGHT, self.visual)
            elseif self.visual then
                vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.visual)
                self.visual = nil
            end
        end,
        restore = function(self, args)
            if UTILS.is_visual(args.mode.mode) then
                if self.visual then
                    local mark = UTILS.get_mark(self.visual, true)
                    UTILS.set_visual_range(mark, {mark[3].end_row, mark[3].end_col}, args.mode.mode)
                    if self.reverse_region then
                        vim.cmd[[normal! o]]
                    end
                else
                    -- don't know the visual range, fake it
                    vim.cmd('normal! '..args.mode.mode)
                end
            end
        end,
    },

    registers = {
        save = function(self)
            self.registers = vim.tbl_map(vim.fn.getreg, CONSTANTS.ALL_REGISTERS)
        end,
        restore = function(self)
            for i, reg in ipairs(self.registers) do
                vim.fn.setreg(CONSTANTS.ALL_REGISTERS[i], reg)
            end
        end,
    },

    marks = {
        save = function(self)
            self.marks = {}
            for i, name in ipairs(CONSTANTS.ALL_MARKS) do
                self.marks[name] = vim.api.nvim_buf_get_mark(0, name)
            end
            return self.marks
        end,
        restore = function(self)
            for k, v in pairs(self.marks) do
                vim.api.nvim_buf_set_mark(0, k, v[1], v[2], {})
            end
        end,
    },
}

local cursor_attrs = vim.tbl_keys(M._save_and_restore)

function M.restore_and_save(self, cb, mode)
    -- restore prev position etc
    for i = 1, #cursor_attrs do
        M._save_and_restore[cursor_attrs[i]].restore(self, {mode=mode})
    end

    RECORDED_POS = nil
    cb()

    for i = #cursor_attrs, 1, -1 do
        M._save_and_restore[cursor_attrs[i]].save(self, {mode=mode, pos=RECORDED_POS and {RECORDED_POS[1]-1, RECORDED_POS[2]}})
    end
end

function M.play_keys(self, keys, undojoin, mode)
    -- get to normal mode
    vim.cmd(UTILS.vim_escape('normal! <esc>'))

    M.restore_and_save(self, function()
        -- if cursor is beyond end, append instead of insert
        if keys:sub(1, 1) == 'i' and UTILS.get_mark(self.pos)[2] > vim.api.nvim_win_get_cursor(0)[2] then
            keys = 'a' .. keys:sub(2)
        end

        -- execute the keys
        vim.cmd((undojoin and 'undojoin | ' or '')..'silent! normal '..keys)
    end, mode)
end

function M.save_undo_pos(self, undo_seq, pos)
    self.undo_pos[undo_seq] = pos
end

function M.restore_undo_pos(self, undo_seq, highlight)
    local pos = self.undo_pos[undo_seq]
    if pos then
        M.set_pos(self, pos, highlight)
        self.curswant = pos[2]
    end
    return self, pos
end

return M
