# Battle Cinematics – Stadium Camera

**A complete cinematic camera layer for Pokémon Gen1Recomp.**

[**Battle Cinematics – Latest Release**](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest)

[![Battle Cinematics showcase](https://img.youtube.com/vi/abv_W16Sstc/hqdefault.jpg)](https://youtu.be/abv_W16Sstc?is=CIt8QNdCDDdVM2Uh)

<img width="214" height="92" alt="Full Stadium Showcase" src="https://github.com/user-attachments/assets/cb0fc799-4d1d-4715-b09d-3e7b51a2e871" />


Battle Cinematics began with a simple idea: bring the cinematic battle language of the Stadium games into Gen1Recomp.

It became something much bigger.

BC is now an adaptable, top-level battle camera system designed to work around the presentation you choose — Stadium models, sprites, alternative battle renderers, different arenas and different camera presets — while preserving readable, cinematic battles across Kanto.

> **Stadium supplied the cinematography. BC supplied the camera system.**

> **Stadium models are not required.**
>
> Stadium 64 refers to the camera language and cinematography. Battle Cinematics is designed to work across supported 3D, sprite and alternative battle presentations without depending on one particular model package.

---

## A complete camera system

Battle Cinematics is not just a collection of authored camera shots.

Every BC camera module operates through the same shared safety and compatibility layer. When an original physical camera movement fits the arena, BC performs it. When the environment cannot support that movement safely, BC preserves the intended composition wherever possible and gracefully substitutes a safer physical route.

The result is a camera system that can be dramatic without assuming every battle takes place in an empty stadium.

**Every BC option produces a good, readable battle everywhere, with BC free to gracefully degrade its physical camera language when the environment cannot support it.**

---

## Three distinct passive camera styles

### Stadium 64

BC's source-faithful translation of the **Pokémon Stadium** battle camera.

Wide establishing movement, sweeping opponent and player compositions, horseshoe-style rotations and the characteristic Stadium battlefield language — adapted to the geometry available in Gen1Recomp rather than blindly replaying unsafe coordinates.

**Stadium 64 is the default BC preset.**

### DW3 Classic

The original Battle Cinematics preset.

A more intimate, dramatic camera language built around orbital movement, shoulder compositions and close environmental framing.

DW3 remains deliberately more interpretive than Stadium 64 and can be extensively configured to taste.

### Hero Portrait

A calmer presentation centred around strong Pokémon portrait compositions.

It remains one of BC's most naturally robust camera styles and is particularly useful for players who want cinematic framing with less physical camera movement.

---

## Pokémon Intro

The BC Hero Intro is its own configurable presentation system.

Pokémon are introduced through a dedicated cinematic portrait before BC hands cleanly into the passive battle camera. The in-game selector is **PKMN INTRO CAM**, with its settings organised under **CONFIGURE INTRO** so additional Intro styles can be added later without redesigning the menu.

Current BC Hero controls include framing, speed, **Hero Tilt**, Intro cancellation and reset-to-default.

Intro cancellation defaults to the logical **Game Boy B button**, respecting the player's Gen1Recomp controller mapping rather than assuming a particular physical controller button.

For players who prefer less movement, **Hero Tilt can be disabled** while retaining the portrait framing and replacing the upward tilt with a subtle reverse-horizontal movement.

And every Intro can still simply be skipped with a press of B.

<img width="320" height="137" alt="BC Hero Pokémon Intro" src="https://github.com/user-attachments/assets/a3a994e3-4163-4033-ab1c-6b9a2a61f716" />

---

## Stadium Attack Camera

Battle Cinematics does not stop when the menu closes.

The optional Stadium Attack Camera provides move-aware cinematic presentation during attacks while remaining synchronised with the actual battle animation window.

Short attacks, longer attacks, self-targeting moves and impact sequences are treated differently rather than forcing every move into one camera template.

BC also accounts for accelerated game speeds, keeping cinematic timing tied to the actual battle rather than assuming the default logic speed.

<img width="400" height="171" alt="Stadium Attack Camera" src="https://github.com/user-attachments/assets/1fc0f71f-43e4-40c7-8ce5-24bfc7fbf28d" />

---

## Faint Camera

Optional faint presentation gives defeated Pokémon a dedicated final composition without requiring a different battle renderer or model package.

Like every other BC camera module, it passes through the same arena and geometry safety systems as the passive cameras.

<img width="400" height="171" alt="Faint Camera" src="https://github.com/user-attachments/assets/a6480ed2-a0ef-4600-a12e-e8006a3efbc9" />

---

# Built for Kanto — not an empty test arena

Kanto contains narrow paths, caves, forests, ledges, trees, rocks, rooftops, building façades and arena boundaries that simply do not exist in the original Stadium battlefields.

BC understands enough about those environments to preserve cinematic movement without treating every foreground object as something that must be avoided.

A tree appearing beautifully in the foreground is allowed.

A camera physically travelling through that tree is not.

A rooftop forming part of a composition is allowed.

A camera occupying the building beneath it is not.

That distinction is fundamental to the way BC works.

## Viridian Forest

Viridian became the proving ground for BC's foliage camera language.

Canopy can remain cinematic foreground while still acting as a physical surface the camera cannot simply descend through. BC can rise to a readable canopy crest, preserve that useful height during the authored shot, and release the correction cleanly at the next camera cut.

The result preserves the forest rather than sterilising it.

<img width="348" height="150" alt="Viridian Forest cinematography" src="https://github.com/user-attachments/assets/8fc32bc6-c572-408e-9e03-e6cbf660035c" />

## Power Plant

Large building geometry presents a very different problem.

BC derives its own private semantic understanding of building **body/façade ↔ roof/top**, allowing large structures to participate in camera occupancy, physical path safety and visibility without changing the underlying battle renderer.

Impossible authored shots can gracefully yield to a safe cinematic substitute instead of repeatedly slamming against the structure. High building façades, low roofs and roof traversal are handled through the same generic system rather than map-specific Power Plant hacks.

<img width="320" height="137" alt="Power Plant structural camera safety" src="https://github.com/user-attachments/assets/8919c000-286e-4a01-bbaa-6a30aecf24ad" />

## Route 12

Small roofs are an equally important test.

BC recognises an authored camera genuinely entering below a local roof and establishes the required viewing height as the camera reaches it, allowing the shot to continue smoothly across the structure.

## Cerulean and open-route cinematography

Safety does not mean flattening the camera.

Open environments remain free to use the full Stadium and DW3 choreography when nothing prevents it. Cerulean in particular is a great example of the camera simply being allowed to breathe.

<img width="278" height="120" alt="Cerulean cinematography" src="https://github.com/user-attachments/assets/4cba44b8-cee8-4463-b412-422590b1ee3f" />

<img width="288" height="124" alt="Celadon cinematography" src="https://github.com/user-attachments/assets/128128b6-321b-4f63-a442-c9705b354dec" />

## Foreground is still part of the cinematography

Routes such as 1, 6 and 8 remain important positive controls for BC.

Ledges, bollards, rocks and other environment pieces are allowed to pass through the foreground when the resulting shot remains readable and physically valid.

BC is designed to **protect cinematography, not remove it**.

<img width="3840" height="1644" alt="Battle Cinematics foreground example 1" src="https://github.com/user-attachments/assets/7d8151ac-de82-45b0-888b-c02efe7838ad" />

<img width="3840" height="1644" alt="Battle Cinematics foreground example 2" src="https://github.com/user-attachments/assets/2bf0c90c-def6-4c0e-a864-3d123efce182" />

<img width="3840" height="1644" alt="Battle Cinematics foreground example 3" src="https://github.com/user-attachments/assets/a9fe22ce-17df-4dcf-910b-5595463ab0c9" />

<img width="3840" height="1644" alt="Battle Cinematics foreground example 4" src="https://github.com/user-attachments/assets/ee6703a9-0676-4fe3-a4a6-569230f9c140" />

---

# Camera safety without camera sameness

BC distinguishes several very different failure classes.

It can prevent invalid physical camera occupancy and travel, respect map boundaries, avoid presentation dead-zones, preserve narrow-route battles, recover from sustained subject obstruction, and substitute impossible authored shots.

But those systems are deliberately shared underneath **different artistic camera languages**.

DW3 still looks like DW3.

Stadium 64 still looks like Stadium.

Hero Portrait still looks like Hero Portrait.

**Safety is infrastructure, not a replacement aesthetic.**

---

# Renderer and presentation independence

Battle Cinematics is designed to sit **above** the active battle presentation.

It is not a Stadium-model dependency and does not require one particular sprite system, model package or battle renderer.

BC has been developed and tested across multiple Gen1Recomp battle configurations, including Stadium-style 3D presentation, alternative battle-art packages and sprite-based setups.

Where a backend provides different scale, geometry or presentation characteristics, BC adapts around them rather than requiring one visual stack to define the camera system.

That remains one of the project's core principles:

> **BC respects what the underlying system provides, then makes the best cinematic use of it.**

### Established presentation configurations

BC has been developed across configurations including:

- **Dramatic Shape Voxel Mod**
- **Dramaless Shape 1.6.4**
- **Pokémon Stadium / 3D model presentations**
- **Dramatic Shape Battle Art** variants
- **Battle Art Voxel Fork**
- Standard 2D and compatible custom battle-art setups

These are presentation systems, **not required dependencies**.

Stadium 64 does not require Stadium models.

Hero Portrait does not require a particular sprite package.

The camera layer remains BC's own.

---

# Configuration

Battle Cinematics is modular. Passive camera style, Pokémon Intro, Attack Camera and Faint Camera can be configured independently.

## Preset

Selects the passive cinematic camera:

- **Stadium 64 — Default**
- **DW3 Classic**
- **Hero Portrait**

## Configure Preset

Opens settings belonging specifically to the selected passive preset.

### DW3 Classic

- **Framing:** Standard / Near / Close
- **Orbit Speed:** Slowest / Slow / Medium / Fast
- **Height:** Low / Standard / High
- **Angle:** Shallow / Standard / Strong
- **Reset to Default**

DW3 settings persist independently.

## PkMn Intro Cam

- **BC Hero**
- **Off**

Controls cinematic Pokémon introductions at the beginning of battle and when new Pokémon enter.

## Configure Intro

Opens settings belonging to the selected Intro style.

**BC Hero** currently provides:

- **Framing:** Extra Wide / Wide / Standard / Close
- **Speed:** Slow / Normal / Fast / Faster
- **Hero Tilt:** On / Off
- **Cancel:** B Button / Any Input / On Move/Item / Off
- **Reset to Default**

**B Button** is the default cancellation mode and uses Gen1Recomp's logical Game Boy B binding, including remapped controllers.

Intro settings persist independently so future Intro styles can coexist without erasing one another's configuration.

## Attack Camera

- **Stadium — Default**
- **Off**

The Attack Camera is independent of the passive preset.

## Faint Camera

- **On — Default**
- **Off**

## Initial Delay

Controls how long BC waits before passive cinematography begins:

- Immediate
- **2 Seconds — Default**
- 4 Seconds
- 6 Seconds
- 9 Seconds
- 12 Seconds
- 15 Seconds

## Legacy Options

Historical escape-hatch behaviour remains available without being presented as part of the recommended main setup.

### Reset Camera

- **Off — Default**
- Confirmed Action
- Any Input

Reset Camera relinquishes the active passive preset back to the ordinary battle camera according to the selected trigger.

**Any Input** remains an explicit legacy opt-in because normal navigation can otherwise cancel the passive camera.

## Diagnostics

Diagnostic logging remains available for development and troubleshooting.

---

# How BC handles constrained environments

A camera does not need to reproduce its original physical journey to remain faithful to the intended shot.

On a clear battlefield, BC can use the complete authored movement.

On a restricted route, it may shorten that journey.

Near a boundary, it may preserve the composition optically rather than parking the camera against the edge.

When a physical shot is impossible, it may substitute a readable cinematic viewpoint while retaining the authored scene timing.

Temporary camera recovery belongs to the authored shot that required it and releases cleanly at the next camera cut rather than becoming an imaginary physical journey into the following scene.

The goal is always the same:

**preserve the cinematic composition without breaking the battle presentation.**

---

# Mix and match

Battle Cinematics is intended to occupy the **camera layer** of a modular Gen1Recomp setup.

For example:

**Battle renderer / environment**  
+ **Pokémon models or sprites of your choice**  
+ **vanilla or compatible battle-animation presentation**  
+ **Battle Cinematics camera system**

None of those visual choices force you to use Stadium 64.

Likewise, Stadium 64 does not require Stadium models.

Use the presentation you prefer and let BC direct the camera around it.

---

# Download

Download the newest version from:

[**Battle Cinematics – Latest Release**](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest)

Install Battle Cinematics using the normal Gen1Recomp mod-installation workflow.

For version-specific changes, compatibility notes and release showcases, see the individual release pages.

---

# Current compatibility note

> [!IMPORTANT]
> ### StadiumBattleFX 2.x / Dramaless 2.x
>
> StadiumBattleFX 2.x **can currently be enabled alongside BC, but it is not recommended if you want BC to look as authored and as shown in the showcase footage above**.
>
> Current SBFX 2.x presentation/camera behaviour can materially alter BC framing and FOV even while BC remains active, so BC scenes can play differently from their intended compositions.
>
> If you specifically want the established **Pokémon Stadium model presentation with BC framing**, the currently recommended legacy backend is **Dramaless Shape 1.6.4**. Dramaless 2.x reorganises the Stadium presentation/model stack and is not yet part of BC's validated framing configuration.
>
> This is a compatibility status, not a dependency change. **BC remains independent of any single renderer or presentation mod.**

BC's development and releases will not be held hostage to the development pace, expanding scope or changing architecture of parallel mods.

BC will continue doing what it has always done: adapt deliberately as the ecosystem evolves, preserve its own camera language and compatibility contract, and integrate new presentation systems once they can coexist without compromising the experience BC is designed to provide.

When those interfaces settle, **BC will adjust — as BC always does.**

---

# What's next

Battle Cinematics 1.0 is a milestone, not the end of the camera system.

The current architecture opens the door to:

- stronger camera-authority handling when multiple presentation mods attempt to influence the same camera;
- presentation-aware Pokémon Intro framing / Actor Presentation Bounds;
- additional Stadium move-camera research and grammar;
- optional Stadium-plus scene mixing with DW3 and Hero camera language;
- item/self-action presentation and further phase-ownership cleanup;
- additional Intro styles and camera presets;
- continued compatibility work as Gen1Recomp's renderer and battle-presentation ecosystem evolves.

New camera systems are developed on top of the last confirmed-good behaviour, with established backend compatibility and safety fallbacks treated as part of BC's contract.

---

# Credits

**EnterPlayerOne** — Battle Cinematics design and development.

**Darkatek7** — identified and traced the accelerated `input.Step / Game:logicSpeed()` timing issue and supplied the original patch that led to BC's game-speed compatibility implementation.

And thanks to everyone who has tested Battle Cinematics across different routes, renderers, presets and increasingly unreasonable camera situations.

A great deal of BC exists because somebody found the arena where the camera finally said no.

---

# Battle Cinematics

**Three camera languages. One shared cinematic system. Across Kanto.**

---

## License

MIT
