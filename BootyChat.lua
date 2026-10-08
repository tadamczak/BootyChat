local Chat = BootyChat
local Runtime = Chat.Core.Runtime
Chat.Product = {
    id = "chat", name = "BootyChat", title = "BootyChat", settingsLabel = "Chat",
    version = Chat.version, apiVersion = Chat.API_VERSION, namespace = Chat,
    description = "Native chat appearance, bounded history, optional message filters and mentions, with your own tabs.",
    requiredAddons = {"BootyLib"},
    Initialize = Runtime.Initialize, OnHostReady = Runtime.OnHostReady,
    OnActivationFailed = Runtime.OnActivationFailed,
    GetDatabase = Chat.Database.Ensure, GetSettings = Chat.GetSettings,
    Stop = Runtime.Stop, Start = Runtime.Start, IsBusy = Runtime.IsBusy,
    BeginSettingsBatch = Runtime.BeginSettingsBatch, EndSettingsBatch = Runtime.EndSettingsBatch,
    OnSettingsProfileApplied = Runtime.OnSettingsProfileApplied,
    views = {{id = "chat", label = "Chat", icon = "list", create = Runtime.CreateView,
        IsAvailable = Runtime.IsAvailable, width = 580, height = 420, minWidth = 350, minHeight = 300}},
    GetQuickMenu = function(host)
        return {{text = "Chat", icon = "list", enabled = Runtime.IsAvailable(), action = function() return host.OpenView("chat") end}}
    end,
}
local product, failure = BootyLib.RegisterProduct(Chat.Product)
if not product then BootyLib.Print(failure) end
SlashCmdList = SlashCmdList or {}
SLASH_BOOTYCHAT1, SLASH_BOOTYCHAT2 = "/bc", "/bootychat"
SlashCmdList.BOOTYCHAT = function(command)
    command = string.lower(string.gsub(string.gsub(command or "", "^%s+", ""), "%s+$", ""))
    local ok, reason = Runtime.Open(command)
    if ok == false and reason then BootyLib.Print("BootyChat: " .. tostring(reason)) end
    return ok, reason
end
