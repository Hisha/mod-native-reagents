#include "../src/NativeReagentsSafety.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
#include <set>
#include <vector>

using NativeReagents::Safety::BorrowRecovery;
using NativeReagents::Safety::CommitDecision;

struct Model
{
    std::uint64_t inventory = 0;
    std::uint64_t storage = 0;
    std::uint64_t capacity = std::numeric_limits<std::uint64_t>::max();
    bool busy = false;
    std::set<std::uint64_t> committed;

    bool Deposit(std::uint64_t id, std::uint64_t amount, bool databaseCommit)
    {
        if (committed.count(id)) return true;
        if (busy || !amount || inventory < amount) return false;
        busy = true;
        std::uint64_t next = 0;
        if (!NativeReagents::Safety::CheckedAdd(storage, amount, 0, next)) { busy = false; return false; }
        auto oldInventory = inventory, oldStorage = storage;
        inventory -= amount; storage = next;
        if (!databaseCommit) { inventory = oldInventory; storage = oldStorage; busy = false; return false; }
        committed.insert(id); busy = false; return true;
    }

    bool Withdraw(std::uint64_t id, std::uint64_t amount, bool databaseCommit)
    {
        if (committed.count(id)) return true;
        if (busy || !amount || inventory > capacity - amount) return false;
        busy = true;
        std::uint64_t next = 0;
        if (!NativeReagents::Safety::CheckedSubtract(storage, amount, next)) { busy = false; return false; }
        auto oldInventory = inventory, oldStorage = storage;
        inventory += amount; storage = next;
        if (!databaseCommit) { inventory = oldInventory; storage = oldStorage; busy = false; return false; }
        committed.insert(id); busy = false; return true;
    }
};

struct CraftModel
{
    CraftModel(std::uint64_t carried, std::uint64_t stored) : inventory(carried), storage(stored) { }
    std::uint64_t inventory;
    std::uint64_t storage;
    std::uint64_t borrowed = 0;
    std::uint64_t baseline = 0;
    bool active = false;

    bool Begin(std::uint64_t required, bool hasSpace, bool commit)
    {
        baseline = inventory;
        if (inventory >= required) return true;
        borrowed = required - inventory;
        if (!hasSpace || storage < borrowed) return false;
        auto oldInventory = inventory, oldStorage = storage;
        inventory += borrowed; storage -= borrowed;
        if (!commit) { inventory = oldInventory; storage = oldStorage; borrowed = 0; return false; }
        active = true; return true;
    }
    void Complete(std::uint64_t required)
    {
        assert(active && inventory >= required);
        inventory -= required; active = false; borrowed = 0;
    }
    bool Cancel()
    {
        if (!active || NativeReagents::Safety::ClassifyBorrowRecovery(inventory, baseline, borrowed) != BorrowRecovery::Rollback)
            return false;
        inventory -= borrowed; storage += borrowed; active = false; borrowed = 0; return true;
    }
};

struct StackDepositModel
{
    struct Stack { std::uint64_t count; bool eligible = true; bool questProtected = false; bool plain = true; };
    std::vector<Stack> stacks;
    std::uint64_t storage = 0;
    std::uint64_t quantityLimit = 0;
    bool typeLimitReached = false;
    bool banker = true;
    bool expired = false;
    std::set<std::uint64_t> committed;

    bool Deposit(std::uint64_t request, std::uint64_t amount, bool databaseCommit = true)
    {
        if (committed.count(request)) return true;
        if (!amount || !banker || expired || typeLimitReached) return false;
        std::uint64_t available = 0;
        for (Stack const& stack : stacks)
            if (stack.eligible && !stack.questProtected && stack.plain) available += stack.count;
        std::uint64_t next = 0;
        if (available < amount || !NativeReagents::Safety::CheckedAdd(storage, amount, quantityLimit, next)) return false;
        auto before = stacks;
        std::uint64_t remaining = amount;
        for (Stack& stack : stacks)
            if (stack.eligible && !stack.questProtected && stack.plain)
            {
                std::uint64_t take = std::min(stack.count, remaining);
                stack.count -= take; remaining -= take;
                if (!remaining) break;
            }
        if (!databaseCommit) { stacks = before; return false; }
        storage = next; committed.insert(request); return true;
    }

    std::uint64_t Inventory() const
    {
        std::uint64_t total = 0;
        for (Stack const& stack : stacks) total += stack.count;
        return total;
    }
};

int main()
{
    Model bank;
    bank.inventory = 20; bank.storage = 10; bank.capacity = 100;
    assert(bank.Deposit(1, 5, true));
    assert(bank.inventory == 15 && bank.storage == 15 && bank.inventory + bank.storage == 30);
    assert(bank.Deposit(1, 5, true)); // durable duplicate id
    assert(bank.inventory == 15 && bank.storage == 15);
    assert(bank.Withdraw(2, 7, true));
    assert(bank.inventory == 22 && bank.storage == 8 && bank.inventory + bank.storage == 30);
    assert(!bank.Withdraw(3, 9, true));
    assert(!bank.Withdraw(3, 0, true));

    auto beforeInventory = bank.inventory, beforeStorage = bank.storage;
    assert(!bank.Deposit(4, 4, false));
    assert(bank.inventory == beforeInventory && bank.storage == beforeStorage);
    assert(!bank.Withdraw(5, 4, false));
    assert(bank.inventory == beforeInventory && bank.storage == beforeStorage);

    bank.capacity = bank.inventory;
    assert(!bank.Withdraw(6, 1, true)); // full inventory
    bank.busy = true;
    assert(!bank.Deposit(7, 1, true) && !bank.Withdraw(8, 1, true));
    bank.busy = false;

    StackDepositModel stacks;
    stacks.stacks = {{20}};
    assert(stacks.Deposit(10, 20) && stacks.Inventory() == 0 && stacks.storage == 20); // full stack
    stacks.stacks = {{20}};
    assert(stacks.Deposit(11, 7) && stacks.Inventory() == 13 && stacks.storage == 27); // partial stack
    stacks.stacks = {{20}, {20}, {20}};
    assert(stacks.Deposit(12, 40) && stacks.Inventory() == 20 && stacks.storage == 67); // multiple stacks
    assert(stacks.Deposit(12, 40) && stacks.Inventory() == 20 && stacks.storage == 67); // duplicate
    auto stackInventory = stacks.Inventory(), stackStorage = stacks.storage;
    assert(!stacks.Deposit(13, 21) && stacks.Inventory() == stackInventory && stacks.storage == stackStorage);
    assert(!stacks.Deposit(14, 0));
    stacks.stacks = {{5, false}, {5, true, true}, {5, true, false, false}};
    assert(!stacks.Deposit(15, 1)); // ineligible, quest-protected, and stateful instances excluded
    stacks.stacks = {{10}}; stacks.quantityLimit = stackStorage + 5;
    assert(!stacks.Deposit(16, 6) && stacks.Inventory() == 10 && stacks.storage == stackStorage);
    stacks.quantityLimit = 0; stacks.typeLimitReached = true;
    assert(!stacks.Deposit(17, 1));
    stacks.typeLimitReached = false; stacks.banker = false;
    assert(!stacks.Deposit(18, 1));
    stacks.banker = true; stacks.expired = true;
    assert(!stacks.Deposit(19, 1));
    stacks.expired = false;
    assert(!stacks.Deposit(20, 6, false) && stacks.Inventory() == 10 && stacks.storage == stackStorage);

    StackDepositModel consecutive;
    consecutive.stacks = {{20}, {20}};
    assert(consecutive.Deposit(21, 7) && consecutive.Deposit(22, 13));
    assert(consecutive.Inventory() == 20 && consecutive.storage == 20);
    CraftModel afterIndividualDeposit{consecutive.Inventory(), consecutive.storage};
    assert(afterIndividualDeposit.Begin(25, true, true)); // inventory first, then five stored
    assert(afterIndividualDeposit.inventory == 25 && afterIndividualDeposit.storage == 15);
    afterIndividualDeposit.Complete(25);
    assert(afterIndividualDeposit.inventory == 0 && afterIndividualDeposit.storage == 15);

    std::uint64_t value = 0;
    assert(!NativeReagents::Safety::CheckedAdd(std::numeric_limits<std::uint64_t>::max(), 1, 0, value));
    assert(!NativeReagents::Safety::CheckedAdd(9, 2, 10, value));
    assert(NativeReagents::Safety::CheckedSubtract(10, 10, value) && value == 0);
    assert(!NativeReagents::Safety::CheckedSubtract(9, 10, value));

    assert(NativeReagents::Safety::ClassifyCommitVerification(true, true) == CommitDecision::Accept);
    assert(NativeReagents::Safety::ClassifyCommitVerification(true, false) == CommitDecision::Reverse);
    assert(NativeReagents::Safety::ClassifyCommitVerification(false, false) == CommitDecision::FailStop);

    // Borrow recovery: exact materialization can roll back; any consumed or
    // missing amount is quarantined for review and is never blindly credited.
    assert(NativeReagents::Safety::ClassifyBorrowRecovery(13, 8, 5) == BorrowRecovery::Rollback);
    assert(NativeReagents::Safety::ClassifyBorrowRecovery(12, 8, 5) == BorrowRecovery::Review);
    assert(NativeReagents::Safety::ClassifyBorrowRecovery(5, 0, 5) == BorrowRecovery::Rollback);

    CraftModel mixed{5, 10};
    assert(mixed.Begin(8, true, true));
    assert(mixed.inventory == 8 && mixed.storage == 7 && mixed.borrowed == 3);
    mixed.Complete(8); // consumed loan is never restored
    assert(mixed.inventory == 0 && mixed.storage == 7);

    CraftModel cancelled{2, 10};
    assert(cancelled.Begin(6, true, true) && cancelled.Cancel());
    assert(cancelled.inventory == 2 && cancelled.storage == 10);
    CraftModel full{2, 10};
    assert(!full.Begin(6, false, true) && full.inventory == 2 && full.storage == 10);
    CraftModel failedCommit{2, 10};
    assert(!failedCommit.Begin(6, true, false) && failedCommit.inventory == 2 && failedCommit.storage == 10);
    CraftModel restartExact{1, 10};
    assert(restartExact.Begin(4, true, true) && restartExact.Cancel());
    CraftModel restartAmbiguous{1, 10};
    assert(restartAmbiguous.Begin(4, true, true)); restartAmbiguous.inventory -= 1;
    assert(!restartAmbiguous.Cancel()); // quarantined, never blindly credited

    assert(!NativeReagents::Safety::BankSessionUsable(false, false, true)); // target only / forged open
    assert(!NativeReagents::Safety::BankSessionUsable(true, true, true));   // expired
    assert(!NativeReagents::Safety::BankSessionUsable(true, false, false)); // out of range/non-banker
    assert(NativeReagents::Safety::BankSessionUsable(true, false, true));

    std::cout << "PASS behavioral storage failures, duplicate/concurrent requests, limits, borrow recovery, banker policy\n";
}
