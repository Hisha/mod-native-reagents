#include "NativeReagentsManager.h"

#include "AllCreatureScript.h"
#include "AllSpellScript.h"
#include "Chat.h"
#include "Creature.h"
#include "Item.h"
#include "Player.h"
#include "PlayerScript.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "Spell.h"
#include "SpellInfo.h"
#include "WorldSession.h"

namespace
{
constexpr uint32 Sender = GOSSIP_SENDER_MAIN;
constexpr uint32 OpenBank = 0x71000001;
constexpr uint32 Deposit = 0x71000002;
constexpr uint32 Toggle = 0x71000003;

bool IsBanker(Creature* creature)
{
    return creature && (creature->GetNpcFlags() & UNIT_NPC_FLAG_BANKER);
}

void FallbackMenu(Player* player, Creature* creature)
{
    ClearGossipMenuFor(player);
    player->PrepareGossipMenu(creature, creature->GetGossipMenuId(), true);
    AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Open Personal Bank", Sender, OpenBank);
    AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Deposit crafting reagents", Sender, Deposit);
    AddGossipItemFor(player, GOSSIP_ICON_CHAT,
        sNativeReagents.IsAutoDepositEnabled(player) ? "Disable Auto Deposit" : "Enable Auto Deposit", Sender, Toggle);
    player->SendPreparedGossip(creature);
}

class NativeReagentsCreatureScript : public AllCreatureScript
{
public:
    NativeReagentsCreatureScript() : AllCreatureScript("NativeReagentsCreatureScript") { }

    bool CanCreatureGossipHello(Player* player, Creature* creature) override
    {
        if (!sNativeReagents.IsEnabled() || !IsBanker(creature)) return false;
        sNativeReagents.NoteBanker(player, creature);
        // Injected FrameXML identifies itself at login. Sending the stock bank packet
        // keeps Personal Bank as the default surface. Unpatched clients get a small,
        // server-only recovery menu instead of losing access to their stored items.
        if (sNativeReagents.IsUiEnabled() && sNativeReagents.HasNativeSession(player))
        {
            player->GetSession()->SendShowBank(creature->GetGUID());
            return true;
        }
        FallbackMenu(player, creature);
        return true;
    }

    bool CanCreatureGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        if (!sNativeReagents.IsEnabled() || !IsBanker(creature) || sender != Sender) return false;
        sNativeReagents.NoteBanker(player, creature);
        if (action == OpenBank) { player->GetSession()->SendShowBank(creature->GetGUID()); return true; }
        if (action == Deposit)
        {
            if (!sNativeReagents.CanUseReagentBank(player)) return false;
            std::string error; uint64 amount = sNativeReagents.DepositAll(player, error);
            if (!error.empty()) ChatHandler(player->GetSession()).PSendSysMessage("Reagent Bank: {}", error);
            else ChatHandler(player->GetSession()).PSendSysMessage("Deposited {} reagents.", amount);
            FallbackMenu(player, creature); return true;
        }
        if (action == Toggle)
        {
            if (!sNativeReagents.CanUseReagentBank(player)) return false;
            sNativeReagents.SetAutoDeposit(player, !sNativeReagents.IsAutoDepositEnabled(player));
            FallbackMenu(player, creature); return true;
        }
        return false;
    }
};

class NativeReagentsSpellScript : public AllSpellScript
{
public:
    NativeReagentsSpellScript() : AllSpellScript("NativeReagentsSpellScript") { }
    void OnSpellCheckCast(Spell* spell, bool, SpellCastResult& result) override { sNativeReagents.OnSpellCheckCast(spell, result); }
    void OnSpellCast(Spell*, Unit* caster, SpellInfo const* info, bool) override { if (caster && caster->IsPlayer()) sNativeReagents.OnSpellCast(caster->ToPlayer(), info); }
    void OnSpellCastCancel(Spell*, Unit* caster, SpellInfo const* info, bool) override { if (caster && caster->IsPlayer()) sNativeReagents.OnSpellCancel(caster->ToPlayer(), info); }
};

class NativeReagentsPlayerScript : public PlayerScript
{
public:
    NativeReagentsPlayerScript() : PlayerScript("NativeReagentsPlayerScript") { }
    void OnPlayerLogin(Player* player) override { sNativeReagents.OnPlayerLogin(player); }
    void OnPlayerBeforeSendChatMessage(Player* player, uint32& type, uint32& language, std::string& message) override
    {
        if (!player || language != LANG_ADDON || type != CHAT_MSG_WHISPER) return;
        static std::string const prefix = "NRB\t";
        if (message.compare(0, prefix.size(), prefix) != 0) return;
        message = prefix + sNativeReagents.HandleRequest(player, message.substr(prefix.size()));
        if (message.size() > 250) message = prefix + "2|0|ERR|response-too-large";
    }
    void OnPlayerAfterUpdate(Player* player, uint32) override { sNativeReagents.OnPlayerUpdate(player); }
    void OnPlayerBeforeLogout(Player* player) override { sNativeReagents.OnPlayerLogout(player); }
    bool OnPlayerCanSellItem(Player* player, Item* item, Creature*) override { return !item || !sNativeReagents.IsBorrowedItem(player, item->GetEntry()); }
    bool OnPlayerCanSendMail(Player* player, ObjectGuid, ObjectGuid, std::string&, std::string&, uint32, uint32, Item* item) override { return !item || !sNativeReagents.IsBorrowedItem(player, item->GetEntry()); }
    bool OnPlayerCanSetTradeItem(Player* player, Item* item, uint8) override { return !item || !sNativeReagents.IsBorrowedItem(player, item->GetEntry()); }
    bool OnPlayerCanUseItem(Player* player, ItemTemplate const* item, InventoryResult& result) override
    {
        if (!item || !sNativeReagents.IsBorrowedItem(player, item->ItemId)) return true;
        result = EQUIP_ERR_CANT_DO_RIGHT_NOW;
        return false;
    }
};
}

void AddNativeReagentsScripts()
{
    new NativeReagentsCreatureScript();
    new NativeReagentsSpellScript();
    new NativeReagentsPlayerScript();
}
