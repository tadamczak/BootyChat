local Chat = BootyChat
local Overview = {}
Chat.Modules.Overview = Overview

function Overview.Create(parent, host)
    local view = Chat.Modules.HistoryView.Create(parent, host, nil, parent)
    view.history, view.mode = view, "history"
    -- Keep the existing host/slash entry points on the same pooled page.
    function view:ShowHistory() return self:Show() end
    function view:ShowOverview() return self:Show() end
    return view
end
