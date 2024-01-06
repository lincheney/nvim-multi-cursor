local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace('nvim-multi-cursor.nvim')
M.PRE_PLUG = '<Plug>NvimMultiCursorPre;'
M.POST_PLUG = '<Plug>NvimMultiCursorPost;'
M.ESC_PLUG = '<Plug>NvimMultiCursorEsc;'

M.ALL_REGISTERS = vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", '')
table.insert(M.ALL_REGISTERS, '')

M.ALL_MARKS = vim.split('<>[]', '')

M.VISUAL_HIGHLIGHT = 'NvimMultiCursorVisual'
M.CHANGED_HIGHLIGHT = 'NvimMultiCursorText'
M.CURSOR_HIGHLIGHT = 'NvimMultiCursor'

M.NOP = '\x80\xfda'
M.EOL = vim.v.maxcol - 1

return M
