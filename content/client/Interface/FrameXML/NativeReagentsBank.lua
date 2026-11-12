local NR = NativeReagents
local view, buttons, page, perPage = nil, {}, 0, 35
local stockState = nil

local quality = {
    [0] = {0.62,0.62,0.62}, [1] = {1,1,1}, [2] = {0.12,1,0},
    [3] = {0,0.44,0.87}, [4] = {0.64,0.21,0.93}, [5] = {1,0.5,0}
}

local function StockFrames()
    local frames = {}
    local function Add(frame) if frame then table.insert(frames, frame) end end
    for i = 1, NUM_BANKGENERIC_SLOTS or 28 do Add(_G["BankFrameItem"..i]) end
    for i = 1, NUM_BANKBAGSLOTS or 7 do Add(_G["BankFrameBag"..i]) end
    Add(BankFrameMoneyFrame); Add(BankFramePurchaseInfo); Add(BankFramePurchaseButton); Add(BankFrameDetailMoneyFrame)
    return frames
end

local function HideStock()
    if stockState then return end
    stockState = {}
    for _, frame in ipairs(StockFrames()) do
        if frame then stockState[frame] = frame:IsShown() and true or false; frame:Hide() end
    end
end

local function RestoreStock()
    if not stockState then return end
    for frame, shown in pairs(stockState) do if shown then frame:Show() else frame:Hide() end end
    stockState = nil
end

local function SortedItems()
    local result = {}
    for id, quantity in pairs(NR.GetItems()) do if quantity > 0 then table.insert(result, {id=id, quantity=quantity}) end end
    table.sort(result, function(a,b) local an = GetItemInfo(a.id) or ""; local bn = GetItemInfo(b.id) or ""; if an == bn then return a.id < b.id end return an < bn end)
    return result
end

local function Refresh()
    if not view or not view:IsShown() then return end
    local items = SortedItems(); local maximum = math.max(0, math.ceil(#items / perPage) - 1); page = math.min(page, maximum)
    local ready = NR.IsReady()
    local status = NR.GetStatus()
    if not ready then
        local labels = { loading="Loading reagent bank...", failed="Synchronization failed", unavailable="Reagent service unavailable" }
        view.statusText:SetText(labels[status] or "Waiting for reagent service...")
    elseif #items == 0 then view.statusText:SetText("No reagents stored") else view.statusText:SetText("") end
    view.pageText:SetText("Page " .. (page + 1) .. " of " .. (maximum + 1))
    if ready and page > 0 then view.previous:Enable() else view.previous:Disable() end
    if ready and page < maximum then view.next:Enable() else view.next:Disable() end
    if ready and NR.IsBankOpen() then view.deposit:Enable() else view.deposit:Disable() end
    if NR.IsAvailable() and NR.IsBankOpen() then view.auto:Enable() else view.auto:Disable() end
    for slot = 1, perPage do
        local button, row = buttons[slot], items[page * perPage + slot]
        if row and ready then
            button.itemId, button.quantity = row.id, row.quantity
            SetItemButtonTexture(button, GetItemIcon(row.id)); SetItemButtonCount(button, row.quantity)
            local _, _, itemQuality = GetItemInfo(row.id); local color = quality[itemQuality or 1] or quality[1]
            button.border:SetVertexColor(color[1], color[2], color[3], 0.85); button:Show()
        else button.itemId, button.quantity = nil, nil; button:Hide() end
    end
end

StaticPopupDialogs["NATIVE_REAGENTS_WITHDRAW"] = {
    text = "Withdraw how many?", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self) local amount = tonumber(self.editBox:GetText()); if amount and self.data then NR.Withdraw(self.data, math.floor(amount)) end end,
    EditBoxOnEnterPressed = function(self) local parent = self:GetParent(); local amount = tonumber(self:GetText()); if amount and parent.data then NR.Withdraw(parent.data, math.floor(amount)) end parent:Hide() end
}

local function ShowReagents()
    if NR.GetPresentation() and NR.GetPresentation() ~= view then return end
    HideStock(); view:Show(); page = 0; Refresh(); NR.RequestSync()
    view.personalTab:UnlockHighlight(); view.reagentTab:LockHighlight()
end
local function ShowPersonal()
    if not view then return end
    view:Hide(); RestoreStock(); view.reagentTab:UnlockHighlight(); view.personalTab:LockHighlight()
end

local function Build()
    if view or not BankFrame then return end
    view = CreateFrame("Frame", "NativeReagentsBankFrame", BankFrame)
    view:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 9, -57); view:SetSize(330, 355); view:SetFrameLevel(BankFrame:GetFrameLevel() + 8)
    local bg = view:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture("Interface\\BankFrame\\Bank-Background"); bg:SetTexCoord(0, 0.65, 0, 0.75)
    view.personalTab = CreateFrame("Button", nil, BankFrame, "UIPanelButtonTemplate"); view.personalTab:SetSize(105, 24); view.personalTab:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 45, -29); view.personalTab:SetText("Personal Bank"); view.personalTab:SetScript("OnClick", ShowPersonal)
    view.reagentTab = CreateFrame("Button", nil, BankFrame, "UIPanelButtonTemplate"); view.reagentTab:SetSize(92, 24); view.reagentTab:SetPoint("LEFT", view.personalTab, "RIGHT", 3, 0); view.reagentTab:SetText("Reagents"); view.reagentTab:SetScript("OnClick", ShowReagents)
    view.deposit = CreateFrame("Button", nil, view, "UIPanelButtonTemplate"); view.deposit:SetSize(132, 24); view.deposit:SetPoint("BOTTOMLEFT", 15, 18); view.deposit:SetText("Deposit Reagents"); view.deposit:SetScript("OnClick", NR.DepositAll)
    view.auto = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate"); view.auto:SetPoint("LEFT", view.deposit, "RIGHT", 8, 0); view.auto.text = view.auto:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); view.auto.text:SetPoint("LEFT", view.auto, "RIGHT", -3, 0); view.auto.text:SetText("Auto Deposit"); view.auto:SetScript("OnClick", function(self) local requested = self:GetChecked() and true or false; self:SetChecked(NR.GetAutoDeposit()); self:Disable(); if not NR.SetAutoDeposit(requested) then self:Enable() end end)
    view.previous = CreateFrame("Button", nil, view, "UIPanelButtonTemplate"); view.previous:SetSize(72,22); view.previous:SetPoint("BOTTOMLEFT", 35, 48); view.previous:SetText("Previous"); view.previous:SetScript("OnClick", function() page = math.max(0, page - 1); Refresh() end)
    view.next = CreateFrame("Button", nil, view, "UIPanelButtonTemplate"); view.next:SetSize(72,22); view.next:SetPoint("BOTTOMRIGHT", -35, 48); view.next:SetText("Next"); view.next:SetScript("OnClick", function() page = page + 1; Refresh() end)
    view.pageText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); view.pageText:SetPoint("BOTTOM", 0, 54)
    view.statusText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); view.statusText:SetPoint("BOTTOM", 0, 78)
    view:SetScript("OnMouseWheel", function(_, delta) if NR.IsReady() then page = math.max(0, page - delta); Refresh() end end); view:EnableMouseWheel(true)
    for slot = 1, perPage do
        local button = CreateFrame("Button", "NativeReagentsItem"..slot, view, "ItemButtonTemplate")
        local column, row = math.mod(slot - 1, 7), math.floor((slot - 1) / 7)
        button:SetPoint("TOPLEFT", 17 + column * 44, -16 - row * 44); button:SetID(slot)
        button.border = button:CreateTexture(nil, "OVERLAY"); button.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); button.border:SetBlendMode("ADD"); button.border:SetSize(62,62); button.border:SetPoint("CENTER")
        button:SetScript("OnEnter", function(self) if self.itemId then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:"..self.itemId); GameTooltip:Show() end end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:SetScript("OnClick", function(self)
            if not self.itemId then return end
            if IsShiftKeyDown() then local popup = StaticPopup_Show("NATIVE_REAGENTS_WITHDRAW"); if popup then popup.data = self.itemId; popup.editBox:SetText(math.min(self.quantity, 20)); popup.editBox:HighlightText() end
            else local _, _, _, _, _, _, _, stack = GetItemInfo(self.itemId); NR.Withdraw(self.itemId, math.min(self.quantity, stack or 1)) end
        end)
        buttons[slot] = button
    end
    NR.RegisterCallback(function(event)
        if event == "ITEMS_UPDATED" or event == "STATUS_CHANGED" or event == "SYNC_FAILED" or event == "AVAILABLE" then Refresh()
        elseif event == "AUTO_DEPOSIT_CHANGED" and view then view.auto:SetChecked(NR.GetAutoDeposit()); view.auto:Enable()
        elseif event == "ERROR" and view then view.auto:SetChecked(NR.GetAutoDeposit()); view.auto:Enable(); Refresh()
        elseif event == "PRESENTATION_CHANGED" and NR.GetPresentation() then ShowPersonal() end
    end, view)
    view:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN"); events:RegisterEvent("BANKFRAME_OPENED"); events:RegisterEvent("BANKFRAME_CLOSED")
events:SetScript("OnEvent", function(_, event)
    Build()
    if event == "BANKFRAME_OPENED" then ShowPersonal(); if view then view.auto:SetChecked(NR.GetAutoDeposit()); view.personalTab:Show(); view.reagentTab:Show() end
    elseif event == "BANKFRAME_CLOSED" then ShowPersonal(); if view then view.personalTab:Hide(); view.reagentTab:Hide() end end
end)
