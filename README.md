
# 🎥 Battle Cinematics – Dynamic 3D Battle Camera

### A top-level cinematic battle director for Pokémon Gen1Recomp

**Stadium 64 • 4-Way Sprite View • Pokémon Intro • Attack & Faint Cameras • Secondary View • Live Voxel Arenas • Gen 1 + Gen 2**

[![Latest Release](https://img.shields.io/github/v/release/EnterPlayerOne/Battle-Cinematics-Stadium-Camera?label=Latest%20Release)](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest)

<!-- PRIME SHOWCASE
Final target: media/Battle_Cinematics_Prime_Showcase.mp4
Optional short looping preview: media/Battle_Cinematics_Prime_Showcase.gif
The reel should show, in order: 4-Way sprites -> Crystal -> Gen5 animated -> genuine Stadium 3D -> Stadium/Intro/Attack/Faint -> Secondary View -> Live Voxel Arena.
-->




https://github.com/user-attachments/assets/c924c8c4-9fda-44be-b7e7-76e48cd88577



**Battle Cinematics (BC)** is the camera/director layer for battles. It brings the cinematic language of Pokémon Stadium into Recomp, then adapts that language around the presentation you choose: classic sprites, animated sprites, voxel worlds, genuine Stadium models and supported live battle hosts.

BC does **not** replace those renderers, models, animations or assets. It directs the camera around them, adapts to their presentation boundaries and can compose supported providers together without taking ownership of their content.

> **Stadium supplied the cinematography. BC supplied the camera system.**
>
> **BC directs. Providers present. Renderers render. Assets remain theirs.**

Stadium models are optional. Battle Cinematics is designed to make the presentation you already use look intentional from a moving cinematic camera.

**Battle Cinematics v1.2.7 has been tested with Gen1Recomp / Recomp through v0.2.45.**

v1.2.7 adds validated **Battle Art Voxel Gen2 2.0.8** compatibility while preserving the v1.2.6 camera, APB, performance, safety and provider-ownership contracts.

[**Download the latest release**](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest)

> [!TIP]
> **New in v1.2.5:** Secondary View now offers genuine **LIVE VIEW**, expressive **LIVING PORTRAIT** and the original **DYNAMIC (DW3)** mode, with independently selectable PiP render resolution from **160x90 to 1280x720**. Gen 2 LIVE VIEW is validated with Stadium2 Overworld Models 0.2.81, Voxel Ultimate 1.0.7 and Stadium2 Importer 0.12.1.
> 
> **New in v1.2.6:** provider presentation bounds are cached for each committed attack instead of being rediscovered every frame. PotatoVoxel + Stadium2 Importer also avoids rendering a second hidden battle scene after the hosted live arena succeeds. The established camera choreography, APB framing, safety and fallback behavior remain intact.
> 
> **New in v1.2.7:** Battle Art Voxel Gen2 2.0.8 is now a validated Gen 2 battle host. BC attaches its passive camera suite, 4-Way Sprite View, Pokémon Intro/send-in and faint lifecycle to Battle Art Gen2 while preserving provider-owned rendering. With Stadium2 Importer 0.12.1 MODELS ON, Secondary View uses the live Stadium actor over the Battle Art voxel world with independent BC framing; with MODELS OFF, Battle Art Gen2 receives the established fixed-FRONT vanilla/animated Secondary View treatment.

---

## What Battle Cinematics changes during a battle

BC is modular. Use the complete presentation or only the camera phases you want.

| Battle moment | Battle Cinematics |
|---|---|
| **Idle / command menu** | Stadium 64, DW3 Classic, Hero Portrait or External host camera |
| **Flat sprites** | Camera-aware **4-Way Sprite View** where supported |
| **Pokémon send-in** | BC Hero FULL / COMPACT cinematic introductions |
| **Moves** | Stadium-inspired, move-aware Attack Camera |
| **Faint** | Dedicated final composition for the defeated Pokémon |
| **Secondary view** | Optional independent PiP camera with **LIVE VIEW**, **LIVING PORTRAIT** or **DYNAMIC (DW3)** presentation |
| **PiP quality** | Independent internal render resolution from **160x90 through 1280x720** |
| **Stadium2 Importer arena** | Optional **LIVE VOXEL ARENA** override where a compatible live-world provider is actually available |
| **Manual camera** | BC-owned on Gen 1; compatible provider-owned control on Gen 2 |

The core rule underneath all of it is:

> **Every BC option produces a good, readable battle everywhere, with BC free to gracefully degrade its physical camera language when the environment cannot support it.**

---

# Compatibility

Battle Cinematics is a director, not a battle renderer. A supported presentation host still owns the world, sprites, models and animation it provides.

The tables below describe the **current tested state**, not every historical version that has ever worked. As compatibility is refined, these tables should be replaced rather than accumulated.

## Gen 1 / RBY

| Presentation / host | Main BC Cameras | 4-Way Sprite View | Secondary View | Stadium2 Importer / arena notes |
|---|:---:|:---:|:---:|---|
| **Dramaless Shape 2.0.4** | ✅ | ✅ | ✅ | Vanilla / Crystal / Importer validated. **LIVE VOXEL ARENA** supported. Provider-native bounded manual fallback retained for the Dramaless + Importer combination. v1.2.6 performance verified. |
| **Battle Art Voxel Fork 1.10.0** | ✅ | ✅ | ✅ | Vanilla, animated / Gen 5 and Stadium2 Importer presentation validated. Battle Art retains its own Importer environment path; BC keeps narrow projection recovery for strong camera compositions. v1.2.6 Attack Camera verified. |
| **Dramatic Shape 1.9.0** | ✅ | ✅ | ✅ | Vanilla / Crystal / Importer validated. **LIVE VOXEL ARENA** supported. |
| **Voxel Ascendant 2.0.2 — MAP** | ✅ | ✅ | ✅ | Vanilla / Crystal / Importer MAP validated. **LIVE VOXEL ARENA** supported. ARENA / DISCS are not currently claimed. |
| **PotatoVoxel 1.9.6 — Gen 1 MAP / 2D-3D A** | ✅ | ✅ | ✅ | Gen 1 validated with Stadium2 Importer **LIVE VOXEL ARENA**. v1.2.6 main/PiP APB framing, passive paths and one-world performance verified. |
| **Voxel Ultimate 1.0.7 — Gen 1** | ✅ | ✅ | ✅ | Integrated host path validated. Avoid stacking duplicate systems that Voxel Ultimate already integrates. |
| **Stadium2 Importer 0.12.1 — Gen 1** | ✅ | 3D yield | ✅ | Genuine Stadium presentation retained. **LIVE VIEW** supported. Can use supported **BATTLE ARENA OVERRIDE** providers below. |
| **Crystal Animated Sprites 2.0.2** | ✅ | ✅ | ✅ | Animated sprite presentation supported on established compatible host paths. Fixed animated FRONT Secondary View remains independent from the main 4-Way view. |
| **Compatible vanilla / ROM sprite presentation** | ✅ | ✅ | ✅ where host-supported | BC uses the host's actual sprite presentation rather than replacing the artwork. |
| **StadiumBattleFX 2.1.8.1** | ✅* | 3D yield | ✅ | **Gen1 Stadium model presentation supported.** Proven with **Dramaless Shape 2.0.3** when SBFX `BATTLE ARENA` is set to the registered **VOXEL ARENA** provider. Other voxel-provider combinations are provider/version-specific; see notes below. |
### Gen 1 LIVE VOXEL ARENA providers for Stadium 2 Importer

- **Dramaless Shape 2.0.3**
- **Dramatic Shape 1.9.0**
- **Voxel Ascendant 2.0.2 — MAP**
- **PotatoVoxel 1.9.6 — MAP / 2D-3D A**

**Battle Art Voxel Fork 1.9.9** already supplies its Importer environment through its own established integration rather than BC's arena-override bridge.

>### StadiumBattleFX + voxel providers

>StadiumBattleFX can provide a separate Gen1 Stadium-model presentation while compatible voxel backends continue to provide the battle environment. This is provider-specific and should not be assumed to work identically across every backend.

| Voxel provider | SBFX Stadium model state v2.1.8.1|
|---|---|
| **Dramaless Shape 2.0.3** | ✅ **Validated.** Select its registered voxel arena in SBFX `BATTLE ARENA`. Stadium models + voxel world + BC cameras + Secondary View work correctly. |
| **Dramatic Shape 1.9.0** | ⚠️ **Partial / not currently recommended.** Its voxel arena is recognised, but current testing can lose the battle UI |
## Gen 2 / GSC

| Presentation / host | Main BC Cameras | 4-Way Sprite View | Secondary View | Current state |
|---|:---:|:---:|:---:|---|
| **Battle Art Voxel Gen2 2.0.9 / `BATTLE_ART_VOXEL_GEN2`** | ✅ | ✅ | ✅ | **Validated in v1.2.7.** Passive presets, Pokémon Intro/send-ins, APB framing and Faint lifecycle are integrated. Importer 0.12.1 MODELS ON provides live Stadium Secondary View over the Battle Art voxel world; MODELS OFF uses the fixed-FRONT vanilla/animated PiP path. |
| **Gen2-3D-Sprites / `STADIUM2_OVERWORLD_MODELS` 0.2.81** | ✅ | ✅ on 2D world-card path | ⚠️ **Partial / audit** | Current recommended standalone Gen 2 Stadium basis. Complete continuous LIVE VIEW tracking remains under renewed runtime audit. Provider owns Gen 2 right-stick behavior. |
| **Voxel Ultimate 1.0.7 — Gen 2** | ⚠️ **Re-audit** | ✅ on supported flat-card path | ⚠️ **Re-audit** | Previously established integrated Gen 2 host. Current 3D attachment and complete continuous LIVE VIEW behavior remain under renewed runtime audit. |
| **Stadium2 Importer 0.12.1 — direct Gen 2** | ⚠️ **Re-audit** | 3D yield | ⚠️ **Re-audit** | **Hosted with Battle Art Gen2 2.0.8 is validated above.** Direct Gen 2 attachment outside that validated composition remains under audit. |
| **PotatoVoxel 1.9.6 + Stadium2 Importer 0.12.1** | ⚠️ **Re-audit** | 3D yield | ⚠️ **Re-audit** | Potato standalone Gen 2 3D is not claimed. Any working combined presentation remains Importer-owned. |
| **Crystal Animated Sprites 2.0.2** | ✅ | ✅ on compatible world-card paths | ✅ | Crystal artwork/animation remains provider-owned; BC supplies camera-relative orientation and secondary composition where supported. |


> [!NOTE]
> **Battle Art Voxel Gen2 + Stadium2 Importer:** use Battle Art `ARENA FILL = OFF` and `STADIUM CIRCLE = OFF` for the validated hosted composition. Importer `MODELS` must be in the desired state when BC initializes; switching between MODELS ON and OFF requires a reload before BC can attach the corresponding Gen2 Secondary View backend.
>
> Highly animated Stadium actors can show a brief initial Secondary View settling period while the stable idle presentation envelope is established. Battle Art Gen2 foreground geometry can also occasionally obscure part of Pokémon Intro choreography; these are pinned presentation-polish items rather than lifecycle failures.
>
> `STADIUM2_OVERWORLD_MODELS` **0.2.81** remains the recommended BC compatibility basis. The tested `0.4.33` build has severe independent performance problems on the Android validation device before BC battle rendering begins, so v1.2.7 does not claim it.

---

# Using Battle Cinematics

The sections below follow the in-game Battle Cinematics menu. New permanent features should be added to this sequence; version-specific history belongs in GitHub Releases instead of being appended to the README.

---

## 1. Camera Authority

`CAMERA AUTHORITY` is the top-level BC ownership control.

- **BC PRIORITY — default:** BC owns the camera phases you have enabled.
- **COOPERATIVE:** allows compatible presentation systems more room to participate where supported.
- **BC DISABLED:** leaves BC installed but stops BC camera ownership.

Ownership is **phase-scoped**, not battle-wide. A host can own the idle camera through External while BC still owns Pokémon Intro, Attack or Faint.

---

## 2. 4-Way Sprite View


![4-Way Sprite View](media/Battle_Cinematics_4-Way_Sprite_View_V2.gif)


A separate vanilla / ROM-sprite example shows the same camera-relative presentation on the flat-card path:


![Vanilla 4-Way Sprite View](media/Battle_Cinematics_Vanilla_4-Way_Sprite_View_V2.gif)

**4-WAY SPRITE VIEW** makes supported flat-card Pokémon behave like world-facing actors instead of cards permanently locked to one battle-screen direction.

BC can independently resolve each battler's normal **FRONT / BACK** representation and then orient it **LEFT / RIGHT** toward the fight as the final camera moves.

This creates a practical four-way presentation without requiring four separate sprite assets.

- **DYNAMIC — default:** full camera-aware four-way behavior. BC selects FRONT/BACK per battler and applies LEFT/RIGHT facing.
- **TURN ONLY:** keep the host/provider's FRONT/BACK choice and apply only horizontal turning.
- **HOST DEFAULT:** zero-touch host presentation.

Genuine 3D Pokémon models automatically yield from this system.

### Animated sprite presentations

![Gen 5 Animated](media/Battle_Cinematics_Gen5_Animated_Showcase_V2b.gif)

![Crystal Animated](media/Battle_Cinematics_Crystal_Animated_Showcase_V2b.gif)

BC does not replace animated sprite providers. The provider keeps the artwork, animation, scale and lifecycle; BC supplies the camera-relative presentation layer where that host exposes a compatible path.

---

## 3. Idle Preset

The idle preset controls BC's passive camera while you are navigating the battle and no higher-priority cinematic phase is active.

### Stadium 64 — default

![Stadium full camera cycle](media/stadium-mewtwo-full-cycle.gif)

BC's source-faithful translation of the original **Pokémon Stadium** passive battle-camera language: wide establishing shots, player/opponent portraits, sweeping battlefield movement and rising horseshoe-style rotations.

The Stadium choreography was captured from the original game and translated into relative compositions rather than blindly replaying N64 world coordinates. That lets BC preserve the visual language while adapting it to Recomp's actual battle environment.

### DW3 Classic

The original Battle Cinematics camera language. DW3 is more intimate and interpretive, with orbital movement, shoulder compositions and close environmental framing.

### Hero Portrait

A calmer passive style that keeps the Pokémon visually dominant with less physical camera travel.

### External

`EXTERNAL` yields the passive / idle camera to the active compatible host.

> **EXTERNAL CAMERA — HOST OWNED**  
> **BC PHASE MODULES — STILL INDEPENDENT**

Pokémon Intro, Attack Camera, Faint Camera and Secondary View can remain independently enabled.

### Configure Preset

Stadium 64, DW3 Classic and Hero Portrait each expose contextual tuning without cluttering the main menu:

- Framing: Extra Wide / Wide / Standard / Near / Close
- Orbit Speed: Slowest / Slow / Medium / Fast
- Height: Low / Standard / High
- Angle: Shallow / Standard / Strong

---

## 4. Idle View

`IDLE VIEW` is a renderer-neutral optical modifier for ordinary BC passive/menu cameras.

- Standard — default
- Wide
- Extra Wide
- Ultra Wide

It changes the viewing width without rewriting the authored physical camera path.

---

## 5. Initial Delay

Controls how long BC waits before beginning passive cinematography after a usable battle camera is established.

- Immediate
- **2 Seconds — default**
- 4 Seconds
- 6 Seconds
- 9 Seconds
- 12 Seconds
- 15 Seconds

Intro / Attack / Faint remain their own battle-aware phases; this delay is for passive cinematography.

---

## 6. Pokémon Intro — BC Hero

<!-- SHOWCASE: Stadium2Importer Stadium.mp4 opening / strongest existing BC Hero clips -->

![Pokémon Intro — Stadium2 Importer / Gold](media/Battle_Cinematics_Pokemon_Intro_Stadium2_Importer_Gold.gif)


BC Hero gives newly presented Pokémon a dedicated cinematic send-in before handing cleanly into the passive battle camera.

The lifecycle understands the battle rather than replaying one intro blindly:

- opening Pokémon → **FULL**;
- enemy replacement → **FULL**;
- forced player replacement after faint → **FULL**;
- later voluntary switch against an established opponent → **COMPACT**;
- battle progression / move commitment immediately wins if the game moves on.

### Configure Intro Cam

- Framing: Extra Wide / Wide / Near / Close
- Speed: Slow / Normal / Fast / Faster
- Hero Tilt: Off / On
- Cancel: B Button / Any Input / On Move/Item / Off
- Reset to Default

Current intended baseline is **WIDE** framing with **Hero Tilt OFF**.

---

## 7. Stadium Attack Camera

![Attack and Faint example](media/articuno-attack-faint.gif)

The optional **ATTACK CAMERA → STADIUM** follows the actual move presentation rather than forcing every attack through one generic animation.

BC can reason about semantic move roles such as attacker declaration, travel/tracking, recipient/impact, SELF actions, FIELD-style actions and different animation windows. Camera timing follows the real battle presentation and remains compatible with accelerated game speed.

The Attack Camera is independent of the selected idle preset.

---

## 8. Faint Camera

`FAINT CAMERA → ON` gives the defeated Pokémon a dedicated final composition.

It remains phase-scoped and renderer-independent. On provider-owned Gen 2 presentations, BC follows the real visible faint lifecycle rather than artificially keeping an actor alive after the host removes it.

---


## 9. Secondary View PiP

![Continuous Secondary View](media/Battle_Cinematics_Continuous_Secondary_View_Showcase_INLINE.gif)

Secondary View is an optional **independent second camera**. It is not a crop of the main view.

`SECOND VIEW PIP` defaults **OFF** so updating BC never silently adds another rendered view.

When enabled, `CONFIG PIP` provides:

### PIP MODE

- **LIVE VIEW — default:** persistent alternate view of the same active battle presentation. Where the host exposes a safe live presentation seam, BC redraws that state through its second camera rather than running a separate imitation battle timeline.
- **LIVING PORTRAIT:** persistent independently animated character portrait. This intentionally keeps its own expressive presentation rather than mirroring the main battle frame-for-frame.
- **DYNAMIC (DW3):** the original authored Secondary View behavior, appearing only during its intended cinematic battle phases.

Persistent **LIVE VIEW** and **LIVING PORTRAIT** begin as soon as the opening player Pokémon Intro / send-out presentation has genuinely cleared. They do **not** wait for the main passive camera's `INITIAL DELAY`.

LIVE VIEW follows the battle state actually exposed by the active provider: idle presentation, move-specific attack animation, fainting, vacancy and replacement where supported.

> **One battle state → two cameras → two views.**

BC does not invent provider presentation that does not exist. If a host does not implement a particular reaction or animation state, Secondary View does not fabricate one.

### PiP Render Resolution

`PIP RENDER RESOLUTION` controls the internal quality of the Secondary View independently from its physical on-screen size.

- 160x90
- 240x135
- **320x180 — default**
- 480x270
- 640x360
- 960x540
- 1280x720

Higher resolutions are intentionally available for stronger phones, handhelds and PCs.

`PIP SIZE` remains purely the physical compositor/window size.

>320x180 is the recommended default. Higher resolutions increase private-render workload and may have a noticeable performance cost on heavier backends or densely populated scenes.

### PiP View

- Size: Standard / **Small — default**
- Framing: **Normal — default** / Close
- Side: **Left (DW3) — default** / Right
- Place: Mid Center / Top Right / **Mid Right — default** / Top Left / Mid Left / Custom

↖️ Custom placement can be adjusted directly on supported mouse/touch frontends.

Different hosts expose different safe private-render seams. BC adapts to those provider boundaries while preserving the same public Secondary View behavior: the provider owns its world, artwork, models and animation state; BC owns the alternate camera and render target.

### Upgrade behavior

v1.2.5 makes **LIVE VIEW** the new default.

Existing installations are migrated to LIVE VIEW **once** when upgrading to the new PIP MODE system. After that migration, the user's own choice is respected normally: LIVE VIEW, LIVING PORTRAIT or DYNAMIC (DW3) all persist across restart.

### Performance rule

> **PiP size on screen must not dictate the internal world-render workload.**

Secondary View uses an independent render-resolution setting and backend-appropriate private rendering. Some providers require bounded or aspect-preserving targets and conservative draw scheduling; BC keeps those implementation details provider-specific rather than forcing every renderer through one identical private-scene path.


---

## 10. Battle Arena Override


![Battle Arena Override — Live Voxel Arena](media/Battle_Cinematics_Live_Voxel_Arena_Override_Showcase_INLINE.gif)


`BATTLE ARENA OVERRIDE` controls **environment ownership** for compatible Stadium2 Importer compositions where an independent live voxel/world provider is actually available.

- **LIVE VOXEL ARENA — default:** use a compatible live voxel/world provider as the battle environment while Stadium2 Importer keeps its genuine Stadium actors, animation and HUD.
- **HOST DEFAULT:** leave the environment entirely to Stadium2 Importer.

This setting changes the **arena only**. It does not enable Stadium models, manufacture a missing 3D provider path or turn a 2D battle into a 3D battle.

If no compatible live voxel battle world exists for the active generation/provider stack, **LIVE VOXEL ARENA** safely has nothing to substitute and the working host presentation remains in control.

The intended division of responsibility is simple:

> **Voxel provider → world / arena**  
> **Stadium2 Importer → Stadium models / animation / HUD**  
> **Battle Cinematics → camera direction / Secondary View**

Supported BC-managed LIVE VOXEL ARENA providers are listed in the compatibility tables above.

For example, **PotatoVoxel 1.9.6 + Stadium2 Importer 0.12.1** is a valid Gen 2 combination, but the battle remains in Stadium2 Importer's circular arena because Potato does not currently expose an attached Gen 2 voxel battle world for BC to substitute.

---

## 11. Legacy Options

`RESET CAMERA` retains older input-driven escape-hatch behavior:

- **Off — default**
- Confirmed Action
- Any Input

Most users should leave this Off. BC's current battle-aware phase lifecycle normally handles camera transitions without needing generic input cancellation.

---

## 12. Diagnostics / Reset

Diagnostics are intended for compatibility testing and support, not normal play. Keep them **OFF** unless you are deliberately gathering evidence for a problem.

Reset Defaults restores the current BC defaults for the relevant configuration.

---

# Presentation-aware framing — APB

![Pidgeotto APB origin](media/pidgeotto-apb-origin.gif)

**Actor Presentation Bounds (APB)** is BC's renderer-neutral language for understanding the Pokémon currently being presented.

Instead of assuming every actor occupies the same volume, compatible adapters can describe facts such as visible top/bottom, visual centre, presented height, elevation and breadth. Each authored camera shot then decides how much of that information it should consume.

> **APB understands the whole presented actor; the authored shot decides how much of that actor it wants to show.**

That distinction matters: Onix can be tall and grounded, Pidgeotto can be genuinely elevated, Articuno can be broad, Snorlax can be bulky, and a classic fixed-card sprite may already fit perfectly without needing dramatic correction.

![Snorlax breadth](media/snorlax-breadth.gif)

![Mew presentation-aware framing](media/mew-presentation-aware.gif)

No Pokémon species, type or model-name camera hardcodes are required for those decisions.

---

# Camera safety without camera sameness

Recomp battle environments are not empty Stadium arenas. Routes, caves, forests and towns contain boundaries, walls, trees, ledges, rocks, façades, roofs and renderer-specific dead zones.

All BC camera modules pass through shared protection systems that can:

- keep the camera inside valid map space;
- prevent physical traversal through known structural geometry;
- protect narrow routes and 3D → 2D presentation boundaries;
- recover from sustained subject obstruction;
- reason about building body / façade / roof structure where reliable evidence exists;
- substitute an impossible physical route while preserving the intended cinematic composition.

Safety is infrastructure, **not** a replacement aesthetic.

A tree crossing the foreground can be good cinematography. A camera physically travelling through that tree is not.

![Celadon structural safety](media/Celadon1.0.gif)

![Power Plant structural safety](media/Plant%20(1).gif)

![Open-route Stadium camera](media/Cerulean%201.0.0_1%20(1)%20(1)%20(3).gif)

BC deliberately preserves useful foreground grazing and environmental depth wherever the subject remains readable.

---

# Manual camera ownership

## Gen 1 / RBY

BC owns the established manual-camera contract:

> **grab current BC shot → free orbit / look → release → soft return to authored BC camera**

4-Way Sprite View follows the final camera, so supported flat-card actors remain spatially coherent while the user moves around the battle.

The exact **Dramaless + Stadium2 Importer** composition intentionally uses the provider's bounded native manual behavior rather than unrestricted BC free orbit, because that host combination has its own safe camera envelope.

## Gen 2 / Gold, Silver, Crystal

The active compatible provider owns the right stick. BC does not run the separate Gen 1 manual subsystem on top of it.

![Randy first-person provider control](media/randy-first-provider-control.gif)

![Randy third-person provider control](randy-third-provider-control.gif)

Voxel Ultimate and `STADIUM2_OVERWORLD_MODELS` keep their provider-native manual-camera semantics while BC retains its configured camera phases.

---

# Quick setup guidance

### I want BC cinematography with sprites

Use a supported live battle/world host and leave **4-WAY SPRITE VIEW → DYNAMIC**. Stadium models are not required.

### I want genuine Stadium models

On Gen 1, use **Stadium2 Importer 0.12.0**. BC can direct Stadium 64 / DW3 / Hero, Pokémon Intro, Attack, Faint and Secondary View over the provider presentation.

On current Gen 2, use a validated working host such as **`STADIUM2_OVERWORLD_MODELS` 0.2.81** or **Voxel Ultimate 1.0.7**.

### I want Stadium models in the actual voxel world

On a supported Gen 1 composition, set:

`BATTLE ARENA OVERRIDE → LIVE VOXEL ARENA`

The voxel provider supplies the environment, Stadium2 Importer supplies the actors/HUD, and BC directs the camera.

### I want the host's idle camera but BC's battle cinematics

Set:

`IDLE PRESET → EXTERNAL`

Then leave Pokémon Intro / Attack / Faint enabled as desired.

> **Using StadiumBattleFX models?**  
> **Dramaless Shape 2.0.3** is the currently validated voxel-world companion. In SBFX, set `BATTLE ARENA` to the registered **VOXEL ARENA** entry for Dramaless, then let Battle Cinematics handle camera direction.

---

# Troubleshooting

### My Pokémon looks camera-locked or faces the wrong way

First check **4-WAY SPRITE VIEW → DYNAMIC** on a supported flat-card path. Older advice to force particular back/front settings is not the general BC model anymore; validated Dynamic adapters should normally own the camera-relative choice themselves.

If you deliberately choose HOST DEFAULT, the host's own fixed presentation may naturally look less spatially convincing during large camera movements.

### A provider says it supports 3D, but BC only sees 2D

Test the provider **without BC first**. BC can adapt a working presentation path; it does not manufacture a provider's missing 3D battle scene.

### Gen 2 right stick behaves differently from Gen 1

That is intentional. Gen 1 uses BC's manual camera. Current supported Gen 2 hosts retain provider-owned manual input.

### A camera shot changes in a constrained environment

That can be intentional safety behavior. BC preserves the authored composition where possible and may change the physical route when the environment cannot support it safely.

### Voxel Ultimate behaves strangely with several overlapping presentation mods

Treat Voxel Ultimate as an integrated host. Avoid stacking standalone equivalents of systems it already includes unless the combination is known-good; duplicate provider ownership can create conflicts outside BC's control.

---

# Installation

1. Download the latest `BATTLE_CINEMATICS-x.x.x.zip` from [Releases](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest).
2. Install it through the normal Gen1Recomp mod workflow.
3. Enable the compatible battle/world/model presentation you want to use.
4. Configure Battle Cinematics from its structured in-game mod options.

For **what changed in a specific version**, see that version's GitHub Release notes. The README describes the current product and current compatibility state.

---

# Interoperability and credits

**EnterPlayerOne** — Battle Cinematics design and development.

Battle Cinematics remains the camera/director layer. The following renderers, providers, sprite systems, effects systems and model projects remain the work of their respective authors:

- **Dramatic Shape**
- **Dramaless Shape** — artyrambles
- **Battle Art Voxel Fork** — absol89
- **PotatoVoxel** — ShaneMcGovernIE
- **Voxel Ascendant** — Roxas2712
- **Voxel Ultimate**
- **Crystal Animated Sprites with Shiny Visuals** — distilledorion-sketch
- **Stadium2 Importer** — Deftones565
- **Gen2-3D-Sprites / `STADIUM2_OVERWORLD_MODELS`** — randyadr
- **StadiumBattleFX** — Root Beer Ronin / anxiousintrovert

**Darkatek7** — scoped credit for identifying the accelerated `input.Step / Game:logicSpeed()` timing path and supplying the original patch that led to BC's game-speed compatibility implementation.

**StadiumBattleFX / Root Beer Ronin** is also acknowledged as a cousin Stadium-focused project whose parallel development helped spur Battle Cinematics' continued Stadium interoperability work. This is an inspiration / ecosystem acknowledgement, not Battle Cinematics code authorship.

**ZEROstig** — thanks for continued YouTube exposure, encouragement and showcasing Battle Cinematics to the wider Gen1Recomp community.

Thanks to everyone who has tested BC across different routes, generations, renderers, presets and increasingly unreasonable camera situations.

> A great deal of Battle Cinematics exists because somebody found the arena where the camera finally said no.

---

# Permissions / license

Battle Cinematics v1.2.1+ is distributed under the **Battle Cinematics Source-Available License 1.0**.

The source remains available for inspection, learning, private/personal modification and contributions back to the official project. Public redistribution, repackaging, rebranding, successor forks, substantial incorporation into another distributed project, sublicensing or commercial redistribution require prior written permission.

Historical copies released under MIT remain governed by the license that accompanied those copies.

See [`LICENSE`](LICENSE) for the complete terms.

---

**Passives. 4-Way Sprites. Intros. Attacks. Faints. Secondary View. Live Arenas. One adaptable camera system. Gen 1 + Gen 2.**
