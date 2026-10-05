-- Plugin-owned translations: KOReader's catalog does not include external plugins.
-- Keep English as the source language, including when KOReader uses another locale.
local GetText = require("gettext")
local PinLocale = {}
local russian = {
    ["Pin"] = "Закрепить",
    ["Pin selected text and images and browse them without leaving the current page."] = "Закрепляет выделенный текст и изображения и позволяет просматривать их, не уходя с текущей страницы.",
    ["Show pins"] = "Показать закрепления",
    ["Pin selection"] = "Закрепить выделение",
    ["Unknown book"] = "Неизвестная книга",
    ["Pins linked: %1"] = "Связаны закрепления: %1",
    ["Long-press a book file to link its pins"] = "Удерживайте файл книги для добавления связи",
    ["A book cannot be linked to itself."] = "Книгу нельзя связать с самой собой.",
    ["%1 (%2)"] = "%1 (%2)",
    ["No other books with pins"] = "Нет других книг с закреплениями",
    ["Links are one-way from this book"] = "Связи действуют только из этой книги",
    ["Add a book with pins"] = "Добавить книгу с закреплениями",
    ["Choose a book file…"] = "Выбрать файл книги…",
    ["Remove link"] = "Убрать связь",
    ["Link removed. Pins kept."] = "Связь удалена. Закрепления сохранены.",
    ["No text to pin."] = "Нет текста для закрепления.",
    ["Pinned"] = "Закреплено",
    ["Failed to save the image."] = "Не удалось сохранить изображение.",
    ["Image"] = "Изображение",
    ["Image pinned"] = "Изображение закреплено",
    ["Failed to jump to the passage."] = "Не удалось перейти к фрагменту.",
    ["Failed to open the pin's book:\n%1"] = "Не удалось открыть книгу закрепления:\n%1",
    ["No pins in this book or its linked books yet.\nSelect text and tap “Pin”, or pin an image from the image viewer."] = "Пока нет закреплений в этой книге и связанных книгах.\nВыделите текст и нажмите «Закрепить», либо закрепите изображение из просмотрщика.",
    ["Pins"] = "Закрепления",
    ["View pins (%1)"] = "Просмотреть закрепления (%1)",
    ["View pins"] = "Просмотреть закрепления",
    ["Linked books (%1)"] = "Связанные книги (%1)",
    ["Delete all pins in this book"] = "Удалить все закрепления книги",
    ["Delete all pins in this book?"] = "Удалить все закрепления в этой книге?",
    ["Delete"] = "Удалить",
    ["Cancel"] = "Отмена",
    ["Pins deleted"] = "Закрепления удалены",
    ["Popup"] = "Всплывающий",
    ["Fullscreen"] = "Полноэкранный",
    ["Viewer mode: %1"] = "Вид просмотра: %1",
    ["Popup in the bottom-right corner"] = "Всплывающий в правом нижнем углу",
    ["Pin %1 of %2"] = "Закрепление %1 из %2",
    ["image"] = "изображение",
    ["text"] = "текст",
    ["p. %1"] = "стр. %1",
    ["Prev."] = "Пред.",
    ["Next"] = "След.",
    ["Go to passage"] = "К фрагменту",
    ["Open fullscreen"] = "На весь экран",
    ["Close"] = "Закрыть",
    ["Details"] = "Сведения",
    ["Close menu"] = "Закрыть меню",
    ["(empty)"] = "(пусто)",
    ["Image unavailable."] = "Изображение недоступно.",
    ["Pinned image"] = "Закреплённое изображение",
    ["Delete this pin?"] = "Удалить это закрепление?",
    ["Delete this pin from the linked book?\n%1\n\nIt will also disappear from the original book."] = "Удалить это закрепление из связанной книги?\n%1\n\nОно исчезнет и при просмотре исходной книги.",
}

local function hasLocale(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function supportedLanguage(locale)
    -- Match language tags, territory/encoding suffixes and the first LANGUAGE entry.
    local language = locale:lower():match("^%s*([a-z]+)")
    return language == "ru" and "ru" or "en"
end

function PinLocale.getLanguage()
    -- An explicit KOReader preference always wins, even if it is unsupported.
    local settings = G_reader_settings
    local locale = settings and settings:readSetting("language")
    if hasLocale(locale) then return supportedLanguage(locale) end

    -- gettext also handles Android's system locale, which need not be in the env.
    local active = type(GetText) == "table" and GetText.current_lang
    if hasLocale(active) and active ~= "C" then return supportedLanguage(active) end

    -- KOReader may leave current_lang at C when a system catalog could not load.
    for _, variable in ipairs({ "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" }) do
        locale = os.getenv(variable)
        if hasLocale(locale) then return supportedLanguage(locale) end
    end
    return "en"
end

return setmetatable(PinLocale, {
    __call = function(_, message)
        if PinLocale.getLanguage() == "ru" then return russian[message] or message end
        if type(GetText) == "table" and GetText.wrapUntranslated then
            return GetText.wrapUntranslated(message)
        end
        return message
    end,
})
