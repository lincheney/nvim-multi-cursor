local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace('nvim-multi-cursor.nvim')
M.ESC_PLUG = '\u{f001}'
M.PRE_PLUG = '\u{f002}'
M.POST_PLUG = '\u{f003}'
M.REPEAT_PLUG = '<Plug>(NvimMultiCursorRepeat)'

M.ALL_REGISTERS = vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", '')
table.insert(M.ALL_REGISTERS, '')

M.ALL_MARKS = vim.split('<>[]', '')

M.VISUAL_HIGHLIGHT = 'NvimMultiCursorVisual'
M.CHANGED_HIGHLIGHT = 'NvimMultiCursorText'
M.CURSOR_HIGHLIGHT = 'NvimMultiCursor'

M.NOP = '\x80\xfda'
M.EOL = vim.v.maxcol - 1

return M
