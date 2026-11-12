#ifndef MOD_NATIVE_REAGENTS_SAFETY_H
#define MOD_NATIVE_REAGENTS_SAFETY_H

#include <cstdint>
#include <limits>

namespace NativeReagents::Safety
{
enum class BorrowRecovery { Rollback, Review };
enum class CommitDecision { Accept, Reverse, FailStop };

inline CommitDecision ClassifyCommitVerification(bool queryExecuted, bool markerPresent)
{
    if (!queryExecuted)
        return CommitDecision::FailStop;
    return markerPresent ? CommitDecision::Accept : CommitDecision::Reverse;
}

inline bool CheckedAdd(std::uint64_t current, std::uint64_t amount,
    std::uint64_t configuredLimit, std::uint64_t& result)
{
    if (amount > std::numeric_limits<std::uint64_t>::max() - current)
        return false;
    result = current + amount;
    return configuredLimit == 0 || result <= configuredLimit;
}

inline bool CheckedSubtract(std::uint64_t current, std::uint64_t amount,
    std::uint64_t& result)
{
    if (amount > current)
        return false;
    result = current - amount;
    return true;
}

inline BorrowRecovery ClassifyBorrowRecovery(std::uint64_t carried,
    std::uint64_t baseline, std::uint64_t borrowed)
{
    std::uint64_t expected = 0;
    if (!CheckedAdd(baseline, borrowed, 0, expected) || carried < expected)
        return BorrowRecovery::Review;
    return BorrowRecovery::Rollback;
}

inline bool BankSessionUsable(bool explicitlyOpened, bool expired, bool bankerInteractable)
{
    return explicitlyOpened && !expired && bankerInteractable;
}
}

#endif
