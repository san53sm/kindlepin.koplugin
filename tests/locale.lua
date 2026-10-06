local PinLocale = require("pinlocale")

return function(test, contains)
    local function withLocale(preference, active, environment, callback)
        local saved_settings, saved_getenv = G_reader_settings, os.getenv
        local gettext = package.loaded.gettext
        local saved_active = gettext.current_lang
        G_reader_settings = preference and { readSetting = function(_, key)
            assert(key == "language")
            return preference
        end } or nil
        gettext.current_lang = active
        os.getenv = function(key) return (environment or {})[key] end
        local ok, err = pcall(callback)
        G_reader_settings, os.getenv = saved_settings, saved_getenv
        gettext.current_lang = saved_active
        assert(ok, err)
    end

    test("KOReader Russian preference overrides English system and accepts locale variants", function()
        for _, locale in ipairs({ "ru", "ru_RU", "ru-RU", "RU_ru.UTF-8", "ru_RU@custom" }) do
            withLocale(locale, "C", { LANG = "en_US.UTF-8" }, function()
                assert(PinLocale.getLanguage() == "ru")
                assert(PinLocale("Pin") == "Закрепить")
            end)
        end
    end)

    test("explicit English or unsupported KOReader language overrides Russian system", function()
        for _, locale in ipairs({ "C", "en", "en_GB", "en-US", "de", "uk", "ar", "unknown" }) do
            withLocale(locale, "ru", { LANGUAGE = "ru", LANG = "ru_RU.UTF-8" }, function()
                assert(PinLocale.getLanguage() == "en")
                assert(PinLocale("Show pins") == "Show pins")
            end)
        end
    end)

    test("active KOReader system locale supports Android without environment variables", function()
        withLocale(nil, "ru_RU", {}, function()
            assert(PinLocale.getLanguage() == "ru")
        end)
        withLocale(nil, "de", { LANG = "ru_RU.UTF-8" }, function()
            assert(PinLocale.getLanguage() == "en")
        end)
    end)

    test("system locale fallback follows KOReader environment precedence", function()
        for _, variable in ipairs({ "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" }) do
            withLocale(nil, "C", { [variable] = "ru_RU.UTF-8" }, function()
                assert(PinLocale.getLanguage() == "ru")
            end)
        end
        withLocale(nil, "C", { LANGUAGE = "de:ru", LC_ALL = "ru", LANG = "ru" }, function()
            assert(PinLocale.getLanguage() == "en")
        end)
        withLocale(nil, "C", { LANGUAGE = "ru:en", LC_ALL = "en" }, function()
            assert(PinLocale.getLanguage() == "ru")
        end)
    end)

    test("missing, blank or unsupported system language falls back to English", function()
        for _, environment in ipairs({ {}, { LANG = "ja_JP.UTF-8" }, { LANG = "C" },
            { LANGUAGE = "", LC_ALL = " ", LC_MESSAGES = "en_US" } }) do
            withLocale("", "C", environment, function()
                assert(PinLocale.getLanguage() == "en")
                assert(PinLocale("Pins") == "Pins")
            end)
        end
    end)

    test("all plugin UI strings have Russian translations with matching placeholders", function()
        local checked = 0
        withLocale("ru", "C", {}, function()
            for _, path in ipairs({ "main.lua", "pindialog.lua", "imageviewer_hook.lua", "_meta.lua" }) do
                local file = assert(io.open(path, "r"))
                local source = file:read("*a")
                file:close()
                for literal in source:gmatch('_%((".-")%)') do
                    local message = assert(loadstring("return " .. literal))()
                    local translated = PinLocale(message)
                    if message ~= "%1 (%2)" then
                        assert(translated ~= message, "missing Russian translation: " .. message)
                    end
                    local function placeholders(text)
                        local tokens = {}
                        for token in text:gmatch("%%%d+") do tokens[#tokens + 1] = token end
                        table.sort(tokens)
                        return table.concat(tokens, ",")
                    end
                    assert(placeholders(message) == placeholders(translated), message)
                    checked = checked + 1
                end
            end
        end)
        assert(checked > 60, "UI string scan did not cover the plugin")
    end)

    test("metadata and menus use the selected language without modifying KOReader translations", function()
        local Plugin = require("main")
        local support = require("support")
        local plugin = support.instance(Plugin, {})
        local gettext = package.loaded.gettext
        local original = gettext.translation
        gettext.translation = { ["Pins"] = "unrelated KOReader translation" }
        for _, locale in ipairs({ "ru", "en", "de" }) do
            withLocale(locale, "C", {}, function()
                local menu = {}
                plugin:addToMainMenu(menu)
                local metadata = dofile("_meta.lua")
                assert(metadata.fullname == "Pin")
                if locale == "ru" then
                    assert(menu.pin.text == "Закрепления")
                    contains(metadata.description, "Закрепляет")
                else
                    assert(menu.pin.text == "Pins")
                    contains(metadata.description, "Pin selected text")
                end
                assert(gettext.translation.Pins == "unrelated KOReader translation")
            end)
        end
        gettext.translation = original
    end)
end
