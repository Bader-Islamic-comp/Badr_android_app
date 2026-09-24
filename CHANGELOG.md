# Changelog

Development increments, newest first. Nothing here is a release: the gates in
[`doc/development-boundary.md`](doc/development-boundary.md) are still open.

Paired server changes are in `comp-server/CHANGELOG.md`; the shared files under
`contracts/` must stay byte-identical between the two repositories.

## Unreleased — 2026-09-22

Three asks: declutter the character page, give the room a background instead of
a black void, and add a customization tab. Fixing the third so it could be seen
on a device turned out to require fixing the bridge handshake, which had never
completed.

### The character page

- **Reduced to the character, the last reply and the composer.** With no reply
  yet the page is only Robert.
- **Removed** the greeting card, the room status chip, the "character room
  stopped" notice, the app header and the adult-operator banner — all from this
  page only.
- **Moved, not dropped:**
  - header and banner → every other page, so the star balance, the parent entry
    and the operator notice stay one tap away. The notice still appears until
    the release gates pass; what changed is where.
  - room status and restart → the parent area, where an adult would act on them.
    How the renderer is doing is developer state, not something to put over a
    character's face.
  - orientation prompt → Learn. Service connection → Quests, Style and the
    parent area.
- **Kept beside the reply:** clearing the conversation, because it deletes the
  server-side conversation as well as the answer, and it stays reachable
  whenever a conversation exists even with no answer showing.
- The "Open character room" button now appears only when the room is *not*
  already the page's background, where it would have opened what is open.
- The stage yields its space below 260 logical pixels of page height, was 240.

### The room's backdrop

- **Added** `unity/tools/make_backdrop.py`, which draws a plain desert horizon
  from the project palette. Decoration only: no text, no symbol, no real place,
  so it needs no content review. One generator writes both copies —
  `unity/Assets/Companion/Room/backdrop_desert.png` for Unity and
  `assets/room/backdrop_desert.png` for Flutter.
- **Added** `unity/Assets/Companion/Runtime/RoomBackdrop.cs`: an unlit quad
  parked behind the character. It sizes itself to the frustum at runtime and
  centre-crops the texture to the screen ("cover", not stretch), because how big
  it must be depends on a viewport the builder cannot know. The quad carries
  both windings — an invisible backdrop from one wrong 180° is a silent failure
  not worth risking for four triangles.
- **Changed** the room camera to clear to an opaque sky colour. It used to clear
  to transparent black, which is what read as a pitch-black void wherever the
  full-bleed page was not painting.
- **Changed** the camera framing: margin 3.4 → 2.6, pitch 10° → 2°, and no
  vertical lift. Pitching down pushes the subject *up* the frame, which is what
  stranded the character above the horizon.
- **Added** the same image, veiled, as the background of every page that is not
  the character page. Robert exists only on Talk; the others read as the same
  place without him, and look identical whether or not a Unity room is running.

### Customization

- **Rewrote** `lib/ui/style_page.dart` as the customization tab: the catalogue
  with prices, swatches, what is earned, what is worn, and how many more stars a
  locked look needs.
- **Added** to the model and controller: `Cosmetic.description` and
  `Cosmetic.cost` (strictly validated — a price the app cannot parse is a
  rejected payload, not a free look), `claimCosmetic`, `equipCosmetic`,
  `equippedCosmeticId`, `canAfford`, and per-look idempotency keys so a retry
  reuses its own key and no look is answered with another's recorded result.
- **Replaced** `DemoApi.equipDefault` with `equipCosmetic(id, key)`, and added
  `claimCosmetic(id, key)`.
- **Replaced** `AvatarBridge.applyServerConfirmedDefault` with
  `applyServerConfirmedCosmetic(id)`, gated on a four-id allowlist that mirrors
  the room's own. A look this build does not ship is refused without touching
  the room.
- **Added** to Unity: the four-look allowlist in `BridgeCommand`, and per-look
  body recolouring in `RobertAvatarPresentation`, re-applied on initialize so a
  rebuilt room does not come back in its default colours. The face screen is
  never tinted — it is approved art, and recolouring it would change what the
  face reads as.
- **The shell decides what the room wears**, from what the service reports as
  worn rather than from the tap that changed it. Earning is not wearing, and the
  worn look comes back by itself after a relaunch or a room rebuild.

A look recolours the character; it is not modelled clothing, because no garment
art exists. The skin system already swaps whole model prefabs, so garments drop
in later as new catalogue entries without changing the bridge contract or how
they are earned. The Style page says this rather than implying otherwise.

### The bridge handshake — it had never completed

The status chip read "Character room · not connected" over a visibly working
room. Two causes, both about waiting for the wrong thing:

- **The handshake deadline was the ordinary 3-second bridge timeout**, but
  initialization waits on the host *starting an engine* — about six seconds on
  the development emulator. `AvatarBridge.surfaceTimeout` is now
  `startupTimeout` (30 s) and covers both the surface probe and the handshake,
  since both wait for an engine rather than for a room that is already
  answering.
- **The receiver announced readiness from `Awake`.** The host releases every
  held command the moment it hears any event from Unity, so the queued
  `avatar.initialize` arrived before `RobertSkinController.Start` had installed
  the visual. `IsAvailable` was false, the session answered `asset_unavailable`,
  and Flutter fell back for good — on every launch.
  `CompanionBridgeReceiver` now announces readiness from `Update`, once the
  presentation reports it can perform. A room whose assets never arrive simply
  never claims readiness, and Flutter's own deadline falls back, which is the
  outcome that was wanted anyway.

What settled it was a lifecycle trace of the Kotlin host — `attach`,
`onPlayerReady`, `onListen`, then Unity's events arriving with a live sink and
lengths matching `asset.failed` rather than an acknowledgement. That tracing was
removed once it had done its job.

### Contracts

- `contracts/openapi-v1.json` **regenerated from the app** rather than
  hand-edited, adding `POST /v1/cosmetics/claim` and the `Cosmetic`
  `description`/`cost` fields. `comp-server/tools/export_contracts.py` writes
  both repositories' copies and a server test fails when the checked-in copy
  drifts from the routes the app serves.
- `contracts/avatar-bridge-v1.schema.json`: `cosmeticId` widened from
  `const: "default"` to the four-id enum.

### Housekeeping

- Untracked `hs_err_pid20448.log`, a JVM crash dump committed by accident, and
  ignored `hs_err_pid*.log`, `replay_pid*.log` and `android/.kotlin/`.
- Removed `sandScrim` and `DevelopmentBanner.overRoom`, dead once the banner
  stopped appearing over the live room.
- `design/room-on-device.png` refreshed and `design/customization-tab.png`
  added, both from the emulator.

### Verification

- Flutter: 29 → **33 tests**, analysis clean. The new ones cover a look being
  earned from the service rather than granted on the device, the balance being
  re-read rather than adjusted, a refused claim spending and wearing nothing, a
  claim naming a different look being a failure rather than an unlock, and — end
  to end through a fake Unity host — the room being told only what the service
  reports as worn.
- Unity: 34 → **36 engine-free checks**, 11 → **12 EditMode tests** (the new one
  covers readiness waiting for a room that can perform).
- Emulator (Android 16, x86_64): the room renders with its backdrop, the
  handshake completes, and the full loop runs — finish the orientation, earn
  Sunset Copper for five stars, wear it, and the character recolours. A fresh
  launch plus connect restores the worn look with no tap.

Still unmeasured: any physical device, ARM64, startup time, memory, frame time,
TalkBack and rotation. A cold first launch after install can still come up
opaque; the host should push a "room attached" event rather than have Flutter
wait on a reply.
