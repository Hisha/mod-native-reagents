local NR = NativeReagents
local view, buttons, page = nil, {}, 0
local columns, perPage = 7, 42
-- Stock BankFrame item buttons are 37x37, with 12 horizontal and 7 vertical
-- gaps.  Keeping the native pitch is important because ItemButtonTemplate's
-- 64x64 UI-Quickslot2 normal texture extends outside the button itself.
local slotWidth, slotHeight, columnPitch, rowPitch = 37, 37, 49, 44
local stockFrames, stockLabels, stockState = {}, {}, nil
local reagentsSelected = false

local quality = {
    [0] = {0.62, 0.62, 0.62}, [1] = {1, 1, 1}, [2] = {0.12, 1, 0},
    [3] = {0, 0.44, 0.87}, [4] = {0.64, 0.21, 0.93}, [5] = {1, 0.5, 0}
}

local function FindStockFrames()
    local function Add(frame) if frame then table.insert(stockFrames, frame) end end
    for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do Add(_G["BankFrameItem" .. i]) end
    for i = 1, (NUM_BANKBAGSLOTS or 7) do Add(_G["BankFrameBag" .. i]) end
    -- PurchaseButton and DetailMoneyFrame are descendants of PurchaseInfo in
    -- Blizzard's BankFrame.xml, but include them explicitly so a direct Show()
    -- cannot escape the selected page if custom FrameXML has reparented them.
    Add(BankFramePurchaseInfo)
    Add(BankFramePurchaseButton)
    Add(BankFrameDetailMoneyFrame)
    Add(BankFrameMoneyFrame)

    -- The stock "Item Slots" and "Bag Slots" labels are anonymous regions on
    -- BankFrame.  BankFrameTitleText is named and must remain visible.
    local regions = {BankFrame:GetRegions()}
    for _, region in ipairs(regions) do
        if region ~= BankFrameTitleText and region:GetObjectType() == "FontString" then
            table.insert(stockLabels, region)
        end
    end
end

local function EnforceStockHidden()
    if not reagentsSelected then return end
    for _, frame in ipairs(stockFrames) do frame:Hide() end
    for _, region in ipairs(stockLabels) do region:Hide() end
end

local function HideStock()
    if not stockState then
        stockState = {}
        for _, frame in ipairs(stockFrames) do stockState[frame] = frame:IsShown() and true or false end
        for _, region in ipairs(stockLabels) do stockState[region] = region:IsShown() and true or false end
    end
    EnforceStockHidden()
end

local function InstallStockVisibilityGuards()
    for _, frame in ipairs(stockFrames) do
        frame:HookScript("OnShow", function(self)
            if reagentsSelected then self:Hide() end
        end)
    end
    local function EnforceAfterStockUpdate() EnforceStockHidden() end
    if BankFrameItemButton_Update then hooksecurefunc("BankFrameItemButton_Update", EnforceAfterStockUpdate) end
    if UpdateBagSlotStatus then hooksecurefunc("UpdateBagSlotStatus", EnforceAfterStockUpdate) end
    if BankFrame_OnShow then hooksecurefunc("BankFrame_OnShow", EnforceAfterStockUpdate) end
    if BankFrame_OnEvent then hooksecurefunc("BankFrame_OnEvent", EnforceAfterStockUpdate) end
end

local function RestoreStock()
    reagentsSelected = false
    if not stockState then return end
    for frame, shown in pairs(stockState) do
        if shown then frame:Show() else frame:Hide() end
    end
    stockState = nil
end

local function HideStockForPage()
    reagentsSelected = true
    HideStock()
end

local function RefreshStockVisibility()
    if reagentsSelected then
        EnforceStockHidden()
    end
end

local function SortedItems()
    local result = {}
    for id, quantity in pairs(NR.GetItems()) do
        if quantity > 0 then table.insert(result, {id = id, quantity = quantity}) end
    end
    table.sort(result, function(a, b)
        local an, bn = GetItemInfo(a.id) or "", GetItemInfo(b.id) or ""
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    return result
end

local function SetTab(tab)
    if not view then return end
    if tab == 2 then
        PanelTemplates_DeselectTab(view.bankTab)
        PanelTemplates_SelectTab(view.reagentTab)
    else
        PanelTemplates_DeselectTab(view.reagentTab)
        PanelTemplates_SelectTab(view.bankTab)
    end
end

local function Refresh()
    if not view or not view:IsShown() then return end
    local items = SortedItems()
    local maximum = math.max(0, math.ceil(#items / perPage) - 1)
    page = math.min(page, maximum)
    local ready, status = NR.IsReady(), NR.GetStatus()

    if NR.GetLastError and NR.GetLastError() == "banker-required" then
        view.statusText:SetText("Banker session was not authorized")
    elseif not ready then
        local labels = {
            loading = "Loading reagent bank...",
            failed = "Synchronization failed",
            unavailable = "Reagent service unavailable"
        }
        view.statusText:SetText(labels[status] or "Waiting for reagent service...")
    elseif #items == 0 then
        view.statusText:SetText("No reagents stored")
    else
        view.statusText:SetText("")
    end

    view.pageText:SetText("Page " .. (page + 1) .. " of " .. (maximum + 1))
    if ready and page > 0 then view.previous:Enable() else view.previous:Disable() end
    if ready and page < maximum then view.next:Enable() else view.next:Disable() end
    local bankerAuthorized = not NR.GetLastError or NR.GetLastError() ~= "banker-required"
    if ready and NR.IsBankOpen() and bankerAuthorized then view.deposit:Enable() else view.deposit:Disable() end
    if NR.IsAvailable() and NR.IsBankOpen() and bankerAuthorized then view.auto:Enable() else view.auto:Disable() end

    for slot = 1, perPage do
        local button = buttons[slot]
        local row = items[page * perPage + slot]
        button.itemId, button.quantity = nil, nil
        SetItemButtonTexture(button, nil)
        SetItemButtonCount(button, 0)
        button.border:Hide()
        if row and ready then
            button.itemId, button.quantity = row.id, row.quantity
            SetItemButtonTexture(button, GetItemIcon(row.id))
            SetItemButtonCount(button, row.quantity)
            local _, _, itemQuality = GetItemInfo(row.id)
            local color = quality[itemQuality or 1] or quality[1]
            button.border:SetVertexColor(color[1], color[2], color[3], 0.85)
            button.border:Show()
        end
        button:Show()
    end
end

StaticPopupDialogs["NATIVE_REAGENTS_WITHDRAW"] = {
    text = "Withdraw how many?", button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self)
        local amount = tonumber(self.editBox:GetText())
        if amount and self.data then NR.Withdraw(self.data, math.floor(amount)) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent, amount = self:GetParent(), tonumber(self:GetText())
        if amount and parent.data then NR.Withdraw(parent.data, math.floor(amount)) end
        parent:Hide()
    end
}

local function ShowReagents()
    if not view or (NR.GetPresentation() and NR.GetPresentation() ~= view) then return end
    HideStockForPage()
    view:Show()
    page = 0
    SetTab(2)
    Refresh()
    NR.RequestSync()
end

local function ShowBank()
    if not view then return end
    view:Hide()
    RestoreStock()
    SetTab(1)
end

local function Build()
    if view or not BankFrame then return end

    FindStockFrames()
    InstallStockVisibilityGuards()

    -- Publish the frame and button arrays only after every item button exists. If a
    -- previous interrupted load left named frames behind, reuse them exactly once.
    local candidate = _G.NativeReagentsBankFrame or CreateFrame("Frame", "NativeReagentsBankFrame", BankFrame)
    local createdButtons = {}
    candidate:ClearAllPoints()
    candidate:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 22, -58)
    candidate:SetPoint("BOTTOMRIGHT", BankFrame, "BOTTOMRIGHT", -43, 68)
    candidate:SetFrameLevel(BankFrame:GetFrameLevel() + 8)
    candidate:EnableMouseWheel(true)

    local background = candidate.background or candidate:CreateTexture(nil, "BACKGROUND")
    candidate.background = background
    background:SetAllPoints()
    background:SetTexture("Interface\\BankFrame\\Bank-Background")
    background:SetTexCoord(0, 0.70, 0, 0.78)

    local bankTab = _G.NativeReagentsBankTab or CreateFrame("Button", "NativeReagentsBankTab", BankFrame, "CharacterFrameTabButtonTemplate")
    bankTab:ClearAllPoints()
    -- BankFrame is 512 high, but its visible artwork ends about 70 UI units
    -- above its geometric bottom.  Anchor to that artwork edge, not the
    -- transparent tail represented by BankFrame's bottom.
    bankTab:SetPoint("TOPLEFT", BankFrame, "BOTTOMLEFT", 30, 70)
    bankTab:SetFrameLevel(BankFrame:GetFrameLevel() + 9)
    bankTab:SetText("Bank")
    bankTab:SetScript("OnClick", ShowBank)
    PanelTemplates_TabResize(bankTab, 0)

    local reagentTab = _G.NativeReagentsReagentTab or CreateFrame("Button", "NativeReagentsReagentTab", BankFrame, "CharacterFrameTabButtonTemplate")
    reagentTab:ClearAllPoints()
    reagentTab:SetPoint("LEFT", bankTab, "RIGHT", -15, 0)
    reagentTab:SetFrameLevel(BankFrame:GetFrameLevel() + 9)
    reagentTab:SetText("Reagents")
    reagentTab:SetScript("OnClick", ShowReagents)
    PanelTemplates_TabResize(reagentTab, 0)

    local controls = candidate.controls or CreateFrame("Frame", nil, candidate)
    candidate.controls = controls
    controls:ClearAllPoints()
    controls:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 4)
    controls:SetSize(360, 44)
    controls:SetFrameLevel(candidate:GetFrameLevel() + 1)
    local divider = controls.divider or controls:CreateTexture(nil, "ARTWORK")
    controls.divider = divider
    divider:ClearAllPoints()
    divider:SetPoint("TOP", controls, "TOP", 0, 0)
    divider:SetSize(346, 1)
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.45, 0.36, 0.16)

    local deposit = _G.NativeReagentsDepositButton or CreateFrame("Button", "NativeReagentsDepositButton", controls, "UIPanelButtonTemplate")
    deposit:SetParent(controls)
    deposit:SetSize(145, 24)
    deposit:ClearAllPoints()
    deposit:SetPoint("BOTTOMRIGHT", controls, "BOTTOMRIGHT", -16, 8)
    deposit:SetText("Deposit Reagents")
    deposit:SetScript("OnClick", NR.DepositAll)

    local auto = _G.NativeReagentsAutoDeposit or CreateFrame("CheckButton", "NativeReagentsAutoDeposit", controls, "UICheckButtonTemplate")
    auto:SetParent(controls)
    auto:ClearAllPoints()
    auto:SetPoint("BOTTOMLEFT", controls, "BOTTOMLEFT", 14, 6)
    local autoText = auto.text or auto:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    auto.text = autoText
    autoText:ClearAllPoints()
    autoText:SetPoint("LEFT", auto, "RIGHT", -2, 1)
    autoText:SetText("Auto Deposit")
    auto:SetScript("OnClick", function(self)
        local requested = self:GetChecked() and true or false
        self:SetChecked(NR.GetAutoDeposit())
        self:Disable()
        if not NR.SetAutoDeposit(requested) then self:Enable() end
    end)

    local previous = _G.NativeReagentsPrevious or CreateFrame("Button", "NativeReagentsPrevious", candidate, "UIPanelButtonTemplate")
    previous:SetSize(90, 22)
    previous:ClearAllPoints()
    previous:SetPoint("BOTTOMLEFT", candidate, "BOTTOMLEFT", 20, 60)
    previous:SetText("Previous")
    previous:SetScript("OnClick", function() page = math.max(0, page - 1); Refresh() end)

    local nextButton = _G.NativeReagentsNext or CreateFrame("Button", "NativeReagentsNext", candidate, "UIPanelButtonTemplate")
    nextButton:SetSize(90, 22)
    nextButton:ClearAllPoints()
    nextButton:SetPoint("BOTTOMRIGHT", candidate, "BOTTOMRIGHT", -20, 60)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function() page = page + 1; Refresh() end)

    local pageText = candidate.pageText or candidate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    candidate.pageText = pageText
    pageText:ClearAllPoints()
    pageText:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 65)

    local statusText = candidate.statusText or candidate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candidate.statusText = statusText
    statusText:ClearAllPoints()
    statusText:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 91)

    candidate:SetScript("OnMouseWheel", function(_, delta)
        if NR.IsReady() then page = math.max(0, page - delta); Refresh() end
    end)

    for slot = 1, perPage do
        local name = "NativeReagentsItem" .. slot
        local button = _G[name] or CreateFrame("Button", name, candidate, "ItemButtonTemplate")
        local column, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
        button:ClearAllPoints()
        button:SetSize(slotWidth, slotHeight)
        button:SetPoint("TOPLEFT", candidate, "TOPLEFT", 10 + column * columnPitch, -16 - row * rowPitch)
        button:SetFrameLevel(candidate:GetFrameLevel() + 2)
        local normal = button:GetNormalTexture()
        if normal then
            normal:ClearAllPoints()
            normal:SetPoint("CENTER", button, "CENTER", 0, -1)
            normal:SetSize(64, 64)
            normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        end
        button:SetID(slot)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if not button.border then
            button.border = button:CreateTexture(nil, "OVERLAY")
            button.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            button.border:SetBlendMode("ADD")
            button.border:SetSize(62, 62)
            button.border:SetPoint("CENTER")
        end
        button:SetScript("OnEnter", function(self)
            if not self.itemId then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemId)
            GameTooltip:AddLine("Right-click to withdraw a stack", 0.5, 0.8, 1)
            GameTooltip:AddLine("Shift-click to choose an amount", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:SetScript("OnClick", function(self, mouseButton)
            if not self.itemId then return end
            if IsShiftKeyDown() then
                local popup = StaticPopup_Show("NATIVE_REAGENTS_WITHDRAW")
                if popup then
                    popup.data = self.itemId
                    popup.editBox:SetText(math.min(self.quantity, 20))
                    popup.editBox:HighlightText()
                end
            elseif mouseButton == "RightButton" then
                local _, _, _, _, _, _, _, stack = GetItemInfo(self.itemId)
                NR.Withdraw(self.itemId, math.min(self.quantity, stack or 1))
            end
        end)
        createdButtons[slot] = button
    end

    candidate.bankTab, candidate.reagentTab = bankTab, reagentTab
    candidate.deposit, candidate.auto = deposit, auto
    candidate.previous, candidate.next = previous, nextButton
    view, buttons = candidate, createdButtons

    NR.RegisterCallback(function(event)
        if event == "ITEMS_UPDATED" or event == "STATUS_CHANGED" or event == "SYNC_FAILED" or event == "AVAILABLE" then
            Refresh()
        elseif event == "AUTO_DEPOSIT_CHANGED" and view then
            view.auto:SetChecked(NR.GetAutoDeposit()); view.auto:Enable()
        elseif event == "ERROR" and view then
            view.auto:SetChecked(NR.GetAutoDeposit()); view.auto:Enable(); Refresh()
        elseif event == "PRESENTATION_CHANGED" and NR.GetPresentation() then
            ShowBank()
        end
    end, view)
    view:Hide()
    bankTab:Hide()
    reagentTab:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:SetScript("OnEvent", function(_, event)
    Build()
    if event == "BANKFRAME_OPENED" then
        ShowBank()
        if view then
            view.auto:SetChecked(NR.GetAutoDeposit())
            view.bankTab:Show()
            view.reagentTab:Show()
        end
    elseif event == "BANKFRAME_CLOSED" then
        ShowBank()
        if view then view.bankTab:Hide(); view.reagentTab:Hide() end
    else
        RefreshStockVisibility()
    end
end)
