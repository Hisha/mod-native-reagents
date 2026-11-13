# WotLK 3.3.5a BankFrame hierarchy

## Source and verification boundary

The repository does not contain Blizzard's complete build-12340 FrameXML or MPQ artwork. The
implementation was checked against the archived 3.3.5 interface extraction at commit
[`d0339b1`](https://github.com/wowgaming/3.3.5-interface-files/tree/d0339b17b0221db76e6acd2dc2915d224a5b62ca),
specifically [`BankFrame.xml`](https://github.com/wowgaming/3.3.5-interface-files/blob/d0339b17b0221db76e6acd2dc2915d224a5b62ca/BankFrame.xml),
[`BankFrame.lua`](https://github.com/wowgaming/3.3.5-interface-files/blob/d0339b17b0221db76e6acd2dc2915d224a5b62ca/BankFrame.lua),
[`ItemButtonTemplate.xml`](https://github.com/wowgaming/3.3.5-interface-files/blob/d0339b17b0221db76e6acd2dc2915d224a5b62ca/ItemButtonTemplate.xml),
and [`CharacterFrameTemplates.xml`](https://github.com/wowgaming/3.3.5-interface-files/blob/d0339b17b0221db76e6acd2dc2915d224a5b62ca/CharacterFrameTemplates.xml).
Its `FrameXML.toc` is byte-for-byte identical to `content/upstream/FrameXML.toc` after CRLF
normalization and declares interface 30300 with `BankFrame.xml` in the same load position.

This establishes the build-12340 XML/Lua hierarchy, but it is not an extraction from the PTR
client itself. A converted copy of the legacy
[`UI-BankFrame` texture](https://github.com/LoonyMoony/wow-ui-textures-pngonly/blob/live/BankFrame/UI-BankFrame.PNG)
was inspected: its 512-by-512 alpha channel has non-transparent bounds `399x424+0+0`, making
the visible bottom edge `512 - 424 = 88` UI units above `BankFrame`'s logical bottom. The XML's
`HitRectInsets bottom="70"` is 18 units lower and describes interaction geometry, not the
visible border. Because the texture was not extracted from the PTR client itself, PTR
screenshots remain required to confirm the rendered edge and final appearance at each UI scale.

## Diagnostic inventory

- `BankFrame` is a top-level, movable, mouse-enabled `Frame` parented to `UIParent`, sized
  425 by 512 and initially anchored at `TOPLEFT (0, -104)`. It declares no explicit strata or
  frame level, so those values come from the client defaults and must be read at runtime.
- Its direct regions are:
  - `BankPortraitTexture`, a named 60-by-60 `ARTWORK` texture at `(7, -6)`.
  - One anonymous 512-by-512 `BORDER` texture at `TOPLEFT`, using
    `Interface\BankFrame\UI-BankFrame`.
  - `BankFrameTitleText`, a named `BORDER` FontString.
  - Anonymous localized `ITEMSLOTTEXT` and `BAGSLOTTEXT` FontStrings.
- The anonymous `UI-BankFrame` texture is monolithic. It contains the outer frame and title
  surround shared by both pages as well as the 28-slot outlines, bag-area rectangles, black
  horizontal bars, and other stock inventory decoration. Those content details are not
  separately named regions and cannot be hidden without also removing the shared border.
- Direct child frames are `BankCloseButton`, `BankFrameItem1` through `BankFrameItem28`,
  `BankFrameBag1` through `BankFrameBag7`, `BankFramePurchaseInfo`, and
  `BankFrameMoneyFrame`.
- The 28 item buttons form a 7-by-4 grid. The first is at `(40, -73)` and the XML pitch is
  49 horizontally and 44 vertically. Each inherits `ItemButtonTemplate`, which owns its icon,
  count, stock text, 64-by-64 `UI-Quickslot2` normal texture, pushed texture, and highlight
  texture. `BankItemButtonGenericTemplate` adds a quest overlay and cooldown child.
- The seven bank-bag buttons begin 32 units below `BankFrameItem22` and use the same horizontal
  pitch. Their inherited item-button regions are supplemented by a cooldown and highlight
  child frame.
- `BankFramePurchaseInfo` is a 380-by-72 child with two FontStrings and child
  `BankFramePurchaseButton` and `BankFrameDetailMoneyFrame`. `BankFrameMoneyFrame` is a
  separate direct child anchored `BOTTOMRIGHT (-30, 103)`.
- `BankFrame_OnShow` and item/bag events refresh icons, locks, cooldowns, and money; they do
  not call `Show()` on the 28 item or seven bag buttons. `UpdateBagSlotStatus` is the stock
  update that can call `BankFramePurchaseInfo:Show()` after a page switch.

## Consequences for the two-page UI

Hiding the stock buttons removes all inherited button artwork, but cannot remove the baked
slot and bag decoration in `UI-BankFrame`. The Reagents page therefore uses an opaque child
content surface above the parent texture, bounded inside the shared portrait/title/border.
The monolithic stock texture remains present so its shared outer artwork is preserved; only
its inventory interior is covered. Bank mode hides that surface and restores the exact prior
visibility of the stock controls and labels before asking Blizzard to refresh their state.

The reagent surface covers the stock inventory decorations with five native-scale crops from
the undecorated 360-by-72 stone floor at texture pixels `(22, 318)` through `(382, 390)` in
`UI-BankFrame`. Four strips use the complete crop; the last uses its first 64 rows. This keeps
the original bank stone artwork at a 1:1 aspect without restoring the sheet's baked item slots,
bag slots, or money bar.

The external tab anchor is `BankFrame BOTTOMLEFT + (11, 92)`: the stock 11-unit horizontal tab
inset, plus the texture's measured 88-unit alpha inset and the reagent surface's four-unit
border inset. This puts the tab frame's top edge on the same bottom-border junction instead of
leaving a gap. Both tabs remain children
of `BankFrame`, and the second tab remains horizontally attached to the first, so scale and page
switches cannot change their relationship. `CharacterFrameTabButtonTemplate` supplies the native
32-unit tab artwork; its selected left texture intentionally extends five units above the button
anchor.

For live inspection, run:

```text
/run NativeReagents.SetBankFrameDiagnostics(true)
/run NativeReagents.DumpBankFrame()
```

The first command enables page-switch visibility and geometry assertions. The second prints
BankFrame regions, stock controls, parentage, anchors, effective scale, frame levels, strata,
and the reagent page objects. Diagnostics are disabled by default and produce no banking spam.
