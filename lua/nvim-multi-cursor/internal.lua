local M = {}

local UTILS = require('nvim-multi-cursor.utils')
local CONSTANTS = require('nvim-multi-cursor.constants')
local MULTI_CURSOR = require('nvim-multi-cursor.multi-cursor')
local REAL_CURSOR = require('nvim-multi-cursor.real-cursor')

local DEFAULT_OPTS = {
    register = 'y',
}

local STATES = {}

local PLAY_KEYS_ARGS = nil
function M._play_keys()
    MULTI_CURSOR.play_keys(unpack(PROCESS_EVENTS_ARGS))
    PROCESS_EVENTS_ARGS = nil
end

local function process_event(state, args, mode)
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

    local undotree = vim.fn.undotree()
    local undo_seq = undotree.seq_cur

    local edit_region = UTILS.get_mark(state.real_cursor.edit_region, true)
    -- stop recording
    -- macro moves the cursor, so move it back
    local keys
    UTILS.save_and_restore_cursor(function()
        vim.cmd('normal! q')
        keys = vim.fn.getreg(state.register)
    end)
    -- remove nop
    keys = keys:gsub(CONSTANTS.NOP, '')

    if args.event == 'WinEnter' then
        -- don't run these keys

    elseif text_changed and state.undo_seq ~= undo_seq and (state.real_cursor.undo_pos[undo_seq] or undo_seq ~= undotree.seq_last) then
        -- don't repeat undo/redo
        -- restore the cursor positions instead
        MULTI_CURSOR.restore_undo_pos(state, undotree)

    elseif text_changed and state.changes
        and not (mode == 'n' and (keys:match('g?[pP]$') or keys:match('".g?[gP]$'))) -- not pasting
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
        UTILS.save_and_restore_cursor(function()
            PROCESS_EVENTS_ARGS = {state, keys, recent_change, mode}
            -- call play_keys() in a normal!
            -- otherwise the feedkeys(..., "itx") does weird things in insert mode
            vim.cmd(vim_escape('normal! <cmd>lua require("nvim-multi-cursor.internal")._play_keys()<cr>'))
        end)

    elseif not UTILS.is_visual(mode) then
        -- clear visual highlights
        MULTI_CURSOR.clear_visual(state)
    end

    -- resume recording the macro
    vim.cmd('normal! q'..state.register)

    if not MULTI_CURSOR.save(state, mode) then
        M.stop()
    end
end

-- call process_events when there are no other callbacks running
local function process_events_soon(state, args)
    if state.recursion or state.done or vim.api.nvim_get_current_buf() ~= state.buffer then
        return
    end

    table.insert(state.event_queue, args)

    local cb
    cb = function(interval)
        if state.recursion or #state.event_queue == 0 or state.done or vim.api.nvim_get_current_buf() ~= state.buffer then
            return
        -- defer processing if we are in the middle of another vim or lua callback
        elseif vim.fn.expand('<stack>') ~= '' or debug.getinfo(2, 'f') then
            vim.defer_fn(function()
                -- the stack in schedule() is cleaner
                vim.schedule(cb)
            end, state.process_interval)
        else
            state.recursion = true

            -- get the mode now, as process_event() may change it
            local mode = vim.api.nvim_get_mode().mode
            -- process each event
            for i, ev in ipairs(state.event_queue) do
                process_event(state, ev, mode)
                state.event_queue[i] = nil
            end

            state.recursion = false
        end
    end
    vim.schedule(cb)
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
        process_events_soon(state, args)
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
