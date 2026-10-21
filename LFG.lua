-- LFG: the game's own group finder, read and followed - the radar's place in it (the user, 2026-10-16: "i was
-- hoping this would be part of the in game LFG"; "it would be great if the tool would /who people on the
-- list and sort them by proximity and role").
--
-- Forever's finder is Blizzard's vanilla-style one (Blizzard_GroupFinder_VanillaStyle: LFGParentFrame with
-- a Listing, a Browse and a Who tab). Three things are taken from it, nothing is written into it:
--   * THE PICK FOLLOWS IT. List yourself for a dungeon (LFG_LIST_ACTIVE_ENTRY_UPDATE) or filter the Browse
--     tab to one, and the radar picks that dungeon. An activity is tied to a dungeon by the instance map id
--     the client gives it (C_LFGList.GetActivityInfoTable(id).mapID), the same id the radar keys dungeons by.
--   * THE LIST IS READ. Whatever search the finder last ran (C_LFGList.GetSearchResults) is read: every
--     listing for the picked dungeon - a person alone or a group, as the finder has them - with every
--     member's name, level, class, the roles they offer, and - the listing carries it - the AREA they are
--     in. Each member gets a proximity: the channel's own word when they run the addon, else the area of
--     the listing, else "not placed yet"; a group's is the aggregate of its members ("2 at the entrance,
--     1 in Elwynn Forest"), ranked by their average. Sorted by proximity, then by role (tank, healer, dps),
--     then by name - on the radar panel, which docks to the finder window while it is open. Blizzard's own
--     list is not re-ordered: it is theirs.
--   * REFRESH. A search of our own, from the click (C_LFGList.Search is restricted to a key press or a click):
--     with the finder's Browse tab open, for the finder's own filter as it stands - read, never written: the
--     very search its own Refresh runs - and with it closed, for the picked dungeon's activities. The finder's
--     own Refresh button is never clicked: clicked from an addon, its search ran tainted and the client blocked
--     it ("Interface action failed because of an AddOn"; the saved log of 2026-10-20: finder_refresh, then
--     ADDON_ACTION_BLOCKED).
local _, ns = ...

local LFG = {}
ns.LFG = LFG

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local MAX_CATEGORY_PROBE = 200
local MAX_MEMBERS = 40

LFG.activityDungeon = {} -- [activityID] = dungeon | false
LFG.listed = {}           -- the last build, sorted: { id, name, class, level, members, roles, role, area, proximity, source, dungeon }
LFG.stats = { builds = 0, results = 0, searches = 0, pickSearches = 0, refused = 0, finderRefreshes = 0, lastResultsAt = nil, lastSearchAt = nil, picksFromListing = 0, picksFromBrowse = 0 }
LFG.lastBrowseSelection = nil

local function api()
    return type(C_LFGList) == "table" and C_LFGList or nil
end

local function plain(value)
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

-- The finder's own word for a listing's playstyle - the choice every listing is posted with on this
-- flavour (Enum.LFGEntryGeneralPlaystyle: Learning, FunRelaxed, FunSerious, Expert), worded by the client
-- itself (GetGeneralPlaystyleString of Blizzard_LFGUtil, as the finder's Browse rows word it). Nil when
-- the listing carries none.
local PLAYSTYLE_FALLBACK = { "Learning", "Relaxed", "Serious", "Expert" }
local function playstyleWord(value)
    if ns.IsSecret(value) or type(value) ~= "number" or value <= 0 then
        return nil
    end
    local helper = _G.GetGeneralPlaystyleString
    if type(helper) == "function" then
        local ok, word = pcall(helper, value)
        if ok and type(word) == "string" and not ns.IsSecret(word) and word ~= "" then
            return word
        end
    end
    return PLAYSTYLE_FALLBACK[value]
end
LFG.PlaystyleWord = playstyleWord

------------------------------------------------------------------------
-- Activities and dungeons
------------------------------------------------------------------------
function LFG:DungeonForActivity(activityID)
    if type(activityID) ~= "number" then
        return nil
    end
    local cached = self.activityDungeon[activityID]
    if cached ~= nil then
        return cached or nil
    end
    local list = api()
    local info = list and ns.Readable(list.GetActivityInfoTable, activityID)
    info = info and info[1]
    local dungeon = ns.Dungeons:ByActivity(activityID) -- a wing, when the finder lists one
    if not dungeon and type(info) == "table" then
        local mapID, fullName = plain(info.mapID), plain(info.fullName)
        if type(mapID) == "number" and mapID > 0 then
            dungeon = ns.Dungeons:Get(tostring(mapID))
        end
        if not dungeon and type(fullName) == "string" then
            dungeon = ns.Dungeons:ByInstance(nil, fullName)
        end
    end
    self.activityDungeon[activityID] = dungeon or false
    return dungeon
end

-- the dungeon of several activities: the one they all name, the instance when they name its wings
-- (several wings, or a wing and the whole); nil and true when they name unrelated dungeons
local function commonDungeon(activityIDs)
    if type(activityIDs) ~= "table" then
        return nil, false
    end
    local common, base
    for _, activityID in ipairs(activityIDs) do
        local dungeon = LFG:DungeonForActivity(plain(activityID))
        if dungeon then
            local mine = ns.Dungeons:BaseOf(dungeon)
            if not common then
                common, base = dungeon, mine
            elseif dungeon ~= common then
                if mine ~= base then
                    return nil, true
                end
                common = base
            end
        end
    end
    return common, false
end

-- the dungeon of a listing: the one its activities name, or their instance when they name several wings
function LFG:DungeonForActivities(activityIDs)
    return (commonDungeon(activityIDs))
end

-- is a listing with these activities for the picked dungeon? any activity of a wing of the pick, or of
-- the pick itself, or of the pick's own instance listed whole
function LFG:ListingCovers(dungeon, activityIDs)
    if not dungeon or type(activityIDs) ~= "table" then
        return false
    end
    for _, activityID in ipairs(activityIDs) do
        local theirs = self:DungeonForActivity(plain(activityID))
        if theirs and (ns.Dungeons.Covers(dungeon, theirs) or ns.Dungeons.Covers(theirs, dungeon)) then
            return true
        end
    end
    return false
end

-- the finder's activities for a dungeon: what Dungeons found when it read the finder's table (and asked once more here)
function LFG:ActivitiesFor(dungeon)
    if not dungeon then
        return nil
    end
    if (#(dungeon.activities or {}) == 0) and ns.Dungeons.discovered.finder == 0 then
        ns.Dungeons:Discover("search")
    end
    if #(dungeon.activities or {}) == 0 then
        return nil
    end
    return { categoryID = dungeon.categoryID, ids = dungeon.activities }
end

------------------------------------------------------------------------
-- The listed people, placed and sorted
------------------------------------------------------------------------
local function bestRole(roles)
    if type(roles) ~= "table" then
        return nil
    end
    if plain(roles.tank) == true then
        return "TANK"
    elseif plain(roles.healer) == true then
        return "HEALER"
    elseif plain(roles.dps) == true then
        return "DAMAGER"
    end
    return nil
end

local function personOf(info)
    if type(info) ~= "table" then
        return nil
    end
    local roles = type(info.lfgRoles) == "table" and info.lfgRoles or {}
    local person = {
        name = plain(info.name), level = plain(info.level), area = plain(info.areaName), class = plain(info.classFilename),
        assignedRole = plain(info.assignedRole), isLeader = plain(info.isLeader) == true,
        roles = { tank = plain(roles.tank) == true, healer = plain(roles.healer) == true, dps = plain(roles.dps) == true },
    }
    -- the slot this person fills: the role the group gave them, else the first they offer (tank, healer, dps)
    person.role = ROLE_ORDER[person.assignedRole or ""] and person.assignedRole or bestRole(person.roles)
    return person
end

-- a group's make-up, one slot per member, tanks first: "THDDD"
local function composition(members)
    local slots = {}
    for _, member in ipairs(members) do
        slots[#slots + 1] = member.role or "NONE"
    end
    table.sort(slots, function(a, b)
        return (ROLE_ORDER[a] or 9) < (ROLE_ORDER[b] or 9)
    end)
    return slots
end

-- every member of a listing, the leader first; the leader alone when the client gives no members
local function membersOf(list, resultID, count)
    local members = {}
    if type(list.GetSearchResultPlayerInfo) == "function" then
        for index = 1, math.min(type(count) == "number" and count or 1, MAX_MEMBERS) do
            local info = ns.Readable(list.GetSearchResultPlayerInfo, resultID, index)
            local person = personOf(info and info[1])
            if person and person.name then
                members[#members + 1] = person
            end
        end
    end
    if #members == 0 then
        local info = ns.Readable(list.GetSearchResultLeaderInfo, resultID)
        local person = personOf(info and info[1])
        if person and person.name then
            person.isLeader = true
            members[1] = person
        end
    end
    table.sort(members, function(a, b)
        if a.isLeader ~= b.isLeader then
            return a.isLeader
        end
        return (a.name or "") < (b.name or "")
    end)
    return members
end

-- where a person is, best source first: the channel, the listing's own area, a /who of ours
local function place(person, dungeon)
    local peer = ns.Net.peers[person.name]
    if peer then
        return ns.Position.Proximity(peer.sampleLike, dungeon), "addon"
    end
    if person.area and person.area ~= "" then
        return ns.Position.AreaProximity(person.area, dungeon), "listing"
    end
    local area = ns.Lookup and ns.Lookup:Area(person.name)
    if area then
        return ns.Position.AreaProximity(area, dungeon), "who"
    end
    return { rank = 8, text = "not placed yet" }, "none"
end

-- a group's proximity: the members' texts counted up, ranked by their average
local function aggregate(members)
    if #members == 1 then
        return members[1].proximity, members[1].source
    end
    local counts, order, rankSum, yards, source = {}, {}, 0, nil, "addon"
    for _, member in ipairs(members) do
        local text = member.proximity.text
        if not counts[text] then
            counts[text] = { count = 0, rank = member.proximity.rank }
            order[#order + 1] = text
        end
        counts[text].count = counts[text].count + 1
        rankSum = rankSum + member.proximity.rank
        if member.proximity.yards and (not yards or member.proximity.yards < yards) then
            yards = member.proximity.yards
        end
        if member.source ~= "addon" then
            source = member.source == "none" and (source == "addon" and "none" or source) or "listing"
        end
    end
    table.sort(order, function(a, b)
        if counts[a].rank ~= counts[b].rank then
            return counts[a].rank < counts[b].rank
        end
        return a < b
    end)
    local text, short, rest
    if #order == 1 then
        text = "all " .. order[1]
        short, rest = text, ""
    else
        local parts = {}
        for _, item in ipairs(order) do
            parts[#parts + 1] = counts[item].count .. " " .. item
        end
        text = table.concat(parts, ", ")
        short = parts[1]
        rest = "+" .. table.concat(parts, ", ", 2)
    end
    return { rank = rankSum / #members, yards = yards, text = text, short = short, rest = rest }, source
end

function LFG:Build(reason)
    local list = api()
    local dungeon = ns.Dungeons:Picked()
    local listed = {}
    if list and type(list.GetSearchResults) == "function" then
        local found = ns.Readable(list.GetSearchResults)
        local ids = found and found[2]
        self.stats.results = type(ids) == "table" and #ids or 0
        for _, resultID in ipairs(type(ids) == "table" and ids or {}) do
            local info = ns.Readable(list.GetSearchResultInfo, resultID)
            info = info and info[1]
            if type(info) == "table" and plain(info.isDelisted) ~= true then
                local theirs = self:DungeonForActivities(info.activityIDs)
                if theirs and (not dungeon or self:ListingCovers(dungeon, info.activityIDs)) then
                    local size = plain(info.numMembers)
                    size = type(size) == "number" and size or 1
                    local members = membersOf(list, resultID, size)
                    local leader = members[1] or { name = plain(info.leaderName), roles = {} }
                    local name = leader.name or plain(info.leaderName)
                    if type(name) == "string" and name ~= "" then
                        local roles = { tank = false, healer = false, dps = false }
                        for _, member in ipairs(members) do
                            member.proximity, member.source = place(member, dungeon or theirs)
                            roles.tank = roles.tank or member.roles.tank
                            roles.healer = roles.healer or member.roles.healer
                            roles.dps = roles.dps or member.roles.dps
                        end
                        local entry = {
                            id = resultID, name = name, class = leader.class, level = leader.level, area = leader.area,
                            members = math.max(size, #members), people = members, composition = composition(members),
                            roles = roles, role = leader.role, dungeon = theirs,
                            playstyle = playstyleWord(plain(info.generalPlaystyle)),
                        }
                        if #members > 0 then
                            entry.proximity, entry.source = aggregate(members)
                        else
                            entry.proximity, entry.source = { rank = 8, text = "not placed yet" }, "none"
                        end
                        listed[#listed + 1] = entry
                    end
                end
            end
        end
    end
    table.sort(listed, function(a, b)
        if a.proximity.rank ~= b.proximity.rank then
            return a.proximity.rank < b.proximity.rank
        end
        if (a.proximity.yards or 0) ~= (b.proximity.yards or 0) then
            return (a.proximity.yards or 0) < (b.proximity.yards or 0)
        end
        local roleA, roleB = ROLE_ORDER[a.role or ""] or 9, ROLE_ORDER[b.role or ""] or 9
        if roleA ~= roleB then
            return roleA < roleB
        end
        return a.name < b.name
    end)
    self.listed = listed
    self.stats.builds = self.stats.builds + 1
    self.stats.lastBuild = reason
    -- the members nobody has placed: a /who each, in the list's order, when a key press or a click allows
    if ns.Lookup then
        local unplaced, seen = {}, {}
        for _, entry in ipairs(listed) do
            for _, member in ipairs(entry.people or {}) do
                if member.source == "none" and member.name and not seen[member.name] then
                    seen[member.name] = true
                    unplaced[#unplaced + 1] = member.name
                end
            end
        end
        ns.Lookup:Request(unplaced)
    end
    ns:Fire("LFG_CHANGED")
    return listed
end

------------------------------------------------------------------------
-- Following the finder
------------------------------------------------------------------------
local function pickFromListing()
    local list = api()
    LFG.ownPlaystyle = nil -- your own listing's playstyle, for the You line; nil while you are not listed
    if not list or not ns.Readable(list.HasActiveEntryInfo) or not (ns.Readable(list.HasActiveEntryInfo))[1] then
        return
    end
    local entry = ns.Readable(list.GetActiveEntryInfo)
    entry = entry and entry[1]
    if type(entry) == "table" then
        LFG.ownPlaystyle = playstyleWord(plain(entry.generalPlaystyle))
    end
    local dungeon = type(entry) == "table" and LFG:DungeonForActivities(entry.activityIDs) or nil
    if dungeon and not ns.Dungeons.Covers(ns.Dungeons:Picked(), dungeon) then
        LFG.stats.picksFromListing = LFG.stats.picksFromListing + 1
        ns:Log("pick_from_listing", dungeon.key)
        ns.Dungeons:Pick(dungeon)
    end
end

-- the Browse tab's activity filter, read while the tab is open: one dungeon selected = the pick
local function pickFromBrowse()
    local browse = _G.LFGBrowseFrame
    if type(browse) ~= "table" or not browse.IsShown or not (ns.Readable(browse.IsShown, browse) or {})[1] then
        LFG.lastBrowseSelection = nil
        return
    end
    local dropdown = browse.ActivityDropdown
    local selected = type(dropdown) == "table" and dropdown.selectedValues or nil
    if type(selected) ~= "table" then
        return
    end
    local signature = table.concat(selected, ",")
    if signature == LFG.lastBrowseSelection then
        return
    end
    LFG.lastBrowseSelection = signature
    local only, mixed = commonDungeon(selected)
    if mixed then
        return -- several dungeons in the filter: no single pick
    end
    if only and ns.Dungeons:Picked() ~= only then
        LFG.stats.picksFromBrowse = LFG.stats.picksFromBrowse + 1
        ns:Log("pick_from_browse", only.key)
        ns.Dungeons:Pick(only)
    end
end

-- is the finder's Browse tab on the screen (its own search stands then)
function LFG:BrowseOpen()
    local browse = _G.LFGBrowseFrame
    return type(browse) == "table" and browse.IsShown ~= nil and (ns.Readable(browse.IsShown, browse) or {})[1] == true
end

-- One search of ours for these activities, from a click or a slash command only (C_LFGList.Search is
-- restricted). `key` names what it was for in the log.
function LFG:SearchActivities(activities, key)
    local list = api()
    if not list or type(list.Search) ~= "function" then
        return false, "this client has no group finder API"
    end
    local ok, err = pcall(list.Search, activities.categoryID, 0, 0, nil, false, nil, activities.ids)
    if not ok then
        self.stats.refused = self.stats.refused + 1
        ns:Log("lfg_search_refused", tostring(err))
        return false, "the client refused the search: " .. tostring(err)
    end
    self.stats.searches = self.stats.searches + 1
    self.stats.lastSearchAt = GetTime()
    ns:Log("lfg_search", { key = key, activities = #activities.ids })
    return true
end

-- Our own search for the picked dungeon.
function LFG:Search()
    local list = api()
    local dungeon = ns.Dungeons:Picked()
    if not list or type(list.Search) ~= "function" then
        return false, "this client has no group finder API"
    end
    if not dungeon then
        return false, "no dungeon picked"
    end
    local activities = self:ActivitiesFor(dungeon)
    if not activities or #activities.ids == 0 then
        return false, "the finder has no activity for " .. dungeon.name
    end
    return self:SearchActivities(activities, dungeon.key)
end

-- The Browse tab's own filter, READ (never written): its category and its selected activities - every
-- activity of the category when none is selected, as the finder's own search does (LFGBrowse_DoSearch,
-- forever branch). Copies: nothing of the finder's is handed back to the client.
local function browseFilter()
    local browse = _G.LFGBrowseFrame
    if type(browse) ~= "table" then
        return nil
    end
    local category = browse.CategoryDropdown
    local categoryID = type(category) == "table" and category.selectedCategoryID or nil
    if ns.IsSecret(categoryID) or type(categoryID) ~= "number" or categoryID <= 0 then
        return nil
    end
    local ids = {}
    local function take(list)
        for _, id in ipairs(type(list) == "table" and list or {}) do
            if not ns.IsSecret(id) and type(id) == "number" then
                ids[#ids + 1] = id
            end
        end
    end
    local dropdown = browse.ActivityDropdown
    take(type(dropdown) == "table" and dropdown.selectedValues or nil)
    if #ids == 0 and type(LFGUtil_GetFilteredActivities) == "function" then
        local ok, all = pcall(LFGUtil_GetFilteredActivities, categoryID)
        take(ok and all or nil)
    end
    if #ids == 0 then
        return nil
    end
    return { categoryID = categoryID, ids = ids }
end

-- A pick from the panel's dropdown or a command searches for it at once - A SEARCH OF OURS
-- (C_LFGList.Search: HasRestrictions like SendWho, so a click or a command, which both are). The finder's
-- Browse list shows the results, since it draws the client's last search. NOT the finder's own way
-- (LFGBrowseMixin:SetSelectedSearchActivities): that wrote the pick into its Activity dropdown's
-- selectedValues from our call - tainted values - and the finder's next search of its own outside a click
-- (after a listing, on LFG_LIST_SHOW_SEARCH) read them on its way to C_LFGList.Search and was BLOCKED
-- ("Interface action failed because of an AddOn", in game 2026-10-16). Nothing of the finder's is written:
-- its dropdown keeps its own choice until you change it there, and the pick follows that.
function LFG:SearchFinder(dungeon, how)
    local ok, why = self:Search()
    if ok then
        self.stats.pickSearches = self.stats.pickSearches + 1
        ns:Log("pick_search", { key = dungeon.key, how = how })
        return true, "search"
    end
    return false, why
end

-- The Refresh button: a search of ours, from a click or a slash command only - with the Browse tab open,
-- for the finder's own filter as it stands (the search its own Refresh runs, without its button), otherwise
-- for the picked dungeon.
function LFG:Refresh()
    if self:BrowseOpen() then
        local filter = browseFilter()
        if filter then
            local ok, why = self:SearchActivities(filter, "the finder's filter")
            if not ok then
                return false, why
            end
            self.stats.finderRefreshes = self.stats.finderRefreshes + 1
            return true, "finder"
        end
    end
    local ok, why = self:Search()
    if ok then
        return true, "search"
    end
    return false, why
end

-- the finder window to dock to, while it is open
function LFG:DockTarget()
    if not ns:GetOption("dock") then
        return nil
    end
    local parent = _G.LFGParentFrame
    if type(parent) == "table" and parent.IsShown and (ns.Readable(parent.IsShown, parent) or {})[1] then
        return parent
    end
    return nil
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
local buildQueued = false
local function buildSoon(reason)
    if buildQueued then
        return
    end
    buildQueued = true
    C_Timer.After(0.2, function()
        buildQueued = false
        ns.SafeCall(LFG.Build, LFG, reason)
    end)
end

for _, event in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED" }) do
    ns:On(event, function()
        LFG.stats.lastResultsAt = GetTime()
        buildSoon(event)
    end)
end

ns:On("LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
    pickFromListing()
    buildSoon("listing")
end)

for _, message in ipairs({ "PEERS_CHANGED", "PICK_CHANGED", "POSITION_CHANGED", "LOOKUP_CHANGED" }) do
    ns:Listen(message, function()
        buildSoon(message)
    end)
end

ns:Listen("PICK_CHANGED", function(dungeon, how)
    if dungeon and (how == "click" or how == "slash") then
        local ok, why = LFG:SearchFinder(dungeon, how)
        if not ok then
            ns:Log("pick_search_skipped", why)
        end
    end
end)

ns:Listen("LOGIN", function()
    pickFromListing()
    C_Timer.NewTicker(1, function()
        ns.SafeCall(pickFromBrowse)
    end)
end)

ns:Listen("DUNGEONS_CHANGED", function()
    LFG.activityDungeon = {} -- the list grew: activities may tie to dungeons now
    buildSoon("dungeons")
end)

ns:RegisterCommand("lfg", "the people listed in the group finder for the picked dungeon, sorted by proximity and role", function()
    local listed = LFG:Build("command")
    local dungeon = ns.Dungeons:Picked()
    if #listed == 0 then
        ns:Print("nobody listed" .. (dungeon and (" for " .. dungeon.name) or "") .. " in the finder's last search"
            .. (LFG.stats.results == 0 and " - open the finder's Browse tab, or click Refresh with it closed." or "."))
        return
    end
    ns:Print(#listed .. " listed" .. (dungeon and (" for " .. dungeon.name) or "") .. ", nearest first:")
    for _, entry in ipairs(listed) do
        print(string.format("   %s%s%s%s %s - %s%s", entry.name, entry.level and (" " .. entry.level) or "", entry.members > 1 and (" +" .. (entry.members - 1)) or "",
            entry.playstyle and (" " .. string.lower(entry.playstyle)) or "", entry.role and string.lower(entry.role) or "any role", entry.proximity.text,
            entry.source == "addon" and " (addon)" or entry.source == "none" and "" or (" (" .. entry.source .. ")")))
    end
end)

ns:RegisterCommand("refresh", "refresh the group finder's list: a search with the finder's own filter while its Browse tab is open, for the picked dungeon otherwise", function()
    local ok, how = LFG:Refresh()
    if ok then
        ns:Print(how == "finder" and "refreshed the group finder's list." or "asked the group finder for its list - the panel fills in when the answer comes.")
    else
        ns:Print("no refresh: " .. tostring(how))
    end
end)

ns:RegisterCommand("dock", "'on' (default) sets the panel beside the group finder window while it is open; 'off' leaves it where you put it", function(rest)
    local word = string.lower(rest or "")
    if word == "on" or word == "off" then
        ns:SetOption("dock", word == "on")
    end
    ns:Print("docking to the group finder is " .. (ns:GetOption("dock") and "on" or "off") .. ".")
end)
