local Font = require("ui/font")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PinFont = {}
local FAMILY = "KindlePinReader"

local function call(object, method)
    if not object or type(object[method]) ~= "function" then return end
    local ok, value = pcall(object[method], object)
    if ok then return value end
end

local function positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

-- Settings are read at display time, including for pins from other books.
function PinFont.forReader(ui)
    local document = ui and ui.document
    local config = ui and ui.font and ui.font.configurable
        or document and document.configurable or {}
    local fallback = Font:getFace("x_smallinfofont")
    local size = call(document, "getFontSize")
    local raw_size = config.font_size
    local has_size = positive(size) or positive(raw_size)
    if not positive(raw_size) then
        raw_size = positive(size) and size * 600 / Screen:scaleBySize(600)
            or fallback.orig_size or 20
    end
    if not positive(size) then size = Screen:scaleBySize(raw_size) end
    local options = {
        size = size,
        face = Font:getFace("x_smallinfofont", raw_size) or fallback,
        html_style = has_size and "font-size:1em !important;" or nil,
    }
    local name = call(document, "getFontFace") or ui and ui.font and ui.font.font_face
    if type(name) ~= "string" or name == "" then return options end
    local engine = call(document, "engineInit")
    if not engine or type(engine.getFontFaceFilenameAndFaceIndex) ~= "function" then return options end
    local function resolve(bold, italic)
        local ok, path, index = pcall(engine.getFontFaceFilenameAndFaceIndex, name, bold, italic)
        if ok and type(path) == "string" and lfs.attributes(path, "mode") == "file" then
            return { path = path, index = index or 0 }
        end
    end
    local regular = resolve(false, false) or resolve(false, true)
    if not regular then return options end
    local ok, face = pcall(Font.getFace, Font, regular.path, raw_size, regular.index)
    if ok and face then options.face = face end
    -- MuPDF's CSS font loader opens face 0 of a collection. Do not silently
    -- substitute a different family for a selected face at another index.
    if regular.index ~= 0 then
        logger.warn("kindlepin: HTML font collections require face index 0", regular.path, regular.index)
        return options
    end
    local css = {}
    for _, style in ipairs({
        { false, false }, { true, false }, { false, true }, { true, true },
    }) do
        local variant = resolve(style[1], style[2])
        if not variant or variant.index ~= 0 then variant = regular end
        local path = variant.path
        if path:sub(1, 1) ~= "/" then path = lfs.currentdir() .. "/" .. path end
        -- All sources share the root archive, including Kindle system fonts
        -- outside KOReader's font folder. MuPDF decodes archive URL names.
        local url = path:sub(2):gsub("[^%w%-%._~/]", function(char)
            return string.format("%%%02X", char:byte())
        end)
        css[#css + 1] = string.format(
            '@font-face { font-family:%s; src:url("%s"); font-weight:%s; font-style:%s; }',
            FAMILY, url, style[1] and "bold" or "normal", style[2] and "italic" or "normal")
    end
    options.css = table.concat(css, "\n")
    options.resource_directory = "/"
    options.html_style = "font-family:" .. FAMILY .. " !important; " .. (options.html_style or "")
    return options
end

local function styledTag(tag, declarations)
    local name = tag:match("^<([%w_:.-]+)")
    local pos = #name + 2
    -- Read attributes rather than matching style-looking text inside a title.
    while pos < #tag do
        local whitespace = tag:sub(pos):match("^%s*")
        pos = pos + #whitespace
        local attribute = tag:sub(pos):match("^([%w_:.-]+)")
        if not attribute then break end
        pos = pos + #attribute
        pos = pos + #tag:sub(pos):match("^%s*")
        if tag:sub(pos, pos) == "=" then
            pos = pos + 1
            pos = pos + #tag:sub(pos):match("^%s*")
            local quote = tag:sub(pos, pos)
            if quote == '"' or quote == "'" then
                local finish = tag:find(quote, pos + 1, true)
                if not finish then break end
                if attribute:lower() == "style" then
                    return tag:sub(1, finish - 1) .. "; " .. declarations .. tag:sub(finish)
                end
                pos = finish + 1
            else
                -- CRe exports XML with quoted attributes, but tolerate HTML.
                local value = tag:sub(pos):match("^[^%s>]+") or ""
                if value:sub(-1) == "/" then value = value:sub(1, -2) end
                if attribute:lower() == "style" then
                    return tag:sub(1, pos - 1) .. '"' .. value .. "; " .. declarations .. '"'
                        .. tag:sub(pos + #value)
                end
                pos = pos + #value
            end
        end
    end
    return (tag:gsub("(%s*/?>)$", ' style="' .. declarations .. '"%1'))
end

-- MuPDF gives inline styles priority even over stylesheet !important rules.
-- Override only family/size in a display copy; keep weight, italic and layout.
function PinFont.styleHTML(html, options)
    if not options or not options.html_style then return html end
    local parts, pos = {}, 1
    while pos <= #html do
        local start = html:find("<", pos, true)
        if not start then parts[#parts + 1] = html:sub(pos); break end
        parts[#parts + 1] = html:sub(pos, start - 1)
        local finish
        if html:sub(start, start + 3) == "<!--" then
            local last = html:find("-->", start + 4, true)
            finish = last and last + 2
        elseif html:sub(start, start + 8) == "<![CDATA[" then
            local last = html:find("]]>", start + 9, true)
            finish = last and last + 2
        else
            local quote
            for index = start + 1, #html do
                local char = html:sub(index, index)
                if quote then
                    if char == quote then quote = nil end
                elseif char == '"' or char == "'" then quote = char
                elseif char == ">" then finish = index; break end
            end
        end
        if not finish then parts[#parts + 1] = html:sub(start); break end
        local tag = html:sub(start, finish)
        local name = tag:match("^<([%a_][%w_:.-]*)")
        if name and (name:lower() == "script" or name:lower() == "style") then
            local closing = html:lower():find("</" .. name:lower(), finish + 1, true)
            if closing then
                parts[#parts + 1] = html:sub(start, closing - 1)
                pos = closing
            else
                parts[#parts + 1] = html:sub(start); break
            end
        else
            parts[#parts + 1] = name and styledTag(tag, options.html_style) or tag
            pos = finish + 1
        end
    end
    return table.concat(parts)
end

return PinFont
