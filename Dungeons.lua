-- Dungeons: the instances of WoW: Forever, where their doors are, and which one you have picked.
--
-- THE LIST comes from the game itself. The group finder's activity table names every dungeon of this realm
-- - Forever's own included - with the instance's map id, its level range and its size
-- (C_LFGList.GetAvailableActivities / GetActivityInfoTable); where the client has a dungeon journal
-- (EJ_GetInstanceByIndex) its instances are added by name. RAIDS ARE LEFT OUT (the user, 2026-10-16: "lets
-- get rid of raid options in the list"): the radar is for five-man groups; a raid is anything the finder
-- sizes above five, or the table marks so. The table below is what the old world knows by
-- heart: a short tag to type, the zone of the door, and a SEED for the door - the mine mouth, the cave, the
-- gate as players know them, to about a percent of the zone map, a hundred yards give or take. It is merged
-- into what the game lists; it never replaces it.
--
-- THE DOOR, best source first: a spot LEARNED by somebody who walked in with the addon on (your own eyes
-- first, then a peer's word); the map's own dungeon-entrance pin, looked for on every zone of the world
-- once (C_EncounterJournal.GetDungeonEntrancesForMap - whether this client has them for the old world is
-- read, never assumed); the seed; else only the zone, if known. Zones are named, not numbered: the zone's
-- uiMapID is looked up by name in the client's map tree, so the table holds no map ids another build could
-- renumber. The instance itself is known by the id GetInstanceInfo gives, which is the finder's mapID too.
local _, ns = ...

local Dungeons = {}
ns.Dungeons = Dungeons

-- x / y: percent of the zone map, as a player reads them off the map
local SEEDS = {
    { id = 389, name = "Ragefire Chasm", tag = "RFC", zone = "Orgrimmar", x = 52.8, y = 49.0, levels = "13-18" },
    { id = 43, name = "Wailing Caverns", tag = "WC", zone = "The Barrens", x = 42.1, y = 66.5, levels = "17-24" },
    { id = 36, name = "The Deadmines", tag = "DM", zone = "Westfall", x = 42.6, y = 71.6, levels = "18-23" },
    { id = 33, name = "Shadowfang Keep", tag = "SFK", zone = "Silverpine Forest", x = 44.8, y = 67.8, levels = "22-30" },
    { id = 48, name = "Blackfathom Deeps", tag = "BFD", zone = "Ashenvale", x = 14.3, y = 14.8, levels = "24-32" },
    { id = 34, name = "The Stockade", tag = "STOCKS", zone = "Stormwind City", x = 50.4, y = 66.6, levels = "24-32" },
    { id = 90, name = "Gnomeregan", tag = "GNOMER", zone = "Dun Morogh", x = 24.4, y = 39.7, levels = "29-38" },
    { id = 47, name = "Razorfen Kraul", tag = "RFK", zone = "The Barrens", x = 42.3, y = 89.9, levels = "29-38" },
    { id = 189, name = "Scarlet Monastery", tag = "SM", zone = "Tirisfal Glades", x = 82.7, y = 32.3, levels = "34-45" },
    { id = 129, name = "Razorfen Downs", tag = "RFD", zone = "The Barrens", x = 50.8, y = 92.3, levels = "37-46" },
    { id = 70, name = "Uldaman", tag = "ULDA", zone = "Badlands", x = 42.4, y = 18.6, levels = "41-51" },
    { id = 209, name = "Zul'Farrak", tag = "ZF", zone = "Tanaris", x = 38.7, y = 20.2, levels = "44-54" },
    { id = 349, name = "Maraudon", tag = "MARA", zone = "Desolace", x = 29.2, y = 62.4, levels = "46-55" },
    { id = 109, name = "The Temple of Atal'Hakkar", tag = "ST", zone = "Swamp of Sorrows", x = 69.9, y = 53.5, levels = "50-56" },
    { id = 230, name = "Blackrock Depths", tag = "BRD", zone = "Burning Steppes", x = 29.7, y = 37.6, levels = "52-60" },
    { id = 229, name = "Blackrock Spire", tag = "BRS", zone = "Burning Steppes", x = 29.7, y = 37.6, levels = "55-60" },
    { id = 429, name = "Dire Maul", tag = "DIRE", zone = "Feralas", x = 59.5, y = 44.5, levels = "55-60" },
    { id = 289, name = "Scholomance", tag = "SCHOLO", zone = "Western Plaguelands", x = 69.3, y = 72.6, levels = "58-60" },
    { id = 329, name = "Stratholme", tag = "STRAT", zone = "Eastern Plaguelands", x = 27.2, y = 11.5, levels = "58-60" },
    { id = 249, name = "Onyxia's Lair", tag = "ONY", zone = "Dustwallow Marsh", x = 52.4, y = 76.8, levels = "60", raid = true },
    { id = 409, name = "Molten Core", tag = "MC", zone = "Burning Steppes", x = 29.7, y = 37.6, levels = "60", raid = true },
    { id = 469, name = "Blackwing Lair", tag = "BWL", zone = "Burning Steppes", x = 29.7, y = 37.6, levels = "60", raid = true },
    { id = 309, name = "Zul'Gurub", tag = "ZG", zone = "Stranglethorn Vale", x = 53.1, y = 17.1, levels = "60", raid = true },
    { id = 509, name = "Ruins of Ahn'Qiraj", tag = "AQ20", zone = "Silithus", x = 28.6, y = 92.4, levels = "60", raid = true },
    { id = 531, name = "Temple of Ahn'Qiraj", tag = "AQ40", zone = "Silithus", x = 28.6, y = 92.4, levels = "60", raid = true },
    { id = 533, name = "Naxxramas", tag = "NAXX", zone = "Eastern Plaguelands", x = 39.6, y = 25.9, levels = "60", raid = true },
    -- Forever's nine (level ranges and zones as the guides of October 2026 give them; the finder's own
    -- suggested levels replace these wherever it has them; no door known by heart - the map's pins and
    -- the first walk-in give that)
    { name = "Hall of Thanes", tag = "THANES", zone = "Ironforge", levels = "13-18" },
    { id = 2999, name = "Ruins of Lordaeron", tag = "LORDAERON", zone = "Tirisfal Glades", levels = "15-20" },
    { name = "Excavation Site: Wetlands", tag = "EXCAV", zone = "Wetlands", levels = "24-29" },
    { name = "City of Dalaran", tag = "DALARAN", zone = "Alterac Mountains", levels = "28-33" },
    { name = "The Drowned City", tag = "DROWNED", zone = "Stranglethorn Vale", levels = "35-40" },
    { name = "Krol'dok Stronghold", tag = "KROLDOK", zone = "Riverglades", levels = "40-45" },
    { name = "Alcaz Island Prison", tag = "ALCAZ", zone = "Dustwallow Marsh", levels = "48-53" },
    { name = "Blackmaw Hold", tag = "BLACKMAW", zone = "Azshara", levels = "55-60" },
    { name = "Shaper's Terrace", tag = "SHAPERS", zone = "Un'Goro Crater", levels = "58-60" },
}

local DUNGEONS, BY_KEY, BY_NAME, BY_TAG, BY_ACTIVITY = {}, {}, {}, {}, {}
Dungeons.list = DUNGEONS
Dungeons.journal = {}   -- what the map's pin lookup said, per zone: "n pins" | "no API" | "error: ..."
Dungeons.mapIndex = nil -- [zone name] = uiMapID, from the map tree; nil until built
Dungeons.pins = nil     -- [lower-case instance name] = { zoneMapID, zoneName, x, y, journalInstanceID }; nil until built
Dungeons.discovered = { finder = 0, journal = 0 }

local function lower(text)
    return type(text) == "string" and string.lower(text) or nil
end

local function plain(value)
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

-- a tag to type for a name the table does not know: the initials of its words, "of"/"the" left out
local function tagFor(name)
    local letters = {}
    for word in string.gmatch(name, "%a+") do
        local w = string.lower(word)
        if w ~= "the" and w ~= "of" then
            letters[#letters + 1] = string.upper(string.sub(word, 1, 1))
        end
    end
    local tag = table.concat(letters)
    if #tag < 2 then
        tag = string.upper((string.gsub(name, "%W", "")):sub(1, 4))
    end
    local candidate, n = tag, 1
    while BY_TAG[candidate] do
        n = n + 1
        candidate = tag .. n
    end
    return candidate
end

-- the words of a name that tell instances apart ("the" and "of" do not)
local function words(name)
    local set, count = {}, 0
    for word in string.gmatch(string.lower(name or ""), "%w+") do
        if word ~= "the" and word ~= "of" then
            set[word] = true
            count = count + 1
        end
    end
    return set, count
end

-- "Alcaz Prison" and "Alcaz Island Prison", "Excavation Site" and "Excavation Site: Wetlands", a wing and
-- its instance: the shorter name's words are all in the longer one's
local function sameInstance(a, b)
    local wa, na = words(a)
    local wb, nb = words(b)
    if na == 0 or nb == 0 then
        return false
    end
    local small, big = wa, wb
    if na > nb then
        small, big = wb, wa
    end
    for word in pairs(small) do
        if not big[word] then
            return false
        end
    end
    return true
end

local function findByWords(name, withoutIdOnly)
    for _, entry in ipairs(DUNGEONS) do
        if entry.name and (not withoutIdOnly or not entry.id) and sameInstance(entry.name, name) then
            return entry
        end
    end
    return nil
end

local function parseLevels(levels)
    if type(levels) ~= "string" then
        return nil
    end
    local low, high = string.match(levels, "^(%d+)%-?(%d*)$")
    low = tonumber(low)
    return low, tonumber(high) or low
end

-- a key that travels (the channel, the saved pick): letters, digits and hyphens
local function slug(name)
    return (string.gsub(string.lower(name or ""), "[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- lowest level range first, the unknown last; a wing right after its instance, wings by their own range
local function levelsBefore(a, b)
    local aLow, aHigh = parseLevels(a.levels)
    local bLow, bHigh = parseLevels(b.levels)
    if (aLow ~= nil) ~= (bLow ~= nil) then
        return aLow ~= nil, true
    end
    if aLow and aLow ~= bLow then
        return aLow < bLow, true
    end
    if aHigh and aHigh ~= bHigh then
        return aHigh < bHigh, true
    end
    return nil, false
end

function Dungeons:Sort()
    table.sort(DUNGEONS, function(a, b)
        local pa = a.parentKey and BY_KEY[a.parentKey] or a
        local pb = b.parentKey and BY_KEY[b.parentKey] or b
        if pa ~= pb then
            local before, decided = levelsBefore(pa, pb)
            if decided then
                return before
            end
            if not parseLevels(pa.levels) and pa.order ~= pb.order then
                return pa.order < pb.order
            end
            return (pa.name or "") < (pb.name or "")
        end
        -- the same instance: the instance itself first, then its wings by their own range
        if (a == pa) ~= (b == pa) then
            return a == pa
        end
        local before, decided = levelsBefore(a, b)
        if decided then
            return before
        end
        return (a.name or "") < (b.name or "")
    end)
    for index, entry in ipairs(DUNGEONS) do
        entry.order = index
    end
end

-- a wing's tag: the instance's and the first letters of what the wing is called ("Scarlet Monastery -
-- Graveyard" -> SMGRA, "Lower Blackrock Spire" -> BRSLOW)
local function wingTag(primary, name)
    local own = words(primary.name or "")
    local extra
    for word in string.gmatch(string.lower(name), "%a+") do
        if word ~= "the" and word ~= "of" and not own[word] then
            extra = word
            break
        end
    end
    local tag = (primary.tag or "") .. string.upper(string.sub(extra or "wing", 1, 3))
    local candidate, n = tag, 1
    while BY_TAG[candidate] do
        n = n + 1
        candidate = tag .. n
    end
    return candidate
end

-- what a winged instance is called, from the names of its wings: the table's name when every wing carries
-- it ("Scarlet Monastery" in "Scarlet Monastery - Graveyard"); else the words the wings' names share at the
-- front ("Dire Maul" of "Dire Maul - East") or at the back ("Blackrock Spire" of "Lower Blackrock Spire");
-- else the first name
local function stemOf(names, tableName)
    if tableName then
        local all = true
        for _, name in ipairs(names) do
            local small, big = words(tableName), words(name)
            for word in pairs(small) do
                if not big[word] then
                    all = false
                end
            end
        end
        if all then
            return tableName
        end
    end
    local function split(name)
        local list = {}
        for word in string.gmatch(name, "%w+") do
            list[#list + 1] = word
        end
        return list
    end
    local first = split(names[1])
    local function shared(fromFront)
        local count = #first
        for index = 2, #names do
            local other = split(names[index])
            local same = 0
            while same < count and same < #other do
                local a = fromFront and first[same + 1] or first[#first - same]
                local b = fromFront and other[same + 1] or other[#other - same]
                if string.lower(a) ~= string.lower(b) then
                    break
                end
                same = same + 1
            end
            count = same
        end
        if count == 0 or count == #first then
            return nil
        end
        local kept = {}
        for index = 1, count do
            kept[index] = fromFront and first[index] or first[#first - count + index]
        end
        return table.concat(kept, " ")
    end
    return shared(true) or shared(false) or names[1]
end

-- the finder's activity for a wing of an instance already on the list (the same map id, another name):
-- an entry of its own under the instance - "Scarlet Monastery - Graveyard" under "Scarlet Monastery"
local function registerWing(primary, given)
    local key = tostring(given.id) .. ":" .. slug(given.name)
    local entry = BY_KEY[key]
    if not entry then
        local tag = (type(given.short) == "string" and given.short ~= "" and not BY_TAG[given.short]) and given.short or wingTag(primary, given.name)
        entry = { key = key, id = given.id, parentKey = primary.key, name = given.name, levels = given.levels, categoryID = given.categoryID,
            tag = tag, order = #DUNGEONS + 1, activities = {} }
        DUNGEONS[#DUNGEONS + 1] = entry
        BY_KEY[key] = entry
        BY_TAG[entry.tag] = entry
        primary.wings = primary.wings or {}
        table.insert(primary.wings, entry)
    elseif given.levels and given.levels ~= "" then
        entry.levels = given.levels
    end
    if not BY_NAME[lower(given.name)] then
        BY_NAME[lower(given.name)] = entry
    end
    return entry
end

-- one entry per instance: the same instance from another source fills what is missing; the game's own word
-- (authoritative: the finder) replaces the table's name and level range
local function register(given, authoritative)
    if given.raid then
        return nil -- raids are not on the list
    end
    local key = given.id and tostring(given.id) or given.name
    local entry = BY_KEY[key] or (given.name and BY_NAME[lower(given.name)]) or nil
    if not entry and given.name then
        entry = findByWords(given.name, given.id ~= nil)
    end
    if not entry then
        entry = { key = key, order = #DUNGEONS + 1, activities = {} }
        DUNGEONS[#DUNGEONS + 1] = entry
        BY_KEY[key] = entry
    end
    if given.id and not entry.id then
        entry.id = given.id
        if entry.key ~= tostring(given.id) then -- known by name so far: now by id too
            BY_KEY[tostring(given.id)] = entry
        end
    end
    if authoritative then
        for _, field in ipairs({ "name", "levels" }) do
            if given[field] ~= nil and given[field] ~= "" then
                entry[field] = given[field]
            end
        end
    end
    for _, field in ipairs({ "name", "zone", "x", "y", "levels", "raid", "categoryID", "journalID" }) do
        if entry[field] == nil and given[field] ~= nil then
            entry[field] = given[field]
        end
    end
    if given.name and not BY_NAME[lower(given.name)] then
        BY_NAME[lower(given.name)] = entry -- every name it ever had finds it
    end
    if given.tag and not entry.tag then
        entry.tag = given.tag
    end
    if authoritative and type(given.short) == "string" and given.short ~= "" and given.short ~= entry.tag then
        local holder = BY_TAG[given.short]
        if not holder or holder == entry then
            if entry.tag and BY_TAG[entry.tag] == entry then
                BY_TAG[entry.tag] = nil
            end
            entry.tag = given.short -- the finder's own short name, as its dropdown shows it
        end
    end
    if entry.name and not BY_NAME[lower(entry.name)] then
        BY_NAME[lower(entry.name)] = entry
    end
    if not entry.tag and entry.name then
        entry.tag = tagFor(entry.name)
    end
    if entry.tag then
        BY_TAG[entry.tag] = entry
    end
    return entry
end

for _, seed in ipairs(SEEDS) do
    register(seed)
end
Dungeons:Sort()

-- the finder's own colouring of an activity against your level: trivial when you are past its range,
-- difficult when you are under it, plain otherwise
local COLOR_TRIVIAL, COLOR_DIFFICULT, COLOR_PLAIN = "|cff808080", "|cffff2020", "|cffffffff"
function Dungeons:LevelColor(dungeon)
    local low, high = parseLevels(dungeon and dungeon.levels)
    local level = ns.Readable(UnitLevel, "player")
    level = level and level[1]
    if not low or type(level) ~= "number" then
        return COLOR_PLAIN
    end
    if high < level then
        return COLOR_TRIVIAL
    elseif low > level then
        return COLOR_DIFFICULT
    end
    return COLOR_PLAIN
end

function Dungeons:ParseLevels(levels)
    return parseLevels(levels)
end

------------------------------------------------------------------------
-- Discovery: the finder's activities, then the journal
------------------------------------------------------------------------
local function finderCategories(list)
    local ids = ns.Readable(list.GetAvailableCategories)
    ids = ids and ids[1]
    if type(ids) == "table" and #ids > 0 then
        return ids
    end
    local found = {}
    for id = 1, 200 do
        local info = ns.Readable(list.GetLfgCategoryInfo, id)
        if info and type(info[1]) == "table" then
            found[#found + 1] = id
        end
    end
    return found
end

function Dungeons:Discover(reason)
    local before = #DUNGEONS
    local list = type(C_LFGList) == "table" and C_LFGList or nil
    local fromFinder = 0
    if list and type(list.GetAvailableActivities) == "function" and type(list.GetActivityInfoTable) == "function" then
        -- the finder's dungeon activities, gathered by instance map first: an instance the finder lists under
        -- SEVERAL names with one map id has wings (the Monastery's four, Dire Maul's three, Stratholme's two,
        -- the two Spires); under one name, whatever it is, it is the instance itself spelt the finder's way
        local byMap, mapOrder = {}, {}
        for _, categoryID in ipairs(finderCategories(list)) do
            local ids = ns.Readable(list.GetAvailableActivities, categoryID)
            ids = ids and ids[1]
            for _, activityID in ipairs(type(ids) == "table" and ids or {}) do
                local info = ns.Readable(list.GetActivityInfoTable, activityID)
                info = info and info[1]
                if type(info) == "table" then
                    local mapID, fullName, shortName = plain(info.mapID), plain(info.fullName), plain(info.shortName)
                    local suggested, required, maxLevel, players = plain(info.minLevelSuggestion), plain(info.minLevel), plain(info.maxLevelSuggestion), plain(info.maxNumPlayers)
                    if type(mapID) == "number" and mapID > 0 and type(fullName) == "string" and fullName ~= "" and plain(info.isPvpActivity) ~= true then
                        -- the finder's own level filter goes by the SUGGESTED range (minLevelSuggestion / maxLevelSuggestion);
                        -- the required level is the fallback when no suggestion is set
                        local low = (type(suggested) == "number" and suggested > 0) and suggested or ((type(required) == "number" and required > 0) and required or nil)
                        local high = (low and type(maxLevel) == "number" and maxLevel > low) and maxLevel or low
                        if not byMap[mapID] then
                            byMap[mapID] = {}
                            mapOrder[#mapOrder + 1] = mapID
                        end
                        table.insert(byMap[mapID], { activityID = activityID, name = fullName, short = (type(shortName) == "string" and shortName ~= "") and shortName or nil,
                            low = low, high = high, levels = low and (high > low and (low .. "-" .. high) or tostring(low)) or nil,
                            raid = (type(players) == "number" and players > 5) or nil, categoryID = categoryID })
                    end
                end
            end
        end
        local function note(target, activityID)
            for _, id in ipairs(target.activities) do
                if id == activityID then
                    return
                end
            end
            table.insert(target.activities, activityID)
        end
        for _, mapID in ipairs(mapOrder) do
            local activities = byMap[mapID]
            local names, distinct, raid, low, high = {}, {}, nil, nil, nil
            for _, activity in ipairs(activities) do
                if not names[lower(activity.name)] then
                    names[lower(activity.name)] = true
                    distinct[#distinct + 1] = activity.name
                end
                raid = raid or activity.raid
                if activity.low and (not low or activity.low < low) then
                    low = activity.low
                end
                if activity.high and (not high or activity.high > high) then
                    high = activity.high
                end
            end
            if #distinct <= 1 then
                local first = activities[1]
                local entry = register({ id = mapID, name = first.name, short = first.short, levels = first.levels, raid = raid, categoryID = first.categoryID }, true)
                if entry then
                    for _, activity in ipairs(activities) do
                        note(entry, activity.activityID)
                        BY_ACTIVITY[activity.activityID] = entry
                        fromFinder = fromFinder + 1
                    end
                end
            elseif not raid then
                local known = BY_KEY[tostring(mapID)]
                local span = low and (high > low and (low .. "-" .. high) or tostring(low)) or nil
                local primary = register({ id = mapID, name = stemOf(distinct, known and known.name), levels = span, categoryID = activities[1].categoryID }, true)
                if primary then
                    for _, activity in ipairs(activities) do
                        local wing = registerWing(primary, { id = mapID, name = activity.name, short = activity.short, levels = activity.levels, categoryID = activity.categoryID })
                        note(wing, activity.activityID)
                        note(primary, activity.activityID) -- the instance itself stands for every wing
                        BY_ACTIVITY[activity.activityID] = wing
                        fromFinder = fromFinder + 1
                    end
                end
            end
        end
    end
    local fromJournal = 0
    if type(EJ_GetNumTiers) == "function" and type(EJ_SelectTier) == "function" and type(EJ_GetInstanceByIndex) == "function" then
        local tiers = ns.Readable(EJ_GetNumTiers)
        for tier = 1, (tiers and type(tiers[1]) == "number" and tiers[1]) or 1 do
            pcall(EJ_SelectTier, tier)
            for index = 1, 60 do -- dungeons only: the journal's raids are not asked for
                local found = ns.Readable(EJ_GetInstanceByIndex, index, false)
                local journalID, name = found and found[1], found and found[2]
                if type(journalID) ~= "number" then
                    break
                end
                if type(name) == "string" and name ~= "" and register({ name = name, journalID = journalID }) then
                    fromJournal = fromJournal + 1
                end
            end
        end
    end
    self.discovered = { finder = fromFinder, journal = fromJournal, total = #DUNGEONS }
    self:Sort()
    if #DUNGEONS ~= before or fromFinder > 0 then
        ns:Log("dungeons_discovered", { why = reason, finder = fromFinder, journal = fromJournal, total = #DUNGEONS, new = #DUNGEONS - before })
        ns:Fire("DUNGEONS_CHANGED")
    end
    return #DUNGEONS - before
end

function Dungeons:Get(key)
    return key and BY_KEY[key] or nil
end

function Dungeons:ByActivity(activityID)
    return activityID and BY_ACTIVITY[activityID] or nil
end

-- the instance a wing belongs to (itself for an instance)
function Dungeons:BaseOf(dungeon)
    return dungeon and dungeon.parentKey and BY_KEY[dungeon.parentKey] or dungeon
end

-- a wing's own part of its name: "Graveyard" of "Scarlet Monastery - Graveyard"; a name that does not
-- start with the instance's ("Lower Blackrock Spire") stays whole
function Dungeons:ShortName(dungeon)
    local base = self:BaseOf(dungeon)
    if not dungeon or base == dungeon or not base.name or not dungeon.name then
        return dungeon and dungeon.name or ""
    end
    if string.sub(lower(dungeon.name), 1, #base.name) == lower(base.name) then
        local rest = string.match(string.sub(dungeon.name, #base.name + 1), "^[%s%p]*(.-)%s*$")
        if rest and rest ~= "" then
            return rest
        end
    end
    return dungeon.name
end

-- the same instance, wing or whole
function Dungeons.Same(a, b)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end
    return a.id ~= nil and a.id == b.id
end

-- does a listing for `theirs` belong under the pick `mine`? itself, or any wing of a whole instance
function Dungeons.Covers(mine, theirs)
    if not mine or not theirs then
        return false
    end
    return mine == theirs or theirs.parentKey == mine.key
end

-- the door is the instance's, whichever wing was picked
local function doorKey(dungeon)
    return dungeon.id and tostring(dungeon.id) or dungeon.key
end

function Dungeons:ByInstance(instanceID, instanceName)
    return (type(instanceID) == "number" and BY_KEY[tostring(instanceID)]) or (type(instanceName) == "string" and BY_NAME[lower(instanceName)]) or nil
end

-- "deadmines", "dm", "the deadmines", "dead" - the dungeon meant, or nil and the candidates when several fit
function Dungeons:Find(text)
    local wanted = lower(string.match(text or "", "^%s*(.-)%s*$"))
    if not wanted or wanted == "" then
        return nil
    end
    local exact = BY_NAME[wanted]
    if exact then
        return exact
    end
    local hits = {}
    for _, dungeon in ipairs(DUNGEONS) do
        local name, tag = lower(dungeon.name) or "", lower(dungeon.tag) or ""
        if tag == wanted then
            return dungeon
        end
        if string.find(name, wanted, 1, true) or string.find((string.gsub(name, "^the ", "")), "^" .. (string.gsub(wanted, "%W", "%%%0")))
            or string.find(tag, wanted, 1, true) then
            hits[#hits + 1] = dungeon
        end
    end
    if #hits == 1 then
        return hits[1]
    end
    return nil, hits
end

------------------------------------------------------------------------
-- The map tree: zone name -> uiMapID, built once from wherever you stand up to the world and down again
------------------------------------------------------------------------
local ZONE, CONTINENT, WORLD = 3, 2, 1 -- Enum.UIMapType.Zone / Continent / World

local function mapInfo(uiMapID)
    local info = ns.Readable(C_Map and C_Map.GetMapInfo, uiMapID)
    info = info and info[1]
    if type(info) ~= "table" or ns.AnySecret(info.name, info.mapType, info.parentMapID) then
        return nil
    end
    return info
end

function Dungeons:BuildMapIndex()
    if self.mapIndex then
        return self.mapIndex
    end
    if type(C_Map) ~= "table" then
        return nil
    end
    local here = ns.Readable(C_Map.GetBestMapForUnit, "player")
    here = here and here[1]
    if type(here) ~= "number" then
        return nil
    end
    local top, guard = here, 0
    while guard < 12 do
        guard = guard + 1
        local info = mapInfo(top)
        if not info then
            break
        end
        if info.mapType == WORLD or not info.parentMapID or info.parentMapID == 0 then
            break
        end
        top = info.parentMapID
    end
    local children = ns.Readable(C_Map.GetMapChildrenInfo, top, nil, true)
    children = children and children[1]
    if type(children) ~= "table" then
        return nil
    end
    local index, continents = {}, {}
    for _, child in ipairs(children) do
        if type(child) == "table" and not ns.AnySecret(child.name, child.mapID, child.mapType, child.parentMapID) then
            if child.mapType == ZONE and type(child.name) == "string" and not index[child.name] then
                index[child.name] = child.mapID
            elseif child.mapType == CONTINENT and type(child.name) == "string" then
                continents[child.mapID] = child.name
            end
        end
    end
    local topInfo = mapInfo(top)
    if topInfo and topInfo.mapType == ZONE and type(topInfo.name) == "string" then
        index[topInfo.name] = index[topInfo.name] or top
    end
    self.mapIndex, self.continents, self.worldMap = index, continents, top
    local count = 0
    for _ in pairs(index) do
        count = count + 1
    end
    ns:Log("map_index", { world = top, zones = count })
    return index
end

function Dungeons:ZoneMapID(zoneName)
    local index = self:BuildMapIndex()
    return index and zoneName and index[zoneName] or nil
end

function Dungeons:ZoneName(zoneMapID)
    local index = self:BuildMapIndex()
    for name, id in pairs(index or {}) do
        if id == zoneMapID then
            return name
        end
    end
    local info = mapInfo(zoneMapID)
    return info and info.name or nil
end

------------------------------------------------------------------------
-- The map's own entrance pins, every zone of the world asked once
------------------------------------------------------------------------
function Dungeons:BuildPinIndex()
    if self.pins then
        return self.pins
    end
    local ask = C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
    local index = self:BuildMapIndex()
    if type(ask) ~= "function" then
        self.journal.api = "none"
        self.pins = {}
        return self.pins
    end
    if not index then
        return nil -- the map tree is not readable yet: try again later
    end
    local pins, zonesWithPins, total = {}, 0, 0
    for zoneName, zoneMapID in pairs(index) do
        local ok, list = pcall(ask, zoneMapID)
        if not ok then
            self.journal[zoneName] = "error: " .. tostring(list)
        elseif ns.IsSecret(list) or type(list) ~= "table" then
            self.journal[zoneName] = "nothing readable"
        else
            local count = 0
            for _, pin in ipairs(list) do
                local position = type(pin) == "table" and pin.position or nil
                local name = type(pin) == "table" and plain(pin.name) or nil
                if type(position) == "table" and type(name) == "string" and not ns.AnySecret(position.x, position.y, pin.journalInstanceID)
                    and type(position.x) == "number" and type(position.y) == "number" then
                    local record = { zoneMapID = zoneMapID, zoneName = zoneName, x = position.x, y = position.y, name = name, journalInstanceID = pin.journalInstanceID }
                    if not pins[lower(name)] then
                        pins[lower(name)] = record
                    end
                    if type(pin.journalInstanceID) == "number" and not pins[pin.journalInstanceID] then
                        pins[pin.journalInstanceID] = record
                    end
                    count = count + 1
                end
            end
            if count > 0 then
                zonesWithPins = zonesWithPins + 1
                total = total + count
                self.journal[zoneName] = count .. " pins"
            end
        end
    end
    self.journal.summary = total .. " pins on " .. zonesWithPins .. " zones"
    self.pins = pins
    ns:Log("entrance_pins", { pins = total, zones = zonesWithPins })
    return pins
end

local function pinFor(dungeon)
    local pins = Dungeons:BuildPinIndex()
    if not pins then
        return nil
    end
    if dungeon.journalID and pins[dungeon.journalID] then
        return pins[dungeon.journalID]
    end
    local wanted = lower(dungeon.name)
    if wanted and pins[wanted] then
        return pins[wanted]
    end
    for key, pin in pairs(pins) do
        if type(key) == "string" and wanted and (string.find(key, wanted, 1, true) or string.find(wanted, key, 1, true)) then
            return pin
        end
    end
    return nil
end

------------------------------------------------------------------------
-- The entrance: { zoneMapID, zoneName, x, y (0..1), source } - or only the zone's name, or nothing
------------------------------------------------------------------------
function Dungeons:Entrance(dungeon)
    if not dungeon then
        return nil
    end
    dungeon = self:BaseOf(dungeon) -- a wing's door is its instance's
    local learned = ns.db and ns.db.learned and ns.db.learned[doorKey(dungeon)]
    if learned and type(learned.zone) == "number" and type(learned.x) == "number" and type(learned.y) == "number" then
        return { zoneMapID = learned.zone, zoneName = self:ZoneName(learned.zone) or dungeon.zone, x = learned.x, y = learned.y,
            source = learned.from == "peer" and ("learned by " .. tostring(learned.by)) or "learned (you walked in)" }
    end
    local pin = pinFor(dungeon)
    if pin then
        return { zoneMapID = pin.zoneMapID, zoneName = pin.zoneName, x = pin.x, y = pin.y, source = "the map's own pin" }
    end
    local zoneMapID = dungeon.zone and self:ZoneMapID(dungeon.zone) or nil
    if dungeon.x and dungeon.y then
        return { zoneMapID = zoneMapID, zoneName = dungeon.zone, x = dungeon.x / 100, y = dungeon.y / 100, source = "seed (about a percent of the map)" }
    end
    if dungeon.zone then
        return { zoneMapID = zoneMapID, zoneName = dungeon.zone, source = "zone only" }
    end
    return nil
end

-- somebody walked in: the spot in front of the door, kept for everyone
function Dungeons:Learn(key, zoneMapID, x, y, by, from)
    if not ns.db or not BY_KEY[key] or type(zoneMapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    key = doorKey(BY_KEY[key])
    local have = ns.db.learned[key]
    if have and have.from ~= "peer" and from == "peer" then
        return false -- your own eyes beat a peer's word
    end
    if have and have.from == "peer" and from == "peer" and have.by == by and math.abs(have.x - x) < 0.0005 and math.abs(have.y - y) < 0.0005 then
        return false -- the same word again
    end
    ns.db.learned[key] = { zone = zoneMapID, x = x, y = y, at = time(), by = by, from = from }
    ns:Log("entrance_learned", { key = key, zone = zoneMapID, x = x, y = y, by = by, from = from })
    ns:Fire("ENTRANCES_CHANGED", key)
    return true
end

------------------------------------------------------------------------
-- The pick, per character
------------------------------------------------------------------------
function Dungeons:Picked()
    return self:Get(ns.cdb and ns.cdb.dungeon)
end

-- how: "click" (the panel's picker) or "slash" (a command) - a hardware event, so the finder may be searched
-- from it; nil when the finder's own listing or filter chose
function Dungeons:Pick(dungeon, how)
    local key = dungeon and dungeon.key or nil
    if (ns.cdb.dungeon or false) == (key or false) then
        return
    end
    ns.cdb.dungeon = key
    ns:Log("picked", { key = key or "none", how = how })
    ns:Fire("PICK_CHANGED", dungeon, how)
end

ns.fallbackCommand = function(text)
    local dungeon, hits = Dungeons:Find(text)
    if dungeon then
        Dungeons:Pick(dungeon, "slash")
        ns:Print("heading for |cffffd100" .. dungeon.name .. "|r" .. (dungeon.levels and (" (" .. dungeon.levels .. ")") or "") .. ".")
        return true
    end
    if hits and #hits > 1 then
        local names = {}
        for _, hit in ipairs(hits) do
            names[#names + 1] = hit.name .. " (" .. string.lower(hit.tag) .. ")"
        end
        ns:Print("which one? " .. table.concat(names, ", "))
        return true
    end
    return false
end

ns:RegisterCommand("list", "every dungeon with its tag, and how many are heading there", function()
    local counts = ns.Net and ns.Net:CountsByDungeon() or {}
    local picked = Dungeons:Picked()
    for _, dungeon in ipairs(DUNGEONS) do
        local count = counts[dungeon.key] or 0
        print(string.format("   %s%s%s%s|r (%s)%s%s%s", dungeon == picked and "> " or "  ", dungeon.parentKey and "   " or "", Dungeons:LevelColor(dungeon), Dungeons:ShortName(dungeon), string.lower(dungeon.tag),
            dungeon.levels and (" " .. dungeon.levels) or "", dungeon.raid and " raid" or "", count > 0 and (" - " .. count .. " heading there") or ""))
    end
    ns:Print(#DUNGEONS .. " instances: " .. Dungeons.discovered.finder .. " named by the group finder, " .. Dungeons.discovered.journal .. " by the journal, the rest known by heart.")
end)

ns:RegisterCommand("none", "pick no dungeon: the panel shows the others only", function()
    Dungeons:Pick(nil, "slash")
    ns:Print("no dungeon picked.")
end)

ns:Listen("LOGIN", function()
    Dungeons:Discover("login")
    C_Timer.After(5, function()
        if Dungeons.discovered.finder == 0 then
            ns.SafeCall(Dungeons.Discover, Dungeons, "later")
        end
    end)
end)

ns:On("LFG_LIST_AVAILABILITY_UPDATE", function()
    if ns.db then
        Dungeons:Discover("availability")
    end
end)
