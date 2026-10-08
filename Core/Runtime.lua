local Chat = BootyChat
-- Profile failures must still throw when another addon makes error a logger.
local Assert = assert
local function error(message) Assert(false, message) end
local Configuration = Chat.Services.Configuration
local Native = Chat.Modules.NativeChat
local Runtime = {}
Chat.Core.Runtime = Runtime
local state = {initialized = false, stopped = false, batchDepth = 0}
local OnNativeWindowsChanged

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
    if not called or active and result ~= true then return false, tostring(result or "Chat window events could not be registered.") end
    state.subscribed = active
    return true
end
local function AdapterFailed(reason)
    state.failure = tostring(reason)
    local ok, failure = Subscription(false)
    if not ok then state.failure = state.failure .. " Event cleanup: " .. tostring(failure) end
    Refresh()
    if state.host then state.host.Print(state.failure)
    else BootyLib.Print("BootyChat: " .. state.failure) end
end
local function Sync()
    local store, failure = Chat.Database.Ensure()
    if not store then state.failure = failure; return false, failure end
    local ok, reason
    state.applying = true
    if state.stopped or not store.enabled then ok, reason = Call(Native.Stop)
    elseif Native.GetState().active then ok, reason = Call(Native.Apply, store)
    else ok, reason = Call(Native.Start, store) end
    state.applying = false
    local subscribed, subscribeFailure = Subscription(ok and Native.GetState().active == true)
    if not subscribed then
        local restored, restoreFailure = Call(Native.Stop)
        ok, reason = false, tostring(subscribeFailure) .. (restored and "" or " Restoration: " .. tostring(restoreFailure))
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
    state.applying = false
    if not ok then
        local restored, failure = Call(Native.Stop)
        AdapterFailed(tostring(reason) .. (restored and "" or " Restoration: " .. tostring(failure)))
    end
end
function Runtime.Initialize()
    local store, failure = Chat.Database.Ensure()
    if not store then state.failure = failure; return false, failure end
    if not state.initialized then Native.SetFailureObserver(AdapterFailed) end
    state.initialized = true
    return true
end
function Runtime.OnHostReady(host)
    state.host = host
    return Runtime.Start()
end
function Runtime.IsAvailable() return state.initialized and not state.stopped end
function Runtime.GetState() return state end
function Runtime.IsBusy() return false end
function Runtime.CreateView(parent, host)
    if not state.view then state.view = Chat.Modules.Overview.Create(parent, host) end
    return state.view
end
function Runtime.Start()
    local ok, failure = Runtime.Initialize()
    if not ok then return false, failure end
    state.stopped = false
    return Sync()
end
function Runtime.Stop()
    -- Stop work first, even if a failed restoration must be retried later.
    state.stopped = true
    local ok, failure = Call(Native.Stop)
    local unsubscribed, reason = Subscription(false)
    if not unsubscribed then ok, failure = false, tostring(failure or "") .. " Event cleanup: " .. tostring(reason) end
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
    target[key] = Configuration.Copy(value)
    if state.batchDepth > 0 then state.batchDirty = true; return true end
    local ok, failure = Sync()
    if not ok then
        target[key] = previous
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
function Runtime.Open(command)
    if command == "enable" or command == "disable" then
        local ok, failure = Runtime.SetEnabled(command == "enable")
        return ok, failure
    end
    if command ~= "" and command ~= "settings" then
        local message = "Use /bc, /bc settings, /bc enable or /bc disable."
        return false, message
    end
    if not state.host and BootyLib.Core.Runtime.started then
        local ok, failure = BootyLib.Core.Runtime.Activate(Chat.Product)
        if not ok then return false, failure end
    end
    if not state.host then return false, state.failure or "BootyChat is waiting for login." end
    if command == "settings" then return state.host.OpenSettings() end
    return state.host.OpenView("chat")
end
