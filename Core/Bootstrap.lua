BootyChat = BootyChat or {}
local Chat = BootyChat
local version = type(GetAddOnMetadata) == "function" and GetAddOnMetadata("BootyChat", "Version")
Chat.version = type(version) == "string" and version ~= "" and version or "0.1.0-dev.5"
Chat.API_VERSION = 1
Chat.Core = Chat.Core or {}
Chat.Services = Chat.Services or {}
Chat.Modules = Chat.Modules or {}
Chat.UI = BootyLib.UI
