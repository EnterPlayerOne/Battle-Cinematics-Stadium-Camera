# Battle Cinematics – Dynamic 3D Battle Camera v1.2.1

Battle Cinematics is a top-level battle-camera/director layer for Gen1Recomp. It adapts its cinematography to the active battle presentation while leaving artwork, models, animation and world rendering with the provider that owns them.


## v1.2.1 — Permissions & licensing

v1.2.1 is **functionally identical to the validated v1.2.0 release**. No camera, renderer, provider, menu, Sprite Facing, Secondary View, Gen 1 or Gen 2 behavior has been changed.

Starting with v1.2.1, Battle Cinematics is distributed under the **Battle Cinematics Source-Available License 1.0** included in `LICENSE`. Source remains public for inspection, learning, private/personal modification and contributions back to the official project. Public redistribution, repackaging, rebranding, sublicensing, or distribution of derivative/forked Battle Cinematics projects requires prior written permission from EnterPlayerOne.

Historical releases that were already distributed under the MIT License remain available under the terms that accompanied those releases. The new license governs v1.2.1 and later Battle Cinematics releases and future project code to the extent EnterPlayerOne holds the applicable rights.

## v1.2.0 — Secondary View

v1.2.0 adds **SECOND VIEW PIP**: an optional live second battle camera rendered inside a movable picture-in-picture window while the main Battle Cinematics camera continues normally.

The Secondary View is provider-aware rather than a duplicated screenshot. Supported 2D hosts receive an independent fixed-FRONT portrait treatment; genuine Stadium/3D hosts receive their real player model through BC's shared 3D compositor and Actor Presentation Bounds.

### Default Secondary View setup

- **SECOND VIEW PIP = OFF**
- **PIP PLACE = MID RIGHT**
- **PIP SIZE = SMALL**
- **PIP SIDE = LEFT (DW3)**
- **PIP FRAMING = NORMAL**

Enable `SECOND VIEW PIP`, then use `CONFIG PIP` to change placement, size, side and framing.

### PiP placement

Choose a named `PIP PLACE` preset or **press/hold and drag the visible PiP** to save a custom position. On mobile, if a virtual stick/button overlaps the PiP, choose a clear named position first and then drag it.

### PiP framing

- **NORMAL** — established cinematic portrait framing.
- **CLOSE** — a tighter version of the same compositor.
- **LEFT (DW3) / RIGHT** — controls the Secondary View's authored side independently of the main camera.

Flat sprites remain fixed FRONT inside the PiP. Genuine 3D actors use BC's three-quarter Secondary View language with shared Actor Presentation Bounds rather than sprite-specific rules.

## Secondary View compatibility

| Presentation / project | v1.2.0 Secondary View status |
|---|---|
| **Dramaless Shape** | Established reference Secondary View path retained. Vanilla/Crystal and genuine Stadium presentation remain provider-owned. |
| **Battle Art Voxel Fork 1.9.6** | Validated flat vanilla/Crystal Secondary View plus genuine Stadium2 Importer 3D actor presentation. Main Battle Art stage remains isolated from the private PiP renderer. |
| **Voxel Ascendant 2.0.1** | **MAP validated.** Vanilla is accepted with its provider-native scale peculiarity; Crystal fixed animated FRONT is supported; Stadium2 Importer genuine 3D presentation is supported. Ascendant ARENA is not claimed for this release. |
| **PotatoVoxel 1.7.11 reference source** | Validated vanilla + Crystal A/B presentation and genuine Stadium2 Importer 3D Secondary View. Crystal fixed-FRONT ownership is isolated from Dynamic main-camera sprite selection. |
| **Dramatic Shape 1.6.1 reference source** | Validated vanilla + Crystal A/B, genuine 3D presentation and Stadium2 Importer Secondary View. Android PiP drag uses the legacy Dramatic touch bridge; the private PiP render is kept off fixed-step to avoid gameplay stalls. |
| **Stadium2 Importer 0.10.13** | Gen 1 + Gold/Silver genuine Stadium-model Secondary View supported through provider-owned player actors and BC's established 3D compositor. |
| **Gen2-3D-Sprites / `STADIUM2_OVERWORLD_MODELS` 0.2.35** | Gold/Silver genuine 3D and provider-hosted 2D vanilla/Crystal Secondary View retained; Randy right-stick/First/Third Person ownership remains provider-owned. |
| **Crystal Animated Sprites 2.0.2** | Fixed animated FRONT PiP supported across validated flat-card hosts. Extreme silhouette framing can still vary slightly by renderer; no species hardcodes are used. |

The versions above are the exact sources used for the v1.2.0 validation work where available. Newer forks/releases may share the same provider contract, but are not automatically claimed as byte-for-byte tested.

## Secondary View lifecycle

The PiP is passive/idle presentation. It suppresses itself around BC-owned or UI-sensitive battle phases such as Intro/Send-In, Attack, Faint and real party/item/submenu states, then resumes cleanly when passive battle presentation returns.

BC deliberately keeps provider ownership separated:

> **BC directs. Providers present. Renderers render. Assets remain theirs.**

## Sprite Facing

v1.2.0 retains v1.1.1's cross-generation Sprite Facing system.

- **DYNAMIC — default:** camera-relative FRONT/BACK + LEFT/RIGHT for supported 2D-card presentations.
- **TURN ONLY:** preserve the provider-selected FRONT/BACK representation while BC turns actors toward one another.
- **HOST DEFAULT:** literal zero-touch host sprite presentation.

Genuine Stadium / 3D model presentations are detected and hard-yield from Sprite Facing.

### Crystal ownership safety

Supported Crystal integrations borrow camera-selected FRONT/BACK presentation only at the host card-capture seam and restore provider-owned sprite state immediately. The live Crystal FRONT animation used by Secondary View is not allowed to be contaminated by a transient Dynamic BACK card.

## Gen 2

Gold and Silver compatibility from v1.1.1 remains intact.

### Stadium2 Importer

Genuine Stadium2 presentation remains provider-owned. BC controls only its configured camera phases and the optional Secondary View camera/compositor.

### Gen2-3D-Sprites / Randy

Randy genuine-3D presentation, First/Third Person and right-stick behavior remain provider-owned. When Randy presents native Gold/Silver 2D battle art in its live 3D world, BC retains the established Dynamic/Turn and Secondary View paths for vanilla and Crystal artwork.

## Existing Battle Cinematics system

v1.2.0 retains the established camera suite underneath Secondary View:

- Stadium 64, DW3 Classic, Hero Portrait and External presets;
- BC Hero Intro / Send-In lifecycle;
- move-aware Stadium Attack Camera;
- Faint Camera;
- Actor Presentation Bounds;
- Camera Authority;
- Gen 1 manual camera;
- provider-owned Gen 2 manual camera;
- Dynamic Sprite Facing;
- structural wall/facade/roof, floor, boundary, narrow-route and 3D→2D safety.

## Manual camera ownership

### RBY / Gen 1

BC retains the established manual-camera contract:

> **grab current BC shot → free orbit / look → release → soft return to authored BC camera**

DYNAMIC follows the final manual camera and updates supported 2D actors as the user moves around the battle.

### Gold + Silver

Provider-owned right-stick behavior remains provider-owned. Randy and Stadium2 Importer keep their native manual-camera semantics rather than receiving the separate RBY free-camera subsystem.

## External

`PRESET → EXTERNAL` yields passive/idle camera ownership and Sprite Facing to the host. BC Hero, Attack Camera and Faint Camera remain independently configurable. Secondary View remains an independent optional passive presentation when its active provider path is supported.

## Settings / migration

- **SECOND VIEW PIP defaults OFF.** Existing users are not forced into a second renderer/camera.
- **SPRITE FACING = DYNAMIC** remains the default.
- `CAMERA AUTHORITY` remains the single top-level enable/ownership control.
- The legacy ENABLED state remains folded into Camera Authority once; previously disabled users remain disabled.
- Existing v1.0.6 Battle Intro WIDE / Hero Tilt OFF one-time migration markers remain intact.
- Structured **Configure Preset**, **Battle Intro** and **Config PiP** screens remain contextual rather than flattening provider-specific controls.

## Compatibility philosophy

> **Every BC option produces a good, readable battle everywhere, with BC free to gracefully degrade its physical camera language when the environment cannot support it.**

> **BC respects what the underlying system provides, then makes the best cinematic use of it.**


## Permissions / forking

Battle Cinematics is **source-available, not freely redistributable** from v1.2.1 onward.

You may inspect and study the source, run the official release, make private/personal modifications, and submit proposed changes to the official Battle Cinematics project. You may also link to the official repository or official release downloads.

Without prior written permission from EnterPlayerOne, you may **not** publicly redistribute Battle Cinematics or modified copies, publish a rebranded or successor fork, bundle substantial Battle Cinematics code into another distributed mod/project, sublicense it, sell it, or present a derivative project as an independent continuation of Battle Cinematics.

Third-party renderers, providers, assets and projects referenced by Battle Cinematics remain under their respective authors' own licenses and copyrights. Battle Cinematics grants no rights over those works.

See `LICENSE` for the complete terms.

## Credits / interoperability

Battle Cinematics remains the camera/director layer. Dramatic Shape, PotatoVoxel, Voxel Ascendant, Battle Art Voxel Fork, Dramaless Shape, Crystal Animated Sprites with Shiny Visuals, StadiumBattleFX, Stadium2 Importer and Gen2-3D-Sprites / `STADIUM2_OVERWORLD_MODELS` remain the work of their respective authors.

Darkatek7 retains scoped credit for identifying the accelerated `input.Step / Game:logicSpeed()` timing path and supplying the original patch that led to BC's game-speed compatibility implementation.

**StadiumBattleFX / Root Beer Ronin** is also acknowledged as a cousin Stadium-focused project whose parallel development helped spur Battle Cinematics' continued Stadium interoperability work. This acknowledgement is for inspiration/motivation and ecosystem collaboration, not code authorship or ownership of Battle Cinematics.
