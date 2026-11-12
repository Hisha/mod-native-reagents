# Transaction and authorization guarantees

## Deposit and withdrawal

Each character has at most one storage mutation in progress. The world thread supplies the
first serialization layer; `OperationGuard` explicitly rejects accidental re-entry.

The critical transaction contains:

1. the inventory state produced by `Player::SaveInventoryAndGoldToDB(transaction)`;
2. absolute reagent-storage balances (not unchecked conditional decrements); and
3. a unique `COMPLETED` operation marker.

The transaction uses `AsyncCommitTransaction` and waits on its worker result, then the marker
is synchronously read back. This is required because AzerothCore registers inventory prepared
statements for asynchronous connections; `DirectCommitTransaction` leases a synchronous
connection where those statements are unavailable. The verification query uses a sentinel
row, so it distinguishes a definitely absent marker from a query that could not execute. Only
a verified marker produces success. When the marker is definitely absent, the live mutation
is reversed. The blocked world thread prevents player actions and logout from interleaving.

If the connection is lost during COMMIT and the verification query is also unavailable, the
commit outcome is unknowable: reversing or later saving either in-memory state could choose the
wrong side. The module logs a fatal diagnostic and fail-stops the process immediately. The
database transaction itself contains both inventory and storage, so crash recovery exposes
either the complete old state or the complete new state. This deliberately trades realm
availability for conservation in the rare ambiguous-COMMIT case.

This short blocking wait is deliberate. A later session callback would allow the character to
disconnect and be saved independently while an inventory mutation was unconfirmed. The core
does not expose affected-row results for individual statements inside a transaction. Absolute
balances plus the single-writer rule avoid that unsupported case.

The marker also makes recent successful request IDs idempotent across duplicate packets and
reconnects. Records older than 30 days are pruned. A database outage detected before mutation
returns an explicit failure. If a definitely failed deposit cannot restore its in-memory items,
the session is closed so the unchanged persistent inventory is reloaded.

## Single-writer rule

`mod-native-reagents` must be the only process/module modifying these rows for an online
character. Running `mod-bank-reagents` simultaneously or editing balances externally breaks
serialization and is unsupported.

## Banker sessions

A pending session is created only when the server packet hook observes `CMSG_BANKER_ACTIVATE`
and independently validates its creature GUID as an interactable banker. This covers the
normal AzerothCore banker opcode path, which does not pass through creature gossip hooks.
Client `BANKOPEN` merely confirms that pending session and cannot create authority. Every
mutation revalidates the same GUID with
`GetNPCIfCanInteractWith(..., UNIT_NPC_FLAG_BANKER)`. Close, logout, timeout, distance, death,
or NPC unavailability invalidates the session. Targeting a banker is insufficient.

## Shutdown and logout

Critical worker transactions finish or fail before the world thread proceeds to logout or
shutdown handling. There is no unconfirmed inventory transaction to strand.
Committed database state contains both sides; failed state contains neither side.
