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
| `Deposit(itemId, quantity)` | Requests an exact banker-validated inventory deposit; returns `sent, requestId`. |
| `DepositInventoryItem(bag, slot)` | Requests context-aware deposit of the exact current inventory stack; non-reagents resume ordinary banking after the server response. |
| `HandleInventoryItemRightClick(bag, slot)` | Handles an unmodified right-click only while the stock Reagents view is active. |
| `GetBankView()` | Returns the stock bank presentation's current `bank` or `reagents` view. |
| `IsReagentBankViewActive()` | True while the personal bank is open on the stock Reagents view. |
| `Withdraw(itemId, quantity)` | Requests a banker-validated withdrawal. |
| `GetAutoDeposit()` | Last synchronized per-character preference. |
| `SetAutoDeposit(enabled)` | Requests a banker-validated preference change. |
| `RegisterCallback(callback[, owner])` | Registers for events and returns its owner token. |
| `UnregisterCallback(owner)` | Removes a callback. |
| `RegisterPresentation(tableOrNil)` | Claims or releases presentation ownership. |
| `GetPresentation()` | Returns the current alternative presenter, if any. |
| `RequestSync()` | Starts a fresh paged snapshot. |

`Deposit` accepts positive integer item IDs and quantities in the unsigned 32-bit range. Its
basic client checks only decide whether to send a request. The server independently validates
the item template, reagent eligibility, active quests, eligible physical inventory stacks,
instance state, storage limits, and banker session. A successful response emits
`DEPOSITED(itemId, quantity, requestId)` and starts the ordinary authoritative snapshot refresh.
Failure emits `ERROR(message, "DEPOSIT_ITEM", requestId)` and does not change the snapshot.
Callers can use the returned request ID to correlate either event. They must not optimistically
edit `GetItems()`.

`DepositInventoryItem` accepts only backpack and equipped bag IDs (`0` through `4` on the
stock client). It snapshots the item ID and entire stack count from the specified slot and
sends one `QUICK_DEPOSIT` request. The server checks the validated banker session before it
classifies the item with the same trade-skill reagent set used by normal deposits. Eligible
items enter the existing `Deposit` transaction path. If the server explicitly reports that
the item is not a reagent, the client rechecks that the source slot still contains the same
item and count before calling ordinary `UseContainerItem(bag, slot)`. Any other rejection,
including an invalid banker session, does not perform a regular-bank transfer. A pending slot
is suppressed so one click cannot enqueue duplicate deposit operations.

The stock build-12340 `ContainerFrameItemButtonTemplate` sends modified clicks to
`ContainerFrameItemButton_OnModifiedClick` and unmodified clicks to
`ContainerFrameItemButton_OnClick`. Native Reagents narrowly wraps the latter and delegates
every case except an unmodified right-click while its Reagents view is active. It does not
replace `UseContainerItem`, so unrelated callers and bank-closed inventory behavior remain
unchanged.

Callback events are `AVAILABLE`, `STATUS_CHANGED`, `SYNC_FAILED`, `BANK_OPENED`,
`BANK_CLOSED`, `ITEMS_UPDATED`, `AUTO_DEPOSIT_CHANGED`, `PRESENTATION_CHANGED`, and `ERROR`.
Individual deposits additionally emit `DEPOSITED` as described above.
Each sync generation has a unique ID; pages carry generation, page index, and total-page
metadata. A snapshot is published only after every page is present. Missing pages cause up to
two whole-generation retries, and stale generations cannot replace current data.

An alternative UI such as
UnifiedNativeBags calls `RegisterPresentation(itsPresenter)` while active and
`RegisterPresentation(nil)` when releasing ownership. The stock Reagents view remains the
fallback. Operations expose no database access and responses are always authoritative.

Alternative bag buttons that call `UseContainerItem` directly do not automatically pass
through the stock container-button handler. After their existing modified-click and split-stack
branches, they should replace the direct `UseContainerItem(button.bag, button.slot)` call only
for their own active Reagents view with:

```lua
if not NativeReagents.DepositInventoryItem(button.bag, button.slot) then
    UseContainerItem(button.bag, button.slot)
end
```

UnifiedNativeBags335 currently has an independent `OnClick` handler with a direct
`UseContainerItem` call, so it requires precisely that addon-side integration and does not
inherit the stock behavior automatically. Native Reagents deliberately does not globally wrap
`UseContainerItem` to force third-party buttons through this policy.

## Cursor and drag-and-drop callers

`Deposit` is deliberately cursor-neutral: it neither reads nor clears the cursor. The server
removes the requested quantity from eligible inventory after validation. A caller implementing
bank-style drag and drop should retain the item ID, quantity, and returned request ID, leave the
cursor alone while the operation is pending, and wait for `DEPOSITED` or `ERROR`. On failure it
must leave or restore the cursor through its normal bag interaction; submission alone is never
evidence that the item moved. On success, wait for the resulting bag update and authoritative
`ITEMS_UPDATED` snapshot before repainting balances.

For a complete-stack drag, capture the count from the source bag slot with
`GetContainerItemInfo(bag, slot)` before or while initiating the drag. For a split-stack drag,
retain the quantity passed to the caller's stack-split callback. The build-12340 cursor API does
not expose a dependable split quantity after `SplitContainerItem`; `GetCursorInfo()` identifies
the cursor item but not the selected count. A safe conventional addon therefore owns the split
quantity selection or deposits through an explicit quantity dialog. It must not guess from the
remaining source stack, because intervening bag updates can make that inference stale. Live
client testing is still required for cursor visuals and event ordering.
