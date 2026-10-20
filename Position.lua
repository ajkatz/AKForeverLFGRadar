-- Position: where you are, as the client tells it, and how far that is from a dungeon's door.
--
-- Every three seconds (and on every zone change) a SAMPLE is taken: inside an instance or not and which,
-- the map under your feet, your spot on it (C_Map.GetPlayerMapPosition - "only works for the player and
-- party members", nothing inside an instance) and that spot in the continent's own yards
-- (C_Map.GetWorldPosFromMapPos). The door of a dungeon is put through the same conversion, and the distance
-- is plain Pythagoras on one continent. The ladder of answers, best first - the user's words: "yards, if
-- possible; in zone next; inside obviously; another continent":
--     inside            you are in that very instance
--     at the entrance   within sixty yards of the door
--     1,240 yd          on the door's continent, with your spot known
--     in Westfall       the door's zone, when your spot is not known (no coordinates, no door yet)
--     another continent the door's continent is not yours
--     in Elwynn Forest  somewhere else, by zone name - or "in Gnomeregan" when you are in another instance
-- A peer's record is put through the same function: they send their spot, not their distance, so everyone
-- measures everyone against THEIR OWN pick.
--
-- LEARNING THE DOOR: the moment a sample says "inside" a listed instance and the one before it was outdoors,
-- the last outdoor spot (within twenty seconds) was the door you went through - kept for everyone
-- (Dungeons:Learn) and told to the others (Net).
local _, ns = ...

local Position = {}
ns.Position = Position

local SAMPLE_SECONDS = 3
local ENTRANCE_YARDS = 60
local LEARN_WINDOW = 20
local OUTDOOR_KEEP = 4
local MOVED_YARDS = 10

Position.sample = nil   -- the latest sample (fields below)
Position.outdoor = {}   -- the last outdoor samples with world coordinates, newest first
Position.changes = 0
Position.doors = {}     -- [entrance signature] = { continent, wx, wy } | false

local function plain(value)
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

-- a vector the map API takes: Blizzard's own when the client has it, a plain pair otherwise
local function vector(x, y)
    if type(CreateVector2D) == "function" then
        local ok, v = pcall(CreateVector2D, x, y)
        if ok and type(v) == "table" then
            return v
        end
    end
    return { x = x, y = y }
end

-- everything the client will say about where you are - readable values only
function Position.Read()
    local s = { at = GetTime() }
    local inst = ns.Readable(IsInInstance)
    s.inInstance = (inst and inst[1] == true) or false
    s.kind = inst and inst[2] or nil
    local info = ns.Readable(GetInstanceInfo)
    if info then
        s.instanceName, s.infoKind, s.instanceID = plain(info[1]), plain(info[2]), plain(info[8])
        if s.infoKind == "party" or s.infoKind == "raid" then
            s.inInstance = true -- IsInInstance said no (or nothing); the instance's own type says yes
            s.kind = s.kind or s.infoKind
        end
    end
    local zone = ns.Readable(GetRealZoneText)
    s.zone = zone and zone[1] or nil
    local sub = ns.Readable(GetSubZoneText)
    s.subzone = sub and sub[1] or nil
    if type(C_Map) == "table" then
        local map = ns.Readable(C_Map.GetBestMapForUnit, "player")
        s.uiMap = map and map[1] or nil
        if type(s.uiMap) == "number" then
            local mapInfo = ns.Readable(C_Map.GetMapInfo, s.uiMap)
            mapInfo = mapInfo and mapInfo[1]
            if type(mapInfo) == "table" and not ns.AnySecret(mapInfo.name, mapInfo.mapType) then
                s.mapName, s.mapType = mapInfo.name, mapInfo.mapType
            end
            local pos = ns.Readable(C_Map.GetPlayerMapPosition, s.uiMap, "player")
            pos = pos and pos[1]
            if type(pos) == "table" and not ns.AnySecret(pos.x, pos.y) and type(pos.x) == "number" and type(pos.y) == "number"
                and (pos.x > 0 or pos.y > 0) then
                s.x, s.y = pos.x, pos.y
                local world = ns.Readable(C_Map.GetWorldPosFromMapPos, s.uiMap, pos)
                local continent, at = world and world[1], world and world[2]
                if type(continent) == "number" and type(at) == "table" and not ns.AnySecret(at.x, at.y)
                    and type(at.x) == "number" and type(at.y) == "number" then
                    s.continent, s.wx, s.wy = continent, at.x, at.y
                end
            end
        else
            s.uiMap = nil
        end
    end
    return s
end

-- the door in the continent's yards; nil when the entrance has no coordinates or the map will not convert
function Position.Door(entrance)
    if not entrance or type(entrance.zoneMapID) ~= "number" or type(entrance.x) ~= "number" or type(entrance.y) ~= "number" then
        return nil
    end
    local signature = entrance.zoneMapID .. ":" .. entrance.x .. ":" .. entrance.y
    local cached = Position.doors[signature]
    if cached ~= nil then
        return cached or nil
    end
    local world = type(C_Map) == "table" and ns.Readable(C_Map.GetWorldPosFromMapPos, entrance.zoneMapID, vector(entrance.x, entrance.y)) or nil
    local continent, at = world and world[1], world and world[2]
    local door = false
    if type(continent) == "number" and type(at) == "table" and not ns.AnySecret(at.x, at.y) and type(at.x) == "number" and type(at.y) == "number" then
        door = { continent = continent, wx = at.x, wy = at.y }
    end
    Position.doors[signature] = door
    return door or nil
end

function Position.FormatYards(yards)
    local whole = math.floor(yards + 0.5)
    if whole < 1000 then
        return whole .. " yd"
    end
    return string.format("%d,%03d yd", math.floor(whole / 1000), whole % 1000)
end

-- { rank, yards, text } for a sample (yours or a peer's record in the same shape) against a dungeon
function Position.Proximity(s, dungeon)
    if not dungeon then
        return { rank = 9, text = "no dungeon picked" }
    end
    if not s then
        return { rank = 8, text = "not yet known" }
    end
    if s.inInstance then
        local here = ns.Dungeons:ByInstance(s.instanceID, s.instanceName)
        if ns.Dungeons.Same(here, dungeon) then
            return { rank = 0, text = "inside" }
        end
        return { rank = 5, text = "in " .. ((here and here.name) or s.instanceName or "an instance") }
    end
    local entrance = ns.Dungeons:Entrance(dungeon)
    local door = entrance and Position.Door(entrance)
    if door and type(s.continent) == "number" and type(s.wx) == "number" and type(s.wy) == "number" then
        if s.continent == door.continent then
            local yards = math.sqrt((s.wx - door.wx) ^ 2 + (s.wy - door.wy) ^ 2)
            if yards <= ENTRANCE_YARDS then
                return { rank = 1, yards = yards, text = "at the entrance" }
            end
            local sameZone = (entrance.zoneName and s.zone == entrance.zoneName) or (entrance.zoneMapID and s.uiMap == entrance.zoneMapID)
            return { rank = 2, yards = yards, text = Position.FormatYards(yards) .. ((not sameZone and s.zone) and (" - " .. s.zone) or "") }
        end
        return { rank = 6, text = "another continent" }
    end
    local zoneName = entrance and entrance.zoneName
    if zoneName and ((s.zone and s.zone == zoneName) or (entrance.zoneMapID and s.uiMap == entrance.zoneMapID)) then
        return { rank = 3, text = "in " .. zoneName }
    end
    if door and type(s.continent) == "number" and s.continent ~= door.continent then
        return { rank = 6, text = "another continent" }
    end
    if s.zone and s.zone ~= "" then
        return { rank = 4, text = "in " .. s.zone }
    end
    return { rank = 8, text = "somewhere" }
end

function Position:Mine()
    return Position.Proximity(self.sample, ns.Dungeons:Picked())
end

-- a zone's continent, from the middle of its map
local zoneContinents = {}
function Position.ZoneContinent(zoneMapID)
    if type(zoneMapID) ~= "number" then
        return nil
    end
    local cached = zoneContinents[zoneMapID]
    if cached ~= nil then
        return cached or nil
    end
    local world = type(C_Map) == "table" and ns.Readable(C_Map.GetWorldPosFromMapPos, zoneMapID, vector(0.5, 0.5)) or nil
    local continent = world and world[1]
    zoneContinents[zoneMapID] = type(continent) == "number" and continent or false
    return type(continent) == "number" and continent or nil
end

-- { rank, text } from nothing but the name of the area somebody is in: a listing's area, a /who answer
function Position.AreaProximity(area, dungeon)
    if not dungeon then
        return { rank = 9, text = "no dungeon picked" }
    end
    if type(area) ~= "string" or area == "" then
        return { rank = 8, text = "not placed yet" }
    end
    local here = ns.Dungeons:ByInstance(nil, area)
    if here then
        if ns.Dungeons.Same(here, dungeon) then
            return { rank = 0, text = "inside" }
        end
        return { rank = 5, text = "in " .. here.name }
    end
    local entrance = ns.Dungeons:Entrance(dungeon)
    if entrance and entrance.zoneName == area then
        return { rank = 3, text = "in " .. area }
    end
    local door = entrance and Position.Door(entrance)
    local continent = Position.ZoneContinent(ns.Dungeons:ZoneMapID(area))
    if door and continent and continent ~= door.continent then
        return { rank = 6, text = "another continent" }
    end
    return { rank = 4, text = "in " .. area }
end

------------------------------------------------------------------------
-- Sampling
------------------------------------------------------------------------
local function moved(a, b)
    if not a or not b then
        return true
    end
    if type(a.wx) == "number" and type(b.wx) == "number" and a.continent == b.continent then
        return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) >= MOVED_YARDS
    end
    return (a.wx ~= nil) ~= (b.wx ~= nil)
end

local function changed(a, b)
    if not a then
        return true
    end
    return a.inInstance ~= b.inInstance or a.instanceID ~= b.instanceID or a.instanceName ~= b.instanceName
        or a.uiMap ~= b.uiMap or a.zone ~= b.zone or moved(a, b)
end

local function learnDoor(previous, s)
    if not s.inInstance or (previous and previous.inInstance and previous.instanceID == s.instanceID and previous.instanceName == s.instanceName) then
        return
    end
    local dungeon = ns.Dungeons:ByInstance(s.instanceID, s.instanceName)
    if not dungeon then
        return
    end
    local door = Position.outdoor[1]
    if not door or s.at - door.at > LEARN_WINDOW or type(door.uiMap) ~= "number" or type(door.x) ~= "number" then
        ns:Log("door_not_learned", { key = dungeon.key, why = door and "the last outdoor spot is too old" or "no outdoor spot" })
        return
    end
    -- a summon can drop you into an instance from anywhere: a spot off the dungeon's own continent is no door
    local expected = ns.Dungeons:Entrance(dungeon)
    local known = expected and Position.Door(expected)
    if known and type(door.continent) == "number" and door.continent ~= known.continent then
        ns:Log("door_not_learned", { key = dungeon.key, why = "the last outdoor spot is on another continent than the dungeon's zone" })
        return
    end
    if ns.Dungeons:Learn(dungeon.key, door.uiMap, door.x, door.y, ns.playerName, "walked in") then
        ns:Fire("ENTRANCE_WALKED_IN", dungeon.key, ns.db.learned[dungeon.key])
    end
end

function Position:Update(reason)
    local previous = self.sample
    local s = Position.Read()
    self.sample = s
    if not s.inInstance and type(s.wx) == "number" then
        table.insert(self.outdoor, 1, s)
        self.outdoor[OUTDOOR_KEEP + 1] = nil
    end
    learnDoor(previous, s)
    if changed(previous, s) then
        self.changes = self.changes + 1
        ns:Log("position", { why = reason, inInstance = s.inInstance, instance = s.instanceID or s.instanceName, map = s.uiMap, zone = s.zone,
            x = s.x and math.floor(s.x * 1000) / 1000, y = s.y and math.floor(s.y * 1000) / 1000, continent = s.continent,
            wx = s.wx and math.floor(s.wx), wy = s.wy and math.floor(s.wy) })
        ns:Fire("POSITION_CHANGED", s, previous)
    end
    return s
end

ns:Listen("LOGIN", function()
    Position:Update("login")
    C_Timer.NewTicker(SAMPLE_SECONDS, function()
        ns.SafeCall(Position.Update, Position, "tick")
    end)
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    ns:On(event, function()
        if ns.db then
            Position:Update(event)
        end
    end)
end

ns:RegisterCommand("where", "where the client says you are, and how far from the picked dungeon", function()
    local s = Position:Update("command")
    local dungeon = ns.Dungeons:Picked()
    local where = s.inInstance and ("inside " .. tostring(s.instanceName or s.instanceID)) or (s.zone or "?")
    if s.x then
        where = where .. string.format(" (%.1f, %.1f)", s.x * 100, s.y * 100)
    end
    ns:Print("you:", where .. (s.continent and (" - continent " .. s.continent) or " - no coordinates here"))
    if dungeon then
        local entrance = ns.Dungeons:Entrance(dungeon)
        ns:Print(dungeon.name .. ":", Position.Proximity(s, dungeon).text
            .. (entrance and (" (door: " .. (entrance.zoneName or "?") .. (entrance.x and string.format(" %.1f, %.1f", entrance.x * 100, entrance.y * 100) or "") .. ", " .. entrance.source .. ")") or " (no door known)"))
    end
end)
