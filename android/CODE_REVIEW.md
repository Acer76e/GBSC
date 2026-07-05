# CherryPick — Code Review Findings

Status: **open** — none of these are fixed yet. Ranked most-impactful first.
Each item lists the location, the concrete failure, and the intended fix. When
you fix one, change its checkbox to `[x]` and note the commit.

The overarching goal is **stability**: correct offer math, a card that always
shows when it should, no silent data loss, and no lingering stale UI. Make each
fix minimal and self-contained. Do not refactor unrelated code. After each fix,
re-read the touched function end-to-end to confirm you didn't break a caller.

---

## Correctness

### [x] 1. Fares over $999 misparse as $1.xx — fixed in d0163f3
**File:** `app/src/main/java/com/gbsc/cherry/capture/OfferParser.kt:32`
**Problem:** `moneyRegex = \$\s*(\d{1,4})[.,](\d{2})` treats a thousands comma as
the decimal separator. `$1,050.25` matches as `$1,05` → `$1.05`. A lucrative
long-haul/airport offer shows a $1.05 fare and grades red.
**Fix:** Match an optional thousands group and a real decimal point. Accept
`$1,050.25`, `$1050.25`, and `$20.08`. Strip thousands separators before
`toDouble`. Keep the existing `+bonus` and `/hr` rate-suffix exclusions working.
Add unit-style reasoning: `$1,050.25`→1050.25, `$20.08`→20.08, `$7.08`→7.08.

### [x] 2. New offer identical to a just-dismissed one shows no card — fixed in 2589e2a
**File:** `app/src/main/java/com/gbsc/cherry/overlay/OverlayController.kt:70`
**Problem:** `dismissedSignature` is set by the auto-hide timer and the ✕ button
but is only cleared inside `show()` when a *different* signature arrives. After
the engine resets (`resetState()` / MISS_LIMIT), a genuinely new offer with the
same `fare|miles|minutes` is suppressed — notification and voice fire, but the
card never appears.
**Fix:** Clear `dismissedSignature` (and `scheduledForSignature`) in `hide()`
and add a public `clearDismissed()` the engine calls from `resetState()` and on
each brand-new offer (when `signature != currentSignature`). The intra-offer
auto-hide (same offer re-parsed by the 1s poll after it hid) must still stay
hidden — only a NEW offer signature should re-enable showing.

### [ ] 3. Offer notification (and card) never clear on normal expiry
**File:** `app/src/main/java/com/gbsc/cherry/capture/OfferEngine.kt:184`
**Problem:** `cancel(NOTIF_OFFER)` and `overlay?.hide()` live only inside the
`missCount >= MISS_LIMIT` branch of `processText`. When an offer expires and
Uber returns to the dashboard (>500 chars, no accept/match), `processText` is
never called, so the stale notification lingers in the shade and — with
`cardDurationSecs = 0` — the card never disappears.
**Fix:** Drive expiry from the service, not the miss counter. When the active
window is Uber but the current frame is not offer-shaped (accessibility text
present, `looksLikeOffer` false, and OCR likewise finds no offer), tell the
engine the offer is gone so it hides the overlay and cancels the notification.
A small `OfferEngine.onNoOffer()` called from the service's non-offer Uber
branch is enough. Keep a short debounce (e.g. 2 consecutive non-offer frames)
so a single dropped frame mid-offer doesn't flap the card.

### [ ] 4. Settings/history can silently reset to defaults (unordered writes)
**File:** `app/src/main/java/com/gbsc/cherry/data/Repo.kt:67` (and `:91`)
**Problem:** `updateSettings`/`persistHistory` each `ioScope.launch { file.writeText(...) }`
on multi-threaded `Dispatchers.IO`. Slider drags fire dozens/sec. Writes can
complete out of order (stale snapshot wins) or interleave into corrupt JSON,
which `loadSettings` swallows and resets ALL settings to defaults.
**Fix:** Serialize writes on a single-thread dispatcher
(`Dispatchers.IO.limitedParallelism(1)`) or a `Mutex`, and write atomically
(write to `settings.json.tmp`, then `renameTo`). Debounce slider persistence:
update the in-memory `_settings` immediately on every tick but persist on a
short conflated delay (or on `onValueChangeFinished`). Apply the same
single-writer + atomic-rename to `persistHistory`.

### [ ] 5. Active Uber window is read twice per frame
**File:** `app/src/main/java/com/gbsc/cherry/accessibility/UberAccessibilityService.kt:132`
**Problem:** `seenRoots.none { it === activeRoot }` uses reference equality
against freshly obtained `AccessibilityNodeInfo` instances, which are never
`===`, so the active window's text is appended to `sb` twice and `nodeCount`
doubles.
**Fix:** Dedupe by window id (`w.id == activeRoot`'s window id) or by tracking
whether the active window's package/root was already covered by the `windows`
loop with a boolean, not a node-identity list. Ensure each on-screen Uber
window contributes its text exactly once.

### [ ] 6. Offer identity is an exact string → OCR jitter re-fires; value collisions drop offers
**File:** `app/src/main/java/com/gbsc/cherry/capture/OfferEngine.kt:204`
**Problem:** `signature = "%.2f|%.1f|%.0f"(fare, miles, minutes)` compared with
`==`. A one-cent OCR wobble ($20.08 vs $20.03) makes a NEW signature → duplicate
history row, re-notify, TTS-over-itself, and the enrichment cache is bypassed
(rating/address flicker returns). Conversely two different trips with identical
fare/miles/minutes collide and the second is silently dropped.
**Fix:** Treat two offers as the same when fare is within a small tolerance
(e.g. ±$0.25) AND miles within ±0.3 AND minutes within ±1, within a short time
window (e.g. 90s). Prefer a structured current-offer record over a formatted
string. This subsumes the enrichment cache. Keep it conservative so distinct
back-to-back offers aren't merged — bias toward "same offer" only when all
three are close AND recent.

### [ ] 7. Non-US decimal locales corrupt Profit inputs (lower priority)
**File:** `app/src/main/java/com/gbsc/cherry/ui/screens/ProfitScreen.kt:169`
**Problem:** The input filter keeps only digits and `.`, dropping the comma
separator that Decimal keyboards emit in comma-decimal locales, so "312,50"
becomes "31250" (100× error).
**Fix:** Accept both `.` and `,` as the decimal separator and normalize to `.`
before `toDouble` (allow a single separator). US behavior unchanged.

---

## Security / setup

### [ ] 8. Committed debug keystore signs the installed APK
**File:** `app/build.gradle.kts:35`, `app/debug.keystore`
**Problem:** The repo-committed `debug.keystore` (password `android`) is the real
key signing the CI `assembleDebug` APK you sideload. Anyone with repo access can
build a trojaned in-place update that inherits the granted accessibility +
screen-capture permissions.
**Fix (personal-use pragmatic):** Keep in-place updates working but document the
risk and keep the repo private. If you want to harden: move signing creds to CI
secrets / a gradle property and stop committing the keystore, accepting that a
one-time reinstall is needed when the key changes. Do **not** silently switch
keys without noting the reinstall. Lowest-effort acceptable action: add a
comment in `build.gradle.kts` and this doc stating the tradeoff; no code change
required if the repo stays private.

### [ ] 9. allowBackup=true exposes unencrypted location history
**File:** `app/src/main/AndroidManifest.xml:9`
**Problem:** `history.json` (up to 500 pickup/dropoff addresses + timestamps)
lives unencrypted in `filesDir` and is backed up to the cloud / extractable via
`adb backup` on older Androids.
**Fix:** Set `android:allowBackup="false"` (simplest), or add
`android:dataExtractionRules` / `android:fullBackupContent` that exclude
`history.json` and `settings.json`.

---

## Efficiency

### [ ] 10. Full node-tree walk on every event before the throttle; typeAllMask
**File:** `app/src/main/java/com/gbsc/cherry/accessibility/UberAccessibilityService.kt:114`
and `app/src/main/res/xml/accessibility_service_config.xml:3`
**Problem:** `captureAndProcess` walks every window's full node tree (one binder
IPC per node) on every event, then checks the 500ms throttle afterward. The
config subscribes to `typeAllMask`, so Uber's animated map keeps the service
busy all day → battery drain + jank.
**Fix:** Check the time throttle at the top of `captureAndProcess` (for
non-forced, non-bypass calls) before any traversal. Narrow
`accessibilityEventTypes` to `typeWindowStateChanged|typeWindowContentChanged`.
Gate the non-Uber `countNodes` diagnostic traversal behind `debugMode`.

---

## Cleanup (not bugs — do only if quick and low-risk)

- [ ] Dead code: `Grading.parseColor`, `Grading.colorHex`, `OverlayController.destroy`,
  `Theme.AvgYellow` are unreferenced.
- [ ] The grade palette (`#22C55E`/`#F5C518`/`#EF4444`) and brand orange are
  duplicated across `Grading.kt`, `Theme.kt`, `colors.xml`, and hardcoded ints —
  consolidate to one source.
- [ ] Money formatting (`%.2f`) is re-implemented in `OfferEngine`, `HistoryScreen`,
  `ProfitScreen`, `FiltersScreen` — one shared formatter.
- [ ] Nine diagnostic `StateFlow`s in `OfferEngine` run on every poll in the
  release build with no off switch — gate behind `debugMode`.

---

## Ground rules for fixing

1. One logical fix per commit; clear message; push to the working branch.
2. Do not change offer-parsing behavior for the cases that already work
   ($7.08, $20.08, Match vs Accept, the `/hr` rate-suffix exclusion).
3. The CI workflow builds `assembleDebug`; there are no automated tests, so
   reason through each regex/logic change with concrete example inputs in the
   commit message.
4. Keep the accessibility-only (no screen-share) architecture intact.
5. Preserve in-place installability (don't change the signing key without
   flagging that a reinstall is required).
