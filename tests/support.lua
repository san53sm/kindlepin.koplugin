-- Small test doubles for KOReader services. The tests run in plain Lua 5.1.
local Support = { shown = {}, files = {}, settings_files = {} }
local Widget = {}
function Widget:extend(options)
    options = options or {}
    options.__index = options
    return setmetatable(options, { __index = self })
end
function Widget:new(options)
    return setmetatable(options or {}, { __index = self })
end
function Support.instance(class, options)
    return setmetatable(options or {}, { __index = class })
end
function Support.stub(name, value)
    package.loaded[name] = value
end
function Support.reset()
    Support.shown = {}
    Support.files = {}
    Support.settings_files = {}
end
for _, name in ipairs({
    "ui/widget/confirmbox", "ui/widget/infomessage", "ui/widget/notification",
    "ui/widget/container/widgetcontainer", "ui/widget/container/inputcontainer",
    "ui/widget/focusmanager", "ui/widget/buttontable", "ui/widget/imageviewer",
    "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
    "ui/geometry", "ui/gesturerange", "ui/widget/imagewidget",
    "ui/widget/scrolltextwidget", "ui/widget/scrollhtmlwidget",
    "ui/widget/titlebar", "ui/widget/verticalgroup", "ui/widget/verticalspan",
    "ui/widget/menu", "ui/widget/pathchooser",
}) do
    Support.stub(name, Widget:extend{})
end
Support.stub("logger", { dbg = function() end, warn = function() end })
Support.stub("gettext", function(text) return text end)
Support.stub("ffi/util", { template = function(text, ...)
    local args = {...}
    return (text:gsub("%%(%d+)", function(n) return tostring(args[tonumber(n)]) end))
end })
Support.stub("util", { cleanupSelectedText = function(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end })
Support.stub("dispatcher", { registerAction = function() end })
Support.stub("ui/event", Widget)
Support.stub("ui/bidi", { mirroredUILayout = function() return false end })
Support.stub("ffi/blitbuffer", { COLOR_WHITE = 0 })
Support.stub("ui/size", { padding = { small = 2, default = 5, large = 10 } })
Support.stub("device", { screen = { getWidth = function() return 600 end,
    getHeight = function() return 800 end } })
Support.stub("ui/font", { getFace = function() return { size = 20 } end })
Support.stub("ui/uimanager", {
    show = function(_, widget) Support.shown[#Support.shown + 1] = widget end,
    close = function() end,
    nextTick = function(_, callback) callback() end,
    setDirty = function() end,
})
Support.stub("libs/libkoreader-lfs", { attributes = function(path, attribute)
    if attribute == "mode" then return Support.files[path] end
end })
Support.stub("datastorage", { getSettingsDir = function() return "/test/settings" end })
Support.stub("document/documentregistry", { hasProvider = function(_, path)
    return path:match("%.epub$") or path:match("%.fb2$") or path:match("%.pdf$")
end })
Support.stub("luasettings", { open = function(_, path)
    if not Support.settings_files[path] then Support.settings_files[path] = {} end
    return {
        data = Support.settings_files[path],
        readSetting = function(self, key) return self.data[key] end,
        saveSetting = function(self, key, value) self.data[key] = value end,
        delSetting = function(self, key) self.data[key] = nil end,
        flush = function() end,
    }
end })
return Support
