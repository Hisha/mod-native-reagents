#ifndef MOD_NATIVE_REAGENTS_MANAGER_H
#define MOD_NATIVE_REAGENTS_MANAGER_H

#include "Define.h"

#include <string>
#include <vector>

class Creature;
class ItemTemplate;
class Player;
class Spell;
class SpellInfo;
enum SpellCastResult : uint8;

namespace NativeReagents
{
struct StorageRow { uint32 itemEntry = 0; uint64 quantity = 0; };

class Manager
{
public:
    static Manager& Instance();
    bool IsEnabled() const;
    bool IsUiEnabled() const;
    bool IsRemoteCraftEnabled() const;
    bool IsEligible(ItemTemplate const* item) const;
    bool IsAutoDepositEnabled(Player* player) const;
    bool SetAutoDeposit(Player* player, bool enabled) const;
    uint64 GetStored(Player* player, uint32 itemEntry) const;
    uint32 CountTypes(Player* player) const;
    std::vector<StorageRow> List(Player* player, uint32 offset, uint32 limit) const;
    uint64 DepositAll(Player* player, std::string& error, uint64 operationId = 0) const;
    bool Withdraw(Player* player, uint32 itemEntry, uint32 amount, std::string& error, uint64 operationId = 0) const;
    void NoteBanker(Player* player, Creature* banker);
    void CloseBanker(Player* player);
    bool HasNativeSession(Player* player) const;
    bool CanUseReagentBank(Player* player) const;
    std::string HandleRequest(Player* player, std::string const& payload);
    void OnSpellCheckCast(Spell* spell, SpellCastResult& result);
    void OnSpellCast(Player* player, SpellInfo const* spellInfo);
    void OnSpellCancel(Player* player, SpellInfo const* spellInfo);
    void OnPlayerUpdate(Player* player);
    void OnPlayerLogout(Player* player);
    void OnPlayerLogin(Player* player);
    bool IsBorrowedItem(Player* player, uint32 entry) const;

private:
    bool BeginBorrow(Player* player, Spell* spell, SpellCastResult& result);
    void RollbackBorrow(Player* player);
};
}

#define sNativeReagents NativeReagents::Manager::Instance()
#endif
