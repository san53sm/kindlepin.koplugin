local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FocusManager = require("ui/widget/focusmanager")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local PinText = require("pintext")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local ImageTapCatcher = InputContainer:extend{}

function ImageTapCatcher:onTap(_, ges)
    if self.dimen and ges.pos:intersectWith(self.dimen) then
        if self.callback then
            self.callback()
        end
        return true
    end
end

local PinDialog = FocusManager:extend{
    pins = nil,
    index = 1,
    plugin = nil,
}

local function formatWhen(ts)
    if not ts then
        return ""
    end
    return os.date("%Y-%m-%d %H:%M", ts)
end

function PinDialog:init()
    -- Fullscreen page: gestures otherwise refresh the book through a floating dialog.
    self.covers_fullscreen = true
    self.align = "center"
    self.pins = self.pins or {}
    self.index = self.index or 1
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            ShowPrev = { { Device.input.group.PgBack } },
            ShowNext = { { Device.input.group.PgFwd } },
        }
        if Device:hasScreenKB() or Device:hasKeyboard() then
            local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
            self.key_events.ShowPrev = { { modifier, Device.input.group.PgBack } }
            self.key_events.ShowNext = { { modifier, Device.input.group.PgFwd } }
            self.key_events.ScrollUp = { { Device.input.group.PgBack } }
            self.key_events.ScrollDown = { { Device.input.group.PgFwd } }
        end
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            SwipeNav = {
                GestureRange:new{ ges = "swipe", range = range },
            },
        }
    end
    self:buildLayout()
end

function PinDialog:currentPin()
    return self.pins[self.index]
end

function PinDialog:freeContent()
    if self._image_wg and self._image_wg.free then
        self._image_wg:free()
    end
    self._image_wg = nil
    if self._scroll_wg and self._scroll_wg.free then
        self._scroll_wg:free()
    end
    self._scroll_wg = nil
end

function PinDialog:buildLayout()
    self:freeContent()

    local pin = self:currentPin()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.width = screen_w
    self.height = screen_h
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = screen_w,
        h = screen_h,
    }

    local total = #self.pins
    local title = T(_("Закрепление %1 из %2"), self.index, total)
    local subtitle_parts = {}
    if pin then
        if pin.doc_path and self.plugin then
            subtitle_parts[#subtitle_parts + 1] = self.plugin:bookName(pin.doc_path)
        end
        if pin.type == "image" then
            subtitle_parts[#subtitle_parts + 1] = _("изображение")
        else
            subtitle_parts[#subtitle_parts + 1] = _("текст")
        end
        if pin.page then
            subtitle_parts[#subtitle_parts + 1] = T(_("стр. %1"), pin.page)
        end
        local when = formatWhen(pin.created_at)
        if when ~= "" then
            subtitle_parts[#subtitle_parts + 1] = when
        end
    end

    self.title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        title = title,
        subtitle = table.concat(subtitle_parts, " · "),
        with_bottom_line = true,
        close_callback = function()
            self:onClose()
        end,
        show_parent = self,
    }

    local is_image = pin and pin.type == "image"
    local buttons = {
        {
            {
                text = _("Пред."),
                enabled = self.index > 1,
                callback = function()
                    self:showAt(self.index - 1)
                end,
            },
            {
                text = _("След."),
                enabled = self.index < total,
                callback = function()
                    self:showAt(self.index + 1)
                end,
            },
        },
        {
            {
                text = _("К фрагменту"),
                enabled = pin ~= nil,
                callback = function()
                    self:goToLocation()
                end,
            },
            {
                text = _("На весь экран"),
                enabled = is_image and pin and pin.image_file
                    and lfs.attributes(pin.image_file, "mode") == "file",
                callback = function()
                    self:openFullscreen()
                end,
            },
        },
        {
            {
                text = _("Удалить"),
                enabled = pin ~= nil,
                callback = function()
                    self:confirmDelete()
                end,
            },
            {
                text = _("Закрыть"),
                callback = function()
                    self:onClose()
                end,
            },
        },
    }

    self.button_table = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local content_padding = Size.padding.large
    local button_gap = Size.padding.small
    local bottom_padding = Size.padding.large
    -- Account for both sides of the content frame and the footer spacing.
    -- FrameContainer's fixed height does not clip an oversized child group.
    local content_h = self.height
        - self.title_bar:getHeight()
        - self.button_table:getSize().h
        - 2 * content_padding
        - button_gap
        - bottom_padding
    local content_w = self.width - 2 * content_padding

    local content_widget
    if is_image then
        content_widget = self:buildImageContent(pin, content_w, content_h)
    else
        content_widget = self:buildTextContent(pin, content_w, content_h)
    end

    local content_frame = FrameContainer:new{
        padding = content_padding,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = content_h },
            content_widget,
        },
    }

    local dialog_inner = VerticalGroup:new{
        align = "left",
        self.title_bar,
        content_frame,
        VerticalSpan:new{ width = button_gap },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = self.button_table:getSize().h,
            },
            self.button_table,
        },
        VerticalSpan:new{ width = bottom_padding },
    }

    self.dialog_frame = FrameContainer:new{
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = screen_w,
        height = screen_h,
        dialog_inner,
    }
    self[1] = self.dialog_frame

    if self.button_table.layout then
        self.layout = self.button_table.layout
        if self.moveFocusTo then
            self:moveFocusTo(1, 1)
        end
    end
end

function PinDialog:buildTextContent(pin, width, height)
    if pin and type(pin.html) == "string" and pin.html ~= "" then
        -- Older KOReader builds may lack this widget. Keep plain text usable.
        local ok, widget = pcall(function()
            local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
            return ScrollHtmlWidget:new{
                html_body = pin.html,
                css = PinText.stylesheet(pin),
                is_xhtml = true, -- FB2 title/poem/etc. must be parsed as XML.
                default_font_size = Font:getFace("x_smallinfofont").size,
                width = width,
                height = height,
                dialog = self,
            }
        end)
        if ok then
            self._scroll_wg = widget
            return widget
        end
        logger.warn("kindlepin: HTML rendering failed, using plain text", widget)
    end
    local text = (pin and pin.text) or _("(пусто)")
    self._scroll_wg = ScrollTextWidget:new{
        text = text,
        face = Font:getFace("x_smallinfofont"),
        width = width,
        height = height,
        dialog = self,
        alignment = "left",
        justified = true,
        auto_para_direction = true,
        scroll_by_pan = true,
    }
    return self._scroll_wg
end

function PinDialog:buildImageContent(pin, width, height)
    local path = pin and pin.image_file
    if not path or lfs.attributes(path, "mode") ~= "file" then
        self._scroll_wg = ScrollTextWidget:new{
            text = _("Изображение недоступно."),
            face = Font:getFace("x_smallinfofont"),
            width = width,
            height = height,
            dialog = self,
        }
        return self._scroll_wg
    end
    self._image_wg = ImageWidget:new{
        file = path,
        width = width,
        height = height,
        scale_factor = 0,
        alpha = false,
    }
    local catcher = ImageTapCatcher:new{
        callback = function()
            self:openFullscreen()
        end,
    }
    catcher[1] = self._image_wg
    catcher.dimen = Geom:new{ w = width, h = height }
    if Device:isTouchDevice() then
        catcher.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = function()
                        return catcher.dimen
                    end,
                },
            },
        }
    end
    return catcher
end

function PinDialog:rebuild()
    self:buildLayout()
    UIManager:setDirty(self, "ui")
end

function PinDialog:showAt(index)
    if index < 1 or index > #self.pins then
        return
    end
    self.index = index
    self:rebuild()
end

function PinDialog:onShowPrev()
    self:showAt(self.index - 1)
    return true
end

function PinDialog:onShowNext()
    self:showAt(self.index + 1)
    return true
end

function PinDialog:onScrollUp()
    if self._scroll_wg and self._scroll_wg.onScrollUp then
        self._scroll_wg:onScrollUp()
        return true
    end
    return self:onShowPrev()
end

function PinDialog:onScrollDown()
    if self._scroll_wg and self._scroll_wg.onScrollDown then
        self._scroll_wg:onScrollDown()
        return true
    end
    return self:onShowNext()
end

function PinDialog:onSwipeNav(_, ges)
    if not ges or not ges.direction then
        return false
    end
    if ges.direction == "west" then
        if BD.mirroredUILayout() then
            self:onShowPrev()
        else
            self:onShowNext()
        end
        return true
    elseif ges.direction == "east" then
        if BD.mirroredUILayout() then
            self:onShowNext()
        else
            self:onShowPrev()
        end
        return true
    end
    -- north/south are handled by ScrollTextWidget when present
    return false
end

function PinDialog:onShow()
    UIManager:setDirty(self, "full")
    return true
end

function PinDialog:openFullscreen()
    local pin = self:currentPin()
    if not pin or pin.type ~= "image" or not pin.image_file then
        return
    end
    if lfs.attributes(pin.image_file, "mode") ~= "file" then
        return
    end
    local ImageViewer = require("ui/widget/imageviewer")
    UIManager:show(ImageViewer:new{
        file = pin.image_file,
        image_disposable = false,
        with_title_bar = true,
        title_text = _("Закреплённое изображение"),
        fullscreen = true,
        buttons_visible = true,
    })
end

function PinDialog:goToLocation()
    local pin = self:currentPin()
    local plugin = self.plugin
    self:onClose()
    if plugin and pin then
        plugin:goToPinLocation(pin)
    end
end

function PinDialog:confirmDelete()
    local pin = self:currentPin()
    if not pin then
        return
    end
    local text = _("Удалить это закрепление?")
    if self.plugin and pin.doc_path and pin.doc_path ~= self.plugin:docPath() then
        text = T(_("Удалить это закрепление из связанной книги?\n%1\n\nОно исчезнет и при просмотре исходной книги."), pin.doc_path)
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Удалить"),
        ok_callback = function()
            self:deleteCurrent()
        end,
    })
end

function PinDialog:deleteCurrent()
    local pin = self:currentPin()
    if not pin or not self.plugin then
        return
    end
    self.plugin:deletePin(pin)
    self.pins = self.plugin:listPins()
    if #self.pins == 0 then
        self:onClose()
        return
    end
    if self.index > #self.pins then
        self.index = #self.pins
    end
    self:rebuild()
end

function PinDialog:onClose()
    UIManager:close(self)
    return true
end

function PinDialog:onCloseWidget()
    self:freeContent()
    UIManager:setDirty(nil, "full")
end

return PinDialog
