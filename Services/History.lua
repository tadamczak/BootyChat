local History = {}
BootyChat.Services.History = History
local Assert = assert
local function Raise(message) Assert(false, message) end
History.MAX_RECORDS = 2000
History.MAX_BYTES = 262144
History.MAX_MESSAGE_BYTES = 4096
History.PAGE_SIZE = 12
History.MAX_QUERY_BYTES = 256
local MAX_ID, MAX_SCALAR = 9007199254740991, 4294967295
local Methods = {}

local function Finite(value)
    return type(value) == "number" and value == value and value - value == 0
end
local function Integer(value, minimum, maximum)
    return Finite(value) and value == math.floor(value) and value >= minimum and value <= maximum
end
local function Window(value, count) return Integer(value, 1, count) end
local function Color(value) return Finite(value) and value >= 0 and value <= 1 end
local function Plain(value) return type(value) == "table" and getmetatable(value) == nil end
local recordKeys = {id = true, windowId = true, text = true, r = true, g = true, b = true, colorId = true, at = true}
local function ValidRecord(record, count)
    if not Plain(record) then return false end
    for key in pairs(record) do if not recordKeys[key] then return false end end
    return Integer(record.id, 1, MAX_ID) and Window(record.windowId, count) and
        type(record.text) == "string" and string.len(record.text) <= History.MAX_MESSAGE_BYTES and
        Color(record.r) and Color(record.g) and Color(record.b) and
        (record.colorId == nil or Integer(record.colorId, 0, MAX_SCALAR)) and
        Finite(record.at) and record.at >= 0 and record.at <= MAX_SCALAR
end
local function Copy(record)
    return {id = record.id, windowId = record.windowId, text = record.text,
        r = record.r, g = record.g, b = record.b, colorId = record.colorId, at = record.at}
end
function History.ValidateSnapshot(bank, count)
    if not Integer(count, 1, 32) then return false, "Invalid history window count." end
    if bank == nil then return true end
    if not Plain(bank) or bank.version ~= 1 or not Plain(bank.records) then
        return false, "Unsupported or invalid chat history snapshot. Preserve the saved data before repairing it."
    end
    for key in pairs(bank) do if key ~= "version" and key ~= "records" then return false, "Invalid history snapshot field." end end
    local length, maximum = 0, 0
    for key in pairs(bank.records) do
        if not Integer(key, 1, History.MAX_RECORDS) then return false, "Invalid history record index." end
        length = length + 1
        if key > maximum then maximum = key end
    end
    if maximum ~= length then return false, "History records must be a dense ordered list." end
    local previous, bytes = 0, 0
    for index = 1, length do
        local record = bank.records[index]
        if not ValidRecord(record, count) or record.id <= previous then return false, "Invalid or unordered history record." end
        previous, bytes = record.id, bytes + string.len(record.text)
        if bytes > History.MAX_BYTES then return false, "Saved history exceeds its text byte limit." end
    end
    return true
end
local function Index(instance, offset)
    return math.mod(instance.head + offset - 1, instance.limit) + 1
end
local function Empty(record)
    for key in pairs(record) do record[key] = nil end
end
local function Evict(instance)
    local record = instance.slots[instance.head]
    instance.bytes = instance.bytes - string.len(record.text)
    instance.byId[record.id] = nil
    Empty(record)
    instance.head = math.mod(instance.head, instance.limit) + 1
    instance.count = instance.count - 1
end
local function Notify(instance)
    for owner, callback in pairs(instance.listeners) do
        local previousThis, previousEvent, previousArg = this, event, arg1
        local ok, reason = pcall(callback, owner)
        this, event, arg1 = previousThis, previousEvent, previousArg
        if not ok then Raise(tostring(reason)) end
    end
end
local function Rebuild(instance, survivors, limit)
    local slots, used = {}, {}
    local length = table.getn(survivors)
    local first = math.max(1, length - limit + 1)
    instance.byId, instance.bytes, instance.count = {}, 0, 0
    for index = first, length do
        local record = survivors[index]
        instance.count = instance.count + 1
        slots[instance.count], used[record] = record, true
        instance.byId[record.id] = record
        instance.bytes = instance.bytes + string.len(record.text)
    end
    local retained = instance.count
    for _, record in pairs(instance.slots) do
        if not used[record] then
            Empty(record)
            if retained < limit then retained = retained + 1; slots[retained] = record end
        end
    end
    instance.slots, instance.head, instance.limit = slots, 1, limit
end
function History.New(limit, count, bank)
    if not Integer(limit, 1, History.MAX_RECORDS) then return nil, "History limit must be a whole number from 1 to 2000." end
    local valid, failure = History.ValidateSnapshot(bank, count)
    if not valid then return nil, failure end
    local instance = {limit = limit, windowCount = count, slots = {}, byId = {}, listeners = {},
        head = 1, count = 0, bytes = 0, skipped = 0, nextId = 1}
    setmetatable(instance, {__index = Methods})
    if bank then
        local length = table.getn(bank.records)
        if length > 0 then instance.nextId = bank.records[length].id + 1 end
        for index = math.max(1, length - limit + 1), length do
            local record = Copy(bank.records[index])
            instance.count = instance.count + 1
            instance.slots[instance.count], instance.byId[record.id] = record, record
            instance.bytes = instance.bytes + string.len(record.text)
        end
    end
    return instance
end
function Methods:Append(windowId, text, r, g, b, colorId, at)
    r, g, b = r == nil and 1 or r, g == nil and 1 or g, b == nil and 1 or b
    if not Window(windowId, self.windowCount) or type(text) ~= "string" or string.len(text) > History.MAX_MESSAGE_BYTES or
        not Color(r) or not Color(g) or not Color(b) or
        colorId ~= nil and not Integer(colorId, 0, MAX_SCALAR) or
        not Finite(at) or at < 0 or at > MAX_SCALAR or not Integer(self.nextId, 1, MAX_ID) then
        self.skipped = self.skipped + 1
        return false, "History skipped invalid or oversized message arguments."
    end
    local bytes = string.len(text)
    while self.count >= self.limit or self.bytes + bytes > History.MAX_BYTES do Evict(self) end
    local index = Index(self, self.count)
    local record = self.slots[index]
    if not record then record = {}; self.slots[index] = record end
    record.id, record.windowId, record.text = self.nextId, windowId, text
    record.r, record.g, record.b, record.colorId, record.at = r, g, b, colorId, at
    self.nextId, self.count, self.bytes = self.nextId + 1, self.count + 1, self.bytes + bytes
    self.byId[record.id] = record
    Notify(self)
    return true
end
function Methods:SetLimit(limit)
    if not Integer(limit, 1, History.MAX_RECORDS) then return false, "History limit must be a whole number from 1 to 2000." end
    if limit == self.limit then return true end
    -- A preference transaction may fail in its listener. Build the proposed
    -- low-frequency resize without clearing any record from the old buffer.
    local oldSlots, oldById, oldHead = self.slots, self.byId, self.head
    local oldCount, oldBytes, oldLimit = self.count, self.bytes, self.limit
    local slots, byId, count, bytes = {}, {}, 0, 0
    for index = math.max(0, oldCount - limit), oldCount - 1 do
        local record = Copy(oldSlots[Index(self, index)])
        count, bytes = count + 1, bytes + string.len(record.text)
        slots[count], byId[record.id] = record, record
    end
    self.slots, self.byId, self.head = slots, byId, 1
    self.count, self.bytes, self.limit = count, bytes, limit
    local ok, reason = pcall(Notify, self)
    if not ok then
        self.slots, self.byId, self.head = oldSlots, oldById, oldHead
        self.count, self.bytes, self.limit = oldCount, oldBytes, oldLimit
        Raise(tostring(reason))
    end
    return true
end
function Methods:Get(id)
    local record = self.byId[id]
    return record and Copy(record) or nil
end
function Methods:GetStats() return {count = self.count, bytes = self.bytes, skipped = self.skipped, limit = self.limit} end
function Methods:Clear(windowId)
    if windowId ~= nil and not Window(windowId, self.windowCount) then return false, "Invalid history window." end
    local ordered = {}
    for index = 0, self.count - 1 do
        local record = self.slots[Index(self, index)]
        if windowId ~= nil and record.windowId ~= windowId then table.insert(ordered, record) end
    end
    local changed = table.getn(ordered) ~= self.count or windowId == nil and self.skipped > 0
    if not changed then return true end
    Rebuild(self, ordered, self.limit)
    if windowId == nil then self.skipped = 0 end
    Notify(self)
    return true
end
function Methods:Snapshot()
    local records = {}
    for index = 0, self.count - 1 do records[index + 1] = Copy(self.slots[Index(self, index)]) end
    return {version = 1, records = records}
end
function Methods:Subscribe(owner, callback)
    if owner == nil or type(callback) ~= "function" then return false, "History subscriptions need an owner and callback." end
    self.listeners[owner] = callback
    return true
end
function Methods:Unsubscribe(owner)
    if owner ~= nil then self.listeners[owner] = nil end
    return true
end
local function Token(text, token, start)
    local position = string.find(text, token, start, true)
    while position do
        local before, pipes = position - 1, 0
        while before > 0 and string.sub(text, before, before) == "|" do pipes = pipes + 1; before = before - 1 end
        if math.mod(pipes, 2) == 0 then return position end
        position = string.find(text, token, position + 2, true)
    end
end
function History.PlainText(text)
    if type(text) ~= "string" then return nil, "Plain history text must be a string." end
    local result, closes = {}, {}
    local index, first, length = 1, 1, string.len(text)
    while index <= length do
        local skip, literal
        if string.sub(text, index, index) == "|" then
            local marker = string.sub(text, index + 1, index + 1)
            if marker == "|" then skip, literal = index + 2, "|"
            elseif marker == "c" and string.find(string.sub(text, index + 2, index + 9), "^%x%x%x%x%x%x%x%x$") then skip = index + 10
            elseif marker == "r" then skip = index + 2
            elseif marker == "H" then
                local header = Token(text, "|h", index + 2)
                local close = header and Token(text, "|h", header + 2)
                if close then closes[close] = true; skip = header + 2 end
            elseif marker == "h" and closes[index] then skip = index + 2
            elseif marker == "T" then
                local close = Token(text, "|t", index + 2)
                if close then skip = close + 2 end
            end
        end
        if skip then
            if first < index then table.insert(result, string.sub(text, first, index - 1)) end
            if literal then table.insert(result, literal) end
            index, first = skip, skip
        else index = index + 1 end
    end
    if first <= length then table.insert(result, string.sub(text, first)) end
    return table.concat(result)
end
local function LowerByte(value) return string.char(string.byte(value) + 32) end
local function LowerASCII(value) return string.gsub(value, "[A-Z]", LowerByte) end
function Methods:Query(windowId, needle, offset, limit)
    if needle == nil then needle = "" end
    if offset == nil then offset = 0 end
    if limit == nil then limit = History.PAGE_SIZE end
    if windowId ~= nil and not Window(windowId, self.windowCount) or type(needle) ~= "string" or
        string.len(needle) > History.MAX_QUERY_BYTES or not Integer(offset, 0, MAX_ID) or
        not Integer(limit, 1, History.PAGE_SIZE) then return nil, "Invalid history search or page arguments." end
    local matches, total = {}, 0
    local query = LowerASCII(needle)
    for index = self.count - 1, 0, -1 do
        local record = self.slots[Index(self, index)]
        if (windowId == nil or record.windowId == windowId) and
            (query == "" or string.find(LowerASCII(History.PlainText(record.text)), query, 1, true)) then
            total = total + 1
            matches[total] = record
        end
    end
    if total == 0 then offset = 0
    elseif offset >= total then offset = math.floor((total - 1) / limit) * limit end
    local records = {}
    for index = offset + 1, math.min(total, offset + limit) do records[table.getn(records) + 1] = Copy(matches[index]) end
    return {records = records, total = total, offset = offset}
end
function History.FormatTime(at)
    if not Finite(at) or at < 0 or at > MAX_SCALAR then return nil, "Invalid history timestamp." end
    if type(date) == "function" then
        local ok, value = pcall(date, "%H:%M:%S", math.floor(at))
        if ok and type(value) == "string" and string.find(value, "^%d%d:%d%d:%d%d$") then return value end
    end
    local seconds = math.mod(math.floor(at), 86400)
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(math.mod(seconds, 3600) / 60), math.mod(seconds, 60))
end
function History.BuildCopy(records)
    if not Plain(records) then return nil, "History copy needs a plain record list." end
    local count, maximum = 0, 0
    for key in pairs(records) do
        if not Integer(key, 1, History.PAGE_SIZE) then return nil, "Copy at most twelve history messages at a time." end
        count = count + 1; if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, "History copy records must be a dense list." end
    local lines = {}
    for index = 1, count do
        local record = records[index]
        if not ValidRecord(record, 32) then return nil, "Invalid history record for copying." end
        lines[index] = "[" .. History.FormatTime(record.at) .. "] [Window " .. record.windowId .. "] " .. History.PlainText(record.text)
    end
    return table.concat(lines, "\n")
end
