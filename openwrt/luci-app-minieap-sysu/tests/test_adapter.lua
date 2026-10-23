local base = assert(arg[1])
package.path = base .. "/root/usr/lib/lua/?.lua;" .. package.path
local conf = "/etc/minieap-sysu.conf"
local initial = "# existing settings\nusername=old-user\npassword=old$!#='\\pass\nnic=eth0\nif-impl=sockraw\ndaemonize=0\npid-file=/var/run/minieap-sysu.pid\n"
local files, modes, calls, enabled, running = {}, {}, {}, false, false
local failwrite, failrename = false, false
local fs = {}
fs.readfile = function(path) return files[path] end
fs.remove = function(path) files[path] = nil; return true end
fs.rename = function(a, b)
    if failrename and b == conf then return nil end
    files[b], modes[b] = files[a], modes[a]; files[a] = nil; return true
end
local nx = {
    getpid = function() return 12345 end,
    open_flags = function(...) return table.concat({...}, ",") end,
    open = function(path, flags, mode)
        assert(flags == "wronly,creat,excl")
        -- Match nixio's octal-string parsing: numeric 384 becomes "384"
        -- and is rejected because 8 is not an octal digit.
        local mode_string = tostring(mode)
        if mode_string == "rw-------" then
            mode = 384
        else
            assert(mode_string:match("^[0-7][0-7][0-7]$") or mode_string:match("^[0-7][0-7][0-7][0-7]$"), "invalid nixio permission string")
            mode = assert(tonumber(mode_string, 8))
        end
        if files[path] then return nil end
        files[path], modes[path] = "", mode
        return {
            write = function(self, s)
                if failwrite then return nil end
                -- Exercise partial-write handling.
                local n = math.min(#s, 11)
                files[path] = files[path] .. s:sub(1, n); return n
            end,
            close = function() return true end,
            sync = function() return true end
        }
    end
}
local init = {enabled = function() return enabled end}
for _, action in ipairs({"enable", "disable", "start", "stop", "restart"}) do
    init[action] = function(name)
        assert(name == "minieap-sysu"); calls[#calls + 1] = action
        if action == "enable" then enabled = true end
        if action == "disable" then enabled = false end
        return true
    end
end
local util = {}
util.ubus = function(object)
    if object == "service" then return {["minieap-sysu"] = {instances = {instance1 = {running = running}}}} end
    return {up = true, ["ipv4-address"] = {{address = "192.0.2.10"}}}
end
util.pcdata = function(s)
    return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end
package.loaded["nixio.fs"], package.loaded["nixio"] = fs, nx
package.loaded["luci.sys"], package.loaded["luci.util"] = {init = init}, util
local model = require "luci.model.minieap_sysu"
local function reset()
    files = {[conf] = initial, ["/sys/class/net/eth0/carrier"] = "1\n"}
    modes, calls, enabled, failwrite, failrename = {}, {}, false, false, false
end
assert(not pcall(nx.open, "/invalid-mode", "wronly,creat,excl", 384))
reset()
local status = model.status()
assert(status.username == "old-user" and status.password == nil)
assert(not status.running and status.carrier and status.wan_up)
running = true; assert(model.status().running); running = false
assert(model.save("new-user", "", true))
assert(files[conf]:find("password=old$!#='\\pass", 1, true))
assert(files[conf]:find("pid-file=/var/run/minieap-sysu.pid", 1, true))
assert(files[conf .. ".web-backup"] == initial)
assert(modes[conf] == 384 and modes[conf .. ".web-backup"] == 384)
assert(#calls == 1 and calls[1] == "enable")
reset()
local special = "new$!#='\\<>&\"password"
assert(model.save("new-user", special, false))
assert(files[conf]:find("password=" .. special .. "\n", 1, true))
for _, pair in ipairs({{"user\nmodule=evil", "pass"}, {"user", "pass\nmodule=evil"}, {"user", "pass "}, {"user", string.rep("x", 65)}, {"", "pass"}}) do
    reset(); assert(not model.save(pair[1], pair[2], true)); assert(files[conf] == initial and #calls == 0)
end
reset(); failwrite = true
assert(not model.save("new-user", "new-password", true)); assert(files[conf] == initial)
reset(); failrename = true
assert(not model.save("new-user", "new-password", true)); assert(files[conf] == initial)
reset(); files[conf] = initial:gsub("nic=eth0", "nic=br-lan")
assert(not model.save("new-user", "new-password", true)); assert(#calls == 0)
reset(); assert(not model.action("stop; echo bad")); assert(#calls == 0)
assert(model.action("restart")); assert(calls[1] == "restart")

local method, posted, renders = "GET", {}, {}
local dispatcher = {
    context = {authtoken = "test-csrf-token"},
    test_post_security = function() return method == "POST" and posted.token == "test-csrf-token" end,
    build_url = function(...) return "/cgi-bin/luci/" .. table.concat({...}, "/") end
}
package.loaded["luci.dispatcher"] = dispatcher
package.loaded["luci.http"] = {formvalue = function(k) return posted[k] end, header = function() end}
package.loaded["luci.template"] = {render = function(name, context) renders[#renders + 1] = context end}
local ctrl = require "luci.controller.minieap_sysu"
reset(); posted = {action = "stop", token = "test-csrf-token"}
ctrl.action_update(); assert(#calls == 0 and #renders == 0)
method = "POST"; posted.token = "wrong"
ctrl.action_update(); assert(#calls == 0 and #renders == 0)
posted.token = "test-csrf-token"
ctrl.action_update(); assert(calls[1] == "stop")
reset(); posted = {token = "test-csrf-token", action = "save", username = "changed", password = "", enabled = "1"}
ctrl.action_update(); assert(calls[1] == "enable" and #calls == 1)
local viewstate = renders[#renders].state
assert(viewstate.username == "changed" and viewstate.password == nil)

-- Execute the Lua template fragments and check escaping and password omission.
local f = assert(io.open(base .. "/root/usr/lib/lua/luci/view/minieap_sysu/index.htm"))
local template = f:read("*a"); f:close()
local fragments, pos = {}, 1
while true do
    local a, b, body = template:find("<%%(.-)%%>", pos)
    if not a then fragments[#fragments + 1] = "out(" .. string.format("%q", template:sub(pos)) .. ")"; break end
    fragments[#fragments + 1] = "out(" .. string.format("%q", template:sub(pos, a - 1)) .. ")"
    if body:sub(1, 1) == "=" then fragments[#fragments + 1] = "out(" .. body:sub(2) .. ")"
    elseif body:sub(1, 1) ~= "+" then fragments[#fragments + 1] = body end
    pos = b + 1
end
local output = {}
local fn = assert(loadstring(table.concat(fragments, "\n")))
viewstate.username = '\"><script>alert(1)</script>'
setfenv(fn, setmetatable({
    state = viewstate, token = "test-csrf-token", message = "Saved", error_message = nil,
    out = function(s) output[#output + 1] = tostring(s or "") end
}, {__index = _G}))
fn()
local html = table.concat(output)
assert(not html:find("<script>", 1, true))
assert(html:find("&lt;script&gt;", 1, true))
assert(not html:find("old$!", 1, true))
assert(html:find('name="password"', 1, true) and html:find('value="" placeholder=', 1, true))
print("PASS: Lua 5.1 model/controller/template; secret retention and escaping; 0600 atomic backup/write; partial writes; failure preservation; input validation; POST+CSRF; action allowlist; save does not restart service.")
