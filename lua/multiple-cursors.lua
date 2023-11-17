local M = {}

local NAMESPACE = vim.api.nvim_create_namespace('multiple-cursors.nvim')
local VISUALMODES = {['v']=true, ['V']=true, ['']=true}
local DEFAULT_OPTS = {
    register = 'y',
}

local VISUAL_HIGHLIGHT = 'MultiCursorVisual'
local CHANGED_HIGHLIGHT = 'MultiCursorText'
local CURSOR_HIGHLIGHT = 'MultiCursor'
local REGISTER = 'm'
local ALL_REGISTERS = vim.list_extend(vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", ''), {''})
local STATES = {}

local function get_mark(id, details)
    return vim.api.nvim_buf_get_extmark_by_id(0, NAMESPACE, id, {details=details})
end

local function get_visual_range()
    local mode = vim.api.nvim_get_mode().mode
    if VISUALMODES[mode] then
        local first = vim.fn.getpos('v')
        local last = vim.api.nvim_win_get_cursor(0)
        return {{first[2]-1, first[3]-1}, {last[1]-1, last[2]+1}}, mode
    end
end

local function set_visual_range(first, last, mode)
    -- reselect the visual region
    vim.api.nvim_win_set_cursor(0, {first[1]+1, first[2]})
    vim.cmd('normal! v')
    vim.api.nvim_win_set_cursor(0, {last[1]+1, last[2]-1})
    -- change to the correct visual mode
    if mode and mode ~= 'v' then
        vim.cmd('normal! '..mode)
    end
end

local function create_mark(pos, highlight, old_mark)
    local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, true)[1]

    local left = {pos[1], pos[2]}
    -- if right is not given, use same as left
    local right = {pos[3] or pos[1], pos[4] or pos[2]}
    local reverse = vim.version.cmp(left, right) > 0
    if reverse then
        left, right = right, left
        left[2] = left[2] - 1
        right[2] = right[2] + 1
    end

    return vim.api.nvim_buf_set_extmark(
        0, NAMESPACE,
        left[1], math.min(left[2], #line-1),
        {
            id = old_mark,
            hl_group = highlight,
            end_row = right[1],
            end_col = math.min(right[2], #line),
            right_gravity = false,
            end_right_gravity = true,
            virt_text = {{'', reverse and 'reverse' or ''}},
        }
    )
end

local function create_cursor_highlight_mark(pos, old_mark)
    local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, true)[1]
    local past_end = pos[2] + 1 > #line

    return vim.api.nvim_buf_set_extmark(
        0, NAMESPACE,
        pos[1],
        past_end and pos[2] or math.min(pos[2], #line-1),
        {
            id = old_mark,
            hl_group = CURSOR_HIGHLIGHT,
            end_row = pos[1],
            end_col = not past_end and pos[2]+1 or nil,
            virt_text = past_end and {{' ', CURSOR_HIGHLIGHT}} or nil,
            virt_text_pos = 'overlay',
            right_gravity = true,
            end_right_gravity = true,
        }
    )
end

local RECORD_POS_PLUG = '<Plug>(multiple-cursors-record_pos)'
local RECORDED_POS = nil
vim.keymap.set('i', RECORD_POS_PLUG, function()
    RECORDED_POS = vim.api.nvim_win_get_cursor(0)
end)

local function make_cursor(position, region, curswant)
    return {
        pos = create_cursor_highlight_mark(position),
        curswant = curswant,
        edit_region = create_mark(position, CHANGED_HIGHLIGHT),
        region = region and create_mark(region, VISUAL_HIGHLIGHT),
        undo_pos = {},
        registers = vim.tbl_map(vim.fn.getreg, ALL_REGISTERS),
    }
end

local function remove_cursor(self)
    vim.api.nvim_buf_del_extmark(0, NAMESPACE, self.pos)
    vim.api.nvim_buf_del_extmark(0, NAMESPACE, self.edit_region)
    if self.region then
        vim.api.nvim_buf_del_extmark(0, NAMESPACE, self.region)
    end
end

local function cursor_restore_undo_pos(self, undo_seq, highlight)
    local pos = self.undo_pos[undo_seq]
    if pos then
        self.edit_region = create_mark(pos, CHANGED_HIGHLIGHT, self.edit_region)
        self.curswant = pos[2]
        if highlight then
            self.pos = create_cursor_highlight_mark(pos, self.pos)
        end
    end
    return self, pos
end

local function real_cursor_record(self)
    local pos = vim.fn.getcurpos()
    self.curswant = pos[5]-1
    pos = {pos[2]-1, pos[3]-1}

    -- save the visual range
    self.region = get_visual_range()
    -- move the real self mark first
    self.edit_region = create_mark(pos, CHANGED_HIGHLIGHT, self.edit_region)
    -- save the registers
    self.registers = vim.tbl_map(vim.fn.getreg, ALL_REGISTERS)
end

local function real_cursor_restore(self, mode)
    -- get the new cursor pos from the mark
    local mark = get_mark(self.edit_region, true)
    vim.fn.setpos('.', {0, mark[3].end_row+1, mark[3].end_col+1, 0, self.curswant+1})

    -- restore the registers
    for i = 1, #ALL_REGISTERS do
        vim.fn.setreg(ALL_REGISTERS[i], self.registers[i])
    end

    -- restore the visual range
    if self.region then
        set_visual_range(self.region[1], self.region[2], mode.mode)
    end
end

local function cursor_record(self, pos)
    -- record registers
    self.registers = vim.tbl_map(vim.fn.getreg, ALL_REGISTERS)

    -- record the position
    if pos then
        self.curswant = pos[2]
    else
        pos = vim.fn.getcurpos()
        self.curswant = pos[5]-1
        pos = {pos[2]-1, pos[3]-1}
    end
    self.edit_region = create_mark(pos, CHANGED_HIGHLIGHT, self.edit_region)
    self.pos = create_cursor_highlight_mark(pos, self.pos)

    -- record the visual range
    local region = get_visual_range()
    if region then
        self.region = create_mark({region[1][1], region[1][2], region[2][1], region[2][2]}, VISUAL_HIGHLIGHT, self.region)
    elseif self.region then
        vim.api.nvim_buf_del_extmark(0, NAMESPACE, self.region)
    end
end
local function cursor_restore(self, mode)
    -- restore registers
    for j = 1, #ALL_REGISTERS do
        vim.fn.setreg(ALL_REGISTERS[j], self.registers[j])
    end

    -- restore the visual range
    if VISUALMODES[mode.mode] and self.region then
        -- reselect the visual region described in the mark
        local region_mark = get_mark(self.region, true)
        set_visual_range(region_mark, {region_mark[3].end_row, region_mark[3].end_col}, mode.mode)
        if region_mark[3].virt_text[1][2] == 'reverse' then
            vim.cmd[[normal! o]]
        end
    end

    -- go to the cursor
    local mark = get_mark(self.edit_region, true)
    vim.api.nvim_win_set_cursor(0, {mark[3].end_row+1, mark[3].end_col})
    if self.curswant ~= mark[3].end_col then
        vim.fn.winrestview({curswant=self.curswant})
    end
end


local function cursor_play_keys(self, keys, undojoin, mode)
    -- get to normal mode
    vim.cmd(vim_escape('normal! <esc>'))

    -- use a plug to get the self pos *before* we leave insert mode
    -- since exiting insert mode moves theself
    RECORDED_POS = nil
    if mode.mode == 'i' then
        keys = keys .. vim_escape(RECORD_POS_PLUG)
    end

    if VISUALMODES[mode.mode] and not self.region then
        -- don't know the region, fake it
        keys = mode.mode .. keys
    end

    cursor_restore(self, mode)

    -- execute the keys
    vim.cmd((undojoin and 'undojoin | ' or '')..'silent! normal '..keys)

    cursor_record(self, mode.mode == 'i' and RECORDED_POS and {RECORDED_POS[1]-1, RECORDED_POS[2]})
end

local function multicursor_play_keys(self, keys, undojoin)
    real_cursor_record(self.real_cursor)

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

    local mode = vim.api.nvim_get_mode()
    if self.mode.mode == 'i' then
        keys = 'i' .. keys
    elseif self.mode.mode == 'R' then
        keys = 'R' .. keys
    elseif keys:match('^%s') then
        -- can't start with space, so prefix with 1?
        keys = '1' .. keys
    end

    -- visual range seems to be lost with nvim_win_call()
    local window = vim.api.nvim_get_current_win()
    vim.cmd('noautocmd call nvim_set_current_win('..scratch..')')

    for i, cursor in ipairs(self.cursors) do
        cursor_play_keys(cursor, keys, undojoin, self.mode)
    end

    -- teardown
    vim.cmd('noautocmd call nvim_set_current_win('..window..')')
    vim.api.nvim_win_close(scratch, true)
    vim.wo.winhighlight = winhighlight

    -- reset to normal mode
    vim.cmd(vim_escape('normal! <esc>'))

    real_cursor_restore(self.real_cursor, mode)
end

local function multicursor_record(self, undotree)
    self.undo_seq = undotree.seq_cur
    self.changedtick = vim.b.changedtick
    self.mode = vim.api.nvim_get_mode()
    self.changes = nil

    local pos = vim.api.nvim_win_get_cursor(0)
    pos[1] = pos[1] - 1

    -- check for overlaps
    local marks = vim.tbl_map(function(c) return get_mark(c.pos) end, self.cursors)
    for i = #self.cursors, 1, -1 do
        for j = 1, i-1 do
            if (marks[i][1] == marks[j][1] and marks[i][2] == marks[j][2]) or (marks[i][1] == pos[1] and marks[i][2] == pos[2]) then
                remove_cursor(self.cursors[i])
                table.remove(self.cursors, i)
                break
            end
        end
    end

    self.real_cursor.undo_pos[undotree.seq_cur] = pos
    for i, cursor in ipairs(self.cursors) do
        cursor.undo_pos[undotree.seq_cur] = marks[i]
    end
end

local function multicursor_process_event(self, args)
    if self.recursion then
        return
    end
    self.recursion = true

    local text_changed = args.event:match('^TextChanged')

    if not text_changed and vim.b.changedtick ~= self.changedtick then
        -- wait for the TextChanged* instead
        self.recursion = false
        return
    end

    local undotree = vim.fn.undotree()
    local undo_seq = undotree.seq_cur

    -- stop recording
    local pos = vim.fn.getcurpos()
    vim.cmd('normal! q')
    -- macro moves the cursor, so move it back
    vim.fn.setpos('.', pos)
    local keys = vim.fn.getreg(self.register)
    local edit_region = get_mark(self.real_cursor.edit_region, true)

    if args.event == 'WinEnter' then
        -- don't run these keys

    elseif text_changed and self.undo_seq ~= undo_seq and (self.real_cursor.undo_pos[undo_seq] or undo_seq ~= undotree.seq_last) then
        -- don't repeat undo/redo
        -- restore the cursor positions instead
        for i, cursor in ipairs(self.cursors) do
            cursor_restore_undo_pos(cursor, undo_seq, true)
        end
        local _, pos = cursor_restore_undo_pos(self.real_cursor, undo_seq, false)
        if pos then
            vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
        end

    elseif text_changed and self.changes
        and not keys:match('^g?[pP]$') and not keys:match('^".g?[gP]$') -- not pasting
        and vim.version.cmp(self.changes.start, self.changes.finish) < 0
        and vim.version.cmp(self.changes.start, {edit_region[1], edit_region[2]}) >= 0
        and vim.version.cmp(self.changes.finish, {edit_region[3].end_row, edit_region[3].end_col}) <= 0
    then
        -- text changed within the mark region
        -- so just grab the text out and copy it
        local text = vim.api.nvim_buf_get_text(0, edit_region[1], edit_region[2], edit_region[3].end_row, edit_region[3].end_col, {})
        for i, cursor in ipairs(self.cursors) do
            local mark = get_mark(cursor.edit_region, true)
            vim.api.nvim_buf_set_text(0, mark[1], mark[2], mark[3].end_row, mark[3].end_col, text)
        end

    elseif #keys > 0 then
        -- is this undo the most recent one
        local recent_change = undotree.seq_last == undotree.seq_cur
        -- run the macro at each position
        multicursor_play_keys(self, keys, recent_change and args.event:match('^TextChanged'))
    end

    multicursor_record(self, undotree)

    local pos = vim.fn.getcurpos()
    -- start recording again
    vim.cmd('normal! q'..self.register)
    -- macro moves the cursor, so move it back
    vim.fn.setpos('.', pos)
    self.recursion = false
end

function M.start(positions, regions, options)
    local buffer = vim.api.nvim_get_current_buf()
    M.stop(buffer)

    options = vim.tbl_deep_extend('keep', options or {}, DEFAULT_OPTS)

    local undotree = vim.fn.undotree()

    local cursor = vim.fn.getcurpos()
    local curswant = cursor[5] - 1
    local self = {
        buffer = buffer,
        register = options.register,
        cursors = {},
        real_cursor = {
            edit_region = create_mark({cursor[2]-1, cursor[3]-1}, nil),
            undo_pos = {},
            curswant = curswant,
        },
        done = false,
    }
    for i = 1, #positions do
        table.insert(self.cursors, make_cursor(positions[i], regions and regions[i], curswant))
    end

    multicursor_record(self, undotree)
    -- start recording
    vim.cmd('normal! q' .. self.register)

    self.autocmd = vim.api.nvim_create_autocmd({
        'TextChangedP',
        'TextChanged',
        'CursorMoved',
        'CursorMovedI',
        'TextChangedI',
        -- 'ModeChanged',
        'WinEnter',
    }, {buffer=buffer, callback=function(args) multicursor_process_event(self, args) end})

    vim.api.nvim_buf_attach(self.buffer, false, {
        on_bytes = function(type, bufnr, tick, start_row, start_col, offset, old_end_row, old_end_col, old_len, end_row, end_col, len)
            if self.detach then
                return self.detach
            end
            self.changes = {
                start = {start_row, start_col},
                finish = {start_row+end_row, start_col+end_col},
            }
            local mark = get_mark(self.real_cursor.edit_region, true)
            if vim.version.cmp({mark[1], mark[2]}, {mark[3].end_row, mark[3].end_col}) == 0 and old_len ~= 0 then
                -- this is an invalid change
                self.changes.finish = {0, 0}
            end
        end,
    })

    STATES[buffer] = self
    return self
end

function M.stop()
    local buffer = vim.api.nvim_get_current_buf()

    if STATES[buffer] then
        vim.api.nvim_buf_clear_namespace(buffer, NAMESPACE, 0, -1)
        vim.cmd('normal! q')
        vim.api.nvim_del_autocmd(STATES[buffer].autocmd)
        STATES[buffer].done = true
        STATES[buffer] = nil
    end
end

return M
