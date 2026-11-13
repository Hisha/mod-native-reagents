-- Native Reagents service and public API. Loaded as protected FrameXML, not an addon.
NativeReagents = NativeReagents or {}
local NR = NativeReagents
local PREFIX, VERSION = "NRB", 2
NR.items, NR.callbacks, NR.available, NR.bankOpen = {}, {}, false, false
NR.autoDeposit, NR.autoKnown, NR.syncing = false, false, false
NR.status, NR.protocolVersion = "unavailable", nil
NR.remoteEnabled = false
NR.pending, NR.bankAuthorizationWarned, NR.lastError = {}, false, nil
NR.sequence = math.random(100000, 900000)
NR.syncSequence, NR.activeSync, NR.resyncPending = 0, nil, false
NR.syncTimeout, NR.syncMaxRetries = 3.0, 2

local function Notice(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7Reagent Bank:|r " .. tostring(message)) end
end

local function Send(command, ...)
    NR.sequence = NR.sequence + 1
    if NR.sequence > 2000000000 then NR.sequence = 1 end
    local payload = VERSION .. "|" .. NR.sequence .. "|" .. command
    for i = 1, select("#", ...) do payload = payload .. "|" .. tostring(select(i, ...)) end
    NR.pending[NR.sequence] = command
    SendAddonMessage(PREFIX, payload, "WHISPER", UnitName("player"))
    return NR.sequence
end

local function Fire(event, ...)
    for owner, callback in pairs(NR.callbacks) do
        local ok = pcall(callback, event, ...)
        if not ok then NR.callbacks[owner] = nil end
    end
end

function NR.IsAvailable() return NR.available end
function NR.IsReady() return NR.available and NR.status == "ready" end
function NR.GetStatus() return NR.status end
function NR.GetLastError() return NR.lastError end
function NR.IsBankOpen() return NR.bankOpen end
function NR.GetItems() return NR.items end
function NR.GetQuantity(itemId) return NR.items[tonumber(itemId)] or 0 end
function NR.GetAutoDeposit() return NR.autoKnown and NR.autoDeposit or false end
function NR.DepositAll() if not NR.bankOpen or not NR.IsReady() then return false end Send("DEPOSIT") return true end
function NR.Withdraw(itemId, quantity)
    itemId, quantity = tonumber(itemId), tonumber(quantity)
    if not NR.bankOpen or not NR.IsReady() or not itemId or not quantity or quantity < 1 then return false end
    Send("WITHDRAW", math.floor(itemId), math.floor(quantity)); return true
end
function NR.SetAutoDeposit(enabled) if not NR.bankOpen or not NR.available then return false end Send("AUTO", enabled and 1 or 0); return true end
function NR.RegisterCallback(callback, owner)
    if type(callback) ~= "function" then return false end
    owner = owner or callback; NR.callbacks[owner] = callback; return owner
end
function NR.UnregisterCallback(owner) NR.callbacks[owner] = nil end
function NR.RegisterPresentation(presentation)
    if presentation ~= nil and type(presentation) ~= "table" then return false end
    if presentation == nil then NR.presentation = nil; Fire("PRESENTATION_CHANGED", nil); return true end
    if NR.presentation and NR.presentation ~= presentation then return false end
    NR.presentation = presentation; Fire("PRESENTATION_CHANGED", presentation); return true
end
function NR.GetPresentation() return NR.presentation end

local RefreshTradeSkill, refreshingTradeSkill
local function SetStatus(status)
    if NR.status == status then return end
    NR.status = status
    Fire("STATUS_CHANGED", status)
end

local function StartSync(retries)
    NR.syncSequence = NR.syncSequence + 1
    if NR.syncSequence > 2000000000 then NR.syncSequence = 1 end
    NR.activeSync = { id=NR.syncSequence, pages={}, total=nil, started=GetTime(), retries=retries or 0 }
    NR.syncing = true
    SetStatus("loading")
    Send("SYNC", NR.activeSync.id, 0)
end
function NR.RequestSync()
    if NR.activeSync then NR.resyncPending = true else StartSync(0) end
    return true
end

local function CompleteSync(sync)
    local combined = {}
    for page = 0, sync.total - 1 do
        local rows = sync.pages[page]
        if not rows then return false end
        for itemId, quantity in pairs(rows) do combined[itemId] = quantity end
    end
    if not NR.activeSync or NR.activeSync.id ~= sync.id then return false end
    NR.items, NR.activeSync, NR.syncing = combined, nil, false
    SetStatus("ready")
    Fire("ITEMS_UPDATED", NR.items)
    RefreshTradeSkill()
    if NR.resyncPending then NR.resyncPending = false; StartSync(0) end
    return true
end

local function ItemId(link) return link and tonumber(string.match(link, "item:(%d+)")) end
local function RecipeSpell(index)
    local link = GetTradeSkillRecipeLink(index)
    return link and (tonumber(string.match(link, "enchant:(%d+)")) or tonumber(string.match(link, "spell:(%d+)")))
end
local function RecipeMax(index)
    local count, maximum, requirements, available = GetTradeSkillNumReagents(index) or 0, 999999, {}, {}
    for reagent = 1, count do
        local _, _, required, carried = GetTradeSkillReagentInfo(index, reagent)
        local id = ItemId(GetTradeSkillReagentItemLink(index, reagent))
        if id and required and required > 0 then
            requirements[id] = (requirements[id] or 0) + required
            available[id] = math.max(available[id] or 0, carried or 0)
        end
    end
    for id, required in pairs(requirements) do
        local total = available[id] + (NR.remoteEnabled and NR.GetQuantity(id) or 0)
        maximum = math.min(maximum, math.floor(total / required))
    end
    if GetTradeSkillCooldown and GetTradeSkillCooldown(index) then return 0 end
    if maximum == 999999 then
        local _, skillType, stockMaximum = GetTradeSkillInfo(index)
        return skillType ~= "header" and math.abs(stockMaximum or 0) or 0
    end
    return maximum
end
local function UsesStored(index)
    for reagent = 1, GetTradeSkillNumReagents(index) or 0 do
        local _, _, required, carried = GetTradeSkillReagentInfo(index, reagent)
        local id = ItemId(GetTradeSkillReagentItemLink(index, reagent))
        if NR.remoteEnabled and (carried or 0) < (required or 0) and (carried or 0) + NR.GetQuantity(id) >= (required or 0) then return true end
    end
end
RefreshTradeSkill = function()
    if refreshingTradeSkill then return end
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    local index = TradeSkillFrame.selectedSkill or GetTradeSkillSelectionIndex()
    if not index or index <= 0 then return end
    refreshingTradeSkill = true
    for reagent = 1, GetTradeSkillNumReagents(index) or 0 do
        local _, _, required, carried = GetTradeSkillReagentInfo(index, reagent)
        local id = ItemId(GetTradeSkillReagentItemLink(index, reagent))
        local total = (carried or 0) + (NR.remoteEnabled and NR.GetQuantity(id) or 0)
        local count = _G["TradeSkillReagent" .. reagent .. "Count"]
        if count then count:SetText((total >= 100 and "*" or total) .. " /" .. (required or 0)) end
    end
    local maximum = RecipeMax(index)
    local linked = IsTradeSkillLinked()
    if maximum > 0 and not linked then
        TradeSkillCreateButton:Enable()
        if TradeSkillCreateAllButton:IsShown() then TradeSkillCreateAllButton:Enable() end
    else
        TradeSkillCreateButton:Disable()
        TradeSkillCreateAllButton:Disable()
    end
    TradeSkillFrame.numAvailable = maximum

    -- Blizzard renders recipe-list quantities from GetTradeSkillInfo(), whose
    -- numAvailable value only includes ordinary inventory.  Replace those
    -- visible counts after the stock update with the same combined calculation
    -- used by Create All and keep the stock name/count layout intact.
    local offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame) or 0
    for row = 1, TRADE_SKILLS_DISPLAYED or 8 do
        local skillIndex = offset + row
        local name, skillType = GetTradeSkillInfo(skillIndex)
        local button = _G["TradeSkillSkill" .. row]
        local text = _G["TradeSkillSkill" .. row .. "Text"]
        local count = _G["TradeSkillSkill" .. row .. "Count"]
        if name and skillType ~= "header" and button and button:IsShown() and text and count then
            local craftable = RecipeMax(skillIndex)
            count:SetText(craftable > 0 and ("[" .. craftable .. "]") or "")
            if craftable > 0 then
                TradeSkillFrameDummyString:SetText(text:GetText() or name)
                local countWidth = count:GetWidth()
                if TradeSkillFrameDummyString:GetWidth() + 2 + countWidth > TRADE_SKILL_TEXT_WIDTH then
                    text:SetWidth(TRADE_SKILL_TEXT_WIDTH - 2 - countWidth)
                else
                    text:SetWidth(0)
                end
            else
                text:SetWidth(TRADE_SKILL_TEXT_WIDTH)
            end
        end
    end
    refreshingTradeSkill = false
end
local function InstallTradeSkill()
    if NR.tradeHooked or not TradeSkillFrame then return end
    NR.tradeHooked = true
    hooksecurefunc("TradeSkillFrame_SetSelection", RefreshTradeSkill)
    hooksecurefunc("TradeSkillFrame_Update", RefreshTradeSkill)
    TradeSkillCreateButton:SetScript("OnClick", function()
        local index, count = TradeSkillFrame.selectedSkill, math.max(1, TradeSkillInputBox:GetNumber() or 1)
        if UsesStored(index) then local spell = RecipeSpell(index); if spell then Send("CRAFT", spell, count) else Notice("Unable to identify this recipe.") end
        else DoTradeSkill(index, count) end
        TradeSkillInputBox:ClearFocus()
    end)
    TradeSkillCreateAllButton:SetScript("OnClick", function()
        local index = TradeSkillFrame.selectedSkill; local count = math.max(1, RecipeMax(index)); TradeSkillInputBox:SetNumber(count)
        if UsesStored(index) then local spell = RecipeSpell(index); if spell then Send("CRAFT", spell, count) end else DoTradeSkill(index, count) end
        TradeSkillInputBox:ClearFocus()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN"); events:RegisterEvent("CHAT_MSG_ADDON"); events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED"); events:RegisterEvent("ADDON_LOADED"); events:RegisterEvent("TRADE_SKILL_UPDATE"); events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then NR.helloStarted = GetTime(); Send("HELLO"); StartSync(0); return end
    if event == "BANKFRAME_OPENED" then
        NR.bankOpen, NR.bankAuthorizationWarned, NR.lastError = true, false, nil
        Send("BANKOPEN"); Fire("BANK_OPENED"); return
    end
    if event == "BANKFRAME_CLOSED" then NR.bankOpen = false; Send("BANKCLOSE"); Fire("BANK_CLOSED"); return end
    if event == "ADDON_LOADED" then if (...) == "Blizzard_TradeSkillUI" then InstallTradeSkill(); NR.RequestSync() end return end
    if event == "TRADE_SKILL_UPDATE" or event == "BAG_UPDATE" then if TradeSkillFrame and TradeSkillFrame:IsShown() then RefreshTradeSkill(); NR.RequestSync() end return end
    local prefix, message, channel, sender = ...
    if prefix ~= PREFIX or channel ~= "WHISPER" or sender ~= UnitName("player") then return end
    local version, request, kind, body = string.match(message, "^(%d+)|(%d+)|([^|]+)|?(.*)$")
    if tonumber(version) ~= VERSION then return end
    request = tonumber(request)
    local command = NR.pending[request]
    NR.pending[request] = nil
    NR.available = true; NR.protocolVersion = tonumber(version)
    if kind == "HELLO" then local remote = string.match(body, "^([01])|"); NR.remoteEnabled = remote == "1"; InstallTradeSkill(); Fire("AVAILABLE", true); return end
    if kind == "DATA" then
        local syncId, pageIndex, totalPages, rows = string.match(body, "^(%d+)|(%d+)|(%d+)|(.*)$")
        syncId, pageIndex, totalPages = tonumber(syncId), tonumber(pageIndex), tonumber(totalPages)
        local sync = NR.activeSync
        if not sync or sync.id ~= syncId or not pageIndex or not totalPages or totalPages < 1 or pageIndex >= totalPages then return end
        if sync.total and sync.total ~= totalPages then NR.resyncPending = true; return end
        sync.total = totalPages
        local parsed = {}
        for pair in string.gmatch(rows or "", "[^,]+") do
            local id, quantity = string.match(pair, "^(%d+):(%d+)$")
            if not id then NR.resyncPending = true; return end
            parsed[tonumber(id)] = tonumber(quantity)
        end
        sync.pages[pageIndex] = parsed
        sync.started = GetTime()
        if pageIndex == 0 then
            for page = 1, totalPages - 1 do if not sync.pages[page] then Send("SYNC", sync.id, page) end end
        end
        CompleteSync(sync)
        return
    end
    if kind == "BANK" then local deposited, enabled = string.match(body, "^(%d+)|([01])$"); NR.lastError = nil; NR.autoDeposit, NR.autoKnown = enabled == "1", true; Fire("AUTO_DEPOSIT_CHANGED", NR.autoDeposit); if tonumber(deposited) and tonumber(deposited) > 0 then NR.RequestSync() end return end
    if kind == "AUTO" then NR.lastError = nil; NR.autoDeposit, NR.autoKnown = body == "1", true; Fire("AUTO_DEPOSIT_CHANGED", NR.autoDeposit); return end
    if kind == "DEPOSITED" or kind == "WITHDRAWN" then NR.lastError = nil; NR.RequestSync(); return end
    if kind == "ERR" then
        NR.lastError = body
        if body == "banker-required" then
            if command ~= "BANKOPEN" and not NR.bankAuthorizationWarned then
                NR.bankAuthorizationWarned = true
                Notice("This reagent operation requires an active banker session.")
            end
        else
            Notice(body)
        end
        Fire("ERROR", body, command)
        return
    end
end)

local watchdog = CreateFrame("Frame")
watchdog.elapsed = 0
watchdog:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    local now = GetTime()
    if not NR.available and NR.helloStarted and now - NR.helloStarted >= 5 then
        NR.helloStarted = nil; NR.activeSync = nil; NR.syncing = false; SetStatus("unavailable"); Fire("AVAILABLE", false)
    end
    local sync = NR.activeSync
    if sync and now - sync.started >= NR.syncTimeout then
        if sync.retries < NR.syncMaxRetries then StartSync(sync.retries + 1)
        else
            NR.activeSync, NR.syncing = nil, false
            SetStatus("failed")
            Fire("SYNC_FAILED", "timeout")
        end
    end
end)
