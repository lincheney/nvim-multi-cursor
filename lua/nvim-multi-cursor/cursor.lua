local M = {}

local UTILS = require('nvim-multi-cursor.utils')
local CONSTANTS = require('nvim-multi-cursor.constants')

function M.make(pos, anchor, curswant, mode)
    local self = {
        pos = UTILS.create_cursor_highlight_mark(pos),
        curpos = pos,
        curswant = curswant,
        edit_region = UTILS.create_mark(pos, CONSTANTS.CHANGED_HIGHLIGHT),
        undo_pos = {},
    }

    if UTILS.is_visual(mode) then
        M.set_visual(self, anchor or {pos[1], pos[2]+1}, pos, mode)
    end

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

function M.set_visual(self, anchor, pos, mode)
    local coords = {anchor[1], anchor[2], pos[1], pos[2]}
    if mode == 'V' then
        if anchor[1] <= pos[1] then
            coords[2] = 0
            coords[4] = CONSTANTS.EOL
        else
            coords[4] = 0
            coords[2] = CONSTANTS.EOL
        end
    end
    self.visual, self.reverse_region = UTILS.create_mark(coords, CONSTANTS.VISUAL_HIGHLIGHT, self.visual)
end

M._save_and_restore = {
    position = {
        save = function(self, args)
            self.curpos, self.curswant = UTILS.getcurpos()

            self.current_line = nil
            if args.new_mode == 'i' then
                local line = vim.api.nvim_get_current_line()
                if line:match('^%s+$') and self.curpos[2] == #line then
                    self.current_line = line
                    vim.api.nvim_buf_set_lines(0, self.curpos[1], self.curpos[1]+1, true, {self.current_line})
                end
            end

            if args.old_mode ~= 'i' and args.new_mode == 'i' then
                self.insert_start = UTILS.create_mark(self.curpos, nil, self.insert_start)
            elseif args.old_mode == 'i' and args.new_mode ~= 'i' then
                vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.insert_start)
                self.insert_start = nil
            end

            M.set_pos(self, self.curpos, CONSTANTS.CHANGED_HIGHLIGHT)
        end,
        restore = function(self, args)
            -- sometimes the mark disappears ...
            if #UTILS.get_mark(self.edit_region) == 0 then
                M.set_pos(self, self.curpos, CONSTANTS.CHANGED_HIGHLIGHT)
            end

            local pos = M.get_pos(self)

            if args.old_mode == 'i' then
                if not self.insert_start then
                    self.insert_start = UTILS.create_mark(UTILS.get_mark(self.edit_region), nil)
                end
                local start = UTILS.get_mark(self.insert_start)
                vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
                if self.curswant ~= pos[2] then
                    vim.fn.winrestview({curswant=self.curswant})
                end

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
            local visual, mode = UTILS.get_visual_range()
            if visual then
                M.set_visual(self, {visual[1][1], visual[1][2]}, {visual[2][1], visual[2][2]}, mode)
            else
                M.clear_visual(self)
            end
        end,
        restore = function(self, args)
            if UTILS.is_visual(args.old_mode) then
                local mark = self.visual and UTILS.get_mark(self.visual, true)
                if mark and #mark > 0 then
                    local cursor = {mark[3].end_row, mark[3].end_col-1}
                    if mark[1] ~= cursor[1] or mark[2] ~= cursor[2]+1 then
                        UTILS.save_and_restore_cursor(function()
                            UTILS.set_visual_range(mark, cursor, args.old_mode)
                            if self.reverse_region then
                                vim.cmd[[normal! o]]
                            end
                        end)
                        return
                    end
                end

                -- don't know the visual range, fake it
                vim.cmd('normal! '..args.old_mode)
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
            local numlines = vim.api.nvim_buf_line_count(0)
            local last_line_len = #vim.api.nvim_buf_get_lines(0, -2, -1, true)[1]
            for k, v in pairs(self.marks) do
                if v[1] > numlines or (v[1] == numlines and v[2] >= last_line_len) then
                    v = {numlines, CONSTANTS.EOL}
                end
                vim.api.nvim_buf_set_mark(0, k, v[1], v[2], {})
            end
        end,
    },

}

local cursor_attrs = vim.tbl_keys(M._save_and_restore)

function M.restore(self, old_mode, new_mode)
    -- restore prev position etc
    for i = 1, #cursor_attrs do
        M._save_and_restore[cursor_attrs[i]].restore(self, {
            new_mode = new_mode,
            old_mode = old_mode,
        })
    end
end

function M.save(self, old_mode, new_mode)
    for i = #cursor_attrs, 1, -1 do
        M._save_and_restore[cursor_attrs[i]].save(self, {
            new_mode = new_mode,
            old_mode = old_mode,
        })
    end
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

function M.clear_visual(self)
    if self.visual then
        vim.api.nvim_buf_del_extmark(0, CONSTANTS.NAMESPACE, self.visual)
        self.visual = nil
    end
end

return M
