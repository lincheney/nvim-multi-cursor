local M = {}

local UTILS = require('multiple-cursors.utils')
local CURSOR = require('multiple-cursors.cursor')

function M.make()
    local pos, curswant = UTILS.getcurpos()
    return {
        edit_region = UTILS.create_mark(pos),
        undo_pos = {},
        curswant = curswant,
    }
end

M._save_and_restore = {
    position = {
        save = function(self)
            local pos
            pos, self.curswant = UTILS.getcurpos()
            CURSOR.set_pos(self, pos)
        end,
        restore = function(self)
            local pos = CURSOR.get_pos(self)
            vim.fn.setpos('.', {0, pos[1]+1, pos[2]+1, 0, self.curswant+1})
        end,
    },

    visual = {
        save = function(self)
            self.visual = UTILS.get_visual_range()
        end,
        restore = function(self, args)
            if self.visual then
                UTILS.set_visual_range(self.visual[1], self.visual[2], args.mode.mode)
            end
        end,
    },

    registers = CURSOR._save_and_restore.registers,
    marks = CURSOR._save_and_restore.marks,

}

local cursor_attrs = vim.tbl_keys(M._save_and_restore)

function M.save_and_restore(self, cb, mode)
    for i = 1, #cursor_attrs do
        M._save_and_restore[cursor_attrs[i]].save(self, {mode=mode})
    end
    cb()
    for i = #cursor_attrs, 1, -1 do
        M._save_and_restore[cursor_attrs[i]].restore(self, {mode=mode})
    end
end

M.save_undo_pos = CURSOR.save_undo_pos
M.restore_undo_pos = CURSOR.restore_undo_pos

return M
