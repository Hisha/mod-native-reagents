local NR = NativeReagents
local view, buttons, page = nil, {}, 0
local columns, rows, perPage = 7, 5, 35
-- Stock BankFrame item buttons are 37x37, with 12 horizontal and 7 vertical
-- gaps.  Keeping the native pitch is important because ItemButtonTemplate's
-- 64x64 UI-Quickslot2 normal texture extends outside the button itself.
local slotWidth, slotHeight, columnPitch, rowPitch = 37, 37, 49, 44
-- Build 12340 BankFrame.xml declares a 425x512 frame and a 512x512
-- UI-BankFrame texture.  The texture's non-transparent alpha bounds end at
-- row 423, so its visible bottom is 88 UI units above the logical frame bottom.
-- HitRectInsets bottom=70 is interaction geometry, not the artwork boundary.
local artworkBottomInset = 88
local stockObjects, stockLabels, stockState = {}, {}, nil
local reagentsSelected = false
local visibilityHookInstalled = false

local quality = {
    [0] = {0.62, 0.62, 0.62}, [1] = {1, 1, 1}, [2] = {0.12, 1, 0},
    [3] = {0, 0.44, 0.87}, [4] = {0.64, 0.21, 0.93}, [5] = {1, 0.5, 0}
}

local function FindStockObjects()
    local function Add(frame) if frame then table.insert(stockObjects, frame) end end
    for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do Add(_G["BankFrameItem" .. i]) end
    for i = 1, (NUM_BANKBAGSLOTS or 7) do Add(_G["BankFrameBag" .. i]) end
    -- PurchaseButton and DetailMoneyFrame are descendants of PurchaseInfo.
    -- Hiding PurchaseInfo hides both; recording the descendants makes the
    -- diagnostic inventory complete and restoration resilient to a direct Hide.
    Add(BankFramePurchaseInfo)
    Add(BankFramePurchaseButton)
    Add(BankFrameDetailMoneyFrame)
    Add(BankFrameMoneyFrame)

    -- These two stock labels are anonymous BankFrame FontStrings.  Match their
    -- localized text instead of hiding every anonymous FontString on BankFrame.
    local regions = {BankFrame:GetRegions()}
    for _, region in ipairs(regions) do
        local text = region:GetObjectType() == "FontString" and region:GetText()
        if text == ITEMSLOTTEXT or text == BAGSLOTTEXT then
            table.insert(stockLabels, region)
        end
    end
end

local function EnforceStockHidden()
    if not reagentsSelected then return end
    for _, frame in ipairs(stockObjects) do frame:Hide() end
    for _, region in ipairs(stockLabels) do region:Hide() end
end

local function HideStock()
    if not stockState then
        stockState = {}
        for _, frame in ipairs(stockObjects) do stockState[frame] = frame:IsShown() and true or false end
        for _, region in ipairs(stockLabels) do stockState[region] = region:IsShown() and true or false end
    end
    EnforceStockHidden()
end

local function InstallStockVisibilityGuard()
    if visibilityHookInstalled then return end
    visibilityHookInstalled = true
    -- In stock 3.3.5a, item/bag refreshes update textures but never Show the
    -- buttons.  UpdateBagSlotStatus is the one stock update that explicitly
    -- Shows BankFramePurchaseInfo, so it is the only function that needs a
    -- post-update guard while Reagents is selected.
    if UpdateBagSlotStatus then hooksecurefunc("UpdateBagSlotStatus", EnforceStockHidden) end
end

local function RestoreStock()
    reagentsSelected = false
    if not stockState then return end
    for frame, shown in pairs(stockState) do
        if shown then frame:Show() else frame:Hide() end
    end
    stockState = nil
    -- Let Blizzard recompute textures, locks, cooldowns, money, and purchase
    -- availability after the saved visibility state has been restored.
    if BankFrameItemButton_Update then
        for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do BankFrameItemButton_Update(_G["BankFrameItem" .. i]) end
        for i = 1, (NUM_BANKBAGSLOTS or 7) do BankFrameItemButton_Update(_G["BankFrameBag" .. i]) end
    end
    if UpdateBagSlotStatus then UpdateBagSlotStatus() end
end

local function HideStockForPage()
    reagentsSelected = true
    HideStock()
end

local function ObjectName(object)
    local name = object and object.GetName and object:GetName()
    return name or "<anonymous>"
end

local function DiagnosticLine(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7NR frame:|r " .. message) end
end

local function DescribeObject(label, object)
    if not object then DiagnosticLine(label .. " = <missing>"); return end
    local parent = object.GetParent and object:GetParent()
    local parts = {
        label .. "=" .. ObjectName(object),
        "type=" .. tostring(object:GetObjectType()),
        "shown=" .. tostring(object:IsShown()),
        "parent=" .. ObjectName(parent)
    }
    if object.GetFrameStrata then table.insert(parts, "strata=" .. tostring(object:GetFrameStrata())) end
    if object.GetFrameLevel then table.insert(parts, "level=" .. tostring(object:GetFrameLevel())) end
    if object.GetEffectiveScale then table.insert(parts, "scale=" .. tostring(object:GetEffectiveScale())) end
    if object.GetNumPoints and object.GetPoint then
        for i = 1, object:GetNumPoints() do
            local point, relative, relativePoint, x, y = object:GetPoint(i)
            table.insert(parts, "point" .. i .. "=" .. tostring(point) .. ":" .. ObjectName(relative) .. ":" .. tostring(relativePoint) .. ":" .. tostring(x) .. ":" .. tostring(y))
        end
    end
    DiagnosticLine(table.concat(parts, " "))
end

-- Development-only and silent until explicitly called from /run.
function NR.SetBankFrameDiagnostics(enabled) NR.bankFrameDiagnostics = enabled and true or false end
function NR.DumpBankFrame()
    if not BankFrame then DiagnosticLine("BankFrame is not loaded"); return end
    DescribeObject("frame", BankFrame)
    DiagnosticLine("bounds top=" .. tostring(BankFrame:GetTop()) .. " bottom=" .. tostring(BankFrame:GetBottom()) .. " width=" .. tostring(BankFrame:GetWidth()) .. " height=" .. tostring(BankFrame:GetHeight()) .. " artworkBottomInset=" .. artworkBottomInset)
    local regions = {BankFrame:GetRegions()}
    for i, region in ipairs(regions) do DescribeObject("region[" .. i .. "]", region) end
    for i, object in ipairs(stockObjects) do DescribeObject("stock[" .. i .. "]", object) end
    DescribeObject("reagentPage", view)
    if view then
        DescribeObject("contentMask", view.contentMask)
        DescribeObject("controls", view.controls)
        DescribeObject("bankTab", view.bankTab)
        DescribeObject("reagentTab", view.reagentTab)
    end
end

local function AssertDiagnosticState()
    if not NR.bankFrameDiagnostics or not view then return end
    local failures = {}
    if reagentsSelected then
        for _, object in ipairs(stockObjects) do if object:IsShown() then table.insert(failures, ObjectName(object) .. " is shown") end end
        for _, region in ipairs(stockLabels) do if region:IsShown() then table.insert(failures, "stock label is shown") end end
        if not view:IsShown() then table.insert(failures, "reagent page is hidden") end
    end
    for _, shared in ipairs({BankPortraitTexture, BankFrameTitleText, BankCloseButton}) do
        if shared and not shared:IsShown() then table.insert(failures, ObjectName(shared) .. " is hidden") end
    end
    if reagentsSelected and view:GetBottom() and view.tabAnchor:GetBottom() then
        if view:GetBottom() <= view.tabAnchor:GetBottom() then table.insert(failures, "reagent page crosses the visible bottom border") end
        if math.abs((view.bankTab:GetTop() or 0) - view.tabAnchor:GetBottom()) > 1 then table.insert(failures, "Bank tab is detached from the border anchor") end
        if view.controls:GetBottom() < view:GetBottom() then table.insert(failures, "controls extend below the reagent page") end
        if view.deposit:GetBottom() < view.controls:GetBottom() or view.deposit:GetTop() > view.controls:GetTop() then table.insert(failures, "deposit button exceeds controls bounds") end
        if view.auto:GetBottom() < view.controls:GetBottom() or view.auto:GetTop() > view.controls:GetTop() then table.insert(failures, "auto-deposit exceeds controls bounds") end
        if view.previous:GetBottom() <= view.controls:GetTop() or view.next:GetBottom() <= view.controls:GetTop() then table.insert(failures, "pagination overlaps deposit controls") end
        if buttons[perPage]:GetBottom() <= view.previous:GetTop() then table.insert(failures, "reagent grid overlaps pagination") end
    end
    if #failures == 0 then DiagnosticLine("runtime visibility assertions passed")
    else for _, failure in ipairs(failures) do DiagnosticLine("ASSERT " .. failure) end end
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
    AssertDiagnosticState()
end

local function ShowBank()
    if not view then return end
    view:Hide()
    RestoreStock()
    SetTab(1)
    AssertDiagnosticState()
end

local function Build()
    if view or not BankFrame then return end

    FindStockObjects()
    InstallStockVisibilityGuard()

    -- Publish the frame and button arrays only after every item button exists. If a
    -- previous interrupted load left named frames behind, reuse them exactly once.
    local candidate = _G.NativeReagentsBankFrame or CreateFrame("Frame", "NativeReagentsBankFrame", BankFrame)
    local createdButtons = {}
    candidate:ClearAllPoints()
    -- Keep the overlay inside the stock border: top=68 clears the portrait and
    -- title, and its bottom leaves four UI units above the measured artwork edge.
    candidate:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 22, -68)
    candidate:SetPoint("BOTTOMRIGHT", BankFrame, "BOTTOMRIGHT", -43, artworkBottomInset + 4)
    candidate:SetFrameLevel(BankFrame:GetFrameLevel() + 8)
    candidate:EnableMouseWheel(true)

    -- UI-BankFrame is one monolithic stock texture: its slot outlines, bag bars,
    -- outer border, and title surround cannot be hidden independently.  This
    -- opaque content mask covers only the inventory interior while leaving the
    -- shared portrait/title/close button and outer border exposed.  A solid
    -- texture avoids the post-Wrath Bank-Background asset used by the old code.
    local contentMask = candidate.contentMask or candidate:CreateTexture(nil, "BACKGROUND")
    candidate.contentMask = contentMask
    contentMask:ClearAllPoints()
    contentMask:SetPoint("TOPLEFT", candidate, "TOPLEFT", 0, 0)
    contentMask:SetPoint("BOTTOMRIGHT", candidate, "BOTTOMRIGHT", 0, 0)
    contentMask:SetTexture(0.035, 0.03, 0.025, 1)

    local tabAnchor = _G.NativeReagentsTabAnchor or CreateFrame("Frame", "NativeReagentsTabAnchor", BankFrame)
    tabAnchor:ClearAllPoints()
    tabAnchor:SetPoint("BOTTOMLEFT", BankFrame, "BOTTOMLEFT", 30, artworkBottomInset)
    tabAnchor:SetSize(1, 1)
    local bankTab = _G.NativeReagentsBankTab or CreateFrame("Button", "NativeReagentsBankTab", BankFrame, "CharacterFrameTabButtonTemplate")
    bankTab:ClearAllPoints()
    bankTab:SetPoint("TOPLEFT", tabAnchor, "BOTTOMLEFT", 0, 0)
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
    controls:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 8)
    controls:SetSize(360, 44)
    controls:SetFrameLevel(candidate:GetFrameLevel() + 1)
    local divider = controls.divider or controls:CreateTexture(nil, "ARTWORK")
    controls.divider = divider
    divider:ClearAllPoints()
    divider:SetPoint("TOP", controls, "TOP", 0, 0)
    divider:SetSize(346, 1)
    divider:SetTexture(0.45, 0.36, 0.16, 1)

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
    previous:SetPoint("BOTTOMLEFT", candidate, "BOTTOMLEFT", 20, 64)
    previous:SetText("Previous")
    previous:SetScript("OnClick", function() page = math.max(0, page - 1); Refresh() end)

    local nextButton = _G.NativeReagentsNext or CreateFrame("Button", "NativeReagentsNext", candidate, "UIPanelButtonTemplate")
    nextButton:SetSize(90, 22)
    nextButton:ClearAllPoints()
    nextButton:SetPoint("BOTTOMRIGHT", candidate, "BOTTOMRIGHT", -20, 64)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function() page = page + 1; Refresh() end)

    local pageText = candidate.pageText or candidate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    candidate.pageText = pageText
    pageText:ClearAllPoints()
    pageText:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 69)

    local statusText = candidate.statusText or candidate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candidate.statusText = statusText
    statusText:ClearAllPoints()
    statusText:SetPoint("BOTTOM", candidate, "BOTTOM", 0, 96)

    candidate:SetScript("OnMouseWheel", function(_, delta)
        if NR.IsReady() then page = math.max(0, page - delta); Refresh() end
    end)

    for slot = 1, perPage do
        local name = "NativeReagentsItem" .. slot
        local button = _G[name] or CreateFrame("Button", name, candidate, "ItemButtonTemplate")
        local column, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
        button:ClearAllPoints()
        button:SetSize(slotWidth, slotHeight)
        button:SetPoint("TOPLEFT", candidate, "TOPLEFT", 10 + column * columnPitch, -12 - row * rowPitch)
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

    candidate.tabAnchor, candidate.bankTab, candidate.reagentTab = tabAnchor, bankTab, reagentTab
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
    end
end)
