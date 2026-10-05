-- Small test doubles for KOReader services. The tests run in plain Lua 5.1.
local Support = { shown = {}, files = {}, settings_files = {}, closed = {}, dirty = {}, tasks = {} }
local Widget = {}
function Widget:extend(options)
    options = options or {}
    options.__index = options
    return setmetatable(options, { __index = self })
end
function Widget:new(options)
    return setmetatable(options or {}, { __index = self })
end
function Widget:getSize()
    return self.dimen or { w = self.width or 20, h = self.height or 20 }
end
function Widget:getHeight() return self:getSize().h end
function Widget:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = { x = x, y = y, w = size.w, h = size.h }
    for _, child in ipairs(self) do child:paintTo(bb, x, y) end
end
function Widget:moveFocusTo() end
function Widget:onKeyPress() Support.key_calls = (Support.key_calls or 0) + 1 end
function Widget:onGesture() Support.gesture_calls = (Support.gesture_calls or 0) + 1 end
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
    Support.closed, Support.dirty, Support.tasks = {}, {}, {}
    Support.defer = false
    Support.key_calls, Support.gesture_calls = 0, 0
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
    "ui/widget/button", "ui/widget/buttondialog", "ui/widget/horizontalgroup",
    "ui/widget/horizontalspan", "ui/widget/linewidget", "ui/widget/textwidget",
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
Support.stub("ffi/blitbuffer", { COLOR_WHITE = 0, COLOR_BLACK = 1 })
Support.stub("ui/size", { padding = { small = 2, default = 5, large = 10, buttontable = 4 },
    border = { window = 1.5 }, line = { thin = 1 } })
Support.stub("device", { screen = { width = 600, height = 800,
    getWidth = function(self) return self.width end,
    getHeight = function(self) return self.height end,
    scaleBySize = function(_, size) return size end,
}, hasKeys = function() return false end, isTouchDevice = function() return true end })
Support.stub("ui/font", { getFace = function(_, name, size, index)
    size = size or 20
    return { size = package.loaded.device.screen:scaleBySize(size), orig_size = size,
        orig_font = name, faceindex = index or 0 }
end })
Support.stub("ui/uimanager", {
    show = function(_, widget) Support.shown[#Support.shown + 1] = widget end,
    close = function(_, widget)
        Support.closed[#Support.closed + 1] = widget
        if widget.onCloseWidget then widget:onCloseWidget() end
    end,
    nextTick = function(_, callback) callback() end,
    tickAfterNext = function(_, callback)
        if Support.defer then Support.tasks[#Support.tasks + 1] = { callback = callback, ticks = 2 }
        else callback() end
    end,
    setDirty = function(_, widget, refresh, region)
        Support.dirty[#Support.dirty + 1] = { widget = widget, refresh = refresh, region = region }
    end,
})
Support.stub("libs/libkoreader-lfs", { attributes = function(path, attribute)
    if attribute == "mode" then return Support.files[path] end
end, currentdir = function() return "/koreader" end })
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
