local Moderation = {}
BootyChat.Services.Moderation = Moderation
local History = BootyChat.Services.History
local Methods = {}
Moderation.MAX_RECORDS = 256
Moderation.MAX_BYTES = 262144
Moderation.MAX_MESSAGE_BYTES = 4096
Moderation.MAX_TERMS = 32
Moderation.MAX_TERM_BYTES = 128
Moderation.MAX_TERM_LIST_BYTES = 4096
Moderation.MAX_CHANNELS = 16
Moderation.MAX_CHANNEL_BYTES = 80
Moderation.MAX_CHANNEL_LIST_BYTES = 1536
local defaults = {blockedEnabled = false, repeatEnabled = false, filterScope = "channels",
    channels = "", blockedTerms = "", repeatSeconds = 15, mentionEnabled = false,
    mentionScope = "all", mentionChannels = "", mentionPlayer = true, mentionTerms = "",
    mentionWholeWord = true, mentionHighlight = true, mentionColor = {1, 0.82, 0},
    mentionSound = false, alertCooldown = 5}
local scopes = {channels = true, public = true, group = true, all = true}
local playerEvents = {CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true, CHAT_MSG_WHISPER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_BATTLEGROUND = true, CHAT_MSG_BATTLEGROUND_LEADER = true}
local groupEvents = {CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_BATTLEGROUND = true, CHAT_MSG_BATTLEGROUND_LEADER = true}
local function Plain(value) return type(value) == "table" and getmetatable(value) == nil end
local function Finite(value) return type(value) == "number" and value == value and value - value == 0 end
local function Integer(value, minimum, maximum)
    return Finite(value) and value == math.floor(value) and value >= minimum and value <= maximum
end
local function LowerByte(value) return string.char(string.byte(value) + 32) end
local function Fold(value) return string.gsub(value, "[A-Z]", LowerByte) end
local function Control(value) return string.find(value, "[%z\001-\031\127]") ~= nil end
local function Trim(value) return string.gsub(string.gsub(value, "^ +", ""), " +$", "") end
local function Copy(value)
    if type(value) ~= "table" then return value end
    return {value[1], value[2], value[3]}
end
local function List(value, channels)
    local maximum = channels and Moderation.MAX_CHANNELS or Moderation.MAX_TERMS
    local size = channels and Moderation.MAX_CHANNEL_BYTES or Moderation.MAX_TERM_BYTES
    local bytes = channels and Moderation.MAX_CHANNEL_LIST_BYTES or Moderation.MAX_TERM_LIST_BYTES
    if type(value) ~= "string" or string.len(value) > bytes or Control(value) then
        return nil, "Chat lists must be bounded single-line text separated by semicolons."
    end
    local result, seen, first, count = {}, {}, 1, 0
    while first <= string.len(value) + 1 do
        local last = string.find(value, ";", first, true) or string.len(value) + 1
        local item = Trim(string.sub(value, first, last - 1))
        if item ~= "" then
            count = count + 1
            if count > maximum or string.len(item) > size then
                return nil, "Chat list has too many entries or an oversized entry."
            end
            item = Fold(item)
            if not seen[item] then result[table.getn(result) + 1], seen[item] = item, true end
        end
        if last > string.len(value) then break end
        first = last + 1
    end
    return result
end
function Moderation.GetDefault(key) return Copy(defaults[key]) end
function Moderation.ValidateValue(key, value)
    if defaults[key] == nil then return false, "Unknown chat filter or mention setting: " .. tostring(key) end
    if value == nil then return true end
    local valid, failure
    if key == "channels" or key == "mentionChannels" or key == "blockedTerms" or key == "mentionTerms" then
        local list
        list, failure = List(value, key == "channels" or key == "mentionChannels")
        valid = list ~= nil
    elseif key == "filterScope" or key == "mentionScope" then valid = scopes[value] == true
    elseif key == "repeatSeconds" then valid = Integer(value, 1, 120)
    elseif key == "alertCooldown" then valid = Integer(value, 1, 60)
    elseif key == "mentionColor" then
        valid = Plain(value)
        if valid then
            for index = 1, 3 do valid = valid and Finite(value[index]) and value[index] >= 0 and value[index] <= 1 end
            for index in pairs(value) do if index ~= 1 and index ~= 2 and index ~= 3 then valid = false end end
        end
    else valid = type(value) == "boolean" end
    if not valid then return false, failure or "Invalid chat filter or mention setting: " .. tostring(key) end
    return true
end
function Moderation.ValidateSection(section)
    if section == nil then return true end
    if not Plain(section) then return false, "Chat filter and mention preferences must be a plain table." end
    for key, value in pairs(section) do
        local valid, failure = Moderation.ValidateValue(key, value)
        if not valid then return false, failure end
    end
    return true
end
function Moderation.Resolve(section)
    local valid, failure = Moderation.ValidateSection(section)
    if not valid then return nil, failure end
    local result = {}
    for key, default in pairs(defaults) do
        local value = section and section[key]
        if value == nil then value = default end
        result[key] = Copy(value)
    end
    return result
end
function Moderation.New(windowCount)
    if not Integer(windowCount, 1, 32) then return nil, "Invalid chat moderation window count." end
    if not History or type(History.PlainText) ~= "function" then return nil, "Visible chat text service is unavailable." end
    return setmetatable({windowCount = windowCount, records = {}, count = 0, bytes = 0,
        head = 1, active = false}, {__index = Methods})
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
function Methods:Reset()
    for _, record in pairs(self.records) do for key in pairs(record) do record[key] = nil end end
    self.count, self.bytes, self.head, self.lastNow, self.lastAlert = 0, 0, 1, nil, nil
    return true
end
function Methods:Apply(preferences, playerName)
    local resolved, failure = Moderation.Resolve(preferences)
    if not resolved then return false, failure end
    if playerName ~= nil and (type(playerName) ~= "string" or string.len(playerName) > 64 or Control(playerName)) then
        return false, "Invalid player name for chat mentions."
    end
    playerName = playerName and Fold(playerName) or ""
    local unchanged = self.playerName == playerName and self.preferences ~= nil
    if unchanged then
        for key, value in pairs(resolved) do if not Equal(self.preferences[key], value) then unchanged = false; break end end
    end
    if unchanged then return true end
    local blocked, mentions = List(resolved.blockedTerms), List(resolved.mentionTerms)
    local channels, mentionChannels = List(resolved.channels, true), List(resolved.mentionChannels, true)
    if resolved.mentionPlayer and playerName ~= "" then mentions[table.getn(mentions) + 1] = playerName end
    self:Reset()
    self.preferences, self.playerName = resolved, playerName
    self.blocked, self.mentions, self.channels, self.mentionChannels = blocked, mentions, channels, mentionChannels
    self.filterBlocked = resolved.blockedEnabled and table.getn(blocked) > 0
    self.filterRepeat = resolved.repeatEnabled
    self.checkMentions = resolved.mentionEnabled and table.getn(mentions) > 0 and
        (resolved.mentionHighlight or resolved.mentionSound)
    self.active = self.filterBlocked or self.filterRepeat or self.checkMentions
    return true
end
function Methods:IsActive() return self.active end
function Methods:GetStats()
    return {count = self.count, bytes = self.bytes, active = self.active, lastAlert = self.lastAlert}
end
local function Scope(scope, eventType)
    if not playerEvents[eventType] then return false end
    if scope == "all" then return true end
    if scope == "group" then return groupEvents[eventType] == true end
    return eventType == "CHAT_MSG_CHANNEL" or scope == "public" and
        (eventType == "CHAT_MSG_SAY" or eventType == "CHAT_MSG_YELL")
end
local function Channel(list, eventType, channel)
    if eventType ~= "CHAT_MSG_CHANNEL" then return true end
    if type(channel) ~= "string" or channel == "" then return false end
    if table.getn(list) == 0 then return true end
    channel = Fold(Trim(channel))
    for _, name in ipairs(list) do if channel == name then return true end end
    return false
end
local function Context(self, windowId, eventType, sender, channel, now)
    return Integer(windowId, 1, self.windowCount) and playerEvents[eventType] == true and
        type(sender) == "string" and string.len(sender) > 0 and string.len(sender) <= 64 and not Control(sender) and
        (channel == nil or type(channel) == "string" and string.len(channel) <= 128 and not Control(channel)) and
        Finite(now) and now >= 0
end
local function WordByte(value)
    return value and (value >= 128 or value >= 48 and value <= 57 or value >= 65 and value <= 90 or
        value >= 97 and value <= 122 or value == 95)
end
local function Match(text, term, whole)
    local position = string.find(text, term, 1, true)
    while position do
        if not whole or not WordByte(string.byte(text, position - 1)) and
            not WordByte(string.byte(text, position + string.len(term))) then return true end
        position = string.find(text, term, position + 1, true)
    end
    return false
end
local function Index(self, offset) return math.mod(self.head + offset - 1, Moderation.MAX_RECORDS) + 1 end
local function Find(self, windowId, eventType, sender, channel, text)
    sender, channel = Fold(sender), channel and Fold(Trim(channel)) or ""
    for offset = self.count - 1, 0, -1 do
        local record = self.records[Index(self, offset)]
        if record.windowId == windowId and record.eventType == eventType and record.sender == sender and
            record.channel == channel and record.text == text then return record end
    end
end
function Methods:Evaluate(windowId, eventType, sender, channel, rawBody, now)
    if not self.active then return false, false, nil end
    if not Context(self, windowId, eventType, sender, channel, now) or type(rawBody) ~= "string" or
        string.len(rawBody) > Moderation.MAX_MESSAGE_BYTES then return false, false, nil end
    local preferences = self.preferences
    local filters = (self.filterBlocked or self.filterRepeat) and Scope(preferences.filterScope, eventType) and
        Channel(self.channels, eventType, channel)
    local mentions = self.checkMentions and Scope(preferences.mentionScope, eventType) and
        Channel(self.mentionChannels, eventType, channel) and Fold(sender) ~= self.playerName
    local plain
    if filters and self.filterBlocked or mentions then plain = Fold(History.PlainText(rawBody)) end
    if filters and self.filterBlocked then
        for _, term in ipairs(self.blocked) do if Match(plain, term, false) then return true, false, nil end end
    end
    local normalized
    if filters and self.filterRepeat then
        normalized = rawBody
        if not self.lastNow or now >= self.lastNow then
            local record = Find(self, windowId, eventType, sender, channel, normalized)
            if record and now >= record.at and now - record.at < preferences.repeatSeconds then return true, false, nil end
        end
    end
    if mentions then
        for _, term in ipairs(self.mentions) do
            if Match(plain, term, preferences.mentionWholeWord) then return false, true, normalized end
        end
    end
    return false, false, normalized
end
local function Evict(self)
    local record = self.records[self.head]
    self.bytes = self.bytes - record.bytes
    for key in pairs(record) do record[key] = nil end
    self.head = math.mod(self.head, Moderation.MAX_RECORDS) + 1
    self.count = self.count - 1
end
local function Remember(self, windowId, eventType, sender, channel, text, now)
    local previous = Find(self, windowId, eventType, sender, channel, text)
    if previous then previous.at = now; return end
    sender, channel = Fold(sender), channel and Fold(Trim(channel)) or ""
    local bytes = string.len(text) + string.len(sender) + string.len(channel)
    while self.count >= Moderation.MAX_RECORDS or self.bytes + bytes > Moderation.MAX_BYTES do Evict(self) end
    local index = Index(self, self.count)
    local record = self.records[index]
    if not record then record = {}; self.records[index] = record end
    record.windowId, record.eventType, record.sender, record.channel, record.text, record.at =
        windowId, eventType, sender, channel, text, now
    record.bytes = bytes
    self.count, self.bytes = self.count + 1, self.bytes + bytes
end
function Methods:Accept(windowId, eventType, sender, channel, normalizedBody, now, mentioned)
    if not self.active or not Context(self, windowId, eventType, sender, channel, now) or
        type(mentioned) ~= "boolean" then return false end
    if self.lastNow and now < self.lastNow then self:Reset() end
    self.lastNow = now
    local preferences = self.preferences
    if self.filterRepeat and Scope(preferences.filterScope, eventType) and Channel(self.channels, eventType, channel) and
        type(normalizedBody) == "string" and string.len(normalizedBody) <= Moderation.MAX_MESSAGE_BYTES then
        Remember(self, windowId, eventType, sender, channel, normalizedBody, now)
    end
    if mentioned and self.checkMentions and preferences.mentionSound and eventType ~= "CHAT_MSG_WHISPER" and
        Scope(preferences.mentionScope, eventType) and Channel(self.mentionChannels, eventType, channel) and
        Fold(sender) ~= self.playerName and (not self.lastAlert or now - self.lastAlert >= preferences.alertCooldown) then
        self.lastAlert = now
        return true
    end
    return false
end
