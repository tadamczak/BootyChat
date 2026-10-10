local Chat = BootyChat
-- Some 1.12 addons replace global error with a nonthrowing chat logger.
local Assert = assert
local function error(message) Assert(false, message) end
local Native = {}
Chat.Modules.NativeChat = Native
local Configuration = Chat.Services.Configuration
local UI = (Chat.UI or BootyLib.UI).Components
local records, editRecord = {}, nil
local state = {active = false, restorationBlocked = false, windows = 0, foreignChanges = 0, deferredWheels = 0}
local store, failureObserver, tabResizeLease, tabMovementLease, mouseOverLease
local competingOwners = {"pfUI", "Prat", "Chatter"}
local fonts = {friz = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF", skurri = "Fonts\\SKURRI.TTF"}
local textureNames = {"Background", "ResizeTopLeftTexture", "ResizeTopRightTexture",
    "ResizeBottomLeftTexture", "ResizeBottomRightTexture", "ResizeTopTexture",
    "ResizeBottomTexture", "ResizeLeftTexture", "ResizeRightTexture"}
local standardBorders = {
    dialog = {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = {left = 5, right = 5, top = 5, bottom = 5}},
    tooltip = {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8, insets = {left = 2, right = 2, top = 2, bottom = 2}},
    none = {bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8},
}
local tabTextureNames = {"Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled", "HighlightTexture"}
local tabBackgrounds={
    color={bgFile="Interface\\Buttons\\WHITE8X8",tile=true,tileSize=16},
    dialog={bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",tile=true,tileSize=16},
    tooltip={bgFile="Interface\\Tooltips\\UI-Tooltip-Background",tile=true,tileSize=16},
}

local function Global(name) return type(getglobal) == "function" and getglobal(name) or _G[name] end
local function Enabled(value) return value ~= nil and value ~= false and value ~= 0 end
local function CompetingOwner()
    for _, name in ipairs(competingOwners) do
        if Enabled(Global(name)) or type(IsAddOnLoaded) == "function" and Enabled(IsAddOnLoaded(name)) then
            return "Disable " .. name .. " chat ownership before enabling BootyChat."
        end
    end
end
local function Call(callback, ...)
    local previousThis, previousEvent, previousArg = this, event, arg1
    -- Lua 5.0's implicit arg.n keeps the exact count, including a trailing nil.
    -- Native C methods see every argument; padding a setter can clear its script.
    local ok, first, second, third, fourth, fifth = pcall(callback, unpack(arg))
    this, event, arg1 = previousThis, previousEvent, previousArg
    return ok, first, second, third, fourth, fifth
end
local function Equal(a, b, tolerance)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) == "table" then
        -- Native frame references are identities, including clients/doubles
        -- that expose them as tables with cyclic parent/child relationships.
        if type(a.GetName) == "function" or type(b.GetName) == "function" then return false end
        for key, value in pairs(a) do if not Equal(value, b[key], tolerance) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end
    if type(a) == "number" then return math.abs(a - b) < (tolerance or 0.00001) end
    return a == b
end
local function FontPath(value) return type(value) == "string" and string.lower(string.gsub(value, "/", "\\")) or value end
local function FontFlags(value)
    value = string.upper(value or "")
    local outline = string.find(value, "THICKOUTLINE", 1, true) and "THICKOUTLINE" or
        string.find(value, "OUTLINE", 1, true) and "OUTLINE" or ""
    local remaining = string.gsub(string.gsub(string.gsub(value, "THICKOUTLINE", ""), "OUTLINE", ""), "MONOCHROME", "")
    remaining = string.gsub(remaining, "[%s,]", "")
    if remaining ~= "" then return value end
    return outline .. (string.find(value, "MONOCHROME", 1, true) and ",MONOCHROME" or "")
end
local function PropertyEqual(key, a, b)
    if key == "font" and type(a) == "table" and type(b) == "table" then
        -- FontString font heights are native floats (1.12 font-height getter).
        -- Compare equivalent resource/flag spellings, not their serialization.
        return FontPath(a[1]) == FontPath(b[1]) and Equal(a[2], b[2], 0.001) and FontFlags(a[3]) == FontFlags(b[3])
    end
    -- Native layout getters use float rectangles and scale conversion. Keep
    -- sub-millipixel readback noise separate from actual ownership changes.
    local tolerance = (key == "width" or key == "height" or key == "points" or key == "geometry") and 0.001 or nil
    return Equal(a, b, tolerance)
end
local function WriteFailure(record, key, desired, actual, restoring)
    local action = restoring and "restoration" or "write"
    if type(desired) == "number" and type(actual) == "number" then
        return string.format("%s %s %s was declined (wanted %.9f, read %.9f).", record.name, key, action, desired, actual)
    end
    if key == "font" and type(desired) == "table" and type(actual) == "table" then
        return string.format("%s font %s was declined (wanted %s / %.9f / %s, read %s / %.9f / %s).",
            record.name, action, tostring(desired[1]), desired[2] or 0, tostring(desired[3]),
            tostring(actual[1]), actual[2] or 0, tostring(actual[3]))
    end
    return record.name .. " " .. key .. " " .. action .. " was declined."
end
local function ReadFont(frame)
    local path, size, flags = frame:GetFont()
    return {path, size, flags or ""}
end
local function SetFont(frame, value) return frame:SetFont(value[1], value[2], value[3]) end
local function ReadTextColor(frame)
    local r, g, b, a = frame:GetTextColor()
    return {r, g, b, a or 1}
end
local function ReadShadowColor(frame)
    local r, g, b, a = frame:GetShadowColor()
    return {r, g, b, a or 1}
end
local function SetShadowColor(frame, value) return frame:SetShadowColor(value[1], value[2], value[3], value[4]) end
local function ReadShadowOffset(frame)
    local x, y = frame:GetShadowOffset()
    return {x, y}
end
local function SetShadowOffset(frame, value) return frame:SetShadowOffset(value[1], value[2]) end
local function ReadFading(frame) return Enabled(frame:GetFading()) end
local function SetFading(frame, value) return frame:SetFading(value and 1 or nil) end
local function ReadTimeVisible(frame) return frame:GetTimeVisible() end
local function SetTimeVisible(frame, value) return frame:SetTimeVisible(value) end
local function ReadFadeDuration(frame) return frame:GetFadeDuration() end
local function SetFadeDuration(frame, value) return frame:SetFadeDuration(value) end
local function ReadSpacing(frame) return frame:GetSpacing() end
local function SetSpacing(frame, value) return frame:SetSpacing(value) end
local function ReadWidth(frame) return frame:GetWidth() end
local function SetWidth(frame, value) return frame:SetWidth(value) end
local function ReadHeight(frame) return frame:GetHeight() end
local function SetHeight(frame, value) return frame:SetHeight(value) end
local function ReadHitRect(frame) return {frame:GetHitRectInsets()} end
local function SetHitRect(frame,value) return frame:SetHitRectInsets(unpack(value)) end
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
local function CopyPoints(points)
    local result = {}
    for index, point in ipairs(points) do result[index] = {point[1], point[2], point[3], point[4], point[5]} end
    return result
end
local function Require(frame, methods, name)
    for _, method in ipairs(methods) do
        if type(frame[method]) ~= "function" then error(name .. " lacks " .. method .. ".") end
    end
end
local function Must(callback, ...)
    local ok, result = Call(callback, unpack(arg))
    if not ok then error(tostring(result)) end
    if result == false then error("A native chat write was declined.") end
    return result
end
local function ReleaseProperty(record, key)
    local lease = record.leases[key]
    if not lease then return true, nil, false end
    local ok, current = Call(lease.read, record.frame)
    if not ok then return false, tostring(current) end
    if PropertyEqual(key, current, lease.original) then record.leases[key] = nil; return true, nil, false end
    if not PropertyEqual(key, current, lease.applied) then
        -- A later owner changed this value. Its state is authoritative.
        state.foreignChanges = state.foreignChanges + 1
        record.leases[key] = nil
        return true, nil, false
    end
    local written, failure = Call(lease.write, record.frame, lease.original)
    local inspected, actual = Call(lease.read, record.frame)
    if written and failure ~= false and inspected and PropertyEqual(key, actual, lease.original) then
        record.leases[key] = nil
        return true, nil, true
    end
    return false, tostring(not written and failure or not inspected and actual or
        WriteFailure(record, key, lease.original, actual, true))
end
local function Property(record, key, read, write, desired)
    if desired == nil then
        local restored, reason, changed = ReleaseProperty(record, key)
        if not restored then error(reason) end
        return changed or false
    end
    local lease = record.leases[key]
    local inspected, actual = Call(read, record.frame)
    if not inspected then error(tostring(actual)) end
    if lease and not PropertyEqual(key, actual, lease.applied) then
        error(record.name .. " " .. key .. " has another owner.")
    end
    if not lease then
        lease = {read = read, write = write, original = actual, applied = actual}
        record.leases[key] = lease
    end
    if PropertyEqual(key, actual, desired) then return false end
    lease.applied = desired
    local written, failure = Call(write, record.frame, desired)
    local inspected, after = Call(read, record.frame)
    -- A setter may mutate and then fail. Retain its actual partial write so
    -- rollback can distinguish our change from a subsequent foreign change.
    if inspected then lease.applied = after end
    if not written then error(tostring(failure)) end
    if failure == false or not inspected or not PropertyEqual(key, after, desired) then
        error(not inspected and tostring(after) or WriteFailure(record, key, desired, after))
    end
    return true
end
local function Shadow(record, mode, color, alpha, x, y)
    local custom = mode == "custom"
    if custom then Require(record.frame, {"GetShadowColor", "SetShadowColor", "GetShadowOffset", "SetShadowOffset"}, record.name) end
    Property(record, "shadowColor", ReadShadowColor, SetShadowColor, custom and {color[1], color[2], color[3], alpha} or nil)
    Property(record, "shadowOffset", ReadShadowOffset, SetShadowOffset, custom and {x, y} or nil)
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
local function Texture(record, name, hidden, supplied)
    local lease = record.textures[name]
    if not hidden then return end
    local texture = supplied or Global(record.name .. name)
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
    -- A disabled guard must retain ownership until the refused value restore
    -- can be retried; releasing its method slot would lose that evidence.
    if not ok then return false, tostring(reason) end
    local released, slotReason = ReleaseSlot(lease.texture, "SetAlpha", lease.setter, lease.guard)
    if released then record.textures[name] = nil; return true end
    return false, tostring(slotReason)
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
    if not ok then return false, tostring(reason) end
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
    -- A later handler may wrap our old callback. Leave it in control for this
    -- activation instead of wrapping it again or stopping unrelated appearance.
    local lease = record.wheel
    if lease and record.frame:GetScript("OnMouseWheel") ~= lease.guard then
        lease.enabled = false
        record.wheel, record.leases.wheel = nil, nil
        record.wheelDeferred = true
        state.foreignChanges = state.foreignChanges + 1
        state.deferredWheels = state.deferredWheels + 1
    end
    if record.wheelDeferred then return end
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
    lease = record.wheel
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
    end
    lease.speed, lease.shift, lease.enabled = options.wheelSpeed, options.shiftScroll, true
    Property(record, "wheel", ReadWheel, SetWheel, true)
end
local function Appearance(record, options)
    local custom = options.goldBorder or options.backgroundAlpha >= 0
    if custom then
        if not record.surface then
            if not UI.Window or type(UI.Window.ApplyProjectSurface) ~= "function" then error("BootyLib project window surface is unavailable.") end
            record.surface = UI.CreateContainer(nil, record.frame)
        end
        if not record.surfaceReady then
            Require(record.surface, {"EnableMouse", "SetFrameStrata", "SetFrameLevel"}, "Project chat surface")
            Must(record.surface.EnableMouse, record.surface, false)
            Must(record.surface.SetFrameStrata, record.surface, record.frame:GetFrameStrata())
            Must(record.surface.SetFrameLevel, record.surface, math.max(0, record.frame:GetFrameLevel() - 1))
            -- Keep a pooled allocation, but retry every unfinished setup step.
            record.surfaceReady = true
        end
        Must(record.surface.ClearAllPoints, record.surface)
        Must(record.surface.SetPoint, record.surface, "TOPLEFT", record.frame, "TOPLEFT", -options.backgroundMarginLeft, options.backgroundMarginTop)
        Must(record.surface.SetPoint, record.surface, "BOTTOMRIGHT", record.frame, "BOTTOMRIGHT", options.backgroundMarginRight, -options.backgroundMarginBottom)
        UI.Window.ApplyProjectSurface(record.surface)
        local color = options.backgroundColor
        Must(record.surface.SetBackdropColor, record.surface, color[1], color[2], color[3], math.max(0, options.backgroundAlpha))
        local r, g, b = record.surface:GetBackdropBorderColor()
        Must(record.surface.SetBackdropBorderColor, record.surface, r, g, b, options.goldBorder and options.borderAlpha or 0)
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
        return (tabResizeLease and tabResizeLease.original or PanelTemplates_TabResize)(10, layout.parts.tab, value.tab)
    end
    for key, region in pairs(layout.parts) do
        if region:SetWidth(value[key]) == false then return false end
    end
end
local function FitTab(record, tab, label, options)
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
    local width = options.tabWidth > 0 and math.max(options.tabWidth,2*left:GetWidth()+1) or middle + 2 * left:GetWidth()
    middle=width-2*left:GetWidth()
    local desired = {tab = width, text = middle}
    for key in pairs(layout.parts) do
        if key ~= "tab" and key ~= "text" then desired[key] = key == "highlight" and width or middle end
    end
    layout.desired = desired
    return Property(record.tabLayout, "geometry", ReadTabGeometry, WriteTabGeometry, desired)
end
local function InstallTabResize()
    if tabResizeLease then
        if PanelTemplates_TabResize~=tabResizeLease.guard then error("Native tab resize has another owner.") end
        return
    end
    Require(_G,{"PanelTemplates_TabResize"},"Native tab resize")
    local lease={original=PanelTemplates_TabResize}
    lease.guard=function(padding,tab,absoluteSize,maxWidth)
        local record
        if state.active and not lease.applying then
            for _,candidate in pairs(records) do if candidate.tab==(tab or this) then record=candidate;break end end
        end
        if not record then return lease.original(padding,tab,absoluteSize,maxWidth) end
        local geometry=record.tabLayout and record.tabLayout.leases.geometry
        if geometry and not PropertyEqual("geometry",ReadTabGeometry(record.tabLayout.frame),geometry.applied) then
            return ReportFailure(record.name.." tab geometry has another owner.")
        end
        local ok,result=Call(lease.original,padding,tab,absoluteSize,maxWidth)
        if geometry then
            local actual=ReadTabGeometry(record.tabLayout.frame)
            geometry.original,geometry.applied=actual,actual
        end
        if not ok or result==false then return ReportFailure(ok and "Native tab resize was declined." or result) end
        -- Only a completed native resize may replace the restoration target.
        -- Direct foreign geometry writes still fail the ownership check.
        if record.tabOptions and (not Enabled(record.frame.isDocked) or record.tabOptions.tabWidth>0 and not absoluteSize) then
            lease.applying=true
            local fitted,reason=Call(FitTab,record,record.tab,record.tabText.frame,record.tabOptions)
            lease.applying=false
            if not fitted then return ReportFailure(reason) end
        end
        return result
    end
    PanelTemplates_TabResize=lease.guard;tabResizeLease=lease
end
local function RefreshTabColor(record)
    local lease = record.tabColor
    if not lease or not lease.enabled then return end
    if lease.frame.SetTextColor ~= lease.guard then error(record.name .. " tab color has another owner.") end
    local selected = Global("SELECTED_DOCK_FRAME") or Global("SELECTED_CHAT_FRAME")
    local color = not Enabled(record.frame.isDocked) or selected == record.frame
    color = color and lease.activeColor or lease.inactiveColor
    local alpha = lease.nativeColor[4]
    local r, g, b, a = lease.frame:GetTextColor()
    if Equal(r, color[1]) and Equal(g, color[2]) and Equal(b, color[3]) and Equal(a or 1, alpha) then
        lease.applied = {r, g, b, a or 1}
        return
    end
    local written, reason = Call(lease.setter, lease.frame, color[1], color[2], color[3], alpha)
    local inspected, actual = Call(ReadTextColor, lease.frame)
    if inspected then lease.applied = actual end
    if not written then error(tostring(reason)) end
    if reason == false or not inspected then error(not inspected and tostring(actual) or "Native chat tab color was declined.") end
    if not Equal(actual, {color[1], color[2], color[3], alpha}) then error("Native chat tab color was declined.") end
end
local function RefreshTabColors()
    for _, record in pairs(records) do RefreshTabColor(record) end
end
local function ReleaseTabColor(record)
    local lease = record.tabColor
    if not lease then return true end
    lease.enabled = false
    local current = ReadTextColor(lease.frame)
    local ok, reason = true, nil
    if Equal(current, lease.nativeColor) then
        -- A previous refused write may already have restored the value.
    elseif lease.frame.SetTextColor == lease.guard and lease.applied and Equal(current, lease.applied) then
        ok, reason = Call(lease.setter, lease.frame, lease.nativeColor[1], lease.nativeColor[2], lease.nativeColor[3], lease.nativeColor[4])
        if ok and reason ~= false and not Equal(ReadTextColor(lease.frame), lease.nativeColor) then ok, reason = false, "Native chat tab color restoration was declined." end
        if reason == false then ok, reason = false, "Native chat tab color restoration was declined." end
    elseif not Equal(current, lease.nativeColor) then state.foreignChanges = state.foreignChanges + 1 end
    if not ok then return false, tostring(reason) end
    local released, slotReason = ReleaseSlot(lease.frame, "SetTextColor", lease.setter, lease.guard)
    if released then record.tabColor = nil; return true end
    return false, tostring(slotReason)
end
local function ReleaseTabHooks(record)
    local failure
    if record.tabColorHooks then
        for name, lease in pairs(record.tabColorHooks) do
            lease.enabled = false
            local ran, ok, reason = Call(ReleaseSlot, record.frame, name, lease.original, lease.guard, true)
            if ran and ok then record.tabColorHooks[name] = nil
            else failure = failure or tostring(ran and reason or ok) end
        end
    end
    return failure == nil, failure
end
local function FinishTabMovement(record)
    if MOVING_CHATFRAME~=record.frame then return end
    Must(record.frame.StopMovingOrSizing,record.frame)
    MOVING_CHATFRAME=nil
end
local function InstallTabMovement()
    if tabMovementLease then
        if FCF_Tab_OnClick~=tabMovementLease.guard then error("Native tab click has another owner.") end
        return
    end
    Require(_G,{"FCF_Tab_OnClick"},"Native tab click")
    local lease={original=FCF_Tab_OnClick}
    lease.guard=function(button)
        local tab=this
        if not state.active then return lease.original(button) end
        local ok,result=Call(lease.original,button)
        if not ok then return ReportFailure(result) end
        -- Stock NORMAL/up clicks can restart movement after OnDragStop.
        -- Finish after that callback; keep the native tab scripts unchanged.
        if tab and (button=="RightButton" or button=="LeftButton" and tab:GetButtonState()=="NORMAL") then
            for _,record in pairs(records) do
                if record.tab==tab then
                    local stopped,reason=Call(FinishTabMovement,record)
                    if not stopped then return ReportFailure(reason) end
                    break
                end
            end
        end
        return result
    end
    FCF_Tab_OnClick=lease.guard;tabMovementLease=lease
end
local function TabColor(record, label, options)
    if options.tabColorMode ~= "custom" then
        local hooksOK, hooksReason = ReleaseTabHooks(record)
        local colorOK, colorReason = ReleaseTabColor(record)
        if not hooksOK or not colorOK then error(hooksReason or colorReason) end
        return
    end
    local lease = record.tabColor
    if not lease then
        Require(label, {"GetTextColor", "SetTextColor"}, record.name .. "TabText")
        lease = {frame = label, setter = label.SetTextColor, nativeColor = ReadTextColor(label)}
        record.tabColor = lease
        lease.guard = function(owner, r, g, b, a)
            if not lease.enabled or owner ~= lease.frame then
                if a == nil then return lease.setter(owner, r, g, b) end
                return lease.setter(owner, r, g, b, a)
            end
            lease.nativeColor = {r, g, b, a or 1}
            local ok, reason = Call(RefreshTabColor, record)
            if not ok then ReportFailure(reason) end
        end
        label.SetTextColor = lease.guard
    elseif label.SetTextColor ~= lease.guard then error(record.name .. " tab color has another owner.") end
    lease.activeColor, lease.inactiveColor, lease.enabled = options.tabActiveColor, options.tabInactiveColor, true
    record.tabColorHooks = record.tabColorHooks or {}
    for _, name in ipairs({"OnShow", "OnHide"}) do
        local hook = record.tabColorHooks[name]
        if not hook then
            hook = {original = record.frame:GetScript(name)}
            record.tabColorHooks[name] = hook
            hook.guard = function()
                if hook.original then
                    if not hook.enabled then return hook.original() end
                    local ok, reason = Call(hook.original)
                    if not ok then ReportFailure(reason) end
                end
                if not hook.enabled or not state.active then return end
                local ok, reason = Call(RefreshTabColors)
                if not ok then ReportFailure(reason) end
            end
            Must(record.frame.SetScript, record.frame, name, hook.guard)
            if record.frame:GetScript(name) ~= hook.guard then error("Native chat visibility script was declined.") end
        elseif record.frame:GetScript(name) ~= hook.guard then error(record.name .. " " .. name .. " has another owner.") end
        hook.enabled = true
    end
    RefreshTabColor(record)
end
local function ApplyMessageText(record, options)
    local original = record.leases.font and record.leases.font.original or ReadFont(record.frame)
    local font, size, outline = options.font == "native" and original[1] or fonts[options.font],
        options.fontSize == 0 and original[2] or options.fontSize,
        options.fontOutline == "native" and original[3] or options.fontOutline == "none" and "" or options.fontOutline
    Property(record, "font", ReadFont, SetFont, {font, size, outline})
    Shadow(record, options.shadowMode, options.shadowColor, options.shadowAlpha, options.shadowX, options.shadowY)
    local fading
    if options.fadingMode ~= "native" then
        Require(record.frame, {"GetFading", "SetFading"}, record.name)
        fading = options.fadingMode == "on"
    end
    Property(record, "fading", ReadFading, SetFading, fading)
    if options.timeVisible > 0 then Require(record.frame, {"GetTimeVisible", "SetTimeVisible"}, record.name) end
    if options.fadeDuration > 0 then Require(record.frame, {"GetFadeDuration", "SetFadeDuration"}, record.name) end
    if options.lineSpacing >= 0 then Require(record.frame, {"GetSpacing", "SetSpacing"}, record.name) end
    Property(record, "timeVisible", ReadTimeVisible, SetTimeVisible, options.timeVisible > 0 and options.timeVisible or nil)
    Property(record, "fadeDuration", ReadFadeDuration, SetFadeDuration, options.fadeDuration > 0 and options.fadeDuration or nil)
    Property(record, "spacing", ReadSpacing, SetSpacing, options.lineSpacing >= 0 and options.lineSpacing or nil)
end
local function RelativeTabOffset(relative)
    if type(relative) == "string" then relative = Global(relative) end
    for _, other in pairs(records) do
        local lease = other.tabPosition
        if other.tab == relative and lease and lease.enabled then return lease.x, lease.y end
    end
    return 0, 0
end
local function TabPointOffsets(point, x, y)
    local relativeX, relativeY = RelativeTabOffset(point[2])
    return x - relativeX, y - relativeY
end
local function NativeTabPoint(owner, values)
    local point, relative, relativePoint, x, y = values[1], values[2], values[3], values[4], values[5]
    -- The native five-argument layout calls and the engine's local x/y
    -- shorthand share the same resolved parent anchor on readback.
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, owner:GetParent(), point
    else
        if relative == nil then relative = owner:GetParent() elseif type(relative) == "string" then relative = Global(relative) or relative end
        relativePoint = relativePoint or point
    end
    return {point, relative, relativePoint, x or 0, y or 0}
end
local function ReplaceTabPoint(points, point)
    local result, replaced = CopyPoints(points), nil
    for index, current in ipairs(result) do
        if current[1] == point[1] then result[index] = point; replaced = true; break end
    end
    if not replaced then result[table.getn(result) + 1] = point end
    return result
end
local function ReleaseTabPosition(record)
    local lease = record.tabPosition
    if not lease then return true end
    lease.enabled = false
    local current = ReadPoints(lease.frame)
    local owned = lease.frame.SetPoint == lease.setGuard and lease.frame.ClearAllPoints == lease.clearGuard
    if owned and PropertyEqual("points", current, lease.applied) then
        local ok, reason = Call(lease.clearer, lease.frame)
        lease.applied = ReadPoints(lease.frame)
        if not ok or reason == false then return false, tostring(ok and "Native tab position restoration was declined." or reason) end
        for _, point in ipairs(lease.native) do
            ok, reason = Call(lease.setter, lease.frame, unpack(point))
            lease.applied = ReadPoints(lease.frame)
            if not ok or reason == false then return false, tostring(ok and "Native tab position restoration was declined." or reason) end
        end
        if not PropertyEqual("points", ReadPoints(lease.frame), lease.native) then return false, "Native tab position restoration was declined." end
    elseif not owned or not PropertyEqual("points", current, lease.native) then state.foreignChanges = state.foreignChanges + 1 end
    local setOK, setReason = ReleaseSlot(lease.frame, "SetPoint", lease.setter, lease.setGuard)
    local clearOK, clearReason = ReleaseSlot(lease.frame, "ClearAllPoints", lease.clearer, lease.clearGuard)
    if not setOK or not clearOK then return false, setReason or clearReason end
    record.tabPosition = nil
    return true
end
local function TabPosition(record, tab, options)
    local x, y = options.tabOffsetX or 0, options.tabOffsetY or 0
    local relativeShift
    local native = record.tabPosition and record.tabPosition.native or ReadPoints(tab)
    for _, point in ipairs(native) do
        local relativeX, relativeY = RelativeTabOffset(point[2])
        if relativeX ~= 0 or relativeY ~= 0 then relativeShift = true end
    end
    if x == 0 and y == 0 and not relativeShift then
        local ok, reason = ReleaseTabPosition(record)
        if not ok then error(reason) end
        return
    end
    Require(tab, {"GetNumPoints", "GetPoint", "SetPoint", "ClearAllPoints", "GetParent"}, record.name .. "Tab")
    local lease = record.tabPosition
    if lease and (tab.SetPoint ~= lease.setGuard or tab.ClearAllPoints ~= lease.clearGuard or
        not PropertyEqual("points", ReadPoints(tab), lease.applied)) then error(record.name .. " tab position has another owner.") end
    if not lease then
        lease = {frame = tab, setter = tab.SetPoint, clearer = tab.ClearAllPoints, native = ReadPoints(tab)}
        record.tabPosition = lease
        lease.setGuard = function(owner, ...)
            if not lease.enabled or owner ~= lease.frame then return lease.setter(owner, unpack(arg)) end
            local native = NativeTabPoint(owner, arg)
            local x, y = TabPointOffsets(native, lease.x, lease.y)
            local desired = {native[1], native[2], native[3], native[4] + x, native[5] + y}
            local expected = ReplaceTabPoint(ReadPoints(owner), desired)
            local ok, reason = Call(lease.setter, owner, unpack(desired))
            lease.applied = ReadPoints(owner)
            if not ok or reason == false then ReportFailure(ok and "Native chat tab position was declined." or reason) end
            if not PropertyEqual("points", lease.applied, expected) then ReportFailure("Native chat tab position write was declined.") end
            -- SetPoint replaces a matching anchor; readback captures the engine's
            -- actual anchor list rather than appending duplicate native points.
            lease.native = CopyPoints(lease.applied)
            for _, anchor in ipairs(lease.native) do
                local x, y = TabPointOffsets(anchor, lease.x, lease.y)
                anchor[4], anchor[5] = anchor[4] - x, anchor[5] - y
            end
            return reason
        end
        lease.clearGuard = function(owner)
            if not lease.enabled or owner ~= lease.frame then return lease.clearer(owner) end
            local ok, reason = Call(lease.clearer, owner)
            lease.applied = ReadPoints(owner)
            if not ok or reason == false then ReportFailure(ok and "Native chat tab position clearing was declined." or reason) end
            if table.getn(lease.applied) ~= 0 then ReportFailure("Native chat tab position clearing was declined.") end
            lease.native = {}
            return reason
        end
        tab.SetPoint, tab.ClearAllPoints = lease.setGuard, lease.clearGuard
    end
    lease.x, lease.y, lease.enabled = x, y, true
    local expected = CopyPoints(lease.native)
    for _, point in ipairs(expected) do
        local offsetX, offsetY = TabPointOffsets(point, x, y)
        point[4], point[5] = point[4] + offsetX, point[5] + offsetY
    end
    if PropertyEqual("points", ReadPoints(tab), expected) then lease.applied = expected; return end
    local cleared, reason = Call(lease.clearer, tab)
    lease.applied = ReadPoints(tab)
    if not cleared or reason == false then error(cleared and "Native tab position clearing was declined." or tostring(reason)) end
    for _, point in ipairs(expected) do
        local written, reason = Call(lease.setter, tab, unpack(point))
        lease.applied = ReadPoints(tab)
        if not written or reason == false then error(written and "Native tab position write was declined." or tostring(reason)) end
    end
    if not PropertyEqual("points", lease.applied, expected) then error(record.name .. " tab position write was declined.") end
end
local function TabAppearance(record, tab, options)
    local style = options.tabBorderStyle or (options.tabBorderMode == "on" and "project" or
        options.tabBorderMode == "off" and "none" or "inherit")
    if style == "inherit" then style = options.goldBorder and "project" or "native" end
    local project = style == "project"
    if tab.openBorder and tab.openBorder ~= record.tabBorder then
        if project then error(record.name .. " tab border has another owner.") end
    elseif project then
        if record.tabBorder and not tab.openBorder then tab.openBorder = record.tabBorder end
        local applied, failure = Call(UI.SetOpenButtonBorder, tab, true, "bottom")
        if tab.openBorder then record.tabBorder = tab.openBorder end
        if not applied then error(tostring(failure)) end
        if failure == false or not record.tabBorder then error("Project chat tab border was declined.") end
        if not Enabled(record.tabBorder:IsShown()) then error("Project chat tab border visibility was declined.") end
        local color = options.tabBorderColor or {1, 0.78, 0.2}
        Must(record.tabBorder.SetBackdropBorderColor, record.tabBorder, color[1], color[2], color[3], options.tabBorderAlpha or 1)
    end
    if not project and record.tabBorder then Must(record.tabBorder.Hide, record.tabBorder) end
    if style == "dialog" or style == "tooltip" then
        if not record.tabSurface then record.tabSurface = UI.CreateContainer(nil, tab) end
        local surface, color = record.tabSurface, options.tabBorderColor or {1, 0.78, 0.2}
        Must(surface.EnableMouse, surface, false)
        Must(surface.SetAllPoints, surface, tab)
        Must(surface.SetFrameStrata, surface, tab:GetFrameStrata())
        Must(surface.SetFrameLevel, surface, tab:GetFrameLevel() + 1)
        Must(surface.SetBackdrop, surface, standardBorders[style])
        Must(surface.SetBackdropColor, surface, 0, 0, 0, 0)
        Must(surface.SetBackdropBorderColor, surface, color[1], color[2], color[3], options.tabBorderAlpha or 1)
        Must(surface.Show, surface)
    elseif record.tabSurface then Must(record.tabSurface.Hide, record.tabSurface) end
    if options.tabBackground~="native" then
        if not record.tabBackground then
            record.tabBackground=UI.CreateContainer(nil,tab)
            Must(record.tabBackground.EnableMouse,record.tabBackground,false)
        end
        local surface=record.tabBackground
        Must(surface.SetAllPoints,surface,tab)
        Must(surface.SetFrameLevel,surface,math.max(0,tab:GetFrameLevel()-1))
        Must(surface.SetBackdrop,surface,tabBackgrounds[options.tabBackground])
        local color=options.tabBackgroundColor
        Must(surface.SetBackdropColor,surface,color[1],color[2],color[3],options.tabBackgroundAlpha)
        Must(surface.Show,surface)
    elseif record.tabBackground then Must(record.tabBackground.Hide,record.tabBackground) end
    for _, suffix in ipairs(tabTextureNames) do
        local name = "Tab" .. suffix
        local region=Global(record.name..name)
        if region then
            record.tabArt=record.tabArt or {}
            local art=record.tabArt[suffix]
            if not art then art={frame=region,name=record.name..name,leases={},textures={},buttons={}};record.tabArt[suffix]=art end
            Property(art,"height",ReadHeight,SetHeight,options.tabHeight>0 and options.tabHeight or nil)
        end
        if style ~= "native" or options.tabBackground~="native" then Texture(record, name, true)
        else local restored, reason = ReleaseTexture(record, name); if not restored then error(reason) end end
    end
    TabPosition(record, tab, options)
end
local function ReleaseTabVisibility(record)
    local lease=record.tabVisibility
    if not lease then return true end
    lease.enabled=false
    if lease.frame.Show==lease.showGuard and lease.frame.Hide==lease.hideGuard and lease.frame.SetAlpha==lease.alphaGuard then
        Must(lease.alpha,lease.frame,lease.nativeAlpha)
        Must(lease.nativeShown and lease.show or lease.hide,lease.frame)
    end
    local ok,reason=ReleaseSlot(lease.frame,"Show",lease.show,lease.showGuard)
    if not ok then return false,reason end
    ok,reason=ReleaseSlot(lease.frame,"Hide",lease.hide,lease.hideGuard)
    if not ok then return false,reason end
    ok,reason=ReleaseSlot(lease.frame,"SetAlpha",lease.alpha,lease.alphaGuard)
    if ok then record.tabVisibility=nil end
    return ok,reason
end
local function TabVisibility(record,tab,options)
    local _,_,_,_,_,_,shown=GetChatWindowInfo(record.frame:GetID())
    if not options.tabsAlwaysVisible or not Enabled(shown) then
        local ok,reason=ReleaseTabVisibility(record);if not ok then error(reason) end;return
    end
    local lease=record.tabVisibility
    if not lease then
        lease={frame=tab,show=tab.Show,hide=tab.Hide,alpha=tab.SetAlpha,nativeShown=Enabled(tab:IsShown()),nativeAlpha=tab:GetAlpha(),enabled=true}
        record.tabVisibility=lease
        local function ShowOpen(owner)
            local _,_,_,_,_,_,open=GetChatWindowInfo(record.frame:GetID())
            local result
            if Enabled(open) then
                if not Enabled(owner:IsShown()) then result=lease.show(owner) end
            else result=lease.hide(owner) end
            if Enabled(owner:IsShown())~=Enabled(open) then error("Native tab visibility write was declined.") end
            return result
        end
        lease.showGuard=function(owner)
            if not lease.enabled or owner~=tab then return lease.show(owner) end
            lease.nativeShown=true;local ok,reason=Call(ShowOpen,owner)
            if not ok or reason==false then ReportFailure(ok and "Tab visibility was declined." or reason) end
        end
        lease.hideGuard=function(owner)
            if not lease.enabled or owner~=tab then return lease.hide(owner) end
            lease.nativeShown=false;local ok,reason=Call(ShowOpen,owner)
            if not ok or reason==false then ReportFailure(ok and "Tab visibility was declined." or reason) end
        end
        lease.alphaGuard=function(owner,value)
            if not lease.enabled or owner~=tab then return lease.alpha(owner,value) end
            lease.nativeAlpha=value
            if owner:GetAlpha()==1 then return end
            local ok,reason=Call(lease.alpha,owner,1)
            if not ok or reason==false then ReportFailure(ok and "Tab alpha was declined." or reason) end
            if owner:GetAlpha()~=1 then ReportFailure("Tab alpha write was declined.") end
        end
        tab.Show,tab.Hide,tab.SetAlpha=lease.showGuard,lease.hideGuard,lease.alphaGuard
    elseif tab.Show~=lease.showGuard or tab.Hide~=lease.hideGuard or tab.SetAlpha~=lease.alphaGuard then error(record.name.." tab visibility has another owner.") end
    Must(lease.alpha,tab,1);Must(lease.show,tab)
    if tab:GetAlpha()~=1 or not Enabled(tab:IsShown()) then error("Native tab visibility write was declined.") end
end
local function InstallTabHover()
    if mouseOverLease then
        if MouseIsOver~=mouseOverLease.guard then error("Native mouse-over has another owner.") end
        return
    end
    local lease={original=MouseIsOver,frames={}}
    Require(_G,{"MouseIsOver"},"Native mouse-over")
    lease.guard=function(frame,top,bottom,left,right)
        local record=lease.frames[frame]
        if state.active and record and top==45 and bottom==-10 and left==-5 and right==5 and record.tabOptions.tabHeight>0 then
            top=record.tabOptions.tabHeight+math.max(0,record.tabOptions.tabOffsetY)
        end
        if right~=nil then return lease.original(frame,top,bottom,left,right) end
        if left~=nil then return lease.original(frame,top,bottom,left) end
        if bottom~=nil then return lease.original(frame,top,bottom) end
        if top~=nil then return lease.original(frame,top) end
        return lease.original(frame)
    end
    MouseIsOver=lease.guard;mouseOverLease=lease
end
local function ApplyWindow(record, options)
    ApplyMessageText(record, options)
    local tab = Global(record.name .. "Tab")
    if tab then
        if record.tab and record.tab ~= tab then error(record.name .. " tab was replaced.") end
        record.tab = tab
        record.tabOptions=options
        if mouseOverLease then mouseOverLease.frames[record.frame]=record end
        TabVisibility(record,tab,options)
        if not record.tabRecord then
            Require(tab,{"GetHeight","SetHeight"},record.name.."Tab")
            record.tabRecord={frame=tab,name=record.name.."Tab",leases={},textures={},buttons={}}
        end
        Property(record.tabRecord,"height",ReadHeight,SetHeight,options.tabHeight>0 and options.tabHeight or nil)
        if options.tabHeight>0 or options.tabWidth>0 then Require(tab,{"GetHitRectInsets","SetHitRectInsets"},record.name.."Tab") end
        Property(record.tabRecord,"hitRect",ReadHitRect,SetHitRect,(options.tabHeight>0 or options.tabWidth>0) and {0,0,0,0} or nil)
        local label = Global(record.name .. "TabText") or type(tab.GetFontString) == "function" and tab:GetFontString()
        if label then
            if not record.tabText then record.tabText = NewRecord(label, record.name .. "TabText", true) end
            if record.tabText.frame ~= label then error(record.name .. " tab text was replaced.") end
            local native = record.tabText.leases.font and record.tabText.leases.font.original or ReadFont(label)
            local tabFont = options.tabFont == "inherit" and options.font or options.tabFont
            local tabSize = options.tabFontSize == -1 and options.fontSize or options.tabFontSize
            local tabOutline = options.tabFontOutline == "inherit" and options.fontOutline or options.tabFontOutline
            local fontChanged = Property(record.tabText, "font", ReadFont, SetFont,
                {tabFont == "native" and native[1] or fonts[tabFont], tabSize == 0 and native[2] or tabSize,
                    tabOutline == "native" and native[3] or tabOutline == "none" and "" or tabOutline})
            Shadow(record.tabText, options.tabShadowMode, options.tabShadowColor, options.tabShadowAlpha, options.tabShadowX, options.tabShadowY)
            TabColor(record, label, options)
            local docked = Enabled(record.frame.isDocked)
            if docked and options.tabWidth==0 then
                -- Native FCF_DockUpdate fits and caps docked tabs on every
                -- selection/resize. Preserve that single geometry owner.
                if fontChanged then state.dockChanged = true end
                if record.tabLayout then
                    local restored, reason, changed = ReleaseProperty(record.tabLayout, "geometry")
                    if not restored then error(reason) end
                    if changed then state.dockChanged=true end
                end
            else
                local resized=FitTab(record, tab, label,options)
                if docked and resized then state.dockChanged=true end
            end
            record.tabDocked = docked
            record.tabTitle = label:GetText()
        end
        TabAppearance(record, tab, options)
    end
    -- FCF_DockUpdate anchors secondary docked frames to DEFAULT_CHAT_FRAME.
    -- Keep their preferences durable, but let that native owner set geometry.
    local geometryOwner = not Enabled(record.frame.isDocked) or record.frame == Global("DEFAULT_CHAT_FRAME")
    if geometryOwner and options.width > 0 then Require(record.frame, {"GetWidth", "SetWidth"}, record.name) end
    if geometryOwner and options.height > 0 then Require(record.frame, {"GetHeight", "SetHeight"}, record.name) end
    local widthChanged = Property(record, "width", ReadWidth, SetWidth, geometryOwner and options.width > 0 and options.width or nil)
    local heightChanged = Property(record, "height", ReadHeight, SetHeight, geometryOwner and options.height > 0 and options.height or nil)
    if Enabled(record.frame.isDocked) and (widthChanged or heightChanged) then state.dockChanged = true end
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
local function InputAppearance(options)
    local record, frame = editRecord, editRecord.frame
    local style = options.borderStyle or (options.goldBorder and "project" or "native")
    local custom = style ~= "native" or options.backgroundAlpha >= 0
    if custom then
        if not record.inputRegions then
            Require(frame, {"GetRegions"}, "ChatFrameEditBox")
            local matched = {}
            -- The 1.12 template has Left/Right plus an unnamed middle texture.
            -- Match only its exact background artwork; the header stays native.
            local regions = {frame:GetRegions()}
            for _, region in ipairs(regions) do
                if type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" and
                    type(region.GetDrawLayer) == "function" and region:GetDrawLayer() == "BACKGROUND" and
                    type(region.GetTexture) == "function" then
                    local texture = region:GetTexture()
                    local name = region:GetName()
                    if name == "ChatFrameEditBoxLeft" and texture == "Interface\\ChatFrame\\UI-ChatInputBorder-Left" or
                        (name == "ChatFrameEditBoxRight" or name == nil) and texture == "Interface\\ChatFrame\\UI-ChatInputBorder-Right" then
                        table.insert(matched, region)
                    end
                end
            end
            if table.getn(matched) ~= 3 then
                error("Native chat input background artwork is unavailable or ambiguous.")
            end
            record.inputRegions = matched
        end
        if not record.surface then
            if type(UI.CreateContainer) ~= "function" or type(UI.SetProjectButtonOutline) ~= "function" then
                error("BootyLib project input surface is unavailable.")
            end
            record.surface = UI.CreateContainer(nil, frame)
        end
        if not record.surfaceReady then
            Require(record.surface, {"EnableMouse", "SetFrameStrata", "SetFrameLevel", "SetAllPoints"}, "Project input surface")
            Must(record.surface.EnableMouse, record.surface, false)
            Must(record.surface.SetFrameStrata, record.surface, frame:GetFrameStrata())
            Must(record.surface.SetFrameLevel, record.surface, math.max(0, frame:GetFrameLevel() - 1))
            Must(record.surface.SetAllPoints, record.surface, frame)
            record.surfaceReady = true
        end
        local color = options.backgroundColor
        -- A plain pooled backdrop avoids a second skinned EditBox whose
        -- nine-slice can cover the independently chosen input outline.
        Must(record.surface.SetBackdrop, record.surface, standardBorders[style] or standardBorders.none)
        Must(record.surface.SetBackdropColor, record.surface, color[1], color[2], color[3], math.max(0, options.backgroundAlpha))
        local borderColor = options.borderColor or {1, 0.78, 0.2}
        Must(record.surface.SetBackdropBorderColor, record.surface, borderColor[1], borderColor[2], borderColor[3],
            (style == "dialog" or style == "tooltip") and (options.borderAlpha or 1) or 0)
        if style == "project" then
            if frame.bootyProjectOutline and frame.bootyProjectOutline ~= record.inputOutline then error("Native chat input border has another owner.") end
            if record.inputOutline and not frame.bootyProjectOutline then frame.bootyProjectOutline = record.inputOutline end
            local applied, reason = Call(UI.SetProjectButtonOutline, frame, true, nil, borderColor)
            record.inputOutline = frame.bootyProjectOutline
            if not applied then error(tostring(reason)) end
            if reason == false or not record.inputOutline then error("Project chat input border was declined.") end
            Must(record.inputOutline.SetBackdropBorderColor, record.inputOutline, borderColor[1], borderColor[2], borderColor[3], options.borderAlpha or 1)
            if not Enabled(record.inputOutline:IsShown()) then error("Project chat input border visibility was declined.") end
        elseif record.inputOutline then Must(record.inputOutline.Hide, record.inputOutline) end
        Must(record.surface.Show, record.surface)
        for index, region in ipairs(record.inputRegions) do
            local name = "InputBackground" .. index
            if style ~= "native" or options.backgroundAlpha >= 0 then Texture(record, name, true, region)
            else local restored, reason = ReleaseTexture(record, name); if not restored then error(reason) end end
        end
    else
        if record.surface then Must(record.surface.Hide, record.surface) end
        if record.inputOutline then Must(record.inputOutline.Hide, record.inputOutline) end
        for name in pairs(record.textures) do
            local restored, reason = ReleaseTexture(record, name)
            if not restored then error(reason) end
        end
    end
end
local function ApplyEditbox(options)
    local frame = Global("ChatFrameEditBox")
    if not frame then error("Native ChatFrameEditBox is unavailable.") end
    if editRecord and editRecord.frame ~= frame then error("Native ChatFrameEditBox was replaced.") end
    if not editRecord then editRecord = NewRecord(frame, "ChatFrameEditBox") end
    local customFont = options.font ~= "native" or options.fontSize > 0 or options.fontOutline ~= "native"
    if customFont then
        local original = editRecord.leases.font and editRecord.leases.font.original or ReadFont(frame)
        Property(editRecord, "font", ReadFont, SetFont, {options.font == "native" and original[1] or fonts[options.font],
            options.fontSize == 0 and original[2] or options.fontSize,
            options.fontOutline == "native" and original[3] or options.fontOutline == "none" and "" or options.fontOutline})
    else Property(editRecord, "font", ReadFont, SetFont, nil) end
    Shadow(editRecord, options.shadowMode, options.shadowColor, options.shadowAlpha, options.shadowX, options.shadowY)
    if options.height > 0 or options.marginTop+options.marginBottom>0 then
        Require(frame, {"GetHeight", "SetHeight"}, "ChatFrameEditBox")
        local _, size = frame:GetFont()
        local nativeHeight=editRecord.leases.height and editRecord.leases.height.original or frame:GetHeight()
        Property(editRecord, "height", ReadHeight, SetHeight, math.max(options.height>0 and options.height or nativeHeight, size + 8+options.marginTop+options.marginBottom))
    else Property(editRecord, "height", ReadHeight, SetHeight, nil) end
    Require(frame, {"GetAltArrowKeyMode", "SetAltArrowKeyMode"}, "ChatFrameEditBox")
    Property(editRecord, "arrows", ReadArrows, SetArrows, not options.arrowKeys)
    local width = options.width or 0
    local freeWidth=options.position=="free" and (editRecord.leases.width and editRecord.leases.width.original or frame:GetWidth()) or nil
    if options.position ~= "native" or width > 0 then
        Require(frame, {"GetNumPoints", "GetPoint", "ClearAllPoints", "SetPoint"}, "ChatFrameEditBox")
        -- Blizzard 1.12 has one shared editbox statically attached to frame 1.
        -- Its input/header/send scripts and chatFrame reference stay intact.
        local owner = Global("ChatFrame1")
        local top = options.position == "top"
        local points
        if options.position == "free" then
            points={{"CENTER",UIParent,"CENTER",options.offsetX,options.offsetY}}
        elseif options.position == "native" then
            local native = editRecord.leases.points and editRecord.leases.points.original or ReadPoints(frame)
            if not native[1] then error("Native chat input anchor is unavailable.") end
            points = CopyPoints({native[1]})
        elseif top then
            points = {{"BOTTOMLEFT", owner, "TOPLEFT", -5, options.gap}}
            if width == 0 then points[2] = {"BOTTOMRIGHT", owner, "TOPRIGHT", 5, options.gap} end
        else
            points = {{"TOPLEFT", owner, "BOTTOMLEFT", -5, -options.gap}}
            if width == 0 then points[2] = {"TOPRIGHT", owner, "BOTTOMRIGHT", 5, -options.gap} end
        end
        Property(editRecord, "points", ReadPoints, SetPoints, points)
    else Property(editRecord, "points", ReadPoints, SetPoints, nil) end
    if width > 0 then Require(frame, {"GetWidth", "SetWidth"}, "ChatFrameEditBox") end
    Property(editRecord, "width", ReadWidth, SetWidth, width > 0 and width or freeWidth)
    local header = Global("ChatFrameEditBoxHeader")
    if header then
        if not editRecord.header then editRecord.header = NewRecord(header, "ChatFrameEditBoxHeader", true) end
        if editRecord.header.frame ~= header then error("Native chat input header was replaced.") end
        local headerChanged
        if customFont then
            local original = editRecord.header.leases.font and editRecord.header.leases.font.original or ReadFont(header)
            local desired = {options.font == "native" and original[1] or fonts[options.font],
                options.fontSize == 0 and original[2] or options.fontSize,
                options.fontOutline == "native" and original[3] or options.fontOutline == "none" and "" or options.fontOutline}
            if not PropertyEqual("font", ReadFont(header), desired) then editRecord.headerDirty = true end
            headerChanged = Property(editRecord.header, "font", ReadFont, SetFont, desired)
        else
            if editRecord.header.leases.font then editRecord.headerDirty = true end
            headerChanged = Property(editRecord.header, "font", ReadFont, SetFont, nil)
        end
        Shadow(editRecord.header, options.shadowMode, options.shadowColor, options.shadowAlpha, options.shadowX, options.shadowY)
        if headerChanged then
            editRecord.headerDirty = true
            if type(ChatEdit_UpdateHeader) ~= "function" then error("Native chat input header layout is unavailable.") end
            -- The existing helper measures the current destination caption;
            -- input text, caret, channel and all input scripts remain native.
            Must(ChatEdit_UpdateHeader, frame)
        end
    end
    InputAppearance(options)
    if editRecord.header then
        local desired
        if options.marginLeft~=0 or options.marginTop~=options.marginBottom then
            local native=editRecord.header.leases.points and editRecord.header.leases.points.original or ReadPoints(editRecord.header.frame)
            desired=CopyPoints(native)
            for _,point in ipairs(desired) do point[4]=point[4]+options.marginLeft;point[5]=point[5]+(options.marginBottom-options.marginTop)/2 end
        end
        Property(editRecord.header,"points",ReadPoints,SetPoints,desired)
    end
end
local function ReleaseInputInsets()
    local lease=editRecord and editRecord.inputInsets
    if not lease then return true end
    lease.enabled=false
    if lease.frame.SetTextInsets==lease.guard then Must(lease.setter,lease.frame,unpack(lease.native)) end
    local ok,reason=ReleaseSlot(lease.frame,"SetTextInsets",lease.setter,lease.guard)
    if ok then editRecord.inputInsets=nil end
    return ok,reason
end
local function InputInsets(options)
    local frame=editRecord.frame
    local values={options.marginLeft,options.marginRight,options.marginTop,options.marginBottom}
    if values[1]+values[2]+values[3]+values[4]==0 then
        local ok,reason=ReleaseInputInsets();if not ok then error(reason) end;return
    end
    Require(frame,{"GetTextInsets","SetTextInsets"},"Chat input padding")
    local lease=editRecord.inputInsets
    if not lease then
        lease={frame=frame,setter=frame.SetTextInsets,native={frame:GetTextInsets()},enabled=true}
        editRecord.inputInsets=lease
        lease.guard=function(owner,l,r,t,b)
            if not lease.enabled or owner~=frame then return lease.setter(owner,l,r,t,b) end
            lease.native[1],lease.native[2],lease.native[3],lease.native[4]=l,r,t,b
            local margins=lease.margins
            local ok,reason=Call(lease.setter,owner,l+margins[1],r+margins[2],t+margins[3],b+margins[4])
            if not ok or reason==false then ReportFailure(ok and "Chat input margins were declined." or reason) end
            local al,ar,at,ab=owner:GetTextInsets()
            if not Equal(al,l+margins[1],0.001) or not Equal(ar,r+margins[2],0.001) or
                not Equal(at,t+margins[3],0.001) or not Equal(ab,b+margins[4],0.001) then ReportFailure("Chat input margins write was declined.") end
        end
        frame.SetTextInsets=lease.guard
    elseif frame.SetTextInsets~=lease.guard then error("Chat input margins have another owner.") end
    lease.margins=values
    local original=lease.native
    Must(lease.setter,frame,original[1]+values[1],original[2]+values[2],original[3]+values[3],original[4]+values[4])
    if not Equal({frame:GetTextInsets()},{original[1]+values[1],original[2]+values[2],original[3]+values[3],original[4]+values[4]},0.001) then error("Chat input margins write was declined.") end
end
local function CancelInputDrag()
    if not editRecord or not editRecord.inputDragging then return end
    Must(editRecord.frame.StopMovingOrSizing,editRecord.frame);editRecord.inputDragging=nil
end
local function ReadMovable(frame) return Enabled(frame:IsMovable()) end
local function SetMovable(frame,value) return frame:SetMovable(value and 1 or nil) end
function Native.SetInputEditing(value,save)
    if type(value)~="boolean" then return false,"Choose input editing on or off." end
    if not state.active then if not value then return true end;return false,"Enable BootyChat before moving its input." end
    local ok,reason=Call(function()
        CancelInputDrag()
        if not value then
            state.inputEditing=false
            if editRecord.inputHandle then Must(editRecord.inputHandle.Hide,editRecord.inputHandle) end
            if editRecord.inputEditingShown==false then Must(editRecord.frame.Hide,editRecord.frame) end
            editRecord.inputEditingShown=nil
            Property(editRecord,"movable",ReadMovable,SetMovable,nil);return
        end
        Require(editRecord.frame,{"IsMovable","SetMovable","StartMoving","StopMovingOrSizing","GetCenter","GetEffectiveScale"},"Chat input movement")
        if not state.inputEditing then editRecord.inputEditingShown=Enabled(editRecord.frame:IsShown()) end
        Property(editRecord,"movable",ReadMovable,SetMovable,true)
        if not editRecord.inputHandle then
            local handle=UI.CreateControl(nil,editRecord.frame);editRecord.inputHandle=handle
            Must(handle.EnableMouse,handle,true);Must(handle.SetAllPoints,handle,editRecord.frame)
            Must(handle.SetFrameLevel,handle,editRecord.frame:GetFrameLevel()+5)
            Must(UI.SetProjectButtonOutline,handle,true)
            handle:RegisterForDrag("LeftButton")
            handle:SetScript("OnDragStart",function()
                if not state.inputEditing then return end
                local started,failure=Call(editRecord.frame.StartMoving,editRecord.frame)
                if not started then ReportFailure(failure) end
                editRecord.inputDragging=true
            end)
            local function Finish()
                if not editRecord.inputDragging then return end
                local finished,failure=Call(function()
                    CancelInputDrag()
                    local x,y=editRecord.frame:GetCenter();local px,py=UIParent:GetCenter()
                    assert(x and y and px and py,"Chat input position is unavailable.")
                    local scale=editRecord.frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
                    local saved,error=editRecord.inputSave(math.floor(x*scale-px+0.5),math.floor(y*scale-py+0.5))
                    assert(saved,error)
                end)
                if not finished then ReportFailure(failure) end
            end
            handle:SetScript("OnDragStop",Finish);handle:SetScript("OnMouseUp",Finish)
            handle:SetScript("OnHide",function() local stopped,failure=Call(CancelInputDrag);if not stopped then ReportFailure(failure) end end)
        end
        editRecord.inputSave=assert(save,"Input position callback is required.")
        state.inputEditing=true;Must(editRecord.frame.Show,editRecord.frame);Must(editRecord.inputHandle.Show,editRecord.inputHandle)
    end)
    if not ok then
        local _,failure=Call(ReportFailure,reason)
        return false,tostring(failure)
    end
    return true
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
    CancelInputDrag()
    local inputOptions=Configuration.ResolveEditbox(store)
    ApplyEditbox(inputOptions)
    InputInsets(inputOptions)
    if state.dockChanged then
        if type(FCF_DockUpdate) ~= "function" then error("Native chat docking layout is unavailable.") end
        state.dockDirty = true
        Must(FCF_DockUpdate)
        state.dockChanged = nil
    end
end
local function Disable(record)
    if record.wheel then record.wheel.enabled = false end
    for _, lease in pairs(record.textures) do lease.enabled = false end
    for _, lease in pairs(record.buttons) do lease.enabled = false end
    if record.tabColor then record.tabColor.enabled = false end
    if record.tabColorHooks then for _, lease in pairs(record.tabColorHooks) do lease.enabled = false end end
    if record.tabPosition then record.tabPosition.enabled = false end
end
local function Attempt(callback, ...)
    local ran, ok, reason = Call(callback, unpack(arg))
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
    local hooksOK, hooksReason = Attempt(ReleaseTabHooks, record)
    local visibleOK,visibleReason=Attempt(ReleaseTabVisibility,record)
    if not visibleOK then failure=failure or visibleReason end
    local colorOK, colorReason = Attempt(ReleaseTabColor, record)
    if not hooksOK or not colorOK then failure = failure or hooksReason or colorReason end
    local positionOK, positionReason = Attempt(ReleaseTabPosition, record)
    if not positionOK then failure = failure or positionReason end
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
    if record.inputOutline then
        local ok, reason = HideSurface(record.inputOutline)
        if not ok then failure = failure or reason
        elseif record.frame.bootyProjectOutline == record.inputOutline then record.frame.bootyProjectOutline = nil end
    end
    if record.tabBorder then
        local ok, reason = HideSurface(record.tabBorder)
        if not ok then
            failure = failure or reason
        elseif record.tab and record.tab.openBorder == record.tabBorder then record.tab.openBorder = nil end
    end
    if record.tabSurface then
        local ok, reason = HideSurface(record.tabSurface)
        if not ok then failure = failure or reason end
    end
    if record.tabBackground then local ok,reason=HideSurface(record.tabBackground);if not ok then failure=failure or reason end end
    if record.tabRecord then local ok,reason=Attempt(Release,record.tabRecord);if not ok then failure=failure or reason end end
    if record.tabArt then for _,art in pairs(record.tabArt) do local ok,reason=Attempt(Release,art);if not ok then failure=failure or reason end end end
    if record.tabText then local ok, reason = Attempt(Release, record.tabText); if not ok then failure = failure or reason end end
    if record.tabLayout then local ok, reason = Attempt(Release, record.tabLayout); if not ok then failure = failure or reason end end
    if record.header then local ok, reason = Attempt(Release, record.header); if not ok then failure = failure or reason end end
    return failure == nil, failure
end
function Native.Stop()
    state.active = false
    state.dockChanged = nil
    state.deferredWheels = 0
    for _, record in pairs(records) do Disable(record); record.wheelDeferred = nil end
    if editRecord then Disable(editRecord) end
    local failure
    state.inputEditing=false
    local inputOK,inputReason=Call(CancelInputDrag)
    if not inputOK then failure=inputReason end
    local insetsOK,insetsReason=Attempt(ReleaseInputInsets)
    if not insetsOK then failure=failure or insetsReason end
    if editRecord and editRecord.inputHandle then local ok,reason=HideSurface(editRecord.inputHandle);if not ok then failure=failure or reason end end
    if editRecord and editRecord.inputEditingShown==false then local ok,reason=Call(editRecord.frame.Hide,editRecord.frame);if not ok then failure=failure or reason end end
    if editRecord then editRecord.inputEditingShown=nil end
    if mouseOverLease then
        local ok,reason=ReleaseSlot(_G,"MouseIsOver",mouseOverLease.original,mouseOverLease.guard)
        if ok then mouseOverLease=nil else failure=reason end
    end
    for _,record in pairs(records) do
        local ok,reason=Call(FinishTabMovement,record)
        if not ok then failure=failure or reason end
    end
    if tabMovementLease then
        local ok,reason=ReleaseSlot(_G,"FCF_Tab_OnClick",tabMovementLease.original,tabMovementLease.guard)
        if ok then tabMovementLease=nil else failure=failure or reason end
    end
    if tabResizeLease then
        local ok,reason=ReleaseSlot(_G,"PanelTemplates_TabResize",tabResizeLease.original,tabResizeLease.guard)
        if ok then tabResizeLease=nil else failure=reason end
    end
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
        InstallTabResize()
        InstallTabMovement()
        InstallTabHover()
        if refresh then
            for id, record in pairs(records) do
                local lease = record.leases.font
                if lease then
                    local current = ReadFont(record.frame)
                    if not PropertyEqual("font", current, lease.applied) then
                        local _, nativeSize = GetChatWindowInfo(id)
                        if FontPath(current[1]) ~= FontPath(lease.applied[1]) or FontFlags(current[3]) ~= FontFlags(lease.applied[3]) or
                            not Equal(current[2], nativeSize, 0.001) or not nativeSize or nativeSize <= 0 then
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
                        if not PropertyEqual(key, current, geometry.applied) then geometry.original, geometry.applied = current, current end
                    end
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
