local M = {}

local UTILS = require('nvim-multi-cursor.utils')
local MULTI_CURSOR = require('nvim-multi-cursor.multi-cursor')

local DEFAULT_OPTS = {
    register = 'y',
}

local STATES = {}

local function process_event(state, args)
    local text_changed = args.event:match('^TextChanged')

    if not text_changed and vim.b.changedtick ~= state.changedtick then
        -- wait for the TextChanged* instead
        return
    end

    if args.event == 'ModeChanged' then
        local from = args.match:sub(1, 1)
        local to = args.match:sub(#args.match)

        if UTILS.is_visual(from) or UTILS.is_visual(to) then
            -- we only care about mode change to/from visual mode
        elseif state.mode ~= 'i' and to == 'i' then
            -- or to insert mode
        else
            return
        end
    end

    if state.recursion then
        return
    end
    state.recursion = true

    local mode = vim.api.nvim_get_mode().mode
    local undotree = vim.fn.undotree()
    local undo_seq = undotree.seq_cur

    local edit_region = UTILS.get_mark(state.real_cursor.edit_region, true)
    -- stop recording
    -- macro moves the cursor, so move it back
    local keys
    UTILS.save_and_restore_cursor(function()
        vim.cmd('normal! q')
        keys = vim.fn.getreg(state.register)
        vim.cmd('normal! q'..state.register)
    end)

    if args.event == 'WinEnter' then
        -- don't run these keys

    elseif text_changed and state.undo_seq ~= undo_seq and (state.real_cursor.undo_pos[undo_seq] or undo_seq ~= undotree.seq_last) then
        -- don't repeat undo/redo
        -- restore the cursor positions instead
        MULTI_CURSOR.restore_undo_pos(state, undo_seq)

    elseif text_changed and state.changes
        and not keys:match('g?[pP]$') and not keys:match('".g?[gP]$') -- not pasting
        and vim.version.cmp(state.changes.start, state.changes.finish) < 0
        and vim.version.cmp(state.changes.start, {edit_region[1], edit_region[2]}) >= 0
        and vim.version.cmp(state.changes.finish, {edit_region[3].end_row, edit_region[3].end_col}) <= 0
    then
        -- text changed within the mark region
        -- so just grab the text out and copy it
        local text = vim.api.nvim_buf_get_text(0, edit_region[1], edit_region[2], edit_region[3].end_row, edit_region[3].end_col, {})
        for i, cursor in ipairs(state.cursors) do
            local mark = UTILS.get_mark(cursor.edit_region, true)
            vim.api.nvim_buf_set_text(0, mark[1], mark[2], mark[3].end_row, mark[3].end_col, text)
        end

    elseif #keys > 0 then
        -- is this undo the most recent one
        local recent_change = (undotree.seq_last == undotree.seq_cur) and args.event:match('^TextChanged')
        -- run the macro at each position
        MULTI_CURSOR.play_keys(state, keys, recent_change, mode)

    elseif not UTILS.is_visual(mode) then
        -- clear visual highlights
        MULTI_CURSOR.clear_visual(state)
    end

    if not MULTI_CURSOR.save(state, undotree, mode) then
        M.stop()
    end
    state.recursion = false
end

function M.start(positions, anchors, options)
    local buffer = vim.api.nvim_get_current_buf()
    M.stop()

    options = vim.tbl_deep_extend('keep', options or {}, DEFAULT_OPTS)

    local state = MULTI_CURSOR.make(buffer, positions, anchors, options)
    if #state.cursors == 0 then
        MULTI_CURSOR.remove(state)
        return
    end

    -- start recording
    vim.cmd('normal! q' .. state.register)

    state.autocmd = vim.api.nvim_create_autocmd({
        'TextChangedP',
        'TextChanged',
        'CursorMoved',
        'CursorMovedI',
        'TextChangedI',
        'ModeChanged',
        'WinEnter',
    }, {buffer=buffer, callback=function(args)
        if not state.recursion then
            local interval = 50
            local cb
            cb = function(later)
                -- defer processing if we are in the middle of another vim or lua callback
                if later or vim.fn.expand('<stack>') ~= '' or debug.getinfo(2, 'f') then
                    vim.defer_fn(function()
                        -- the stack in schedule() is cleaner
                        vim.schedule(cb)
                    end, later or interval)
                else
                    process_event(state, args)
                end
            end
            cb(0)
        end
    end})

    vim.api.nvim_buf_attach(state.buffer, false, {
        on_bytes = function(type, bufnr, tick, start_row, start_col, offset, old_end_row, old_end_col, old_len, end_row, end_col, len)
            if state.done then
                return state.done
            end
            local changes = {
                start = {start_row, start_col},
                finish = {start_row+end_row, start_col+end_col},
            }
            if state.changes then
                -- merge these changes together
                state.changes.start = vim.version.cmp(state.changes.start, changes.start) < 0 and state.changes.start or changes.start
                state.changes.finish = vim.version.cmp(state.changes.finish, changes.finish) > 0 and state.changes.finish or changes.finish
            else
                state.changes = changes
            end

            local mark = UTILS.get_mark(state.real_cursor.edit_region, true)
            if vim.version.cmp({mark[1], mark[2]}, {mark[3].end_row, mark[3].end_col}) == 0 and old_len ~= 0 then
                -- this is an invalid change
                state.changes.finish = {0, 0}
            end
        end,
    })

    STATES[buffer] = state
    state.on_leave = options.on_leave
    return state
end

function M.stop()
    local buffer = vim.api.nvim_get_current_buf()
    if STATES[buffer] then
        MULTI_CURSOR.remove(STATES[buffer])
        vim.cmd('normal! q')
        if STATES[buffer].on_leave then
            STATES[buffer].on_leave()
        end
        STATES[buffer] = nil
    end
end

function M.is_active()
    local buffer = vim.api.nvim_get_current_buf()
    if STATES[buffer] then
        return true
    end
end

return M
