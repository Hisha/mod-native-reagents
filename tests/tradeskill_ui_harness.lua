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

TRADE_SKILLS_DISPLAYED, TRADE_SKILL_TEXT_WIDTH = 5, 275
TradeSkillListScrollFrame = Widget(); TradeSkillListScrollFrame.offset = 0
function FauxScrollFrame_GetOffset(frame) return frame.offset end
TradeSkillFrame = Widget(false); TradeSkillFrame.selectedSkill = 4
TradeSkillCreateButton = Widget()
TradeSkillCreateAllButton = Widget()
TradeSkillInputBox = Widget()
TradeSkillFrameDummyString = Widget()
DEFAULT_CHAT_FRAME = { AddMessage=function() end }

local definitions = {
    metal = { name="Metal", kind="header", stock=0, reagents={} },
    inventory = { name="Inventory Recipe", kind="optimal", stock=5,
        reagents={{ id=100, required=2, carried=10 }} },
    bank = { name="Bank Recipe", kind="optimal", stock=0,
        reagents={{ id=101, required=2, carried=0 }} },
    runed = { name="Runed Copper Pants", kind="optimal", stock=0,
        reagents={
            { id=200, required=8, carried=17 },
            { id=201, required=2, carried=8 },
            { id=202, required=3, carried=2 },
        } },
    insufficient = { name="Insufficient Recipe", kind="medium", stock=0,
        reagents={{ id=105, required=4, carried=1 }} },
    duplicate = { name="Duplicate Reagent Recipe", kind="easy", stock=1,
        reagents={{ id=104, required=2, carried=3 }, { id=104, required=4, carried=3 }} },
    cloth = { name="Cloth", kind="header", stock=0, reagents={} },
    scrolla = { name="Scrolled Recipe A", kind="optimal", stock=0,
        reagents={{ id=106, required=5, carried=0 }} },
    scrollb = { name="Scrolled Recipe B", kind="optimal", stock=1,
        reagents={{ id=107, required=2, carried=2 }} },
    special = { name="Cooldown Recipe", kind="optimal", stock=-1, reagents={} },
}
local metalCollapsed, clothCollapsed = false, false
local function VisibleRecipes()
    local result = { definitions.metal }
    if not metalCollapsed then
        for _, key in ipairs({ "inventory", "bank", "runed", "insufficient", "duplicate" }) do
            table.insert(result, definitions[key])
        end
    end
    table.insert(result, definitions.cloth)
    if not clothCollapsed then
        for _, key in ipairs({ "scrolla", "scrollb", "special" }) do table.insert(result, definitions[key]) end
    end
    return result
end
local function Recipe(index) return VisibleRecipes()[index] end

function GetTradeSkillInfo(index)
    local recipe = Recipe(index)
    if not recipe then return nil end
    return recipe.name, recipe.kind, recipe.stock
end
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

for row = 1, TRADE_SKILLS_DISPLAYED do
    _G["TradeSkillSkill" .. row] = Widget()
    _G["TradeSkillSkill" .. row .. "Text"] = Widget()
    _G["TradeSkillSkill" .. row .. "Count"] = Widget()
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

print("PASS original ApplyList port, exact item IDs, lifecycle, scrolling, collapse, and synchronization")
