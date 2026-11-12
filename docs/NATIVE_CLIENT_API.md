# Native client API

`NativeReagents` is loaded from protected FrameXML before normal play and is independent of
the default bank presentation.

| Function | Result |
| --- | --- |
| `IsAvailable()` | Server capability handshake completed. |
| `IsReady()` | A complete current reagent snapshot has been atomically published. |
| `GetStatus()` | `unavailable`, `loading`, `ready`, or `failed`. |
| `GetLastError()` | Last server rejection body, or `nil` after the next confirmed operation/bank open. |
| `IsBankOpen()` | The stock personal bank session is open. |
| `GetItems()` | Read-only-by-convention snapshot table keyed by item ID. Do not mutate it. |
| `GetQuantity(itemId)` | Synchronized stored quantity or `0`. |
| `DepositAll()` | Requests a banker-validated deposit; returns whether a request was sent. |
| `Withdraw(itemId, quantity)` | Requests a banker-validated withdrawal. |
| `GetAutoDeposit()` | Last synchronized per-character preference. |
| `SetAutoDeposit(enabled)` | Requests a banker-validated preference change. |
| `RegisterCallback(callback[, owner])` | Registers for events and returns its owner token. |
| `UnregisterCallback(owner)` | Removes a callback. |
| `RegisterPresentation(tableOrNil)` | Claims or releases presentation ownership. |
| `GetPresentation()` | Returns the current alternative presenter, if any. |
| `RequestSync()` | Starts a fresh paged snapshot. |

Callback events are `AVAILABLE`, `STATUS_CHANGED`, `SYNC_FAILED`, `BANK_OPENED`,
`BANK_CLOSED`, `ITEMS_UPDATED`, `AUTO_DEPOSIT_CHANGED`, `PRESENTATION_CHANGED`, and `ERROR`.
Each sync generation has a unique ID; pages carry generation, page index, and total-page
metadata. A snapshot is published only after every page is present. Missing pages cause up to
two whole-generation retries, and stale generations cannot replace current data.

An alternative UI such as
UnifiedNativeBags calls `RegisterPresentation(itsPresenter)` while active and
`RegisterPresentation(nil)` when releasing ownership. The stock Reagents view remains the
fallback. Operations expose no database access and responses are always authoritative.
