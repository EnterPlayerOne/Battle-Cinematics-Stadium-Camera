# Battle Cinematics v0.7.3 — Stadium Classic

Battle Cinematics v0.7.3 introduces **Stadium Classic**, a new cinematic battle-camera preset based directly on the camera choreography of the original Pokémon Stadium.

This isn't simply a camera inspired by Stadium.

The original Pokémon Stadium camera was captured frame-by-frame from a clean US v1.0 ROM, including its camera position, look target, field of view, timing, cuts and transitions. That choreography was then translated into Battle Cinematics' existing camera system and adapted to work safely inside Gen1Recomp / Dramatic Shape environments.

The result is a recreation of the original Stadium battle-camera language while retaining Battle Cinematics' existing safety systems and compatibility with modern battle presentation mods.

---

## 🎥 New Preset — Stadium Classic

The Preset menu now includes:

- **DW3 Classic**
- **Hero Portrait**
- **Stadium Classic**

Stadium Classic recreates the passive cinematic camera sequence used by Pokémon Stadium.

The captured sequence lasts roughly **32 seconds** before cycling and includes:

- Three-quarter horseshoe shots
- Moving Pokémon portrait shots
- Wide battlefield establishing shots
- Opponent tracking shots
- High circular / aerial camera movement
- Close player and opponent portraits
- Long sweeping battlefield transitions
- Alternating shot variants between cycles

The sequence uses the original Stadium timing and shot ordering rather than randomly selecting cinematic angles.

---

## 🏟️ Recreated from the Original Pokémon Stadium Camera

For this update, the original Pokémon Stadium battle camera was recorded directly at runtime.

The capture included:

- Camera eye position
- Camera target
- FOV
- Shot duration
- Camera movement
- Cuts
- Holds
- Transition timing
- Repeating passive-camera cycle

Rather than copying Stadium's raw N64 world coordinates, those shots were converted into **relative cinematic compositions**.

That means Battle Cinematics can reproduce the same visual language while adapting it to different Pokémon sizes, battlefields and Dramatic Shape environments.

Several parts of Stadium's original camera turned out to closely resemble systems Battle Cinematics already had:

- Stadium portrait sweeps map naturally onto the **Hero Portrait** rig
- Stadium's high circular camera maps onto the existing **DW3 orbit** technology
- Mirrored player/opponent shots use BC's existing subject-target system
- Wide Stadium compositions use BC's battlefield-relative camera system

This allowed the original choreography to be recreated without replacing the safety work already developed for Battle Cinematics.

---

## 🛡️ Stadium Camera Safety

Some original Stadium camera positions are extremely wide and would place the camera outside certain enclosed Gen1Recomp battle arenas.

v0.7.3 adds additional protection for the Stadium camera family.

### Outer Arena Boundary Protection

Wide Stadium shots, sweeps and orbital cameras now respect a safe physical camera envelope.

When an original Stadium-style composition would push the camera too far outside an enclosed arena:

- physical camera travel is limited
- the camera stays inside a safer usable region
- FOV compensates to retain the intended wide composition

Open environments can still use the full large-scale Stadium shot.

This sits alongside Battle Cinematics' existing protections against the rendering dead zones that can temporarily cause 3D models to fall back to sprites.

---

## 👤 Improved Portrait Headroom

Very tall Pokémon could occasionally extend beyond the top of the frame during one of Stadium Classic's closest portrait shots.

That shot now includes a subtle upward target movement during the composition.

The camera itself remains physically stable while its focus rises, providing additional headroom without sacrificing the close portrait or introducing additional dead-zone risk.

This was specifically useful for tall models such as Mewtwo and Charizard.

---

## 🎬 Dynamic Intro Compatibility

Stadium Classic works with Battle Cinematics' existing **Dynamic Intro** system.

The two systems remain independent.

You can therefore use:

- Stadium Classic + Dynamic Intro
- Stadium Classic without Dynamic Intro
- DW3 Classic + Dynamic Intro
- Hero Portrait + Dynamic Intro

Dynamic Intro has not been replaced or tied permanently to Stadium Classic.

The original Pokémon Stadium **battle introduction camera has also now been successfully captured** and is being researched separately.

The long-term intention is to keep intro styles modular so players can mix and match intro cinematography and passive camera presets.

---

## 🔌 Multi-Backend Camera Architecture

Battle Cinematics remains a standalone camera companion.

It does not overwrite the files of the battle-rendering mod it attaches to.

The camera backend layer introduced in previous releases allows Battle Cinematics to attach to compatible BattleCam implementations rather than containing or modifying their renderer code.

Current compatibility work covers the Dramatic Shape family and compatible Battle Art camera implementations.

Further compatibility with newly maintained/repackaged renderer branches is being tested carefully so that alternate backends do not alter Battle Cinematics' established framing.

---

## ⚙️ Preset Configuration

Battle Cinematics keeps its contextual preset configuration system.

Select a preset, then choose:

**Configure Preset**

The available controls depend on the selected camera preset rather than placing every setting into one large menu.

### DW3 Classic

Current DW3 configuration controls:

- **Framing**
  - Standard
  - Near
  - Close

- **Orbit Speed**
  - Slowest
  - Slow
  - Medium
  - Fast

- **Height**
  - Low
  - Standard
  - High

- **Angle**
  - Shallow
  - Standard
  - Strong

- **Reset to Default**

These settings are stored persistently.

### Stadium Classic

Stadium Classic currently prioritises the authentic captured choreography.

Its timing and major compositions are intentionally kept close to the original Pokémon Stadium camera rather than exposing raw camera coordinates.

Additional safe Stadium-specific configuration may be added later.

---

# Controls / Options Refresher

## Preset

Chooses the passive cinematic camera style.

**DW3 Classic**  
Aerial orbit and cinematic over-the-shoulder / Pokémon portrait camera inspired by Digimon World 3.

**Hero Portrait**  
Close cinematic three-quarter Pokémon portrait sweeps.

**Stadium Classic**  
Recreation of Pokémon Stadium's original passive battle-camera choreography.

---

## Configure Preset

Opens the configuration page belonging to the currently selected preset.

This keeps preset-specific controls separate from the main Battle Cinematics menu.

---

## Dynamic Intro

**On / Off**

Plays a cinematic Pokémon introduction when Pokémon enter battle.

Opponent Pokémon receive their introduction first, followed by the player's Pokémon.

The system also works when Pokémon are switched or newly sent into battle.

---

## Intro Speed

Controls the speed of Dynamic Intro cinematography.

- **Slow**
- **Normal**
- **Fast**

**Fast** retains the established original Dynamic Intro timing.

---

## Intro Reset Cam

Controls whether player input is allowed to interrupt/reset the Dynamic Intro camera.

- **Off**
- **On Move/Item**
- **Any Input**

**Off** allows the intro to complete regardless of menu input.

---

## Reset Camera

Controls when passive cinematics return to the normal battle camera.

- **On Move/Item**
- **Any Input**
- **Off**

Default behaviour is **On Move/Item**.

This remains separate from Intro Reset Cam.

---

## Initial Delay

Controls how long Battle Cinematics waits before passive cinematography begins.

- **Immediate**
- **2 Seconds**
- **4 Seconds**
- **Short — 6 Seconds**
- **Standard — 9 Seconds**
- **Long — 12 Seconds**
- **Extra Long — 15 Seconds**

**Standard — 9 Seconds** remains the default.

Immediate removes the intentional waiting period, although Battle Cinematics will still wait until a usable battle camera exists.

---

## Notes

Battle Cinematics controls the **camera only**.

Pokémon models and battle presentation remain the responsibility of the active compatible renderer.

Move-effect mods such as Stadium-style battle-animation projects can operate independently while naturally following Battle Cinematics' moving camera through the shared battle scene.

---

## v0.7.3

- Added **Stadium Classic**
- Recreated Pokémon Stadium passive camera choreography from runtime capture
- Added Stadium wide-shot arena-boundary protection
- Added improved portrait headroom for tall Pokémon
- Retained existing rendering dead-zone protection
- Retained DW3 Classic
- Retained Hero Portrait
- Retained Dynamic Intro
- Retained per-preset configuration
- Retained persistent settings
- Retained multi-backend architecture
- Corrected version reporting so `manifest.json` and Battle Cinematics' exported/logged version remain synchronized

---

Battle Cinematics is still evolving from a camera preset mod into a broader cinematic battle-camera framework.

DW3, Hero Portrait and Stadium can remain independent styles, while systems such as intros and future attack cinematography can be mixed and matched rather than locked to a single presentation mode.
