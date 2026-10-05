local logger = require("logger")

local PinText = {}

-- MuPDF renders the saved snippet independently of the book's CRe DOM.
-- Supply readable defaults, including FB2 elements unknown to HTML renderers.
PinText.DEFAULT_CSS = [[
body { margin: 0; padding: 0; line-height: 1.35; }
p { margin: 0.35em 0; text-indent: 1.2em; }
blockquote, cite, epigraph { display: block; margin: 0.5em 1em; }
emphasis { font-style: italic; }
strong { font-weight: bold; }
strikethrough { text-decoration: line-through; }
underline { text-decoration: underline; }
empty-line { display: block; height: 1em; }
DocFragment, section, autoBoxing, floatBox, tabularBox { display: block; }
poem, stanza { display: block; margin: 0.5em 0; }
v { display: block; text-indent: 0; text-align: left; }
text-author { display: block; text-align: right; font-style: italic; }
title, subtitle { display: block; font-weight: bold; text-align: center; }
title p, subtitle p { text-indent: 0; }
]]

local function resolvePath(base, relative)
    if relative:match("^%a[%w+.-]*:") or relative:sub(1, 2) == "//" then
        return nil
    end
    local path = relative:sub(1, 1) == "/" and relative
        or (base:match("^(.*)/") or "") .. "/" .. relative
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            table.remove(parts)
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

local function importPath(rule)
    local path = rule:match("^%s*url%s*%(%s*['\"]?(.-)['\"]?%s*%)")
        or rule:match("^%s*['\"](.-)['\"]")
    return path
end

-- Expand local imports at their original position so the CSS cascade survives
-- saving. Nothing is loaded from the network or from the host filesystem.
local function readCSS(document, path, visiting, seen, depth)
    if not document.getDocumentFileContent or visiting[path] or depth > 8 then
        return ""
    end
    local ok, css = pcall(document.getDocumentFileContent, document, path)
    if not ok or type(css) ~= "string" then
        return ""
    end
    visiting[path] = true
    seen[path] = true
    css = css:gsub("@import%s+([^;]+);", function(rule)
        local relative = importPath(rule)
        local resolved = relative and resolvePath(path, relative)
        return resolved and readCSS(document, resolved, visiting, seen, depth + 1) or ""
    end)
    visiting[path] = nil
    return css:gsub("@charset%s+[^;]+;", "")
end

function PinText.capture(document, selected)
    if not document or not document.getHTMLFromXPointers
        or type(selected.pos0) ~= "string" or type(selected.pos1) ~= "string"
    then
        return nil
    end
    -- Include ancestors (even for a selection inside one text node), direction,
    -- linked CSS and embedded stylesheet nodes; only selected text is exported.
    local ok, html, css_files = pcall(document.getHTMLFromXPointers,
        document, selected.pos0, selected.pos1, 0x7000, true)
    if not ok or type(html) ~= "string" or html == "" then
        logger.dbg("kindlepin: HTML extraction unavailable", html)
        return nil
    end
    local embedded_css = {}
    html = html:gsub("<stylesheet[^>]*>(.-)</stylesheet>", function(css)
        embedded_css[#embedded_css + 1] = css
        return ""
    end)
    html = html:gsub("<stylesheet[^>]*/>", "")
    local css_parts = {}
    local seen = {}
    -- CRe returns linked stylesheets and their imported files. Imported files
    -- are included by readCSS, so don't apply them again after the parent sheet.
    for _, path in ipairs(type(css_files) == "table" and css_files or {}) do
        if type(path) == "string" and not seen[path] then
            local css = readCSS(document, path, {}, seen, 0)
            css_parts[#css_parts + 1] = css
        end
    end
    for _, css in ipairs(embedded_css) do
        -- Linked sheets have already been captured from css_files.
        css_parts[#css_parts + 1] = css:gsub("@import%s+[^;]+;", "")
    end
    return { html = html, css = table.concat(css_parts, "\n") }
end

function PinText.stylesheet(pin)
    return PinText.DEFAULT_CSS .. "\n" .. (pin.css or "") .. [[
/* The snippet uses the viewer's available space rather than a book page. */
@page { margin: 0 !important; }
body { margin: 0 !important; padding: 0 !important; }
]]
end

return PinText
