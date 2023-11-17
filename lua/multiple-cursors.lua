local M = {}

local NAMESPACE = vim.api.nvim_create_namespace('multiple-cursors.nvim')
local VISUALMODES = {'v', 'V', ''}
local VISUAL_HIGHLIGHT = 'MultiCursorVisual'
local CHANGED_HIGHLIGHT = 'MultiCursorText'
local CURSOR_HIGHLIGHT = 'MultiCursor'
local REGISTER = 'm'
local ALL_REGISTERS = vim.list_extend(vim.split("-/0123456789abcdefghijklmnopqrstuvwxyz", ''), {''})
local teardowns = {}

local function get_mark(id, details)
    return vim.api.nvim_buf_get_extmark_by_id(0, NAMESPACE, id, {details=details})
end

local function create_marks(positions, highlight, old_marks)
    local marks = {}
    old_marks = old_marks or {}
    for i, pos in ipairs(positions) do
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

        table.insert(marks, vim.api.nvim_buf_set_extmark(
            0, NAMESPACE,
            left[1], math.min(left[2], #line-1),
            {
                id = old_marks[i],
                hl_group = highlight,
                end_row = right[1],
                end_col = math.min(right[2], #line),
                right_gravity = false,
                end_right_gravity = true,
                virt_text = {{'', reverse and 'reverse' or ''}},
            }
        ))
    end
    return marks
end

local function create_cursor_highlight_marks(marks, old_marks)
    local cursor_marks = {}
    old_marks = old_marks or {}
    for i, id in ipairs(marks) do
        local mark = get_mark(id, true)
        local row = mark[3].end_row
        local col = mark[3].end_col

        local line = vim.api.nvim_buf_get_lines(0, row, row+1, true)[1]
        local past_end = col + 1 > #line

        table.insert(cursor_marks, vim.api.nvim_buf_set_extmark(
            0, NAMESPACE,
            row,
            past_end and col or math.min(col, #line-1),
            {
                id = old_marks[i],
                hl_group = CURSOR_HIGHLIGHT,
                end_row = row,
                end_col = not past_end and col+1 or nil,
                virt_text = past_end and {{' ', CURSOR_HIGHLIGHT}} or nil,
                virt_text_pos = 'overlay',
                right_gravity = true,
                end_right_gravity = true,
            }
        ))
    end
    return cursor_marks
end

local RECORD_POS_PLUG = '<Plug>(multiple-cursors-record_pos)'
local RECORDED_POS = nil
map.i[RECORD_POS_PLUG] = function()
    RECORDED_POS = vim.api.nvim_win_get_cursor(0)
end
local function repeat_key(marks, region_marks, key, mode, registers, undojoin)

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

    local new_mode = vim.api.nvim_get_mode()
    if mode.mode == 'i' then
        key = 'i' .. key
    elseif mode.mode == 'R' then
        key = 'R' .. key
    elseif key:match('^%s') then
        -- can't start with space, so prefix with 1?
        key = '1' .. key
    end

    local new_cursors = {}
    local new_regions = {}

    -- visual range seems to be lost with nvim_win_call()
    local window = vim.api.nvim_get_current_win()
    vim.cmd('noautocmd call nvim_set_current_win('..scratch..')')

    for i, id in ipairs(marks) do
        -- get to normal mode
        vim.cmd(vim_escape('normal! <esc>'))

        -- repeat the key at each spot
        local mark = get_mark(id, true)

        -- use a plug to get the cursor pos *before* we leave insert mode
        -- since exiting insert mode moves the cursor
        RECORDED_POS = nil
        if new_mode.mode == 'i' then
            key = key .. vim_escape(RECORD_POS_PLUG)
        end

        if vim.tbl_contains(VISUALMODES, mode.mode) then
            if region_marks[i] then
                -- reselect the visual region described in the mark
                local region_mark = get_mark(region_marks[i], true)
                utils.set_visual_range(region_mark, {region_mark[3].end_row, region_mark[3].end_col}, mode.mode)
                if region_mark[3].virt_text[1][2] == 'reverse' then
                    vim.cmd[[normal! o]]
                end
            else
                -- don't know the region, fake it
                key = mode.mode .. key
            end
        end

        -- restore registers
        for j = 1, #ALL_REGISTERS do
            vim.fn.setreg(ALL_REGISTERS[j], registers[i][j])
        end

        -- go to the cursor
        vim.api.nvim_win_set_cursor(0, {mark[3].end_row+1, mark[3].end_col})
        -- execute the keys
        vim.cmd((undojoin and 'undojoin | ' or '')..'normal '..key)

        -- record registers
        registers[i] = vim.tbl_map(vim.fn.getreg, ALL_REGISTERS)

        -- record the positions
        local cursor = RECORDED_POS or vim.api.nvim_win_get_cursor(0)
        cursor[1] = cursor[1] - 1
        new_cursors[i] = cursor
        local range = utils.get_visual_range()
        if range then
            new_regions[i] = {range[1][1], range[1][2], range[2][1], range[2][2]}
        end
    end
    -- teardown
    vim.cmd('noautocmd call nvim_set_current_win('..window..')')
    vim.api.nvim_win_close(scratch, true)
    vim.wo.winhighlight = winhighlight

    -- reset to normal mode
    vim.cmd(vim_escape('normal! <esc>'))

    return new_cursors, new_regions
end

function M.start(positions, regions, options)
    M.stop()

    options = vim.tbl_deep_extend('keep', options or {}, {
        highlights = {
            changed = CHANGED_HIGHLIGHT,
            visual = VISUAL_HIGHLIGHT
        }
    })

    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local undotree = vim.fn.undotree()
    local last_undo_seq = undotree.seq_cur
    local last_tick = vim.b.changedtick
    local mode = vim.api.nvim_get_mode()
    local registers = vim.tbl_map(function(x) return vim.tbl_map(vim.fn.getreg, ALL_REGISTERS) end, positions)

    local undo_cursor_pos = {[last_undo_seq] = {cursor, positions}}
    local marks = create_marks(positions, options.highlights.changed)
    local cursor_marks = create_cursor_highlight_marks(marks)
    local real_mark_id = create_marks({{cursor[1]-1, cursor[2]}}, options.highlights.cursor)[1]
    local region_marks = create_marks(regions or {}, options.highlights.visual)
    table.insert(teardowns, function() vim.api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1) end)

    vim.cmd('normal! q'..REGISTER)
    table.insert(teardowns, function() vim.cmd('normal! q') end)

    local recursion = false
    local changes = nil
    local function processor(args)
        if recursion then
            return
        end
        recursion = true

        if args.event:match('^CursorMoved') and vim.b.changedtick ~= last_tick then
            -- wait for the TextChanged* instead
            recursion = false
            return
        end

        local new_cursor = vim.api.nvim_win_get_cursor(0)
        local undotree = vim.fn.undotree()

        -- stop recording
        vim.cmd('normal! q')
        local key = vim.fn.getreg(REGISTER)
        local mark = get_mark(real_mark_id, true)

        if args.event:match('^TextChanged') and last_undo_seq ~= undotree.seq_cur and (undo_cursor_pos[undotree.seq_cur] or undotree.seq_cur ~= undotree.seq_last) then
            -- don't repeat undo/redo
            local pos = undo_cursor_pos[undotree.seq_cur]
            if pos then
                new_cursor = pos[1]
                marks = create_marks(pos[2], options.highlights.changed, marks)
            end

        elseif args.event:match('^TextChanged') and changes
            and not key:match('^g?[pP]$') and not key:match('^".g?[gP]$') -- not pasting
            and vim.version.cmp(changes.start, changes.finish) < 0
            and vim.version.cmp(changes.start, {mark[1], mark[2]}) >= 0
            and vim.version.cmp(changes.finish, {mark[3].end_row, mark[3].end_col}) <= 0
        then
            -- text changed within the mark region
            -- so just grab the text out and copy it
            local text = vim.api.nvim_buf_get_text(0, mark[1], mark[2], mark[3].end_row, mark[3].end_col, {})
            for i, id in ipairs(marks) do
                local mark = get_mark(id, true)
                vim.api.nvim_buf_set_text(0, mark[1], mark[2], mark[3].end_row, mark[3].end_col, text)
            end

        else
            -- run the macro at each position
            if #key > 0 then
                -- save the visual range
                local range, visual_mode = utils.get_visual_range()
                -- move the real cursor mark first
                real_mark_id = create_marks({{new_cursor[1]-1, new_cursor[2]}}, options.highlights.cursor, {real_mark_id})[1]
                -- save the registers
                local new_registers = vim.tbl_map(vim.fn.getreg, ALL_REGISTERS)

                -- is this undo the most recent one
                local recent_change = undotree.seq_last == undotree.seq_cur
                local new_positions, new_regions = repeat_key(marks, region_marks, key, mode, registers, recent_change and args.event:match('^TextChanged'))

                -- get the new cursor pos from the mark
                local real_mark = get_mark(real_mark_id, true)
                new_cursor = {real_mark[3].end_row+1, real_mark[3].end_col}
                -- move the marks
                marks = create_marks(new_positions, options.highlights.changed, marks)

                -- restore the registers
                for i = 1, #ALL_REGISTERS do
                    vim.fn.setreg(ALL_REGISTERS[i], new_registers[i])
                end
                if #new_regions > 0 then
                    region_marks = create_marks(new_regions, options.highlights.visual, region_marks)
                else
                    for i, id in ipairs(region_marks) do
                        vim.api.nvim_buf_del_extmark(0, NAMESPACE, id)
                    end
                end

                -- restore the visual range
                if range then
                    utils.set_visual_range(range[1], range[2], visual_mode)
                end
            end
        end

        changes = nil
        cursor_marks = create_cursor_highlight_marks(marks, cursor_marks)
        undo_cursor_pos[undotree.seq_cur] = {new_cursor, vim.tbl_map(get_mark, cursor_marks)}
        mode = vim.api.nvim_get_mode()
        -- start recording again
        vim.cmd('normal! q'..REGISTER)
        -- macro moves the cursor, so move it back
        vim.api.nvim_win_set_cursor(0, new_cursor)
        last_tick = vim.b.changedtick
        last_undo_seq = undotree.seq_cur
        recursion = false
    end

    local autocmd = vim.api.nvim_create_autocmd({
        'TextChangedP',
        'TextChanged',
        'CursorMoved',
        'CursorMovedI',
        'TextChangedI',
        -- 'ModeChanged',
    }, {buffer=buffer, callback=processor})
    table.insert(teardowns, function() vim.api.nvim_del_autocmd(autocmd) end)

    local detach = false
    vim.api.nvim_buf_attach(buffer, false, {
        on_bytes = function(type, bufnr, tick, start_row, start_col, offset, old_end_row, old_end_col, old_len, end_row, end_col, len)
            if detach then
                return detach
            end
            changes = {
                start = {start_row, start_col},
                finish = {start_row+end_row, start_col+end_col},
            }
            local mark = get_mark(real_mark_id, true)
            if vim.version.cmp({mark[1], mark[2]}, {mark[3].end_row, mark[3].end_col}) == 0 and old_len ~= 0 then
                -- this is an invalid change
                changes.finish = {0, 0}
            end
        end,
    })
    table.insert(teardowns, function() detach = true end)
end

function M.stop()
    for i, fn in ipairs(teardowns) do
        fn()
    end
    teardowns = {}
end

return M
