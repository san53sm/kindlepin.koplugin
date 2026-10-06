return function(test, contains)
    local support = require("popup_support")
    local Store = require("pinstore")
    local Dialog = require("pindialog")
    local Plugin = require("main")
    local screen = package.loaded.device.screen
    local function pluginFor(store)
        return support.instance(Plugin, { store = store, ui = { document = { file = "book.epub" } } })
    end
    local function dialogFor(options)
        local dialog = support.instance(Dialog, options or {
            popup = true, pins = { { type = "text", text = "A long snippet", page = 3 } }, index = 1,
        })
        dialog:init()
        return dialog
    end
    local function position(x, y)
        return { x = x, y = y, intersectWith = function(self, rectangle)
            return self.x >= rectangle.x and self.x < rectangle.x + rectangle.w
                and self.y >= rectangle.y and self.y < rectangle.y + rectangle.h
        end }
    end
    local function realNew(callback)
        local saved = rawget(Dialog, "new")
        Dialog.new = function(_, options) return dialogFor(options) end
        callback()
        Dialog.new = saved
    end

    test("fullscreen is the default and viewer mode is persisted separately from pins", function()
        local store = Store:new()
        assert(store:getViewerMode() == "fullscreen")
        assert(store:setViewerMode("popup"))
        assert(Store:new():getViewerMode() == "popup")
        assert(not store:setViewerMode("invalid"))
        assert(store:getViewerMode() == "popup")
        assert(store:setViewerMode("fullscreen"))
        assert(store:getViewerMode() == "fullscreen")
        assert(store.settings.data.viewer_mode == nil and store.links.data.viewer_mode == nil)
    end)

    test("settings expose both viewer modes with mutually exclusive checkmarks", function()
        local store = Store:new()
        local menu = {}
        pluginFor(store):addToMainMenu(menu)
        local modes = menu.pin.sub_item_table[4]
        contains(modes.text_func(), "Fullscreen")
        assert(modes.sub_item_table[1].checked_func() and not modes.sub_item_table[2].checked_func())
        modes.sub_item_table[2].callback()
        contains(modes.text_func(), "Popup")
        assert(not modes.sub_item_table[1].checked_func() and modes.sub_item_table[2].checked_func())
    end)

    test("the default viewer paints the original fullscreen layout without allocating a snapshot", function()
        local bb = support.framebuffer("book")
        bb.copy = function() error("fullscreen must not copy the framebuffer") end
        local dialog = dialogFor({ pins = { { text = "pin" } } })
        assert(not dialog.popup and not dialog._background_bb and not dialog.panel_dimen)
        assert(dialog.button_table and dialog.title_bar)
        dialog:paintTo(bb, 0, 0)
        assert(not bb.restored)
        assert(bb.painted[1].w == 600 and bb.painted[1].h == 800)
        assert(bb.painted[1].color == package.loaded["ffi/blitbuffer"].COLOR_WHITE)
    end)

    test("menu and gesture openers wait for two ticks and capture the repainted book", function()
        for _, opener in ipairs({ "menu", "gesture" }) do
            support.reset()
            support.screenSize(600, 800)
            local bb = support.framebuffer("gesture inversion or menu")
            local store = Store:new()
            store:add("book.epub", { text = "pin" })
            store:setViewerMode("popup")
            local plugin = pluginFor(store)
            support.defer = true
            realNew(function()
                if opener == "gesture" then plugin:onPinShow()
                else
                    local menu = {}
                    plugin:addToMainMenu(menu)
                    menu.pin.sub_item_table[1].callback()
                end
                plugin:showPins() -- Repeated triggers must not stack dialogs.
                assert(#support.shown == 0 and #support.tasks == 1)
                support.tick()
                bb.contents = "clean book page"
                assert(#support.shown == 0)
                support.tick()
                local dialog = support.shown[1]
                assert(#support.shown == 1 and dialog.popup)
                assert(dialog._background_bb.contents == "clean book page")
                assert(plugin._pin_dialog == dialog)
                plugin:showPins()
                assert(#support.tasks == 0)
                dialog:onClose()
                assert(plugin._pin_dialog == nil)
            end)
        end
    end)

    test("a queued opener does not show pins after the reader changed documents", function()
        local store = Store:new()
        store:add("book.epub", { text = "pin" })
        local plugin = pluginFor(store)
        support.defer = true
        plugin:showPins()
        plugin.ui.document = { file = "other.epub" }
        support.tick(); support.tick()
        assert(#support.shown == 0 and not plugin._show_pins_pending)
    end)

    test("hardware controls keep FocusManager bindings and the reader close releases the popup", function()
        local device = package.loaded.device
        local has_keys = device.hasKeys
        device.hasKeys = function() return true end
        device.hasKeyboard = function() return false end
        device.hasScreenKB = function() return false end
        device.input = { group = { Back = { "Back" }, PgBack = { "PageBack" }, PgFwd = { "PageForward" } } }
        local focus = { { "Up" }, event = "FocusMove", args = { 0, -1 } }
        support.framebuffer("book")
        local plugin = pluginFor(Store:new())
        local dialog = dialogFor({ popup = true, pins = { { text = "pin" } }, plugin = plugin,
            key_events = { FocusUp = focus, Press = { { "Press" } } } })
        device.hasKeys = has_keys
        assert(dialog.key_events.FocusUp == focus and dialog.key_events.Press)
        assert(dialog.key_events.Close and dialog.key_events.ShowPrev and dialog.key_events.ShowNext)
        plugin._pin_dialog = dialog
        local background = dialog._background_bb
        plugin:onCloseDocument()
        assert(dialog._closed and background.freed and plugin._pin_dialog == nil)
    end)

    test("popup geometry fits portrait and landscape screens with bottom and right margins", function()
        for _, dimensions in ipairs({ {600, 800}, {1072, 1448}, {1448, 1072}, {800, 600} }) do
            support.screenSize(dimensions[1], dimensions[2])
            local bb = support.framebuffer("book")
            local dialog = dialogFor()
            assert(dialog.popup)
            local rectangle = dialog.panel_dimen
            local size = dialog.dialog_frame:getSize()
            assert(math.abs(size.w - rectangle.w) < 0.001 and math.abs(size.h - rectangle.h) < 0.001)
            assert(rectangle.x > 0 and rectangle.y > 0)
            assert(rectangle.x + rectangle.w == dimensions[1] - 10)
            assert(rectangle.y + rectangle.h == dimensions[2] - 10)
            assert(dialog._scroll_wg.width > 0 and dialog._scroll_wg.height >= 80)
            dialog:paintTo(bb, 0, 0)
            assert(bb.restored.contents == "book")
            local opaque = bb.painted[1]
            assert(opaque.color == package.loaded["ffi/blitbuffer"].COLOR_WHITE)
            assert(opaque.x == rectangle.x and opaque.y == rectangle.y)
            assert(opaque.w == rectangle.w and opaque.h == rectangle.h)
            dialog:onCloseWidget()
        end
        support.screenSize(600, 800)
    end)

    test("repainting restores frozen book pixels before painting the opaque popup", function()
        local bb = support.framebuffer("original book")
        local dialog = dialogFor()
        assert(dialog.covers_fullscreen and dialog.stop_events_propagation)
        bb.contents = "late reader paint"
        dialog:paintTo(bb, 0, 0)
        assert(bb.restored.contents == "original book")
        assert(bb.restored.w == 600 and bb.restored.h == 800)
        assert(#bb.painted > 0)
    end)

    test("gestures and keys outside the popup are consumed and cannot turn pins or the book", function()
        support.framebuffer("book")
        local dialog = dialogFor()
        local changed = false
        dialog.showAt = function() changed = true end
        assert(dialog:onSwipeNav(nil, { direction = "west", pos = position(0, 0) }))
        assert(not changed)
        assert(dialog:onGesture({ ges = "tap", pos = position(0, 0) }))
        assert(dialog:onGesture({ ges = "hold", pos = position(0, 0) }))
        assert(dialog:onKeyPress({}) and dialog:onKeyRepeat({}))
        assert(support.gesture_calls == 2 and support.key_calls == 2)
        local rectangle = dialog.panel_dimen
        assert(dialog:onSwipeNav(nil, { direction = "west", pos = position(rectangle.x + 1, rectangle.y + 1) }))
        assert(changed)
    end)

    test("popup navigation preserves the snapshot and refreshes only the panel region", function()
        support.framebuffer("book")
        local dialog = dialogFor({ popup = true, index = 1, pins = {
            { type = "text", text = "first" }, { type = "text", text = "second" },
        } })
        assert(dialog.layout[2][1].enabled == false and dialog.layout[2][2].enabled)
        local background = dialog._background_bb
        dialog.layout[2][2].callback()
        assert(dialog.index == 2 and dialog._background_bb == background)
        assert(dialog.layout[2][1].enabled and dialog.layout[2][2].enabled == false)
        local update = support.dirty[#support.dirty]
        assert(update.widget == dialog and update.region == dialog.panel_dimen)
        assert(not background.freed)
    end)

    test("an outside tap closes only the popup and consumes the tap before the reader sees it", function()
        support.framebuffer("book")
        local dialog = dialogFor()
        local rectangle = dialog.panel_dimen
        local background = dialog._background_bb
        assert(dialog.ges_events.TapOutside[1].range() == dialog.dimen)
        assert(not dialog:onTapOutside(nil, { pos = position(rectangle.x + 1, rectangle.y + 1) }))
        assert(not dialog._closed and not background.freed)
        assert(dialog:onSwipeNav(nil, { direction = "west", pos = position(0, 0) }))
        assert(not dialog._closed)
        assert(dialog:onTapOutside(nil, { pos = position(0, 0) }))
        assert(dialog._closed and background.freed and support.closed[#support.closed] == dialog)
        local fullscreen = dialogFor({ pins = { { text = "pin" } } })
        assert(not fullscreen.ges_events.TapOutside)
        assert(not fullscreen:onTapOutside(nil, { pos = position(0, 0) }) and not fullscreen._closed)
    end)

    test("popup supports saved HTML and image previews without changing their contents", function()
        support.framebuffer("book")
        local html = dialogFor({ popup = true, index = 1, pins = {
            { type = "text", text = "plain", html = "<p><emphasis>FB2</emphasis></p>", css = "p { text-indent: 2em; }" },
        } })
        assert(html._scroll_wg.is_xhtml)
        contains(html._scroll_wg.css, "text-indent: 2em")
        contains(html._scroll_wg.html_body, "<emphasis>FB2</emphasis>")
        support.files["map.png"] = "file"
        local image = dialogFor({ popup = true, index = 1, pins = { { type = "image", image_file = "map.png" } } })
        assert(image._image_wg.file == "map.png")
        image:showActions()
        local actions = support.shown[#support.shown]
        actions.buttons[2][1].callback()
        assert(support.shown[#support.shown].file == "map.png" and support.shown[#support.shown].fullscreen)
        assert(not image._closed and image.popup)
    end)

    test("popup action menu retains source information, navigation and deletion", function()
        support.framebuffer("book")
        local navigated, deleted = false, false
        local dialog = dialogFor({ popup = true, index = 1, pins = {
            { type = "text", text = "pin", doc_path = "source.fb2", page = 7 },
        }, plugin = { bookName = function(_, path) return path end } })
        dialog.goToLocation = function() navigated = true end
        dialog.confirmDelete = function() deleted = true end
        dialog:showActions()
        local actions = support.shown[#support.shown]
        actions.buttons[1][1].callback()
        assert(navigated)
        actions.buttons[3][1].callback()
        contains(support.shown[#support.shown].text, "source.fb2")
        contains(support.shown[#support.shown].text, "p. 7")
        actions.buttons[4][1].callback()
        assert(deleted)
    end)

    test("expanding text preserves the selected pin and does not change the saved mode", function()
        support.framebuffer("book")
        local store = Store:new()
        store:setViewerMode("popup")
        local plugin = pluginFor(store)
        local pins = { { text = "one" }, { text = "two" } }
        local dialog = dialogFor({ popup = true, index = 2, pins = pins, plugin = plugin })
        plugin._pin_dialog = dialog
        realNew(function() dialog:expandText() end)
        local expanded = support.shown[#support.shown]
        assert(dialog._closed and not expanded.popup and expanded.index == 2 and expanded.pins == pins)
        assert(plugin._pin_dialog == expanded and store:getViewerMode() == "popup")
    end)

    test("closing frees the snapshot and repaints the reader", function()
        support.framebuffer("book")
        local dialog = dialogFor()
        local background = dialog._background_bb
        dialog:onClose()
        assert(background.freed and dialog._background_bb == nil and dialog._closed)
        local update = support.dirty[#support.dirty]
        assert(update.widget == "all" and update.refresh == "full")
    end)

    test("screen resize dismisses a popup so stale snapshot coordinates cannot be used", function()
        support.framebuffer("book")
        local dialog = dialogFor()
        local background = dialog._background_bb
        support.screenSize(800, 600)
        dialog:onScreenResize()
        assert(dialog._closed and background.freed)
        support.screenSize(600, 800)
    end)

    test("snapshot allocation failure and undersized screens safely use fullscreen", function()
        local bb = support.framebuffer("book")
        bb.copy = function() error("out of memory") end
        local no_snapshot = dialogFor()
        assert(not no_snapshot.popup and no_snapshot._background_bb == nil)
        support.screenSize(180, 240)
        support.framebuffer("book")
        local tiny = dialogFor()
        assert(not tiny.popup and tiny._background_bb == nil)
        support.screenSize(600, 800)
    end)
end
