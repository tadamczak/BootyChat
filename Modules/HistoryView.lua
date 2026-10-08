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
local function Action(view, label, width, callback)
    local button = UI.CreateButton(view.canvas, nil, label, width, 22)
    UI.StyleActionButton(button)
    button.historyView = view; button:SetScript("OnClick", callback)
    return button
end
local function Back() this.historyView.onBack() end
local function Search() this.historyView:Search() end
local function ClearSearch() this.historyView:ClearSearch() end
local function Refresh() this.historyView:Refresh() end
local function Previous() local view = this.historyView; view:RunQuery(math.max(0, view.offset - PAGE_SIZE)) end
local function Next() local view = this.historyView; view:RunQuery(view.offset + PAGE_SIZE) end
local function CopySelected() this.historyView:CopySelected() end
local function CopyPage() this.historyView:CopyPage() end
local function ConfirmClear() this.historyView:ConfirmClear() end
local function SelectRow() this.historyView:SelectRecord(this.record) end
local function OnScroll()
    if this.historyView.rendering then return end
    FauxScrollFrame_OnVerticalScroll(ROW_STEP, this.refreshCallback)
end
local function OnHistoryChanged(view)
    -- Keep the displayed page and any focused copy snapshot stable during capture.
    if view.frame:IsVisible() and not view.dirty then
        view.dirty = true
        view.status:SetText("New messages. Refresh to update.")
    end
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
        records = {}, rowText = {}, rowTime = {}, offset = 0, total = 0, query = "", dirty = false}
    local title = UI.CreateHeading(canvas, "Chat history", 2, "gold")
    view.backButton = Action(view, "Back", 72, Back)
    local choices = {{value = 0, text = "All windows"}}
    for id = 1, Chat.Services.Configuration.WindowCount() do
        table.insert(choices, {value = id, text = Chat.Services.Configuration.WindowLabel(id)})
    end
    local choiceLabel, choice = UI.CreateChoiceField({parent = canvas, x = 0, y = 0, label = "", initialText = "All windows",
        width = 160, height = 14 + table.getn(choices) * 20, firstY = -7, step = 20, buttonOffset = 0, choices = choices,
        getValue = function() return view.windowId or 0 end,
        onSelect = function(id)
            if id == 0 then view.windowId = nil else view.windowId = id end
            view:RunQuery(0)
        end})
    choiceLabel:Hide(); view.windowChoice, view.windowLabel = choice, choiceLabel
    view.searchBox = UI.CreateFramedEditBox(canvas, nil, 160)
    view.searchBox:SetMaxLetters(256); view.searchBox.historyView = view
    UI.AttachPlaceholder(view.searchBox, "Search visible text...")
    view.searchBox:SetScript("OnEnterPressed", Search)
    view.searchButton = Action(view, "Search", 64, Search)
    view.clearSearchButton = Action(view, "Clear query", 76, ClearSearch)
    view.refreshButton = Action(view, "Refresh", 64, Refresh)
    view.copySelectedButton = Action(view, "Copy selected", 96, CopySelected)
    view.copyPageButton = Action(view, "Copy page", 80, CopyPage)
    view.clearButton = Action(view, "Clear history", 88, ConfirmClear)
    view.previousButton = Action(view, "Previous", 64, Previous)
    view.nextButton = Action(view, "Next", 64, Next)
    view.pageLabel = UI.CreateComponentLabel(canvas, "", "white")
    view.status = UI.CreateComponentLabel(canvas, "", "white")
    view.status:SetJustifyH("LEFT"); view.status:SetJustifyV("TOP")
    local dirtyMeasure = UI.CreateComponentLabel(canvas, "New messages. Refresh to update.", "white")
    dirtyMeasure:SetAlpha(0)
    view.filters = {choice, view.searchBox, view.searchButton}
    view.actions = {view.clearSearchButton, view.refreshButton, view.copySelectedButton, view.copyPageButton, view.clearButton}
    view.pager = {view.previousButton, view.nextButton, view.pageLabel}
    view.table = UI.Table.Create({parent = canvas, name = "BootyChatHistoryScroll", x = 16, width = 300,
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
        if failure and host.Print then host.Print(message) end
        self.status:SetText(Escape(message))
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
        local scrollOffset, visible, width = UI.Table.LayoutViewport(self.table.scroll, canvas, 16, self.resultTop,
            self.resultWidth, self.resultHeight, table.getn(self.records), ROW_STEP, PAGE_SIZE)
        self.table.resolvedWidth, self.table.visibleRows, self.table.offset = width, visible, scrollOffset
        for index = 1, PAGE_SIZE do
            local row, record = self.rows[index], self.records[scrollOffset + index]
            if record and index <= visible then
                row.record = record; row:ClearAllPoints(); row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -(self.resultTop + (index - 1) * ROW_STEP))
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
        local available = math.max(1, width - 32)
        self.narrow = available < 240
        title:SetText(self.narrow and "History" or "Chat history")
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16); title:SetWidth(math.max(1, available - 80)); title:SetHeight(22)
        self.backButton:ClearAllPoints(); self.backButton:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -16, -16)
        local choiceWidth = math.min(200, math.max(120, available * 0.38))
        choice:SetWidth(choiceWidth)
        self.searchBox:SetWidth(math.max(96, math.min(260, available - choiceWidth - 80)))
        local top = UI.LayoutFlow(canvas, self.filters, 16, 46, available, 8)
        top = UI.LayoutFlow(canvas, self.actions, 16, top + 8, available, 8)
        self.pageLabel:SetWidth(math.min(128, available)); self.pageLabel:SetHeight(18)
        top = UI.LayoutFlow(canvas, self.pager, 16, top + 8, available, 8)
        local statusHeight = math.max(14, UI.MeasureTextHeight(self.status, available), UI.MeasureTextHeight(dirtyMeasure, available))
        self.status:ClearAllPoints(); self.status:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -(top + 8))
        self.status:SetWidth(available); self.status:SetHeight(statusHeight)
        self.resultTop, self.resultWidth = top + 12 + statusHeight, available
        local previewHeight = math.min(84, math.max(50, height * 0.18))
        local previewTop = height - 16 - previewHeight
        self.compact = previewTop - 24 - self.resultTop < ROW_STEP
        if self.compact then
            -- Whole-body scrolling owns overflow; the logical table has no second gutter.
            self.resultHeight = math.max(1, table.getn(self.records)) * ROW_STEP
            previewTop = self.resultTop + self.resultHeight + 24
        else self.resultHeight = previewTop - 24 - self.resultTop end
        self.previewLabel:ClearAllPoints(); self.previewLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -(previewTop - 18))
        self.previewLabel:SetWidth(available); self.previewLabel:SetHeight(16)
        self.previewPanel:ClearAllPoints(); self.previewPanel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -previewTop)
        self.previewPanel:SetWidth(available); self.previewPanel:SetHeight(previewHeight)
        self.preview:ClearAllPoints(); self.preview:SetPoint("TOPLEFT", self.previewPanel, "TOPLEFT", 6, -6)
        self.preview:SetWidth(math.max(1, available - 12)); self.preview:SetHeight(math.max(1, previewHeight - 12))
        self:RenderRows()
        self.contentWidth, self.contentHeight = width, math.max(height, previewTop + previewHeight + 16)
        return self.contentHeight
    end
    function view:OnResize(width, height)
        if not frame:IsVisible() then return end
        if not width or not height then width, height = UI.GetFrameSpan(self.layoutOwner) end
        width, height = math.max(1, width), math.max(1, height)
        self.layoutWidth, self.layoutHeight = width, height
        UI.LayoutResponsiveCanvas(canvas, MeasureBody, nil, width, height)
    end
    function view:RunQuery(offset)
        if not frame:IsVisible() then return false, "History view is hidden." end
        local service = Chat.Core.Runtime.GetHistory()
        if self.subscribed ~= service then
            if self.subscribed then self.subscribed:Unsubscribe(self); self.subscribed = nil end
            if service then
                local accepted, reason = service:Subscribe(self, OnHistoryChanged)
                if not accepted then self:Message(reason, true); return false, reason end
                self.subscribed = service
            end
        end
        if not service then self:Message("Chat history is unavailable.", true); return false, "Chat history is unavailable." end
        local page, failure = service:Query(self.windowId, self.query, offset or self.offset, PAGE_SIZE)
        if not page then self:Message(failure, true); return false, failure end
        local previousId = self.selectedRecord and self.selectedRecord.id
        self.records, self.offset, self.total, self.dirty = page.records, page.offset, page.total, false
        self.table.scroll.offset = 0
        for index = 2, table.getn(choices) do
            local text = Chat.Services.Configuration.WindowLabel(index - 1)
            choices[index].text = text
            local option = choice.panel.options[index]
            option.choiceText = text; option:SetText(text)
        end
        choice:SetText(self.windowId and Chat.Services.Configuration.WindowLabel(self.windowId) or "All windows")
        local selected
        -- Parsing and time formatting happen once per explicit page query, not per scroll.
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
        local stats = service:GetStats()
        local runtime = Chat.Core.Runtime.GetState()
        self:Message(runtime.historyFailure or (stats.count .. " messages retained. " .. stats.bytes .. " bytes."))
        self:SelectRecord(selected or self.records[1]); self:OnResize()
        return true
    end
    function view:Refresh() return self:RunQuery(self.offset) end
    function view:Search()
        self.query = self.searchBox:GetText() or ""; self.searchBox:ClearFocus()
        return self:RunQuery(0)
    end
    function view:ClearSearch()
        self.searchBox:SetText(""); self.query = ""; self.searchBox:ClearFocus()
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
            UI.Window.StyleProjectDialog(popup, "list")
            popup.hint = UI.CreateComponentLabel(popup, "Select text and press Ctrl+C. Escape closes this window.", "white")
            popup.hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -34); popup.hint:SetWidth(488); popup.hint:SetHeight(18)
            popup.edit = UI.CreateTextArea(popup, 488, 240, COPY_LIMIT)
            popup.area = UI.MakeTextAreaScrollable(popup.edit, popup)
            popup.area:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -58); popup.area:SetWidth(488); popup.area:SetHeight(246)
            popup.scroll = popup.edit.viewport
            UI.RegisterSkinnedScrollBar(popup.edit.scrollBar)
            popup.edit.historyPopup = popup; popup.edit:SetScript("OnEscapePressed", CloseCopy)
            popup:SetScript("OnHide", function() popup.edit:ClearFocus(); popup.edit:SetText("") end)
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
        if self.subscribed then self.subscribed:Unsubscribe(self); self.subscribed = nil end
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
