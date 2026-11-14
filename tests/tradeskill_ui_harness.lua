local sent, frames, hooks = {}, {}, {}
local Event
local unpackValues = table.unpack or unpack

local function Widget(shown)
    local widget = { shown=shown ~= false, enabled=true, text="", width=20, scripts={}, hooks={}, events={} }
    function widget:IsShown() return self.shown end
    function widget:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function widget:Hide() self.shown = false end
    function widget:Enable() self.enabled = true end
    function widget:Disable() self.enabled = false end
    function widget:SetText(value) self.text = tostring(value or ""); self.width = #self.text * 6 end
    function widget:GetText() return self.text end
    function widget:GetWidth() return self.width end
    function widget:SetWidth(value) self.setWidth = value; self.width = value end
    function widget:SetID(value) self.id = value end
    function widget:GetID() return self.id end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked and true or false end
    function widget:SetNumber(value) self.number = value end
    function widget:GetNumber() return self.number or 1 end
    function widget:ClearFocus() self.focusCleared = true end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, callback)
        self.hooks[name] = self.hooks[name] or {}
        table.insert(self.hooks[name], callback)
    end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:SetNormalFontObject(value) self.font = value end
    function widget:SetVertexColor(...) self.vertexColor = {...} end
    function widget:SetNormalTexture(value) self.normalTexture = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:SetPoint(...) self.point = {...} end
    function widget:LockHighlight() self.highlightLocked = true end
    function widget:UnlockHighlight() self.highlightLocked = false end
    return widget
end

function CreateFrame()
    local frame = Widget()
    table.insert(frames, frame)
    return frame
end
function hooksecurefunc(name, callback)
    local original = _G[name]
    hooks[name] = callback
    _G[name] = function(...)
        local results = { original(...) }
        callback(...)
        return unpackValues(results)
    end
end
function SendAddonMessage(prefix, payload, channel, target)
    table.insert(sent, { prefix=prefix, payload=payload, channel=channel, target=target })
end
function UnitName() return "Tester" end
function GetTime() return 100 end
function IsTradeSkillLinked() return false end
function DoTradeSkill(index, count) _G.lastStockCraft = { index, count } end

TRADE_SKILLS_DISPLAYED, TRADE_SKILL_TEXT_WIDTH, TRADE_SKILL_HEIGHT = 5, 275, 16
MAX_TRADE_SKILL_REAGENTS = 8
ENABLE_COLORBLIND_MODE = "0"
TradeSkillTypePrefix = { optimal=" [+++] ", medium=" [++] ", easy=" [+] ", trivial=" ", header=" " }
TradeSkillTypeColor = {
    optimal={r=1,g=.5,b=.25,font="orange"}, medium={r=1,g=1,b=0,font="yellow"},
    easy={r=.25,g=.75,b=.25,font="green"}, trivial={r=.5,g=.5,b=.5,font="gray"},
    header={r=1,g=.82,b=0,font="normal"},
}
HIGHLIGHT_FONT_COLOR = { r=1, g=1, b=1 }
TradeSkillListScrollFrame = Widget(); TradeSkillListScrollFrame.offset = 0
function FauxScrollFrame_GetOffset(frame) return frame.offset end
function FauxScrollFrame_SetOffset(frame, offset) frame.offset = offset end
function FauxScrollFrame_Update(frame, count) frame.filteredCount = count end
TradeSkillFrame = Widget(false); TradeSkillFrame.selectedSkill = 4
TradeSkillCreateButton = Widget()
TradeSkillCreateAllButton = Widget()
TradeSkillInputBox = Widget()
TradeSkillFrameDummyString = Widget()
TradeSkillFrameAvailableFilterCheckButton = Widget(); TradeSkillFrameAvailableFilterCheckButton:SetChecked(false)
TradeSkillHighlightFrame = Widget(false)
TradeSkillSkillName = Widget()
TradeSkillSkillCooldown = Widget()
TradeSkillSkillIcon = Widget()
TradeSkillDescription = Widget()
DEFAULT_CHAT_FRAME = { AddMessage=function() end }

local definitions = {
    metal = { name="Metal", kind="header", stock=0, reagents={} },
    inventory = { name="Inventory Recipe", kind="optimal", stock=5, subclass=1, slot=1,
        reagents={{ id=100, required=2, carried=10 }} },
    bank = { name="Bank Recipe", kind="optimal", stock=0, subclass=1, slot=2,
        reagents={{ id=101, required=2, carried=0 }} },
    runed = { name="Runed Copper Pants", kind="optimal", stock=0, subclass=2, slot=2,
        reagents={
            { id=200, required=8, carried=17 },
            { id=201, required=2, carried=8 },
            { id=202, required=3, carried=2 },
        } },
    insufficient = { name="Insufficient Recipe", kind="medium", stock=0, subclass=2, slot=1,
        reagents={{ id=105, required=4, carried=1 }} },
    duplicate = { name="Duplicate Reagent Recipe", kind="easy", stock=1, subclass=1, slot=1,
        reagents={{ id=104, required=2, carried=3 }, { id=104, required=4, carried=3 }} },
    cloth = { name="Cloth", kind="header", stock=0, reagents={} },
    scrolla = { name="Scrolled Recipe A", kind="optimal", stock=0, subclass=2, slot=1,
        reagents={{ id=106, required=5, carried=0 }} },
    scrollb = { name="Scrolled Recipe B", kind="optimal", stock=1, subclass=1, slot=2,
        reagents={{ id=107, required=2, carried=2 }} },
    special = { name="Cooldown Recipe", kind="optimal", stock=-1, reagents={} },
}
local metalCollapsed, clothCollapsed = false, false
local searchText, subclassFilter, slotFilter = "", 0, 0
local function Matches(recipe)
    return (searchText == "" or string.find(string.lower(recipe.name), string.lower(searchText), 1, true)) and
        (subclassFilter == 0 or recipe.subclass == subclassFilter) and
        (slotFilter == 0 or recipe.slot == slotFilter)
end
local function VisibleRecipes()
    local result = { definitions.metal }
    if not metalCollapsed then
        for _, key in ipairs({ "inventory", "bank", "runed", "insufficient", "duplicate" }) do
            if Matches(definitions[key]) then table.insert(result, definitions[key]) end
        end
    end
    table.insert(result, definitions.cloth)
    if not clothCollapsed then
        for _, key in ipairs({ "scrolla", "scrollb", "special" }) do
            if Matches(definitions[key]) then table.insert(result, definitions[key]) end
        end
    end
    return result
end
local function Recipe(index) return VisibleRecipes()[index] end
local tradeSkillInfoCalls = 0

function GetTradeSkillInfo(index)
    tradeSkillInfoCalls = tradeSkillInfoCalls + 1
    local recipe = Recipe(index)
    if not recipe then return nil end
    local expanded = recipe == definitions.metal and not metalCollapsed or
        recipe == definitions.cloth and not clothCollapsed
    return recipe.name, recipe.kind, recipe.stock, expanded
end
function GetNumTradeSkills() return #VisibleRecipes() end
function GetTradeSkillNumReagents(index) return Recipe(index) and #Recipe(index).reagents or 0 end
function GetTradeSkillReagentInfo(index, reagent)
    local row = Recipe(index).reagents[reagent]
    return "Reagent" .. row.id, "Texture" .. row.id, row.required, row.carried
end
function GetTradeSkillReagentItemLink(index, reagent)
    return "|Hitem:" .. Recipe(index).reagents[reagent].id .. ":0:0:0|h[item]|h"
end
function GetTradeSkillRecipeLink(index) return "|Henchant:" .. (1000 + index) .. "|h[recipe]|h" end
function GetTradeSkillSelectionIndex() return TradeSkillFrame.selectedSkill end

local nativeMakeableCalls = {}
function TradeSkillOnlyShowMakeable(enabled) table.insert(nativeMakeableCalls, enabled and true or false) end
function SetTradeSkillItemNameFilter(value) searchText = value or "" end
function SetTradeSkillItemLevelFilter() end
function SetTradeSkillSubClassFilter(value) subclassFilter = value or 0 end
function SetTradeSkillInvSlotFilter(value) slotFilter = value or 0 end
function ExpandTradeSkillSubClass(index)
    local row = Recipe(index)
    if index == 0 or row == definitions.metal then metalCollapsed = false end
    if index == 0 or row == definitions.cloth then clothCollapsed = false end
end
function CollapseTradeSkillSubClass(index)
    local row = Recipe(index)
    if index == 0 or row == definitions.metal then metalCollapsed = true end
    if index == 0 or row == definitions.cloth then clothCollapsed = true end
end

for row = 1, TRADE_SKILLS_DISPLAYED do
    _G["TradeSkillSkill" .. row] = Widget()
    _G["TradeSkillSkill" .. row .. "Text"] = Widget()
    _G["TradeSkillSkill" .. row .. "Count"] = Widget()
    _G["TradeSkillSkill" .. row .. "Highlight"] = Widget()
end
for reagent = 1, 8 do
    _G["TradeSkillReagent" .. reagent] = Widget()
    _G["TradeSkillReagent" .. reagent .. "Name"] = Widget()
    _G["TradeSkillReagent" .. reagent .. "Count"] = Widget()
end

local stockUpdateCalls = 0
function TradeSkillFrame_SetSelection(index)
    local recipe = Recipe(index)
    if not recipe or recipe.kind == "header" then return end
    TradeSkillFrame.selectedSkill = index
end
function TradeSkillFrame_Update()
    stockUpdateCalls = stockUpdateCalls + 1
    assert(stockUpdateCalls < 200, "Blizzard trade-skill update lifecycle did not terminate")
    local offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame)
    for row = 1, TRADE_SKILLS_DISPLAYED do
        local recipe = Recipe(offset + row)
        local text = _G["TradeSkillSkill" .. row .. "Text"]
        local count = _G["TradeSkillSkill" .. row .. "Count"]
        if recipe then
            _G["TradeSkillSkill" .. row]:SetID(offset + row)
            _G["TradeSkillSkill" .. row]:Show()
            text:SetText(recipe.name)
            count:SetText(recipe.kind ~= "header" and recipe.stock > 0 and ("[" .. recipe.stock .. "]") or "")
        else
            _G["TradeSkillSkill" .. row]:Hide(); text:SetText(""); count:SetText("")
        end
    end
    local selected = Recipe(TradeSkillFrame.selectedSkill)
    if selected and selected.kind ~= "header" then
        local stockCreatable = true
        for reagent, row in ipairs(selected.reagents) do
            _G["TradeSkillReagent" .. reagent .. "Count"]:SetText(row.carried .. " /" .. row.required)
            _G["TradeSkillReagent" .. reagent].stockDimmed = row.carried < row.required
            if row.carried < row.required then stockCreatable = false end
        end
        if stockCreatable and selected.stock > 0 then
            TradeSkillCreateButton:Enable(); TradeSkillCreateAllButton:Enable()
        else
            TradeSkillCreateButton:Disable(); TradeSkillCreateAllButton:Disable()
        end
        TradeSkillFrame.numAvailable = math.max(0, selected.stock)
    end
end

function TradeSkillFrame_Show()
    TradeSkillFrame:Show()
    TradeSkillOnlyShowMakeable(TradeSkillFrameAvailableFilterCheckButton:GetChecked())
    TradeSkillFrame_Update()
end

assert(loadfile("content/client/Interface/FrameXML/NativeReagents.lua"))()

local lifecycle
for _, frame in ipairs(frames) do if frame.events.CHAT_MSG_ADDON then lifecycle = frame end end
assert(lifecycle, "Native Reagents event frame was not created")

local function RunUpdates(elapsed)
    local callbacks = {}
    for _, frame in ipairs(frames) do
        if frame.scripts.OnUpdate then table.insert(callbacks, { frame, frame.scripts.OnUpdate }) end
    end
    for _, entry in ipairs(callbacks) do entry[2](entry[1], elapsed or 0.11) end
end
Event = function(event, ...)
    if event == "TRADE_SKILL_UPDATE" and TradeSkillFrame:IsShown() then
        TradeSkillFrame_SetSelection(GetTradeSkillSelectionIndex())
        TradeSkillFrame_Update()
    end
    lifecycle.scripts.OnEvent(lifecycle, event, ...)
end
local function LastRequest(command)
    for index = #sent, 1, -1 do
        local version, request, found, arguments = string.match(sent[index].payload, "^(%d+)|(%d+)|([^|]+)|?(.*)$")
        if found == command then return tonumber(version), tonumber(request), arguments end
    end
    error("missing request " .. command)
end
local function Reply(request, kind, body)
    Event("CHAT_MSG_ADDON", "NRB", "2|" .. request .. "|" .. kind .. (body and "|" .. body or ""), "WHISPER", "Tester")
end
local function CompleteLatestSync(rows)
    local _, request, arguments = LastRequest("SYNC")
    local syncId = tonumber(string.match(arguments, "^(%d+)|0$"))
    assert(syncId, "initial sync page request missing")
    Reply(request, "DATA", syncId .. "|0|1|" .. rows)
    RunUpdates()
end
local function RequestCount(command)
    local count = 0
    for _, message in ipairs(sent) do
        if string.match(message.payload, "^%d+|%d+|([^|]+)") == command then count = count + 1 end
    end
    return count
end

Event("PLAYER_LOGIN")
local _, helloRequest = LastRequest("HELLO")
Reply(helloRequest, "HELLO", "1|1")
CompleteLatestSync("101:10,104:5,106:10,200:100,201:10,202:5")
TradeSkillFrame:Show()
CompleteLatestSync("101:10,104:5,106:10,200:100,201:10,202:5")
TradeSkillFrame_Update()

assert(TradeSkillSkill2Count.text == "[5]", "inventory-only list count is wrong")
assert(TradeSkillSkill3Count.text == "[5]", "bank-only list count is wrong")
assert(TradeSkillSkill4Count.text == "[2]", "Runed Copper Pants must display [2]")
assert(TradeSkillSkill4Text.text == "Runed Copper Pants", "recipe name was modified")
TradeSkillListScrollFrame.offset = 4
TradeSkillFrame_Update()
assert(TradeSkillSkill1Text.text == "Insufficient Recipe" and TradeSkillSkill1Count.text == "",
    "insufficient recipe display is wrong after scrolling")
assert(TradeSkillSkill2Text.text == "Duplicate Reagent Recipe" and TradeSkillSkill2Count.text == "[2]",
    "duplicate reagent requirements are wrong")
assert(TradeSkillSkill4Text.text == "Scrolled Recipe A" and TradeSkillSkill4Count.text == "[2]",
    "scrolled row was not associated with its trade-skill index")

metalCollapsed = true
TradeSkillListScrollFrame.offset = 0
TradeSkillFrame.selectedSkill = 3
TradeSkillFrame_Update()
assert(TradeSkillSkill1Text.text == "Metal" and TradeSkillSkill1Count.text == "", "collapsed header count changed")
assert(TradeSkillSkill2Text.text == "Cloth" and TradeSkillSkill2Count.text == "", "collapsed list indexing is wrong")
assert(TradeSkillSkill3Text.text == "Scrolled Recipe A" and TradeSkillSkill3Count.text == "[2]",
    "expanded category recipe count is wrong")
assert(TradeSkillSkill5Text.text == "Cooldown Recipe" and TradeSkillSkill5Count.text == "",
    "cooldown/no-ordinary-reagent recipe handling changed")
metalCollapsed = false

TradeSkillFrame.selectedSkill = 4
TradeSkillListScrollFrame.offset = 0
TradeSkillFrame_SetSelection(4)
TradeSkillFrame_Update()
assert(TradeSkillFrame.numAvailable == 2, "selected mixed-material maximum is wrong")
assert(TradeSkillReagent1Count.text == "* /8" and TradeSkillReagent2Count.text == "18 /2" and
       TradeSkillReagent3Count.text == "7 /3", "selected combined reagent totals are wrong")
assert(TradeSkillReagent3.stockDimmed, "bank-only-assisted reagent must remain visually dimmed")
assert(TradeSkillCreateButton.enabled and TradeSkillCreateAllButton.enabled, "combined materials did not enable crafting")

TradeSkillCreateAllButton.scripts.OnClick()
local _, _, craftArguments = LastRequest("CRAFT")
assert(craftArguments == "1004|2", "Create All did not use the combined maximum")
TradeSkillFrame.selectedSkill = 2
TradeSkillFrame_SetSelection(2)
TradeSkillInputBox:SetNumber(1)
TradeSkillCreateButton.scripts.OnClick()
assert(lastStockCraft[1] == 2 and lastStockCraft[2] == 1, "inventory-only craft bypassed Blizzard")

TradeSkillFrame.selectedSkill = 3
TradeSkillFrame_SetSelection(3)
TradeSkillFrame_Update()
local beforeName = TradeSkillSkill3Text.text
NativeReagents.RequestSync()
CompleteLatestSync("101:2,104:5,106:10,200:100,201:10,202:5")
assert(TradeSkillSkill3Count.text == "[1]" and TradeSkillSkill3Text.text == beforeName,
    "bank synchronization did not refresh the dedicated count safely")

local syncRequests = RequestCount("SYNC")
local updates = stockUpdateCalls
for _ = 1, 20 do Event("TRADE_SKILL_UPDATE") end
RunUpdates()
assert(RequestCount("SYNC") == syncRequests, "profession updates started synchronization requests")
assert(stockUpdateCalls - updates == 20, "profession update recursion occurred")

TradeSkillFrame:Hide()
local closedCount = TradeSkillSkill3Count.text
RunUpdates(0.5)
assert(TradeSkillSkill3Count.text == closedCount, "closed profession window was rewritten")
TradeSkillFrame:Show()
assert(RequestCount("SYNC") == syncRequests + 1, "profession reopen did not request synchronization")
CompleteLatestSync("101:10,104:5,106:10,200:100,201:10,202:5")
TradeSkillFrame_Update()
assert(TradeSkillSkill3Count.text == "[5]", "profession reopen did not restore counts")

syncRequests = RequestCount("SYNC")
Event("BAG_UPDATE")
assert(RequestCount("SYNC") == syncRequests + 1, "BAG_UPDATE did not request synchronization")
CompleteLatestSync("101:10,104:5,106:10,200:100,201:10,202:5")

local function RowName(row)
    return string.gsub(_G["TradeSkillSkill" .. row .. "Text"].text or "", "^%s+", "")
end
local function AssertRows(expected, message)
    for row, name in ipairs(expected) do
        assert(RowName(row) == name, message .. " row " .. row .. ": " .. RowName(row))
    end
end
local function SetHaveMaterials(enabled)
    TradeSkillFrameAvailableFilterCheckButton:SetChecked(enabled)
    TradeSkillFrameAvailableFilterCheckButton.scripts.OnClick(TradeSkillFrameAvailableFilterCheckButton)
end
local function ResetNativeFilters()
    searchText, subclassFilter, slotFilter = "", 0, 0
    metalCollapsed, clothCollapsed = false, false
    TradeSkillListScrollFrame.offset = 0
end

-- Unchecked remains Blizzard's full list with the established bank-aware counts.
ResetNativeFilters()
SetHaveMaterials(false)
AssertRows({ "Metal", "Inventory Recipe", "Bank Recipe", "Runed Copper Pants", "Insufficient Recipe" },
    "unchecked Have Materials changed the native list")
assert(TradeSkillSkill2Count.text == "[5]" and TradeSkillSkill3Count.text == "[5]" and
    TradeSkillSkill4Count.text == "[2]", "unchecked recipe counts regressed")

-- The active mapping keeps inventory-only, bank-only, mixed, and duplicate-reagent recipes,
-- while omitting recipes whose authoritative RecipeMax is zero.
SetHaveMaterials(true)
AssertRows({ "Metal", "Inventory Recipe", "Bank Recipe", "Runed Copper Pants", "Duplicate Reagent Recipe" },
    "bank-aware Have Materials mapping is wrong")
assert(TradeSkillSkill2Count.text == "[5]", "inventory-only recipe was not retained")
assert(TradeSkillSkill3Count.text == "[5]", "bank-only recipe was not retained")
assert(TradeSkillSkill4Count.text == "[2]", "mixed Runed Copper Pants count is wrong")
assert(TradeSkillSkill5:GetID() == 6, "visible row did not retain the duplicate recipe's native index")
assert(TradeSkillListScrollFrame.filteredCount == 8, "filtered list size is wrong")
local stableInfoCalls = tradeSkillInfoCalls
for _ = 1, 5 do RunUpdates() end
assert(tradeSkillInfoCalls - stableInfoCalls == 45,
    "the complete filtered mapping was rebuilt by the 0.10-second count guard")

-- Scrolling must map every visible row back to its native recipe index.
TradeSkillListScrollFrame.offset = 3
TradeSkillFrame_Update()
AssertRows({ "Runed Copper Pants", "Duplicate Reagent Recipe", "Cloth", "Scrolled Recipe A", "Scrolled Recipe B" },
    "filtered scrolling is wrong")
assert(TradeSkillSkill1:GetID() == 4 and TradeSkillSkill5:GetID() == 9,
    "filtered scrolling passed visible positions instead of native indices")
TradeSkillFrame_SetSelection(TradeSkillSkill5:GetID())
TradeSkillInputBox:SetNumber(1)
TradeSkillCreateButton.scripts.OnClick()
assert(lastStockCraft[1] == 9, "crafting did not receive the filtered row's native recipe index")

-- Search is applied natively first; Have Materials then filters that native result.
TradeSkillListScrollFrame.offset = 0
SetTradeSkillItemNameFilter("Bank")
TradeSkillFrame.selectedSkill = 2
TradeSkillFrame_Update()
AssertRows({ "Metal", "Bank Recipe" }, "search plus Have Materials is wrong")
assert(not TradeSkillSkill3:IsShown() and TradeSkillSkill2:GetID() == 2,
    "search result mapping is not bounded to native results")

-- Subclass and inventory-slot filters remain native and compose with the custom filter.
SetTradeSkillItemNameFilter("")
SetTradeSkillSubClassFilter(1)
SetTradeSkillInvSlotFilter(2)
TradeSkillFrame.selectedSkill = 2
TradeSkillFrame_Update()
AssertRows({ "Metal", "Bank Recipe", "Cloth", "Scrolled Recipe B" },
    "subclass/slot filters plus Have Materials are wrong")
assert(TradeSkillSkill4:GetID() == 4, "filtered native index after subclass/slot filtering is wrong")

-- Collapsed categories stay collapsed. Their hidden children cannot be inspected by the
-- 3.3.5 API, so the header is retained without any automatic expansion.
ResetNativeFilters()
CollapseTradeSkillSubClass(1)
TradeSkillFrame.selectedSkill = 3
TradeSkillFrame_Update()
AssertRows({ "Metal", "Cloth", "Scrolled Recipe A", "Scrolled Recipe B" },
    "collapsed category handling is wrong")
assert(metalCollapsed, "filtering expanded a collapsed category")
ExpandTradeSkillSubClass(1)
TradeSkillFrame_Update()
assert(not metalCollapsed and RowName(2) == "Inventory Recipe", "expanded category was not rebuilt")

-- When the selected recipe loses its last craft, it disappears and selection moves to a
-- qualifying native recipe before any further craft can occur.
TradeSkillFrame_SetSelection(4)
definitions.runed.reagents[1].carried = 0
definitions.runed.reagents[2].carried = 0
definitions.runed.reagents[3].carried = 0
NativeReagents.RequestSync()
CompleteLatestSync("101:10,104:5,106:10")
assert(TradeSkillFrame.selectedSkill == 2, "disappearing selected recipe was not replaced safely")
assert(RowName(4) ~= "Runed Copper Pants", "zero-craft selected recipe remained visible")
TradeSkillInputBox:SetNumber(1)
TradeSkillCreateButton.scripts.OnClick()
assert(lastStockCraft[1] == 2, "stale selection crafted a different filtered-row position")

-- Inventory changes rebuild the mapping without waiting for a polling loop.
definitions.bank.reagents[1].carried = 0
NativeReagents.RequestSync()
CompleteLatestSync("104:5,106:10")
assert(RowName(3) ~= "Bank Recipe", "zero-quantity bank recipe remained visible")
definitions.bank.reagents[1].carried = 2
Event("BAG_UPDATE")
RunUpdates()
assert(RowName(3) == "Bank Recipe", "inventory update did not refresh the active filter")
CompleteLatestSync("104:5,106:10")

-- Bank synchronization independently removes and restores bank-only recipes.
definitions.bank.reagents[1].carried = 0
NativeReagents.RequestSync()
CompleteLatestSync("104:5,106:10")
assert(RowName(3) ~= "Bank Recipe", "empty bank synchronization did not remove recipe")
NativeReagents.RequestSync()
CompleteLatestSync("101:10,104:5,106:10")
assert(RowName(3) == "Bank Recipe", "bank synchronization did not restore bank-only recipe")

-- Restore the mixed recipe and verify its selected details/count after active filtering.
definitions.runed.reagents[1].carried = 17
definitions.runed.reagents[2].carried = 8
definitions.runed.reagents[3].carried = 2
NativeReagents.RequestSync()
CompleteLatestSync("101:10,104:5,106:10,200:100,201:10,202:5")
TradeSkillFrame_SetSelection(4)
TradeSkillFrame_Update()
assert(TradeSkillFrame.selectedSkill == 4 and TradeSkillFrame.numAvailable == 2,
    "selection after filtering did not retain the native recipe index")

-- Reopen repeatedly: Blizzard's stock show path may request true, but every native call
-- observed after installation must be coerced to false.
local callsBeforeReopen = #nativeMakeableCalls
for _ = 1, 3 do
    TradeSkillFrame:Hide()
    TradeSkillFrame_Show()
end
for index = callsBeforeReopen + 1, #nativeMakeableCalls do
    assert(nativeMakeableCalls[index] == false, "profession reopen re-enabled Blizzard's native filter")
end
assert(stockUpdateCalls < 200, "repeated profession opens caused recursive refreshes")

-- Turning the filter off restores the full native list and the original count renderer.
ResetNativeFilters()
SetHaveMaterials(false)
TradeSkillListScrollFrame.offset = 4
TradeSkillFrame_Update()
assert(RowName(1) == "Insufficient Recipe" and TradeSkillSkill1Count.text == "",
    "unchecked full list/count behavior was not restored")
assert(nativeMakeableCalls[#nativeMakeableCalls] == false, "native Have Materials filter was not left disabled")
for _, enabled in ipairs(nativeMakeableCalls) do
    assert(enabled == false, "an inventory-only native filter call was allowed through")
end

print("PASS original profession integration and bank-aware Have Materials filtering")
