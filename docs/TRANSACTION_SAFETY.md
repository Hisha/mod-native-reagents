# Transaction and authorization guarantees

## Deposit and withdrawal

Each character has at most one storage mutation in progress. The world thread supplies the
first serialization layer; `OperationGuard` explicitly rejects accidental re-entry.

The critical transaction contains:

1. the inventory state produced by `Player::SaveToDB(transaction, false, false)`;
2. absolute reagent-storage balances (not unchecked conditional decrements); and
3. a unique `COMPLETED` operation marker.

The transaction uses `DirectCommitTransaction`, then the marker is synchronously read back.
The verification query uses a sentinel row, so it distinguishes a definitely absent marker
from a query that could not execute. Only a verified marker produces a success response. When
the query proves the marker absent, the live inventory mutation is reversed before control
returns. Because the direct call does not yield the world thread, player actions and logout
cannot interleave with mutation, commit, verification, or reversal.

If the connection is lost during COMMIT and the verification query is also unavailable, the
commit outcome is unknowable: reversing or later saving either in-memory state could choose the
wrong side. The module logs a fatal diagnostic and fail-stops the process immediately. The
database transaction itself contains both inventory and storage, so crash recovery exposes
either the complete old state or the complete new state. This deliberately trades realm
availability for conservation in the rare ambiguous-COMMIT case.

This short blocking operation is a deliberate exception to the normal asynchronous database
preference. `AsyncCommitTransaction` exposes eventual success through a session callback, but
the character could disconnect and be saved independently while an inventory mutation was
unconfirmed. The core does not expose affected-row results for individual statements inside
a transaction. Absolute balances plus the single-writer rule avoid that unsupported case.

The marker also makes recent successful request IDs idempotent across duplicate packets and
reconnects. Records older than 30 days are pruned. A database outage detected before mutation
returns an explicit failure. If a definitely failed deposit cannot restore its in-memory items,
the session is closed so the unchanged persistent inventory is reloaded.

## Single-writer rule

`mod-native-reagents` must be the only process/module modifying these rows for an online
character. Running `mod-bank-reagents` simultaneously or editing balances externally breaks
serialization and is unsupported.

## Banker sessions

A session is created only in the server-side `AllCreatureScript` hook after a legitimate
interaction with a banker. Client `BANKOPEN` merely confirms presentation and cannot create
authority. Every mutation revalidates the same GUID with
`GetNPCIfCanInteractWith(..., UNIT_NPC_FLAG_BANKER)`. Close, logout, timeout, distance, death,
or NPC unavailability invalidates the session. Targeting a banker is insufficient.

## Shutdown and logout

Direct critical transactions finish or fail before the world thread proceeds to logout or
shutdown handling. There is no unconfirmed asynchronous inventory transaction to strand.
Committed database state contains both sides; failed state contains neither side.
