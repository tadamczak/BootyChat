local Chat = BootyChat
local Native = {}
Chat.Modules.NativeChat = Native
local Configuration = Chat.Services.Configuration
local UI = (Chat.UI or BootyLib.UI).Components
local records, editRecord = {}, nil
local state = {active = false, restorationBlocked = false, windows = 0, foreignChanges = 0}
local store, failureObserver
local competingOwners = {"pfUI", "Prat", "Chatter"}
local fonts = {friz = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF", skurri = "Fonts\\SKURRI.TTF"}
local textureNames = {"Background", "ResizeTopLeftTexture", "ResizeTopRightTexture",
    "ResizeBottomLeftTexture", "ResizeBottomRightTexture", "ResizeTopTexture",
    "ResizeBottomTexture", "ResizeLeftTexture", "ResizeRightTexture"}

local function Global(name) return type(getglobal) == "function" and getglobal(name) or _G[name] end
local function Enabled(value) return value ~= nil and value ~= false and value ~= 0 end
local function CompetingOwner()
    for _, name in ipairs(competingOwners) do
        if Enabled(Global(name)) or type(IsAddOnLoaded) == "function" and Enabled(IsAddOnLoaded(name)) then
            return "Disable " .. name .. " chat ownership before enabling BootyChat."
        end
    end
end
local function Call(callback, owner, a, b, c, d, e)
    local previousThis, previousEvent, previousArg = this, event, arg1
    local ok, first, second, third, fourth, fifth = pcall(callback, owner, a, b, c, d, e)
    this, event, arg1 = previousThis, previousEvent, previousArg
    return ok, first, second, third, fourth, fifth
end
local function Equal(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) == "table" then
        -- Native frame references are identities, including clients/doubles
        -- that expose them as tables with cyclic parent/child relationships.
        if type(a.GetName) == "function" or type(b.GetName) == "function" then return false end
        for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end
    if type(a) == "number" then return math.abs(a - b) < 0.00001 end
    return a == b
end
local function ReadFont(frame)
    local path, size, flags = frame:GetFont()
    return {path, size, flags or ""}
end
local function SetFont(frame, value) return frame:SetFont(value[1], value[2], value[3]) end
local function ReadWidth(frame) return frame:GetWidth() end
local function SetWidth(frame, value) return frame:SetWidth(value) end
local function ReadHeight(frame) return frame:GetHeight() end
local function SetHeight(frame, value) return frame:SetHeight(value) end
-- Both getter/setter pairs are present in the 1.12.1 engine method tables:
-- ClassicAPI/docs/BlizzardScriptAPI.md (Frame and EditBox), not Classic APIs.
local function ReadWheel(frame) return Enabled(frame:IsMouseWheelEnabled()) end
local function SetWheel(frame, value) return frame:EnableMouseWheel(value and 1 or nil) end
local function ReadArrows(frame) return Enabled(frame:GetAltArrowKeyMode()) end
local function SetArrows(frame, value) return frame:SetAltArrowKeyMode(value and 1 or nil) end
local function ReadPoints(frame)
    local result = {}
    for index = 1, frame:GetNumPoints() do
        local point, relative, relativePoint, x, y = frame:GetPoint(index)
        result[index] = {point, relative, relativePoint, x, y}
    end
    return result
end
local function SetPoints(frame, points)
    if frame:ClearAllPoints() == false then return false end
    for index = 1, table.getn(points) do
        local point = points[index]
        if frame:SetPoint(point[1], point[2], point[3], point[4], point[5]) == false then return false end
    end
end
local function Require(frame, methods, name)
    for _, method in ipairs(methods) do
        if type(frame[method]) ~= "function" then error(name .. " lacks " .. method .. ".") end
    end
end
local function Must(callback, owner, a, b, c, d, e)
    local ok, result = Call(callback, owner, a, b, c, d, e)
    if not ok then error(tostring(result)) end
    if result == false then error("A native chat write was declined.") end
    return result
end
local function ReleaseProperty(record, key)
    local lease = record.leases[key]
    if not lease then return true end
    local ok, current = Call(lease.read, record.frame)
    if not ok then return false, tostring(current) end
    if Equal(current, lease.original) then record.leases[key] = nil; return true end
    if not Equal(current, lease.applied) then
        -- A later owner changed this value. Its state is authoritative.
        state.foreignChanges = state.foreignChanges + 1
        record.leases[key] = nil
        return true
    end
    local written, failure = Call(lease.write, record.frame, lease.original)
    local inspected, actual = Call(lease.read, record.frame)
    if written and failure ~= false and inspected and Equal(actual, lease.original) then
        record.leases[key] = nil
        return true
    end
    return false, tostring(not written and failure or not inspected and actual or
        record.name .. " " .. key .. " restoration was declined.")
end
local function Property(record, key, read, write, desired)
    if desired == nil then
        local restored, reason = ReleaseProperty(record, key)
        if not restored then error(reason) end
        return
    end
    local lease = record.leases[key]
    local inspected, actual = Call(read, record.frame)
    if not inspected then error(tostring(actual)) end
    if lease and not Equal(actual, lease.applied) then
        error(record.name .. " " .. key .. " has another owner.")
    end
    if not lease then
        lease = {read = read, write = write, original = actual}
        record.leases[key] = lease
    end
    if lease.applied and Equal(actual, desired) then return end
    lease.applied = desired
    local written, failure = Call(write, record.frame, desired)
    local inspected, after = Call(read, record.frame)
    -- A setter may mutate and then fail. Retain its actual partial write so
    -- rollback can distinguish our change from a subsequent foreign change.
    if inspected then lease.applied = after end
    if not written then error(tostring(failure)) end
    if failure == false or not inspected or not Equal(after, desired) then
        error(not inspected and tostring(after) or record.name .. " " .. key .. " write was declined.")
    end
end
local function ReleaseSlot(owner, key, original, guard, script)
    local current = script and owner:GetScript(key) or owner[key]
    if current == original then return true end
    if current ~= guard then state.foreignChanges = state.foreignChanges + 1; return true end
    if script then
        local ok, reason = Call(owner.SetScript, owner, key, original)
        if not ok then return false, tostring(reason) end
        if reason == false or owner:GetScript(key) ~= original then return false, key .. " restoration was declined." end
    else owner[key] = original end
    return true
end
local function ReportFailure(reason)
    local original = tostring(reason)
    local restored, restoreReason = Native.Stop()
    state.failure = original .. (restored and "" or " Restoration: " .. tostring(restoreReason))
    if failureObserver then
        local notified, notifyReason = Call(failureObserver, state.failure)
        if not notified then state.failure = state.failure .. " Notification: " .. tostring(notifyReason) end
    end
    error(state.failure)
end
local function Texture(record, name, hidden)
    local lease = record.textures[name]
    if not hidden then return end
    local texture = Global(record.name .. name)
    if not texture then return end
    if lease and lease.texture ~= texture then error(record.name .. name .. " was replaced.") end
    if not lease then
        Require(texture, {"GetAlpha", "SetAlpha"}, record.name .. name)
        lease = {texture = texture, setter = texture.SetAlpha, nativeAlpha = texture:GetAlpha()}
        record.textures[name] = lease
        lease.guard = function(owner, alpha)
            if not lease.enabled or owner ~= lease.texture then return lease.setter(owner, alpha) end
            lease.nativeAlpha = alpha
            local ok, result = Call(lease.setter, owner, 0)
            if not ok or result == false then ReportFailure(ok and "Native chat texture hiding was declined." or result) end
            return result
        end
        lease.enabled = true
        texture.SetAlpha = lease.guard
    elseif texture.SetAlpha ~= lease.guard then error(record.name .. name .. " alpha has another owner.") end
    lease.enabled = true
    Must(lease.setter, texture, 0)
    if texture:GetAlpha() ~= 0 then error("Native chat texture hiding was declined.") end
end
local function ReleaseTexture(record, name)
    local lease = record.textures[name]
    if not lease then return true end
    lease.enabled = false
    local current = lease.texture:GetAlpha()
    local ok, reason = true, nil
    if lease.texture.SetAlpha == lease.guard and current == 0 and current ~= lease.nativeAlpha then
        ok, reason = Call(lease.setter, lease.texture, lease.nativeAlpha)
        if ok and reason ~= false and not Equal(lease.texture:GetAlpha(), lease.nativeAlpha) then ok, reason = false, "Native chat texture restoration was declined." end
        if reason == false then ok, reason = false, "Native chat texture restoration was declined." end
    elseif current ~= lease.nativeAlpha then state.foreignChanges = state.foreignChanges + 1 end
    local released, slotReason = ReleaseSlot(lease.texture, "SetAlpha", lease.setter, lease.guard)
    if ok and released then record.textures[name] = nil; return true end
    return false, tostring(not ok and reason or slotReason)
end
local function Button(record, name)
    local button = Global(name)
    if not button then return end
    local lease = record.buttons[name]
    if lease and lease.frame ~= button then error(name .. " was replaced.") end
    if not lease then
        Require(button, {"Show", "Hide", "IsShown"}, name)
        lease = {frame = button, show = button.Show, hide = button.Hide, nativeShown = Enabled(button:IsShown())}
        record.buttons[name] = lease
        lease.showGuard = function(owner)
            if not lease.enabled or owner ~= lease.frame then return lease.show(owner) end
            lease.nativeShown = true
            local ok, reason = Call(lease.hide, owner)
            if not ok or reason == false then ReportFailure(ok and "Native chat button hiding was declined." or reason) end
            return reason
        end
        lease.hideGuard = function(owner)
            if lease.enabled and owner == lease.frame then
                lease.nativeShown = false
                local ok, reason = Call(lease.hide, owner)
                if not ok or reason == false then ReportFailure(ok and "Native chat button hiding was declined." or reason) end
                return reason
            end
            return lease.hide(owner)
        end
        button.Show, button.Hide = lease.showGuard, lease.hideGuard
    elseif button.Show ~= lease.showGuard or button.Hide ~= lease.hideGuard then error(name .. " visibility has another owner.") end
    lease.enabled = true
    Must(lease.hide, button)
    if Enabled(button:IsShown()) then error(name .. " hiding was declined.") end
end
local function ReleaseButton(record, name)
    local lease = record.buttons[name]
    if not lease then return true end
    lease.enabled = false
    local ok, reason = true, nil
    if lease.frame.Show == lease.showGuard and lease.frame.Hide == lease.hideGuard and
        not Enabled(lease.frame:IsShown()) and lease.nativeShown then
        ok, reason = Call(lease.show, lease.frame)
        if ok and reason ~= false and not Enabled(lease.frame:IsShown()) then ok, reason = false, name .. " visibility restoration was declined." end
        if reason == false then ok, reason = false, name .. " visibility restoration was declined." end
    end
    local showOK, showReason = ReleaseSlot(lease.frame, "Show", lease.show, lease.showGuard)
    local hideOK, hideReason = ReleaseSlot(lease.frame, "Hide", lease.hide, lease.hideGuard)
    if ok and showOK and hideOK then record.buttons[name] = nil; return true end
    return false, tostring(not ok and reason or not showOK and showReason or hideReason)
end
local function NewRecord(frame, name, fontOnly)
    Require(frame, fontOnly and {"GetFont", "SetFont"} or {"GetFont", "SetFont", "GetScript", "SetScript"}, name)
    return {frame = frame, name = name, leases = {}, textures = {}, buttons = {}}
end
local function Wheel(record, options)
    if not options.wheel then
        if record.wheel then
            record.wheel.enabled = false
            local restored, reason = ReleaseSlot(record.frame, "OnMouseWheel", record.wheel.original, record.wheel.guard, true)
            if not restored then error(reason) end
            record.wheel = nil
        end
        Property(record, "wheel", ReadWheel, SetWheel, nil)
        return
    end
    Require(record.frame, {"IsMouseWheelEnabled", "EnableMouseWheel", "ScrollUp", "ScrollDown", "ScrollToTop", "ScrollToBottom"}, record.name)
    local lease = record.wheel
    if not lease then
        lease = {original = record.frame:GetScript("OnMouseWheel")}
        record.wheel = lease
        lease.guard = function()
            if not lease.enabled then if lease.original then return lease.original() end; return end
            local direction = tonumber(arg1) or 0
            if direction == 0 then return end
            local frame, count = record.frame, lease.speed
            local callback = direction > 0 and frame.ScrollUp or frame.ScrollDown
            if lease.shift and type(IsShiftKeyDown) == "function" and Enabled(IsShiftKeyDown()) then
                callback = direction > 0 and frame.ScrollToTop or frame.ScrollToBottom
                local ok, reason = Call(callback, frame)
                if not ok or reason == false then ReportFailure(ok and "Native chat scrolling was declined." or reason) end
                return
            end
            if lease.original then
                local ok, reason = Call(lease.original)
                if not ok then ReportFailure(reason) end
                count = count - 1
            end
            for index = 1, count do
                local ok, reason = Call(callback, frame)
                if not ok or reason == false then ReportFailure(ok and "Native chat scrolling was declined." or reason) end
            end
        end
        Must(record.frame.SetScript, record.frame, "OnMouseWheel", lease.guard)
        if record.frame:GetScript("OnMouseWheel") ~= lease.guard then error("Native mousewheel script was declined.") end
    elseif record.frame:GetScript("OnMouseWheel") ~= lease.guard then error(record.name .. " mousewheel has another owner.") end
    lease.speed, lease.shift, lease.enabled = options.wheelSpeed, options.shiftScroll, true
    Property(record, "wheel", ReadWheel, SetWheel, true)
end
local function Appearance(record, options)
    local custom = options.goldBorder or options.backgroundAlpha >= 0
    if custom then
        if not record.surface then
            if not UI.Window or type(UI.Window.ApplyProjectSurface) ~= "function" then error("BootyLib project window surface is unavailable.") end
            record.surface = UI.CreateContainer(nil, record.frame)
            record.surface:EnableMouse(false)
            record.surface:SetFrameStrata(record.frame:GetFrameStrata())
            record.surface:SetFrameLevel(math.max(0, record.frame:GetFrameLevel() - 1))
            record.surface:SetPoint("TOPLEFT", record.frame, "TOPLEFT", -4, 4)
            record.surface:SetPoint("BOTTOMRIGHT", record.frame, "BOTTOMRIGHT", 4, -4)
        end
        UI.Window.ApplyProjectSurface(record.surface)
        local color = options.backgroundColor
        Must(record.surface.SetBackdropColor, record.surface, color[1], color[2], color[3], math.max(0, options.backgroundAlpha))
        if not options.goldBorder then Must(record.surface.SetBackdropBorderColor, record.surface, 0, 0, 0, 0) end
        Must(record.surface.Show, record.surface)
    elseif record.surface then Must(record.surface.Hide, record.surface) end
    for _, name in ipairs(textureNames) do
        if custom and (name ~= "Background" or options.backgroundAlpha >= 0) then Texture(record, name, true)
        else
            local restored, reason = ReleaseTexture(record, name)
            if not restored then error(reason) end
        end
    end
end
local function ReadTabGeometry(layout)
    local value = {}
    for key, region in pairs(layout.parts) do value[key] = region:GetWidth() end
    return value
end
local function WriteTabGeometry(layout, value)
    if value == layout.desired then
        -- Reuse Blizzard's tab geometry owner (1.12 UIPanelTemplates.lua).
        -- An absolute measured width avoids stale/clipped GetWidth captions.
        return PanelTemplates_TabResize(10, layout.parts.tab, value.tab)
    end
    for key, region in pairs(layout.parts) do
        if region:SetWidth(value[key]) == false then return false end
    end
end
local function FitTab(record, tab, label)
    Require(label, {"GetStringWidth", "GetWidth", "SetWidth"}, record.name .. "TabText")
    local left = Global(record.name .. "TabLeft")
    if not left or type(left.GetWidth) ~= "function" or type(PanelTemplates_TabResize) ~= "function" then
        error("Native chat tab sizing is unavailable.")
    end
    if not record.tabLayout then
        local layout = {parts = {tab = tab, text = label}}
        for key, suffix in pairs({middle = "Middle", middleDisabled = "MiddleDisabled", highlight = "HighlightTexture"}) do
            local region = Global(record.name .. "Tab" .. suffix)
            if region then Require(region, {"GetWidth", "SetWidth"}, record.name .. "Tab" .. suffix); layout.parts[key] = region end
        end
        Require(tab, {"GetWidth", "SetWidth"}, record.name .. "Tab")
        record.tabLayout = {frame = layout, name = record.name .. "Tab", leases = {}, textures = {}, buttons = {}}
    end
    local layout = record.tabLayout.frame
    local middle = math.max(1, label:GetStringWidth() + 10)
    local width = middle + 2 * left:GetWidth()
    local desired = {tab = width, text = middle}
    for key in pairs(layout.parts) do
        if key ~= "tab" and key ~= "text" then desired[key] = key == "highlight" and width or middle end
    end
    layout.desired = desired
    Property(record.tabLayout, "geometry", ReadTabGeometry, WriteTabGeometry, desired)
end
local function ApplyWindow(record, options)
    local original = record.leases.font and record.leases.font.original or ReadFont(record.frame)
    local font, size, outline = options.font == "native" and original[1] or fonts[options.font],
        options.fontSize == 0 and original[2] or options.fontSize,
        options.fontOutline == "native" and original[3] or options.fontOutline == "none" and "" or options.fontOutline
    Property(record, "font", ReadFont, SetFont, {font, size, outline})
    local tab = Global(record.name .. "Tab")
    if tab then
        if record.tab and record.tab ~= tab then error(record.name .. " tab was replaced.") end
        record.tab = tab
        local label = Global(record.name .. "TabText") or type(tab.GetFontString) == "function" and tab:GetFontString()
        if label then
            if not record.tabText then record.tabText = NewRecord(label, record.name .. "TabText", true) end
            if record.tabText.frame ~= label then error(record.name .. " tab text was replaced.") end
            local native = record.tabText.leases.font and record.tabText.leases.font.original or ReadFont(label)
            Property(record.tabText, "font", ReadFont, SetFont,
                {options.font == "native" and native[1] or font, options.fontSize == 0 and native[2] or size,
                    options.fontOutline == "native" and native[3] or outline})
            if Enabled(record.frame.isDocked) then
                -- Native FCF_DockUpdate fits and caps docked tabs on every
                -- selection/resize. Preserve that single geometry owner.
                state.dockDirty = true
                if record.tabLayout then
                    local restored, reason = ReleaseProperty(record.tabLayout, "geometry")
                    if not restored then error(reason) end
                end
            else FitTab(record, tab, label) end
        end
        if tab.openBorder and tab.openBorder ~= record.tabBorder then
            if options.goldBorder then error(record.name .. " tab border has another owner.") end
        elseif options.goldBorder then
            if record.tabBorder and not tab.openBorder then tab.openBorder = record.tabBorder end
            local applied, failure = Call(UI.SetOpenButtonBorder, tab, true, "bottom")
            if tab.openBorder then record.tabBorder = tab.openBorder end
            if not applied then error(tostring(failure)) end
            if failure == false or not record.tabBorder then error("Project chat tab border was declined.") end
            if not Enabled(record.tabBorder:IsShown()) then error("Project chat tab border visibility was declined.") end
        elseif record.tabBorder then Must(record.tabBorder.Hide, record.tabBorder) end
    end
    -- FCF_DockUpdate anchors secondary docked frames to DEFAULT_CHAT_FRAME.
    -- Keep their preferences durable, but let that native owner set geometry.
    local geometryOwner = not Enabled(record.frame.isDocked) or record.frame == Global("DEFAULT_CHAT_FRAME")
    if geometryOwner and options.width > 0 then Require(record.frame, {"GetWidth", "SetWidth"}, record.name) end
    if geometryOwner and options.height > 0 then Require(record.frame, {"GetHeight", "SetHeight"}, record.name) end
    Property(record, "width", ReadWidth, SetWidth, geometryOwner and options.width > 0 and options.width or nil)
    Property(record, "height", ReadHeight, SetHeight, geometryOwner and options.height > 0 and options.height or nil)
    Appearance(record, options)
    Wheel(record, options)
    if options.hideButtons then
        for _, suffix in ipairs({"UpButton", "DownButton", "BottomButton"}) do Button(record, record.name .. suffix) end
        if record.name == "ChatFrame1" then Button(record, "ChatFrameMenuButton") end
    else
        for name in pairs(record.buttons) do
            local restored, reason = ReleaseButton(record, name)
            if not restored then error(reason) end
        end
    end
end
local function ApplyEditbox(options)
    local frame = Global("ChatFrameEditBox")
    if not frame then error("Native ChatFrameEditBox is unavailable.") end
    if editRecord and editRecord.frame ~= frame then error("Native ChatFrameEditBox was replaced.") end
    if not editRecord then editRecord = NewRecord(frame, "ChatFrameEditBox") end
    if options.fontSize > 0 then
        local original = editRecord.leases.font and editRecord.leases.font.original or ReadFont(frame)
        Property(editRecord, "font", ReadFont, SetFont, {original[1], options.fontSize, original[3]})
    else Property(editRecord, "font", ReadFont, SetFont, nil) end
    Require(frame, {"GetAltArrowKeyMode", "SetAltArrowKeyMode"}, "ChatFrameEditBox")
    Property(editRecord, "arrows", ReadArrows, SetArrows, not options.arrowKeys)
    if options.position ~= "native" then
        Require(frame, {"GetNumPoints", "GetPoint", "ClearAllPoints", "SetPoint"}, "ChatFrameEditBox")
        -- Blizzard 1.12 has one shared editbox statically attached to frame 1.
        -- Its input/header/send scripts and chatFrame reference stay intact.
        local owner = Global("ChatFrame1")
        local top = options.position == "top"
        Property(editRecord, "points", ReadPoints, SetPoints, top and
            {{"BOTTOMLEFT", owner, "TOPLEFT", -5, 2}, {"BOTTOMRIGHT", owner, "TOPRIGHT", 5, 2}} or
            {{"TOPLEFT", owner, "BOTTOMLEFT", -5, -2}, {"TOPRIGHT", owner, "BOTTOMRIGHT", 5, -2}})
    else Property(editRecord, "points", ReadPoints, SetPoints, nil) end
    local header = Global("ChatFrameEditBoxHeader")
    if header then
        if not editRecord.header then editRecord.header = NewRecord(header, "ChatFrameEditBoxHeader", true) end
        if options.fontSize > 0 then
            editRecord.headerDirty = true
            local original = editRecord.header.leases.font and editRecord.header.leases.font.original or ReadFont(header)
            Property(editRecord.header, "font", ReadFont, SetFont, {original[1], options.fontSize, original[3]})
        else Property(editRecord.header, "font", ReadFont, SetFont, nil) end
        if editRecord.headerDirty then
            if type(ChatEdit_UpdateHeader) ~= "function" then error("Native chat input header layout is unavailable.") end
            -- The existing helper measures the current destination caption;
            -- input text, caret, channel and all input scripts remain native.
            Must(ChatEdit_UpdateHeader, frame)
        end
    end
end
local function ApplyAll()
    state.windows = 0
    for id = 1, Configuration.WindowCount() do
        local frame = Global("ChatFrame" .. id)
        if frame then
            local record = records[id]
            if record and record.frame ~= frame then error("ChatFrame" .. id .. " was replaced.") end
            if not record then record = NewRecord(frame, "ChatFrame" .. id); records[id] = record end
            ApplyWindow(record, Configuration.Resolve(store, id))
            state.windows = state.windows + 1
        elseif id == 1 then error("Native ChatFrame1 is unavailable.") end
    end
    ApplyEditbox(Configuration.ResolveEditbox(store))
    if state.dockDirty then
        if type(FCF_DockUpdate) ~= "function" then error("Native chat docking layout is unavailable.") end
        Must(FCF_DockUpdate)
    end
end
local function Disable(record)
    if record.wheel then record.wheel.enabled = false end
    for _, lease in pairs(record.textures) do lease.enabled = false end
    for _, lease in pairs(record.buttons) do lease.enabled = false end
end
local function Attempt(callback, owner, a, b, c, d, e)
    local ran, ok, reason = Call(callback, owner, a, b, c, d, e)
    if not ran then return false, tostring(ok) end
    return ok, reason
end
local function HideSurface(surface)
    local ok, reason = Call(surface.Hide, surface)
    if not ok then return false, tostring(reason) end
    local inspected, shown = Call(surface.IsShown, surface)
    if not inspected then return false, tostring(shown) end
    if reason == false or Enabled(shown) then return false, "Chat surface hiding was declined." end
    return true
end
local function ReleaseWheel(record)
    local current = record.frame:GetScript("OnMouseWheel")
    if current ~= record.wheel.guard and current ~= record.wheel.original then record.leases.wheel = nil end
    return ReleaseSlot(record.frame, "OnMouseWheel", record.wheel.original, record.wheel.guard, true)
end
local function Release(record)
    local failure
    if record.wheel then
        local ok, reason = Attempt(ReleaseWheel, record)
        if ok then record.wheel = nil else failure = reason end
    end
    for key in pairs(record.leases) do
        -- Keep input enabled until its callback owner can be verified/released.
        if key ~= "wheel" or not record.wheel then
            local ok, reason = Attempt(ReleaseProperty, record, key)
            if not ok then failure = failure or reason end
        end
    end
    for name in pairs(record.textures) do
        local ok, reason = Attempt(ReleaseTexture, record, name)
        if not ok then failure = failure or reason end
    end
    for name in pairs(record.buttons) do
        local ok, reason = Attempt(ReleaseButton, record, name)
        if not ok then failure = failure or reason end
    end
    if record.surface then
        local ok, reason = HideSurface(record.surface)
        if not ok then failure = failure or reason end
    end
    if record.tabBorder then
        local ok, reason = HideSurface(record.tabBorder)
        if not ok then
            failure = failure or reason
        elseif record.tab and record.tab.openBorder == record.tabBorder then record.tab.openBorder = nil end
    end
    if record.tabText then local ok, reason = Attempt(Release, record.tabText); if not ok then failure = failure or reason end end
    if record.tabLayout then local ok, reason = Attempt(Release, record.tabLayout); if not ok then failure = failure or reason end end
    if record.header then local ok, reason = Attempt(Release, record.header); if not ok then failure = failure or reason end end
    return failure == nil, failure
end
function Native.Stop()
    state.active = false
    for _, record in pairs(records) do Disable(record) end
    if editRecord then Disable(editRecord) end
    local failure
    for _, record in pairs(records) do
        local ran, ok, reason = Call(Release, record)
        if not ran or not ok then failure = failure or tostring(ran and reason or ok) end
    end
    if editRecord then
        local ran, ok, reason = Call(Release, editRecord)
        if not ran or not ok then failure = failure or tostring(ran and reason or ok) end
        if editRecord.headerDirty then
            local ran, result = Call(ChatEdit_UpdateHeader, editRecord.frame)
            if not ran or result == false then failure = failure or tostring(ran and "Native chat input header restoration was declined." or result)
            else editRecord.headerDirty = nil end
        end
    end
    if state.dockDirty then
        local ran, result = Call(FCF_DockUpdate)
        if not ran or result == false then failure = failure or tostring(ran and "Native chat docking restoration was declined." or result)
        else state.dockDirty = nil end
    end
    state.restorationBlocked = failure ~= nil
    if failure then state.failure = failure; return false, failure end
    store, state.failure = nil, nil
    return true
end
local function Apply(value, refresh)
    local valid, reason = Configuration.Validate(value)
    if not valid then return false, reason end
    if not state.active then return false, "Native chat is not active." end
    store = value or {}
    local ran, failure = Call(function()
        local owner = CompetingOwner()
        if owner then error(owner) end
        if refresh then
            for id, record in pairs(records) do
                local lease = record.leases.font
                if lease then
                    local current = ReadFont(record.frame)
                    if not Equal(current, lease.applied) then
                        local _, nativeSize = GetChatWindowInfo(id)
                        if current[1] ~= lease.applied[1] or current[3] ~= lease.applied[3] or
                            current[2] ~= nativeSize or not nativeSize or nativeSize <= 0 then
                            error(record.name .. " font has another owner.")
                        end
                        lease.original[2], lease.applied = nativeSize, current
                    end
                end
                -- UPDATE_CHAT_WINDOWS is the native geometry boundary. Keep
                -- those new native values as the disable/restoration target.
                for _, key in ipairs({"width", "height"}) do
                    local geometry = record.leases[key]
                    if geometry then
                        local current = geometry.read(record.frame)
                        if not Equal(current, geometry.applied) then geometry.original, geometry.applied = current, current end
                    end
                end
                if record.tabLayout and record.tabLayout.leases.geometry then
                    local geometry = record.tabLayout.leases.geometry
                    local current = ReadTabGeometry(record.tabLayout.frame)
                    if not Equal(current, geometry.applied) then geometry.original, geometry.applied = current, current end
                end
            end
        end
        ApplyAll()
    end)
    if ran then state.failure = nil; return true end
    local restored, restoreReason = Native.Stop()
    state.failure = tostring(failure) .. (restored and "" or " Restoration: " .. tostring(restoreReason))
    return false, state.failure
end
function Native.Apply(value) return Apply(value, false) end
function Native.Refresh(value) return Apply(value, true) end
function Native.Start(value)
    local valid, reason = Configuration.Validate(value)
    if not valid then return false, reason end
    if state.restorationBlocked then
        local restored, failure = Native.Stop()
        if not restored then return false, failure end
    end
    state.active = true
    return Native.Apply(value)
end
function Native.GetState() return state end
function Native.SetFailureObserver(observer) failureObserver = type(observer) == "function" and observer or nil end
