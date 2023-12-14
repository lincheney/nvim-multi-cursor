local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace('nvim-multi-cursor.nvim')
M.RECORD_PLUG = '<Plug>(nvim-multi-cursor-record_insert_mode)'
M.RESTORE_PLUG = '<Plug>(nvim-multi-cursor-restore_insert_mode)'

M.ALL_REGISTERS = vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", '')
table.insert(M.ALL_REGISTERS, '')

M.ALL_MARKS = vim.split('<>[]', '')

M.VISUAL_HIGHLIGHT = 'MultiCursorVisual'
M.CHANGED_HIGHLIGHT = 'MultiCursorText'
M.CURSOR_HIGHLIGHT = 'MultiCursor'

M.NOP = '\x80\xfda'
M.EOL = vim.v.maxcol - 1

return M
