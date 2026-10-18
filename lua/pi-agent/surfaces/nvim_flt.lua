local config = require("pi-agent.config")
local utils = require("pi-agent.utils")

local M = {}

---@class pi_agent.surfaces.nvim_flt.Opts
---@field auto_insert_on_focus boolean
---@field width number ratio of editor columns when <= 1, absolute columns otherwise
---@field height number ratio of editor lines when <= 1, absolute lines otherwise
---@field border string|string[] border style, see ':h nvim_open_win'
---@field winblend integer transparency (0-100)
---@field title string? title shown on the top border
---@field zindex integer? stacking order

---@type pi_agent.surfaces.nvim_flt.Opts
M.default_opts = {
    auto_insert_on_focus = true,
    width = 0.8,
    height = 0.8,
    border = "rounded",
    winblend = 0,
    title = " pi ",
    zindex = 50,
}

---@type pi_agent.surfaces.nvim_flt.Opts
M.opts = vim.deepcopy(M.default_opts)

---@type integer?
M.win_id = nil

---@type integer?
M.buf_id = nil

---@type integer?
M.chan_id = nil

---@type integer?
M.autocmd_id = nil

function M.setup()
    if M.opts.auto_insert_on_focus and M.autocmd_id == nil then
        M.autocmd_id = vim.api.nvim_create_autocmd("BufEnter", {
            callback = function()
                vim.defer_fn(function()
                    if M.buf_id == nil then
                        return
                    end

                    local buf_id = vim.api.nvim_get_current_buf()
                    if buf_id == M.buf_id and vim.bo[buf_id].filetype == "pi-agent" then
                        if vim.fn.mode() ~= "i" then
                            vim.cmd("startinsert")
                        end

                        return
                    end
                end, 16)
            end,
        })
    elseif M.autocmd_id ~= nil then
        vim.api.nvim_del_autocmd(M.autocmd_id)
        M.autocmd_id = nil
    end

    M.win_id = nil
    M.buf_id = nil
    M.chan_id = nil
end

---@param opts pi_agent.surfaces.nvim_flt.Opts?
---@return pi_agent.Surface
function M.configure(opts)
    M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

    return M
end

local function start_term()
    local jobstart_opts = {
        cwd = vim.uv.cwd(),
        on_exit = function()
            pcall(M.close)
        end, -- close the float on jobstart exit
        pty = true,
        term = true,
    }

    local result = vim.fn.jobstart(
        utils.make_pi_launch_command(config.get_opts().pi_bin, require("pi-agent").session_name),
        jobstart_opts
    )

    if result < 1 then
        utils.raise("Failed to jobstart pi in Nvim float surface")
    end

    if M.buf_id == nil then
        return
    end

    M.chan_id = result
    vim.bo[M.buf_id].bufhidden = "hide"
end

---@return boolean
local function is_job_valid()
    if M.chan_id == nil then
        return false
    end

    local chan_info = vim.api.nvim_get_chan_info(M.chan_id)

    -- check if dict returned is empty, if so not a valid job
    if next(chan_info) == nil then
        M.chan_id = nil
        return false
    end

    if chan_info.buf == -1 or chan_info.exitcode ~= nil then
        vim.fn.chanclose(M.chan_id)
        M.chan_id = nil
        return false
    end

    return true
end

---@param value number
---@param total number
---@return integer
local function resolve_dimension(value, total)
    if value <= 1 then
        return math.max(1, math.floor(total * value))
    end

    return math.max(1, math.floor(value))
end

local function _focus_float()
    if M.buf_id == nil then
        utils.raise("No buffer id")
    end

    -- reuse the float if it is still around and shows our buffer
    if M.win_id ~= nil and vim.api.nvim_win_is_valid(M.win_id) then
        if vim.api.nvim_win_get_buf(M.win_id) == M.buf_id then
            vim.api.nvim_set_current_win(M.win_id)
            return
        end

        -- the window was repurposed, get rid of it before opening a new float
        vim.api.nvim_win_close(M.win_id, true)
        M.win_id = nil
    end

    -- local width = resolve_dimension(M.opts.width, vim.o.columns)
    -- local height = resolve_dimension(M.opts.height, vim.o.lines - vim.o.cmdheight)
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.9)

    ---@type vim.api.keyset.win_config
    local cfg = {
        relative = "editor",
        width = width,
        height = height,
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        style = "minimal",
        border = M.opts.border,
        zindex = M.opts.zindex,
    }

    if M.opts.title ~= nil and M.opts.title ~= "" then
        cfg.title = M.opts.title
        cfg.title_pos = "center"
    end

    M.win_id = vim.api.nvim_open_win(M.buf_id, true, cfg)

    if M.opts.winblend ~= nil then
        vim.api.nvim_set_option_value("winblend", M.opts.winblend, { win = M.win_id })
    end
end

---@param pi pi_agent.Pi
function M.open(pi)
    local has_valid_job = is_job_valid()

    -- no valid job, handle buffer first
    if not has_valid_job then
        -- do NOT reuse buffers
        if M.buf_id ~= nil then
            vim.api.nvim_buf_delete(M.buf_id, { force = true })
            M.buf_id = nil
        end

        -- create a buffer if we don't have one
        if M.buf_id == nil then
            M.buf_id = vim.api.nvim_create_buf(true, true)
            vim.bo[M.buf_id].filetype = "pi-agent"
        end
    end

    -- create float if needed and focus
    M.focus()

    if not has_valid_job then
        start_term()
    end
end

function M.close()
    if M.win_id ~= nil and vim.api.nvim_win_is_valid(M.win_id) then
        vim.api.nvim_win_close(M.win_id, true)
    end

    M.win_id = nil
end

function M.focus()
    _focus_float()
end

function M.validate()
    return true -- we're in nvim, so a float should always be available
end

return M
