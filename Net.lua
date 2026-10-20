-- Net: everyone with the addon tells everyone else where they are - over a hidden chat channel.
--
-- The channel "AKLFGRadar" is joined at login (JoinTemporaryChannel: proven from a timer on this realm,
-- 2026-10-01) and addon messages go into it (C_ChatInfo.SendAddonMessage with chatType CHANNEL and the
-- channel's number; proven to arrive after 3-6 seconds). Chat itself the realm forbids addons; addon
-- messages it allows. Nothing is written into a chat window: the channel is not added to one.
--
-- Wire format, prefix "AKLR", fields split by "|", one message under 240 bytes:
--   P|1|<dungeon key or ->|<state I/O/Z>|<uiMap>|<x>|<y>|<continent>|<wx>|<wy>|<zone>|<level>|<class>|<instance>
--       my position: I = inside <instance>, O = outdoors with coordinates, Z = zone only
--   E|<dungeon key>|<uiMap>|<x>|<y>|<by>         a door somebody walked through
--   R|1                                          a request: everyone answers with P (+ their own doors)
-- Positions go out every 15 seconds while you move (15 yards or more, a zone or instance change, a new
-- pick), every 60 seconds regardless; a peer not heard from for 90 seconds leaves the list. Your own
-- messages come back from the channel too and are counted, not read.
local _, ns = ...

local Net = {}
ns.Net = Net

local PREFIX = "AKLR"
local CHANNEL = "AKLFGRadar"
local VERSION = "1"
local MAX_MESSAGE = 240
local TICK_SECONDS = 5
local SEND_MOVED_SECONDS = 15
local HEARTBEAT_SECONDS = 60
local PEER_TTL_SECONDS = 90
local JOIN_RETRY_SECONDS = 30
local MOVE_YARDS = 15

Net.channelID = nil
Net.peers = {}   -- [name] = { name, class, level, dungeon, state, uiMap, x, y, continent, wx, wy, zone, instanceKey, at, sampleLike }
Net.stats = { sent = 0, received = 0, own = 0, failed = 0, malformed = 0, lastResult = nil, lastSentAt = nil, lastReceivedAt = nil,
    joinAttempts = 0, joinedAt = nil, prefixRegistered = false, requests = 0 }

local unpack = table.unpack or unpack
local dirty = true
local lastSent = nil  -- { at, sample signature }

------------------------------------------------------------------------
-- Small codecs
------------------------------------------------------------------------
local function clean(text)
    if type(text) ~= "string" then
        return ""
    end
    return (string.gsub(text, "[|;,]", " "))
end

local function fmt(value, decimals)
    if type(value) ~= "number" then
        return ""
    end
    return string.format("%." .. decimals .. "f", value)
end

local function num(text)
    if text == nil or text == "" then
        return nil
    end
    return tonumber(text)
end

local function split(text, separator)
    local parts, from = {}, 1
    while true do
        local at = string.find(text, separator, from, true)
        if not at then
            parts[#parts + 1] = string.sub(text, from)
            break
        end
        parts[#parts + 1] = string.sub(text, from, at - 1)
        from = at + #separator
    end
    return parts
end

------------------------------------------------------------------------
-- The channel
------------------------------------------------------------------------
local function findChannel()
    local answer = ns.Readable(GetChannelName, CHANNEL)
    local id = answer and answer[1]
    if type(id) == "number" and id > 0 then
        Net.channelID = id
        return id
    end
    Net.channelID = nil
    return nil
end

local function onJoined()
    if Net.stats.joinedAt then
        return
    end
    Net.stats.joinedAt = GetTime()
    ns:Log("channel_joined", { id = Net.channelID })
    Net:Request()
    dirty = true
    Net:MaybeSend(true)
    ns:Fire("NET_CHANGED")
end

function Net:Join()
    if findChannel() then
        onJoined()
        return
    end
    self.stats.joinAttempts = self.stats.joinAttempts + 1
    local result = ns.Readable(JoinTemporaryChannel, CHANNEL)
    ns:Log("channel_join", { attempt = self.stats.joinAttempts, result = result and result[1] })
    C_Timer.After(1, function()
        if findChannel() then
            onJoined()
        end
    end)
end

ns:On("CHAT_MSG_CHANNEL_NOTICE", function(_, kind, _, _, _, _, _, _, _, channelBaseName)
    if ns.AnySecret(kind, channelBaseName) or channelBaseName ~= CHANNEL then
        return
    end
    if kind == "YOU_LEFT" or kind == "YOU_CHANGED" and not findChannel() then
        Net.channelID, Net.stats.joinedAt = nil, nil
        ns:Fire("NET_CHANGED")
        return
    end
    if findChannel() then
        onJoined()
    end
end)

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local function transmit(text)
    if not Net.channelID or type(C_ChatInfo) ~= "table" or type(C_ChatInfo.SendAddonMessage) ~= "function" then
        return false
    end
    if #text > 255 then
        Net.stats.failed = Net.stats.failed + 1
        ns:Log("net_too_long", #text)
        return false
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", tostring(Net.channelID))
    Net.stats.lastResult = ok and result or ("error: " .. tostring(result))
    if ok and (result == 0 or result == true or result == nil) then
        Net.stats.sent = Net.stats.sent + 1
        Net.stats.lastSentAt = GetTime()
        return true
    end
    Net.stats.failed = Net.stats.failed + 1
    return false
end

local function mySample()
    return ns.Position and ns.Position.sample or nil
end

local function encodePosition(s)
    local picked = ns.Dungeons:Picked()
    local state, instance = "Z", ""
    if s.inInstance then
        state, instance = "I", tostring(s.instanceID or s.instanceName or "")
    elseif type(s.wx) == "number" then
        state = "O"
    end
    local level = ns.Readable(UnitLevel, "player")
    return table.concat({ "P", VERSION, picked and picked.key or "-", state, s.uiMap or "", fmt(s.x, 4), fmt(s.y, 4),
        s.continent or "", fmt(s.wx, 0), fmt(s.wy, 0), clean(s.zone), level and level[1] or "", ns.playerClass or "", clean(instance) }, "|")
end

local function signature(s)
    local picked = ns.Dungeons:Picked()
    return table.concat({ picked and picked.key or "-", tostring(s.inInstance), tostring(s.instanceID or s.instanceName or ""), tostring(s.uiMap), tostring(s.zone) }, "/")
end

local function movedSince(last, s)
    if not last or not last.sample then
        return true
    end
    local a = last.sample
    if type(a.wx) == "number" and type(s.wx) == "number" and a.continent == s.continent then
        return math.sqrt((a.wx - s.wx) ^ 2 + (a.wy - s.wy) ^ 2) >= MOVE_YARDS
    end
    return (a.wx ~= nil) ~= (s.wx ~= nil)
end

function Net:SendPosition()
    local s = mySample()
    if not s or not self.channelID or not ns:GetOption("share") then
        return false
    end
    if transmit(encodePosition(s)) then
        lastSent = { at = GetTime(), sample = s, signature = signature(s) }
        dirty = false
        return true
    end
    return false
end

-- the cadence: moved or changed -> 15 s apart; nothing new -> every 60 s
function Net:MaybeSend(force)
    local s = mySample()
    if not s or not self.channelID or not ns:GetOption("share") then
        return
    end
    local now = GetTime()
    local since = lastSent and (now - lastSent.at) or math.huge
    local changed = dirty or not lastSent or lastSent.signature ~= signature(s) or movedSince(lastSent, s)
    if force or since >= HEARTBEAT_SECONDS or (changed and since >= SEND_MOVED_SECONDS) then
        self:SendPosition()
    end
end

function Net:Request()
    if transmit("R|" .. VERSION) then
        self.stats.requests = self.stats.requests + 1
    end
end

function Net:SendDoor(key, entry)
    if type(entry) ~= "table" then
        return
    end
    transmit(table.concat({ "E", key, entry.zone, fmt(entry.x, 4), fmt(entry.y, 4), clean(entry.by or ns.playerName) }, "|"))
end

function Net:SendMyDoors()
    for key, entry in pairs(ns.db and ns.db.learned or {}) do
        if entry.from ~= "peer" then
            self:SendDoor(key, entry)
        end
    end
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local function ownName(sender)
    local me = ns.playerName
    if not me then
        return false
    end
    return sender == me or string.find(sender, "^" .. (string.gsub(me, "%W", "%%%0")) .. "%-") ~= nil
end

local function shortName(sender)
    local realm = ns.Readable(GetRealmName)
    realm = realm and type(realm[1]) == "string" and string.gsub(realm[1], "%s", "") or nil
    if realm and realm ~= "" then
        local base = string.match(sender, "^(.-)%-" .. (string.gsub(realm, "%W", "%%%0")) .. "$")
        if base then
            return base
        end
    end
    return sender
end

local function onPosition(fields, sender, now)
    local peer = Net.peers[sender] or { name = sender, firstSeen = now }
    peer.version = fields[2]
    peer.dungeon = fields[3] ~= "-" and fields[3] or nil
    peer.state = fields[4]
    peer.uiMap = num(fields[5])
    peer.x, peer.y = num(fields[6]), num(fields[7])
    peer.continent = num(fields[8])
    peer.wx, peer.wy = num(fields[9]), num(fields[10])
    peer.zone = fields[11] ~= "" and fields[11] or nil
    peer.level = num(fields[12])
    peer.class = fields[13] ~= "" and fields[13] or nil
    peer.instanceKey = fields[14] ~= "" and fields[14] or nil
    peer.at = now
    peer.sampleLike = {
        inInstance = peer.state == "I", instanceID = num(peer.instanceKey), instanceName = peer.instanceKey,
        uiMap = peer.uiMap, x = peer.x, y = peer.y, continent = peer.continent, wx = peer.wx, wy = peer.wy, zone = peer.zone,
    }
    Net.peers[sender] = peer
end

local function onDoor(fields, sender)
    local key, uiMap, x, y, by = fields[2], num(fields[3]), num(fields[4]), num(fields[5]), fields[6]
    if key and uiMap and x and y then
        ns.Dungeons:Learn(key, uiMap, x, y, (by ~= "" and by) or sender, "peer")
    end
end

local function onAddonMessage(_, prefix, text, channel, sender)
    if prefix ~= PREFIX or ns.AnySecret(text, channel, sender) or type(text) ~= "string" or type(sender) ~= "string" then
        return
    end
    sender = shortName(sender)
    if ownName(sender) then
        Net.stats.own = Net.stats.own + 1
        return
    end
    local now = GetTime()
    Net.stats.received = Net.stats.received + 1
    Net.stats.lastReceivedAt = now
    local fields = split(text, "|")
    local kind = fields[1]
    if kind == "P" and #fields >= 13 then
        onPosition(fields, sender, now)
        ns:Fire("PEERS_CHANGED")
    elseif kind == "E" and #fields >= 5 then
        onDoor(fields, sender)
    elseif kind == "R" then
        -- answer a little later, each at a different moment: a burst of answers is what the throttle hates
        C_Timer.After(0.5 + math.random() * 2, function()
            ns.SafeCall(Net.SendPosition, Net)
            ns.SafeCall(Net.SendMyDoors, Net)
        end)
    else
        Net.stats.malformed = Net.stats.malformed + 1
    end
end

------------------------------------------------------------------------
-- The peers, for the panel
------------------------------------------------------------------------
function Net:Prune()
    local now, gone = GetTime(), false
    for name, peer in pairs(self.peers) do
        if now - peer.at > PEER_TTL_SECONDS then
            self.peers[name] = nil
            gone = true
        end
    end
    if gone then
        ns:Fire("PEERS_CHANGED")
    end
end

-- every peer with their proximity to the dungeon given (yours, by default), nearest first
function Net:Peers(dungeon)
    dungeon = dungeon or ns.Dungeons:Picked()
    local list = {}
    for _, peer in pairs(self.peers) do
        local proximity = ns.Position.Proximity(peer.sampleLike, dungeon)
        list[#list + 1] = { peer = peer, proximity = proximity, age = GetTime() - peer.at }
    end
    table.sort(list, function(a, b)
        if a.proximity.rank ~= b.proximity.rank then
            return a.proximity.rank < b.proximity.rank
        end
        if (a.proximity.yards or 0) ~= (b.proximity.yards or 0) then
            return (a.proximity.yards or 0) < (b.proximity.yards or 0)
        end
        return a.peer.name < b.peer.name
    end)
    return list
end

function Net:CountsByDungeon()
    local counts = {}
    local mine = ns.Dungeons:Picked()
    if mine then
        counts[mine.key] = 1
    end
    for _, peer in pairs(self.peers) do
        if peer.dungeon then
            counts[peer.dungeon] = (counts[peer.dungeon] or 0) + 1
        end
    end
    return counts
end

function Net:PeerCount()
    local count = 0
    for _ in pairs(self.peers) do
        count = count + 1
    end
    return count
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
ns:Listen("LOGIN", function()
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        Net.stats.prefixRegistered = ok and (result == true or result == 0 or result == nil) or false
    end
    ns:On("CHAT_MSG_ADDON", onAddonMessage)
    C_Timer.After(2, function()
        ns.SafeCall(Net.Join, Net)
    end)
    C_Timer.NewTicker(TICK_SECONDS, function()
        ns.SafeCall(function()
            if not Net.channelID then
                if Net.stats.joinAttempts == 0 or (GetTime() - (Net.lastJoinTry or 0)) >= JOIN_RETRY_SECONDS then
                    Net.lastJoinTry = GetTime()
                    Net:Join()
                end
                return
            end
            Net:Prune()
            Net:MaybeSend()
        end)
    end)
end)

ns:Listen("POSITION_CHANGED", function()
    dirty = true
end)

ns:Listen("PICK_CHANGED", function()
    dirty = true
    if Net.channelID then
        Net:MaybeSend(true)
    end
end)

ns:Listen("ENTRANCE_WALKED_IN", function(key, entry)
    Net:SendDoor(key, entry)
end)

ns:Listen("OPTION_CHANGED", function(key, value)
    if key == "share" and value then
        dirty = true
        Net:MaybeSend(true)
    end
end)

ns:RegisterCommand("share", "'on' (default) tells the others where you are; 'off' keeps you to yourself - you still see them", function(rest)
    local word = string.lower(rest or "")
    if word == "on" then
        ns:SetOption("share", true)
        ns:Print("sharing your position with everyone running the addon.")
    elseif word == "off" then
        ns:SetOption("share", false)
        ns:Print("your position stays with you - the others are still shown.")
    else
        ns:Print("sharing is " .. (ns:GetOption("share") and "on" or "off") .. " (|cffffd100/dr share on|r / |cffffd100off|r); "
            .. (Net.channelID and ("channel " .. Net.channelID .. ", " .. Net:PeerCount() .. " others heard from") or "channel not joined yet") .. ".")
    end
end)
