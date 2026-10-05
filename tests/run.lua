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

print(string.format("%d tests passed", passed))
