local Configuration = {}
BootyChat.Services.Configuration = Configuration

local defaults = {
    font = "native", fontSize = 14, fontOutline = "OUTLINE",
    backgroundColor = {0.02, 0.02, 0.02}, backgroundAlpha = 0.65,
    goldBorder = true, wheel = true, wheelSpeed = 3, shiftScroll = true,
    hideButtons = false, width = 0, height = 0,
}
local editboxDefaults = {position = "bottom", fontSize = 14, arrowKeys = true}
local fonts = {native = true, friz = true, arial = true, morpheus = true, skurri = true}
local outlines = {native = true, none = true, OUTLINE = true, THICKOUTLINE = true}
local positions = {native = true, top = true, bottom = true}

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
    if key == "fontSize" then valid = value == 0 or Integer(value, 8, 24)
    elseif key == "font" then valid = type(value) == "string" and fonts[value]
    elseif key == "fontOutline" then valid = type(value) == "string" and outlines[value]
    elseif key == "position" then valid = type(value) == "string" and positions[value]
    elseif key == "backgroundAlpha" then valid = Finite(value) and (value == -1 or value >= 0 and value <= 1)
    elseif key == "backgroundColor" then
        valid = type(value) == "table"
        if valid then
            for index = 1, 3 do
                valid = valid and Finite(value[index]) and value[index] >= 0 and value[index] <= 1
            end
            for index in pairs(value) do if index ~= 1 and index ~= 2 and index ~= 3 then valid = false end end
        end
    elseif key == "wheelSpeed" then valid = Integer(value, 1, 10)
    elseif key == "width" then valid = value == 0 or Integer(value, 100, 4096)
    elseif key == "height" then valid = value == 0 or Integer(value, 50, 4096)
    else valid = type(value) == "boolean" end
    if not valid then return false, "Invalid chat setting: " .. tostring(key) end
    return true
end
local function ValidateSection(section, editbox)
    if section == nil then return true end
    if type(section) ~= "table" then return false, "Invalid chat appearance settings." end
    for key, value in pairs(section) do
        local valid, failure = Configuration.ValidateValue(key, value, editbox)
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
    if store.windows ~= nil then
        if type(store.windows) ~= "table" then return false, "Invalid saved chat windows." end
        for id, appearance in pairs(store.windows) do
            if not Configuration.ValidWindow(id) then return false, "Invalid saved chat window identifier." end
            valid, failure = ValidateSection(appearance)
            if not valid then return false, failure end
        end
    end
    return true
end
function Configuration.Resolve(store, id)
    local result = {}
    local override = store.windows and store.windows[id]
    for key, value in pairs(defaults) do
        if store.defaults and store.defaults[key] ~= nil then value = store.defaults[key] end
        if override and override[key] ~= nil then value = override[key] end
        result[key] = Configuration.Copy(value)
    end
    return result
end
function Configuration.ResolveEditbox(store)
    local result = {}
    for key, value in pairs(editboxDefaults) do
        if store.editbox and store.editbox[key] ~= nil then value = store.editbox[key] end
        result[key] = value
    end
    return result
end
