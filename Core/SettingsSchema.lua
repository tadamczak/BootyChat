local Chat = BootyChat
-- Shared Settings uses thrown failures to reject values and undo a profile.
local Assert = assert
local function error(message) Assert(false, message) end
local Configuration, Runtime = Chat.Services.Configuration, Chat.Core.Runtime
local fields, count
local fontChoices = {{value = "native", text = "Native font"}, {value = "friz", text = "Friz Quadrata"},
    {value = "arial", text = "Arial Narrow"}, {value = "morpheus", text = "Morpheus"}, {value = "skurri", text = "Skurri"}}
local outlineChoices = {{value = "native", text = "Native outline"}, {value = "none", text = "None"},
    {value = "OUTLINE", text = "Outline"}, {value = "THICKOUTLINE", text = "Thick outline"}}
local sizes = {{value = 0, text = "Native size"}}
for size = 8, 24 do table.insert(sizes, {value = size, text = tostring(size)}) end
local function Inherited(choices)
    local result = {{value = "inherit", text = "Same as chat text"}}
    for _, choice in ipairs(choices) do table.insert(result, choice) end
    return result
end
local tabSizes = {{value = -1, text = "Same as chat text"}}
for _, choice in ipairs(sizes) do table.insert(tabSizes, choice) end
local shadowChoices = {{value = "native", text = "Native shadow"}, {value = "custom", text = "Custom shadow"}}
local colorChoices = {{value = "native", text = "Native colors"}, {value = "custom", text = "Custom colors"}}
local fadeChoices = {{value = "native", text = "Native fading"}, {value = "on", text = "Fade messages"}, {value = "off", text = "Keep messages visible"}}
local borderChoices = {{value = "inherit", text = "Same as chat window"}, {value = "on", text = "Show gold border"}, {value = "off", text = "Hide gold border"}}
local opacityChoices = {{value = -1, text = "Native opacity"}}
local alphaChoices = {}
for step = 0, 20 do
    local choice = {value = step / 20, text = step * 5 .. "%"}
    table.insert(opacityChoices, choice); table.insert(alphaChoices, choice)
end
local spacingChoices = {{value = -1, text = "Native spacing"}}
for step = 0, 24 do table.insert(spacingChoices, {value = step / 2, text = tostring(step / 2)}) end
local definitions = {
    {key = "font", label = "Font", type = "choice", choices = fontChoices, group = "Text"},
    {key = "fontSize", label = "Font size", type = "choice", choices = sizes, group = "Text"},
    {key = "fontOutline", label = "Font outline", type = "choice", choices = outlineChoices, group = "Text"},
    {key = "lineSpacing", label = "Line spacing", type = "choice", choices = spacingChoices, group = "Text"},
    {key = "shadowMode", label = "Text shadow", type = "choice", choices = shadowChoices, group = "Text shadow"},
    {key = "shadowColor", label = "Shadow color", type = "color", group = "Text shadow"},
    {key = "shadowAlpha", label = "Shadow opacity", type = "choice", choices = alphaChoices, group = "Text shadow"},
    {key = "shadowX", label = "Horizontal shadow offset", type = "number", min = -8, max = 8, group = "Text shadow"},
    {key = "shadowY", label = "Vertical shadow offset", type = "number", min = -8, max = 8, group = "Text shadow"},
    {key = "fadingMode", label = "Message fading", type = "choice", choices = fadeChoices, group = "Fading"},
    {key = "timeVisible", label = "Seconds before fading (0 keeps native time)", type = "number", min = 0, max = 3600, group = "Fading"},
    {key = "fadeDuration", label = "Fade duration (0 keeps native duration)", type = "number", min = 0, max = 30, group = "Fading"},
    {key = "backgroundColor", label = "Background color", type = "color", group = "Background"},
    {key = "backgroundAlpha", label = "Background opacity", type = "choice", choices = opacityChoices, group = "Background",
        tooltip = "Native opacity keeps the native chat background and gives the project surface a transparent fill."},
    {key = "backgroundPaddingX", label = "Horizontal background margin", type = "slider", min = 0, max = 24, step = 1, group = "Background"},
    {key = "backgroundPaddingY", label = "Vertical background margin", type = "slider", min = 0, max = 24, step = 1, group = "Background"},
    {key = "goldBorder", label = "Project gold border", type = "checkbox", group = "Background"},
    {key = "borderAlpha", label = "Gold border opacity", type = "choice", choices = alphaChoices, group = "Background"},
    {key = "wheel", label = "Mouse wheel scrolling", type = "checkbox", group = "Scrolling"},
    {key = "wheelSpeed", label = "Lines per wheel step", type = "slider", min = 1, max = 10, step = 1, group = "Scrolling"},
    {key = "shiftScroll", label = "Shift-wheel to top or bottom", type = "checkbox", group = "Scrolling"},
    {key = "hideButtons", label = "Hide scroll buttons", type = "checkbox", group = "Scrolling"},
    {key = "width", label = "Width (0 keeps native size)", type = "number", min = 0, max = 4096, group = "Layout"},
    {key = "height", label = "Height (0 keeps native size)", type = "number", min = 0, max = 4096, group = "Layout"},
    {key = "tabFont", label = "Tab font", type = "choice", choices = Inherited(fontChoices), group = "Tabs"},
    {key = "tabFontSize", label = "Tab font size", type = "choice", choices = tabSizes, group = "Tabs"},
    {key = "tabFontOutline", label = "Tab font outline", type = "choice", choices = Inherited(outlineChoices), group = "Tabs"},
    {key = "tabBorderMode", label = "Tab gold border", type = "choice", choices = borderChoices, group = "Tabs"},
    {key = "tabColorMode", label = "Tab text colors", type = "choice", choices = colorChoices, group = "Tabs"},
    {key = "tabActiveColor", label = "Active tab color", type = "color", group = "Tabs"},
    {key = "tabInactiveColor", label = "Inactive tab color", type = "color", group = "Tabs"},
    {key = "tabShadowMode", label = "Tab text shadow", type = "choice", choices = shadowChoices, group = "Tab shadow"},
    {key = "tabShadowColor", label = "Tab shadow color", type = "color", group = "Tab shadow"},
    {key = "tabShadowAlpha", label = "Tab shadow opacity", type = "choice", choices = alphaChoices, group = "Tab shadow"},
    {key = "tabShadowX", label = "Horizontal tab shadow offset", type = "number", min = -8, max = 8, group = "Tab shadow"},
    {key = "tabShadowY", label = "Vertical tab shadow offset", type = "number", min = -8, max = 8, group = "Tab shadow"},
}
local function Required(ok, failure) if not ok then error(failure) end end
local function Field(definition)
    -- Choices are immutable metadata shared by all windows; don't duplicate
    -- those arrays for every lazy Settings row.
    local field = {}
    for key, value in pairs(definition) do if key ~= "group" then field[key] = value end end
    return field
end
local function NumberValue(definition, value)
    if definition.type == "number" and type(value) == "string" then
        local number = tonumber(value)
        if not number then error("Enter a numeric value for " .. definition.label .. ".") end
        return number
    end
    return value
end
local function AddAppearance(id, definition)
    local key = definition.key
    local field = Field(definition)
    field.key = id and "window" .. id .. "_" .. key or "default_" .. key
    field.durableKey = id and "windows" or "defaults"
    field.default = Configuration.GetDefault(key)
    field.path = id and {"Chat", "Windows", Configuration.WindowLabel(id), definition.group} or {"Chat", "Appearance", definition.group}
    field.windowId = id
    field.get = function(store)
        if id then return Configuration.Resolve(store, id)[key] end
        return store.defaults[key]
    end
    field.set = function(value)
        Required(Runtime.SetOption(id, key, NumberValue(definition, value)))
    end
    field.profile = not id
    if id then
        field.tooltip = (field.tooltip and field.tooltip .. "\n\n" or "") .. "This setting overrides the common appearance for native chat window " .. id .. ". Reset this window from the Chat page to inherit the common appearance again."
    end
    if key == "width" or key == "height" then
        field.tooltip = (field.tooltip or "") .. " Docked windows share the main window size. An individual size takes effect for a detached window on the next setting change or chat-window update; zero keeps the native size."
    end
    table.insert(fields, field)
end
local function Build()
    fields = {{key = "enabled", label = "Enable native chat customizations", type = "checkbox", default = true,
        path = {"Chat", "General"}, profile = false,
        tooltip = "Turning this off restores native appearance and scrolling, and pauses history, filters and mentions. Your channels remain available.",
        set = function(value) Required(Runtime.SetEnabled(value)) end},
        {key = "hideMinimapIcon", label = "Hide minimap icon", type = "checkbox", default = false,
        path = {"Chat", "General"}, set = function(value) Required(Runtime.SetMinimapHidden(value)) end}}
    for _, definition in ipairs(definitions) do AddAppearance(nil, definition) end
    count = Configuration.WindowCount()
    for id = 1, count do for _, definition in ipairs(definitions) do AddAppearance(id, definition) end end
    table.insert(fields, {key = "windowOverrides", type = "text", profileOnly = true, durableKey = "windows", default = {},
        get = function(store) return store.windows end,
        set = function(value) Required(Runtime.SetWindowOverrides(value)) end})
    local editboxDefinitions = {
        {key = "position", label = "Input position", type = "choice", choices = {
            {value = "native", text = "Native position"}, {value = "top", text = "Above main chat"}, {value = "bottom", text = "Below main chat"}}, group = "Behavior"},
        {key = "height", label = "Minimum input height (0 keeps native height)", type = "number", min = 0, max = 64, group = "Behavior",
            tooltip = "An explicit height keeps at least eight pixels of room beyond the selected font size. Zero keeps the native height."},
        {key = "gap", label = "Distance from main chat", type = "slider", min = 0, max = 32, step = 1, group = "Behavior"},
        {key = "arrowKeys", label = "Arrow keys without Alt", type = "checkbox", group = "Behavior"},
        {key = "font", label = "Input font", type = "choice", choices = fontChoices, group = "Text"},
        {key = "fontSize", label = "Input font size", type = "choice", choices = sizes, group = "Text"},
        {key = "fontOutline", label = "Input font outline", type = "choice", choices = outlineChoices, group = "Text"},
        {key = "shadowMode", label = "Input text shadow", type = "choice", choices = shadowChoices, group = "Text shadow"},
        {key = "shadowColor", label = "Input shadow color", type = "color", group = "Text shadow"},
        {key = "shadowAlpha", label = "Input shadow opacity", type = "choice", choices = alphaChoices, group = "Text shadow"},
        {key = "shadowX", label = "Horizontal input shadow offset", type = "number", min = -8, max = 8, group = "Text shadow"},
        {key = "shadowY", label = "Vertical input shadow offset", type = "number", min = -8, max = 8, group = "Text shadow"},
        {key = "backgroundColor", label = "Input background color", type = "color", group = "Background"},
        {key = "backgroundAlpha", label = "Input background opacity", type = "choice", choices = opacityChoices, group = "Background",
            tooltip = "Native opacity restores the original input artwork when the project gold border is off. With the project border on, Native opacity gives the custom surface a transparent fill."},
        {key = "goldBorder", label = "Input project gold border", type = "checkbox", group = "Background"},
    }
    for _, definition in ipairs(editboxDefinitions) do
        local key, field = definition.key, Field(definition)
        field.key, field.durableKey = "input_" .. key, "editbox"
        field.default, field.path = Configuration.GetDefault(key, true), {"Chat", "Input", definition.group}
        field.get = function(store) return store.editbox[key] end
        field.set = function(value) Required(Runtime.SetEditboxOption(key, NumberValue(definition, value))) end
        table.insert(fields, field)
    end
    local historyDefinitions = {
        {key = "enabled", label = "Collect chat history", type = "checkbox",
            tooltip = "Collect messages submitted to native chat windows. Pausing collection keeps existing session history."},
        {key = "persist", label = "Remember history between sessions", type = "checkbox",
            tooltip = "Save bounded history on logout or reload. Turning this off clears the saved copy and retains the current session."},
        {key = "limit", label = "Maximum history entries", type = "choice", choices = {
            {value = 100, text = "100"}, {value = 250, text = "250"}, {value = 500, text = "500"},
            {value = 1000, text = "1000"}, {value = 2000, text = "2000"}},
            tooltip = "A global limit across all native windows, also bounded to 256 KiB of message text. Lowering the limit removes the oldest entries."},
    }
    for _, definition in ipairs(historyDefinitions) do
        local key, field = definition.key, Field(definition)
        field.key, field.durableKey, field.profile = "history_" .. key, "history", false
        field.default, field.path = Configuration.GetHistoryDefault(key), {"Chat", "History"}
        field.get = function(store) return store.history[key] end
        field.set = function(value) Required(Runtime.SetHistoryOption(key, value)) end
        table.insert(fields, field)
    end
    local scopeChoices = {{value = "channels", text = "Named channels"}, {value = "public", text = "Channels, Say and Yell"},
        {value = "group", text = "Guild, party, raid and battleground"}, {value = "all", text = "All player messages"}}
    local scopeHelp = "Only messages displayed in native chat windows are processed. Loot, system, NPC and combat messages are excluded. Other addons still receive the original events. Native whisper sounds and tab flashing remain active."
    local channelHelp = "Separate exact channel names with semicolons, for example World;Trade. Use the name without its number or zone suffix. Empty means all channels in the selected scope. Maximum 16 names, 80 bytes per name."
    local termHelp = "Separate literal phrases with semicolons. ASCII letters ignore case; other characters match exactly. No patterns or wildcards. Maximum 32 phrases, 128 bytes each."
    local moderationDefinitions = {
        {key = "blockedEnabled", label = "Hide messages containing blocked phrases", type = "checkbox", group = "Filters"},
        {key = "blockedTerms", label = "Blocked phrases (semicolon separated)", type = "text", maxLength = 4096, tooltip = termHelp, group = "Filters"},
        {key = "filterScope", label = "Filter and repetition scope", type = "choice", choices = scopeChoices, tooltip = scopeHelp, group = "Filters"},
        {key = "channels", label = "Filtered channel names", type = "text", maxLength = 1536, tooltip = channelHelp, group = "Filters"},
        {key = "repeatEnabled", label = "Hide repeated messages", type = "checkbox", group = "Filters"},
        {key = "repeatSeconds", label = "Repeat blocking window (seconds)", type = "slider", min = 1, max = 120, step = 1,
            tooltip = "Repeated text from the same sender, message type and channel is hidden separately in each native window. Only a successfully displayed message starts the timer.", group = "Filters"},
        {key = "mentionEnabled", label = "Enable mentions", type = "checkbox", group = "Mentions"},
        {key = "mentionScope", label = "Mention scope", type = "choice", choices = scopeChoices, tooltip = scopeHelp, group = "Mentions"},
        {key = "mentionChannels", label = "Mention channel names", type = "text", maxLength = 1536, tooltip = channelHelp, group = "Mentions"},
        {key = "mentionPlayer", label = "Match my character name", type = "checkbox", group = "Mentions"},
        {key = "mentionTerms", label = "Additional mention phrases", type = "text", maxLength = 4096, tooltip = termHelp, group = "Mentions"},
        {key = "mentionWholeWord", label = "Match whole words", type = "checkbox", tooltip = "For example Ann matches Ann, but does not match Anna. Names in sender prefixes are excluded.", group = "Mentions"},
        {key = "mentionHighlight", label = "Color mentioned messages", type = "checkbox", group = "Mentions"},
        {key = "mentionColor", label = "Mention text color", type = "color", group = "Mentions"},
        {key = "mentionSound", label = "Play a sound for mentions", type = "checkbox", tooltip = "Uses the native TellMessage sound. Incoming whispers keep their own native alert. Messages you send do not trigger mentions.", group = "Mentions"},
        {key = "alertCooldown", label = "Minimum time between mention sounds", type = "slider", min = 1, max = 60, step = 1,
            tooltip = "A shared cooldown prevents repeated sounds when the same message appears in several windows.", group = "Mentions"},
    }
    for _, definition in ipairs(moderationDefinitions) do
        local key, field = definition.key, Field(definition)
        field.key, field.durableKey, field.profile = "moderation_" .. key, "moderation", false
        field.default, field.path = Configuration.GetModerationDefault(key), {"Chat", definition.group}
        field.get = function(store) return store.moderation[key] end
        field.set = function(value) Required(Runtime.SetModerationOption(key, value)) end
        table.insert(fields, field)
    end
end
function Chat.GetSettings()
    local store = Chat.Database.Ensure()
    if not store then return nil end
    if not fields or count ~= Configuration.WindowCount() then Build() end
    local labels = {}
    for id = 1, count do labels[id] = Configuration.WindowLabel(id) end
    for _, field in ipairs(fields) do
        if field.windowId then field.path[3] = labels[field.windowId] end
    end
    return {db = store, fields = fields}
end
