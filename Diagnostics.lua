-- Diagnostics: '/dr diag' writes a report into the saved file - where the client says you are and what it
-- made of it, the door of the picked dungeon and where it came from, the channel and everyone heard on it,
-- the last scans, every error. Nothing in it is a frame; every value is checked before it is copied so that
-- a secret cannot poison the file. The same report is written at logout.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function sanitize(value, depth)
    depth = depth or 0
    if ns.IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "table" then
        if depth >= 7 then
            return "<too deep>"
        end
        if type(value.GetObjectType) == "function" then
            return "<frame>"
        end
        local copy = {}
        for k, v in pairs(value) do
            local key = k
            if ns.IsSecret(k) then
                key = "<secret key>"
            elseif type(k) ~= "string" and type(k) ~= "number" then
                key = tostring(k)
            end
            copy[key] = sanitize(v, depth + 1)
        end
        return copy
    elseif kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "nil" then
        return nil
    end
    return "<" .. kind .. ">"
end

function Diagnostics:Collect()
    local dungeon = ns.Dungeons:Picked()
    local entrance = dungeon and ns.Dungeons:Entrance(dungeon) or nil
    local sample = ns.Position.sample
    local peers = {}
    for _, item in ipairs(ns.Net:Peers(dungeon)) do
        peers[#peers + 1] = { name = item.peer.name, class = item.peer.class, level = item.peer.level, dungeon = item.peer.dungeon, state = item.peer.state,
            zone = item.peer.zone, continent = item.peer.continent, age = math.floor(item.age), proximity = item.proximity.text, yards = item.proximity.yards and math.floor(item.proximity.yards) }
    end
    local mapIndexSize = 0
    for _ in pairs(ns.Dungeons.mapIndex or {}) do
        mapIndexSize = mapIndexSize + 1
    end
    return {
        version = ns.version, at = time(), character = ns.characterKey, class = ns.playerClass,
        savedState = ns.savedStateSource, loads = ns.db and ns.db.loads,
        options = sanitize(ns.db and ns.db.options),
        dungeon = dungeon and { key = dungeon.key, name = dungeon.name } or "none",
        entrance = sanitize(entrance),
        door = entrance and sanitize(ns.Position.Door(entrance)) or nil,
        proximity = sanitize(ns.Position:Mine()),
        position = sanitize(sample),
        positionChanges = ns.Position.changes,
        maps = { world = ns.Dungeons.worldMap, zonesIndexed = mapIndexSize, continents = sanitize(ns.Dungeons.continents), journal = sanitize(ns.Dungeons.journal) },
        dungeons = { discovered = sanitize(ns.Dungeons.discovered), count = #ns.Dungeons.list },
        learned = sanitize(ns.db and ns.db.learned),
        net = { stats = sanitize(ns.Net.stats), channel = ns.Net.channelID, peers = peers, share = ns:GetOption("share") },
        lfg = { stats = sanitize(ns.LFG.stats), listed = sanitize(ns.LFG.listed), docked = ns.Panel and ns.Panel:IsDocked() or false },
        lookups = sanitize(ns.Lookup:Describe()),
        panel = ns.Panel and sanitize(ns.Panel:Describe()) or nil,
        errors = sanitize(ns.errors),
        blocked = sanitize(ns.blocked),
        unknownEvents = sanitize(ns.unknownEvents),
        log = sanitize(ns.sessionLog),
    }
end

function Diagnostics:Save()
    if not ns.db then
        return nil
    end
    local report = self:Collect()
    ns.db.diag = report
    return report
end

ns:RegisterCommand("diag", "write a report into the saved file (for bug reports) and say the gist", function()
    local report = Diagnostics:Save()
    if not report then
        ns:Print("nothing to report yet.")
        return
    end
    local errors = 0
    for _ in pairs(ns.errors) do
        errors = errors + 1
    end
    ns:Print("report written (SavedVariables\\AKForeverLFGRadar.lua after a logout or /reload):",
        (type(report.dungeon) == "table" and report.dungeon.name or "no dungeon") .. ", you " .. tostring(report.proximity and report.proximity.text)
        .. ", door " .. tostring(report.entrance and report.entrance.source or "none") .. ", channel " .. tostring(report.net.channel or "not joined")
        .. ", " .. #report.net.peers .. " heard, " .. errors .. " error(s).")
end)

ns:On("PLAYER_LOGOUT", function()
    Diagnostics:Save()
end)
