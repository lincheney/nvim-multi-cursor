local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace('multiple-cursors.nvim')
M.RECORD_POS_PLUG = '<Plug>(multiple-cursors-record_pos)'

M.ALL_REGISTERS = vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", '')
table.insert(M.ALL_REGISTERS, '')

M.ALL_MARKS = vim.split('<>[]', '')

M.VISUAL_HIGHLIGHT = 'MultiCursorVisual'
M.CHANGED_HIGHLIGHT = 'MultiCursorText'
M.CURSOR_HIGHLIGHT = 'MultiCursor'

M.NOP = '\x80\xfda'

return M
