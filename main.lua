--[[--
Kindle-style pins for KOReader: save selected text or images and
browse them without leaving the current page.

@module koplugin.KindlePin
--]]--

local ConfirmBox = require("ui/widget/confirmbox")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local ImageViewerHook = require("imageviewer_hook")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local PinDialog = require("pindialog")
local PinStore = require("pinstore")
local PinText = require("pintext")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local KindlePin = WidgetContainer:extend{
    name = "kindlepin",
    is_doc_only = true,
}

function KindlePin.getActive()
    return KindlePin._active
end

local function cleanText(text)
    if not text or text == "" then
        return ""
    end
    if util.cleanupSelectedText then
        return util.cleanupSelectedText(text)
    end
    return text:gsub("\n+", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
end

local function writeImage(image, path)
    if not image then
        return false, "no image"
    end
    local bb = image
    if type(image) == "table" then
        bb = image[1]
        if type(bb) == "function" then
            bb = bb()
        end
    elseif type(image) == "function" then
        bb = image(1)
    end
    if not bb or not bb.writePNG then
        return false, "unsupported image"
    end
    local ok, err = pcall(function()
        bb:writePNG(path)
    end)
    if not ok then
        ok, err = pcall(function()
            bb:writePNG(path, true)
        end)
    end
    if not ok then
        return false, err
    end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") ~= "file" then
        return false, "png not written"
    end
    return true
end

function KindlePin:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindlepin_show", {
        category = "none",
        event = "KindlePinShow",
        title = _("Показать закрепления"),
        reader = true,
    })
    Dispatcher:registerAction("kindlepin_pin_selection", {
        category = "none",
        event = "KindlePinSelection",
        title = _("Закрепить выделение"),
        reader = true,
    })
end

function KindlePin:init()
    KindlePin._active = self
    self.store = PinStore:new()
    ImageViewerHook.install(KindlePin.getActive)
    self:onDispatcherRegisterActions()
    if self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui.highlight and self.ui.highlight.addToHighlightDialog then
        self:registerHighlightButton()
    end
end

function KindlePin:onCloseWidget()
    if KindlePin._active == self then
        KindlePin._active = nil
    end
    if self.store then
        self.store:flush()
    end
end

function KindlePin:onFlushSettings()
    if self.store then
        self.store:flush()
    end
end

function KindlePin:docPath()
    return self.ui.document and self.ui.document.file
end

function KindlePin:listPins()
    return self.store:listForViewer(self:docPath())
end

function KindlePin:bookName(path)
    return path and path:match("([^/]+)$") or _("Неизвестная книга")
end

function KindlePin:linkBook(path)
    if self.store:addLink(self:docPath(), path) then
        UIManager:show(Notification:new{
            text = T(_("Связаны закрепления: %1"), self:bookName(path)),
        })
    end
end

function KindlePin:chooseLinkedBook()
    local PathChooser = require("ui/widget/pathchooser")
    local DocumentRegistry = require("document/documentregistry")
    UIManager:show(PathChooser:new{
        title = _("Удерживайте файл книги для добавления связи"),
        path = self:docPath():match("^(.*)/") or ".",
        select_directory = false,
        select_file = true,
        file_filter = function(path)
            return DocumentRegistry:hasProvider(path)
        end,
        onConfirm = function(path)
            if path == self:docPath() then
                UIManager:show(InfoMessage:new{ text = _("Книгу нельзя связать с самой собой.") })
                return
            end
            self:linkBook(path)
        end,
    })
end

function KindlePin:linkCandidates()
    local excluded = { [self:docPath()] = true }
    for _, path in ipairs(self.store:getLinkedBooks(self:docPath())) do excluded[path] = true end
    local items = {}
    for i, path in ipairs(self.store:listBooksWithPins()) do
        if not excluded[path] then
            local source_path = path
            items[#items + 1] = {
                text = T(_("%1 (%2)"), self:bookName(path), self.store:count(path)),
                help_text = path,
                callback = function() self:linkBook(source_path) end,
            }
        end
    end
    if #items == 0 then
        items[1] = { text = _("Нет других книг с закреплениями"), enabled = false }
    end
    return items
end

function KindlePin:linkedBooksMenu()
    local items = {
        { text = _("Связи действуют только из этой книги"), enabled = false },
        {
            text = _("Добавить книгу с закреплениями"),
            sub_item_table_func = function() return self:linkCandidates() end,
        },
        {
            text = _("Выбрать файл книги…"),
            callback = function() self:chooseLinkedBook() end,
        },
    }
    for i, path in ipairs(self.store:getLinkedBooks(self:docPath())) do
        local source_path = path
        items[#items + 1] = {
            text = T(_("%1 (%2)"), self:bookName(path), self.store:count(path)),
            sub_item_table = {
                { text = path, enabled = false },
                {
                    text = _("Убрать связь"),
                    callback = function()
                        self.store:removeLink(self:docPath(), source_path)
                        UIManager:show(Notification:new{ text = _("Связь удалена. Закрепления сохранены.") })
                    end,
                },
            },
        }
    end
    return items
end

function KindlePin:registerHighlightButton()
    self.ui.highlight:addToHighlightDialog("12_kindlepin", function(reader_highlight)
        return {
            text = _("Закрепить"),
            enabled = true,
            show_in_highlight_dialog_func = function()
                local sel = reader_highlight.selected_text
                return sel and sel.text and cleanText(sel.text) ~= ""
            end,
            callback = function()
                self:pinFromHighlight(reader_highlight)
                reader_highlight:onClose()
            end,
        }
    end)
end

function KindlePin:pageFromHighlight(reader_highlight, selected)
    if reader_highlight.hold_pos and reader_highlight.hold_pos.page then
        return reader_highlight.hold_pos.page
    end
    if selected and type(selected.pos0) == "table" and selected.pos0.page then
        return selected.pos0.page
    end
    if self.ui.getCurrentPage then
        return self.ui:getCurrentPage()
    end
end

function KindlePin:currentLocation()
    local loc = {}
    if self.ui.getCurrentPage then
        loc.page = self.ui:getCurrentPage()
    end
    if self.ui.document and self.ui.document.getXPointer then
        local ok, xp = pcall(function()
            return self.ui.document:getXPointer()
        end)
        if ok and type(xp) == "string" then
            loc.xpointer = xp
        end
    end
    return loc
end

function KindlePin:pinFromHighlight(reader_highlight)
    local selected = reader_highlight.selected_text
    if not selected then
        return
    end
    local text = cleanText(selected.text)
    if text == "" then
        UIManager:show(InfoMessage:new{
            text = _("Нет текста для закрепления."),
        })
        return
    end
    local loc = self:currentLocation()
    local pin = {
        type = "text",
        text = text,
        page = self:pageFromHighlight(reader_highlight, selected) or loc.page,
        xpointer = type(selected.pos0) == "string" and selected.pos0 or loc.xpointer,
        pos0 = selected.pos0,
        pos1 = selected.pos1,
        pboxes = selected.pboxes,
        sboxes = selected.sboxes,
    }
    local formatted = PinText.capture(self.ui.document, selected)
    if formatted then
        pin.html = formatted.html
        pin.css = formatted.css
    end
    self.store:add(self:docPath(), pin)
    UIManager:show(Notification:new{
        text = _("Закреплено"),
    })
end

function KindlePin:pinFromImageViewer(viewer)
    local doc_path = self:docPath()
    if not doc_path then
        return
    end
    local id = self.store:nextId()
    local path = self.store:imagePath(doc_path, id)
    local image = viewer._scaled_image_func or viewer.image
    local ok, err = writeImage(image, path)
    if not ok then
        logger.warn("kindlepin: failed to save image", err)
        UIManager:show(InfoMessage:new{
            text = _("Не удалось сохранить изображение."),
        })
        return
    end
    local loc = self:currentLocation()
    self.store:add(doc_path, {
        id = id,
        type = "image",
        text = _("Изображение"),
        image_file = path,
        page = loc.page,
        xpointer = loc.xpointer,
    })
    UIManager:show(Notification:new{
        text = _("Изображение закреплено"),
    })
end

function KindlePin:deletePin(pin)
    self.store:delete(pin.doc_path or self:docPath(), pin.id)
end

local function jumpToPin(ui, pin)
    local function tryJump(fn)
        local ok, result = pcall(fn)
        return ok and result ~= false
    end
    local jumped = false
    if pin.xpointer and ui.rolling and ui.rolling.onGotoXPointer then
        local valid = true
        if ui.document.isXPointerInDocument then
            local ok, found = pcall(ui.document.isXPointerInDocument, ui.document, pin.xpointer)
            valid = ok and found
        end
        if valid then
            jumped = tryJump(function()
                return ui.rolling:onGotoXPointer(pin.xpointer, pin.xpointer)
            end)
        end
    end
    if not jumped and pin.page then
        if ui.paging and ui.paging.onGotoPage then
            jumped = tryJump(function() return ui.paging:onGotoPage(pin.page) end)
        elseif ui.rolling and ui.rolling.onGotoPage then
            jumped = tryJump(function() return ui.rolling:onGotoPage(pin.page) end)
        elseif ui.handleEvent then
            jumped = tryJump(function() return ui:handleEvent(Event:new("GotoPage", pin.page)) end)
        end
    end
    if jumped and pin.pboxes and ui.view and ui.view.highlight and pin.page then
        ui.view.highlight.temp[pin.page] = pin.pboxes
        UIManager:setDirty(ui, "ui")
    end
    if not jumped then
        UIManager:show(InfoMessage:new{ text = _("Не удалось перейти к фрагменту.") })
    end
end

function KindlePin:goToPinLocation(pin)
    if not pin then return end
    UIManager:nextTick(function()
        local source_path = pin.doc_path or self:docPath()
        if source_path ~= self:docPath() then
            -- Read stored pins even if the source was moved, but don't close the
            -- current reader when an unavailable source cannot be opened.
            local DocumentRegistry = require("document/documentregistry")
            if lfs.attributes(source_path, "mode") ~= "file"
                or not DocumentRegistry:hasProvider(source_path) or not self.ui.switchDocument
            then
                UIManager:show(InfoMessage:new{
                    text = T(_("Не удалось открыть книгу закрепления:\n%1"), source_path),
                })
                return
            end
            self.ui:switchDocument(source_path, nil, function(reader)
                jumpToPin(reader, pin)
            end)
        else
            jumpToPin(self.ui, pin)
        end
    end)
end

function KindlePin:showPins()
    local pins = self:listPins()
    if #pins == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Пока нет закреплений в этой книге и связанных книгах.\nВыделите текст и нажмите «Закрепить», либо закрепите изображение из просмотрщика."),
        })
        return
    end
    -- Defer until after the triggering gesture/menu refresh, otherwise the
    -- reader can repaint through the viewer on e-ink.
    UIManager:nextTick(function()
        UIManager:show(PinDialog:new{
            pins = pins,
            index = 1,
            plugin = self,
        })
    end)
end

function KindlePin:onKindlePinShow()
    self:showPins()
    return true
end

function KindlePin:onKindlePinSelection()
    if self.ui.highlight then
        self:pinFromHighlight(self.ui.highlight)
        return true
    end
end

function KindlePin:addToMainMenu(menu_items)
    menu_items.kindlepin = {
        text = _("Закрепления"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    local n = self.store:countVisible(self:docPath())
                    if n > 0 then
                        return T(_("Просмотреть закрепления (%1)"), n)
                    end
                    return _("Просмотреть закрепления")
                end,
                enabled_func = function()
                    return self.store:countVisible(self:docPath()) > 0
                end,
                callback = function()
                    self:showPins()
                end,
            },
            {
                text_func = function()
                    return T(_("Связанные книги (%1)"), #self.store:getLinkedBooks(self:docPath()))
                end,
                sub_item_table_func = function() return self:linkedBooksMenu() end,
            },
            {
                text = _("Удалить все закрепления книги"),
                enabled_func = function()
                    return self.store:count(self:docPath()) > 0
                end,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Удалить все закрепления в этой книге?"),
                        ok_text = _("Удалить"),
                        ok_callback = function()
                            self.store:deleteAll(self:docPath())
                            UIManager:show(Notification:new{
                                text = _("Закрепления удалены"),
                            })
                        end,
                    })
                end,
            },
        },
    }
end

return KindlePin
