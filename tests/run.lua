-- Scenario tests for AKForeverLFGRadar: lua tests/run.lua  (from the addon's folder)
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local passed, failures = 0, {}

local function check(condition, message)
    if not condition then
        error(message or "check failed", 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message and (message .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function near(actual, expected, tolerance, message)
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        error((message and (message .. ": ") or "") .. "expected about " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function scenario(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok and #Mock.errors > 0 then
        ok, err = false, "the addon raised an error: " .. tostring(Mock.errors[1])
    end
    if ok and Mock.forbidden > 0 then
        ok, err = false, "the addon did " .. Mock.forbidden .. " forbidden thing(s): a restricted call outside a key press - the client's \"blocked\" popup"
    end
    if ok then
        passed = passed + 1
        Mock.realPrint("  ok    " .. name)
    else
        failures[#failures + 1] = name
        Mock.realPrint("  FAIL  " .. name .. "\n          " .. tostring(err):gsub("\n", "\n          "))
    end
end

local function start(options)
    local ns, state = Mock.install(options)
    Mock.login()
    return ns, state
end

local function printed(text)
    for _, line in ipairs(Mock.printed) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- an addon message we sent whose text matches the pattern
local function sentMessage(pattern)
    for _, message in ipairs(Mock.sent) do
        if string.find(message.text, pattern) then
            return message
        end
    end
    return nil
end

local function savedSafe(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == "table" then
        if depth > 12 then
            return false
        end
        for k, v in pairs(value) do
            if type(k) ~= "string" and type(k) ~= "number" then
                return false
            end
            if not savedSafe(v, depth + 1) then
                return false
            end
        end
        return true
    end
    return kind == "string" or kind == "number" or kind == "boolean"
end

local function panel()
    return AKForeverLFGRadarPanel
end

------------------------------------------------------------------------
Mock.realPrint("AKForeverLFGRadar scenarios")

scenario("a fresh login: nothing picked, the panel is up and says so; '/dr deadmines' picks The Deadmines - by name, tag or a part of the name, with a question when two fit - remembered per character; '/dr none' lets go", function()
    local ns = start()
    check(not ns.Dungeons:Picked(), "nothing picked at first")
    check(panel() and not panel():IsShown(), "the panel waits for the finder, or for '/dr show'")
    check(printed("open the group finder"), "a hint once")
    Mock.slash("show")
    check(panel():IsShown(), "shown on its own when asked")
    check(AKForeverLFGRadarPick:GetText():find("pick a dungeon", 1, true), tostring(AKForeverLFGRadarPick:GetText()))
    Mock.slash("deadmines")
    equal(ns.Dungeons:Picked().key, "36")
    check(printed("heading for"), "told")
    equal(ns.cdb.dungeon, "36")
    Mock.advance(0.2)
    check(AKForeverLFGRadarPick:GetText():find("Deadmines", 1, true), "the panel names it: " .. tostring(AKForeverLFGRadarPick:GetText()))
    Mock.slash("sfk")
    equal(ns.Dungeons:Picked().key, "33", "a tag")
    Mock.slash("razorfen")
    check(printed("which one?"), "two Razorfens: asked")
    equal(ns.Dungeons:Picked().key, "33", "and nothing changed")
    Mock.slash("rfd")
    equal(ns.Dungeons:Picked().name, "Razorfen Downs")
    Mock.slash("Blackrock Dep")
    equal(ns.Dungeons:Picked().name, "Blackrock Depths", "a part of a name")
    Mock.slash("list")
    check(printed("Blackrock Depths"), "the list names them all")
    Mock.slash("none")
    check(not ns.Dungeons:Picked())
    -- remembered per character
    Mock.slash("deadmines")
    local db = AKForeverLFGRadarDB
    local again = start({ db = db })
    equal(again.Dungeons:Picked().key, "36", "the pick survives a login")
    check(not printed("open the group finder"), "the hint was for a character's first login only")
    local alt = start({ db = db, playerName = "Stabby" })
    check(not alt.Dungeons:Picked(), "another character, its own pick")
    check(printed("open the group finder"), "a new character gets the hint once")
    -- the picker on the panel
    Mock.slash("show")
    Mock.click(AKForeverLFGRadarPick)
    check(AKForeverLFGRadarPicker and AKForeverLFGRadarPicker:IsShown(), "the list drops down")
    local deadminesRow
    for _, row in ipairs(alt.Panel.pickerRows) do
        if row.dungeon and row.dungeon.key == "36" then deadminesRow = row end
    end
    check(deadminesRow and deadminesRow:IsShown(), "the Deadmines are on the list")
    Mock.click(deadminesRow)
    equal(alt.Dungeons:Picked().name, "Deadmines", "picked from the list - under the finder's own name")
    check(not AKForeverLFGRadarPicker:IsShown(), "and the list folds")
end)

scenario("proximity, the ladder: at the entrance within sixty yards; yards on the door's continent, with the zone when it is another; in the zone when the client gives no coordinates; inside when you are; in another instance by its name; another continent", function()
    local ns, state = start()
    Mock.slash("show")
    Mock.slash("deadmines")
    -- the mock's Westfall is 3500 x 2333 yards: a percent of the map is 35 x 23 yards. The seed door: 42.6, 71.6
    Mock.moveTo("Westfall", 0.426, 0.716)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "at the entrance")
    Mock.moveTo("Westfall", 0.526, 0.716) -- ten percent east: 350 yards
    Mock.advance(3)
    local mine = ns.Position:Mine()
    equal(mine.rank, 2); near(mine.yards, 350, 1); equal(mine.text, "350 yd")
    Mock.moveTo("Westfall", 0.926, 0.716)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "1,750 yd", "thousands with a comma")
    Mock.moveTo("Elwynn Forest", 0.3, 0.5)
    Mock.advance(3)
    mine = ns.Position:Mine()
    equal(mine.rank, 2)
    check(mine.text:find("Elwynn Forest", 1, true), "another zone of the same continent: yards, and the zone: " .. mine.text)
    state.world.noPosition = true -- a map the client gives no coordinates on
    Mock.moveTo("Westfall", 0.5, 0.5)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "in Westfall")
    Mock.moveTo("Elwynn Forest", 0.5, 0.5)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "in Elwynn Forest")
    state.world.noPosition = false
    Mock.moveTo("The Barrens", 0.4, 0.6)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "another continent")
    Mock.enterInstance(36, "The Deadmines")
    Mock.advance(3)
    equal(ns.Position:Mine().text, "inside")
    Mock.enterInstance(43, "Wailing Caverns")
    Mock.advance(3)
    equal(ns.Position:Mine().text, "in Wailing Caverns")
    Mock.slash("where")
    check(printed("Deadmines:"), "the command says it")
    check(AKForeverLFGRadarDB.learned["36"] == nil, "a leap into the instance from another continent (a summon) teaches no door")
    -- the panel's own line
    Mock.moveTo("Westfall", 0.426, 0.716)
    Mock.advance(3)
    check(ns.Panel ~= nil)
    Mock.advance(1)
    local lines = {}
    local function walk(widget)
        for _, child in ipairs(widget.__children or {}) do
            if child.__kind == "FontString" and type(child.__text) == "string" and child.__text:find("You:", 1, true) then
                lines[#lines + 1] = child.__text
            end
            walk(child)
        end
    end
    walk(panel())
    check(#lines >= 1 and lines[1]:find("at the entrance", 1, true), "the panel says where you are: " .. tostring(lines[1]))
end)

scenario("the channel: joined after login, a request goes out and our position with it; peers' positions come in and are shown nearest first with THEIR distance to MY pick and their own pick as a tag; we send on a move within 15 s and every minute regardless; a peer not heard for 90 s leaves; '/dr share off' stops the sending, not the listening; a peer's request is answered", function()
    local ns, state = start()
    Mock.slash("show")
    Mock.slash("deadmines")
    Mock.moveTo("Westfall", 0.5, 0.5)
    Mock.advance(4)
    check(ns.Net.channelID, "the channel is joined")
    check(ns.Net.stats.prefixRegistered, "the prefix is registered")
    check(sentMessage("^R|"), "a request went out")
    check(sentMessage("^P|1|36|O|"), "and our position: outdoors, heading for the Deadmines")
    local sentBefore = #Mock.sent
    Mock.advance(3)
    check(ns.Net.stats.own >= 1, "our own echo is counted, not read")
    equal(ns.Net:PeerCount(), 0)
    -- three peers
    Mock.peerPosition("Grom Hellscream", { dungeon = "36", uiMap = "Westfall", x = 0.43, y = 0.72, class = "WARRIOR", level = 20 })
    Mock.peerPosition("Jaina Proudmoore", { dungeon = "33", uiMap = "The Barrens", x = 0.4, y = 0.6, class = "MAGE", level = 60 })
    Mock.peerPosition("Thrall", { dungeon = "36", inside = 36, instanceName = "The Deadmines", class = "SHAMAN", level = 22 })
    Mock.advance(0.5)
    local peers = ns.Net:Peers()
    equal(#peers, 3)
    equal(peers[1].peer.name, "Thrall"); equal(peers[1].proximity.text, "inside")
    equal(peers[2].peer.name, "Grom Hellscream"); equal(peers[2].proximity.text, "at the entrance")
    equal(peers[3].peer.name, "Jaina Proudmoore"); equal(peers[3].proximity.text, "another continent")
    local rows = ns.Panel.rows
    check(rows[1] and rows[1]:IsShown() and rows[1].name:GetText():find("Thrall", 1, true), "the first row: " .. tostring(rows[1] and rows[1].name:GetText()))
    check(rows[2].where:GetText():find("at the entrance", 1, true), tostring(rows[2].where:GetText()))
    check(rows[3].name:GetText():find("Jaina", 1, true) and rows[3].where:GetText():find("another continent", 1, true), tostring(rows[3].where:GetText()))
    check(rows[3].where:GetText():find("SFK", 1, true), "her own pick as a tag: " .. tostring(rows[3].where:GetText()))
    check(not rows[4]:IsShown(), "no fourth row")
    equal(ns.Net:CountsByDungeon()["36"], 3, "three heading for the Deadmines, me included")
    -- the cadence
    Mock.advance(20)
    equal(#Mock.sent, sentBefore, "standing still: nothing more for 20 s")
    Mock.advance(45)
    check(#Mock.sent > sentBefore, "the heartbeat within a minute")
    local count = #Mock.sent
    Mock.moveTo("Westfall", 0.6, 0.5) -- 350 yards east
    Mock.advance(20)
    check(#Mock.sent > count, "a move goes out within 15 s")
    -- stale peers
    Mock.advance(100)
    equal(#ns.Net:Peers(), 0, "not heard from for 90 s: gone")
    -- share off
    Mock.slash("share off")
    count = #Mock.sent
    Mock.moveTo("Westfall", 0.7, 0.5)
    Mock.advance(70)
    equal(#Mock.sent, count, "nothing sent while sharing is off")
    Mock.peerPosition("Grom Hellscream", { dungeon = "36", uiMap = "Westfall", x = 0.43, y = 0.72, class = "WARRIOR", level = 20 })
    equal(#ns.Net:Peers(), 1, "still listening")
    Mock.slash("share on")
    Mock.advance(1)
    check(#Mock.sent > count, "sharing on again: our position goes out at once")
    count = #Mock.sent
    Mock.peerMessage("Grom Hellscream", "R|1")
    Mock.advance(3)
    check(#Mock.sent > count, "a request is answered")
    -- a peer who picked nothing shows what they are near all the same
    Mock.peerPosition("Cairne", { uiMap = "Westfall", x = 0.9, y = 0.9, class = "WARRIOR", level = 60 })
    peers = ns.Net:Peers()
    local cairne
    for _, item in ipairs(peers) do if item.peer.name == "Cairne" then cairne = item end end
    check(cairne and cairne.proximity.rank == 2, "measured against MY pick: " .. tostring(cairne and cairne.proximity.text))
end)

scenario("the door is learned by walking in: the last outdoor spot becomes the entrance, saved for every character and told to the others; a peer's door replaces a seed but never your own eyes; the map's own pin beats the seed; Forever's own instances know only their zone until somebody walks in", function()
    local ns = start()
    Mock.slash("deadmines")
    Mock.advance(4)
    local entrance = ns.Dungeons:Entrance(ns.Dungeons:Picked())
    check(entrance.source:find("seed", 1, true), entrance.source)
    Mock.moveTo("Westfall", 0.44, 0.70)
    Mock.advance(3)
    Mock.enterInstance(36, "The Deadmines")
    Mock.advance(1)
    local learned = AKForeverLFGRadarDB.learned["36"]
    check(learned and learned.from == "walked in", "learned")
    near(learned.x, 0.44, 0.0001); near(learned.y, 0.70, 0.0001)
    equal(learned.by, "Purrdee Bubson")
    check(sentMessage("^E|36|"), "told to the others")
    entrance = ns.Dungeons:Entrance(ns.Dungeons:Picked())
    check(entrance.source:find("walked in", 1, true), entrance.source)
    -- the door now measured from the learned spot
    Mock.moveTo("Westfall", 0.54, 0.70)
    Mock.advance(3)
    near(ns.Position:Mine().yards, 350, 1, "measured from the learned door")
    -- a peer's word
    Mock.peerMessage("Grom Hellscream", "E|33|" .. Mock.mapID("Silverpine Forest") .. "|0.4500|0.6800|Grom Hellscream")
    equal(AKForeverLFGRadarDB.learned["33"].from, "peer")
    Mock.peerMessage("Grom Hellscream", "E|36|" .. Mock.mapID("Westfall") .. "|0.1000|0.1000|Grom Hellscream")
    near(AKForeverLFGRadarDB.learned["36"].x, 0.44, 0.0001, "your own eyes beat a peer's word")
    -- the map's own pin
    local fresh = start({ pins = { ["Silverpine Forest"] = { { name = "Shadowfang Keep", x = 0.45, y = 0.68 } } } })
    Mock.slash("sfk")
    entrance = fresh.Dungeons:Entrance(fresh.Dungeons:Picked())
    equal(entrance.source, "the map's own pin"); near(entrance.x, 0.45, 0.0001)
    -- Forever's own
    Mock.slash("excav")
    local site = fresh.Dungeons:Entrance(fresh.Dungeons:Picked())
    equal(site.source, "zone only")
    Mock.moveTo("Wetlands", 0.5, 0.5)
    Mock.advance(3)
    equal(fresh.Position:Mine().text, "in Wetlands")
    Mock.moveTo("Westfall", 0.5, 0.5)
    Mock.advance(3)
    equal(fresh.Position:Mine().text, "in Westfall")
    Mock.slash("thanes")
    Mock.advance(3)
    equal(fresh.Position:Mine().text, "in Westfall", "no zone known either: where you are, by name")
end)

scenario("the group finder: people and groups listed for the picked dungeon come to the panel sorted by proximity, then role - an addon user by the channel, the rest by the area the listing names, the unknown last; a group shows where all of its members are; the pick follows your own listing and the Browse tab's filter; the panel docks to the finder, shows with it and closes with it, and has an X; Refresh is the finder's own refresh while its Browse tab is open, a search of ours otherwise; '/dr lfg'", function()
    local ns, state = start()
    Mock.slash("show")
    Mock.slash("deadmines")
    Mock.moveTo("Westfall", 0.5, 0.5)
    Mock.advance(4)
    -- the finder's last search: people and groups, one listing for another dungeon
    Mock.lfgResults({
        { id = 1, leader = "Bolvar", activity = 1001, roles = "T", class = "WARRIOR", level = 22, area = "Elwynn Forest" },
        { id = 2, leader = "Anduin", activity = 1001, roles = "H", class = "PRIEST", level = 20, area = "Westfall" },
        { id = 3, leader = "Grom Hellscream", activity = 1001, roles = "D", class = "WARRIOR", level = 20, playstyle = 4 },
        { id = 4, leader = "Mathias", activity = 1001, roles = "D", class = "ROGUE", level = 19 },
        { id = 5, leader = "Jaina Proudmoore", activity = 1002, roles = "D", class = "MAGE", level = 25, area = "Silverpine Forest" },
        { id = 6, leader = "Edwin", activity = 1001, roles = "TD", class = "WARRIOR", level = 21, area = "The Deadmines", playstyle = 2,
            members = { { name = "Cookie", level = 20, class = "ROGUE", roles = "D", area = "The Deadmines" }, { name = "Sneed", level = 21, class = "WARRIOR", roles = "D", area = "The Deadmines" } } },
        { id = 7, leader = "Garona", activity = 1001, roles = "D", class = "ROGUE", level = 23, area = "The Barrens" },
        { id = 8, leader = "Vanessa", activity = 1001, roles = "D", class = "ROGUE", level = 20, area = "Westfall" },
        { id = 9, leader = "Thrall", activity = 1001, roles = "H", class = "SHAMAN", level = 22, area = "Elwynn Forest", playstyle = 3,
            members = { { name = "Nazgrel", level = 22, class = "WARRIOR", roles = "T", area = "Westfall" }, { name = "Drek", level = 21, class = "HUNTER", roles = "D", area = "The Barrens" } } },
        -- a group whose other members the listing does not place: the finder names an area for the leader only
        { id = 10, leader = "Varian", activity = 1001, roles = "T", class = "WARRIOR", level = 22, area = "Westfall",
            members = { { name = "Marcus", level = 20, class = "PALADIN", roles = "H" }, { name = "Reginald", level = 21, class = "PRIEST", roles = "H" } } },
    })
    Mock.peerPosition("Grom Hellscream", { dungeon = "36", uiMap = "Westfall", x = 0.43, y = 0.72, class = "WARRIOR", level = 20 })
    Mock.peerPosition("Nazgrel", { dungeon = "36", uiMap = "Westfall", x = 0.43, y = 0.72, class = "WARRIOR", level = 22 })
    Mock.advance(0.5)
    local listed = ns.LFG.listed
    equal(#listed, 9, "the SFK listing is not for this dungeon")
    equal(listed[1].name, "Edwin"); equal(listed[1].proximity.text, "all inside"); equal(listed[1].members, 3, "a group of three, all inside")
    equal(listed[2].name, "Grom Hellscream"); equal(listed[2].proximity.text, "at the entrance"); equal(listed[2].source, "addon")
    equal(listed[3].name, "Anduin"); equal(listed[3].proximity.text, "in Westfall"); equal(listed[3].role, "HEALER")
    equal(listed[4].name, "Vanessa"); equal(listed[4].proximity.text, "in Westfall"); equal(listed[4].role, "DAMAGER", "the same zone: the healer before the dps")
    equal(listed[5].name, "Thrall"); equal(listed[5].proximity.text, "1 at the entrance, 1 in Elwynn Forest, 1 another continent", "a group spread out: the members counted up, nearest first")
    check(listed[5].proximity.rank > listed[4].proximity.rank and listed[5].proximity.rank < 6, "ranked by the members' average: " .. tostring(listed[5].proximity.rank))
    check(listed[5].roles.tank and listed[5].roles.healer and listed[5].roles.dps, "the roles of the whole group")
    equal(listed[6].name, "Bolvar"); equal(listed[6].proximity.text, "in Elwynn Forest", "the same continent, another zone")
    equal(listed[7].name, "Garona"); equal(listed[7].proximity.text, "another continent")
    equal(listed[8].name, "Varian"); equal(listed[8].proximity.text, "1 in Westfall, 2 not placed yet", "the leader placed by the listing, the others not yet")
    equal(listed[9].name, "Mathias"); equal(listed[9].proximity.text, "not placed yet"); equal(listed[9].source, "none")
    -- the unplaced members: a /who each - on the Refresh click, then on your key presses, ten seconds apart
    equal(ns.Lookup:Next(), "Marcus", "the first unplaced member is up for a /who")
    check(ns.Lookup.keys and ns.Lookup.keys.__keyboard and ns.Lookup.keys.__propagate, "the key rider hears every key and passes every key on")
    Mock.click(AKForeverLFGRadarRefresh)
    equal(#Mock.whoQueries, 1); equal(Mock.whoQueries[1], 'n-"Marcus"', "the click carried a /who for Marcus")
    equal(Mock.whoToUi, false, "the answer is NOT asked to the UI: that opens the finder's Who tab")
    Mock.keyPress("W")
    equal(#Mock.whoQueries, 1, "one query on its way: nothing more until the answer")
    Mock.whoAnswer({ { "Marcus", 20, "PALADIN", "Westfall" } }, 1)
    equal(Mock.finderOpenedByWho, 0, "the finder stayed closed")
    equal(#Mock.chatLines, 0, "and nothing reached the chat: " .. tostring(Mock.chatLines[1]))
    equal(ns.Lookup.stats.byChat, 1, "read from the chat path")
    Mock.advance(0.5)
    local varian
    for _, entry in ipairs(ns.LFG.listed) do if entry.name == "Varian" then varian = entry end end
    equal(varian.proximity.text, "2 in Westfall, 1 not placed yet", "Marcus placed by the /who")
    equal(ns.Lookup:Next(), "Reginald")
    Mock.keyPress("S")
    equal(#Mock.whoQueries, 1, "ten seconds between queries")
    Mock.advance(10)
    Mock.keyPress("W")
    equal(#Mock.whoQueries, 2); equal(Mock.whoQueries[2], 'n-"Reginald"', "the next one rides on a key press")
    Mock.keyPress("W") -- held down: a repeat within a second and a half is no press
    equal(ns.Lookup.stats.repeats, 1)
    Mock.whoAnswer({}, 0)
    check(ns.Lookup.known["Reginald"] and ns.Lookup.known["Reginald"].missing, "not found: not asked again for a while")
    Mock.advance(12)
    Mock.keyPress("A")
    equal(#Mock.whoQueries, 3); equal(Mock.whoQueries[3], 'n-"Mathias"', "a person alone whom nothing placed is asked about too")
    Mock.whoAnswer({ { "Mathias", 19, "ROGUE", "Elwynn Forest" } }, 1)
    Mock.advance(10.5)
    Mock.keyPress("A")
    equal(#Mock.whoQueries, 3, "nothing left to ask")
    equal(ns.Lookup.stats.viaClick, 1); equal(ns.Lookup.stats.viaKey, 2)
    equal(Mock.finderOpenedByWho, 0, "the finder never opened for a lookup")
    equal(#Mock.chatLines, 0, "no who line ever reached the chat")
    check(ns.Lookup.stats.filterInstalled, "the chat filter is in place")
    -- an action the client refuses is kept with the function's name; ours is said in the chat, another addon's is not
    Mock.fire("ADDON_ACTION_BLOCKED", ns.name, "Search")
    Mock.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName")
    equal(#ns.blocked, 2); equal(ns.blocked[1].func, "Search"); equal(ns.blocked[1].event, "ADDON_ACTION_BLOCKED"); equal(ns.blocked[2].addon, "SomeOtherAddon")
    check(printed("the client blocked Search()"), "said in the chat")
    check(not printed("CastSpellByName"), "another addon's trouble is not ours to announce")
    local mathias
    for _, entry in ipairs(ns.LFG.listed) do if entry.name == "Mathias" then mathias = entry end end
    equal(mathias.proximity.text, "in Elwynn Forest"); equal(mathias.source, "who")
    -- the panel: groups first, players after, each nearest first
    local rows = ns.Panel.listedRows
    check(ns.Panel.listedHeaders[1]:GetText():find("Groups listed in the group finder - 3", 1, true), tostring(ns.Panel.listedHeaders[1]:GetText()))
    check(ns.Panel.listedHeaders[2]:GetText():find("Players listed in the group finder - 6", 1, true), tostring(ns.Panel.listedHeaders[2]:GetText()))
    check(rows[1]:IsShown() and rows[1].name:GetText():find("Edwin", 1, true), tostring(rows[1].name:GetText()))
    check(rows[1].name:GetText():find("+2", 1, true), "the group's size")
    local function icons(text, role)
        local n = 0
        for _ in string.gmatch(text, "role%-micro%-" .. role) do n = n + 1 end
        return n
    end
    -- a group takes two lines: the leader and the size, where most of it is; beneath, the role symbols and the rest
    local edwin = rows[1].detail:GetText()
    check(icons(edwin, "tank") == 1 and icons(edwin, "heal") == 0 and icons(edwin, "dps") == 2, "a group of three: one symbol per member, tanks first - tank, dps, dps: " .. edwin)
    check(select(2, string.gsub(edwin, "|A:", "")) == 3, "three symbols, no letters")
    check(not rows[1].name:GetText():find("|A:", 1, true), "the group's first line carries the leader alone: " .. rows[1].name:GetText())
    check(rows[1].detail:IsShown() and rows[1].__height == 28, "a group row is two lines tall")
    local thrall = rows[2].detail:GetText()
    check(icons(thrall, "tank") == 1 and icons(thrall, "heal") == 1 and icons(thrall, "dps") == 1, "Thrall's group: tank, healer, dps: " .. thrall)
    check(string.find(thrall, "micro%-tank.*micro%-heal.*micro%-dps"), "in that order")
    local grom = rows[4].name:GetText()
    check(icons(grom, "dps") == 1 and icons(grom, "tank") == 0, "a person alone: the roles they offer, on the one line: " .. grom)
    check(not rows[4].detail:IsShown() and rows[4].__height == 14, "a person's row is one line")
    -- the playstyle each listing was posted with, in the finder's own words, dim after the name
    check(rows[1].name:GetText():find("+2|r  |cff999999Relaxed|r", 1, true), "Edwin's group: Relaxed, after the size: " .. rows[1].name:GetText())
    check(rows[2].name:GetText():find("|cff999999Serious|r", 1, true), "Thrall's group: Serious: " .. rows[2].name:GetText())
    check(rows[4].name:GetText():find("20|r  |cff999999Expert|r", 1, true), "Grom: Expert, after his level: " .. rows[4].name:GetText())
    local mathiasRow
    for _, row in ipairs(rows) do if row.listed and row.listed.name == "Mathias" then mathiasRow = row end end
    local mathiasText = mathiasRow and mathiasRow.name:GetText() or ""
    check(mathiasRow and not (mathiasText:find("Learning", 1, true) or mathiasText:find("Relaxed", 1, true) or mathiasText:find("Serious", 1, true) or mathiasText:find("Expert", 1, true)),
        "a listing without one says nothing: " .. mathiasText)
    equal(ns.LFG.PlaystyleWord(0), nil); equal(ns.LFG.PlaystyleWord(2), "Relaxed", "the client's own word")
    rows[1].__scripts.OnEnter(rows[1])
    check(table.concat(GameTooltip.__lines, " | "):find("a group of 3 - Relaxed", 1, true), "the tooltip names it too")
    check(not string.find(edwin, "THD", 1, true), "no letters")
    check(rows[1].where:GetText():find("all inside", 1, true))
    for index = 1, 3 do
        local group = rows[index].listed
        check(group and group.members > 1, "a group in the groups section")
        if group.proximity.rest ~= "" then
            check(rows[index].where:GetText():find(group.proximity.short, 1, true) and rows[index].detail:GetText():find(group.proximity.rest, 1, true),
                "a scattered group: the best-placed part on the right, the rest beneath: " .. rows[index].where:GetText() .. " / " .. rows[index].detail:GetText())
            check(rows[index].where.__width == nil or rows[index].where.__width <= 130, "the right column never wider than its cap")
        end
    end
    check(rows[2].name:GetText():find("Thrall", 1, true), "the second group: " .. tostring(rows[2].name:GetText()))
    check(rows[3].name:GetText():find("Varian", 1, true), "the third group: " .. tostring(rows[3].name:GetText()))
    check(rows[4].name:GetText():find("Grom", 1, true) and rows[4].where:GetText() == "at the entrance", "the players after the groups, an addon user's word with no ~: " .. tostring(rows[4].where:GetText()))
    check(rows[5].where:GetText():find("~", 1, true), "a guess from an area carries a ~")
    rows[2].__scripts.OnEnter(rows[2])
    local lines = table.concat(GameTooltip.__lines, " | ")
    check(lines:find("Nazgrel", 1, true) and lines:find("Drek", 1, true) and lines:find("Together:", 1, true), "the tooltip names every member and the whole: " .. lines)
    Mock.click(rows[1], "RightButton")
    equal(Mock.invites[#Mock.invites], "Edwin")
    -- the command
    Mock.slash("lfg")
    check(printed("9 listed for Deadmines"), "the command lists them")
    check(printed("Edwin 21 +2 relaxed"), "a group with its size and its playstyle")
    -- your own listing picks the dungeon, and the You line says what you are advertising
    local function youLine()
        local found
        local function walk(widget)
            for _, child in ipairs(widget.__children or {}) do
                if child.__kind == "FontString" and type(child.__text) == "string" and child.__text:find("You:", 1, true) then
                    found = child.__text
                end
                walk(child)
            end
        end
        walk(panel())
        return found or ""
    end
    Mock.listSelf(1002, 3)
    equal(ns.Dungeons:Picked().key, "33", "listed yourself for SFK: SFK is the pick")
    Mock.advance(0.5)
    check(youLine():find("listed Serious", 1, true), "your own listing's playstyle on the You line: " .. youLine())
    Mock.listSelf(nil)
    Mock.advance(0.5)
    check(not youLine():find("listed", 1, true), "taken down: gone from the You line")
    -- the Browse tab's filter picks, and the panel docks
    Mock.slash("hide")
    check(not panel():IsShown(), "away on its own")
    Mock.openLFG({ 1001 })
    Mock.advance(1.5)
    equal(ns.Dungeons:Picked().key, "36", "the Browse filter on the Deadmines: the pick follows")
    check(ns.Panel:IsDocked(), "docked to the finder")
    check(panel():IsShown(), "and shown with it")
    local point = { panel():GetPoint(1) }
    equal(point[2], LFGParentFrame, "beside the finder window")
    check(point[4] >= 68, "clear of the finder's side tabs, measured: " .. tostring(point[4]))
    Mock.openLFG({ 1001, 1003 })
    Mock.advance(1.5)
    equal(ns.Dungeons:Picked().key, "36", "two dungeons in the filter: the pick stays")
    -- Refresh with the Browse tab open is the finder's own refresh; with the finder closed, a search of ours
    local searches, refreshes = #Mock.lfgSearches, Mock.finderRefreshes
    check(AKForeverLFGRadarRefresh:IsEnabled(), "Refresh is live with the finder open")
    Mock.click(AKForeverLFGRadarRefresh)
    equal(Mock.finderRefreshes, refreshes + 1, "the finder's own refresh button was clicked")
    equal(#Mock.lfgSearches, searches + 1, "which searched with the finder's own filter")
    equal(#Mock.lfgSearches[#Mock.lfgSearches].activityIDs, 2, "the filter as it stands, both dungeons")
    -- the X beside the finder: away until the finder is opened again
    Mock.click(AKForeverLFGRadarClose)
    check(not panel():IsShown(), "closed")
    Mock.advance(2)
    check(not panel():IsShown(), "and it stays closed while the finder stays open")
    Mock.closeLFG()
    Mock.advance(1.5)
    check(not ns.Panel:IsDocked(), "undocked when the finder closes")
    check(not panel():IsShown(), "and gone with it")
    Mock.openLFG({ 1001 })
    Mock.advance(1.5)
    check(panel():IsShown() and ns.Panel:IsDocked(), "back with the finder")
    Mock.closeLFG()
    Mock.advance(1.5)
    -- on its own again: a search of ours
    Mock.slash("show")
    check(panel():IsShown() and not ns.Panel:IsDocked(), "on its own, where you put it")
    searches = #Mock.lfgSearches
    Mock.click(AKForeverLFGRadarRefresh)
    equal(#Mock.lfgSearches, searches + 1, "a search of ours")
    equal(Mock.lfgSearches[#Mock.lfgSearches].activityIDs[1], 1001, "for the Deadmines' activity")
    Mock.slash("refresh")
    equal(#Mock.lfgSearches, searches + 2, "the command too")
    -- the X on its own: away until '/dr show'
    Mock.click(AKForeverLFGRadarClose)
    Mock.advance(2)
    check(not panel():IsShown(), "closed on its own stays closed")
    equal(ns:GetOption("shown"), false)
    Mock.slash("dock off")
    Mock.openLFG({ 1001 })
    Mock.advance(1.5)
    check(not ns.Panel:IsDocked() and not panel():IsShown(), "docking off: the finder does not bring it")
    Mock.closeLFG()
    local report = ns.Diagnostics:Collect()
    check(report.lfg and report.lfg.listed and #report.lfg.listed == 9, "the report carries the list")
    check(report.lookups and report.lookups.stats.found == 2, "and the lookups")
end)

scenario("the dungeon list follows the group finder: its activities name every instance of this realm, Forever's own included, with level range and size; the map's pin gives such a door; the table's tags and seeds merge in; the journal adds names when the client has one", function()
    local ns = start({ pins = { ["Dun Morogh"] = { { name = "Hall of Thanes", x = 0.3, y = 0.4 } }, ["Westfall"] = { { name = "The Deadmines", x = 0.43, y = 0.72 } } } })
    check(ns.Dungeons.discovered.finder == 11, "the finder's dungeon activities were read, its two raids left out: " .. tostring(ns.Dungeons.discovered.finder))
    -- wings: the Monastery's four under the Monastery, each with its own range, tag and activity; the Spires likewise
    local monastery = ns.Dungeons:Get("189")
    check(monastery and monastery.name == "Scarlet Monastery" and #monastery.activities == 4, "the instance stands for all four wings: " .. tostring(monastery and #monastery.activities))
    local cathedral = ns.Dungeons:Find("cath")
    check(cathedral and cathedral.parentKey == "189" and cathedral.id == 189 and cathedral.levels == "38-46", "the Cathedral wing, under the Monastery: " .. tostring(cathedral and cathedral.key))
    equal(cathedral.tag, "SM Cath", "the finder's own short name as the tag"); equal(#cathedral.activities, 1); equal(cathedral.activities[1], 1007)
    equal(monastery.levels, "30-46", "the instance spans its wings"); equal(monastery.tag, "SM", "the table's tag stays for the instance itself")
    equal(ns.Dungeons:Find("sm gy").name, "Scarlet Monastery - Graveyard", "a wing by the finder's short name")
    equal(ns.Dungeons:Find("gy").name, "Scarlet Monastery - Graveyard", "or a part of it")
    equal(ns.Dungeons:ShortName(ns.Dungeons:Find("gy")), "Graveyard", "a wing's own part of its name")
    equal(ns.Dungeons:ShortName(monastery), "Scarlet Monastery")
    equal(ns.Dungeons:ByActivity(1005).name, "Scarlet Monastery - Library")
    equal(ns.Dungeons:Find("ubrs").name, "Upper Blackrock Spire"); equal(ns.Dungeons:Find("lower blackrock").parentKey, "229")
    equal(ns.Dungeons:ShortName(ns.Dungeons:Find("ubrs")), "Upper Blackrock Spire", "a wing named otherwise stays whole")
    equal(ns.Dungeons:Get("229").name, "Blackrock Spire", "the Spires' instance keeps the table's name")
    equal(ns.Dungeons:Get("36").name, "Deadmines", "one activity under another spelling: the instance itself, the finder's way")
    equal(ns.Dungeons:Get("36").tag, "DM")
    equal(ns.Dungeons:Entrance(cathedral).zoneName, "Tirisfal Glades", "a wing's door is its instance's")
    local names = {}
    for index, dungeon in ipairs(ns.Dungeons.list) do names[dungeon.key] = index end
    check(names["189"] < names[cathedral.key] and names[cathedral.key] - names["189"] <= 4, "the wings sit right after their instance in the list")
    check(names["189:scarlet-monastery-graveyard"] < names["189:scarlet-monastery-library"], "wings by their own range")
    local thanes = ns.Dungeons:Find("thanes")
    check(thanes and thanes.id == 3001, "Hall of Thanes is known by the finder's instance id")
    equal(thanes.name, "The Hall of Thanes", "the finder's own name, merged with the table's by its words")
    equal(thanes.levels, "13-18", "the finder's SUGGESTED range, with no required level set"); equal(thanes.tag, "HoT", "the finder's own short name becomes the tag"); check(ns.Dungeons:Find("hot") == thanes, "and finds it")
    equal(thanes.zone, "Ironforge", "the table's zone kept")
    local alcaz = ns.Dungeons:Get("3003")
    check(alcaz and alcaz.tag == "AP" and alcaz.levels == "48-53" and alcaz.zone == "Dustwallow Marsh", "'Alcaz Prison' is the table's 'Alcaz Island Prison', tagged the finder's way: " .. tostring(alcaz and alcaz.tag))
    check(ns.Dungeons:Find("alcaz") == alcaz, "and still found by a part of its name")
    check(not ns.Dungeons:Find("karazhan"), "a raid is not on the list, however new")
    check(not ns.Dungeons:Get("409"), "nor an old one: Molten Core is gone")
    local deadmines = ns.Dungeons:Get("36")
    equal(deadmines.levels, "15-22", "the finder's suggestion replaces the table's range"); equal(deadmines.activities[1], 1001, "the finder's activity, kept for the search")
    -- sorted by level, lowest first (a wing takes its instance's place); the finder's colours against your level (22)
    local previousLow, previousHigh = 0, 0
    for _, dungeon in ipairs(ns.Dungeons.list) do
        if not dungeon.parentKey then
            local low, high = ns.Dungeons:ParseLevels(dungeon.levels)
            check(low, "every instance has a level range now: " .. dungeon.name)
            check(low > previousLow or (low == previousLow and high >= previousHigh), "sorted by level: " .. dungeon.name .. " after " .. previousLow .. "-" .. previousHigh)
            previousLow, previousHigh = low, high
        end
    end
    equal(ns.Dungeons:LevelColor(deadmines), "|cffffffff", "15-22 at level 22: plain")
    equal(ns.Dungeons:LevelColor(thanes), "|cff808080", "13-18 at level 22: trivial, grey")
    equal(ns.Dungeons:LevelColor(ns.Dungeons:Get("230")), "|cffff2020", "Blackrock Depths at level 22: difficult, red")
    Mock.slash("list")
    check(printed("Hall of Thanes") and not printed("Karazhan Crypts"), "the list names the dungeons and no raid")
    check(printed("named by the group finder"))
    check(printed("|cff808080The Hall of Thanes"), "coloured in the printed list too")
    -- the picker shows the same list, in the same order and colours
    Mock.slash("show")
    Mock.click(AKForeverLFGRadarPick)
    local pickerRows = ns.Panel.pickerRows
    check(#pickerRows >= #ns.Dungeons.list, "a row for every instance")
    check(pickerRows[1].text:GetText():find(ns.Dungeons.list[1].name, 1, true), "the lowest range first: " .. tostring(pickerRows[1].text:GetText()))
    check(pickerRows[1].text:GetText():find("|cff808080", 1, true), "greyed for a level-22 character")
    Mock.click(AKForeverLFGRadarPick)
    -- the door from the map's pin, found on whatever zone carries it
    Mock.slash("thanes")
    local entrance = ns.Dungeons:Entrance(ns.Dungeons:Picked())
    equal(entrance.source, "the map's own pin"); equal(entrance.zoneName, "Dun Morogh"); near(entrance.x, 0.3, 0.0001)
    Mock.moveTo("Dun Morogh", 0.3, 0.4)
    Mock.advance(3)
    equal(ns.Position:Mine().text, "at the entrance")
    Mock.enterInstance(3001, "Hall of Thanes")
    Mock.advance(3)
    equal(ns.Position:Mine().text, "inside", "inside by the finder's instance id")
    -- the pin beats the seed for a table dungeon too
    Mock.slash("deadmines")
    equal(ns.Dungeons:Entrance(ns.Dungeons:Picked()).source, "the map's own pin")
    -- a search of ours uses the finder's activity
    Mock.slash("thanes")
    Mock.slash("refresh")
    equal(Mock.lfgSearches[#Mock.lfgSearches].activityIDs[1], 1201)
    -- a wing picked: inside the Monastery is inside; a listing for that wing counts, one for another wing does not,
    -- and the whole Monastery picked takes them all
    local searches = #Mock.lfgSearches
    Mock.slash("cath")
    equal(ns.Dungeons:Picked().key, cathedral.key)
    equal(#Mock.lfgSearches, searches + 1, "a pick by command searches for it at once")
    equal(Mock.lfgSearches[#Mock.lfgSearches].activityIDs[1], 1007, "the Cathedral's activity")
    Mock.enterInstance(189, "Scarlet Monastery")
    Mock.advance(3)
    equal(ns.Position:Mine().text, "inside", "a wing picked, inside the instance: inside")
    Mock.lfgResults({
        { id = 21, leader = "Whitemane", activity = 1007, roles = "H", class = "PRIEST", level = 40, area = "Tirisfal Glades" },
        { id = 22, leader = "Doan", activity = 1005, roles = "D", class = "MAGE", level = 35, area = "Tirisfal Glades" },
    })
    Mock.advance(0.5)
    equal(#ns.LFG.listed, 1); equal(ns.LFG.listed[1].name, "Whitemane", "only the Cathedral's listing")
    Mock.slash("scarlet monastery")
    Mock.advance(0.5)
    equal(#ns.LFG.listed, 2, "the whole Monastery: every wing's listing")
    Mock.slash("refresh")
    equal(#Mock.lfgSearches[#Mock.lfgSearches].activityIDs, 4, "a search for the whole Monastery asks for all four wings")
    -- with the finder loaded, a pick from the panel's dropdown sets the finder's own filter and runs its search
    Mock.openLFG({})
    Mock.advance(1.5)
    Mock.click(AKForeverLFGRadarPick)
    local graveyardRow
    for _, row in ipairs(ns.Panel.pickerRows) do
        if row.dungeon and row.dungeon.key == "189:scarlet-monastery-graveyard" then graveyardRow = row end
    end
    check(graveyardRow and graveyardRow:IsShown() and graveyardRow.text:GetText():find("    ", 1, true) and graveyardRow.text:GetText():find("Graveyard", 1, true)
        and not graveyardRow.text:GetText():find("Scarlet Monastery - Graveyard", 1, true), "the wing indented under its instance, by its own part of the name: " .. tostring(graveyardRow and graveyardRow.text:GetText()))
    searches = #Mock.lfgSearches
    local pickSearches = ns.LFG.stats.pickSearches
    Mock.click(graveyardRow)
    equal(ns.Dungeons:Picked().key, "189:scarlet-monastery-graveyard")
    equal(#Mock.lfgSearches, searches + 1, "a search of ours, at once")
    equal(Mock.lfgSearches[#Mock.lfgSearches].activityIDs[1], 1004); equal(#Mock.lfgSearches[#Mock.lfgSearches].activityIDs, 1)
    equal(ns.LFG.stats.pickSearches, pickSearches + 1)
    equal(#Mock.browseSelections, 0, "nothing of the finder's written: its own filter is left alone (tainted values there get its own searches blocked)")
    equal(#LFGBrowseFrame.ActivityDropdown.selectedValues, 0, "its dropdown keeps its own choice")
    Mock.advance(1.5)
    equal(ns.Dungeons:Picked().key, "189:scarlet-monastery-graveyard", "the pick stands: the finder's filter did not change")
    -- the finder's filter on every wing: the whole Monastery is the pick
    Mock.openLFG({ 1004, 1005, 1006, 1007 })
    Mock.advance(1.5)
    equal(ns.Dungeons:Picked().key, "189", "all four wings in the filter: the Monastery itself")
    Mock.openLFG({ 1004, 1001 })
    Mock.advance(1.5)
    equal(ns.Dungeons:Picked().key, "189", "a wing and another dungeon: the pick stays")
    Mock.closeLFG()
    Mock.advance(1.5)
    Mock.moveTo("Westfall", 0.5, 0.5)
    Mock.advance(3)
    -- the journal, when the client has one, adds instances by name
    G = _G
    G.EJ_GetNumTiers = function() return 1 end
    G.EJ_SelectTier = function() end
    G.EJ_GetInstanceByIndex = function(index, isRaid)
        local list = isRaid and { { 9001, "Molten Core" } } or { { 9002, "Hall of Thanes" }, { 9003, "Grim Batol" } }
        local entry = list[index]
        if entry then return entry[1], entry[2], "", 0, 0, 0, 0, "", false end
    end
    ns.Dungeons:Discover("journal")
    local batol = ns.Dungeons:Find("batol")
    check(batol and batol.journalID == 9003 and not batol.id, "a journal instance the finder does not list: by name, until the finder or a walk-in gives its id")
    equal(ns.Dungeons:Find("thanes").journalID, 9002, "the same instance from both sources is one entry")
    equal(ns.Dungeons.list[#ns.Dungeons.list].name, "Grim Batol", "no level range known: last on the list")
    G.EJ_GetNumTiers, G.EJ_SelectTier, G.EJ_GetInstanceByIndex = nil, nil, nil
end)

scenario("diagnostics and logout: the report is SavedVariables-safe and names the door's source; '/dr hide' and 'show'; the panel's place is remembered per character; '/dr reset' puts it back", function()
    local ns = start()
    Mock.slash("deadmines")
    Mock.advance(4)
    Mock.slash("diag")
    check(printed("report written"), "told")
    local report = AKForeverLFGRadarDB.diag
    check(report and report.entrance and report.entrance.source, "the door's source is in the report")
    check(savedSafe(report), "nothing but strings, numbers, booleans and tables")
    Mock.slash("show")
    check(panel():IsShown())
    Mock.slash("hide")
    check(not panel():IsShown())
    Mock.slash("show")
    check(panel():IsShown())
    panel().__scripts.OnDragStart(panel())
    panel():ClearAllPoints()
    panel():SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
    panel().__scripts.OnDragStop(panel())
    check(ns.cdb.panel and ns.cdb.panel.x == 300, "the place is saved")
    Mock.fire("PLAYER_LOGOUT")
    check(AKForeverLFGRadarDB.diag, "a report at logout")
    local again = start({ db = AKForeverLFGRadarDB })
    local point = { panel():GetPoint(1) }
    equal(point[4], 300, "the place is back"); equal(point[5], -200)
    Mock.slash("reset")
    point = { panel():GetPoint(1) }
    equal(point[1], "TOPRIGHT", "the first place again")
    check(again.cdb.panel == nil)
end)

Mock.realPrint(string.format("\n%d passed, %d failed", passed, #failures))
os.exit(#failures == 0 and 0 or 1)
