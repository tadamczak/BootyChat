local Chat = BootyChat
local Capture = {}
Chat.Modules.HistoryCapture = Capture
local Assert = assert
local function Raise(message) Assert(false, message) end
local Configuration = Chat.Services.Configuration
local records, history, observer = {}, nil, nil
local state = {active = false, restorationBlocked = false, deferred = 0, windows = 0, foreignChanges = 0}
local function Global(name) return type(getglobal) == "function" and getglobal(name) or _G[name] end
local function Pack(...) return arg end
local function Results(values) return unpack(values) end
local function ValidHistory(value)
    return type(value) == "table" and type(value.Append) == "function" and type(value.GetStats) == "function"
end
local function Write(owner, value) owner.AddMessage = value end
local function Release(record)
    local lease = record.lease
    if not lease then return true end
    lease.enabled = false
    local current = lease.frame.AddMessage
    if current == lease.original then record.lease = nil; return true end
    if current ~= lease.guard then
        state.foreignChanges = state.foreignChanges + 1
        record.lease = nil
        return true
    end
    local previousThis, previousEvent, previousArg = this, event, arg1
    local ok, reason = pcall(Write, lease.frame, lease.original)
    this, event, arg1 = previousThis, previousEvent, previousArg
    local after = lease.frame.AddMessage
    if ok and after == lease.original then record.lease = nil; return true end
    return false, tostring(not ok and reason or record.name .. " AddMessage restoration was declined.")
end
function Capture.Stop()
    state.active, state.deferred, state.windows = false, 0, 0
    for _, record in pairs(records) do
        if record.lease then record.lease.enabled = false end
        record.deferred = nil
    end
    local failure
    for _, record in pairs(records) do
        local previousThis, previousEvent, previousArg = this, event, arg1
        local ok, restored, reason = pcall(Release, record)
        this, event, arg1 = previousThis, previousEvent, previousArg
        if not ok or not restored then failure = failure or tostring(ok and reason or restored) end
    end
    state.restorationBlocked = failure ~= nil
    if failure then state.failure = failure; return false, failure end
    history, state.failure = nil, nil
    return true
end
local function Failed(reason)
    local restored, restoreReason = Capture.Stop()
    state.failure = tostring(reason) .. (restored and "" or " Restoration: " .. tostring(restoreReason))
    -- Guards are inactive before a diagnostic callback can print to chat.
    if observer then
        local previousThis, previousEvent, previousArg = this, event, arg1
        local ok, notification = pcall(observer, state.failure)
        this, event, arg1 = previousThis, previousEvent, previousArg
        if not ok then state.failure = state.failure .. " Notification: " .. tostring(notification) end
    end
end
local function Append(lease, values)
    if type(time) ~= "function" then Raise("Native chat history clock is unavailable.") end
    history:Append(lease.id, values[2], values[3], values[4], values[5], values[6], time())
end
local function Owned(record, lease)
    if not lease.enabled or not state.active then return false end
    if lease.frame.AddMessage == lease.guard then return true end
    lease.enabled = false
    if record.lease == lease then
        record.lease, record.deferred = nil, true
        state.deferred = state.deferred + 1
        state.foreignChanges = state.foreignChanges + 1
    end
    return false
end
local function Commit(record, lease, values)
    if Owned(record, lease) then Append(lease, values) end
end
local function After(record, lease, values, result)
    -- Native/foreign callback effects and errors remain authoritative. Only
    -- our own capture work borrows the context left by the original callback.
    local previousThis, previousEvent, previousArg = this, event, arg1
    local ok, reason = pcall(Commit, record, lease, values)
    this, event, arg1 = previousThis, previousEvent, previousArg
    if not ok then
        local reported = pcall(Failed, reason)
        if not reported then state.failure = "Chat history capture failed while reporting its error." end
    end
    this, event, arg1 = previousThis, previousEvent, previousArg
    return Results(result)
end
local function Install(record, frame, id)
    if record.frame and record.frame ~= frame then Raise(record.name .. " history frame was replaced.") end
    record.frame = frame
    local current = frame.AddMessage
    local lease = record.lease
    if lease and current ~= lease.guard then
        lease.enabled = false
        record.lease, record.deferred = nil, true
        state.deferred = state.deferred + 1
        state.foreignChanges = state.foreignChanges + 1
    end
    if record.deferred then return end
    if type(current) ~= "function" then Raise(record.name .. " AddMessage is unavailable.") end
    if not record.lease then
        lease = {frame = frame, id = id, original = current, enabled = false}
        record.lease = lease
        lease.guard = function(...)
            local values = arg
            -- Disabled retained guards remain transparent even when a later
            -- wrapper has captured them; their original never changes.
            if values[1] ~= lease.frame or not lease.enabled or not state.active then
                return lease.original(unpack(values))
            end
            return After(record, lease, values, Pack(lease.original(unpack(values))))
        end
        Write(frame, lease.guard)
        if frame.AddMessage ~= lease.guard then Raise(record.name .. " history capture was declined.") end
    end
    record.lease.enabled = true
    state.windows = state.windows + 1
end
function Capture.Apply(value)
    if not ValidHistory(value) then return false, "A history service is required for capture." end
    if not state.active then return false, "Chat history capture is not active." end
    history, state.windows = value, 0
    local previousThis, previousEvent, previousArg = this, event, arg1
    local ok, reason = pcall(function()
        for id = 1, Configuration.WindowCount() do
            local name = "ChatFrame" .. id
            local frame = Global(name)
            if frame then
                local record = records[id]
                if not record then record = {name = name}; records[id] = record end
                Install(record, frame, id)
            elseif id == 1 then Raise("Native ChatFrame1 is unavailable for history capture.") end
        end
    end)
    this, event, arg1 = previousThis, previousEvent, previousArg
    if ok then state.failure = nil; return true end
    local restored, restoreReason = Capture.Stop()
    state.failure = tostring(reason) .. (restored and "" or " Restoration: " .. tostring(restoreReason))
    return false, state.failure
end
function Capture.Refresh(value) return Capture.Apply(value) end
function Capture.Start(value)
    if not ValidHistory(value) then return false, "A history service is required for capture." end
    if state.restorationBlocked then
        local ok, failure = Capture.Stop()
        if not ok then return false, failure end
    end
    state.active = true
    return Capture.Apply(value)
end
function Capture.GetState() return state end
function Capture.SetFailureObserver(callback) observer = type(callback) == "function" and callback or nil end
