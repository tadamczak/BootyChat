local Chat = BootyChat
-- Profile failures must still throw when another addon makes error a logger.
local Assert = assert
local function error(message) Assert(false, message) end
local Configuration = Chat.Services.Configuration
local Native = Chat.Modules.NativeChat
local Capture = Chat.Modules.HistoryCapture
local History = Chat.Services.History
local Runtime = {}
Chat.Core.Runtime = Runtime
local state = {initialized = false, stopped = false, batchDepth = 0}
local OnNativeWindowsChanged, OnHistoryLogout

local function Call(callback, value)
    local called, result, failure = pcall(callback, value)
    if not called then return false, tostring(result) end
    if result ~= true then return false, failure or "The chat adapter declined the operation." end
    return true
end
local function Refresh()
    if state.host and state.host.ApplySettings then state.host.ApplySettings() end
    if state.view then state.view:Refresh() end
end
local function Subscription(active)
    if active == state.subscribed then return true end
    local callback = active and BootyLib.Subscribe or BootyLib.Unsubscribe
    local called, result = pcall(callback, "UPDATE_CHAT_WINDOWS", Runtime, OnNativeWindowsChanged)
    if not called or result == false or active and result ~= true then return false, tostring(result or "Chat window events could not be registered.") end
    state.subscribed = active
    return true
end
local function LogoutSubscription(active)
    if active == state.logoutSubscribed then return true end
    local callback = active and BootyLib.Subscribe or BootyLib.Unsubscribe
    local called, result = pcall(callback, "PLAYER_LOGOUT", Runtime, OnHistoryLogout)
    if not called or result == false or active and result ~= true then return false, tostring(result or "History persistence events could not be registered.") end
    state.logoutSubscribed = active
    return true
end
local function SaveHistory(store)
    if not state.history then return true end
    if Configuration.ResolveHistory(store).persist then store.historyData = state.history:Snapshot()
    else store.historyData = nil end
    return true
end
OnHistoryLogout = function()
    local store, failure = Chat.Database.Ensure()
    if not store then error(failure) end
    local ok, reason = Call(SaveHistory, store)
    if not ok then error(reason) end
end
local function HistoryFailed(reason)
    state.historyFailure = tostring(reason)
    Refresh()
    if state.host then state.host.Print("Chat history: " .. state.historyFailure)
    else BootyLib.Print("Chat history: " .. state.historyFailure) end
end
local function SetHistoryLimit(value) return state.history:SetLimit(value) end
local function AdapterFailed(reason)
    state.failure = tostring(reason)
    local captured, captureFailure = Call(Capture.Stop)
    if not captured then state.failure = state.failure .. " History cleanup: " .. tostring(captureFailure) end
    local store, storeFailure = Chat.Database.Ensure()
    if store then
        local saved, saveFailure = Call(SaveHistory, store)
        if not saved then state.failure = state.failure .. " History save: " .. tostring(saveFailure) end
    else state.failure = state.failure .. " History save: " .. tostring(storeFailure) end
    local ok, failure = Subscription(false)
    if not ok then state.failure = state.failure .. " Event cleanup: " .. tostring(failure) end
    local logoutOK, logoutFailure = LogoutSubscription(false)
    if not logoutOK then state.failure = state.failure .. " Persistence event cleanup: " .. tostring(logoutFailure) end
    Refresh()
    if state.host then state.host.Print(state.failure)
    else BootyLib.Print("BootyChat: " .. state.failure) end
end
local function Sync()
    local store, failure = Chat.Database.Ensure()
    if not store then state.failure = failure; return false, failure end
    local preferences = Configuration.ResolveHistory(store)
    local ok, reason
    state.applying = true
    if state.stopped or not store.enabled then
        local captured, captureFailure = Call(Capture.Stop)
        ok, reason = Call(Native.Stop)
        if not captured then ok, reason = false, tostring(reason or "") .. " History cleanup: " .. tostring(captureFailure) end
    elseif Native.GetState().active then ok, reason = Call(Native.Apply, store)
    else ok, reason = Call(Native.Start, store) end
    if ok then
        if state.stopped or not store.enabled or not preferences.enabled or state.historyFailure then
            ok, reason = Call(Capture.Stop)
        elseif Capture.GetState().active then ok, reason = Call(Capture.Apply, state.history)
        else ok, reason = Call(Capture.Start, state.history) end
    else
        local cleaned, cleanup = Call(Capture.Stop)
        if not cleaned then reason = tostring(reason) .. " History cleanup: " .. tostring(cleanup) end
    end
    state.applying = false
    local subscribed, subscribeFailure = Subscription(ok and Native.GetState().active == true)
    local persisted, persistFailure = LogoutSubscription(ok and not state.stopped and Capture.GetState().active == true and preferences.persist)
    if not subscribed or not persisted or not ok then
        local captured, captureFailure = Call(Capture.Stop)
        local restored, restoreFailure = Call(Native.Stop)
        ok, reason = false, tostring(reason or subscribeFailure or persistFailure) ..
            (captured and "" or " History restoration: " .. tostring(captureFailure)) ..
            (restored and "" or " Restoration: " .. tostring(restoreFailure))
        local saved, saveFailure = Call(SaveHistory, store)
        if not saved then reason = reason .. " History save: " .. tostring(saveFailure) end
        local eventsOK, eventReason = Subscription(false)
        local logoutOK, logoutReason = LogoutSubscription(false)
        if not eventsOK or not logoutOK then reason = reason .. " Event cleanup: " .. tostring(eventReason or logoutReason) end
    end
    if ok then
        local previousLimit = state.history:GetStats().limit
        ok, reason = Call(SetHistoryLimit, preferences.limit)
        if ok then
            local collecting = Capture.GetState().active == true
            if state.persist ~= preferences.persist or previousLimit ~= preferences.limit or state.collecting and not collecting then
                ok, reason = Call(SaveHistory, store)
            end
            if ok then state.persist, state.collecting = preferences.persist, collecting end
        end
    end
    state.failure = not ok and reason or nil
    Refresh()
    return ok, reason
end
OnNativeWindowsChanged = function()
    if state.stopped or state.applying or not Native.GetState().active then return end
    local store, failure = Chat.Database.Ensure()
    if not store then
        local restored, reason = Call(Native.Stop)
        AdapterFailed(tostring(failure) .. (restored and "" or " Restoration: " .. tostring(reason)))
        return
    end
    state.applying = true
    local ok, reason = Call(Native.Refresh or Native.Apply, store)
    if ok and Capture.GetState().active then ok, reason = Call(Capture.Refresh, state.history) end
    state.applying = false
    if not ok then
        local captured, captureFailure = Call(Capture.Stop)
        local restored, failure = Call(Native.Stop)
        AdapterFailed(tostring(reason) .. (captured and "" or " History restoration: " .. tostring(captureFailure)) ..
            (restored and "" or " Restoration: " .. tostring(failure)))
    end
end
function Runtime.Initialize()
    local store, failure = Chat.Database.Ensure()
    if not store then state.failure = failure; return false, failure end
    if not state.history then
        local preferences = Configuration.ResolveHistory(store)
        state.history, failure = History.New(preferences.limit, Configuration.WindowCount(), preferences.persist and store.historyData or nil)
        if not state.history then state.failure = failure; return false, failure end
    end
    if not state.initialized then
        Native.SetFailureObserver(AdapterFailed)
        Capture.SetFailureObserver(HistoryFailed)
    end
    state.initialized = true
    return true
end
function Runtime.OnHostReady(host)
    state.host = host
    return Runtime.Start()
end
function Runtime.IsAvailable() return state.initialized and not state.stopped end
function Runtime.GetState() return state end
function Runtime.GetHistory() return state.history end
function Runtime.IsBusy() return false end
function Runtime.CreateView(parent, host)
    if not state.view then state.view = Chat.Modules.Overview.Create(parent, host) end
    return state.view
end
function Runtime.Start()
    local ok, failure = Runtime.Initialize()
    if not ok then return false, failure end
    state.stopped = false
    state.historyFailure = nil
    return Sync()
end
function Runtime.Stop()
    -- Stop work first, even if a failed restoration must be retried later.
    state.stopped = true
    local captured, captureFailure = Call(Capture.Stop)
    local ok, failure = Call(Native.Stop)
    if not captured then ok, failure = false, tostring(failure or "") .. " History cleanup: " .. tostring(captureFailure) end
    local unsubscribed, reason = Subscription(false)
    if not unsubscribed then ok, failure = false, tostring(failure or "") .. " Event cleanup: " .. tostring(reason) end
    local logoutOK, logoutFailure = LogoutSubscription(false)
    if not logoutOK then ok, failure = false, tostring(failure or "") .. " Persistence event cleanup: " .. tostring(logoutFailure) end
    local store, storeFailure = Chat.Database.Ensure()
    if store then
        local saved, saveFailure = Call(SaveHistory, store)
        if not saved then ok, failure = false, tostring(failure or "") .. " History save: " .. tostring(saveFailure) end
    else ok, failure = false, tostring(failure or "") .. " History save: " .. tostring(storeFailure) end
    state.failure = not ok and failure or nil
    if state.view then state.view:Hide() end
    return ok, failure
end
function Runtime.OnActivationFailed()
    local ok, failure = Runtime.Stop()
    state.host = nil
    return ok, failure
end
function Runtime.SettingsChanged()
    if state.batchDepth > 0 then state.batchDirty = true; return true end
    return Sync()
end
function Runtime.BeginSettingsBatch() state.batchDepth = state.batchDepth + 1 end
function Runtime.EndSettingsBatch(success)
    state.batchDepth = math.max(0, state.batchDepth - 1)
    if state.batchDepth == 0 then
        local dirty = state.batchDirty
        state.batchDirty = nil
        if success ~= false and dirty then
            local ok, failure = Sync()
            if not ok then error(failure) end
        end
    end
end
function Runtime.OnSettingsProfileApplied()
    local ok, failure = Runtime.SettingsChanged()
    if not ok then error(failure) end
end
local function Commit(store, target, key, value)
    local previous = target[key]
    local previousHistory = store.historyData
    target[key] = Configuration.Copy(value)
    if state.batchDepth > 0 then state.batchDirty = true; return true end
    local ok, failure = Sync()
    if not ok then
        target[key] = previous
        store.historyData = previousHistory
        local restored, reason = Sync()
        state.failure = failure
        if not restored then failure = tostring(failure) .. " Restoration failed: " .. tostring(reason); state.failure = failure end
        Refresh()
        return false, failure
    end
    return true
end
function Runtime.SetOption(id, key, value)
    if id ~= nil and not Configuration.ValidWindow(id) then return false, "Choose a native chat window." end
    local valid, failure = Configuration.ValidateValue(key, value)
    if not valid then return false, failure end
    local store, reason = Chat.Database.Ensure()
    if not store then return false, reason end
    local target = store.defaults
    if id then
        target = store.windows[id]
        if not target then target = {}; store.windows[id] = target end
    end
    return Commit(store, target, key, value)
end
function Runtime.SetEditboxOption(key, value)
    local valid, failure = Configuration.ValidateValue(key, value, true)
    if not valid then return false, failure end
    local store, reason = Chat.Database.Ensure()
    if not store then return false, reason end
    return Commit(store, store.editbox, key, value)
end
function Runtime.SetEnabled(value)
    if type(value) ~= "boolean" then return false, "Choose enabled or disabled." end
    local store, failure = Chat.Database.Ensure()
    if not store then return false, failure end
    if value then state.historyFailure = nil end
    return Commit(store, store, "enabled", value)
end
function Runtime.SetMinimapHidden(value)
    if value ~= nil and type(value) ~= "boolean" then return false, "Choose a minimap visibility setting." end
    local store, failure = Chat.Database.Ensure()
    if not store then return false, failure end
    store.hideMinimapIcon = value
    Refresh()
    return true
end
function Runtime.ResetWindow(id)
    if not Configuration.ValidWindow(id) then return false, "Choose a native chat window." end
    local store, failure = Chat.Database.Ensure()
    if not store then return false, failure end
    return Commit(store, store.windows, id, nil)
end
function Runtime.SetWindowOverrides(value)
    local valid, failure = Configuration.ValidateWindows(value)
    if not valid then return false, failure end
    local store, reason = Chat.Database.Ensure()
    if not store then return false, reason end
    return Commit(store, store, "windows", value or {})
end
function Runtime.SetHistoryOption(key, value)
    local valid, failure = Configuration.ValidateHistoryValue(key, value)
    if not valid then return false, failure end
    local store, reason = Chat.Database.Ensure()
    if not store then return false, reason end
    state.historyFailure = nil
    return Commit(store, store.history, key, value)
end
function Runtime.ClearHistory(windowId)
    if windowId ~= nil and not Configuration.ValidWindow(windowId) then return false, "Choose a native chat window." end
    local store, failure = Chat.Database.Ensure()
    if not store or not state.history then return false, failure or "History is waiting for login." end
    local cleared, result, clearFailure = pcall(state.history.Clear, state.history, windowId)
    -- A listener can fail after the clear committed. Save the actual buffer so
    -- an opted-in reload cannot resurrect the deliberately removed messages.
    local saved, saveFailure = Call(SaveHistory, store)
    if not cleared or result ~= true or not saved then
        return false, tostring(not cleared and result or result ~= true and (clearFailure or "History clearing was declined.") or saveFailure)
    end
    Refresh()
    return true
end
function Runtime.Open(command)
    if command == "enable" or command == "disable" then
        local ok, failure = Runtime.SetEnabled(command == "enable")
        return ok, failure
    end
    if command ~= "" and command ~= "settings" and command ~= "history" then
        local message = "Use /bc, /bc settings, /bc history, /bc enable or /bc disable."
        return false, message
    end
    if not state.host and BootyLib.Core.Runtime.started then
        local ok, failure = BootyLib.Core.Runtime.Activate(Chat.Product)
        if not ok then return false, failure end
    end
    if not state.host then return false, state.failure or "BootyChat is waiting for login." end
    if command == "settings" then return state.host.OpenSettings() end
    if command == "history" then
        local view, failure = state.host.OpenView("chat")
        if not view then return false, failure end
        return view:ShowHistory()
    end
    return state.host.OpenView("chat")
end
