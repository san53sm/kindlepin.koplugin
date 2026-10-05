package.path = "./?.lua;./tests/?.lua;" .. package.path
local support = require("support")
local passed = 0
local function test(name, callback)
    support.reset()
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function contains(text, expected)
    assert(text:find(expected, 1, true), "missing: " .. expected)
end
local PinText = require("pintext")
local PinStore = require("pinstore")
local PinDialog = require("pindialog")
local Plugin = require("main")
local selection = { text = "Первый абзац.\nВторой абзац.", pos0 = "/start.4", pos1 = "/end.12" }

test("EPUB keeps selection boundaries, ancestors, inline markup and CSS cascade", function()
    local source = {
        ["OPS/main.css"] = '@import url("styles/base.css"); p { text-indent: 2em; }',
        ["OPS/styles/base.css"] = '.italic { font-style: italic; }',
    }
    local captured = PinText.capture({
        getHTMLFromXPointers = function(_, start, finish, flags, from_root)
            assert(start == selection.pos0 and finish == selection.pos1)
            assert(flags == 0x7000 and from_root)
            return '<body><DocFragment><body><p><em>Первый</em> <strong>абзац.</strong></p><p>Второй абзац.</p></body></DocFragment></body>',
                { "OPS/main.css", "OPS/styles/base.css" }
        end,
        getDocumentFileContent = function(_, path) return source[path] end,
    }, selection)
    contains(captured.html, "<em>Первый</em>")
    contains(captured.html, "<strong>абзац.</strong>")
    contains(captured.css, "text-indent: 2em")
    local _, occurrences = captured.css:gsub("font%-style: italic", "")
    assert(occurrences == 1, "import was applied twice")
    assert(captured.css:find("font%-style") < captured.css:find("text%-indent"))
end)

test("FB2 preserves semantic elements and embedded styles", function()
    local captured = PinText.capture({ getHTMLFromXPointers = function()
        return '<body><stylesheet>p { margin-left: 2em; }</stylesheet><section><title><p>Глава</p></title><p><emphasis>Курсив</emphasis><strong>Жирный</strong></p><poem><stanza><v>Строка</v></stanza></poem></section></body>'
    end }, selection)
    contains(captured.html, "<emphasis>Курсив</emphasis>")
    contains(captured.html, "<v>Строка</v>")
    assert(not captured.html:find("<stylesheet", 1, true))
    contains(captured.css, "margin-left: 2em")
    contains(PinText.stylesheet(captured), "emphasis { font-style: italic;")
    contains(PinText.stylesheet(captured), "v { display: block;")
end)

test("cyclic CSS imports terminate and remote imports stay offline", function()
    local files = {
        ["a.css"] = '@import "b.css"; @import "https://example.org/no.css"; .a { font-weight: bold; }',
        ["b.css"] = '@import "a.css"; .b { font-style: italic; }',
    }
    local captured = PinText.capture({
        getHTMLFromXPointers = function() return "<p>text</p>", { "a.css", "b.css" } end,
        getDocumentFileContent = function(_, path)
            assert(not path:find("https:", 1, true))
            return files[path]
        end,
    }, selection)
    contains(captured.css, ".a")
    contains(captured.css, ".b")
    assert(not captured.css:find("@import", 1, true))
end)

test("missing CSS leaves HTML usable", function()
    local captured = PinText.capture({
        getHTMLFromXPointers = function() return "<p><b>text</b></p>", { "missing.css" } end,
        getDocumentFileContent = function() error("file unavailable") end,
    }, selection)
    contains(captured.html, "<b>text</b>")
end)

test("unsupported documents and invalid ranges fall back to plain text", function()
    assert(PinText.capture({}, selection) == nil)
    assert(PinText.capture({ getHTMLFromXPointers = function() error("invalid range") end }, selection) == nil)
    assert(PinText.capture({ getHTMLFromXPointers = function() return "" end }, selection) == nil)
    assert(PinText.capture({ getHTMLFromXPointers = function() error("must not be called") end },
        { pos0 = {page = 1}, pos1 = {page = 1} }) == nil)
end)

test("pinning persists formatted and plain text alongside existing pins", function()
    local store = PinStore:new()
    store:add("book.epub", { type = "text", text = "old" })
    local plugin = support.instance(Plugin, {
        store = store,
        ui = { document = { file = "book.epub", getHTMLFromXPointers = function()
            return "<p><em>Первый абзац.</em></p><p>Второй абзац.</p>"
        end }, getCurrentPage = function() return 5 end },
    })
    plugin:pinFromHighlight({ selected_text = selection })
    local saved = PinStore:new():getPins("book.epub")
    assert(#saved == 2 and saved[1].text == "old")
    assert(saved[2].text == selection.text and saved[2].pos0 == selection.pos0)
    contains(saved[2].html, "<em>Первый абзац.</em>")
end)

test("HTML viewer uses XHTML for FB2 and offline saved CSS", function()
    local dialog = support.instance(PinDialog)
    local widget = dialog:buildTextContent({ text = "plain", html = "<p><emphasis>text</emphasis></p>",
        css = "p { text-indent: 2em; }" }, 500, 400)
    assert(widget.is_xhtml and widget.width == 500 and widget.height == 400)
    contains(widget.css, "text-indent: 2em")
    assert(widget.html_body == "<p><emphasis>text</emphasis></p>")
end)

test("legacy pins and HTML renderer errors use saved plain text", function()
    local dialog = support.instance(PinDialog)
    assert(dialog:buildTextContent({ text = "legacy" }, 500, 400).text == "legacy")
    local html_widget = package.loaded["ui/widget/scrollhtmlwidget"]
    support.stub("ui/widget/scrollhtmlwidget", { new = function() error("renderer unavailable") end })
    assert(dialog:buildTextContent({ text = "fallback", html = "<p>text</p>" }, 500, 400).text == "fallback")
    support.stub("ui/widget/scrollhtmlwidget", html_widget)
end)

test("hardware scrolling invokes the shared KOReader widget API", function()
    local up, down = 0, 0
    local dialog = support.instance(PinDialog, { _scroll_wg = {
        onScrollUp = function() up = up + 1 end,
        onScrollDown = function() down = down + 1 end,
    } })
    assert(dialog:onScrollUp() and dialog:onScrollDown())
    assert(up == 1 and down == 1)
end)

local function pluginFor(store, path, ui)
    ui = ui or {}
    ui.document = ui.document or { file = path }
    return support.instance(Plugin, { store = store, ui = ui })
end

test("links are one-way and survive reopening the store", function()
    local store = PinStore:new()
    store:add("one.epub", { id = "one", text = "volume one" })
    store:add("two.fb2", { id = "two", text = "volume two" })
    assert(store:addLink("two.fb2", "one.epub"))
    store = PinStore:new()
    assert(#store:listForViewer("two.fb2") == 2)
    assert(#store:listForViewer("one.epub") == 1)
    assert(#store:getLinkedBooks("one.epub") == 0)
    assert(store:getLinkedBooks("two.fb2")[1] == "one.epub")
end)

test("viewer order is current book, then explicit sources in link order", function()
    local store = PinStore:new()
    store:add("current.epub", { id = "old", created_at = 50 })
    store:add("current.epub", { id = "new", created_at = 60 })
    store:add("first.fb2", { id = "source-old", created_at = 10 })
    store:add("first.fb2", { id = "source-new", created_at = 20 })
    store:add("second.epub", { id = "other", created_at = 100 })
    store:addLink("current.epub", "first.fb2")
    store:addLink("current.epub", "second.epub")
    local pins = store:listForViewer("current.epub")
    assert(#pins == 5 and store:countVisible("current.epub") == 5)
    assert(pins[1].id == "new" and pins[2].id == "old")
    assert(pins[3].id == "source-new" and pins[4].id == "source-old" and pins[5].id == "other")
    assert(pins[3].doc_path == "first.fb2")
    assert(store:getPins("first.fb2")[1].doc_path == nil, "viewer mutated stored pin")
end)

test("transitive sources require their own explicit link", function()
    local store = PinStore:new()
    for _, path in ipairs({ "one.epub", "two.epub", "three.epub" }) do
        store:add(path, { text = path })
    end
    store:addLink("two.epub", "one.epub")
    store:addLink("three.epub", "two.epub")
    assert(#store:listForViewer("three.epub") == 2)
    assert(store:addLink("three.epub", "one.epub"))
    assert(#store:listForViewer("three.epub") == 3)
end)

test("mutual links and malformed settings never recurse or duplicate books", function()
    local store = PinStore:new()
    store:add("one.epub", { text = "one" })
    store:add("two.epub", { text = "two" })
    store:addLink("one.epub", "two.epub")
    store:addLink("two.epub", "one.epub")
    assert(#store:listForViewer("one.epub") == 2)
    assert(#store:listForViewer("two.epub") == 2)
    assert(not store:addLink("one.epub", "one.epub"))
    assert(not store:addLink("one.epub", "two.epub"))
    assert(not store:addLink("one.epub", nil))
    store.links:saveSetting("one.epub", { "two.epub", "one.epub", "two.epub", "", 42 })
    assert(#store:getLinkedBooks("one.epub") == 1)
    assert(#store:listForViewer("one.epub") == 2)
end)

test("unlinking does not delete original pins or affect the reverse link", function()
    local store = PinStore:new()
    store:add("one.epub", { text = "one" })
    store:add("two.epub", { text = "two" })
    store:addLink("two.epub", "one.epub")
    store:addLink("one.epub", "two.epub")
    store:removeLink("two.epub", "one.epub")
    assert(store:count("one.epub") == 1 and store:count("two.epub") == 1)
    assert(#store:listForViewer("two.epub") == 1)
    assert(#store:listForViewer("one.epub") == 2)
end)

test("deleting a linked image resolves colliding IDs against the source book", function()
    local store = PinStore:new()
    store:add("one.epub", { id = "same", type = "image", image_file = "/test/source.png" })
    store:add("two.epub", { id = "same", text = "keep me" })
    store:addLink("two.epub", "one.epub")
    local removed_path, remove = nil, os.remove
    os.remove = function(path) removed_path = path; return true end
    pluginFor(store, "two.epub"):deletePin(store:listForViewer("two.epub")[2])
    os.remove = remove
    assert(removed_path == "/test/source.png")
    assert(store:count("one.epub") == 0)
    assert(store:count("two.epub") == 1 and store:getPins("two.epub")[1].text == "keep me")
end)

test("viewer warns about the linked source and refreshes after deletion", function()
    local store = PinStore:new()
    store:add("source.fb2", { id = "source", text = "source" })
    store:addLink("current.epub", "source.fb2")
    local plugin = pluginFor(store, "current.epub")
    local closed = false
    local dialog = support.instance(PinDialog, { plugin = plugin, pins = plugin:listPins(), index = 1,
        onClose = function() closed = true end })
    dialog:confirmDelete()
    local confirmation = support.shown[1]
    contains(confirmation.text, "source.fb2")
    contains(confirmation.text, "исходной книги")
    confirmation.ok_callback()
    assert(closed and store:count("source.fb2") == 0)
end)

test("bulk deletion affects only current-book pins and preserves sources and links", function()
    local store = PinStore:new()
    store:add("source.fb2", { id = "source", text = "source" })
    store:add("current.epub", { id = "current", text = "current" })
    store:addLink("current.epub", "source.fb2")
    local items = {}
    pluginFor(store, "current.epub"):addToMainMenu(items)
    items.kindlepin.sub_item_table[3].callback()
    support.shown[1].ok_callback()
    assert(store:count("current.epub") == 0 and store:count("source.fb2") == 1)
    assert(#store:getLinkedBooks("current.epub") == 1)
end)

test("a book with no own pins can display linked pins, including missing source files", function()
    local store = PinStore:new()
    store:add("missing.fb2", { id = "source", text = "source", html = "<p><emphasis>source</emphasis></p>" })
    store:addLink("current.epub", "missing.fb2")
    local plugin = pluginFor(store, "current.epub")
    local items = {}
    plugin:addToMainMenu(items)
    assert(items.kindlepin.sub_item_table[1].enabled_func())
    contains(items.kindlepin.sub_item_table[1].text_func(), "(1)")
    assert(not items.kindlepin.sub_item_table[3].enabled_func())
    plugin:showPins()
    assert(support.shown[1].pins[1].doc_path == "missing.fb2")
    contains(support.shown[1].pins[1].html, "<emphasis>source</emphasis>")
end)

test("linked navigation waits for the source reader and uses its XPointer API", function()
    local callback, switched, jumped = nil, nil, false
    local old_ui = { document = { file = "current.epub" },
        rolling = { onGotoXPointer = function() error("jumped in wrong book") end },
        switchDocument = function(_, path, seamless, after_open)
            switched, callback = path, after_open
        end,
    }
    support.files["source.fb2"] = "file"
    pluginFor(PinStore:new(), "current.epub", old_ui):goToPinLocation({
        doc_path = "source.fb2", xpointer = "/target", page = 7,
    })
    assert(switched == "source.fb2" and not jumped)
    old_ui.document = nil -- The old plugin/UI is torn down before the callback.
    callback({ document = { file = "source.fb2", isXPointerInDocument = function(_, xp)
        return xp == "/target"
    end }, rolling = { onGotoXPointer = function(_, xp)
        assert(xp == "/target"); jumped = true
    end } })
    assert(jumped)
end)

test("missing or unsupported source files leave the current reader open", function()
    local switched = false
    local plugin = pluginFor(PinStore:new(), "current.epub", {
        switchDocument = function() switched = true end,
    })
    plugin:goToPinLocation({ doc_path = "missing.fb2", page = 1 })
    assert(not switched)
    contains(support.shown[1].text, "missing.fb2")
    support.files["unsupported.bin"] = "file"
    plugin:goToPinLocation({ doc_path = "unsupported.bin", page = 1 })
    assert(not switched)
end)

test("PDF sources use page navigation in their own reader", function()
    local reached = nil
    support.files["source.pdf"] = "file"
    pluginFor(PinStore:new(), "current.epub", {
        switchDocument = function(_, _, _, callback)
            callback({ document = { file = "source.pdf" }, paging = { onGotoPage = function(_, page)
                reached = page
            end } })
        end,
    }):goToPinLocation({ doc_path = "source.pdf", page = 17 })
    assert(reached == 17)
end)

test("invalid XPointers fall back to the saved page", function()
    local reached = nil
    local ui = { document = { file = "current.epub", isXPointerInDocument = function() return false end },
        rolling = { onGotoXPointer = function() error("invalid XPointer used") end,
            onGotoPage = function(_, page) reached = page end },
    }
    pluginFor(PinStore:new(), "current.epub", ui):goToPinLocation({ xpointer = "/invalid", page = 12 })
    assert(reached == 12)
end)

test("settings candidates exclude self and existing links and bind the chosen path", function()
    local store = PinStore:new()
    for _, path in ipairs({ "current.epub", "linked.fb2", "first.fb2", "second.epub" }) do
        store:add(path, { text = path })
    end
    store:addLink("current.epub", "linked.fb2")
    local plugin = pluginFor(store, "current.epub")
    local candidates = plugin:linkCandidates()
    assert(#candidates == 2)
    candidates[1].callback()
    assert(store:getLinkedBooks("current.epub")[2] == "first.fb2")
    candidates[2].callback()
    assert(store:getLinkedBooks("current.epub")[3] == "second.epub")
    local settings = plugin:linkedBooksMenu()
    settings[4].sub_item_table[2].callback()
    assert(store:getLinkedBooks("current.epub")[1] == "first.fb2")
end)

test("file chooser accepts supported books, rejects self, and links an empty source", function()
    local store = PinStore:new()
    local plugin = pluginFor(store, "/books/current.epub")
    plugin:chooseLinkedBook()
    local chooser = support.shown[1]
    assert(chooser.path == "/books" and chooser.select_file and not chooser.select_directory)
    assert(chooser.file_filter("volume.fb2") and not chooser.file_filter("image.png"))
    chooser.onConfirm("/books/current.epub")
    assert(#store:getLinkedBooks("/books/current.epub") == 0)
    chooser.onConfirm("/books/empty.fb2")
    assert(store:getLinkedBooks("/books/current.epub")[1] == "/books/empty.fb2")
    store:add("/books/empty.fb2", { text = "added later" })
    assert(store:countVisible("/books/current.epub") == 1)
end)

require("fonts")(test, contains)
require("popup")(test, contains)
print(string.format("%d tests passed", passed))
