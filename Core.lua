-- AKForeverLFGRadar core: namespace, safe calls, event dispatch, message bus, saved variables, the
-- character's profile, session log and slash commands.
--
-- The mission of this addon family, built for the WoW: Forever game mode: minimalistic UI additions that
-- bring out the utility Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth. So:
-- every entry point goes through ns.SafeCall, and every error is kept for the report.
--
-- What this addon is for (the user, 2026-10-15): "shows your proximity to a specific dungeon; everyone with
-- the addon should be able to see other people's proximity to the dungeon; it should also be able to guess
-- by /who-ing". Pick a dungeon; the panel says how far you are from its entrance - in yards when the client
-- gives your position, else the zone you are in, "inside" once you are, "another continent" when you are -
-- and the same for everyone running the addon, who tell each other where they are over a hidden chat
-- channel. The game's own group finder is followed and read: its listings for the dungeon, each placed the
-- same way, sorted by proximity and role.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
if string.find(ns.version, "@", 1, true) then
    ns.version = "dev" -- a working copy: the packager has not replaced the @project-version@ token
end
ns.version = (string.gsub(ns.version, "^v", ""))

local PRINT_PREFIX = "|cff5ec8e8LFGRadar|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(PRINT_PREFIX .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Secret values. WoW: Forever runs the Midnight-era API, where some values handed to addons may be held
-- but not inspected.
------------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or nil

function ns.IsSecret(value)
    if issecret then
        return issecret(value) and true or false
    end
    return false
end

function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- Call a client function; its results as a list, or nil when it errors or answers with anything secret.
function ns.Readable(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return nil
    end
    for i = 2, #results do
        if ns.IsSecret(results[i]) then
            return nil
        end
    end
    table.remove(results, 1)
    return results
end

------------------------------------------------------------------------
-- Safe calls: every distinct error is kept for the report.
------------------------------------------------------------------------
ns.errors = {}

local function onError(err)
    err = tostring(err)
    local seen = ns.errors[err]
    ns.errors[err] = (seen or 0) + 1
    if not seen then
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        end
    end
    return err
end

function ns.SafeCall(fn, ...)
    return xpcall(fn, onError, ...)
end

------------------------------------------------------------------------
-- Session log (ring buffer)
------------------------------------------------------------------------
local LOG_MAX = 160
ns.sessionLog = {}

function ns:Log(kind, data)
    local log = ns.sessionLog
    log[#log + 1] = {
        t = math.floor(GetTime() * 1000) / 1000,
        k = kind,
        d = data,
    }
    if #log > LOG_MAX then
        table.remove(log, 1)
    end
end

------------------------------------------------------------------------
-- Internal message bus
------------------------------------------------------------------------
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], ...)
    end
end

------------------------------------------------------------------------
-- Game events: one frame, handlers per event, every handler in a SafeCall
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.unknownEvents = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
        end
    end
    table.insert(eventHandlers[event], fn)
end

------------------------------------------------------------------------
-- Blocked actions: the client's word on an action it refused an addon - this one or another - with the
-- function's name, since "Interface action failed because of an AddOn" names nothing on screen. Kept for
-- the report; ours said once in the chat.
------------------------------------------------------------------------
ns.blocked = {}
local saidBlocked = {}
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    ns:On(event, function(_, addon, func) -- handlers get the event first
        addon = (not ns.IsSecret(addon) and type(addon) == "string") and addon or "?"
        func = (not ns.IsSecret(func) and type(func) == "string") and func or "?"
        local record = { event = event, addon = addon, func = func, at = math.floor(GetTime()) }
        ns.blocked[#ns.blocked + 1] = record
        if #ns.blocked > 40 then
            table.remove(ns.blocked, 1)
        end
        ns:Log("blocked", record)
        if addon == ADDON_NAME and not saidBlocked[func] then
            saidBlocked[func] = true
            ns:Print("the client blocked " .. func .. "() for this addon (" .. event .. ") - '/dr diag' keeps what led up to it.")
        end
    end)
end

------------------------------------------------------------------------
-- Saved variables: one account-wide table - the options and the learned entrances for every character
-- alike - and a profile per character (the dungeon picked, the panel's place), keyed "First Last - Realm"
-- as the client names you since build 70170 (the surname sits in the realm slot of UnitName; the name on
-- the wire is GetUnitName(unit, true)).
------------------------------------------------------------------------
local OPTION_DEFAULTS = {
    share = true,  -- tell the others where you are (positions go out over the hidden channel)
    shown = false, -- the panel on its own, finder closed ('/dr show'); beside the finder it shows with the finder
    dock = true,   -- ... beside the group finder window while that is open, and closes with it
}

local function initDB()
    if type(AKForeverLFGRadarDB) ~= "table" then
        AKForeverLFGRadarDB = {}
        ns.savedStateSource = "none (first run, or the client did not load it)"
    else
        ns.savedStateSource = "client"
    end
    local db = AKForeverLFGRadarDB
    db.schema = db.schema or 1
    db.loads = (db.loads or 0) + 1
    db.options = db.options or {}
    db.chars = db.chars or {}
    db.learned = db.learned or {} -- [dungeon key] = { zone = uiMapID, x, y, at, by, from = "walked in" | "peer" }
    ns.db = db
    ns.cdb = ns.cdb or {} -- a stand-in until the profile is bound at PLAYER_LOGIN
end

-- the name the client puts on the wire, plus the realm
function ns.PlayerKey()
    local name = ns.Readable(GetUnitName, "player", true)
    name = name and name[1]
    if type(name) ~= "string" or name == "" or name == "Unknown" then
        local short = ns.Readable(UnitName, "player")
        name = short and short[1]
    end
    local realm = ns.Readable(GetRealmName)
    realm = realm and realm[1]
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name .. " - " .. (type(realm) == "string" and realm or "?"), name
end

local function bindProfile()
    local key, name = ns.PlayerKey()
    ns.characterKey, ns.playerName = key, name
    if not key then
        ns.cdb = ns.cdb or {}
        return
    end
    ns.db.chars[key] = ns.db.chars[key] or {}
    local carried = ns.cdb
    ns.cdb = ns.db.chars[key]
    for k, v in pairs(carried or {}) do -- anything written before the name was known
        if ns.cdb[k] == nil then
            ns.cdb[k] = v
        end
    end
end

function ns:GetOption(key)
    local options = ns.db and ns.db.options
    local value = options and options[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

function ns:SetOption(key, value)
    ns.db.options[key] = value
    ns:Fire("OPTION_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Slash commands: modules register their own sub-commands; anything else is taken as a dungeon's name
------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function ns:RegisterCommand(name, help, fn)
    commands[name] = { help = help, fn = fn }
    commandOrder[#commandOrder + 1] = name
end

ns.fallbackCommand = nil -- set by Dungeons.lua: "/dr <dungeon>" picks one

SLASH_AKFOREVERLFGRADAR1 = "/akforeverlfgradar"
SLASH_AKFOREVERLFGRADAR2 = "/dr"
SLASH_AKFOREVERLFGRADAR3 = "/lr"
SlashCmdList["AKFOREVERLFGRADAR"] = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    local command = commands[string.lower(name or "")]
    if command then
        ns.SafeCall(command.fn, rest or "")
        return
    end
    if name and name ~= "" and ns.fallbackCommand and ns.fallbackCommand(message) then
        return
    end
    ns:Print("v" .. ns.version .. " - |cffffd100/dr <dungeon>|r picks one (a name or a tag: deadmines, sfk, brd ...). Commands:")
    for _, commandName in ipairs(commandOrder) do
        print("   |cffffd100/dr " .. commandName .. "|r - " .. commands[commandName].help)
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns.inCombat = false

ns:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()
end)

ns:On("PLAYER_LOGIN", function()
    if not ns.db then
        initDB()
    end
    bindProfile()
    local class = ns.Readable(UnitClass, "player")
    ns.playerClass = class and class[2] or nil
    ns.inCombat = InCombatLockdown() and true or false
    ns:Log("login", { version = ns.version, loads = ns.db.loads, savedState = ns.savedStateSource, character = ns.characterKey })
    ns:Fire("LOGIN")
end)

ns:On("PLAYER_REGEN_DISABLED", function()
    ns.inCombat = true
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    ns.inCombat = false
    ns:Fire("COMBAT_END")
end)
