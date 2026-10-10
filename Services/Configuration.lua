local Configuration = {}
BootyChat.Services.Configuration = Configuration

local defaults = {
    font = "native", fontSize = 14, fontOutline = "OUTLINE",
    backgroundColor = {0.02, 0.02, 0.02}, backgroundAlpha = 0.65,
    goldBorder = true, wheel = true, wheelSpeed = 3, shiftScroll = true,
    hideButtons = false, width = 0, height = 0,
    shadowMode = "native", shadowColor = {0, 0, 0}, shadowAlpha = 1, shadowX = 1, shadowY = -1,
    fadingMode = "off", timeVisible = 0, fadeDuration = 0, lineSpacing = -1,
    backgroundPaddingX = 4, backgroundPaddingY = 4, borderAlpha = 1,
    tabFont = "inherit", tabFontSize = -1, tabFontOutline = "inherit", tabBorderMode = "inherit",
    tabBorderStyle = "legacy", tabBorderColor = {1, 0.78, 0.2}, tabBorderAlpha = 1,
    tabOffsetX = 0, tabOffsetY = 0, tabWidth = 0, tabHeight = 0,
    tabsAlwaysVisible = false, tabBackground = "native", tabBackgroundColor = {0.02,0.02,0.02}, tabBackgroundAlpha = 0.65,
    backgroundMarginTop = -1, backgroundMarginBottom = -1, backgroundMarginLeft = -1, backgroundMarginRight = -1,
    tabColorMode = "native", tabActiveColor = {1, 0.82, 0}, tabInactiveColor = {0.7, 0.7, 0.7},
    tabShadowMode = "native", tabShadowColor = {0, 0, 0}, tabShadowAlpha = 1, tabShadowX = 1, tabShadowY = -1,
}
local editboxDefaults = {position = "bottom", fontSize = 14, arrowKeys = true,
    font = "native", fontOutline = "native", width = 0, height = 0, gap = 2, offsetX = 0, offsetY = 0,
    marginLeft = 0, marginRight = 0, marginTop = 0, marginBottom = 0,
    shadowMode = "native", shadowColor = {0, 0, 0}, shadowAlpha = 1, shadowX = 1, shadowY = -1,
    backgroundColor = {0.02, 0.02, 0.02}, backgroundAlpha = -1, goldBorder = false,
    borderStyle = "legacy", borderColor = {1, 0.78, 0.2}, borderAlpha = 1}
local historyDefaults = {enabled = false, persist = false, limit = 500}
local Moderation = BootyChat.Services.Moderation
local fonts = {native = true, friz = true, arial = true, morpheus = true, skurri = true}
local outlines = {native = true, none = true, OUTLINE = true, THICKOUTLINE = true}
local positions = {native = true, top = true, bottom = true, free = true}
local shadowModes = {native = true, custom = true}
local fadingModes = {native = true, on = true, off = true}
local borderModes = {inherit = true, on = true, off = true}
local borderStyles = {legacy = true, native = true, none = true, project = true, dialog = true, tooltip = true}

local function Finite(value)
    return type(value) == "number" and value == value and value - value == 0
end
local function Integer(value, low, high)
    return Finite(value) and value == math.floor(value) and value >= low and value <= high
end
function Configuration.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Configuration.Copy(child) end
    return copy
end
function Configuration.WindowCount()
    return Integer(NUM_CHAT_WINDOWS, 1, 32) and NUM_CHAT_WINDOWS or 7
end
function Configuration.ValidWindow(id)
    return Integer(id, 1, Configuration.WindowCount())
end
function Configuration.WindowLabel(id)
    local label = "Window " .. id
    if type(GetChatWindowInfo) == "function" then
        local name = GetChatWindowInfo(id)
        if type(name) == "string" and name ~= "" then label = label .. " - " .. name end
    end
    return label
end
function Configuration.GetDefault(key, editbox)
    return Configuration.Copy((editbox and editboxDefaults or defaults)[key])
end
function Configuration.ValidateValue(key, value, editbox)
    local source = editbox and editboxDefaults or defaults
    if source[key] == nil then return false, "Unknown chat setting: " .. tostring(key) end
    if value == nil then return true end
    local valid
    if key == "fontSize" or key == "tabFontSize" then
        valid = key == "tabFontSize" and value == -1 or value == 0 or Integer(value, 8, 24)
    elseif key == "font" or key == "tabFont" then
        valid = type(value) == "string" and (fonts[value] or key == "tabFont" and value == "inherit")
    elseif key == "fontOutline" or key == "tabFontOutline" then
        valid = type(value) == "string" and (outlines[value] or key == "tabFontOutline" and value == "inherit")
    elseif key == "position" then valid = type(value) == "string" and positions[value]
    elseif key == "shadowMode" or key == "tabShadowMode" or key == "tabColorMode" then
        valid = type(value) == "string" and shadowModes[value]
    elseif key == "fadingMode" then valid = type(value) == "string" and fadingModes[value]
    elseif key == "tabBorderMode" then valid = type(value) == "string" and borderModes[value]
    elseif key == "borderStyle" or key == "tabBorderStyle" then
        valid = type(value) == "string" and (borderStyles[value] or key == "tabBorderStyle" and value == "inherit")
    elseif key == "backgroundAlpha" then valid = Finite(value) and (value == -1 or value >= 0 and value <= 1)
    elseif key == "shadowAlpha" or key == "tabShadowAlpha" or key == "borderAlpha" or key == "tabBorderAlpha" then
        valid = Finite(value) and value >= 0 and value <= 1
    elseif key == "shadowX" or key == "shadowY" or key == "tabShadowX" or key == "tabShadowY" then
        valid = Finite(value) and value >= -8 and value <= 8
    elseif key == "backgroundPaddingX" or key == "backgroundPaddingY" then
        valid = Finite(value) and value >= 0 and value <= 24
    elseif key == "tabOffsetX" or key == "tabOffsetY" then
        valid = Finite(value) and value >= -128 and value <= 128
    elseif key == "tabWidth" then valid = value == 0 or Integer(value, 0, 512)
    elseif key == "tabHeight" then valid = value == 0 or Integer(value, 0, 128)
    elseif key == "tabBackground" then valid = value == "native" or value == "color" or value == "tooltip" or value == "dialog"
    elseif string.find(key,"^backgroundMargin") then valid = value == -1 or Integer(value,0,256)
    elseif key == "tabBackgroundAlpha" then valid = Finite(value) and value >= 0 and value <= 1
    elseif key == "offsetX" or key == "offsetY" then valid = Integer(value,-4096,4096)
    elseif string.find(key,"^margin") then valid = Integer(value,0,128)
    elseif key == "gap" then valid = Finite(value) and value >= -512 and value <= 512
    elseif key == "timeVisible" then valid = Integer(value, 0, 3600)
    elseif key == "fadeDuration" then valid = value == 0 or Finite(value) and value >= 0.1 and value <= 30
    elseif key == "lineSpacing" then valid = value == -1 or Finite(value) and value >= 0 and value <= 12
    elseif string.find(key, "Color$") then
        valid = type(value) == "table" and getmetatable(value) == nil
        if valid then
            for index = 1, 3 do
                valid = valid and Finite(value[index]) and value[index] >= 0 and value[index] <= 1
            end
            for index in pairs(value) do if index ~= 1 and index ~= 2 and index ~= 3 then valid = false end end
        end
    elseif key == "wheelSpeed" then valid = Integer(value, 1, 10)
    elseif key == "width" then valid = value == 0 or Integer(value, 0, 4096)
    elseif key == "height" then valid = value == 0 or (editbox and Integer(value, 0, 64) or not editbox and Integer(value, 0, 4096))
    else valid = type(value) == "boolean" end
    if not valid then return false, "Invalid chat setting: " .. tostring(key) end
    return true
end
local function ValidateSection(section, editbox)
    if section == nil then return true end
    if type(section) ~= "table" or getmetatable(section) ~= nil then return false, "Invalid chat appearance settings." end
    for key, value in pairs(section) do
        local valid, failure = Configuration.ValidateValue(key, value, editbox)
        if not valid then return false, failure end
    end
    return true
end
function Configuration.ValidateWindows(windows)
    if windows == nil then return true end
    if type(windows) ~= "table" or getmetatable(windows) ~= nil then return false, "Invalid saved chat windows." end
    for id, appearance in pairs(windows) do
        if not Configuration.ValidWindow(id) then return false, "Invalid saved chat window identifier." end
        local valid, failure = ValidateSection(appearance)
        if not valid then return false, failure end
    end
    return true
end
function Configuration.GetHistoryDefault(key) return historyDefaults[key] end
function Configuration.ValidateHistoryValue(key, value)
    if historyDefaults[key] == nil then return false, "Unknown history setting: " .. tostring(key) end
    if value == nil then return true end
    local valid = key == "limit" and Integer(value, 1, 2000) or
        key ~= "limit" and type(value) == "boolean"
    if not valid then return false, "Invalid history setting: " .. tostring(key) end
    return true
end
local function ValidateHistory(section)
    if section == nil then return true end
    if type(section) ~= "table" or getmetatable(section) ~= nil then return false, "Invalid history preferences." end
    for key, value in pairs(section) do
        local valid, failure = Configuration.ValidateHistoryValue(key, value)
        if not valid then return false, failure end
    end
    return true
end
function Configuration.Validate(store)
    if store ~= nil and type(store) ~= "table" then return false, "Invalid BootyChat saved data. Preserve the saved file before repairing it." end
    if store == nil then return true end
    if store.schemaVersion ~= nil and store.schemaVersion ~= 1 then
        return false, "Unsupported BootyChat saved format. Update the addon before opening it."
    end
    for _, key in ipairs({"enabled", "hideMinimapIcon"}) do
        if store[key] ~= nil and type(store[key]) ~= "boolean" then return false, "Invalid chat setting: " .. key end
    end
    local valid, failure = ValidateSection(store.defaults)
    if not valid then return false, failure end
    valid, failure = ValidateSection(store.editbox, true)
    if not valid then return false, failure end
    valid, failure = ValidateHistory(store.history)
    if not valid then return false, failure end
    valid, failure = Moderation.ValidateSection(store.moderation)
    if not valid then return false, failure end
    if store.historyData ~= nil then
        local History = BootyChat.Services.History
        if not History then return false, "The chat history service is unavailable." end
        valid, failure = History.ValidateSnapshot(store.historyData, Configuration.WindowCount())
        if not valid then return false, failure end
    end
    return Configuration.ValidateWindows(store.windows)
end
function Configuration.Resolve(store, id)
    local result = {}
    local override = store.windows and store.windows[id]
    for key, value in pairs(defaults) do
        if store.defaults and store.defaults[key] ~= nil then value = store.defaults[key] end
        if override and override[key] ~= nil then value = override[key] end
        result[key] = Configuration.Copy(value)
    end
    -- Keep old sparse window overrides authoritative until the user chooses a
    -- new style. No saved table or raw profile preference is rewritten here.
    local source = override and (override.tabBorderStyle ~= nil or override.tabBorderMode ~= nil) and override or store.defaults
    local style = source and source.tabBorderStyle
    if not style or style == "legacy" then
        local mode = source and source.tabBorderMode or result.tabBorderMode
        style = mode == "on" and "project" or mode == "off" and "none" or "inherit"
    end
    for _,side in ipairs({"Top","Bottom","Left","Right"}) do
        local key="backgroundMargin"..side
        if result[key]==-1 then result[key]=(side=="Left" or side=="Right") and result.backgroundPaddingX or result.backgroundPaddingY end
    end
    result.tabBorderStyle = style
    return result
end
function Configuration.UsesGlobal(store, id)
    local override = store.windows and store.windows[id]
    return override == nil or next(override) == nil
end
function Configuration.ResolveEditbox(store)
    local result = {}
    for key, value in pairs(editboxDefaults) do
        if store.editbox and store.editbox[key] ~= nil then value = store.editbox[key] end
        result[key] = Configuration.Copy(value)
    end
    if result.borderStyle == "legacy" then result.borderStyle = result.goldBorder and "project" or "native" end
    return result
end
function Configuration.ResolveHistory(store)
    local result = {}
    for key, value in pairs(historyDefaults) do
        if store.history and store.history[key] ~= nil then value = store.history[key] end
        result[key] = value
    end
    return result
end
function Configuration.ValidateModerationValue(key, value) return Moderation.ValidateValue(key, value) end
function Configuration.GetModerationDefault(key) return Moderation.GetDefault(key) end
function Configuration.ResolveModeration(store) return Moderation.Resolve(store.moderation) end
