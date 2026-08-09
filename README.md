# 🎥 Battle Cinematics - Stadium Camera

A standalone, modular battle-camera system for **Pokémon Gen1Recomp**.

Battle Cinematics adds cinematic passive cameras, battle introductions, attack cinematography and faint presentation while remaining independent of the battle sprites, models and renderer you choose to use.

> ⚠️ **Stadium models are NOT required!**
>
> Battle Cinematics works with **supported 2D sprites, custom battle-art packages, voxel/model renderers and Pokémon Stadium model setups**.
>
> The Stadium features refer to the **camera style and cinematography**. They are designed to mix naturally with the wider Stadium-themed mod ecosystem, but Pokémon Stadium models are not a requirement.
>
> **From the beginning, Battle Cinematics has been designed as an adaptable top-level camera system — fitting around the active battle presentation rather than being tied to one renderer, model set, preset or visual style.**

---
## 🎥 See Battle Cinematics in Action

### Stadium Classic

Pokémon Stadium camera choreography, reverse-engineered from runtime capture and translated through **Battle Cinematics' own subject-relative Gen1Recomp camera system**.

[![Battle Cinematics - Stadium Classic](https://img.youtube.com/vi/Lc37dOoFhBs/maxresdefault.jpg)](https://youtu.be/Lc37dOoFhBs)

### Dynamic Battle Direction

Attack-aware framing, self-move cinematography, faint reactions and passive camera systems working together as a **modular battle-direction layer**, independently of the chosen battle-art setup.

[![Battle Cinematics - Dynamic Battle Direction](https://img.youtube.com/vi/ch1kvbhVqeM/maxresdefault.jpg)](https://youtu.be/ch1kvbhVqeM)

### 2D / 2D-3D Compatibility

Battle Cinematics is not limited to Stadium-model battles. The same camera systems also operate across supported **2D and 2D-3D battle presentations**, with backend-aware framing and safety fallbacks.

[![Battle Cinematics - 2D / 2D-3D Compatibility](https://img.youtube.com/vi/aXX6RjYRUzc/hqdefault.jpg)](https://youtu.be/aXX6RjYRUzc)

---

## ✨ What Battle Cinematics Does

Battle Cinematics separates battle presentation into modular camera systems.

Choose your passive camera style, then independently decide whether you want a battle intro, attack cinematography and faint-camera behaviour.

Current systems include:

- **DW3 Classic** — orbiting and cinematic battle framing inspired by Digimon World 3
- **Hero Portrait** — close three-quarter Pokémon portrait cinematography
- **Stadium Classic** — Pokémon Stadium's passive battle-camera choreography, reverse-engineered from runtime capture and translated onto Battle Cinematics' own subject-relative Gen1Recomp camera rig
- **BC Hero Battle Intro** — cinematic introductions when Pokémon enter battle
- **Stadium Attack Camera** — move-aware attack cinematography synchronized to the real move-animation window
- **Faint Camera** — keeps focus on a defeated Pokémon through its faint presentation

These systems are intentionally independent and can be mixed and matched.

---

# 🎬 Camera Presets

## DW3 Classic

Battle cinematography inspired by **Digimon World 3**, combining:

- Aerial orbiting
- Pokémon portrait framing
- Over-the-shoulder compositions
- Enemy/player focus changes
- Cinematic transitions

DW3 Classic has its own configurable preset menu.

## Hero Portrait

A closer cinematic preset built around moving three-quarter Pokémon portrait shots.

Designed for players who want character-focused battle framing without the longer Stadium or DW3 camera sequences.

## Stadium Classic

Recreates the passive battle-camera language of the original **Pokémon Stadium**.

The original Stadium camera was captured at runtime, including:

- Camera position
- Camera target
- FOV
- Timing
- Cuts
- Holds
- Sweeps and orbital movement
- Shot ordering

Rather than copying N64 world coordinates, the captured choreography was **reverse-translated into Battle Cinematics' existing subject-relative camera system**.

Stadium supplied the original cinematography; Battle Cinematics' own camera rig reproduces that language dynamically around Gen1Recomp Pokémon, arenas and supported rendering backends.

---

# ⚔️ Stadium Attack Camera

**Attack Camera — Stadium / Off**

The Stadium Attack Camera follows the **real move-animation window**, allowing the same system to work with both vanilla Gen1Recomp move animations and compatible animation mods such as Stadium Battle FX.

It is move-aware:

- **Targeted attacks** — attacker → battlefield/travel → target/impact
- **Self-targeting moves** — remain focused on the Pokémon using the move
- **Field-style effects** — use broader neutral framing
- Player and opponent attacks mirror automatically

Because this system is independent from the passive preset, Stadium attack cinematography can be used with:

- DW3 Classic
- Hero Portrait
- Stadium Classic

Or simply set **Attack Camera — Off** if another mod should control attack cinematography.

---

# 💥 Faint Camera

**Faint Camera — On / Off**

Default: **On**

When a Pokémon faints, Battle Cinematics can retain focus on the defeated Pokémon instead of immediately returning the camera to the surviving battler.

Where supported, BC follows the actual model faint state. Other presentation setups use a safe timed fallback.

---

# ⚙️ Options

## Preset

Selects the passive cinematic camera:

- **DW3 Classic**
- **Hero Portrait**
- **Stadium Classic**

## Configure Preset

Opens settings belonging specifically to the selected preset.

### DW3 Classic

- **Framing:** Standard / Near / Close
- **Orbit Speed:** Slowest / Slow / Medium / Fast
- **Height:** Low / Standard / High
- **Angle:** Shallow / Standard / Strong
- **Reset to Default**

Preset settings are persistent.

## Battle Intro

- **BC Hero**
- **Off**

Controls cinematic Pokémon introductions at the beginning of battle and when new Pokémon enter.

## Intro Speed

- Slow
- Normal
- Fast

## Intro Reset Camera

Controls whether input can interrupt the Battle Intro:

- Off
- On Move/Item
- Any Input

## Attack Camera

- **Stadium**
- **Off**

Default: **Stadium**

## Faint Camera

- **On**
- **Off**

Default: **On**

## Initial Delay

Controls how long Battle Cinematics waits before passive cinematography begins:

- Immediate
- 2 Seconds
- **4 Seconds — Default**
- 6 Seconds
- 9 Seconds
- 12 Seconds
- 15 Seconds

## Reset Camera

Controls when passive cinematography returns to the standard battle camera:

- **On Move/Item — Default**
- Any Input
- Off

---

# ✅ Broad Renderer / Battle-Art Compatibility

Battle Cinematics is designed as an **independent camera layer** and adapts its framing, geometry and fallback behaviour to the supported battle environment currently active.

Tested compatibility includes:

- [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) — including v1.8.0
- [Dramaless Shape](https://github.com/artyrambles/DRAMALESS_SHAPE) — including altered camera rigging used by the ST fork
- [Pokémon Stadium Overworld Models](https://github.com/randyadr/3D-Pokemon-Sprites)
- [Stadium Battle FX](https://github.com/anxiousintrovert/StadiumBattleFX)
- **Dramatic Shape Battle Art** variants
- **Battle Art Voxel Fork**
- Standard 2D and compatible custom battle-art setups

These are **supported presentation systems, not required dependencies**.

Battle Cinematics does not require another project to implement BC-specific camera behaviour. Its compatibility layer detects and adapts to supported battle-camera environments itself.

---

# 🛡️ Camera Safety & Fallbacks

Different Gen1Recomp battle environments provide very different amounts of safe physical camera space.

Battle Cinematics includes fallback behaviour designed to preserve cinematography without breaking the active renderer.

Current protections include:

- Arena-boundary handling
- Rendering dead-zone protection
- Safe-eye / zero-travel fallback where physical camera movement is unsafe
- FOV compensation to preserve framing
- Tall-Pokémon headroom handling
- Backend camera-rig normalization
- Real constrained arenas distinguished from synthetic 2D-3D battle stages
- Support for 2D-3D A/B presentation modes across supported backends
- Clean camera ownership and reset between passive, intro, attack and faint systems

On constrained areas such as Routes 22 and 24, BC can preserve the intended composition optically rather than forcing unsafe physical camera travel.

On synthetic battle stages such as compatible 2D-3D B environments, full physical choreography remains available where safe.

The goal is always the same:

**preserve the cinematic composition without breaking the battle presentation.**

---

# 🔌 Mix and Match

Battle Cinematics is intended to sit at the **camera layer** of a modular Gen1Recomp setup.

For example:

**Battle renderer / sprite package**  
+ **Pokémon models or sprites of your choice**  
+ **Stadium Battle FX or vanilla animations**  
+ **Battle Cinematics camera system**

None of those visual choices force you to use Stadium Classic.

Likewise, Stadium Classic does not require Stadium models.

Use the combination you prefer.

---

# 📥 Download

Download the newest version from:

[**Battle Cinematics - Latest Release**](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera/releases/latest)

For detailed development history, compatibility changes and additional videos, see the individual release pages.

---

# 🔭 Development

Battle Cinematics continues to develop as a broader cinematic camera framework.

Future work may include:

- Additional battle-intro styles
- Further Stadium camera research
- Duration-aware attack-camera grammar
- Additional camera presets
- Continued compatibility work as new Gen1Recomp renderers and battle environments appear

New camera systems are developed on top of the last confirmed-good release, with existing backend and safety fallbacks treated as part of the compatibility contract.

---

## License

MIT
