local Processing = {}
BootyChat.Modules.MessageProcessing = Processing
local Moderation = BootyChat.Services.Moderation
local Assert = assert
local function Raise(message) Assert(false, message) end
local Methods = {}
local events = {
    CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_BATTLEGROUND = true, CHAT_MSG_BATTLEGROUND_LEADER = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true,
}
local function Global(name) return type(getglobal) == "function" and getglobal(name) or _G[name] end
local function Text(value, maximum)
    return type(value) == "string" and string.len(value) <= maximum
end
local function Clock()
    if type(GetTime) ~= "function" then Raise("Native chat moderation clock is unavailable.") end
    local now = GetTime()
    if type(now) ~= "number" or now ~= now or now - now ~= 0 or now < 0 then Raise("Native chat moderation clock is invalid.") end
    return now
end
local function Context(frame, values)
    local eventType, raw, sender = event, arg1, arg2
    if this ~= frame or not events[eventType] or not Text(values[2], 4096) or
        not Text(raw, 4096) or not Text(sender, 64) or sender == "" or
        not Text(arg3, 64) or not Text(arg4, 128) or not Text(arg6, 64) or
        type(ChatTypeInfo) ~= "table" then return end
    local kind = string.sub(eventType, 10)
    local info, channel = ChatTypeInfo[kind], nil
    if kind == "CHANNEL" then
        if not Text(arg9, 128) or type(arg8) ~= "number" or arg8 ~= math.floor(arg8) or arg8 < 1 or arg8 > 32 then return end
        info, channel = ChatTypeInfo["CHANNEL" .. arg8], arg9
    end
    if type(info) ~= "table" or type(info.id) ~= "number" or values[6] ~= info.id then return end
    if kind == "TEXT_EMOTE" then
        if values[2] == raw then return eventType, sender, channel, raw end
        return
    end
    if type(TEXT) ~= "function" then return end
    local template = Global("CHAT_" .. kind .. "_GET")
    if type(template) ~= "string" then return end
    local flag = ""
    if arg6 ~= "" then
        local value = Global("CHAT_FLAG_" .. arg6)
        if type(value) ~= "string" then return end
        flag = TEXT(value)
        if type(flag) ~= "string" then return end
    end
    local header = ""
    if arg3 ~= "" and arg3 ~= "Universal" and arg3 ~= frame.defaultLanguage then header = "[" .. arg3 .. "] " end
    local player = flag .. sender
    if kind ~= "EMOTE" or header ~= "" then player = flag .. "|Hplayer:" .. sender .. "|h[" .. sender .. "]|h" end
    if not string.find(values[2], player, 1, true) then return end
    local localized = TEXT(template)
    if type(localized) ~= "string" then return end
    local formatted, body = pcall(string.format, localized .. header .. raw, player)
    if not formatted then return end
    if arg4 ~= "" then body = "[" .. arg4 .. "] " .. body end
    -- Event globals can also be visible to addon diagnostics. Only the exact
    -- native formatted delivery is eligible for policy; unknown wrappers yield.
    if values[2] ~= body then return end
    return eventType, sender, channel, (string.gsub(raw, "%%%%", "%%"))
end
function Processing.New(windowCount)
    if type(Moderation) ~= "table" or type(Moderation.New) ~= "function" then return nil, "Chat message moderation is unavailable." end
    local moderation, failure = Moderation.New(windowCount)
    if not moderation then return nil, failure end
    return setmetatable({moderation = moderation}, {__index = Methods})
end
function Methods:Apply(preferences, playerName)
    local ok, failure = self.moderation:Apply(preferences, playerName)
    if ok ~= true then return false, failure or "Chat message moderation declined its settings." end
    self.highlight, self.sound = preferences.mentionHighlight, preferences.mentionSound
    self.r, self.g, self.b = preferences.mentionColor[1], preferences.mentionColor[2], preferences.mentionColor[3]
    return true
end
function Methods:IsActive() return self.moderation:IsActive() end
function Methods:Reset()
    local ok, failure = self.moderation:Reset()
    if ok ~= true then return false, failure or "Chat message moderation could not reset its session state." end
    return true
end
function Methods:Evaluate(windowId, frame, values)
    if not self:IsActive() then return true end
    local eventType, sender, channel, raw = Context(frame, values)
    if not eventType then return true end
    local now = Clock()
    local suppressed, mentioned, normalized = self.moderation:Evaluate(windowId, eventType, sender, channel, raw, now)
    if suppressed then return false end
    if mentioned and self.highlight then values[3], values[4], values[5] = self.r, self.g, self.b end
    return true, {windowId = windowId, eventType = eventType, sender = sender, channel = channel,
        body = normalized, now = now, mentioned = mentioned}
end
function Methods:Commit(ticket)
    -- A native/foreign renderer may deliver a nested message first. Timestamp
    -- accepted state at commitment, rather than rewinding to the outer entry.
    local now = Clock()
    local alert = self.moderation:Accept(ticket.windowId, ticket.eventType, ticket.sender, ticket.channel,
        ticket.body, now, ticket.mentioned)
    if alert and self.sound and ticket.eventType ~= "CHAT_MSG_WHISPER" then
        if type(PlaySound) ~= "function" then Raise("Native chat mention sound is unavailable.") end
        -- FrameXML treats this native API as a void call. Its return is opaque.
        PlaySound("TellMessage")
    end
    return true
end
