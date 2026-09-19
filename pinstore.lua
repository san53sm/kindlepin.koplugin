local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local PinStore = {}
PinStore.__index = PinStore

local function makeHash(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h * 16777619) % 4294967296
        h = (h + s:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function isSerializable(value)
    local t = type(value)
    return t == "string" or t == "number" or t == "boolean"
end

-- Keep only values that LuaSettings/dump can write.
local function sanitize(value, depth)
    depth = depth or 0
    if depth > 8 then
        return nil
    end
    local t = type(value)
    if isSerializable(value) then
        return value
    elseif t == "table" then
        local out = {}
        for k, v in pairs(value) do
            local sk = sanitize(k, depth + 1)
            local sv = sanitize(v, depth + 1)
            if sk ~= nil and sv ~= nil then
                out[sk] = sv
            end
        end
        return out
    end
    return nil
end

function PinStore:new()
    local o = setmetatable({}, self)
    local settings_dir = DataStorage:getSettingsDir()
    o.settings_path = settings_dir .. "/kindlepin.lua"
    o.media_dir = settings_dir .. "/kindlepin_media"
    o.settings = LuaSettings:open(o.settings_path)
    o._seq = 0
    return o
end

function PinStore:ensureMediaDir(doc_path)
    local book_dir = self.media_dir .. "/" .. makeHash(doc_path)
    if lfs.attributes(book_dir, "mode") ~= "directory" then
        if util.makePath then
            util.makePath(book_dir)
        else
            lfs.mkdir(self.media_dir)
            lfs.mkdir(book_dir)
        end
    end
    return book_dir
end

function PinStore:nextId()
    self._seq = self._seq + 1
    return string.format("%d-%d", os.time(), self._seq)
end

function PinStore:getPins(doc_path)
    if not doc_path then
        return {}
    end
    local pins = self.settings:readSetting(doc_path)
    if type(pins) ~= "table" then
        return {}
    end
    return pins
end

function PinStore:count(doc_path)
    return #self:getPins(doc_path)
end

function PinStore:listNewestFirst(doc_path)
    local pins = self:getPins(doc_path)
    local out = {}
    for i = #pins, 1, -1 do
        out[#out + 1] = pins[i]
    end
    return out
end

function PinStore:add(doc_path, pin)
    if not doc_path then
        return nil
    end
    pin = sanitize(pin) or {}
    pin.id = pin.id or self:nextId()
    pin.created_at = pin.created_at or os.time()
    local pins = self:getPins(doc_path)
    pins[#pins + 1] = pin
    self.settings:saveSetting(doc_path, pins)
    self:flush()
    return pin
end

function PinStore:delete(doc_path, pin_id)
    local pins = self:getPins(doc_path)
    local kept = {}
    local removed
    for i = 1, #pins do
        if pins[i].id == pin_id then
            removed = pins[i]
        else
            kept[#kept + 1] = pins[i]
        end
    end
    self.settings:saveSetting(doc_path, kept)
    if removed and removed.image_file then
        local ok, err = os.remove(removed.image_file)
        if not ok then
            logger.dbg("kindlepin: could not remove image", removed.image_file, err)
        end
    end
    self:flush()
    return removed
end

function PinStore:deleteAll(doc_path)
    local pins = self:getPins(doc_path)
    for i = 1, #pins do
        if pins[i].image_file then
            os.remove(pins[i].image_file)
        end
    end
    self.settings:delSetting(doc_path)
    self:flush()
end

function PinStore:imagePath(doc_path, pin_id)
    return self:ensureMediaDir(doc_path) .. "/" .. pin_id .. ".png"
end

function PinStore:flush()
    self.settings:flush()
end

return PinStore
