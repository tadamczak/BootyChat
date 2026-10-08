local Chat = BootyChat
local UI = Chat.UI.Components
local Overview = {}
Chat.Modules.Overview = Overview

function Overview.Create(parent, host)
    local frame = UI.CreateContainer(nil, parent)
    frame:SetAllPoints(parent)
    local canvas = UI.CreateResponsiveCanvas(frame, "BootyChatOverviewScroll")
    local view = {frame = frame, canvas = canvas}
    local title = UI.CreateHeading(canvas, "Native chat", 2, "gold")
    local status = UI.CreateComponentLabel(canvas, "", "white")
    status:SetJustifyH("LEFT"); status:SetJustifyV("TOP")
    local help = UI.CreateComponentLabel(canvas,
        "Create, rename and filter your tabs through the native right-click menu. Unlock and drag a native tab to move its window; use its native resize handle to resize it.\n\nOpen Settings for common appearance, individual windows and the shared input box. Text, shadows, fading, backgrounds and tabs have separate groups. Window numbers follow the native chat slots. A zero width or height keeps the native size.\n\nUse the shared Profile page to save and load your appearance, including individual window overrides. Reset window restores the selected window's inheritance. Disable customizations to return to the native appearance. Channels, messages and item links stay in the native chat.", "white")
    help:SetJustifyH("LEFT"); help:SetJustifyV("TOP")
    local settings = UI.CreateButton(canvas, nil, "Settings", 104, 24)
    local enabled = UI.CreateButton(canvas, nil, "Disable", 104, 24)
    local reset = UI.CreateButton(canvas, nil, "Reset window", 120, 24)
    UI.StyleActionButton(settings); UI.StyleActionButton(enabled); UI.StyleActionButton(reset)
    local choices = {}
    for id = 1, Chat.Services.Configuration.WindowCount() do choices[id] = {value = id, text = Chat.Services.Configuration.WindowLabel(id)} end
    view.selectedWindow = 1
    local choiceLabel, selection = UI.CreateChoiceField({parent = canvas, x = 0, y = 0,
        label = "Native window", initialText = "Window 1", width = 200, height = 220, firstY = -7, step = 20,
        buttonOffset = 120, labelValue = true, choices = choices,
        getValue = function() return view.selectedWindow end,
        onSelect = function(id) view.selectedWindow = id end})
    local actions = {settings, enabled, reset}
    settings:SetScript("OnClick", function() host.OpenSettings() end)
    enabled:SetScript("OnClick", function()
        local store = Chat.Database.Ensure()
        if not store then return end
        local ok, failure = Chat.Core.Runtime.SetEnabled(not store.enabled)
        if not ok then host.Print(failure) end
        view:Refresh()
    end)
    reset:SetScript("OnClick", function()
        local ok, failure = Chat.Core.Runtime.ResetWindow(view.selectedWindow)
        if not ok then host.Print(failure) end
        view:Refresh()
    end)
    local function Measure(width)
        local available = math.max(1, width - 32)
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16); title:SetWidth(available)
        status:ClearAllPoints(); status:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -48); status:SetWidth(available)
        local statusHeight = UI.MeasureTextHeight(status, available)
        status:SetHeight(statusHeight)
        local top = 58 + statusHeight
        help:ClearAllPoints(); help:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -top); help:SetWidth(available)
        local helpHeight = UI.MeasureTextHeight(help, available)
        help:SetHeight(helpHeight); top = top + helpHeight + 18
        choiceLabel:ClearAllPoints(); choiceLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -top)
        selection:ClearAllPoints(); selection:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -(top + 20))
        selection:SetWidth(math.min(200, available))
        return UI.LayoutFlow(canvas, actions, 16, top + 58, available, 8) + 16
    end
    function view:OnResize()
        if not frame:IsVisible() then return end
        local width, height = UI.GetFrameSpan(parent)
        UI.LayoutResponsiveCanvas(canvas, Measure, nil, math.max(1, width), math.max(1, height))
    end
    function view:Refresh()
        if not frame:IsVisible() then return end
        local runtime = Chat.Core.Runtime.GetState()
        local native = Chat.Modules.NativeChat.GetState()
        local store, failure = Chat.Database.Ensure()
        local message = native.active and "Chat customizations are active." or "Native chat customizations are disabled."
        if native.active and native.deferredWheels > 0 then
            message = message .. " Another addon controls scrolling in " .. native.deferredWheels .. " window(s). Disable and enable BootyChat to apply its scrolling again."
        end
        status:SetText(runtime.failure or failure or message)
        enabled:SetText(store and store.enabled and "Disable" or "Enable")
        self:OnResize()
    end
    function view:Show() frame:Show(); self:Refresh(); return true end
    function view:Hide() selection.panel:Hide(); frame:Hide(); return true end
    frame:SetScript("OnHide", function() selection.panel:Hide() end)
    frame:Hide()
    view.status, view.settingsButton, view.enabledButton, view.resetButton = status, settings, enabled, reset
    return view
end
