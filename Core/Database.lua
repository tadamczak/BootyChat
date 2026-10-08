local Chat = BootyChat
local Assert = assert
local function error(message) Assert(false, message) end
local Configuration = Chat.Services.Configuration
local Database = {SCHEMA_VERSION = 1}
Chat.Database = Database

local function Defaults(store)
    local valid, failure = Configuration.Validate(store)
    if not valid then error(failure) end
    store.schemaVersion = Database.SCHEMA_VERSION
    if store.enabled == nil then store.enabled = true end
    if store.hideMinimapIcon == nil then store.hideMinimapIcon = false end
    store.defaults = store.defaults or {}
    store.windows = store.windows or {}
    store.editbox = store.editbox or {}
    store.history = store.history or {}
    store.moderation = store.moderation or {}
    if type(store.presentation) ~= "table" then store.presentation = {} end
    if type(store.presentation.windows) ~= "table" then store.presentation.windows = {} end
    if type(store.presentation.minimap) ~= "table" then store.presentation.minimap = {angle = 225} end
    store.addonVersion = Chat.version
end
-- A new product owns no legacy MOS settings or chat logs.
BootyLib.Data.RegisterOwner("chat", "BootyChatDB", function() return false end, Defaults)
function Database.Ensure()
    local valid, failure = Configuration.Validate(BootyChatDB)
    if not valid then return nil, failure end
    return BootyLib.Data.Ensure("chat")
end
