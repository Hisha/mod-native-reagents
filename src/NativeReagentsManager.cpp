#include "NativeReagentsManager.h"
#include "NativeReagentsProtocol.h"
#include "NativeReagentsSafety.h"

#include "Bag.h"
#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "Errors.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectGuid.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Spell.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <deque>
#include <limits>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace
{
struct Borrowed { uint32 entry; uint32 amount; uint32 baseline; };
struct BorrowTransaction
{
    uint64 operationId = 0;
    uint32 spellId = 0;
    std::vector<Borrowed> reagents;
    std::chrono::steady_clock::time_point started;
};
struct CraftRequest { uint32 spellId; uint32 remaining; };
struct BankerSession
{
    ObjectGuid banker;
    std::chrono::steady_clock::time_point touched;
    bool clientOpened = false;
};
struct SyncSnapshot
{
    uint32 syncId = 0;
    std::vector<NativeReagents::StorageRow> rows;
    std::chrono::steady_clock::time_point created;
};

std::unordered_map<uint32, BankerSession> Bankers;
std::unordered_map<uint32, SyncSnapshot> Snapshots;
std::unordered_map<uint32, BorrowTransaction> Borrows;
std::unordered_map<uint32, CraftRequest> Crafts;
std::unordered_set<uint32> NativeSessions;
std::unordered_map<uint64, std::string> MutationReplies;
std::unordered_map<uint32, std::deque<uint32>> MutationOrder;
std::unordered_set<uint32> BusyCharacters;
std::atomic<uint64> ServerOperationSequence{1};

uint32 Guid(Player* player) { return player ? player->GetGUID().GetCounter() : 0; }

uint64 NewOperationId()
{
    uint64 now = uint64(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count());
    return (now << 12) ^ (ServerOperationSequence.fetch_add(1) & 0xFFFu);
}

class OperationGuard
{
public:
    explicit OperationGuard(uint32 guid) : _guid(guid), _locked(BusyCharacters.insert(guid).second) { }
    ~OperationGuard() { if (_locked) BusyCharacters.erase(_guid); }
    explicit operator bool() const { return _locked; }
private:
    uint32 _guid;
    bool _locked;
};

enum class OperationStatus { Present, Absent, Unavailable };

OperationStatus GetOperationStatus(uint32 guid, uint64 operationId, char const* kind,
    char const* state, uint64* resultAmount = nullptr)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT operation_row.result_amount FROM (SELECT 1 AS sentinel) AS verification "
        "LEFT JOIN character_native_reagent_operations AS operation_row "
        "ON operation_row.guid={} AND operation_row.operation_id={} "
        "AND operation_row.kind='{}' AND operation_row.state='{}' LIMIT 1",
        guid, operationId, kind, state);
    if (!result)
        return OperationStatus::Unavailable;
    Field* fields = result->Fetch();
    if (fields[0].IsNull())
        return OperationStatus::Absent;
    if (resultAmount)
        *resultAmount = fields[0].Get<uint64>();
    return OperationStatus::Present;
}

[[noreturn]] void FailStopAmbiguousCommit(char const* operation, uint32 guid, uint64 operationId)
{
    LOG_FATAL("module", "Native Reagents cannot determine whether {} operation {} for character {} committed. "
        "Stopping immediately prevents a later character save from creating or losing items.",
        operation, operationId, guid);
    ABORT();
}

bool WithdrawalMatches(uint32 guid, uint64 operationId, uint32 entry, uint32 amount)
{
    return CharacterDatabase.Query(
        "SELECT 1 FROM character_native_reagent_operations "
        "WHERE guid={} AND operation_id={} AND kind='WITHDRAW' AND state='COMPLETED' "
        "AND item_entry={} AND amount={}", guid, operationId, entry, amount) != nullptr;
}

bool ParseArg(std::vector<std::string> const& args, std::size_t index, uint32& value)
{
    return index < args.size() && NativeReagents::Protocol::ParseUInt32(args[index], value);
}

uint64 MaxQuantity()
{
    return sConfigMgr->GetOption<uint64>("NativeReagents.Storage.MaxQuantityPerItem", 0);
}

uint32 MaxTypes()
{
    return sConfigMgr->GetOption<uint32>("NativeReagents.Storage.MaxTypes", 0);
}
}

namespace NativeReagents
{
Manager& Manager::Instance() { static Manager instance; return instance; }
bool Manager::IsEnabled() const { return sConfigMgr->GetOption<bool>("NativeReagents.Enable", true); }
bool Manager::IsUiEnabled() const { return IsEnabled() && sConfigMgr->GetOption<bool>("NativeReagents.UI.Enable", true); }
bool Manager::IsRemoteCraftEnabled() const { return IsEnabled() && sConfigMgr->GetOption<bool>("NativeReagents.RemoteCraft.Enable", false); }

bool Manager::IsEligible(ItemTemplate const* proto) const
{
    if (!proto)
        return false;
    static std::unordered_set<uint32> entries;
    static bool initialized = false;
    if (!initialized)
    {
        for (uint32 id = 1; id < sSpellMgr->GetSpellInfoStoreSize(); ++id)
            if (SpellInfo const* info = sSpellMgr->GetSpellInfo(id))
                if (info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL))
                    for (uint32 i = 0; i < MAX_SPELL_REAGENTS; ++i)
                        if (info->Reagent[i] > 0 && info->ReagentCount[i] > 0)
                            entries.insert(uint32(info->Reagent[i]));
        initialized = true;
    }
    if (entries.find(proto->ItemId) == entries.end())
        return false;
    switch (proto->Class)
    {
        case ITEM_CLASS_CONTAINER: case ITEM_CLASS_WEAPON: case ITEM_CLASS_ARMOR:
        case ITEM_CLASS_PROJECTILE: case ITEM_CLASS_RECIPE: case ITEM_CLASS_MONEY:
        case ITEM_CLASS_QUIVER: case ITEM_CLASS_QUEST: case ITEM_CLASS_KEY: case ITEM_CLASS_GLYPH:
            return false;
        default: return true;
    }
}

bool Manager::IsAutoDepositEnabled(Player* player) const
{
    if (!IsEnabled() || !player || !sConfigMgr->GetOption<bool>("NativeReagents.AutoDeposit.Enable", true))
        return false;
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT auto_deposit FROM character_bank_reagent_settings WHERE guid={}", Guid(player)))
        return result->Fetch()[0].Get<uint8>() != 0;
    return false;
}

bool Manager::SetAutoDeposit(Player* player, bool enabled) const
{
    if (!IsEnabled() || !player || !sConfigMgr->GetOption<bool>("NativeReagents.AutoDeposit.Enable", true))
        return false;
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "INSERT INTO character_bank_reagent_settings(guid,auto_deposit) VALUES({}, {}) "
        "ON DUPLICATE KEY UPDATE auto_deposit=VALUES(auto_deposit)", Guid(player), enabled ? 1 : 0);
    CharacterDatabase.DirectCommitTransaction(transaction);
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT auto_deposit FROM character_bank_reagent_settings WHERE guid={}", Guid(player)))
        return (result->Fetch()[0].Get<uint8>() != 0) == enabled;
    return false;
}

uint64 Manager::GetStored(Player* player, uint32 entry) const
{
    if (!IsEnabled() || !player || !entry)
        return 0;
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT quantity FROM character_bank_reagents WHERE guid={} AND item_entry={}", Guid(player), entry))
        return result->Fetch()[0].Get<uint64>();
    return 0;
}

uint32 Manager::CountTypes(Player* player) const
{
    if (!IsEnabled() || !player)
        return 0;
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT COUNT(*) FROM character_bank_reagents WHERE guid={}", Guid(player)))
        return result->Fetch()[0].Get<uint32>();
    return 0;
}

std::vector<StorageRow> Manager::List(Player* player, uint32 offset, uint32 limit) const
{
    std::vector<StorageRow> rows;
    if (!IsEnabled() || !player || !limit || limit > 50)
        return rows;
    QueryResult result = CharacterDatabase.Query(
        "SELECT item_entry,quantity FROM character_bank_reagents WHERE guid={} "
        "ORDER BY item_entry LIMIT {} OFFSET {}", Guid(player), limit, offset);
    if (!result)
        return rows;
    do
    {
        Field* fields = result->Fetch();
        rows.push_back({fields[0].Get<uint32>(), fields[1].Get<uint64>()});
    } while (result->NextRow());
    return rows;
}

uint64 Manager::DepositAll(Player* player, std::string& error, uint64 operationId) const
{
    if (!IsEnabled() || !player)
    {
        error = "Reagent banking is disabled.";
        return 0;
    }
    OperationGuard guard(Guid(player));
    if (!guard)
    {
        error = "Another reagent operation is still in progress.";
        return 0;
    }
    operationId = operationId ? operationId : NewOperationId();
    uint64 previousResult = 0;
    OperationStatus prior = GetOperationStatus(Guid(player), operationId, "DEPOSIT", "COMPLETED", &previousResult);
    if (prior == OperationStatus::Present)
        return previousResult;
    if (prior == OperationStatus::Unavailable)
    {
        error = "The reagent database is unavailable; nothing was deposited.";
        return 0;
    }

    struct Candidate { uint8 bag; uint8 slot; uint32 entry; uint32 count; };
    std::vector<Candidate> candidates;
    auto inspect = [&](uint8 bag, uint8 slot, Item* item)
    {
        if (item && IsEligible(item->GetTemplate()) && !player->HasQuestForItem(item->GetEntry()))
            candidates.push_back({bag, slot, item->GetEntry(), item->GetCount()});
    };
    for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        inspect(INVENTORY_SLOT_BAG_0, slot, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
    for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
        if (Bag* bag = player->GetBagByPos(bagSlot))
            for (uint32 slot = 0; slot < bag->GetBagSize(); ++slot)
                inspect(bagSlot, uint8(slot), bag->GetItemByPos(slot));

    std::unordered_map<uint32, uint64> additions;
    std::unordered_map<uint32, uint64> finalQuantities;
    for (Candidate const& candidate : candidates)
        additions[candidate.entry] += candidate.count;
    uint32 currentTypes = CountTypes(player), newTypes = 0;
    uint64 quantityLimit = MaxQuantity();
    for (auto const& [entry, amount] : additions)
    {
        uint64 stored = GetStored(player, entry);
        if (!stored)
            ++newTypes;
        uint64 finalQuantity = 0;
        if (!Safety::CheckedAdd(stored, amount, quantityLimit, finalQuantity))
        {
            error = "A reagent quantity limit would be exceeded; nothing was deposited.";
            return 0;
        }
        finalQuantities[entry] = finalQuantity;
    }
    uint32 typeLimit = MaxTypes();
    if (typeLimit && (newTypes > typeLimit || currentTypes > typeLimit - newTypes))
    {
        error = "The reagent type limit would be exceeded; nothing was deposited.";
        return 0;
    }
    if (candidates.empty())
        return 0;

    uint64 total = 0;
    for (Candidate const& candidate : candidates)
    {
        Item* item = player->GetItemByPos(candidate.bag, candidate.slot);
        if (!item || item->GetEntry() != candidate.entry || item->GetCount() != candidate.count ||
            player->HasQuestForItem(candidate.entry))
        {
            error = "Inventory changed during deposit; nothing was deposited.";
            return 0;
        }
        total += candidate.count;
    }

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    for (Candidate const& candidate : candidates)
        player->DestroyItem(candidate.bag, candidate.slot, true);
    for (auto const& [entry, quantity] : finalQuantities)
        transaction->Append(
            "INSERT INTO character_bank_reagents(guid,item_entry,quantity) VALUES({}, {}, {}) "
            "ON DUPLICATE KEY UPDATE quantity=VALUES(quantity)", Guid(player), entry, quantity);
    transaction->Append(
        "INSERT INTO character_native_reagent_operations"
        "(guid,operation_id,kind,state,result_amount) VALUES({}, {}, 'DEPOSIT', 'COMPLETED', {})",
        Guid(player), operationId, total);
    player->SaveToDB(transaction, false, false);
    CharacterDatabase.DirectCommitTransaction(transaction);
    OperationStatus committed = GetOperationStatus(Guid(player), operationId, "DEPOSIT", "COMPLETED");
    Safety::CommitDecision decision = Safety::ClassifyCommitVerification(
        committed != OperationStatus::Unavailable, committed == OperationStatus::Present);
    if (decision == Safety::CommitDecision::Accept)
        return total;
    if (decision == Safety::CommitDecision::FailStop)
        FailStopAmbiguousCommit("deposit", Guid(player), operationId);

    // The database transaction rolled back. No other player action can interleave
    // with DirectCommitTransaction on the world thread, so restoring by entry returns
    // the live inventory to the same totals that remain persistent in the database.
    bool restored = true;
    for (auto const& [entry, amount] : additions)
    {
        ItemPosCountVec destination;
        if (amount > std::numeric_limits<uint32>::max() ||
            player->CanStoreNewItem(NULL_BAG, NULL_SLOT, destination, entry, uint32(amount)) != EQUIP_ERR_OK ||
            !player->StoreNewItem(destination, entry, true))
            restored = false;
    }
    error = "The reagent deposit could not be committed; no persistent items were moved.";
    if (!restored)
    {
        error += " Reconnect to reload the unchanged persistent inventory.";
        player->GetSession()->KickPlayer("Native Reagents deposit recovery");
    }
    return 0;
}

bool Manager::Withdraw(Player* player, uint32 entry, uint32 amount, std::string& error, uint64 operationId) const
{
    if (!IsEnabled() || !player || !entry || !amount)
    {
        error = "Invalid withdrawal request.";
        return false;
    }
    OperationGuard guard(Guid(player));
    if (!guard)
    {
        error = "Another reagent operation is still in progress.";
        return false;
    }
    operationId = operationId ? operationId : NewOperationId();
    OperationStatus prior = GetOperationStatus(Guid(player), operationId, "WITHDRAW", "COMPLETED");
    if (prior == OperationStatus::Present)
    {
        if (WithdrawalMatches(Guid(player), operationId, entry, amount)) return true;
        error = "The request identifier was already used for another withdrawal.";
        return false;
    }
    if (prior == OperationStatus::Unavailable)
    {
        error = "The reagent database is unavailable; nothing was withdrawn.";
        return false;
    }
    uint64 stored = GetStored(player, entry);
    if (!sObjectMgr->GetItemTemplate(entry) || stored < amount)
    {
        error = "That quantity is no longer stored.";
        return false;
    }
    ItemPosCountVec destination;
    InventoryResult result = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, destination, entry, amount);
    if (result != EQUIP_ERR_OK)
    {
        player->SendEquipError(result, nullptr, nullptr, entry);
        error = "There is not enough inventory space.";
        return false;
    }
    Item* item = player->StoreNewItem(destination, entry, true);
    if (!item)
    {
        error = "The item could not be created.";
        return false;
    }
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    uint64 remaining = 0;
    if (!Safety::CheckedSubtract(stored, amount, remaining))
    {
        player->DestroyItemCount(entry, amount, true);
        error = "That quantity is no longer stored.";
        return false;
    }
    transaction->Append(
        "INSERT INTO character_bank_reagents(guid,item_entry,quantity) VALUES({}, {}, {}) "
        "ON DUPLICATE KEY UPDATE quantity=VALUES(quantity)", Guid(player), entry, remaining);
    transaction->Append("DELETE FROM character_bank_reagents WHERE guid={} AND item_entry={} AND quantity=0", Guid(player), entry);
    transaction->Append(
        "INSERT INTO character_native_reagent_operations"
        "(guid,operation_id,kind,state,item_entry,amount,result_amount) "
        "VALUES({}, {}, 'WITHDRAW', 'COMPLETED', {}, {}, {})",
        Guid(player), operationId, entry, amount, amount);
    player->SaveToDB(transaction, false, false);
    CharacterDatabase.DirectCommitTransaction(transaction);
    OperationStatus committed = GetOperationStatus(Guid(player), operationId, "WITHDRAW", "COMPLETED");
    Safety::CommitDecision decision = Safety::ClassifyCommitVerification(
        committed != OperationStatus::Unavailable, committed == OperationStatus::Present);
    if (decision != Safety::CommitDecision::Accept)
    {
        if (decision == Safety::CommitDecision::FailStop)
            FailStopAmbiguousCommit("withdrawal", Guid(player), operationId);
        // No world-thread action can interleave with the direct commit, so returning
        // the total to its pre-operation baseline is deterministic.
        player->DestroyItemCount(entry, amount, true);
        error = "The reagent withdrawal could not be committed; no persistent items were moved.";
        return false;
    }
    player->SendNewItem(item, amount, true, false);
    return true;
}

void Manager::NoteBanker(Player* player, Creature* banker, bool clientOpened)
{
    if (player && banker && (banker->GetNpcFlags() & UNIT_NPC_FLAG_BANKER))
        Bankers[Guid(player)] = {banker->GetGUID(), std::chrono::steady_clock::now(), clientOpened};
}

bool Manager::ConfirmBankerOpen(Player* player, std::string* reason)
{
    if (!player)
    {
        if (reason) *reason = "no-player";
        return false;
    }
    auto found = Bankers.find(Guid(player));
    if (found == Bankers.end())
    {
        if (reason) *reason = "no-server-session";
        return false;
    }
    uint32 timeout = std::max<uint32>(5,
        sConfigMgr->GetOption<uint32>("NativeReagents.BankerSession.TimeoutSeconds", 300));
    auto age = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - found->second.touched).count();
    if (age >= timeout)
    {
        if (reason) *reason = "expired";
        Bankers.erase(found);
        return false;
    }
    if (!player->GetNPCIfCanInteractWith(found->second.banker, UNIT_NPC_FLAG_BANKER))
    {
        if (reason) *reason = "banker-not-interactable";
        Bankers.erase(found);
        return false;
    }
    found->second.clientOpened = true;
    found->second.touched = std::chrono::steady_clock::now();
    if (reason) *reason = "authorized";
    return true;
}

void Manager::CloseBanker(Player* player)
{
    if (player)
        Bankers.erase(Guid(player));
}

bool Manager::HasNativeSession(Player* player) const
{
    return player && NativeSessions.find(Guid(player)) != NativeSessions.end();
}

bool Manager::CanUseReagentBank(Player* player, std::string* reason) const
{
    if (!player)
    {
        if (reason) *reason = "no-player";
        return false;
    }
    auto found = Bankers.find(Guid(player));
    if (found == Bankers.end())
    {
        if (reason) *reason = "no-server-session";
        return false;
    }
    if (!found->second.clientOpened)
    {
        if (reason) *reason = "client-not-open";
        return false;
    }
    uint32 timeout = std::max<uint32>(5,
        sConfigMgr->GetOption<uint32>("NativeReagents.BankerSession.TimeoutSeconds", 300));
    auto age = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - found->second.touched).count();
    bool expired = age >= timeout;
    bool interactable = player->GetNPCIfCanInteractWith(found->second.banker, UNIT_NPC_FLAG_BANKER) != nullptr;
    if (!Safety::BankSessionUsable(found->second.clientOpened, expired, interactable))
    {
        if (reason) *reason = expired ? "expired" : "banker-not-interactable";
        Bankers.erase(found);
        return false;
    }
    found->second.touched = std::chrono::steady_clock::now();
    if (reason) *reason = "authorized";
    return true;
}

std::string Manager::HandleRequest(Player* player, std::string const& payload)
{
    auto parsed = Protocol::Parse(payload);
    if (!parsed)
        return Protocol::Reply(0, "ERR", "bad-request");
    auto const& request = *parsed;
    auto reply = [&](std::string_view kind, std::string_view body = {}) { return Protocol::Reply(request.id, kind, body); };
    if (!IsEnabled()) return reply("ERR", "disabled");
    auto authorize = [&](bool confirmOpen = false)
    {
        std::string reason;
        bool allowed = confirmOpen ? ConfirmBankerOpen(player, &reason) : CanUseReagentBank(player, &reason);
        if (sConfigMgr->GetOption<bool>("NativeReagents.Debug", false))
            LOG_INFO("module", "Native Reagents authorization operation={} character={} outcome={} reason={}",
                request.command, Guid(player), allowed ? "allowed" : "rejected", reason);
        return allowed;
    };

    if (request.command == "HELLO")
    {
        NativeSessions.insert(Guid(player));
        return reply("HELLO", std::string(IsRemoteCraftEnabled() ? "1" : "0") + "|" + (IsUiEnabled() ? "1" : "0"));
    }
    if (request.command == "SYNC")
    {
        uint32 syncId = 0, pageIndex = 0;
        if (!ParseArg(request.arguments, 0, syncId) || !syncId ||
            !ParseArg(request.arguments, 1, pageIndex))
            return reply("ERR", "bad-sync-request");
        // Five worst-case uint32:uint64 rows plus sync metadata and outer framing
        // always remain below the build-12340 addon-message payload bound.
        constexpr uint32 pageSize = 5;
        uint32 guid = Guid(player);
        if (pageIndex == 0)
        {
            SyncSnapshot snapshot;
            snapshot.syncId = syncId;
            snapshot.created = std::chrono::steady_clock::now();
            for (uint32 offset = 0;; offset += 50)
            {
                auto rows = List(player, offset, 50);
                snapshot.rows.insert(snapshot.rows.end(), rows.begin(), rows.end());
                if (rows.size() < 50) break;
            }
            Snapshots[guid] = std::move(snapshot);
        }
        auto snapshot = Snapshots.find(guid);
        if (snapshot == Snapshots.end() || snapshot->second.syncId != syncId)
            return reply("ERR", "stale-sync");
        uint32 totalPages = std::max<uint32>(1, uint32((snapshot->second.rows.size() + pageSize - 1) / pageSize));
        if (pageIndex >= totalPages)
            return reply("ERR", "bad-sync-page");
        uint32 offset = pageIndex * pageSize;
        uint32 end = std::min<uint32>(uint32(snapshot->second.rows.size()), offset + pageSize);
        std::ostringstream body;
        body << syncId << '|' << pageIndex << '|' << totalPages << '|';
        for (uint32 i = offset; i < end; ++i)
        {
            if (i != offset) body << ',';
            body << snapshot->second.rows[i].itemEntry << ':' << snapshot->second.rows[i].quantity;
        }
        return reply("DATA", body.str());
    }
    bool mutation = request.command == "DEPOSIT" || request.command == "AUTO" ||
        request.command == "WITHDRAW" || request.command == "CRAFT" || request.command == "CANCEL";
    uint32 guid = Guid(player);
    uint64 requestKey = (uint64(guid) << 32) | request.id;
    auto previous = MutationReplies.find(requestKey);
    if (mutation && previous != MutationReplies.end())
        return previous->second;
    auto finish = [&](std::string response)
    {
        if (mutation)
        {
            MutationReplies[requestKey] = response;
            auto& order = MutationOrder[guid];
            order.push_back(request.id);
            if (order.size() > 64)
            {
                MutationReplies.erase((uint64(guid) << 32) | order.front());
                order.pop_front();
            }
        }
        return response;
    };
    if (request.command == "BANKOPEN")
    {
        // This message confirms only client presentation state. The session itself
        // was established from AzerothCore's validated banker-activation path.
        if (!authorize(true)) return reply("ERR", "banker-required");
        std::string error;
        uint64 deposited = IsAutoDepositEnabled(player) ? DepositAll(player, error, requestKey) : 0;
        return error.empty() ? reply("BANK", std::to_string(deposited) + "|" + (IsAutoDepositEnabled(player) ? "1" : "0")) : reply("ERR", error);
    }
    if (request.command == "BANKCLOSE")
    {
        CloseBanker(player);
        return reply("OK", "bank-closed");
    }
    if (request.command == "DEPOSIT")
    {
        if (!authorize()) return finish(reply("ERR", "banker-required"));
        std::string error; uint64 amount = DepositAll(player, error, requestKey);
        return finish(error.empty() ? reply("DEPOSITED", std::to_string(amount)) : reply("ERR", error));
    }
    if (request.command == "AUTO")
    {
        if (request.arguments.empty()) return finish(reply("AUTO", IsAutoDepositEnabled(player) ? "1" : "0"));
        uint32 enabled = 0;
        if (!authorize()) return finish(reply("ERR", "banker-required"));
        if (!ParseArg(request.arguments, 0, enabled) || enabled > 1) return finish(reply("ERR", "bad-auto-deposit"));
        if (!SetAutoDeposit(player, enabled != 0)) return finish(reply("ERR", "auto-deposit-disabled"));
        return finish(reply("AUTO", enabled ? "1" : "0"));
    }
    if (request.command == "WITHDRAW")
    {
        uint32 entry = 0, amount = 0;
        if (!authorize()) return finish(reply("ERR", "banker-required"));
        if (!ParseArg(request.arguments, 0, entry) || !ParseArg(request.arguments, 1, amount)) return finish(reply("ERR", "bad-withdrawal"));
        std::string error;
        return finish(Withdraw(player, entry, amount, error, requestKey) ? reply("WITHDRAWN", std::to_string(entry) + "|" + std::to_string(amount)) : reply("ERR", error));
    }
    if (request.command == "CRAFT")
    {
        uint32 spellId = 0, count = 1;
        if (!IsRemoteCraftEnabled() || NativeSessions.find(Guid(player)) == NativeSessions.end()) return finish(reply("ERR", "remote-craft-disabled"));
        if (!ParseArg(request.arguments, 0, spellId) || (request.arguments.size() > 1 && !ParseArg(request.arguments, 1, count))) return finish(reply("ERR", "bad-craft"));
        SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
        if (!info || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) || !player->HasSpell(spellId)) return finish(reply("ERR", "unknown-recipe"));
        count = std::max<uint32>(1, std::min<uint32>(count, 1000));
        for (uint32 i = 0; i < MAX_SPELL_REAGENTS; ++i)
            if (info->Reagent[i] > 0)
            {
                uint64 stored = GetStored(player, info->Reagent[i]);
                uint32 needed = info->ReagentCount[i];
                uint32 carried = player->GetItemCount(info->Reagent[i], false);
                if (stored < needed && carried < needed - stored)
                    return finish(reply("ERR", "not-enough-reagents"));
            }
        Crafts[Guid(player)] = {spellId, count};
        return finish(reply("QUEUED", std::to_string(spellId) + "|" + std::to_string(count)));
    }
    if (request.command == "CANCEL")
    {
        Crafts.erase(Guid(player)); RollbackBorrow(player); return finish(reply("OK", "cancelled"));
    }
    return reply("ERR", "unknown-command");
}

bool Manager::BeginBorrow(Player* player, Spell* spell, SpellCastResult& result)
{
    if (!player || !spell || result != SPELL_CAST_OK || NativeSessions.find(Guid(player)) == NativeSessions.end()) return false;
    uint32 guid = Guid(player);
    SpellInfo const* info = spell->GetSpellInfo();
    if (!info || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) || !player->HasSpell(info->Id)) return false;
    auto activeBorrow = Borrows.find(guid);
    if (activeBorrow != Borrows.end())
    {
        if (activeBorrow->second.spellId == info->Id) return true;
        result = SPELL_FAILED_DONT_REPORT;
        return false;
    }
    std::unordered_map<uint32, uint32> requiredByEntry;
    for (uint32 i = 0; i < MAX_SPELL_REAGENTS; ++i)
        if (info->Reagent[i] > 0 && info->ReagentCount[i] > 0)
        {
            uint32 entry = info->Reagent[i];
            uint32 count = info->ReagentCount[i];
            if (requiredByEntry[entry] > std::numeric_limits<uint32>::max() - count)
            {
                result = SPELL_FAILED_DONT_REPORT;
                return false;
            }
            requiredByEntry[entry] += count;
        }

    std::vector<Borrowed> borrowed;
    std::unordered_map<uint32, uint64> remainingStored;
    for (auto const& [entry, required] : requiredByEntry)
    {
        uint32 carried = player->GetItemCount(entry, false);
        if (carried >= required || !IsEligible(sObjectMgr->GetItemTemplate(entry))) continue;
        uint32 missing = required - carried;
        uint64 stored = GetStored(player, entry);
        if (stored < missing) return false; // Let the stock reagent check reject it.
        borrowed.push_back({entry, missing, carried});
        remainingStored[entry] = stored - missing;
    }
    if (borrowed.empty()) return true;

    std::vector<Borrowed> materialized;
    for (Borrowed const& planned : borrowed)
    {
        ItemPosCountVec destination;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, destination, planned.entry, planned.amount) != EQUIP_ERR_OK)
        {
            for (Borrowed const& row : materialized) player->DestroyItemCount(row.entry, row.amount, true);
            result = SPELL_FAILED_DONT_REPORT;
            ChatHandler(player->GetSession()).SendSysMessage("Reagent Storage has the materials, but temporary bag space is required.");
            return false;
        }
        Item* item = player->StoreNewItem(destination, planned.entry, true);
        if (!item)
        {
            for (Borrowed const& row : materialized) player->DestroyItemCount(row.entry, row.amount, true);
            result = SPELL_FAILED_DONT_REPORT;
            return false;
        }
        materialized.push_back(planned);
    }

    uint64 operationId = NewOperationId();
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "INSERT INTO character_native_reagent_operations"
        "(guid,operation_id,kind,state,item_entry,amount,result_amount) "
        "VALUES({}, {}, 'CRAFT', 'BORROWED', {}, 0, {})",
        guid, operationId, info->Id, borrowed.size());
    for (Borrowed const& row : borrowed)
    {
        transaction->Append(
            "INSERT INTO character_bank_reagents(guid,item_entry,quantity) VALUES({}, {}, {}) "
            "ON DUPLICATE KEY UPDATE quantity=VALUES(quantity)", guid, row.entry, remainingStored[row.entry]);
        transaction->Append("DELETE FROM character_bank_reagents WHERE guid={} AND item_entry={} AND quantity=0", guid, row.entry);
        transaction->Append(
            "INSERT INTO character_native_reagent_operation_items"
            "(guid,operation_id,item_entry,amount,baseline) VALUES({}, {}, {}, {}, {})",
            guid, operationId, row.entry, row.amount, row.baseline);
    }
    player->SaveToDB(transaction, false, false);
    CharacterDatabase.DirectCommitTransaction(transaction);
    OperationStatus borrowedState = GetOperationStatus(guid, operationId, "CRAFT", "BORROWED");
    Safety::CommitDecision decision = Safety::ClassifyCommitVerification(
        borrowedState != OperationStatus::Unavailable, borrowedState == OperationStatus::Present);
    if (decision != Safety::CommitDecision::Accept)
    {
        if (decision == Safety::CommitDecision::FailStop)
            FailStopAmbiguousCommit("craft borrow", guid, operationId);
        for (Borrowed const& row : borrowed) player->DestroyItemCount(row.entry, row.amount, true);
        result = SPELL_FAILED_DONT_REPORT;
        ChatHandler(player->GetSession()).SendSysMessage("Remote crafting could not reserve its reagents.");
        return false;
    }
    Borrows[guid] = BorrowTransaction{operationId, info->Id, std::move(borrowed), std::chrono::steady_clock::now()};
    return true;
}

void Manager::RollbackBorrow(Player* player)
{
    if (!player) return;
    auto found = Borrows.find(Guid(player));
    if (found == Borrows.end()) return;
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    std::unordered_map<uint32, uint64> restoredStorage;
    for (Borrowed const& row : found->second.reagents)
    {
        uint64 stored = GetStored(player, row.entry), finalQuantity = 0;
        if (!Safety::CheckedAdd(stored, row.amount, 0, finalQuantity))
        {
            ChatHandler(player->GetSession()).SendSysMessage("Remote crafting rollback exceeded the storage numeric bound; administrator review is required.");
            return;
        }
        restoredStorage[row.entry] = finalQuantity;
        uint32 now = player->GetItemCount(row.entry, false);
        uint32 removable = now > row.baseline ? std::min(row.amount, now - row.baseline) : 0;
        if (removable != row.amount)
        {
            CharacterDatabaseTransaction review = CharacterDatabase.BeginTransaction();
            review->Append(
                "UPDATE character_native_reagent_operations SET state='REVIEW' "
                "WHERE guid={} AND operation_id={} AND state='BORROWED'",
                Guid(player), found->second.operationId);
            CharacterDatabase.DirectCommitTransaction(review);
            Borrows.erase(found);
            ChatHandler(player->GetSession()).SendSysMessage(
                "Remote crafting recovery found an ambiguous reagent balance; no automatic credit was made.");
            return;
        }
    }
    for (Borrowed const& row : found->second.reagents)
    {
        player->DestroyItemCount(row.entry, row.amount, true);
        transaction->Append(
            "INSERT INTO character_bank_reagents(guid,item_entry,quantity) VALUES({}, {}, {}) "
            "ON DUPLICATE KEY UPDATE quantity=VALUES(quantity)", Guid(player), row.entry, restoredStorage[row.entry]);
    }
    transaction->Append(
        "UPDATE character_native_reagent_operations SET state='ROLLEDBACK' "
        "WHERE guid={} AND operation_id={} AND state='BORROWED'",
        Guid(player), found->second.operationId);
    player->SaveToDB(transaction, false, false);
    uint64 operationId = found->second.operationId;
    CharacterDatabase.DirectCommitTransaction(transaction);
    OperationStatus rollbackState = GetOperationStatus(Guid(player), operationId, "CRAFT", "ROLLEDBACK");
    Safety::CommitDecision decision = Safety::ClassifyCommitVerification(
        rollbackState != OperationStatus::Unavailable, rollbackState == OperationStatus::Present);
    if (decision == Safety::CommitDecision::Accept)
        Borrows.erase(found);
    else
    {
        if (decision == Safety::CommitDecision::FailStop)
            FailStopAmbiguousCommit("craft rollback", Guid(player), operationId);
        for (Borrowed const& row : found->second.reagents)
        {
            ItemPosCountVec destination;
            if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, destination, row.entry, row.amount) == EQUIP_ERR_OK)
                player->StoreNewItem(destination, row.entry, true);
        }
        player->GetSession()->KickPlayer("Native Reagents craft rollback recovery");
    }
}

void Manager::OnSpellCheckCast(Spell* spell, SpellCastResult& result) { if (IsRemoteCraftEnabled() && spell && spell->GetCaster()->IsPlayer()) BeginBorrow(spell->GetCaster()->ToPlayer(), spell, result); }
void Manager::OnSpellCast(Player* player, SpellInfo const* info)
{
    if (!player || !info) return;
    auto found = Borrows.find(Guid(player));
    if (found == Borrows.end() || found->second.spellId != info->Id) return;
    // Core calls this hook after TakeReagents() and immediate spell effects. Persist
    // the consumed state, crafted result, and journal completion atomically.
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    transaction->Append(
        "UPDATE character_native_reagent_operations SET state='COMPLETED' "
        "WHERE guid={} AND operation_id={} AND state='BORROWED'",
        Guid(player), found->second.operationId);
    player->SaveToDB(transaction, false, false);
    uint64 operationId = found->second.operationId;
    CharacterDatabase.DirectCommitTransaction(transaction);
    Borrows.erase(found); // Never refund after the core has consumed reagents.
    OperationStatus completionState = GetOperationStatus(Guid(player), operationId, "CRAFT", "COMPLETED");
    Safety::CommitDecision decision = Safety::ClassifyCommitVerification(
        completionState != OperationStatus::Unavailable, completionState == OperationStatus::Present);
    if (decision != Safety::CommitDecision::Accept)
    {
        if (decision == Safety::CommitDecision::FailStop)
            FailStopAmbiguousCommit("craft completion", Guid(player), operationId);
        CharacterDatabase.Execute(
            "UPDATE character_native_reagent_operations SET state='REVIEW' "
            "WHERE guid={} AND operation_id={} AND state='BORROWED'", Guid(player), operationId);
        player->GetSession()->KickPlayer("Native Reagents craft completion recovery");
    }
}
void Manager::OnSpellCancel(Player* player, SpellInfo const* info) { if (!player) return; auto found = Borrows.find(Guid(player)); if (!info || (found != Borrows.end() && found->second.spellId == info->Id)) RollbackBorrow(player); }

void Manager::OnPlayerUpdate(Player* player)
{
    if (!player) return;
    uint32 guid = Guid(player);
    auto banker = Bankers.find(guid);
    if (banker != Bankers.end())
    {
        uint32 timeout = std::max<uint32>(5,
            sConfigMgr->GetOption<uint32>("NativeReagents.BankerSession.TimeoutSeconds", 300));
        auto age = std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::steady_clock::now() - banker->second.touched).count();
        if (age >= timeout || !player->GetNPCIfCanInteractWith(banker->second.banker, UNIT_NPC_FLAG_BANKER))
            Bankers.erase(banker);
    }
    auto snapshot = Snapshots.find(guid);
    if (snapshot != Snapshots.end() && std::chrono::steady_clock::now() - snapshot->second.created > std::chrono::seconds(30))
        Snapshots.erase(snapshot);
    auto borrow = Borrows.find(guid);
    if (borrow != Borrows.end())
    {
        auto age = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - borrow->second.started).count();
        uint32 timeout = std::max<uint32>(5, sConfigMgr->GetOption<uint32>("NativeReagents.RemoteCraft.TransactionTimeoutSeconds", 30));
        if (age >= timeout || (age >= 1 && !player->FindCurrentSpellBySpellId(borrow->second.spellId))) { RollbackBorrow(player); Crafts.erase(guid); }
        return;
    }
    auto request = Crafts.find(guid);
    if (request == Crafts.end() || player->IsNonMeleeSpellCast(false)) return;
    if (!request->second.remaining) { Crafts.erase(request); return; }
    SpellInfo const* info = sSpellMgr->GetSpellInfo(request->second.spellId);
    if (!info || !player->HasSpell(info->Id) || player->CastSpell(player, info->Id, false) != SPELL_CAST_OK) { Crafts.erase(request); return; }
    if (--request->second.remaining == 0) Crafts.erase(request);
}

void Manager::OnPlayerLogout(Player* player)
{
    if (!player) return;
    RollbackBorrow(player); Crafts.erase(Guid(player)); NativeSessions.erase(Guid(player)); Bankers.erase(Guid(player)); Snapshots.erase(Guid(player)); BusyCharacters.erase(Guid(player));
    auto order = MutationOrder.find(Guid(player));
    if (order != MutationOrder.end())
    {
        for (uint32 id : order->second) MutationReplies.erase((uint64(Guid(player)) << 32) | id);
        MutationOrder.erase(order);
    }
}

void Manager::OnPlayerLogin(Player* player)
{
    if (!player) return;
    uint32 guid = Guid(player);
    CharacterDatabase.Execute(
        "DELETE FROM character_native_reagent_operations WHERE guid={} AND state IN ('COMPLETED','ROLLEDBACK') "
        "AND created_at < (CURRENT_TIMESTAMP - INTERVAL 30 DAY)", guid);
    QueryResult operations = CharacterDatabase.Query(
        "SELECT operation_id,item_entry FROM character_native_reagent_operations "
        "WHERE guid={} AND kind='CRAFT' AND state='BORROWED' ORDER BY operation_id", guid);
    if (!operations) return;
    do
    {
        Field* fields = operations->Fetch();
        uint64 operationId = fields[0].Get<uint64>();
        uint32 spellId = fields[1].Get<uint32>();
        QueryResult items = CharacterDatabase.Query(
            "SELECT item_entry,amount,baseline FROM character_native_reagent_operation_items "
            "WHERE guid={} AND operation_id={} ORDER BY item_entry", guid, operationId);
        std::vector<Borrowed> borrowed;
        bool exact = items != nullptr;
        if (items)
            do
            {
                Field* row = items->Fetch();
                Borrowed value{row[0].Get<uint32>(), row[1].Get<uint32>(), row[2].Get<uint32>()};
                if (Safety::ClassifyBorrowRecovery(player->GetItemCount(value.entry, false), value.baseline, value.amount) == Safety::BorrowRecovery::Review)
                    exact = false;
                borrowed.push_back(value);
            } while (items->NextRow());
        if (!exact)
        {
            CharacterDatabase.Execute(
                "UPDATE character_native_reagent_operations SET state='REVIEW' "
                "WHERE guid={} AND operation_id={} AND state='BORROWED'", guid, operationId);
            ChatHandler(player->GetSession()).SendSysMessage(
                "A remote-crafting recovery record requires administrator review; no automatic reagent credit was made.");
            continue;
        }
        Borrows[guid] = BorrowTransaction{operationId, spellId, std::move(borrowed), std::chrono::steady_clock::now()};
        RollbackBorrow(player);
    } while (operations->NextRow());

}

bool Manager::IsBorrowedItem(Player* player, uint32 entry) const
{
    if (!player) return false;
    auto found = Borrows.find(Guid(player));
    if (found == Borrows.end()) return false;
    return std::any_of(found->second.reagents.begin(), found->second.reagents.end(), [entry](Borrowed const& row) { return row.entry == entry; });
}
}
