local Chat = BootyChat
local Configuration, Runtime = Chat.Services.Configuration, Chat.Core.Runtime
local fields, count
local fontChoices = {{value = "native", text = "Native font"}, {value = "friz", text = "Friz Quadrata"},
    {value = "arial", text = "Arial Narrow"}, {value = "morpheus", text = "Morpheus"}, {value = "skurri", text = "Skurri"}}
local outlineChoices = {{value = "native", text = "Native outline"}, {value = "none", text = "None"},
    {value = "OUTLINE", text = "Outline"}, {value = "THICKOUTLINE", text = "Thick outline"}}
local sizes = {{value = 0, text = "Native size"}}
for size = 8, 24 do table.insert(sizes, {value = size, text = tostring(size)}) end
local definitions = {
    {key = "font", label = "Font", type = "choice", choices = fontChoices},
    {key = "fontSize", label = "Font size", type = "choice", choices = sizes},
    {key = "fontOutline", label = "Font outline", type = "choice", choices = outlineChoices},
    {key = "backgroundColor", label = "Background color", type = "color"},
    {key = "backgroundAlpha", label = "Background opacity", type = "slider", min = 0, max = 1, step = 0.05},
    {key = "goldBorder", label = "Project gold border", type = "checkbox"},
    {key = "wheel", label = "Mouse wheel scrolling", type = "checkbox"},
    {key = "wheelSpeed", label = "Lines per wheel step", type = "slider", min = 1, max = 10, step = 1},
    {key = "shiftScroll", label = "Shift-wheel to top or bottom", type = "checkbox"},
    {key = "hideButtons", label = "Hide scroll buttons", type = "checkbox"},
    {key = "width", label = "Width (0 keeps native size)", type = "number", min = 0, max = 4096},
    {key = "height", label = "Height (0 keeps native size)", type = "number", min = 0, max = 4096},
}
local function Required(ok, failure) if not ok then error(failure) end end
local function AddAppearance(id, definition)
    local key = definition.key
    local field = Configuration.Copy(definition)
    field.key = id and "window" .. id .. "_" .. key or "default_" .. key
    field.durableKey = id and "windows" or "defaults"
    field.default = Configuration.GetDefault(key)
    field.path = id and {"Chat", "Windows", Configuration.WindowLabel(id)} or {"Chat", "Appearance"}
    field.windowId = id
    field.get = function(store)
        if id then return Configuration.Resolve(store, id)[key] end
        return store.defaults[key]
    end
    field.set = function(value)
        -- The shared saved-text control supplies strings for numeric fields.
        if definition.type == "number" and type(value) == "string" then
            local number = tonumber(value)
            if not number then error("Enter a whole-number chat " .. key .. ".") end
            value = number
        end
        Required(Runtime.SetOption(id, key, value))
    end
    field.profile = not id
    if id then field.tooltip = "This setting overrides the common appearance for native chat window " .. id .. ". Reset this window from the Chat page to inherit the common appearance again." end
    if key == "width" or key == "height" then
        field.tooltip = (field.tooltip or "") .. " Docked windows share the main window size. An individual size takes effect for a detached window on the next setting change or chat-window update; zero keeps the native size."
    end
    table.insert(fields, field)
end
local function Build()
    fields = {{key = "enabled", label = "Enable native chat customizations", type = "checkbox", default = true,
        path = {"Chat", "General"}, profile = false,
        tooltip = "Turning this off restores the native chat appearance and scrolling. Your channels and messages remain available.",
        set = function(value) Required(Runtime.SetEnabled(value)) end},
        {key = "hideMinimapIcon", label = "Hide minimap icon", type = "checkbox", default = false,
        path = {"Chat", "General"}, set = function(value) Required(Runtime.SetMinimapHidden(value)) end}}
    for _, definition in ipairs(definitions) do AddAppearance(nil, definition) end
    count = Configuration.WindowCount()
    for id = 1, count do for _, definition in ipairs(definitions) do AddAppearance(id, definition) end end
    local editboxDefinitions = {
        {key = "position", label = "Input position", type = "choice", choices = {
            {value = "native", text = "Native position"}, {value = "top", text = "Above main chat"}, {value = "bottom", text = "Below main chat"}}},
        {key = "fontSize", label = "Input font size", type = "choice", choices = sizes},
        {key = "arrowKeys", label = "Arrow keys without Alt", type = "checkbox"},
    }
    for _, definition in ipairs(editboxDefinitions) do
        local key, field = definition.key, Configuration.Copy(definition)
        field.key, field.durableKey = "input_" .. key, "editbox"
        field.default, field.path = Configuration.GetDefault(key, true), {"Chat", "Input"}
        field.get = function(store) return store.editbox[key] end
        field.set = function(value) Required(Runtime.SetEditboxOption(key, value)) end
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
