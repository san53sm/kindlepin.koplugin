-- Geometry/paint service doubles for the popup tests; no native GUI required.
local support = require("support")
local screen = package.loaded.device.screen
local Frame = package.loaded["ui/widget/container/framecontainer"]
function Frame:getSize()
    local size = self[1]:getSize()
    local pad = 2 * ((self.padding or 0) + (self.margin or 0) + (self.bordersize or 0))
    return { w = size.w + pad, h = size.h + pad }
end
function Frame:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = { x = x, y = y, w = size.w, h = size.h }
    if self.background ~= nil then
        bb.painted[#bb.painted + 1] = { x = x, y = y,
            w = self.width or size.w, h = self.height or size.h, color = self.background }
    end
    local inset = (self.padding or 0) + (self.bordersize or 0) + (self.margin or 0)
    self[1]:paintTo(bb, x + inset, y + inset)
end
for _, kind in ipairs({ "horizontal", "vertical" }) do
    local group = package.loaded["ui/widget/" .. kind .. "group"]
    function group:getSize()
        local width, height = 0, 0
        for _, child in ipairs(self) do
            local size = child:getSize()
            if kind == "horizontal" then width = width + size.w; height = math.max(height, size.h)
            else width = math.max(width, size.w); height = height + size.h end
        end
        return { w = width, h = height }
    end
    function group:paintTo(bb, x, y)
        for _, child in ipairs(self) do
            child:paintTo(bb, x, y)
            local size = child:getSize()
            if kind == "horizontal" then x = x + size.w else y = y + size.h end
        end
    end
end
package.loaded["ui/widget/verticalspan"].getSize = function(self) return { w = 0, h = self.width } end
package.loaded["ui/widget/horizontalspan"].getSize = function(self) return { w = self.width, h = 0 } end
package.loaded["ui/widget/textwidget"].getSize = function(self)
    return { w = math.min(self.max_width or 500, #self.text * self.face.size / 2), h = self.face.size * 1.2 }
end
function support.screenSize(width, height)
    screen.width, screen.height = width, height
end
function support.framebuffer(contents)
    local bb = { contents = contents, painted = {} }
    function bb:copy()
        support.copied_contents = self.contents
        return { contents = self.contents, free = function(self) self.freed = true end }
    end
    function bb:blitFrom(source, x, y, sx, sy, width, height)
        self.restored = { contents = source.contents, x = x, y = y, w = width, h = height }
    end
    screen.bb = bb
    return bb
end
function support.tick()
    local tasks = support.tasks
    support.tasks = {}
    for _, task in ipairs(tasks) do
        task.ticks = task.ticks - 1
        if task.ticks == 0 then task.callback()
        else support.tasks[#support.tasks + 1] = task end
    end
end
return support
