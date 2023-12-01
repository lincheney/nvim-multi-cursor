local M = {}

local UTILS = require('multiple-cursors.utils')
local CONSTANTS = require('multiple-cursors.constants')

local RECORDED_INSERT_MODE = nil
vim.keymap.set('', CONSTANTS.RECORD_PLUG, CONSTANTS.NOP)
vim.keymap.set('i', CONSTANTS.RECORD_PLUG, function()
    RECORDED_INSERT_MODE = {
        -- record the cursor position as it will jump back after insert mode
        vim.api.nvim_win_get_cursor(0),
        -- record the line; indentation may reset
        vim.api.nvim_get_current_line(),
    }
end)
vim.keymap.set('i', CONSTANTS.RESTORE_PLUG, function()
    if RECORDED_INSERT_MODE then
        vim.api.nvim_win_set_cursor(0, {RECORDED_INSERT_MODE[1][1], RECORDED_INSERT_MODE[1][2]})
        if RECORDED_INSERT_MODE[1][3] then
            vim.fn.winrestview({curswant=RECORDED_INSERT_MODE[1][3]})
        end
        RECORDED_INSERT_MODE = nil
    end
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
    if self.insert_start then
        vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.insert_start)
    end
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

            self.current_line = nil
            if args.line and args.new_mode == 'i' and args.line:match('^%s+$') and pos[2] == #args.line then
                self.current_line = args.line
                vim.api.nvim_buf_set_lines(0, pos[1], pos[1]+1, true, {self.current_line})
            end

            if args.old_mode ~= 'i' and args.new_mode == 'i' then
                self.insert_start = UTILS.create_mark(pos, nil, self.insert_start)
            elseif args.old_mode == 'i' and args.new_mode ~= 'i' then
                vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.insert_start)
                self.insert_start = nil
            end

            M.set_pos(self, pos, CONSTANTS.CHANGED_HIGHLIGHT)
        end,
        restore = function(self, args)
            local pos = M.get_pos(self)

            if not self.real and args.old_mode == 'i' then
                if not self.insert_start then
                    self.insert_start = UTILS.create_mark(UTILS.get_mark(self.edit_region), nil)
                end
                local start = UTILS.get_mark(self.insert_start)
                vim.api.nvim_win_set_cursor(0, {start[1]+1, start[2]})
                RECORDED_INSERT_MODE = {{pos[1]+1, pos[2], self.curswant ~= pos[2] and self.curswant}}

            else
                vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
                if self.curswant ~= pos[2] then
                    vim.fn.winrestview({curswant=self.curswant})
                end
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
            if UTILS.is_visual(args.old_mode) then
                if self.visual then
                    local mark = UTILS.get_mark(self.visual, true)
                    UTILS.set_visual_range(mark, {mark[3].end_row, mark[3].end_col}, args.old_mode)
                    if self.reverse_region then
                        vim.cmd[[normal! o]]
                    end
                else
                    -- don't know the visual range, fake it
                    vim.cmd('normal! '..args.old_mode)
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

function M.restore_and_save(self, cb, old_mode, new_mode)
    RECORDED_INSERT_MODE = nil

    -- restore prev position etc
    for i = 1, #cursor_attrs do
        M._save_and_restore[cursor_attrs[i]].restore(self, {
            new_mode = new_mode,
            old_mode = old_mode,
        })
    end

    cb()

    for i = #cursor_attrs, 1, -1 do
        M._save_and_restore[cursor_attrs[i]].save(self, {
            new_mode = new_mode,
            old_mode = old_mode,
            line = RECORDED_INSERT_MODE and RECORDED_INSERT_MODE[2],
            pos = RECORDED_INSERT_MODE and {RECORDED_INSERT_MODE[1][1]-1, RECORDED_INSERT_MODE[1][2]},
        })
    end
end

function M.play_keys(self, keys, undojoin, old_mode, new_mode)
    -- get to normal mode
    vim.cmd(UTILS.vim_escape('normal! <esc>'))

    M.restore_and_save(self, function()
        -- execute the keys
        vim.cmd((undojoin and 'undojoin | ' or '')..'silent! normal '..keys)
    end, old_mode, new_mode)
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
