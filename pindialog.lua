local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FocusManager = require("ui/widget/focusmanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local PinText = require("pintext")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local TextWidget = require("ui/widget/textwidget")
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
    popup = false,
}

local function formatWhen(ts)
    if not ts then
        return ""
    end
    return os.date("%Y-%m-%d %H:%M", ts)
end

function PinDialog:init()
    if self.popup then self:captureBackground() end
    -- Popup mode paints a frozen full-screen book background, then an opaque
    -- panel. It really covers the framebuffer, so late reader paints are hidden.
    self.covers_fullscreen = true
    self.stop_events_propagation = true
    self.align = "center"
    self.pins = self.pins or {}
    self.index = self.index or 1
    if Device:hasKeys() then
        -- Keep FocusManager's D-pad bindings so the popup menu and close
        -- controls remain reachable on Kindle models without a touchscreen.
        self.key_events = self.key_events or {}
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.ShowPrev = { { Device.input.group.PgBack } }
        self.key_events.ShowNext = { { Device.input.group.PgFwd } }
        if Device:hasScreenKB() or Device:hasKeyboard() then
            local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
            self.key_events.ShowPrev = { { modifier, Device.input.group.PgBack } }
            self.key_events.ShowNext = { { modifier, Device.input.group.PgFwd } }
            self.key_events.ScrollUp = { { Device.input.group.PgBack } }
            self.key_events.ScrollDown = { { Device.input.group.PgFwd } }
        end
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            SwipeNav = {
                GestureRange:new{ ges = "swipe", range = function()
                    return self.popup and self.panel_dimen or self.dimen
                end },
            },
        }
    end
    self:buildLayout()
end

function PinDialog:freeBackground()
    if self._background_bb then self._background_bb:free() end
    self._background_bb = nil
end

function PinDialog:captureBackground()
    self:freeBackground()
    local ok, background = pcall(function() return Screen.bb:copy() end)
    if ok and background then
        self._background_bb = background
    else
        -- Never show a supposedly opaque popup without a valid background.
        logger.warn("kindlepin: cannot capture screen, using fullscreen viewer", background)
        self.popup = false
    end
end

function PinDialog:paintTo(bb, x, y)
    if self.skip_paint then return end
    if not self.popup then return FocusManager.paintTo(self, bb, x, y) end
    bb:blitFrom(self._background_bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
    self.dialog_frame:paintTo(bb, x + self.panel_dimen.x, y + self.panel_dimen.y)
end

function PinDialog:onKeyPress(key)
    if self.skip_paint then return true end
    FocusManager.onKeyPress(self, key)
    return true
end
PinDialog.onKeyRepeat = PinDialog.onKeyPress

function PinDialog:onGesture(ges)
    if self.skip_paint then return true end
    -- Even gestures outside the panel are consumed. The page is a visual
    -- background, never an active reader while pins are shown.
    FocusManager.onGesture(self, ges)
    return true
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
    if self.popup then return self:buildPopupLayout(pin, screen_w, screen_h) end

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

function PinDialog:buildPopupLayout(pin, screen_w, screen_h)
    local margin = Size.padding.large
    local border = math.ceil(Size.border.window)
    local panel_w = math.min(screen_w - 2 * margin,
        math.max(math.floor(screen_w * 0.62), Screen:scaleBySize(260)))
    local panel_h = math.floor(screen_h * (screen_w > screen_h and 0.78 or 0.58))
    panel_h = math.min(panel_h, screen_h - 2 * margin)
    local inner_w = panel_w - 2 * border
    local control_w = Screen:scaleBySize(44)
    local gap = Size.padding.small
    local padding = Size.padding.default
    local metadata_w = inner_w - 2 * control_w
    if metadata_w < Screen:scaleBySize(100) then
        self.popup = false
        self:freeBackground()
        return self:buildLayout()
    end

    local function control(text, callback, enabled)
        return Button:new{
            text = text, width = control_w,
            bordersize = 0, margin = 0, padding = Size.padding.buttontable,
            enabled = enabled ~= false, callback = callback, show_parent = self,
        }
    end
    local menu_button = control("⋮", function() self:showActions() end)
    local close_button = control("∨", function() self:onClose() end)
    local header = HorizontalGroup:new{
        menu_button,
        HorizontalSpan:new{ width = inner_w - 2 * control_w },
        close_button,
    }
    local previous = control("‹", function() self:onShowPrev() end, self.index > 1)
    local next_pin = control("›", function() self:onShowNext() end, self.index < #self.pins)
    local source = pin and pin.page and T(_("стр. %1"), pin.page) or ""
    if pin and pin.doc_path and self.plugin then
        local name = self.plugin:bookName(pin.doc_path)
        source = source ~= "" and source .. " · " .. name or name
    end
    local metadata = VerticalGroup:new{
        TextWidget:new{
            text = T(_("Закрепление %1 из %2"), self.index, #self.pins),
            face = Font:getFace("xx_smallinfofont", 14), max_width = metadata_w,
        },
        TextWidget:new{
            text = source, face = Font:getFace("xx_smallinfofont", 12),
            max_width = metadata_w,
        },
    }
    local footer_h = math.max(metadata:getSize().h, previous:getSize().h, next_pin:getSize().h)
    local footer = HorizontalGroup:new{
        previous,
        CenterContainer:new{ dimen = Geom:new{ w = metadata_w, h = footer_h }, metadata },
        next_pin,
    }
    local line_h = Size.line.thin
    local content_h = panel_h - 2 * border - header:getSize().h - footer_h
        - 2 * line_h - 2 * padding - 2 * gap
    local content_w = inner_w - 2 * padding
    if content_h < Screen:scaleBySize(80) then
        self.popup = false
        self:freeBackground()
        return self:buildLayout()
    end
    self.panel_dimen = Geom:new{
        x = screen_w - margin - panel_w, y = screen_h - margin - panel_h,
        w = panel_w, h = panel_h,
    }
    local content = pin and pin.type == "image"
        and self:buildImageContent(pin, content_w, content_h)
        or self:buildTextContent(pin, content_w, content_h)
    local function line()
        return LineWidget:new{ dimen = Geom:new{ w = inner_w, h = line_h },
            background = Blitbuffer.COLOR_BLACK }
    end
    self.dialog_frame = FrameContainer:new{
        width = panel_w, height = panel_h, bordersize = border,
        padding = 0, margin = 0, radius = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            header, line(),
            FrameContainer:new{
                padding = padding, margin = 0, bordersize = 0,
                CenterContainer:new{ dimen = Geom:new{ w = content_w, h = content_h }, content },
            },
            line(), VerticalSpan:new{ width = gap }, footer,
            VerticalSpan:new{ width = gap },
        },
    }
    self[1] = self.dialog_frame
    self.layout = { { menu_button, close_button }, { previous, next_pin } }
    self:moveFocusTo(1, 1)
end

function PinDialog:showActions()
    local pin = self:currentPin()
    local can_expand = pin ~= nil and (pin.type ~= "image"
        or (pin.image_file and lfs.attributes(pin.image_file, "mode") == "file"))
    local actions
    local function action(callback)
        return function()
            UIManager:close(actions)
            callback()
        end
    end
    actions = ButtonDialog:new{
        title = T(_("Закрепление %1 из %2"), self.index, #self.pins),
        buttons = {
            { { text = _("К фрагменту"), enabled = pin ~= nil,
                callback = action(function() self:goToLocation() end) } },
            { { text = _("На весь экран"), enabled = can_expand,
                callback = action(function()
                    if pin.type == "image" then self:openFullscreen() else self:expandText() end
                end) } },
            { { text = _("Сведения"), callback = action(function()
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = table.concat({ pin and pin.doc_path or "",
                        pin and pin.page and T(_("стр. %1"), pin.page) or "",
                        formatWhen(pin and pin.created_at) }, "\n"),
                })
            end) } },
            { { text = _("Удалить"), enabled = pin ~= nil,
                callback = action(function() self:confirmDelete() end) } },
            { { text = _("Закрыть меню"), callback = function() UIManager:close(actions) end } },
        },
    }
    UIManager:show(actions)
end

function PinDialog:expandText()
    local pins, index, plugin = self.pins, self.index, self.plugin
    local document = plugin and plugin.ui.document
    self:onClose()
    UIManager:nextTick(function()
        if plugin and plugin.ui.document ~= document then return end
        local dialog = PinDialog:new{ pins = pins, index = index, plugin = plugin }
        if plugin then plugin._pin_dialog = dialog end
        UIManager:show(dialog)
    end)
end

function PinDialog:onScreenResize()
    if self._closed then return end
    if self.popup then
        -- A screen snapshot belongs to one orientation. Close it rather than
        -- capture an action menu or image viewer that may currently be on top.
        self:onClose()
    else
        self:buildLayout()
        UIManager:setDirty(self, "full")
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
    UIManager:setDirty(self, "ui", self.popup and self.panel_dimen or nil)
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
    if self.popup and (not ges.pos or not ges.pos:intersectWith(self.panel_dimen)) then
        return true
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
    self._closed = true
    self:freeContent()
    self:freeBackground()
    if self.plugin and self.plugin._pin_dialog == self then self.plugin._pin_dialog = nil end
    -- A snapshot may have hidden reader updates, so explicitly repaint it.
    UIManager:setDirty("all", "full")
end

return PinDialog
