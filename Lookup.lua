-- Lookup: a /who for a listed member the finder does not place (the user, 2026-10-16: "for groups it seems
-- not to be able to place anyone but the top group member, it should be running /who on those others while
-- it is in a state of not knowing").
--
-- A listing names an area for its leader only. For every other member - and for anyone the channel has not
-- heard from - one who query by name ('n-"Name"') asks the server where they are. C_FriendList.SendWho is
-- restricted to a key press or a click on this client, so the queries RIDE ON YOUR OWN KEY PRESSES: a frame
-- hears every key and passes every key on (the way AKForeverNiceWarstomp sends its yell, proven in game
-- 2026-10-02), and a fresh press - a held key repeats within a second, so a key that has not gone down for
-- longer is pressed afresh - sends the next query, ten seconds after the last at the soonest (the server's
-- patience). The Refresh click sends one too. The answer holds for five minutes; a name the who did not find
-- - offline, or spelt otherwise - is left alone for three.
--
-- THE ANSWER COMES THROUGH THE CHAT. Results sent to the UI (SetWhoToUi) fire WHO_LIST_UPDATE, and on this
-- flavour the finder's Who tab answers that event with ShowUIPanel(LFGParentFrame), every time (the user,
-- 2026-10-16: "it keeps randomly opening the LFG tool when i'm not using it"). So the results are left on
-- the chat path: each comes as a system line ("[Name]: Level 20 Human Paladin - Westfall") that a chat
-- filter of ours reads and swallows while a query of ours is out, so nothing lands in the chat window and
-- nothing opens. Should the client fire WHO_LIST_UPDATE all the same (the Who tab open, say), that answer is
-- read too.
local _, ns = ...

local Lookup = {}
ns.Lookup = Lookup

local GAP_SECONDS = 10
local FRESH_AFTER = 1.5
local KNOWN_SECONDS = 300
local MISSING_SECONDS = 180
local PENDING_SECONDS = 10

Lookup.queue = {}    -- names waiting, in the finder's order
Lookup.known = {}    -- [name] = { area, at (time()), missing }
Lookup.pending = nil -- the query on its way: { name, at (GetTime()), how }
Lookup.stats = { asked = 0, answered = 0, found = 0, missing = 0, refused = 0, viaKey = 0, viaClick = 0, keyDowns = 0, repeats = 0, armProblem = nil,
    byChat = 0, byEvent = 0, swallowed = 0, unanswered = 0, filterInstalled = false }

local lastAsk = nil
local keys, armed = nil, false
local lastDown = {}

------------------------------------------------------------------------
-- What is known, what is wanted
------------------------------------------------------------------------
function Lookup:Area(name)
    local entry = name and self.known[name]
    if entry and not entry.missing and time() - entry.at <= KNOWN_SECONDS then
        return entry.area
    end
    return nil
end

-- the names the finder's list leaves unplaced, in its order (LFG:Build hands them over after every build)
function Lookup:Request(names)
    self.queue = names or {}
end

local function stale(entry)
    if not entry then
        return true
    end
    if entry.missing then
        return time() - entry.at > MISSING_SECONDS
    end
    return time() - entry.at > KNOWN_SECONDS
end

function Lookup:Next()
    for _, name in ipairs(self.queue) do
        if stale(self.known[name]) and not (self.pending and self.pending.name == name) then
            return name
        end
    end
    return nil
end

-- the name to ask now, with the gaps honoured - or nil
function Lookup:Due()
    local now = GetTime()
    if self.pending and now - self.pending.at < PENDING_SECONDS then
        return nil
    end
    if lastAsk and now - lastAsk < GAP_SECONDS then
        return nil
    end
    return self:Next()
end

------------------------------------------------------------------------
-- Asking - from a key press or a click only
------------------------------------------------------------------------
function Lookup:Ask(how)
    local name = self:Due()
    if not name then
        return false
    end
    local api = C_FriendList
    if type(api) ~= "table" or type(api.SendWho) ~= "function" then
        return false
    end
    -- not SetWhoToUi: results sent to the UI open the finder's Who tab on this flavour; the chat path it is
    local ok, err = pcall(api.SendWho, 'n-"' .. name .. '"')
    if not ok then
        self.stats.refused = self.stats.refused + 1
        ns:Log("lookup_refused", { name = name, how = how, error = tostring(err) })
        return false
    end
    self.pending = { name = name, at = GetTime(), how = how, lines = 0 }
    lastAsk = GetTime()
    self.stats.asked = self.stats.asked + 1
    if how == "key" then
        self.stats.viaKey = self.stats.viaKey + 1
    else
        self.stats.viaClick = self.stats.viaClick + 1
    end
    ns:Log("lookup_asked", { name = name, how = how })
    ns:Fire("LOOKUP_CHANGED")
    return true
end

local function readAnswer(name)
    local api = C_FriendList
    local counts = ns.Readable(api.GetNumWhoResults)
    local shown = counts and counts[1]
    local wanted = string.lower(name)
    for index = 1, (type(shown) == "number" and shown or 0) do
        local info = ns.Readable(api.GetWhoInfo, index)
        info = info and info[1]
        if type(info) == "table" and not ns.AnySecret(info.fullName, info.area) and type(info.fullName) == "string" then
            local found = string.lower(info.fullName)
            if found == wanted or string.sub(found, 1, #wanted + 1) == wanted .. " " or string.sub(found, 1, #wanted + 1) == wanted .. "-" then
                return type(info.area) == "string" and info.area ~= "" and info.area or nil
            end
        end
    end
    return nil
end

local function settle(pending, area, by)
    Lookup.pending = nil
    Lookup.stats.answered = Lookup.stats.answered + 1
    Lookup.stats[by] = Lookup.stats[by] + 1
    if area then
        Lookup.known[pending.name] = { area = area, at = time() }
        Lookup.stats.found = Lookup.stats.found + 1
    else
        Lookup.known[pending.name] = { missing = true, at = time() }
        Lookup.stats.missing = Lookup.stats.missing + 1
    end
    ns:Log("lookup_answered", { name = pending.name, area = area, how = pending.how, by = by })
    ns:Fire("LOOKUP_CHANGED")
end

-- the Who tab open, say: the client sends the results to the UI after all, and says so
ns:On("WHO_LIST_UPDATE", function()
    local pending = Lookup.pending
    if not pending or GetTime() - pending.at > PENDING_SECONDS then
        return
    end
    settle(pending, readAnswer(pending.name), "byEvent")
end)

-- a who result line in the chat: "[Name]: Level 20 Human Paladin <Guild> - Westfall" (the player link in
-- front of it carries the name); the count line "3 players total" closes the answer
local function parseWhoLine(text)
    local name = string.match(text, "|Hplayer:([^|:]+)")
    if not name then
        return nil
    end
    name = string.match(name, "^(.-)%-[^%-]*$") or name -- a realm suffix, if any
    if not string.find(text, "Level %d+") then
        return nil
    end
    local area = string.match(text, " %- ([^|]-)%s*$")
    return name, area
end

local function isCountLine(text)
    return string.find(text, "^%d+ [%a%s]+ total$") ~= nil or (type(WHO_NUM_RESULTS) == "string" and string.find(text, string.gsub(WHO_NUM_RESULTS, "%%d", "%%d+"):gsub("|4[^;]*;", "%%a+"), 1) ~= nil)
end

-- while a query of ours is out, its lines are ours: read, and swallowed
local function onSystemMessage(_, _, text)
    local pending = Lookup.pending
    if not pending or ns.IsSecret(text) or type(text) ~= "string" or GetTime() - pending.at > PENDING_SECONDS then
        return false
    end
    local name, area = parseWhoLine(text)
    if name then
        pending.lines = pending.lines + 1
        Lookup.stats.swallowed = Lookup.stats.swallowed + 1
        local wanted = string.lower(pending.name)
        local found = string.lower(name)
        if found == wanted or string.sub(found, 1, #wanted + 1) == wanted .. " " then
            pending.area = area
            pending.hit = true
        end
        return true
    end
    if isCountLine(text) then
        Lookup.stats.swallowed = Lookup.stats.swallowed + 1
        settle(pending, pending.hit and pending.area or nil, "byChat")
        return true
    end
    return false
end

-- a query nobody answered within its time: given up, and the name left alone for a while
local function expire()
    local pending = Lookup.pending
    if pending and GetTime() - pending.at > PENDING_SECONDS then
        Lookup.stats.unanswered = Lookup.stats.unanswered + 1
        settle(pending, pending.hit and pending.area or nil, "byChat")
    end
end

------------------------------------------------------------------------
-- The key rider: every key heard and passed on; a fresh press sends the next query
------------------------------------------------------------------------
local function arm()
    if armed or not keys then
        return
    end
    if InCombatLockdown() then
        return -- refused in a fight: PLAYER_REGEN_ENABLED tries again
    end
    local ok = pcall(keys.SetPropagateKeyboardInput, keys, true)
    local passesOn = ok and type(keys.GetPropagateKeyboardInput) == "function" and keys:GetPropagateKeyboardInput() == true
    if not passesOn then
        Lookup.stats.armProblem = ok and "the client did not confirm that keys are passed on" or "SetPropagateKeyboardInput failed"
        return
    end
    keys:EnableKeyboard(true)
    armed, Lookup.stats.armProblem = true, nil
end

local function onKeyDown(_, key)
    if ns.IsSecret(key) or type(key) ~= "string" then
        key = "?"
    end
    local now = GetTime()
    Lookup.stats.keyDowns = Lookup.stats.keyDowns + 1
    local last = lastDown[key]
    lastDown[key] = now
    if last and now - last < FRESH_AFTER then
        Lookup.stats.repeats = Lookup.stats.repeats + 1 -- held, or pressed again at once: no press to the client
        return
    end
    if Lookup:Due() then
        Lookup:Ask("key")
    end
end

local function onKeyUp(_, key)
    if not ns.IsSecret(key) and type(key) == "string" then
        lastDown[key] = nil
    end
end

ns:Listen("LOGIN", function()
    if type(ChatFrame_AddMessageEventFilter) == "function" then
        local ok = pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", function(...)
            local swallowed = false
            ns.SafeCall(function(...)
                swallowed = onSystemMessage(...)
            end, ...)
            return swallowed
        end)
        Lookup.stats.filterInstalled = ok and true or false
    end
    C_Timer.NewTicker(2, function()
        ns.SafeCall(expire)
    end)
    keys = CreateFrame("Frame", "AKForeverLFGRadarKeys", UIParent)
    keys:SetScript("OnKeyDown", function(...)
        ns.SafeCall(onKeyDown, ...)
    end)
    keys:SetScript("OnKeyUp", function(...)
        ns.SafeCall(onKeyUp, ...)
    end)
    Lookup.keys = keys
    arm()
end)

ns:On("PLAYER_REGEN_ENABLED", arm)

function Lookup:Describe()
    local waiting = 0
    for _, name in ipairs(self.queue) do
        if stale(self.known[name]) then
            waiting = waiting + 1
        end
    end
    return { stats = self.stats, pending = self.pending, waiting = waiting, queue = self.queue, known = self.known, armed = armed }
end
