module("luci.controller.minieap_sysu", package.seeall)

function index()
    local page = entry({"admin", "services", "minieap_sysu"}, call("action_index"), "校园网认证", 65)
    page.dependent = false
    page.sysauth = "root"
    page.sysauth_authenticator = "htmlauth"
    entry({"admin", "services", "minieap_sysu", "update"}, post("action_update")).leaf = true
end

local function render(message, error_message)
    local http = require "luci.http"
    local dispatcher = require "luci.dispatcher"
    http.header("Cache-Control", "no-store")
    require("luci.template").render("minieap_sysu/index", {
        state = require("luci.model.minieap_sysu").status(),
        token = dispatcher.context.authtoken,
        message = message,
        error_message = error_message
    })
end

function action_index()
    render()
end

function action_update()
    local dispatcher = require "luci.dispatcher"
    if not dispatcher.test_post_security() then return end
    local http = require "luci.http"
    local model = require "luci.model.minieap_sysu"
    local action = http.formvalue("action")
    local ok, message
    if action == "save" then
        ok, message = model.save(http.formvalue("username"), http.formvalue("password") or "",
                                 http.formvalue("enabled") == "1")
    else
        ok, message = model.action(action)
    end
    if ok then render(message) else render(nil, message) end
end
