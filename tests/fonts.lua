return function(test, contains)
    local support = require("support")
    local PinFont = require("pinfont")
    local Dialog = require("pindialog")
    local screen = package.loaded.device.screen
    local function reader()
        local config = { font_size = 24 }
        local family, pixels = "Book Font", 48
        local engine = { getFontFaceFilenameAndFaceIndex = function(name, bold, italic)
            local path = "./fonts/" .. name .. (bold and " Bold" or "") .. (italic and " Italic" or "") .. ".ttf"
            return path, 0
        end }
        for _, suffix in ipairs({ "", " Bold", " Italic", " Bold Italic" }) do
            support.files["./fonts/Book Font" .. suffix .. ".ttf"] = "file"
        end
        local ui = { document = {
            configurable = config,
            getFontFace = function() return family end,
            getFontSize = function() return pixels end,
            engineInit = function() return engine end,
        } }
        return ui, config, engine, function(name, size) family, pixels = name, size end
    end

    test("formatted pins load the current book font and four style variants at its pixel size", function()
        local ui = reader()
        local pin = { doc_path = "previous-volume.fb2", text = "plain",
            html = '<p style="font:italic 9px OldFont; text-indent:2em;"><strong>Bold</strong><emphasis>Italic</emphasis></p>',
            css = 'p { font-family:OldFont !important; font-size:9px; margin-left:2em; }' }
        local html, css = pin.html, pin.css
        for _, popup in ipairs({ false, true }) do
            local dialog = support.instance(Dialog, { plugin = { ui = ui }, popup = popup })
            local widget = dialog:buildTextContent(pin, 350, 450)
            assert(widget.default_font_size == 48 and widget.html_resource_directory == "/")
            contains(widget.css, 'src:url("koreader/./fonts/Book%20Font.ttf")')
            contains(widget.css, "Book%20Font%20Bold%20Italic.ttf")
            contains(widget.css, "font-weight:bold; font-style:italic")
            contains(widget.html_body, "font-family:KindlePinReader !important")
            contains(widget.html_body, "font-size:1em !important")
            contains(widget.html_body, "text-indent:2em")
            contains(widget.html_body, "<strong style=")
            contains(widget.css, "margin-left:2em")
            assert(pin.html == html and pin.css == css)
        end
    end)

    test("reopening saved pins follows a newly selected reader font and size", function()
        local ui, config, _, change = reader()
        local dialog = support.instance(Dialog, { plugin = { ui = ui } })
        local pin = { html = "<p>Saved</p>", text = "Saved" }
        assert(dialog:buildTextContent(pin, 350, 450).default_font_size == 48)
        support.files["./fonts/New Font.ttf"] = "file"
        change("New Font", 60)
        config.font_size = 30
        local updated = dialog:buildTextContent(pin, 350, 450)
        assert(updated.default_font_size == 60)
        contains(updated.css, "New%20Font.ttf")
        assert(pin.html == "<p>Saved</p>")
    end)

    test("legacy text and HTML fallback use the reader's FreeType face without double scaling", function()
        local ui = reader()
        local scale = screen.scaleBySize
        screen.scaleBySize = function(_, size) return size * 2 end
        local dialog = support.instance(Dialog, { plugin = { ui = ui } })
        local plain = dialog:buildTextContent({ text = "legacy" }, 350, 450)
        assert(plain.face.orig_font == "./fonts/Book Font.ttf")
        assert(plain.face.orig_size == 24 and plain.face.size == 48 and plain.face.faceindex == 0)
        local saved = package.loaded["ui/widget/scrollhtmlwidget"]
        support.stub("ui/widget/scrollhtmlwidget", { new = function() error("renderer unavailable") end })
        local fallback = dialog:buildTextContent({ text = "fallback", html = "<p>HTML</p>" }, 350, 450)
        support.stub("ui/widget/scrollhtmlwidget", saved)
        screen.scaleBySize = scale
        assert(fallback.face.orig_font == "./fonts/Book Font.ttf" and fallback.face.size == 48)
    end)

    test("font variants missing from a family use its regular file for synthesized styles", function()
        local ui = reader()
        support.files["./fonts/Book Font Bold.ttf"] = nil
        support.files["./fonts/Book Font Italic.ttf"] = nil
        support.files["./fonts/Book Font Bold Italic.ttf"] = nil
        local typography = PinFont.forReader(ui)
        local _, count = typography.css:gsub("Book%%20Font.ttf", "")
        assert(count == 4)
        contains(typography.css, "font-weight:bold; font-style:italic")
    end)

    test("unavailable font APIs and font files keep text readable with the current size", function()
        local ui, _, engine = reader()
        engine.getFontFaceFilenameAndFaceIndex = function() error("old font API") end
        local options = PinFont.forReader(ui)
        assert(options.size == 48 and options.css == nil and options.face.orig_font == "x_smallinfofont")
        assert(PinFont.forReader(nil).html_style == nil)
        ui.document.engineInit = function() error("engine unavailable") end
        assert(PinFont.forReader(ui).size == 48)
        ui.document.engineInit = function() return engine end
        engine.getFontFaceFilenameAndFaceIndex = function() return "/missing.ttf", 0 end
        assert(PinFont.forReader(ui).css == nil)
    end)

    test("nonzero collection face indexes are kept for plain text without loading the wrong HTML family", function()
        local ui, _, engine = reader()
        support.files["/fonts/Collection.ttc"] = "file"
        engine.getFontFaceFilenameAndFaceIndex = function() return "/fonts/Collection.ttc", 3 end
        local options = PinFont.forReader(ui)
        assert(options.face.faceindex == 3 and options.css == nil and not options.resource_directory)
        assert(not options.html_style:find("font-family", 1, true))
    end)

    test("typography overrides preserve quoted attributes, comments, CDATA, self-closing and raw style content", function()
        local html = [=[<p title="a > b, style='unchanged'" style='font-family:Old !important; font-weight:bold;'>A<em>B</em></p><!-- <fake> --><![CDATA[<raw>]]><empty-line/><style>p:before { content:"<raw>"; }</style>]=]
        local styled = PinFont.styleHTML(html, { html_style = "font-family:KindlePinReader !important; font-size:1em !important;" })
        contains(styled, [[title="a > b, style='unchanged'"]])
        contains(styled, "font-weight:bold;; font-family:KindlePinReader")
        contains(styled, '<em style="font-family:KindlePinReader')
        contains(styled, "<!-- <fake> --><![CDATA[<raw>]]>")
        contains(styled, '<empty-line style="font-family:KindlePinReader')
        contains(styled, [[<style>p:before { content:"<raw>"; }</style>]])
        assert(PinFont.styleHTML(html, {}) == html)
    end)
end
