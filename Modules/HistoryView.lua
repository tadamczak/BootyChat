local Chat = BootyChat
local UI = Chat.UI.Components
local HistoryView = {}
Chat.Modules.HistoryView = HistoryView
local ROW_STEP, PAGE_SIZE, COPY_LIMIT = 22, 12, 65535

local function Escape(text) return string.gsub(text or "", "|", "||") end
local function PreviewText(text)
    local plain = Chat.Services.History.PlainText(text)
    if string.len(plain) > 180 then
        local stop = 180
        local byte = string.byte(plain, stop + 1)
        while stop > 0 and byte and byte >= 128 and byte <= 191 do
            stop = stop - 1; byte = string.byte(plain, stop + 1)
        end
        plain = string.sub(plain, 1, stop) .. "..."
    end
    return Escape(plain)
end
local function Enable(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end
local function Action(view, label, width, callback, parent, icon)
    local button = UI.CreateButton(parent or view.canvas, nil, label, width, 26)
    UI.StyleActionButton(button)
    button.historyWidth = width
    if icon then UI.SetActionButtonIcon(button, icon) end
    button.historyView = view; button:SetScript("OnClick", callback)
    return button
end
local function Settings() this.historyView.host.OpenSettings() end
local function ToggleEnabled()
    local view = this.historyView
    local store, failure = Chat.Database.Ensure()
    if not store then view:Message(failure, true); return end
    local ok, reason = Chat.Core.Runtime.SetEnabled(not store.enabled)
    if not ok then view:Message(reason, true) else view:Refresh() end
end
local function ToggleLive() local view = this.historyView; view:SetLive(not view.live) end
local function ResetAppearance() this.historyView:OpenResetMenu() end
local function Search() this.historyView:Search() end
local function ClearSearch() this.historyView:ClearSearch() end
local function Refresh() this.historyView:Refresh() end
local function Previous()
    local view = this.historyView
    local offset = math.max(0, view.offset - PAGE_SIZE)
    view.live = offset == 0; view:RunQuery(offset)
end
local function Next() local view = this.historyView; view.live = false; view:RunQuery(view.offset + PAGE_SIZE) end
local function CopySelected() this.historyView:CopySelected() end
local function CopyPage() this.historyView:CopyPage() end
local function ConfirmClear() this.historyView:ConfirmClear() end
local function RestoreWidths(controls)
    for _, control in ipairs(controls) do
        if control.historyWidth then control:SetWidth(control.historyWidth) end
    end
end
local function SelectRow() this.historyView:SelectRecord(this.record) end
local function OnScroll()
    if this.historyView.rendering then return end
    FauxScrollFrame_OnVerticalScroll(ROW_STEP, this.refreshCallback)
end
local function FlushHistory()
    local view = this.historyView
    this:SetScript("OnUpdate", nil); view.pendingRefresh = nil
    if view.frame:IsVisible() and view.live and view.offset == 0 and not view.queryFailed
        and not (view.copyPopup and view.copyPopup:IsVisible()) then view:RunQuery(0, true) end
end
local function OnHistoryChanged(view)
    if not view.frame:IsVisible() then return end
    local wasDirty = view.dirty
    view.dirty = true
    if view.refreshing then view.changedDuringRefresh = true; return end
    if view.queryFailed then return end
    if not view:QueueRefresh() and not wasDirty then view:Message("New messages.") end
end
local function PreviewWheel()
    if arg1 > 0 then this:ScrollUp() elseif arg1 < 0 then this:ScrollDown() end
end
local function PreviewLink()
    if type(ChatFrame_OnHyperlinkShow) == "function" then
        ChatFrame_OnHyperlinkShow(arg1, arg2, arg3)
    else this.historyView:Message("Native link handling is unavailable.", true) end
end
local function CloseCopy() this.historyPopup:Hide() end

function HistoryView.Create(parent, host, onBack, layoutOwner)
    local frame = UI.CreateContainer(nil, parent)
    frame:SetAllPoints(parent)
    local canvas = UI.CreateResponsiveCanvas(frame, "BootyChatHistoryCanvas")
    local view = {frame = frame, canvas = canvas, host = host, onBack = onBack, layoutOwner = layoutOwner or parent,
        records = {}, rowText = {}, rowTime = {}, offset = 0, total = 0, query = "", dirty = false, live = true}
    frame.historyView = view
    local title = UI.CreateHeading(canvas, "Chat history", 1, "gold", "archive")
    title:SetJustifyH("LEFT"); view.title = title
    view.actionPanel = UI.CreateToolbarSurface(canvas, true, true)
    view.filterPanel = UI.CreateToolbarSurface(canvas, false, true)
    UI.AddToolbarBackground(view.actionPanel, 0.42)
    view.settingsButton = Action(view, "Settings", 104, Settings, view.actionPanel, "settings")
    view.enabledButton = Action(view, "Disable", 96, ToggleEnabled, view.actionPanel, "disable")
    view.resetButton = Action(view, "Reset appearance", 148, ResetAppearance, view.actionPanel, "reset")
    view.liveButton = Action(view, "Pause", 92, ToggleLive, view.actionPanel, "disable")
    local choices = {{value = 0, text = "All windows"}}
    for id = 1, Chat.Services.Configuration.WindowCount() do
        table.insert(choices, {value = id, text = Chat.Services.Configuration.WindowLabel(id)})
    end
    local choiceLabel, choice = UI.CreateChoiceField({parent = view.filterPanel, x = 0, y = 0, label = "", initialText = "All windows",
        width = 160, height = 14 + table.getn(choices) * 20, firstY = -7, step = 20, buttonOffset = 0, choices = choices,
        getValue = function() return view.windowId or 0 end,
        onSelect = function(id)
            if id == 0 then view.windowId = nil else view.windowId = id end
            view.live = true
            view:RunQuery(0)
        end})
    choiceLabel:Hide(); view.windowChoice, view.windowLabel = choice, choiceLabel
    view.searchBox = UI.CreateFramedEditBox(view.filterPanel, nil, 160)
    view.searchBox:SetMaxLetters(256); view.searchBox.historyView = view
    UI.AttachPlaceholder(view.searchBox, "Search visible text...")
    view.searchBox:SetScript("OnEnterPressed", Search)
    view.searchButton = Action(view, "Search", 72, Search, view.filterPanel)
    view.clearSearchButton = Action(view, "Clear query", 92, ClearSearch, view.filterPanel)
    view.refreshButton = Action(view, "Refresh", 100, Refresh, view.actionPanel, "refresh")
    view.copySelectedButton = Action(view, "Copy selected", 112, CopySelected, view.actionPanel)
    view.copyPageButton = Action(view, "Copy page", 96, CopyPage, view.actionPanel)
    view.clearButton = Action(view, "Clear history", 108, ConfirmClear, view.actionPanel)
    view.previousButton = Action(view, "Previous", 64, Previous)
    view.nextButton = Action(view, "Next", 64, Next)
    view.pageLabel = UI.CreateComponentLabel(canvas, "", "white")
    view.status = UI.CreateComponentLabel(canvas, "", "white")
    view.status:SetJustifyH("LEFT"); view.status:SetJustifyV("TOP")
    view.filters = {choice, view.searchBox, view.searchButton, view.clearSearchButton}
    view.actions = {view.settingsButton, view.enabledButton, view.resetButton, view.liveButton,
        view.refreshButton, view.copySelectedButton, view.copyPageButton, view.clearButton}
    view.pager = {view.previousButton, view.nextButton, view.pageLabel}
    view.table = UI.Table.Create({parent = canvas, name = "BootyChatHistoryScroll", x = 8, width = 300,
        scrollTop = -160, scrollHeight = 100, rowTop = -160, rowCount = PAGE_SIZE, rowStep = ROW_STEP, rowHeight = 20,
        onScroll = OnScroll, refresh = function() view:RenderRows() end,
        columns = {{key = "time", side = "LEFT", x = 4, width = 98}, {key = "message", side = "LEFT", x = 104, width = 190}},
        bindRow = function(row) row.historyView = view; row:SetScript("OnClick", SelectRow) end})
    view.table.scroll.historyView = view; view.rows = view.table.rows
    view.previewLabel = UI.CreateComponentLabel(canvas, "Select a message", "gold")
    view.previewPanel = UI.CreateContainer(nil, canvas)
    UI.Window.ApplyProjectSurface(view.previewPanel)
    view.preview = UI.CreateMessageFrame(nil, view.previewPanel)
    view.preview.historyView = view
    view.preview:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    view.preview:SetJustifyH("LEFT"); view.preview:SetFading(false)
    -- A bounded message may contain 4096 newline bytes; do not trim its preview.
    view.preview:SetMaxLines(4097); view.preview:EnableMouse(true); view.preview:EnableMouseWheel(true)
    view.preview:SetScript("OnHyperlinkClick", PreviewLink); view.preview:SetScript("OnMouseWheel", PreviewWheel)

    function view:Message(message, failure)
        if failure then
            self.queryFailed = true; self.dirty = true; self.pendingRefresh = nil
            frame:SetScript("OnUpdate", nil)
        end
        if failure and host.Print then host.Print(message) end
        self.status:SetText(Escape(message))
        if message ~= "" then self.status:Show() else self.status:Hide() end
        if not self.refreshing then
            local laidOut, reason = pcall(self.OnResize, self)
            if not laidOut then
                self.rendering = nil; self.queryFailed = true; self.dirty = true; self.pendingRefresh = nil
                frame:SetScript("OnUpdate", nil)
                self.status:SetText(Escape(tostring(message) .. " History layout: " .. tostring(reason)))
                self.status:Show(); self.status:SetHeight(28)
                if host.Print then host.Print("Chat history layout: " .. tostring(reason)) end
            end
        end
    end
    function view:QueueRefresh()
        if not frame:IsVisible() or not self.live or self.offset ~= 0 or self.queryFailed
            or self.refreshing or self.copyPopup and self.copyPopup:IsVisible() then return false end
        if not self.pendingRefresh then self.pendingRefresh = true; frame:SetScript("OnUpdate", FlushHistory) end
        return true
    end
    function view:SetLive(active)
        self.live = active
        if active then return self:RunQuery(0) end
        frame:SetScript("OnUpdate", nil); self.pendingRefresh = nil
        self.liveButton:SetText("Live"); UI.SetActionButtonIcon(self.liveButton, "enable")
        return true
    end
    local function ResetEntry(id)
        return {text = Chat.Services.Configuration.WindowLabel(id), action = function()
            local ok, failure = Chat.Core.Runtime.ResetWindow(id)
            if not ok then view:Message(failure, true) else view:Refresh() end
        end}
    end
    function view:OpenResetMenu()
        if not self.resetMenu then
            self.resetMenu = UI.CreateCascadingMenu(function(action) if type(action) == "function" then action() end end)
            self.resetEntries = {}
            for id = 1, Chat.Services.Configuration.WindowCount() do self.resetEntries[id] = ResetEntry(id) end
        end
        if self.resetMenu.anchor then self.resetMenu:Close(); return end
        for id, entry in ipairs(self.resetEntries) do entry.text = Chat.Services.Configuration.WindowLabel(id) end
        self.resetMenu:Open(self.resetButton, self.resetEntries)
    end
    function view:SelectRecord(record)
        self.selectedRecord = record
        self.preview:Clear()
        if record then
            self.previewLabel:SetText(Chat.Services.History.FormatTime(record.at) .. " - Window " .. record.windowId)
            if record.colorId ~= nil then self.preview:AddMessage(record.text, record.r, record.g, record.b, record.colorId)
            else self.preview:AddMessage(record.text, record.r, record.g, record.b) end
            self.preview:ScrollToTop()
        else self.previewLabel:SetText("Select a message") end
        Enable(self.copySelectedButton, record ~= nil)
        self:RenderRows()
    end
    function view:RenderRows()
        if not frame:IsVisible() or not self.resultTop or self.rendering then return end
        self.rendering = true
        local scrollOffset, visible, width = UI.Table.LayoutViewport(self.table.scroll, canvas, 8, self.resultTop,
            self.resultWidth, self.resultHeight, table.getn(self.records), ROW_STEP, PAGE_SIZE)
        self.table.resolvedWidth, self.table.visibleRows, self.table.offset = width, visible, scrollOffset
        for index = 1, PAGE_SIZE do
            local row, record = self.rows[index], self.records[scrollOffset + index]
            if record and index <= visible then
                row.record = record; row:ClearAllPoints(); row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -(self.resultTop + (index - 1) * ROW_STEP))
                row:SetWidth(width); row:SetHeight(20)
                UI.Table.Cell(row.time, row, 4, 98, 20, self.rowTime[scrollOffset + index])
                if self.narrow then
                    row.time:Hide()
                    UI.Table.Cell(row.message, row, 4, math.max(1, width - 8), 20, self.rowText[scrollOffset + index])
                else
                    row.time:Show()
                    UI.Table.Cell(row.message, row, 104, math.max(1, width - 108), 20, self.rowText[scrollOffset + index])
                end
                row.message:SetTextColor(record.r, record.g, record.b)
                UI.StyleSelectableTableRow(row, math.mod(self.offset + scrollOffset + index, 2) == 0,
                    self.selectedRecord and self.selectedRecord.id == record.id)
                row:Show()
            else row.record = nil; row:Hide() end
        end
        self.rendering = false
    end
    local function MeasureBody(width, height)
        local self = view
        local available = math.max(1, width - 16)
        self.narrow = available < 240
        title:SetText(self.narrow and "History" or "Chat history")
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8); title:SetWidth(available); title:SetHeight(22)
        local choiceWidth = math.min(200, math.max(120, available * 0.38))
        choice:SetWidth(choiceWidth)
        self.searchBox:SetWidth(math.max(96, math.min(260, available - choiceWidth - 80)))
        -- Own authored widths so both installed and current shared skins can regrow.
        RestoreWidths(self.actions); RestoreWidths(self.filters); RestoreWidths(self.pager)
        local actionHeight = UI.LayoutFlow(self.actionPanel, self.actions, 8, 8, available, 8) + 8
        self.actionPanel:ClearAllPoints(); self.actionPanel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -38)
        self.actionPanel:SetWidth(width); self.actionPanel:SetHeight(actionHeight)
        local top = 38 + actionHeight
        local filterHeight = UI.LayoutFlow(self.filterPanel, self.filters, 8, 8, available, 8) + 8
        self.filterPanel:ClearAllPoints(); self.filterPanel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -top)
        self.filterPanel:SetWidth(width); self.filterPanel:SetHeight(filterHeight)
        top = top + filterHeight
        self.pageLabel:SetWidth(math.min(128, available)); self.pageLabel:SetHeight(18)
        top = UI.LayoutFlow(canvas, self.pager, 8, top + 8, available, 8)
        local statusHeight = 0
        if self.status:GetText() ~= "" then statusHeight = math.max(14, UI.MeasureTextHeight(self.status, available)); self.status:Show()
        else self.status:Hide() end
        self.status:ClearAllPoints(); self.status:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -(top + 8))
        self.status:SetWidth(available); self.status:SetHeight(statusHeight)
        self.resultTop, self.resultWidth = top + 12 + statusHeight, available
        local previewHeight = math.min(84, math.max(50, height * 0.18))
        local previewTop = height - 8 - previewHeight
        self.compact = previewTop - 24 - self.resultTop < ROW_STEP
        if self.compact then
            -- Whole-body scrolling owns overflow; the logical table has no second gutter.
            self.resultHeight = math.max(1, table.getn(self.records)) * ROW_STEP
            previewTop = self.resultTop + self.resultHeight + 24
        else self.resultHeight = previewTop - 24 - self.resultTop end
        self.previewLabel:ClearAllPoints(); self.previewLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -(previewTop - 18))
        self.previewLabel:SetWidth(available); self.previewLabel:SetHeight(16)
        self.previewPanel:ClearAllPoints(); self.previewPanel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -previewTop)
        self.previewPanel:SetWidth(available); self.previewPanel:SetHeight(previewHeight)
        self.preview:ClearAllPoints(); self.preview:SetPoint("TOPLEFT", self.previewPanel, "TOPLEFT", 6, -6)
        self.preview:SetWidth(math.max(1, available - 12)); self.preview:SetHeight(math.max(1, previewHeight - 12))
        self:RenderRows()
        self.contentWidth, self.contentHeight = width, math.max(height, previewTop + previewHeight + 8)
        return self.contentHeight
    end
    function view:OnResize(width, height)
        if not frame:IsVisible() then return end
        if not width or not height then width, height = UI.GetFrameSpan(self.layoutOwner) end
        width, height = math.max(1, width), math.max(1, height)
        self.layoutWidth, self.layoutHeight = width, height
        UI.LayoutResponsiveCanvas(canvas, MeasureBody, nil, width, height)
    end
    local function QueryPage(self, offset, preserveSelection)
        if not frame:IsVisible() then return false, "History view is hidden." end
        local service = Chat.Core.Runtime.GetHistory()
        if self.subscribed ~= service then
            if self.subscribed then self.subscribed:Unsubscribe(self); self.subscribed = nil end
            if service then
                local accepted, reason = service:Subscribe(self, OnHistoryChanged)
                if not accepted then return false, reason end
                self.subscribed = service
            end
        end
        if not service then return false, "Chat history is unavailable." end
        local page, failure = service:Query(self.windowId, self.query, offset or self.offset, PAGE_SIZE)
        if not page then return false, failure end
        local previousId = self.selectedRecord and self.selectedRecord.id
        self.records, self.offset, self.total, self.dirty = page.records, page.offset, page.total, false
        self.table.scroll.offset = 0
        if self.offset > 0 then self.live = false end
        self.liveButton:SetText(self.live and "Pause" or "Live")
        UI.SetActionButtonIcon(self.liveButton, self.live and "disable" or "enable")
        for index = 2, table.getn(choices) do
            local text = Chat.Services.Configuration.WindowLabel(index - 1)
            choices[index].text = text
            local option = choice.panel.options[index]
            option.choiceText = text; option:SetText(text)
        end
        choice:SetText(self.windowId and Chat.Services.Configuration.WindowLabel(self.windowId) or "All windows")
        local selected
        -- Parsing happens once per page refresh, never in the row-scroll callback.
        for index = 1, PAGE_SIZE do
            local record = self.records[index]
            if record then
                self.rowText[index] = PreviewText(record.text)
                self.rowTime[index] = Chat.Services.History.FormatTime(record.at) .. " [" .. record.windowId .. "]"
                if record.id == previousId then selected = record end
            else self.rowText[index], self.rowTime[index] = nil, nil end
        end
        self.pageLabel:SetText(self.total == 0 and "0 results" or (self.offset + 1) .. "-" .. (self.offset + table.getn(self.records)) .. " / " .. self.total)
        Enable(self.previousButton, self.offset > 0); Enable(self.nextButton, self.offset + PAGE_SIZE < self.total)
        Enable(self.copyPageButton, table.getn(self.records) > 0)
        local runtime = Chat.Core.Runtime.GetState()
        local store, storeFailure = Chat.Database.Ensure()
        local native, capture = Chat.Modules.NativeChat.GetState(), Chat.Modules.HistoryCapture.GetState()
        self.enabledButton:SetText(store and store.enabled and "Disable" or "Enable")
        UI.SetActionButtonIcon(self.enabledButton, store and store.enabled and "disable" or "enable")
        local status = runtime.failure or runtime.historyFailure or storeFailure or ""
        if status == "" and native.deferredWheels > 0 then status = "Another addon controls scrolling in " .. native.deferredWheels .. " window(s)." end
        if status == "" and capture.deferred > 0 then status = "Another addon controls messages in " .. capture.deferred .. " window(s)." end
        if status == "" and not capture.collecting then status = "History collection is paused." end
        self:Message(status)
        self:SelectRecord(selected or preserveSelection and self.selectedRecord or self.records[1]); self:OnResize()
        return true
    end
    function view:RunQuery(offset, preserveSelection)
        if not frame:IsVisible() then return false, "History view is hidden." end
        if self.refreshing then return false, "History refresh is already running." end
        frame:SetScript("OnUpdate", nil); self.pendingRefresh = nil
        self.refreshing = true; self.changedDuringRefresh = nil; self.queryFailed = nil
        local called, result, failure = pcall(QueryPage, self, offset, preserveSelection)
        self.refreshing = nil
        if not called then failure, result = tostring(result), false end
        if result ~= true then
            self.rendering = nil
            self:Message(failure or "History refresh failed.", true); return false, failure
        end
        if self.changedDuringRefresh then self.dirty = true; self:QueueRefresh() end
        return true
    end
    function view:Refresh()
        if not frame:IsVisible() then return true end
        return self:RunQuery(self.offset)
    end
    function view:Search()
        self.query = self.searchBox:GetText() or ""; self.searchBox:ClearFocus()
        self.live = true
        return self:RunQuery(0)
    end
    function view:ClearSearch()
        self.searchBox:SetText(""); self.query = ""; self.searchBox:ClearFocus()
        self.live = true
        return self:RunQuery(0)
    end
    function view:OpenCopy(records)
        local text, failure = Chat.Services.History.BuildCopy(records)
        if not text then self:Message(failure, true); return false, failure end
        if string.len(text) > COPY_LIMIT then
            failure = "Copy text exceeds the native field limit."; self:Message(failure, true); return false, failure
        end
        if not self.copyPopup then
            local popup = UI.CreateContainer("BootyChatHistoryCopy", UIParent)
            popup:SetWidth(520); popup:SetHeight(320); popup:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
            popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetFrameLevel(220)
            if popup.SetClampedToScreen then popup:SetClampedToScreen(true) end
            popup.title = UI.CreateHeading(popup, "Copy chat history", 2, "gold")
            popup.close = UI.CreateWindowButton(popup, nil, "close")
            popup.close.historyPopup = popup; popup.close:SetScript("OnClick", CloseCopy)
            UI.Window.StyleProjectDialog(popup, "archive")
            popup.hint = UI.CreateComponentLabel(popup, "Select text and press Ctrl+C. Escape closes this window.", "white")
            popup.hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -34); popup.hint:SetWidth(488); popup.hint:SetHeight(18)
            popup.edit = UI.CreateTextArea(popup, 488, 240, COPY_LIMIT)
            popup.area = UI.MakeTextAreaScrollable(popup.edit, popup)
            popup.area:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -58); popup.area:SetWidth(488); popup.area:SetHeight(246)
            popup.scroll = popup.edit.viewport
            UI.RegisterSkinnedScrollBar(popup.edit.scrollBar)
            popup.edit.historyPopup = popup; popup.edit:SetScript("OnEscapePressed", CloseCopy)
            popup:SetScript("OnHide", function()
                popup.edit:ClearFocus(); popup.edit:SetText("")
                if view.dirty then view:QueueRefresh() end
            end)
            if UI.WindowStack then UI.WindowStack.SetOwner(popup, frame) end
            popup:Hide(); self.copyPopup = popup
        end
        local popup = self.copyPopup
        popup.edit:SetText(text)
        if popup.edit:GetText() ~= text then
            popup:Hide()
            failure = "The native copy field did not accept the complete text."; self:Message(failure, true); return false, failure
        end
        popup.edit.viewport:SetVerticalScroll(0); popup.edit.LayoutScroll()
        popup:Show(); popup.edit:SetFocus(); popup.edit:HighlightText()
        if UI.WindowStack then UI.WindowStack.Raise(popup) end
        return true
    end
    function view:CopySelected()
        if not self.selectedRecord then return false, "Select a message first." end
        return self:OpenCopy({self.selectedRecord})
    end
    function view:CopyPage()
        if table.getn(self.records) == 0 then return false, "No messages on this page." end
        return self:OpenCopy(self.records)
    end
    function view:ConfirmClear()
        if not self.confirmation then
            self.confirmation = UI.Window.CreateProjectConfirmation("BootyChatHistoryClear", "Clear chat history", "Clear", "list")
            if UI.WindowStack then UI.WindowStack.SetOwner(self.confirmation, frame) end
        end
        local windowId = self.windowId
        local target = windowId and Chat.Services.Configuration.WindowLabel(windowId) or "all windows"
        self.confirmation:Open("Clear retained messages for " .. target .. "?", function()
            local ok, failure = Chat.Core.Runtime.ClearHistory(windowId)
            if not ok then view:Message(failure, true) else view:RunQuery(0) end
        end)
        return true
    end
    function view:Cleanup()
        frame:SetScript("OnUpdate", nil); self.pendingRefresh = nil
        if self.subscribed then self.subscribed:Unsubscribe(self); self.subscribed = nil end
        if self.resetMenu then self.resetMenu:Close() end
        choice.panel:Hide(); self.searchBox:ClearFocus()
        if self.copyPopup then self.copyPopup:Hide() end
        if self.confirmation then self.confirmation:Hide() end
    end
    function view:Show()
        frame:Show()
        if not frame:IsVisible() then return true end
        return self:Refresh()
    end
    function view:Hide() self:Cleanup(); frame:Hide(); return true end
    frame:SetScript("OnHide", function() view:Cleanup() end)
    Enable(view.copySelectedButton, false); Enable(view.copyPageButton, false)
    Enable(view.previousButton, false); Enable(view.nextButton, false)
    frame:Hide()
    return view
end
