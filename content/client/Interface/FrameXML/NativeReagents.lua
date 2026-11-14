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
function NR.Deposit(itemId, quantity)
    itemId, quantity = tonumber(itemId), tonumber(quantity)
    if not NR.bankOpen or not NR.IsReady() or not itemId or not quantity or
        itemId < 1 or quantity < 1 or itemId > 4294967295 or quantity > 4294967295 or
        itemId ~= math.floor(itemId) or quantity ~= math.floor(quantity) then return false end
    local request = Send("DEPOSIT_ITEM", itemId, quantity); return true, request
end
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

local QueueRefresh, InvalidateTradeSkillFilter
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
    InvalidateTradeSkillFilter()
    QueueRefresh()
    if NR.resyncPending then NR.resyncPending = false; StartSync(0) end
    return true
end

local function ItemIDFromLink(link) return link and tonumber(string.match(link, "item:(%d+)")) end
local function SpellIDForRecipe(index)
    local link = GetTradeSkillRecipeLink(index)
    return link and (tonumber(string.match(link, "enchant:(%d+)")) or tonumber(string.match(link, "spell:(%d+)")))
end
local function CombinedForReagent(skillIndex, reagentIndex)
    local _, _, required, carried = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
    local itemId = ItemIDFromLink(GetTradeSkillReagentItemLink(skillIndex, reagentIndex))
    local stored = itemId and NR.GetQuantity(itemId) or 0
    return (carried or 0) + stored, required or 0, carried or 0, stored, itemId
end

local function RecipeMax(index)
    local name, skillType = GetTradeSkillInfo(index)
    if not name or skillType == "header" then return 0 end
    local count = GetTradeSkillNumReagents(index) or 0
    if count == 0 then
        local _, _, normal = GetTradeSkillInfo(index)
        return math.max(0, normal or 0)
    end
    local maximum = 999999
    for reagent = 1, count do
        local combined, required = CombinedForReagent(index, reagent)
        if required > 0 then maximum = math.min(maximum, math.floor(combined / required)) end
    end
    if maximum == 999999 then return 0 end
    return maximum
end

local function RecipeUsesVirtual(index)
    for reagent = 1, GetTradeSkillNumReagents(index) or 0 do
        local combined, required, carried = CombinedForReagent(index, reagent)
        if combined >= required and carried < required then return true end
    end
    return false
end

local filteredTradeSkills = { dirty=true, indices=nil }
InvalidateTradeSkillFilter = function()
    filteredTradeSkills.dirty = true
end

local function TradeSkillFilterEnabled()
    return TradeSkillFrameAvailableFilterCheckButton and TradeSkillFrameAvailableFilterCheckButton:GetChecked()
end

local function NativeIndexForVisibleRow(visibleIndex)
    if TradeSkillFilterEnabled() and filteredTradeSkills.indices then
        return filteredTradeSkills.indices[visibleIndex]
    end
    return visibleIndex
end

local function BuildFilteredTradeSkills()
    filteredTradeSkills.dirty = false
    if not TradeSkillFilterEnabled() then filteredTradeSkills.indices = nil; return end

    local indices = {}
    local headerIndex, headerAdded, headerExpanded
    local function FinishHeader()
        -- Collapsed children are not exposed by the 3.3.5 API.  Retain their
        -- header without expanding it or changing the user's category state.
        if headerIndex and not headerAdded and not headerExpanded then
            table.insert(indices, headerIndex)
        end
    end
    for index = 1, GetNumTradeSkills() or 0 do
        local name, skillType, _, isExpanded = GetTradeSkillInfo(index)
        if name and skillType == "header" then
            FinishHeader()
            headerIndex, headerAdded, headerExpanded = index, false, isExpanded and true or false
        elseif name and RecipeMax(index) > 0 then
            if headerIndex and not headerAdded then
                table.insert(indices, headerIndex)
                headerAdded = true
            end
            table.insert(indices, index)
        end
    end
    FinishHeader()
    filteredTradeSkills.indices = indices
end

local function FilterContains(index)
    for _, nativeIndex in ipairs(filteredTradeSkills.indices or {}) do
        if nativeIndex == index then return true end
    end
    return false
end

local function ClearTradeSkillSelection()
    TradeSkillFrame.selectedSkill = 0
    TradeSkillFrame.numAvailable = 0
    TradeSkillCreateButton:Disable()
    TradeSkillCreateAllButton:Disable()
    if TradeSkillHighlightFrame then TradeSkillHighlightFrame:Hide() end
    if TradeSkillSkillName then TradeSkillSkillName:SetText("") end
    if TradeSkillSkillCooldown then TradeSkillSkillCooldown:SetText("") end
    if TradeSkillSkillIcon then TradeSkillSkillIcon:SetNormalTexture("") end
    if TradeSkillDescription then TradeSkillDescription:SetText("") end
    for reagent = 1, MAX_TRADE_SKILL_REAGENTS or 8 do
        local button = _G["TradeSkillReagent" .. reagent]
        if button then button:Hide() end
    end
end

local function EnsureFilteredSelection()
    if not TradeSkillFilterEnabled() or FilterContains(TradeSkillFrame.selectedSkill) then return end
    for _, index in ipairs(filteredTradeSkills.indices or {}) do
        local _, skillType = GetTradeSkillInfo(index)
        if skillType and skillType ~= "header" then
            TradeSkillFrame_SetSelection(index)
            return
        end
    end
    ClearTradeSkillSelection()
end

local function RenderFilteredTradeSkills()
    if not TradeSkillFilterEnabled() then return end
    local indices = filteredTradeSkills.indices or {}
    local maximumOffset = math.max(0, #indices - TRADE_SKILLS_DISPLAYED)
    local offset = math.min(FauxScrollFrame_GetOffset(TradeSkillListScrollFrame), maximumOffset)
    if offset ~= FauxScrollFrame_GetOffset(TradeSkillListScrollFrame) then
        FauxScrollFrame_SetOffset(TradeSkillListScrollFrame, offset)
    end
    FauxScrollFrame_Update(TradeSkillListScrollFrame, #indices, TRADE_SKILLS_DISPLAYED,
        TRADE_SKILL_HEIGHT, nil, nil, nil, TradeSkillHighlightFrame, 293, 316)
    TradeSkillHighlightFrame:Hide()

    for row = 1, TRADE_SKILLS_DISPLAYED do
        local index = indices[offset + row]
        local button = _G["TradeSkillSkill" .. row]
        local text = _G["TradeSkillSkill" .. row .. "Text"]
        local count = _G["TradeSkillSkill" .. row .. "Count"]
        local highlight = _G["TradeSkillSkill" .. row .. "Highlight"]
        if index then
            local name, skillType, _, isExpanded = GetTradeSkillInfo(index)
            local color = TradeSkillTypeColor[skillType]
            local prefix = ENABLE_COLORBLIND_MODE == "1" and (TradeSkillTypePrefix[skillType] or " ") or " "
            button:SetID(index)
            button:Show()
            button:SetWidth(TradeSkillListScrollFrame:IsShown() and 293 or 323)
            if color then
                button:SetNormalFontObject(color.font)
                count:SetVertexColor(color.r, color.g, color.b)
                button.r, button.g, button.b = color.r, color.g, color.b
            end
            if skillType == "header" then
                button:SetText(name)
                text:SetText(name)
                text:SetWidth(TRADE_SKILL_TEXT_WIDTH)
                count:SetText("")
                button:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or
                    "Interface\\Buttons\\UI-PlusButton-Up")
                if highlight then highlight:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight") end
                button:UnlockHighlight()
                button.isHighlighted = false
            else
                local maximum = RecipeMax(index)
                local displayName = prefix .. name
                button:SetNormalTexture("")
                if highlight then highlight:SetTexture("") end
                button:SetText(displayName)
                text:SetText(displayName)
                count:SetText(maximum > 0 and ("[" .. maximum .. "]") or "")
                TradeSkillFrameDummyString:SetText(displayName)
                if TradeSkillFrameDummyString:GetWidth() + 2 + count:GetWidth() > TRADE_SKILL_TEXT_WIDTH then
                    text:SetWidth(TRADE_SKILL_TEXT_WIDTH - 2 - count:GetWidth())
                else
                    text:SetWidth(0)
                end
                if TradeSkillFrame.selectedSkill == index then
                    TradeSkillHighlightFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                    TradeSkillHighlightFrame:Show()
                    count:SetVertexColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                    button:LockHighlight()
                    button.isHighlighted = true
                else
                    button:UnlockHighlight()
                    button.isHighlighted = false
                end
            end
        else
            button:Hide()
            button:UnlockHighlight()
            button.isHighlighted = false
        end
    end
end

local function ApplySelection()
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    local index = TradeSkillFrame.selectedSkill or GetTradeSkillSelectionIndex()
    if not index or index <= 0 then return end

    local skillName, skillType = GetTradeSkillInfo(index)
    if not skillName or skillType == "header" then return end

    local creatable = true
    for reagent = 1, GetTradeSkillNumReagents(index) or 0 do
        local total, required = CombinedForReagent(index, reagent)
        local count = _G["TradeSkillReagent" .. reagent .. "Count"]
        if total < required then creatable = false end
        if count then
            count:SetText((total >= 100 and "*" or tostring(total)) .. " /" .. required)
        end
    end

    if creatable and not IsTradeSkillLinked() then
        TradeSkillCreateButton:Enable()
        if TradeSkillCreateAllButton:IsShown() then TradeSkillCreateAllButton:Enable() end
    else
        TradeSkillCreateButton:Disable()
        TradeSkillCreateAllButton:Disable()
    end
    TradeSkillFrame.numAvailable = RecipeMax(index)
end

local function ApplyList()
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    local offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame)
    for row = 1, TRADE_SKILLS_DISPLAYED do
        local index = NativeIndexForVisibleRow(row + offset)
        local name, skillType
        if index then name, skillType = GetTradeSkillInfo(index) end
        local button = _G["TradeSkillSkill" .. row]
        local text = _G["TradeSkillSkill" .. row .. "Text"]
        local count = _G["TradeSkillSkill" .. row .. "Count"]
        if name and skillType ~= "header" and button and count then
            local maximum = RecipeMax(index)
            if maximum > 0 then count:SetText("[" .. maximum .. "]") else count:SetText("") end
            if text and TradeSkillFrameDummyString then
                TradeSkillFrameDummyString:SetText(text:GetText() or name)
                local nameWidth = TradeSkillFrameDummyString:GetWidth()
                local countWidth = count:GetWidth()
                if nameWidth + 2 + countWidth > TRADE_SKILL_TEXT_WIDTH then
                    text:SetWidth(TRADE_SKILL_TEXT_WIDTH - 2 - countWidth)
                else
                    text:SetWidth(0)
                end
            end
        end
    end
end

local function RefreshUI()
    if filteredTradeSkills.dirty then BuildFilteredTradeSkills() end
    EnsureFilteredSelection()
    RenderFilteredTradeSkills()
    ApplySelection()
    ApplyList()
end

local countGuard = CreateFrame("Frame")
countGuard.elapsed = 0
countGuard:SetScript("OnUpdate", function(self, elapsed)
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then self.elapsed = 0; return end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.10 then return end
    self.elapsed = 0
    ApplyList()
end)

local refreshFrame = CreateFrame("Frame")
QueueRefresh = function()
    if NR.refreshPending then return end
    NR.refreshPending = true
    refreshFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        NR.refreshPending = false
        RefreshUI()
    end)
end

local function InstallTradeSkill()
    if NR.tradeHooked or not TradeSkillFrame then return end
    NR.tradeHooked = true
    local NativeTradeSkillOnlyShowMakeable = TradeSkillOnlyShowMakeable
    local disablingNativeFilter = false
    local function DisableNativeTradeSkillFilter()
        if disablingNativeFilter then return end
        disablingNativeFilter = true
        NativeTradeSkillOnlyShowMakeable(false)
        disablingNativeFilter = false
    end
    -- Blizzard reapplies this filter from TradeSkillFrame_Show.  Keep the
    -- native list complete so bank-only recipes remain available to our map.
    TradeSkillOnlyShowMakeable = function() DisableNativeTradeSkillFilter() end
    DisableNativeTradeSkillFilter()
    TradeSkillFrameAvailableFilterCheckButton:SetScript("OnClick", function()
        DisableNativeTradeSkillFilter()
        InvalidateTradeSkillFilter()
        FauxScrollFrame_SetOffset(TradeSkillListScrollFrame, 0)
        TradeSkillFrame_Update()
    end)
    hooksecurefunc("TradeSkillFrame_SetSelection", ApplySelection)
    hooksecurefunc("TradeSkillFrame_Update", RefreshUI)
    hooksecurefunc("TradeSkillFrame_Show", function()
        DisableNativeTradeSkillFilter()
        InvalidateTradeSkillFilter()
        QueueRefresh()
    end)
    local lastFilterArguments = {}
    for _, functionName in ipairs({ "SetTradeSkillItemNameFilter", "SetTradeSkillItemLevelFilter",
        "SetTradeSkillSubClassFilter", "SetTradeSkillInvSlotFilter" }) do
        local hookedName = functionName
        if type(_G[hookedName]) == "function" then
            hooksecurefunc(hookedName, function(...)
                local arguments = ""
                for argument = 1, select("#", ...) do
                    arguments = arguments .. "\031" .. tostring(select(argument, ...))
                end
                if lastFilterArguments[hookedName] ~= arguments then
                    lastFilterArguments[hookedName] = arguments
                    InvalidateTradeSkillFilter()
                end
            end)
        end
    end
    for _, functionName in ipairs({ "ExpandTradeSkillSubClass", "CollapseTradeSkillSubClass" }) do
        if type(_G[functionName]) == "function" then hooksecurefunc(functionName, InvalidateTradeSkillFilter) end
    end
    TradeSkillCreateButton:SetScript("OnClick", function()
        local index, count = TradeSkillFrame.selectedSkill, math.max(1, TradeSkillInputBox:GetNumber() or 1)
        if NR.remoteEnabled and RecipeUsesVirtual(index) then local spell = SpellIDForRecipe(index); if spell then Send("CRAFT", spell, count) else Notice("Unable to identify this recipe.") end
        else DoTradeSkill(index, count) end
        TradeSkillInputBox:ClearFocus()
    end)
    TradeSkillCreateAllButton:SetScript("OnClick", function()
        local index = TradeSkillFrame.selectedSkill; local count = math.max(1, RecipeMax(index)); TradeSkillInputBox:SetNumber(count)
        if NR.remoteEnabled and RecipeUsesVirtual(index) then local spell = SpellIDForRecipe(index); if spell then Send("CRAFT", spell, count) end else DoTradeSkill(index, count) end
        TradeSkillInputBox:ClearFocus()
    end)
    TradeSkillFrame:HookScript("OnShow", function() InvalidateTradeSkillFilter(); NR.RequestSync() end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN"); events:RegisterEvent("CHAT_MSG_ADDON"); events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED"); events:RegisterEvent("ADDON_LOADED"); events:RegisterEvent("TRADE_SKILL_UPDATE"); events:RegisterEvent("TRADE_SKILL_FILTER_UPDATE"); events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then NR.helloStarted = GetTime(); Send("HELLO"); StartSync(0); return end
    if event == "BANKFRAME_OPENED" then
        NR.bankOpen, NR.bankAuthorizationWarned, NR.lastError = true, false, nil
        Send("BANKOPEN"); Fire("BANK_OPENED"); return
    end
    if event == "BANKFRAME_CLOSED" then NR.bankOpen = false; Send("BANKCLOSE"); Fire("BANK_CLOSED"); return end
    if event == "ADDON_LOADED" then if (...) == "Blizzard_TradeSkillUI" then InstallTradeSkill(); NR.RequestSync() end return end
    if event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_FILTER_UPDATE" then
        InvalidateTradeSkillFilter()
        if TradeSkillFrame and TradeSkillFrame:IsShown() then QueueRefresh() end
        return
    end
    if event == "BAG_UPDATE" then
        if TradeSkillFrame and TradeSkillFrame:IsShown() then
            InvalidateTradeSkillFilter()
            QueueRefresh()
            NR.RequestSync()
        end
        return
    end
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
    if kind == "DEPOSITED" or kind == "WITHDRAWN" then
        NR.lastError = nil
        if kind == "DEPOSITED" and command == "DEPOSIT_ITEM" then
            local itemId, quantity = string.match(body, "^(%d+)|(%d+)$")
            if itemId then Fire("DEPOSITED", tonumber(itemId), tonumber(quantity), request) end
        end
        NR.RequestSync(); return
    end
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
        Fire("ERROR", body, command, request)
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
