-- Local LuCI adapter for the existing minieap-sysu service. MIT licensed.
local fs = require "nixio.fs"
local nx = require "nixio"
local sys = require "luci.sys"
local util = require "luci.util"
local M = {}
local conf = "/etc/minieap-sysu.conf"
local service = "minieap-sysu"

local function read_config()
    local raw = fs.readfile(conf)
    if not raw or #raw > 16384 then return nil, "无法读取现有认证配置。" end
    local cfg = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local key, value = line:match("^%s*([%w_-]+)=(.*)$")
        if key and cfg[key] == nil then cfg[key] = value:gsub("%s+$", "") end
    end
    return cfg, raw
end

local function atomic_write(path, data)
    local tmp = path .. ".web-" .. nx.getpid()
    -- Symbolic owner-only permissions avoid numeric mode interpretation.
    local file = nx.open(tmp, nx.open_flags("wronly", "creat", "excl"), "rw-------")
    if not file then return nil end
    local offset = 1
    while offset <= #data do
        local n = file:write(data:sub(offset))
        if not n or n <= 0 then
            file:close(); fs.remove(tmp); return nil
        end
        offset = offset + n
    end
    local synced = file:sync()
    file:close()
    if not synced or not fs.rename(tmp, path) then fs.remove(tmp); return nil end
    return true
end

function M.status()
    local cfg, err = read_config()
    -- Never pass the stored password into the template or a response.
    local result = {
        username = cfg and cfg.username or "",
        nic = cfg and cfg.nic or "",
        configured = cfg and cfg.username ~= nil and cfg.password ~= nil,
        error = not cfg and err or nil,
        enabled = sys.init.enabled(service),
        running = false,
        carrier = (fs.readfile("/sys/class/net/eth0/carrier") or ""):match("^1") ~= nil,
        wan_up = false,
        address = ""
    }
    local ok, state = pcall(util.ubus, "service", "list", {name = service})
    if ok and state and state[service] then
        for _, instance in pairs(state[service].instances or {}) do
            if instance.running then result.running = true end
        end
    end
    local wok, wan = pcall(util.ubus, "network.interface.wan", "status", {})
    if wok and wan then
        result.wan_up = wan.up == true
        local addresses = wan["ipv4-address"] or {}
        result.address = addresses[1] and addresses[1].address or ""
    end
    return result
end

function M.save(username, password, enabled)
    if type(username) ~= "string" or #username < 1 or #username > 64
       or username:find("[%c%s]") then
        return nil, "账号应为 1–64 字节，不能包含空格、换行或控制字符。"
    end
    if type(password) ~= "string" or #password > 64 or password:find("%c")
       or password:find("%s$") then
        return nil, "密码不能超过 64 字节，不能包含控制字符或以空白结尾。"
    end
    local cfg, raw = read_config()
    if not cfg then return nil, raw end
    if cfg.nic ~= "eth0" then return nil, "此页面适配 eth0，请先确认现有网卡配置。" end
    if password == "" then password = cfg.password end
    if not password or password == "" then return nil, "请填写校园网密码。" end
    local lines = {}
    for line in raw:gmatch("([^\n]+)") do
        local key = line:match("^%s*([%w_-]+)=")
        if key ~= "username" and key ~= "password" then lines[#lines + 1] = line end
    end
    lines[#lines + 1] = "username=" .. username
    lines[#lines + 1] = "password=" .. password
    if not atomic_write(conf .. ".web-backup", raw) then
        return nil, "备份配置失败，未修改认证配置。"
    end
    if not atomic_write(conf, table.concat(lines, "\n") .. "\n") then
        return nil, "保存失败，原认证配置保持不变。"
    end
    local ok = enabled and sys.init.enable(service) or nil
    if not enabled then ok = sys.init.disable(service) end
    if not ok then return nil, "账号配置已保存，但开机启动设置失败，请检查系统日志。" end
    return true, "已保存。账号密码将在下次启动或重新认证时生效。"
end

function M.action(action)
    local allowed = {start = true, stop = true, restart = true}
    if not allowed[action] then return nil, "不支持的操作。" end
    -- All service names and allowed actions are fixed, never shell form inputs.
    if not sys.init[action](service) then return nil, "服务操作失败，请在系统日志中查看 minieap。" end
    local messages = {
        start = "已提交启动请求，请稍后刷新状态。",
        stop = "已停止认证服务。服务器可能需要稍后才释放在线会话。",
        restart = "已提交重新认证请求，请稍后刷新状态。"
    }
    return true, messages[action]
end

return M
