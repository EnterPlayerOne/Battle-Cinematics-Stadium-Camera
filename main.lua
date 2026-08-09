-- Battle Cinematics v0.7.7 — 2D-3D B Compatibility Hotfix
-- Clean companion mod. It never modifies a renderer's files.
--
-- Compatible backends currently mapped:
--   DRAMATIC_SHAPE          upstream Dramatic Shape, including the 1.68
--                           Battle Art replacement (same manifest id)
--   DRAMALESS_SHAPE         Dramaless Shape fork (1.6.2.ST+)
--   BATTLE_ART_VOXEL_FORK   parallel Battle Art fork
--
-- Both are optional at manifest level so either implementation can satisfy
-- Battle Cinematics. Optional dependencies still guarantee load ordering in
-- Gen1Recomp; the runtime check below enforces that at least one compatible
-- camera backend actually survived loading.
local mod = ...

local BACKEND_IDS = { "DRAMATIC_SHAPE", "DRAMALESS_SHAPE", "BATTLE_ART_VOXEL_FORK" }
local backends = {}

local function discoverBackend(id)
  local handle = mod.find(id)
  if not handle then return nil end
  local exports = handle.exports or {}
  local V = exports.lib
  if type(V) ~= "table" or type(V.require) ~= "function" then
    mod.log:warn("backend %s has no compatible library loader", id)
    return nil
  end
  local okCam, BattleCam = pcall(V.require, "BattleCam")
  if not okCam or type(BattleCam) ~= "table"
     or type(BattleCam.rig) ~= "function"
     or type(BattleCam.rigFor) ~= "function" then
    mod.log:warn("backend %s has no compatible BattleCam", id)
    return nil
  end
  local okBattle, OverworldBattle = pcall(V.require, "OverworldBattle")
  local okStadium, Stadium = pcall(V.require, "Stadium")
  local okStadiumMon, StadiumMon = pcall(V.require, "StadiumMon")
  return {
    id=id, version=handle.version, V=V, BattleCam=BattleCam,
    OverworldBattle=(okBattle and type(OverworldBattle)=="table") and OverworldBattle or nil,
    Stadium=(okStadium and type(Stadium)=="table") and Stadium or nil,
    StadiumMon=(okStadiumMon and type(StadiumMon)=="table") and StadiumMon or nil,
  }
end

for _,id in ipairs(BACKEND_IDS) do
  local backend=discoverBackend(id)
  if backend then backends[#backends+1]=backend end
end
if #backends==0 then
  error("BATTLE_CINEMATICS: compatible battle-camera backend required (Dramatic Shape / Dramaless Shape / Battle Art)", 0)
end


-- Dramaless compatibility normalization -----------------------------------
--
-- Battle Cinematics 0.7.x was authored/tuned against the original Dramatic
-- Shape battle-camera contract. DRAMALESS_SHAPE 1.6.2.ST deliberately changes
-- that contract for its larger Stadium presentation:
--
--   original tele: back=144.96, height=37.88, full FOV = 2*atan(...)
--   Dramaless tele: back=144.96*1.5, height=37.88*1.5,
--                  and base FOV = 1*atan(...)
--
-- Feeding those altered rig constants into BC changes not just the renderer's
-- ordinary battle shot but every BC radius/FOV calculation and every blend
-- into/out of a cinematic. That is why simply recognizing the new manifest ID
-- produced the heavily zoomed result.
--
-- Do NOT retune the presets around the fork. Instead, when DRAMALESS_SHAPE is
-- the active provider and Battle Cinematics itself is enabled, use the exact
-- original Dramatic Shape camera geometry as BC's presentation reference.
-- Dramaless still owns all rendering/models; BC only normalizes the camera seam.
--
-- The wide rig was not altered by Dramaless, but keeping both reference rigs
-- here makes the adapter deterministic and protects future provider changes.
local BC_REFERENCE_RIGS = {
  tele = {
    side=78.79, back=144.96, height=37.88,
    lookX=-0.26, lookY=0.34, frameH=34.11,
  },
  wide = {
    side=41.98, back=41.16, height=28.48,
    lookX=-3.24, lookY=-1.35, frameH=55.62,
  },
}

local function bcReferenceRigFor(arena, frameScale)
  local key=(arena and arena.cam=="wide") and "wide" or "tele"
  local src=BC_REFERENCE_RIGS[key]
  local k=frameScale or 1
  return {
    side=src.side, back=src.back, height=src.height,
    lookX=src.lookX, lookY=src.lookY, frameH=src.frameH*k,
    __bcActorScale=k,
  }
end

local function poseActorScale(R)
  local k=tonumber(R and R.__bcActorScale) or 1.0
  return math.max(1.0,math.min(1.30,k))
end

-- Dramaless enlarges its Stadium actors as well as altering the camera. For a
-- non-clamped model its world-height multiplier relative to upstream is:
--   (REF/14) * (52.25/MEDIAN)^SQUASH
-- Read the fork's own constants rather than hard-coding the current ~1.14.
-- Widening BC's optical frame by the same amount preserves the established
-- apparent Pokemon size while leaving BC's physical eye paths untouched.
local function backendActorFrameScale(backend)
  if not backend or backend.id~="DRAMALESS_SHAPE" then return 1 end
  local Stadium=backend.Stadium
  local StadiumMon=backend.StadiumMon
  if not (Stadium and type(Stadium.active)=="function" and Stadium.active()) then
    return 1
  end
  if not StadiumMon then return 1 end
  local ref=tonumber(StadiumMon.REF_HEIGHT) or 14
  local med=tonumber(StadiumMon.MEDIAN) or 52.25
  local squash=tonumber(StadiumMon.SQUASH) or 0.5
  if med<=0 then return 1 end
  local k=(ref/14.0)*((52.25/med)^squash)
  return math.max(1.0,math.min(1.30,k))
end

local function bcPoseCamera(backend, BattleCam)
  if not backend or backend.id~="DRAMALESS_SHAPE" then return BattleCam end
  local k=backendActorFrameScale(backend)
  return {
    rigFor=function(arena) return bcReferenceRigFor(arena,k) end
  }
end

local function bcAxisSpan(beta,elev)
  local c=math.cos(elev)
  local s=math.sin(beta)*c
  local v=math.sin(elev)
  return math.sqrt(s*s+v*v)
end

local function bcPhase(t,period)
  period=tonumber(period) or 1
  if math.abs(period)<1e-6 then return 0 end
  return math.sin(2*math.pi*(tonumber(t) or 0)/period)
end

-- Reconstruct upstream Dramatic Shape's ordinary battle camera from the live
-- Dramaless steering state. This is used for BC's idle delay and as the blend
-- endpoint for Dynamic Intro / presets, so transitions begin from the same
-- camera that 0.7.3 was tuned against.
local function drAmalessNormalizedBase(backend,arena,groundY,BattleCam,canonical)
  if not (backend and backend.id=="DRAMALESS_SHAPE" and arena and arena.mid) then
    return nil,nil
  end
  groundY=groundY or 0
  local R=bcReferenceRigFor(arena,backendActorFrameScale(backend))
  local mx,mz=arena.mid[1],arena.mid[2]
  local fixed=(BattleCam.still and true or false) or (canonical and true or false)
  local steerable=(BattleCam.steerable~=false)
  local steered=(not fixed) and steerable

  local orbit=tonumber(BattleCam.orbit) or 0
  local orbitRange=math.max(0,math.pi/2-math.atan2(R.side,R.back))
  local steer=steered and (-orbit*orbitRange) or 0

  local base=math.rad(arena.turn or 0)
  local panYaw=tonumber(BattleCam.PAN_YAW) or math.rad(2)
  local panPeriod=tonumber(BattleCam.PAN_PERIOD) or 26
  local yaw=base+steer+(fixed and 0 or panYaw*bcPhase(BattleCam.t,panPeriod))
  local c,s=math.cos(yaw),math.sin(yaw)

  local panDolly=tonumber(BattleCam.PAN_DOLLY) or 0.02
  local dollyPeriod=tonumber(BattleCam.DOLLY_PERIOD) or 37
  local breath=fixed and 1 or (1+panDolly*bcPhase(BattleCam.t,dollyPeriod))
  local dx=(R.side*c-R.back*s)*breath
  local dz=(R.side*s+R.back*c)*breath

  -- Upstream contract: groundY + height. Dramaless currently multiplies
  -- groundY by 1.5 here as part of its fork-specific presentation change.
  local eye={mx+dx,groundY+R.height*breath,mz+dz}

  local bc,bs=math.cos(base),math.sin(base)
  local focus={mx+R.lookX*bc,groundY+R.lookY,mz+R.lookX*bs}

  local pitchValue=tonumber(BattleCam.pitch) or 0
  local pitchRange=tonumber(BattleCam.PITCH_RANGE) or math.rad(45)
  local lift=steered and pitchValue*pitchRange or 0
  if lift>0 then
    local vx,vy,vz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
    local flat=math.sqrt(vx*vx+vz*vz)
    local radius=math.sqrt(flat*flat+vy*vy)
    if flat>1e-6 and radius>1e-6 then
      local a=math.min(math.atan2(vy,flat)+lift,math.rad(85))
      local nf=radius*math.cos(a)
      eye[1]=focus[1]+vx/flat*nf
      eye[3]=focus[3]+vz/flat*nf
      eye[2]=focus[2]+radius*math.sin(a)
    end
  end

  local ex,ey,ez=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(1,math.sqrt(ex*ex+ey*ey+ez*ez))
  local horiz=math.sqrt(ex*ex+ez*ez)

  local frameH=R.frameH
  if not fixed and steerable then
    local beta=math.atan2(R.side,R.back)
    local homeElev=math.atan2(R.height-R.lookY,
      math.sqrt((R.side-R.lookX)^2+R.back^2))
    local home=bcAxisSpan(beta,homeElev)
    local spread=1
    if home>1e-6 then
      spread=bcAxisSpan(beta+orbit*orbitRange,
        homeElev+pitchValue*pitchRange)/home
    end
    frameH=frameH*(tonumber(BattleCam.zoom) or 1)*spread
  end

  return {
    eye=eye, focus=focus,
    -- Upstream/full-angle camera contract. This is intentionally NOT the
    -- fork's current 1*atan formula.
    fov=2*math.atan((frameH/2)/dist),
    curve=0,
  },math.atan2(horiz,math.max(1e-3,ey))
end

local SPEEDS = {
  { value="slowest", label="SLOWEST", scale=1.75 },
  { value="slow",    label="SLOW",    scale=1.35 },
  { value="medium",  label="MEDIUM",  scale=1.00 },
  { value="fast",    label="FAST",    scale=0.78 },
}
local DELAYS = { immediate=0.0, quick_2=2.0, quick_4=4.0, short=6.0, standard=9.0, long=12.0, extra_long=15.0 }

-- A genuine mod-owned settings page. Nothing is injected into the game's
-- global Options list or Dramatic Shape's menu.
mod.options:define({
  { key="enabled", label="ENABLED", type="choice", default="on",
    choices={{"ON","on"},{"OFF","off"}} },
  { key="preset", label="PRESET", type="choice", default="dw3",
    choices={{"DW3 CLASSIC","dw3"},{"HERO PORTRAIT","portrait_test"},{"STADIUM CLASSIC","stadium"}} },
  { key="dynamicIntro", label="BATTLE INTRO", type="choice", default="on",
    choices={{"BC HERO","on"},{"OFF","off"}} },
  { key="attackCamera", label="ATTACK CAMERA", type="choice", default="stadium",
    choices={{"STADIUM","stadium"},{"OFF","off"}} },
  { key="faintCamera", label="FAINT CAMERA", type="choice", default="on",
    choices={{"ON","on"},{"OFF","off"}} },

  -- Preset-owned values. The Mod Manager wrapper below hides these rows from
  -- the main Battle Cinematics page and exposes them through CONFIGURE PRESET.
  -- They remain normal mod options underneath, so values are persisted by the
  -- launcher and survive preset switching / restarts.
  { key="dw3Framing", label="FRAMING", type="choice", default="standard",
    choices={{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}} },
  { key="circleSpeed", label="ORBIT SPEED", type="choice", default="medium",
    choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}} },
  { key="dw3Height", label="HEIGHT", type="choice", default="standard",
    choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}} },
  { key="dw3Angle", label="ANGLE", type="choice", default="standard",
    choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}} },

  { key="introSpeed", label="INTRO SPEED", type="choice", default="fast",
    choices={{"SLOW","slow"},{"NORMAL","normal"},{"FAST","fast"}} },
  { key="introReset", label="INTRO CANCEL", type="choice", default="confirmed",
    choices={{"ON MOVE/ITEM","confirmed"},{"ANY INPUT","any"},{"OFF","off"}} },
  { key="initialDelay", label="INITIAL DELAY", type="choice", default="quick_4",
    choices={{"IMMEDIATE (0s)","immediate"},{"2 SECONDS","quick_2"},
             {"4 SECONDS","quick_4"},{"SHORT (6s)","short"},
             {"STANDARD (9s)","standard"},{"LONG (12s)","long"},
             {"EXTRA LONG (15s)","extra_long"}} },
  { key="inputReturn", label="RESET CAMERA", type="choice", default="confirmed",
    choices={{"ON MOVE/ITEM","confirmed"},{"ANY INPUT","any"},{"OFF","off"}} },
  { key="diagnostics", label="DIAGNOSTICS", type="choice", default="off",
    choices={{"OFF","off"},{"ON","on"}} },
})

local state = {
  rigSeen=false, sinceRig=0, noRig=0,
  idle=0, time=0, active=false, blend=0,
  directorPlan=1, directorBattle=0,
  battle=nil,
  intro={ active=false, style=nil, side=nil, time=0,
          pendingEnemy=false, pendingPlayer=false,
          initial=true, enemyWasSending=false, playerWasSending=false },
  attack={ pending=false, active=false, side=nil, moveId=nil, mode="target", time=0, progress=0,
           sawAnimation=false, animTotal=0, tail=0 },
  faint={ pending=false, active=false, side=nil, battler=nil, time=0,
          shownStart=nil, zeroReached=false, zeroTime=0,
          stadiumSeen=false, stadiumGone=0 },
}
local BLEND_TIME=0.70

local function enabled()
  return mod.options:get("enabled") ~= "off"
end
local function idleDelay()
  return DELAYS[mod.options:get("initialDelay")] or DELAYS.quick_4
end
local function speedScale()
  local value=mod.options:get("circleSpeed") or "medium"
  for _,e in ipairs(SPEEDS) do if e.value==value then return e.scale end end
  return 1.0
end

-- Gen1Recomp fast-forward runs the fixed 1/60 logic step multiple times per
-- real frame. Battle Cinematics is presentation-only, so advancing its timers
-- by the raw input.step dt makes every camera run N times faster at N X game
-- speed. Convert the logic-step delta back to real presentation time here and
-- keep every camera system on this one clock.
local function effectiveLogicSpeed(game)
  if game and type(game.logicSpeed)=="function" then
    local ok,value=pcall(game.logicSpeed,game)
    value=ok and tonumber(value) or nil
    if value and value>0 then return value end
  end
  -- Compatibility fallback for older supported Gen1Recomp builds that expose
  -- the saved speed option but not Game:logicSpeed(). Current builds should
  -- always take the authoritative runtime path above (speed override/link-safe).
  local options=game and game.save and game.save.options
  local value=options and tonumber(options.speed) or nil
  return (value and value>0) and value or 1
end

local function cameraDelta(game,dt)
  dt=math.max(0,tonumber(dt) or 0)
  return dt/effectiveLogicSpeed(game)
end

local CAMERA_FPS=60
local function advanceAttackProgress(progress,target,animTotal,dt)
  progress=math.max(0,math.min(1,tonumber(progress) or 0))
  target=math.max(progress,math.min(1,tonumber(target) or progress))
  animTotal=tonumber(animTotal) or 0
  if animTotal<=0 then return target end
  local maxAdvance=math.max(0,tonumber(dt) or 0)*CAMERA_FPS/animTotal
  return math.min(target,progress+maxAdvance)
end
local function diagnosticsOn()
  return mod.options:get("diagnostics") == "on"
end
local function logDiagnostic(message)
  if diagnosticsOn() then mod.log:info("[diagnostics] " .. message) end
end

local HERO_INTRO_DURATION=9.4
local function battleIntroStyle()
  return mod.options:get("dynamicIntro")=="off" and "off" or "hero"
end
local function battleIntroOn()
  return battleIntroStyle() ~= "off"
end
local function attackCameraStyle()
  return mod.options:get("attackCamera") or "off"
end
local function stadiumAttackOn()
  return attackCameraStyle()=="stadium"
end
local function faintCameraOn()
  return mod.options:get("faintCamera") ~= "off"
end
local function introSpeedScale()
  local value=mod.options:get("introSpeed") or "fast"
  if value=="fast" then return 2.0 end      -- established v0.7.1 default
  if value=="slow" then return 0.75 end     -- gentler presentation
  return 1.0                                -- normal / legacy normal
end
local function introResetMode()
  return mod.options:get("introReset") or "off"
end
local function clearIntro()
  state.intro.active=false
  state.intro.style=nil
  state.intro.side=nil
  state.intro.time=0
end
local function queueIntro(side)
  if battleIntroStyle()~="hero" then return end
  if side=="enemy" then state.intro.pendingEnemy=true
  elseif side=="player" then state.intro.pendingPlayer=true end
end
local function startIntro(side,style)
  style=style or "hero"
  state.intro.active=true
  state.intro.style=style
  state.intro.side=side
  state.intro.time=0
  if side=="enemy" then
    state.intro.pendingEnemy=false
  elseif side=="player" then
    state.intro.pendingPlayer=false
  end
  state.active=false
  state.idle=0
  state.blend=0
  logDiagnostic("battle intro: "..style..(side and (" / "..side) or ""))
end
local function clearAttack()
  state.attack.pending=false
  state.attack.active=false
  state.attack.side=nil
  state.attack.moveId=nil
  state.attack.mode="target"
  state.attack.time=0
  state.attack.progress=0
  state.attack.sawAnimation=false
  state.attack.animTotal=0
  state.attack.tail=0
end
local function clearFaint()
  state.faint.pending=false
  state.faint.active=false
  state.faint.side=nil
  state.faint.battler=nil
  state.faint.time=0
  state.faint.shownStart=nil
  state.faint.zeroReached=false
  state.faint.zeroTime=0
  state.faint.stadiumSeen=false
  state.faint.stadiumGone=0
end
local function queueFaint(side,battler)
  if not enabled() or not faintCameraOn() or not side or not battler then return end
  -- onFaint fires when actual HP reaches zero, before the queued move FX / HP
  -- drain / visible collapse have necessarily finished. Record the victim here;
  -- camera ownership is handed over later so we never pre-empt the attack.
  clearFaint()
  state.faint.pending=true
  state.faint.side=side
  state.faint.battler=battler
  state.faint.shownStart=tonumber(battler.shownHP)
  logDiagnostic("faint camera queued: "..tostring(side))
end
local function beginFaint()
  if not state.faint.pending or not faintCameraOn() then return false end
  clearIntro()
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  state.faint.pending=false
  state.faint.active=true
  state.faint.time=0
  state.faint.zeroReached=false
  state.faint.zeroTime=0
  state.faint.stadiumSeen=false
  state.faint.stadiumGone=0
  state.active=false
  state.idle=0
  -- A faint is a deliberate cut from the completed attack/engine camera to the
  -- defeated Pokemon. Do not spend its collapse blending through the rear rig.
  state.blend=1
  logDiagnostic("faint camera started: "..tostring(state.faint.side))
  return true
end
local function classifyAttackMove(battle,move)
  -- Gen1Recomp exposes the merged move-effect record through battle.data.
  -- Its own battle engine documents a useful semantic distinction: status
  -- effects with accuracyChecked=true are aimed at the opponent; the other
  -- primary status effects operate on the user. Reuse that contract instead
  -- of maintaining a brittle list of move names, while keeping sensible
  -- fallbacks for old/alternate data registries.
  if not move then return "target" end
  if (tonumber(move.power) or 0)>0 then return "target" end

  local effect=move.effect
  if effect=="HAZE_EFFECT" then return "field" end

  local effects=battle and battle.data and battle.data.move_effects
  local record=effects and effect and effects[effect] or nil
  if type(record)=="table" and record.kind=="primary" then
    return record.accuracyChecked and "target" or "self"
  end

  -- Older caches / third-party effect registries may not expose the record
  -- metadata above. These are the opponent-directed primary effect families
  -- in Gen 1; unknown zero-power moves are safer framed on their user than on
  -- an opponent they may never touch.
  local opponentEffects={
    SLEEP_EFFECT=true, POISON_EFFECT=true, PARALYZE_EFFECT=true,
    CONFUSION_EFFECT=true, LEECH_SEED_EFFECT=true, DISABLE_EFFECT=true,
    ATTACK_DOWN1_EFFECT=true, DEFENSE_DOWN1_EFFECT=true,
    DEFENSE_DOWN2_EFFECT=true, SPEED_DOWN1_EFFECT=true,
    ACCURACY_DOWN1_EFFECT=true,
  }
  if opponentEffects[effect] then return "target" end
  if move.id=="ROAR" then return "target" end
  return "self"
end

local function armAttack(side,moveId,mode)
  if not enabled() or not stadiumAttackOn() then return end
  -- move_used is the reliable commitment signal, but the text announcement can
  -- precede the visual animation by an arbitrary amount of time. Arm here and
  -- take camera control only when Gen1Recomp actually starts AnimPlayer.
  state.attack.pending=true
  state.attack.active=false
  state.attack.side=side
  state.attack.moveId=moveId
  state.attack.mode=mode or "target"
  state.attack.time=0
  state.attack.progress=0
  state.attack.sawAnimation=false
  state.attack.animTotal=0
  state.attack.tail=0
  logDiagnostic("stadium attack armed: "..tostring(side).." / "..tostring(moveId).." / "..tostring(state.attack.mode))
end
local function beginAttack()
  if not state.attack.pending then return end
  -- An actual visual move takes camera priority. Any queued introduction is
  -- discarded at this point so the two cinematography modules cannot compete.
  clearIntro()
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  state.attack.pending=false
  state.attack.active=true
  state.attack.time=0
  state.attack.progress=0
  state.attack.sawAnimation=false
  state.attack.animTotal=0
  state.attack.tail=0
  state.active=false
  state.idle=0
  -- Stadium uses deliberate cuts; do not spend the first shot blending out of
  -- the ordinary rear camera.
  state.blend=1
  logDiagnostic("stadium attack camera started")
end

local function activity()
  state.idle=0
  state.active=false
end
local function resetBattle()
  state.idle,state.time,state.active,state.blend=0,0,false,0
  state.directorBattle=(state.directorBattle or 0)+1
  state.directorPlan=((state.directorBattle-1)%3)+1
  clearIntro()
  clearAttack()
  clearFaint()
end
local function chase(now,goal,dt,time)
  if now==goal then return goal end
  local v=now+(goal-now)*math.min(1,(dt or 0)/math.max(1e-4,time))
  return (math.abs(goal-v)<1e-4) and goal or v
end
local function smoothstep(q) return q*q*(3-2*q) end
local function smootherstep(q) return q*q*q*(q*(q*6-15)+10) end
local function mix(a,b,w) return a+(b-a)*w end
local function mixCamera(base,cine,w)
  if not cine or w<=0 then return base end
  return {
    eye={mix(base.eye[1],cine.eye[1],w),mix(base.eye[2],cine.eye[2],w),mix(base.eye[3],cine.eye[3],w)},
    focus={mix(base.focus[1],cine.focus[1],w),mix(base.focus[2],cine.focus[2],w),mix(base.focus[3],cine.focus[3],w)},
    fov=mix(base.fov,cine.fov,w), curve=0,
  }
end

-- Strong zero-travel safety for renderer dead-zone arenas. Some narrow maps
-- (notably the Route 22/24 family) can drop back to the original 2D battle
-- layer when a cinematic eye leaves the backend's known-safe native rig even
-- though the requested destination itself is inside the map rectangle.
--
-- Locking the physical eye to the backend's resolved base camera is the only
-- universally safe answer on those maps. To preserve the authored cinematic
-- framing, recover the implied optical frame from the cinematic eye/FOV, then
-- re-project that same frame from the locked eye. This is important: simply
-- copying cine.fov while changing the eye distance makes close-ups look like
-- nothing happened (the old narrow-route Battle Intro symptom).
local function zeroTravelCamera(base,cine,w)
  if not base or not cine or w<=0 then return base end
  local focus={
    mix(base.focus[1],cine.focus[1],w),
    mix(base.focus[2],cine.focus[2],w),
    mix(base.focus[3],cine.focus[3],w),
  }

  local cdx,cdy,cdz=cine.eye[1]-cine.focus[1],cine.eye[2]-cine.focus[2],cine.eye[3]-cine.focus[3]
  local cineDist=math.max(1,math.sqrt(cdx*cdx+cdy*cdy+cdz*cdz))
  local impliedFrame=2*cineDist*math.tan((cine.fov or base.fov)*0.5)

  local ldx,ldy,ldz=base.eye[1]-cine.focus[1],base.eye[2]-cine.focus[2],base.eye[3]-cine.focus[3]
  local lockedDist=math.max(1,math.sqrt(ldx*ldx+ldy*ldy+ldz*ldz))
  local safeFov=2*math.atan((impliedFrame*0.5)/lockedDist)
  -- Keep pathological provider values bounded without changing normal framing.
  safeFov=math.max(math.rad(6.0),math.min(math.rad(85.0),safeFov))

  local camera={
    eye={base.eye[1],base.eye[2],base.eye[3]},
    focus=focus,
    fov=mix(base.fov,safeFov,w), curve=0,
  }
  local pdx,pdy,pdz=camera.eye[1]-camera.focus[1],camera.eye[2]-camera.focus[2],camera.eye[3]-camera.focus[3]
  local horiz=math.sqrt(pdx*pdx+pdz*pdz)
  local projectedPitch=math.atan2(horiz,math.max(1e-3,pdy))
  return camera,projectedPitch
end

local PLANS={
  {
    {kind="orbit",duration=13.5,turns=1.00,direction=1},
    {kind="enemy",duration=6.0,approach=0.30,hold=0.40},
    {kind="player",duration=6.0,approach=0.30,hold=0.40},
  },
  {
    {kind="orbit",duration=10.5,turns=0.78,direction=-1},
    {kind="enemy",duration=7.4,approach=0.27,hold=0.48},
    {kind="player",duration=6.2,approach=0.30,hold=0.40},
  },
  {
    {kind="player",duration=6.4,approach=0.29,hold=0.42},
    {kind="orbit",duration=12.0,turns=0.88,direction=1},
    {kind="enemy",duration=8.0,approach=0.26,hold=0.52},
  },
}
local function shots() return PLANS[state.directorPlan or 1] or PLANS[1] end
local function shotDuration(shot)
  return shot.kind=="orbit" and shot.duration*speedScale() or shot.duration
end

local function selectedPreset()
  return mod.options:get("preset") or "dw3"
end

-- First Configure Preset proof: a DW3-owned framing profile.  This is saved
-- independently of the selected preset, so switching to Hero Portrait and
-- back restores the user's DW3 choice.  Framing is optical rather than a
-- positional push: the camera path remains inside the already-proven safe
-- volume while the field of view provides increasing degrees of closeness.
local function dw3FramingScale()
  local value=mod.options:get("dw3Framing") or "standard"
  if value=="near" then return 0.86 end
  if value=="close" then return 0.72 end
  return 1.00
end

-- Safe preset-direction controls. These deliberately expose artistic levels,
-- not raw coordinates. Height nudges the entire DW3 rig vertically within a
-- conservative range; Angle changes the lateral strength of the close-up /
-- shoulder compositions. Standard is exactly the v0.7.1 camera.
local function dw3HeightOffset()
  local value=mod.options:get("dw3Height") or "standard"
  if value=="low" then return math.rad(-4.0) end
  if value=="high" then return math.rad(4.0) end
  return 0
end
local function dw3AngleScale()
  local value=mod.options:get("dw3Angle") or "standard"
  if value=="shallow" then return 0.72 end
  if value=="strong" then return 1.30 end
  return 1.00
end

-- Passive opponent-side portrait proof. The camera remains safely on the
-- opponent's half of the Stadium volume, moves laterally out of the battle
-- lane, and looks back toward the player's Pokémon for an unobstructed hero
-- portrait. It never crosses onto the player's side of midfield.
local function portraitTestPose(arena,groundY,camera)
  if not arena or not arena.player or not arena.enemy then return nil,nil,0 end
  local R=camera.rigFor(arena)

  -- Hero Portrait is a complete mirrored two-subject sequence:
  -- player portrait -> brief neutral pause -> opponent portrait -> pause.
  -- Each side uses the exact V5 lens, safe-distance geometry and subtle rise.
  local cycle=20.4
  local t=state.time%cycle
  local target,other,mirror,localT
  if t<9.4 then
    target,other,mirror,localT=arena.player,arena.enemy,1,t
  elseif t<10.2 then
    return nil,nil,0
  elseif t<19.6 then
    target,other,mirror,localT=arena.enemy,arena.player,-1,t-10.2
  else
    return nil,nil,0
  end

  local tx,tz=target[1],target[2]
  local ox,oz=other[1],other[2]
  local fx,fz=ox-tx,oz-tz
  local len=math.sqrt(fx*fx+fz*fz)
  if len<1e-4 then return nil,nil,0 end
  fx,fz=fx/len,fz/len
  local rx,rz=-fz,fx

  local w
  if localT<2.6 then
    w=smootherstep(localT/2.6)
  elseif localT<6.8 then
    w=1.0
  else
    w=1.0-smootherstep((localT-6.8)/2.6)
  end

  local holdT=math.max(0,math.min(1,(localT-2.6)/4.2))
  local micro=math.sin(holdT*math.pi*2)*math.rad(0.35)

  -- V5 breathing drift, restarted identically for each subject.
  local tiltT=math.max(0,math.min(1,(localT-2.9)/2.75))
  local tiltEase=smootherstep(tiltT)

  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local radius=baseRadius*0.80
  local elevation=math.rad(12.0)

  -- Mirror the successful V5 side offset across the arena. Swapping target
  -- and opponent reverses the forward axis; mirror reverses the lateral arc.
  local arc=mirror*(math.rad(24.0)+micro)
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)

  local actorScale=poseActorScale(R)
  local baseFocusY=(groundY or 0)+R.lookY+4.9*actorScale
  local eye={
    tx+dx*flat,
    baseFocusY+radius*math.sin(elevation),
    tz+dz*flat,
  }

  local horizontalDistance=math.max(1,flat)
  local focusRise=horizontalDistance*math.tan(math.rad(2.25))*tiltEase
  local focus={
    tx+rx*(len*0.010)*mirror,
    baseFocusY+focusRise,
    tz+rz*(len*0.010)*mirror,
  }

  local cameraDistance=math.sqrt((eye[1]-focus[1])^2+(eye[3]-focus[3])^2)
  local frame=R.frameH*0.46
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end

local function dynamicIntroPose(arena,groundY,camera)
  if not arena or not arena.player or not arena.enemy or not state.intro.active then return nil,nil,0 end
  local R=camera.rigFor(arena)
  local side=state.intro.side
  local target,other,mirror
  if side=="player" then target,other,mirror=arena.player,arena.enemy,1
  else target,other,mirror=arena.enemy,arena.player,-1 end
  local localT=state.intro.time
  local tx,tz=target[1],target[2]
  local ox,oz=other[1],other[2]
  local fx,fz=ox-tx,oz-tz
  local len=math.sqrt(fx*fx+fz*fz)
  if len<1e-4 then return nil,nil,0 end
  fx,fz=fx/len,fz/len
  local rx,rz=-fz,fx
  local w
  if localT<2.6 then w=smootherstep(localT/2.6)
  elseif localT<6.8 then w=1.0
  else w=1.0-smootherstep((localT-6.8)/2.6) end
  local holdT=math.max(0,math.min(1,(localT-2.6)/4.2))
  local micro=math.sin(holdT*math.pi*2)*math.rad(0.35)
  local tiltT=math.max(0,math.min(1,(localT-2.9)/2.75))
  local tiltEase=smootherstep(tiltT)
  local actorScale=poseActorScale(R)
  local baseFocusY=(groundY or 0)+R.lookY+4.9*actorScale

  -- Hard Dynamic Intro fallback. Do not attempt to rescue the target-relative
  -- front-axis trajectory on extreme rigs. The successful DW3 shoulder fix
  -- taught us that these maps need a different construction method entirely.
  -- For Dramatic Shape's known problem rig, or when battlers are spread much
  -- farther apart than the normal ~48 world pixels, construct the camera from
  -- the arena midpoint and a strong perpendicular offset. This guarantees the
  -- eye never travels down the line through either Pokemon.
  local extreme = (arena.cam=="wide") or (len>56.0)
  if extreme then
    local mx,mz=(arena.mid and arena.mid[1]) or ((tx+ox)*0.5),
                (arena.mid and arena.mid[2]) or ((tz+oz)*0.5)
    -- Stay predominantly beside the battle line. A small axial component keeps
    -- the portrait three-quarter rather than pure profile, while remaining far
    -- away from the dangerous front/back axis.
    local lateral=math.min(30.0,math.max(22.0,len*0.42))
    local axial=math.min(10.0,math.max(6.0,len*0.12))
    local microOffset=math.sin(holdT*math.pi*2)*0.35
    local eye={
      mx + rx*(mirror*(lateral+microOffset)) - fx*axial,
      baseFocusY + 10.5,
      mz + rz*(mirror*(lateral+microOffset)) - fz*axial,
    }
    local cameraDistance=math.sqrt((eye[1]-tx)^2+(eye[3]-tz)^2)
    local focusRise=cameraDistance*math.tan(math.rad(2.25))*tiltEase
    local focus={tx,baseFocusY+focusRise,tz}
    -- Recover intimacy optically rather than by moving the eye closer.
    local frame=R.frameH*0.43
    local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
    local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
    logDiagnostic(string.format("dynamic intro midpoint fallback: cam=%s spacing=%.1f",tostring(arena.cam),len))
    return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
  end

  -- Established Hero Portrait intro for normal arenas.
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local radius=baseRadius*0.80
  local elevation=math.rad(12.0)
  local arc=mirror*(math.rad(24.0)+micro)
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)
  local eye={tx+dx*flat,baseFocusY+radius*math.sin(elevation),tz+dz*flat}
  local horizontalDistance=math.max(1,flat)
  local focusRise=horizontalDistance*math.tan(math.rad(2.25))*tiltEase
  local focus={tx+rx*(len*0.010)*mirror,baseFocusY+focusRise,tz+rz*(len*0.010)*mirror}
  local cameraDistance=math.sqrt((eye[1]-focus[1])^2+(eye[3]-focus[3])^2)
  local frame=R.frameH*0.46
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end


-- Shared safety for the new Stadium-derived modules. Like Stadium Classic's
-- existing boundary layer, this scales an eye back along its requested ray;
-- it never independently clamps X/Z, so the authored yaw is preserved.
local function clampEyeToArena(arena,anchorX,anchorZ,eye,maxFlat)
  if not eye then return eye end
  local bx,bz=eye[1]-anchorX,eye[3]-anchorZ
  local flat=math.sqrt(bx*bx+bz*bz)
  if flat<1e-4 then return eye end
  local limit=tonumber(maxFlat) or flat
  local map=arena and arena.map
  if map and type(map.widthCells)=="number" and type(map.heightCells)=="number" then
    local margin=12.0
    local minX,minZ=margin,margin
    local maxX,maxZ=map.widthCells*16.0-margin,map.heightCells*16.0-margin
    local ux,uz=bx/flat,bz/flat
    local edge=math.huge
    if ux>1e-6 then edge=math.min(edge,(maxX-anchorX)/ux)
    elseif ux<-1e-6 then edge=math.min(edge,(minX-anchorX)/ux) end
    if uz>1e-6 then edge=math.min(edge,(maxZ-anchorZ)/uz)
    elseif uz<-1e-6 then edge=math.min(edge,(minZ-anchorZ)/uz) end
    if edge~=math.huge and edge>8.0 then limit=math.min(limit,edge) end
  end
  if limit<flat then
    local k=limit/flat
    eye[1]=anchorX+bx*k
    eye[3]=anchorZ+bz*k
  end
  return eye
end

-- Faint Camera ------------------------------------------------------------
-- A KO is reported by the battle engine as soon as real HP reaches zero, but
-- the visible HP bar and the model's collapse are queued afterwards. Keep this
-- module independent of Attack Camera: it can receive a clean hand-off from
-- Stadium Attack Camera, or wait for the HP drain when Attack Camera is Off.
local function stadiumFaintStatus(side)
  local function probe(backend)
    local Stadium=backend and backend.Stadium
    if type(Stadium)~="table" then return nil,false,false end
    local hasAnim=type(Stadium.animOf)=="function"
    local hasShowing=type(Stadium.showing)=="function"
    if not hasAnim and not hasShowing then return nil,false,false end
    local anim,showing=nil,false
    if hasAnim then
      local ok,v=pcall(Stadium.animOf,side)
      if ok then anim=v end
    end
    if hasShowing then
      local ok,v=pcall(Stadium.showing,side)
      if ok then showing=not not v end
    end
    return anim,showing,true
  end

  -- The backend which most recently supplied BattleCam is the authoritative
  -- one. Fall back to the other discovered providers for older/hot-reload
  -- arrangements where backendId has not been latched yet.
  if state.backendId then
    for _,backend in ipairs(backends) do
      if backend.id==state.backendId then
        local anim,showing,api=probe(backend)
        if api then return anim,showing,true end
        break
      end
    end
  end
  local sawApi=false
  for _,backend in ipairs(backends) do
    local anim,showing,api=probe(backend)
    if api then
      sawApi=true
      if anim~=nil or showing then return anim,showing,true end
    end
  end
  return nil,false,sawApi
end

local function faintCameraPose(arena,groundY,camera)
  if not state.faint.active or not arena or not arena.player or not arena.enemy then
    return nil,nil,0
  end
  local R=camera.rigFor(arena)
  local faintIsPlayer=state.faint.side=="player"
  local subject=faintIsPlayer and arena.player or arena.enemy
  local other=faintIsPlayer and arena.enemy or arena.player
  local sx,sz=subject[1],subject[2]
  local ox,oz=other[1],other[2]

  -- Define forward as the line the finishing blow travelled into the fainted
  -- Pokemon. This makes the same three-quarter composition mirror naturally
  -- when the player's Pokemon is the one collapsing.
  local fx,fz=sx-ox,sz-oz
  local spacing=math.sqrt(fx*fx+fz*fz)
  if spacing<1e-4 then return nil,nil,0 end
  fx,fz=fx/spacing,fz/spacing
  local rx,rz=-fz,fx
  local mx,mz=(arena.mid and arena.mid[1]) or ((sx+ox)*0.5),
              (arena.mid and arena.mid[2]) or ((sz+oz)*0.5)
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local baseY=(groundY or 0)+R.lookY
  local actorScale=poseActorScale(R)
  local extreme=(arena.cam=="wide") or spacing>56.0

  -- As the visible HP reaches zero, open the frame and lower the focus slightly
  -- so tall Stadium models remain readable all the way through a fall to the
  -- ground. It is intentionally one sustained shot, not another mini-sequence.
  local fallQ=smootherstep(math.max(0,math.min(1,(state.faint.zeroTime or 0)/2.0)))
  local drift=smootherstep(math.max(0,math.min(1,(state.faint.time or 0)/3.0)))
  local focusY=baseY+mix(3.8,2.45,fallQ)*actorScale
  local yaw=mix(128.0,136.0,drift)
  local elev=mix(16.0,12.0,fallQ)
  local radius=baseRadius*mix(0.80,0.84,fallQ)
  local a=math.rad(yaw)
  local dirX,dirZ=fx*math.cos(a)+rx*math.sin(a),
                  fz*math.cos(a)+rz*math.sin(a)
  local e=math.rad(elev)
  local flat=radius*math.cos(e)
  local eye={sx+dirX*flat,focusY+radius*math.sin(elev*math.pi/180),sz+dirZ*flat}

  if extreme then
    -- Same one-side safety principle as Stadium Attack Camera: on the known
    -- wide/problem rig, never create a path through both battlers merely to
    -- watch a faint. The focus still follows the defeated Pokemon downward.
    local lateral=math.min(30.0,math.max(22.0,spacing*0.42))
    local side=faintIsPlayer and 1 or -1
    eye={mx+rx*(side*lateral)-fx*math.min(9.0,spacing*0.12),
         focusY+10.5,
         mz+rz*(side*lateral)-fz*math.min(9.0,spacing*0.12)}
  end
  eye=clampEyeToArena(arena,sx,sz,eye,baseRadius*0.96)

  local focus={sx,focusY,sz}
  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(1,math.sqrt(dx*dx+dy*dy+dz*dz))
  local horiz=math.sqrt(dx*dx+dz*dz)
  local frameScale=mix(0.61,0.73,fallQ)
  local fov=2*math.atan(((R.frameH*frameScale)/2)/dist)
  return {eye=eye,focus=focus,fov=fov,curve=0},
         math.atan2(horiz,math.max(1e-3,dy)),1
end

-- Stadium Attack Camera ---------------------------------------------------
-- A move-independent camera grammar derived from the manually bounded
-- Flamethrower capture. The N64 trace repeatedly uses four broad ideas around
-- an attack: attacker-side launch, cross-field tracking, defender impact, and
-- a high finishing rise. We sync those ideas to Gen1Recomp's *actual compiled
-- move-animation progress* (AnimPlayer.elapsed / total step duration), so a
-- short move and a long Stadium FX replacement both receive the complete
-- choreography without changing either animation system.
local function stadiumAttackPose(arena,groundY,camera)
  if not state.attack.active or not arena or not arena.player or not arena.enemy then
    return nil,nil,0
  end
  local R=camera.rigFor(arena)
  local attackerIsPlayer=state.attack.side=="player"
  local attacker=attackerIsPlayer and arena.player or arena.enemy
  local target=attackerIsPlayer and arena.enemy or arena.player
  local ax,az=attacker[1],attacker[2]
  local tx,tz=target[1],target[2]
  local fx,fz=tx-ax,tz-az
  local spacing=math.sqrt(fx*fx+fz*fz)
  if spacing<1e-4 then return nil,nil,0 end
  fx,fz=fx/spacing,fz/spacing
  local rx,rz=-fz,fx
  local mx,mz=(arena.mid and arena.mid[1]) or ((ax+tx)*0.5),
              (arena.mid and arena.mid[2]) or ((az+tz)*0.5)
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local baseY=(groundY or 0)+R.lookY
  local actorScale=poseActorScale(R)
  local extreme=(arena.cam=="wide") or spacing>56.0

  local focusX,focusZ,focusY=ax,az,baseY+4.2*actorScale
  local yaw,elev,radius,frameScale=42.0,12.0,baseRadius*0.74,0.54
  local p=math.max(0,math.min(1,state.attack.progress or 0))
  local phase="launch"
  local mode=state.attack.mode or "target"

  -- Self-only moves (Barrier, Recover, stat boosts, Reflect, Rest, etc.)
  -- never spend animation time looking across the field. The whole available
  -- animation window becomes one restrained attacker portrait: a slow
  -- three-quarter pivot with the same upward focus tilt that made BC Hero's
  -- portrait shot work. Short vanilla animations therefore read as one clean
  -- move instead of racing through launch/track/impact/rise in under a second.
  if mode=="self" then
    local q=smootherstep(p)
    local mirror=attackerIsPlayer and 1 or -1
    local portraitY=baseY+4.9*actorScale
    local arc=mirror*math.rad(mix(32.0,18.0,q))
    local ca,sa=math.cos(arc),math.sin(arc)
    local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
    local selfRadius=baseRadius*mix(0.78,0.82,q)
    local selfElev=math.rad(mix(11.0,16.0,q))
    local flat=selfRadius*math.cos(selfElev)
    local eye={ax+dx*flat,portraitY+selfRadius*math.sin(selfElev),az+dz*flat}

    if extreme then
      local lateral=math.min(30.0,math.max(22.0,spacing*0.42))
      local axial=math.min(10.0,math.max(6.0,spacing*0.12))
      eye={mx+rx*(mirror*lateral)-fx*axial,portraitY+10.5,
           mz+rz*(mirror*lateral)-fz*axial}
    end
    eye=clampEyeToArena(arena,ax,az,eye,baseRadius*0.94)

    local horizontal=math.max(1,math.sqrt((eye[1]-ax)^2+(eye[3]-az)^2))
    local tilt=smootherstep(math.max(0,math.min(1,(p-0.12)/0.78)))
    local focusRise=horizontal*math.tan(math.rad(2.8))*tilt
    local focus={ax+rx*(spacing*0.008)*mirror,portraitY+focusRise,
                 az+rz*(spacing*0.008)*mirror}
    local dx2,dy2,dz2=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
    local dist=math.max(1,math.sqrt(dx2*dx2+dy2*dy2+dz2*dz2))
    local horiz=math.sqrt(dx2*dx2+dz2*dz2)
    local frame=R.frameH*mix(0.52,0.47,q)
    local fov=2*math.atan((frame/2)/dist)
    return {eye=eye,focus=focus,fov=fov,curve=0},
           math.atan2(horiz,math.max(1e-3,dy2)),1
  elseif mode=="field" then
    -- Haze is genuinely field-wide in Gen 1. Give it a restrained family
    -- composition rather than pretending either battler is the victim.
    local q=smootherstep(p)
    focusX,focusZ,focusY=mx,mz,baseY+3.1*actorScale
    yaw=mix(86.0,112.0,q)
    elev=mix(17.0,27.0,q)
    radius=baseRadius*mix(0.98,1.05,q)
    frameScale=mix(1.02,1.10,q)
    phase="field"
  elseif not state.attack.sawAnimation then
    -- Hold an attacker establishing composition while the "used MOVE!" page
    -- types. A tiny source-like creep keeps it alive without stealing time
    -- from the animation-synchronised four-shot sequence.
    local a=math.max(0,math.min(1,(state.attack.time or 0)/1.0))
    yaw=mix(48.0,36.0,smootherstep(a))
    elev=mix(10.0,14.0,smootherstep(a))
  elseif p<0.22 then
    local q=smootherstep(p/0.22)
    yaw=mix(58.0,18.0,q)
    elev=mix(10.0,18.0,q)
    radius=baseRadius*mix(0.76,0.68,q)
    frameScale=mix(0.56,0.48,q)
  elseif p<0.58 then
    phase="track"
    local q=smootherstep((p-0.22)/0.36)
    -- Track the aim point across the battlefield as the source does during
    -- Flamethrower's travelling middle section. The eye stays laterally clear
    -- of the attack line, so 3D FX remain readable rather than hidden behind
    -- either Pokémon.
    focusX=mix(ax,tx,q)
    focusZ=mix(az,tz,q)
    focusY=baseY+mix(4.0,3.2,q)*actorScale
    yaw=mix(105.0,78.0,q)
    elev=mix(8.0,11.0,q)
    radius=baseRadius*0.80
    frameScale=0.72
  elseif p<0.82 then
    phase="impact"
    local q=smootherstep((p-0.58)/0.24)
    focusX,focusZ,focusY=tx,tz,baseY+4.0*actorScale
    yaw=mix(154.0,122.0,q)
    elev=mix(9.0,17.0,q)
    radius=baseRadius*mix(0.72,0.76,q)
    frameScale=mix(0.47,0.50,q)
  else
    phase="rise"
    local q=smootherstep((p-0.82)/0.18)
    focusX,focusZ,focusY=tx,tz,baseY+(4.0+1.2*q)*actorScale
    yaw=mix(122.0,158.0,q)
    elev=mix(17.0,48.0,q)
    radius=baseRadius*mix(0.76,0.94,q)
    frameScale=mix(0.50,0.62,q)
  end

  local function eyeAround(cx,cz,yawDeg,elevDeg,rad)
    local a=math.rad(yawDeg)
    local dirX,dirZ=fx*math.cos(a)+rx*math.sin(a),
                    fz*math.cos(a)+rz*math.sin(a)
    local e=math.rad(elevDeg)
    local flat=rad*math.cos(e)
    return {cx+dirX*flat,focusY+rad*math.sin(e),cz+dirZ*flat}
  end

  local eye
  if phase=="track" or phase=="field" then
    -- Tracking follows its travelling aim point; field-wide moves orbit the
    -- midpoint so neither battler is falsely presented as the target.
    eye=eyeAround(focusX,focusZ,yaw,elev,radius)
  else
    local cx,cz=(phase=="impact" or phase=="rise") and tx or ax,
                (phase=="impact" or phase=="rise") and tz or az
    eye=eyeAround(cx,cz,yaw,elev,radius)
  end

  if extreme then
    -- Conservative attack-camera fallback. Keep every shot to one side of the
    -- battle line; phase still changes focus/FOV/elevation, but no eye path is
    -- allowed to sweep through both actors on the problem rig.
    local lateral=math.min(30.0,math.max(22.0,spacing*0.42))
    local side=attackerIsPlayer and -1 or 1
    eye={mx+rx*(side*lateral)-fx*math.min(9.0,spacing*0.12),
         focusY+10.5+baseRadius*math.sin(math.rad(elev))*0.25,
         mz+rz*(side*lateral)-fz*math.min(9.0,spacing*0.12)}
  end

  -- Attacker/impact shots use their subject as the radial anchor; the travelling
  -- middle shot uses the midpoint so boundary limiting cannot push it past a
  -- battler. FOV is always derived after any physical pull-in.
  local anchorX,anchorZ
  if phase=="track" or phase=="field" then anchorX,anchorZ=mx,mz
  elseif phase=="impact" or phase=="rise" then anchorX,anchorZ=tx,tz
  else anchorX,anchorZ=ax,az end
  eye=clampEyeToArena(arena,anchorX,anchorZ,eye,baseRadius*0.94)

  local focus={focusX,focusY,focusZ}
  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(1,math.sqrt(dx*dx+dy*dy+dz*dz))
  local horiz=math.sqrt(dx*dx+dz*dz)
  local fov=2*math.atan(((R.frameH*frameScale)/2)/dist)
  return {eye=eye,focus=focus,fov=fov,curve=0},
         math.atan2(horiz,math.max(1e-3,dy)),1
end


-- Stadium Classic ---------------------------------------------------------
-- Runtime-derived recreation of Pokemon Stadium (USA) v1.0's passive battle
-- camera. The timing/order comes from an untouched Project64 capture of the
-- original game. We translate Stadium's shot intent into Dramatic Shape's
-- arena-relative coordinate system rather than copying raw N64 coordinates.
--
-- One passive cycle measured 1912 VI (~31.87 s) and repeated with the same
-- shot boundaries. The first player horseshoe/portrait pair had two observed
-- variants, so alternate cycles reproduce both captured compositions.
local STADIUM_CYCLE=31.87

local function stadiumClassicPose(arena,groundY,camera)
  if not arena or not arena.player or not arena.enemy then return nil,nil,0 end
  local R=camera.rigFor(arena)
  local px,pz=arena.player[1],arena.player[2]
  local ex,ez=arena.enemy[1],arena.enemy[2]
  local fx,fz=ex-px,ez-pz
  local spacing=math.sqrt(fx*fx+fz*fz)
  if spacing<1e-4 then return nil,nil,0 end
  fx,fz=fx/spacing,fz/spacing
  local rx,rz=-fz,fx
  local mx,mz=(arena.mid and arena.mid[1]) or ((px+ex)*0.5),
              (arena.mid and arena.mid[2]) or ((pz+ez)*0.5)
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local baseY=(groundY or 0)+R.lookY
  local actorScale=poseActorScale(R)
  -- A carried B-stage deliberately reports the wide rig, but it is not a
  -- cramped/problem map: there is no map geometry around the fight at all.
  -- Treating arena.discs as a narrow-route fallback wrongly collapses
  -- Stadium Classic into zero-travel framing and can put a foreground 2D
  -- billboard across the subject. Only real map arenas inherit wide-rig
  -- dead-zone handling here.
  local extreme=((arena.cam=="wide") and not arena.discs) or spacing>56.0

  local total=STADIUM_CYCLE
  local cycleIndex=math.floor((state.time or 0)/total)
  local t=(state.time or 0)%total
  local variant=cycleIndex%2

  -- Measured shot boundaries, seconds:
  -- 2.97 / 2.93 / 3.97 / 2.23 / 2.87 / 6.33 / 1.97 / 1.97 / 6.33
  local spans={2.97,2.93,3.97,2.23,2.87,6.33,1.97,1.97,6.33}
  local shot=1
  while shot<#spans and t>=spans[shot] do
    t=t-spans[shot]; shot=shot+1
  end
  local q=math.max(0,math.min(1,t/spans[shot]))
  local u=smootherstep(q)

  local targetX,targetZ,targetY=mx,mz,baseY
  local yaw,elev,radius,frameScale
  local focusOffset=0
  local focusLift=0

  -- Helpers use Stadium yaw convention: 0° points player->enemy, +90° is the
  -- perpendicular/right side of that battle axis.
  local function eyeAround(tx,tz,yawDeg,elevDeg,rad)
    local a=math.rad(yawDeg)
    local dirX,dirZ=fx*math.cos(a)+rx*math.sin(a),
                    fz*math.cos(a)+rz*math.sin(a)
    local e=math.rad(elevDeg)
    local flat=rad*math.cos(e)
    return {tx+dirX*flat, targetY+rad*math.sin(e), tz+dirZ*flat}
  end

  local eye,focus

  if shot==1 then
    -- Player three-quarter horseshoe. Stadium alternated two variants across
    -- the two captured cycles while keeping the exact same 2.97 s boundary.
    targetX,targetZ,targetY=px,pz,baseY+3.6*actorScale
    if variant==0 then
      yaw=mix(80.0,0.0,u)
      elev=mix(0.0,34.0,u)
      radius=baseRadius*mix(0.80,1.05,u)
      frameScale=0.62
    else
      yaw=mix(165.0,20.0,u)
      elev=mix(0.0,12.0,u)
      radius=baseRadius*mix(0.82,1.12,u)
      frameScale=0.88
    end

  elseif shot==2 then
    -- Player close portrait/hold following the horseshoe. Stadium's captured
    -- framing is intentionally intimate, but tall models can lose the crown
    -- of the head at the fixed source aim. Preserve the eye/radius and add a
    -- gentle late aim-up instead: the composition stays close while gaining
    -- headroom, without introducing another positional dead-zone path.
    local headroomQ=math.max(0,math.min(1,(q-0.22)/0.78))
    focusLift=2.4*actorScale*smootherstep(headroomQ)
    targetX,targetZ,targetY=px,pz,baseY+3.6*actorScale
    if variant==0 then
      yaw,elev,radius,frameScale=154.0,23.0,baseRadius*0.82,0.48
    else
      yaw,elev,radius,frameScale=45.0,2.0,baseRadius*0.80,0.46
    end

  elseif shot==3 then
    -- Very wide static battlefield composition.
    targetX,targetZ,targetY=mx,mz,baseY
    yaw,elev,radius,frameScale=54.0,3.0,baseRadius*1.65,1.55

  elseif shot==4 then
    -- Cross-field enemy sweep. Original Stadium pans the aim point across the
    -- defender while the eye rotates into a near side-on composition.
    targetX,targetZ,targetY=ex,ez,baseY+2.0*actorScale
    yaw=mix(140.0,180.0,u)
    elev=3.0
    radius=baseRadius*0.78
    frameScale=0.72
    focusOffset=(1-u)*spacing*0.44

  elseif shot==5 then
    -- Enemy portrait/hold.
    targetX,targetZ,targetY=ex,ez,baseY+3.6*actorScale
    yaw,elev,radius,frameScale=113.0,17.0,baseRadius*0.80,0.48

  elseif shot==6 then
    -- High Stadium circle: ~170 degrees in 6.33 s at a fixed high elevation.
    targetX,targetZ,targetY=mx,mz,baseY
    yaw=mix(90.0,-80.0,u)
    elev=36.9
    radius=baseRadius*1.18
    frameScale=1.12

  elseif shot==7 then
    -- Very close player portrait. Reuse the proven Hero Portrait safety
    -- distance and achieve intimacy optically.
    targetX,targetZ,targetY=px,pz,baseY+4.9*actorScale
    yaw,elev,radius,frameScale=32.0,16.0,baseRadius*0.80,0.46

  elseif shot==8 then
    -- Mirrored close defender portrait.
    targetX,targetZ,targetY=ex,ez,baseY+4.9*actorScale
    yaw,elev,radius,frameScale=161.0,10.0,baseRadius*0.80,0.42

  else
    -- Final low/wide Stadium sweep. The source camera expands outward through
    -- the middle of the arc, then settles back as ~164 degrees of yaw pass.
    targetX,targetZ,targetY=mx,mz,baseY
    yaw=mix(90.0,-74.0,u)
    local bow=math.sin(q*math.pi)
    elev=13.0-5.0*bow
    radius=baseRadius*(1.05+0.55*bow)
    frameScale=1.22
  end

  -- Cramped/problem rigs: preserve Stadium's composition but do not send a
  -- target-relative portrait eye through the known sprite deadzone. Subject
  -- shots become a midpoint/perpendicular safe composition; orbit/wide shots
  -- remain naturally midpoint-based.
  local subjectShot=(shot==1 or shot==2 or shot==4 or shot==5 or shot==7 or shot==8)
  if extreme and subjectShot then
    local side=(targetX==px and targetZ==pz) and -1 or 1
    local lateral=math.min(30.0,math.max(22.0,spacing*0.42))
    local axial=math.min(10.0,math.max(6.0,spacing*0.12))
    eye={
      mx+rx*(side*lateral)-fx*axial,
      targetY+10.5,
      mz+rz*(side*lateral)-fz*axial,
    }
  else
    eye=eyeAround(targetX,targetZ,yaw,elev,radius)
  end

  -- Stadium outer-boundary safety ----------------------------------------
  -- The source game is happy to put its very-wide/orbit eye far outside the
  -- battler pair. In a voxel arena that can place the camera *inside* the
  -- venue's outer geometry even though the battle itself remains visible.
  --
  -- Keep every Stadium eye inside the host map when dimensions are known,
  -- and give midpoint-based Stadium shots (wide / high circle / final sweep)
  -- a second proven-safe radial envelope based on Dramatic Shape's own native
  -- rig reach. Pulling the eye inward does NOT make the shot visually tighter:
  -- FOV is derived below from the final distance, so the requested Stadium
  -- framing is preserved optically while physical travel remains safe.
  local familyShot=(shot==3 or shot==6 or shot==9)
  local anchorX,anchorZ=familyShot and mx or targetX,familyShot and mz or targetZ
  local bx,bz=eye[1]-anchorX,eye[3]-anchorZ
  local flat=math.sqrt(bx*bx+bz*bz)
  if flat>1e-4 then
    local maxFlat=flat

    -- Native DS horizontal reach is a known-good physical envelope. 96%
    -- leaves a little breathing room while leaving the captured high orbit
    -- effectively unchanged; only the genuinely over-wide sweeps are pulled
    -- inward on normal/open arenas.
    if familyShot then maxFlat=math.min(maxFlat,baseRadius*0.96) end

    -- Also respect the actual map rectangle. Stay about one cell inside the
    -- world edge so the renderer's outer voxel/border ring cannot swallow the
    -- camera. Scale along the requested ray rather than independently clamping
    -- X/Z, preserving the captured Stadium yaw.
    -- A B-stage carries arena.map only for sky/palette information; no map
    -- geometry is drawn behind the discs. Do not clamp its synthetic camera
    -- against an unrelated Kanto map rectangle.
    local map=(not arena.discs) and arena.map or nil
    if map and type(map.widthCells)=="number" and type(map.heightCells)=="number" then
      local margin=12.0
      local minX,minZ=margin,margin
      local maxX,maxZ=map.widthCells*16.0-margin,map.heightCells*16.0-margin
      local ux,uz=bx/flat,bz/flat
      local edgeLimit=math.huge
      if ux>1e-6 then edgeLimit=math.min(edgeLimit,(maxX-anchorX)/ux)
      elseif ux<-1e-6 then edgeLimit=math.min(edgeLimit,(minX-anchorX)/ux) end
      if uz>1e-6 then edgeLimit=math.min(edgeLimit,(maxZ-anchorZ)/uz)
      elseif uz<-1e-6 then edgeLimit=math.min(edgeLimit,(minZ-anchorZ)/uz) end
      if edgeLimit~=math.huge and edgeLimit>8.0 then
        maxFlat=math.min(maxFlat,edgeLimit)
      end
    end

    if maxFlat<flat then
      local k=maxFlat/flat
      eye[1]=anchorX+bx*k
      eye[3]=anchorZ+bz*k
    end
  end

  focus={
    targetX+rx*focusOffset,
    targetY+focusLift,
    targetZ+rz*focusOffset,
  }

  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(1,math.sqrt(dx*dx+dy*dy+dz*dz))
  local horiz=math.sqrt(dx*dx+dz*dz)
  local fov=2*math.atan(((R.frameH*frameScale)/2)/dist)
  return {eye=eye,focus=focus,fov=fov,curve=0},
         math.atan2(horiz,math.max(1e-3,dy)),1
end

local function cinematicPose(arena,groundY,camera)
  local t=state.time
  local list=shots(); local cycle=0
  for _,s in ipairs(list) do cycle=cycle+shotDuration(s) end
  if cycle<=0 then return nil end
  t=t%cycle
  local shot,localT
  for _,candidate in ipairs(list) do
    local d=shotDuration(candidate)
    if t<d then shot,localT=candidate,t/d break end
    t=t-d
  end
  if not shot then return nil end

  local R=camera.rigFor(arena)
  -- Dramatic Shape marks cramped indoor arenas with the wide rig. Those are
  -- exactly the maps where the target-relative shoulder trajectory can be
  -- redirected through both battlers by surrounding voxels. On those maps,
  -- use a conservative midpoint-based shoulder fallback: it preserves the
  -- subject bias and timing, but never travels down the line between mons.
  local cramped = arena and arena.cam == "wide"
  local mx,mz=arena.mid[1],arena.mid[2]
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local yaw0=math.atan2(R.side,R.back)
  local yaw,radius,elevation,focusBias,frameScale
  local portraitEyeX,portraitEyeZ

  if shot.kind=="orbit" then
    local q=localT; local u=smootherstep(q)
    yaw=yaw0+u*math.pi*2*(shot.turns or 1)*(shot.direction or 1)
    radius=baseRadius*(1.15+0.025*math.sin(q*math.pi*2)+0.012*math.sin(q*math.pi*4+0.7))
    elevation=math.rad(41.5+1.4*math.sin(q*math.pi*2-0.4)+0.6*math.sin(q*math.pi*6))+dw3HeightOffset()
    focusBias=0.025*math.sin(q*math.pi*2+0.8)
    frameScale=1.22+0.018*math.sin(q*math.pi*2+1.2)
  else
    local side=(shot.kind=="enemy") and 1 or -1
    local approach,holdPhase=0,0
    local approachEnd=shot.approach or 0.30
    local holdLength=shot.hold or 0.40
    local holdEnd=approachEnd+holdLength
    local departLength=math.max(1e-4,1-holdEnd)
    if localT<approachEnd then approach=smoothstep(localT/approachEnd)
    elseif localT<=holdEnd then approach=1; holdPhase=(localT-approachEnd)/math.max(1e-4,holdLength)
    else approach=1-smoothstep((localT-holdEnd)/departLength) end
    local travel=math.sin(math.pi*math.min(1,localT/approachEnd))
    if localT>holdEnd then travel=math.sin(math.pi*math.min(1,(1-localT)/departLength))
    elseif localT>=approachEnd then travel=0 end
    local micro=(holdPhase>0) and math.sin(holdPhase*math.pi*2) or 0
    if cramped then
      -- Safe fallback for narrow voxel arenas. Keep the camera farther back,
      -- reduce the inward travel, and avoid constructing an eye point from
      -- the target-to-opponent axis (the path that can be shoved through both
      -- models by geometry correction).
      radius=baseRadius*(1.14-0.10*approach+0.004*micro)
      elevation=math.rad(20.0-3.5*approach+1.2*travel+0.12*micro)+dw3HeightOffset()
      focusBias=side*(0.12+0.40*approach)
      frameScale=1.18-0.08*approach+0.002*micro
    else
      radius=baseRadius*(1.07-0.31*approach+0.006*micro)
      elevation=math.rad(18.0-10.0*approach+3.5*travel+0.18*micro)+dw3HeightOffset()
      focusBias=side*(0.18+0.68*approach)
      frameScale=1.10-0.27*approach+0.003*micro
    end
    if (not cramped) and arena.player and arena.enemy then
      local px,pz=arena.player[1],arena.player[2]
      local ex,ez=arena.enemy[1],arena.enemy[2]
      local tx,tz,ox,oz
      if shot.kind=="enemy" then tx,tz,ox,oz=ex,ez,px,pz else tx,tz,ox,oz=px,pz,ex,ez end
      local fx,fz=ox-tx,oz-tz; local fl=math.sqrt(fx*fx+fz*fz)
      if fl>1e-4 then
        fx,fz=fx/fl,fz/fl
        local rx,rz=-fz,fx
        local arc=side*(math.sin(localT*math.pi)*math.rad(5.0)+micro*math.rad(0.55))*dw3AngleScale()
        local ca,sa=math.cos(arc),math.sin(arc)
        local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
        local flatPortrait=radius*math.cos(elevation)
        portraitEyeX,portraitEyeZ=tx+dx*flatPortrait,tz+dz*flatPortrait
      end
    end
    yaw=yaw0+side*math.rad(12)*dw3AngleScale()
  end

  local focusX,focusZ=mx+R.lookX,mz
  local focusY=(groundY or 0)+R.lookY
  if shot.kind~="orbit" then focusY=focusY+3.6*poseActorScale(R) end
  if focusBias~=0 and arena.player and arena.enemy then
    local px,pz=arena.player[1],arena.player[2]
    local ex,ez=arena.enemy[1],arena.enemy[2]
    local tx=(px+ex)*0.5+(ex-px)*0.5*focusBias
    local tz=(pz+ez)*0.5+(ez-pz)*0.5*focusBias
    focusX,focusZ=focusX+(tx-mx),focusZ+(tz-mz)
  end
  local flat=radius*math.cos(elevation)
  local eye={portraitEyeX or (focusX+math.sin(yaw)*flat),focusY+radius*math.sin(elevation),portraitEyeZ or (focusZ+math.cos(yaw)*flat)}
  local focus={focusX,focusY,focusZ}
  local dist=math.max(1,radius)
  -- Apply the user's DW3 framing only at the final optical stage.  Standard
  -- is bit-for-bit the existing composition; Near and Close narrow the lens
  -- without moving the eye closer to either battler or changing the safe
  -- narrow-arena fallback trajectory.
  local opticalFrameScale=frameScale*dw3FramingScale()
  return {eye=eye,focus=focus,fov=2*math.atan(((R.frameH*opticalFrameScale)/2)/dist),curve=0},
         math.atan2(flat,math.max(1e-3,eye[2]-focusY)),1
end

-- Configure Preset --------------------------------------------------------
-- Gen1Recomp's stock mod-options schema is intentionally flat. Battle
-- Cinematics already has engine_internals permission, so we add one narrowly
-- scoped ManagerState row that opens a second options-style screen. Nothing is
-- written into Gen1Recomp's files: this is a runtime wrapper for this mod only.
local MOD_ID="BATTLE_CINEMATICS"
local PRESET_KEYS={ dw3Framing=true, circleSpeed=true, dw3Height=true, dw3Angle=true }

local function schemaRow(manager,key)
  local loader=manager and manager.game and manager.game.mods
  local schema=loader and loader.optionSchemas and loader.optionSchemas[MOD_ID]
  for _,row in ipairs(schema or {}) do
    if row.key==key then return row end
  end
end

local function choiceLabel(manager,row)
  if not row then return "----" end
  local cur=manager:optionValue(MOD_ID,row)
  for _,choice in ipairs(row.choices or {}) do
    if choice[2]==cur then return choice[1] end
  end
  return ((row.choices or {})[1] or {})[1] or "----"
end

local function stepChoice(manager,row,dir)
  if not row then return end
  local choices=row.choices or {}
  if #choices==0 then return end
  local cur=manager:optionValue(MOD_ID,row)
  local index=1
  for i,choice in ipairs(choices) do
    if choice[2]==cur then index=i break end
  end
  index=((index-1+(dir or 1))%#choices)+1
  manager:setOption(MOD_ID,row.key,choices[index][2])
end

local okRows,OptionRows=pcall(require,"src.ui.OptionRows")
local okFont,Font=pcall(require,"src.render.Font")
local okTheme,Theme=pcall(require,"src.ui.Theme")
local PresetConfigState={}
PresetConfigState.__index=PresetConfigState
PresetConfigState.isOpaque=true
PresetConfigState.screenId="BattleCinematicsPresetConfig"

function PresetConfigState.new(manager,preset)
  local self=setmetatable({},PresetConfigState)
  self.manager=manager
  self.game=manager.game
  self.preset=preset or "dw3"
  self.cursor=1
  self.scroll=0
  self.rows={}

  if self.preset=="dw3" then
    local keys={"dw3Framing","circleSpeed","dw3Height","dw3Angle"}
    for _,key in ipairs(keys) do
      local def=schemaRow(manager,key)
      self.rows[#self.rows+1]={
        id=key,
        label=def and def.label or key,
        value=function() return choiceLabel(manager,def) end,
        step=function(_,dir) stepChoice(manager,def,dir); return true end,
      }
    end
    self.rows[#self.rows+1]={
      id="__preset_reset", label="RESET TO DEFAULT", value=function() return "" end,
      activate=function()
        for _,key in ipairs(keys) do
          local def=schemaRow(manager,key)
          if def then manager:setOption(MOD_ID,key,def.default) end
        end
        if manager.notify then manager:notify("DW3 DEFAULTS RESTORED") end
      end,
    }
  elseif self.preset=="stadium" then
    self.rows[#self.rows+1]={
      id="__stadium_info", label="STADIUM CLASSIC", value=function() return "SOURCE FAITHFUL" end,
    }
    self.rows[#self.rows+1]={
      id="__stadium_cycle", label="PASSIVE CYCLE", value=function() return "31.87 SECONDS" end,
    }
  else
    -- Contextual second page is live now; Hero-specific controls can be added
    -- without growing the main options list when that preset is tuned next.
    self.rows[#self.rows+1]={
      id="__hero_future", label="HERO PORTRAIT", value=function() return "NO OPTIONS YET" end,
    }
  end
  return self
end

function PresetConfigState:update(dt)
  local input=self.game.input
  local n=#self.rows
  if input:wasPressed("b") then self.game.stack:pop(); return end
  if n==0 then return end
  if input:wasPressed("up") then
    self.cursor=((self.cursor-2)%n)+1
  elseif input:wasPressed("down") then
    self.cursor=(self.cursor%n)+1
  elseif input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("a") then
    local row=self.rows[self.cursor]
    local dir=input:wasPressed("left") and -1 or 1
    if row.activate and input:wasPressed("a") then row.activate()
    elseif row.step then row.step(self.game,dir) end
  end
  if okRows and OptionRows then
    self.scroll=OptionRows.clampScroll(self.cursor,self.scroll or 0,n,nil)
  end
end

function PresetConfigState:draw()
  if okRows and OptionRows then
    OptionRows.draw(self.game,self.rows,self.cursor,self.scroll or 0)
    if okFont and Font then
      love.graphics.setColor(0,0,0,1)
      Font.draw(self.preset=="dw3" and "DW3 SETTINGS B:DONE" or (self.preset=="stadium" and "STADIUM SETTINGS B:DONE" or "HERO SETTINGS B:DONE"),8,136)
      love.graphics.setColor(1,1,1,1)
    end
    return
  end
end

local okManager,ManagerState=pcall(require,"src.mods.ManagerState")
if okManager and ManagerState then
  -- Provider is refreshed on hot reload; wrapper itself is installed once.
  ManagerState.__bcPresetConfigProvider=function(manager)
    local preset=mod.options:get("preset") or "dw3"
    manager.game.stack:push(PresetConfigState.new(manager,preset))
  end
  if not ManagerState.__bcPresetConfigWrapped then
    local originalBuildOptionRows=ManagerState.buildOptionRows
    ManagerState.buildOptionRows=function(self,m,schema)
      local rows=originalBuildOptionRows(self,m,schema)
      if not m or m.id~=MOD_ID then return rows end

      local filtered={}
      for _,row in ipairs(rows) do
        if not PRESET_KEYS[row.id] then
          filtered[#filtered+1]=row
        end
      end

      local insertAt=#filtered
      for i,row in ipairs(filtered) do
        if row.id=="preset" then insertAt=i+1 break end
      end
      local configure={
        id="__bc_configure_preset",
        label="CONFIGURE PRESET",
        value=function()
          local p=mod.options:get("preset") or "dw3"
          if p=="dw3" then return "DW3 CLASSIC" end
          if p=="stadium" then return "STADIUM CLASSIC" end
          return "HERO PORTRAIT"
        end,
        activate=function()
          local provider=ManagerState.__bcPresetConfigProvider
          if provider then provider(self) end
        end,
      }
      table.insert(filtered,insertAt,configure)
      return filtered
    end
    ManagerState.__bcPresetConfigWrapped=true
  end
else
  mod.log:warn("Configure Preset menu unavailable on this Gen1Recomp build")
end

local Game=require("src.core.Game")

-- Install the same cinematic wrapper into every compatible camera backend.
-- This is the key compatibility seam: we no longer assume that the battle
-- renderer carrying the active BattleCam table must have the DRAMATIC_SHAPE
-- manifest id. Whichever backend actually asks for a rig receives the same
-- Battle Cinematics choreography, using that backend's own rig constants.
local function installBackendCamera(backend)
  local BattleCam=backend.BattleCam
  if BattleCam.__bcStandaloneDW3Wrapped then return end
  local originalRig=BattleCam.rig
  BattleCam.rig=function(arena,groundY,canonical)
    local rawBase,rawPitch=originalRig(arena,groundY,canonical)
    if canonical then return rawBase,rawPitch end

    state.rigSeen=true; state.noRig=0
    state.backendId=backend.id

    -- Compatibility contract: when BC is enabled, Dramaless is normalized to
    -- the exact upstream camera geometry that all 0.7.3 choreography was tuned
    -- against. When BC is disabled, the fork's own camera is returned untouched.
    local base,pitch=rawBase,rawPitch
    if backend.id=="DRAMALESS_SHAPE" and enabled() then
      local normalized,normalizedPitch=
        drAmalessNormalizedBase(backend,arena,groundY,BattleCam,false)
      if normalized then base,pitch=normalized,normalizedPitch end
    end

    if state.blend<=0 or type(base)~="table" then return base,pitch end

    -- Preset math also sees the upstream reference rig under Dramaless. This
    -- prevents its fork-specific back/height changes from stretching BC radii,
    -- orbit heights, safety envelopes or optical framing.
    local poseCamera=bcPoseCamera(backend,BattleCam)

    local cine,cinePitch,shotWeight
    -- Priority is intentionally additive: a confirmed faint owns the camera
    -- only after the move camera releases it, then an actual Stadium attack,
    -- then the established BC Hero intro, then the ordinary passive preset.
    -- Proven v0.7.3 intro/preset math remains intact.
    if state.faint.active then
      cine,cinePitch,shotWeight=faintCameraPose(arena,groundY,poseCamera)
    elseif state.attack.active then
      cine,cinePitch,shotWeight=stadiumAttackPose(arena,groundY,poseCamera)
    elseif state.intro.active then
      cine,cinePitch,shotWeight=dynamicIntroPose(arena,groundY,poseCamera)
    elseif selectedPreset()=="portrait_test" then
      cine,cinePitch,shotWeight=portraitTestPose(arena,groundY,poseCamera)
    elseif selectedPreset()=="stadium" then
      cine,cinePitch,shotWeight=stadiumClassicPose(arena,groundY,poseCamera)
    else
      cine,cinePitch,shotWeight=cinematicPose(arena,groundY,poseCamera)
    end
    if not cine then return base,pitch end
    local w=state.blend*(shotWeight or 1)

    -- Zero-travel dead-zone safety -----------------------------------------
    -- Hero Portrait / Battle Intro already needed this philosophy on cramped
    -- rigs. v0.7.3's Stadium safety protected map boundaries, but Route 22/24
    -- exposed a second failure mode: Stadium's *valid* eye positions can still
    -- leave the renderer's 3D camera volume and reveal the original 2D sprite
    -- layer. Apply the stronger known-safe base-eye fallback to every Stadium-
    -- derived camera while the arena is extreme. Attack/Faint keep their full
    -- choreography everywhere else.
    if arena and arena.player and arena.enemy then
      local dx=arena.enemy[1]-arena.player[1]
      local dz=arena.enemy[2]-arena.player[2]
      local spacing=math.sqrt(dx*dx+dz*dz)
      if arena.cam=="wide" or spacing>56.0 then
        local heroSafety=state.intro.active or selectedPreset()=="portrait_test"
        -- B-stage arenas are synthetic carried stages, not cramped map rigs.
        -- Across every supported backend using this arena contract, let passive
        -- Stadium Classic use its authored physical eye path instead of the
        -- Route 22/24 zero-travel fallback.
        local passiveStadium=((not state.intro.active) and selectedPreset()=="stadium")
        local stadiumSafety=state.attack.active or state.faint.active or
          (passiveStadium and not arena.discs)
        if heroSafety or stadiumSafety then
          local locked,lockedPitch=zeroTravelCamera(base,cine,w)
          return locked,lockedPitch or mix(pitch,cinePitch,w)
        end
      end
    end

    return mixCamera(base,cine,w),mix(pitch,cinePitch,w)
  end
  BattleCam.__bcStandaloneDW3Wrapped=true
  mod.log:info("camera backend connected: %s %s",backend.id,tostring(backend.version or ""))
  if backend.id=="DRAMALESS_SHAPE" then
    mod.log:info("Dramaless camera normalized to Battle Cinematics 0.7.3 reference geometry")
    mod.log:info("Dramaless actor-height framing normalization active")
  end
end

for _,backend in ipairs(backends) do installBackendCamera(backend) end

mod.hooks:wrap("input.step",function(nextFn,game,dt)
  local result=nextFn(game,dt)
  dt=cameraDelta(game,dt)
  state.noRig=state.noRig+dt
  if state.noRig>0.75 and state.rigSeen then
    state.rigSeen=false; resetBattle()
  end

  local battle=state.battle

  -- Stadium attack camera -------------------------------------------------
  -- battle.move_used arms the module, but camera ownership begins only when
  -- the actual visual animation starts. This avoids timing out while the player
  -- is reading/advancing the move announcement and naturally ignores failed or
  -- nonvisual moves that never start AnimPlayer.
  if state.attack.pending and battle and battle.animPlaying then
    local sideMatches=true
    if battle.animAttackerIsPlayer~=nil then
      sideMatches=(not not battle.animAttackerIsPlayer)==(state.attack.side=="player")
    end
    if sideMatches then beginAttack() end
  end

  if state.attack.active then
    state.attack.time=state.attack.time+dt

    local sideMatches=true
    if battle and battle.animAttackerIsPlayer~=nil then
      sideMatches=(not not battle.animAttackerIsPlayer)==(state.attack.side=="player")
    end
    -- Deliberately do not require animName == moveId. Charge animations and
    -- external Stadium FX replacements may use a different animation id while
    -- retaining the same attacker, and the camera should follow them.
    local animationMatches=battle and battle.animPlaying and sideMatches

    if animationMatches then
      if not state.attack.sawAnimation then
        state.attack.sawAnimation=true
        state.attack.animTotal=0
        local player=battle.animPlayer
        if player and type(player.steps)=="table" then
          for _,step in ipairs(player.steps) do
            state.attack.animTotal=state.attack.animTotal+math.max(0,tonumber(step.dur) or 0)
          end
        end
        state.attack.tail=0
        logDiagnostic("stadium attack animation acquired: "..tostring(state.attack.animTotal).." frames")
      end

      local player=battle.animPlayer
      local elapsed=player and tonumber(player.elapsed) or nil
      if elapsed and state.attack.animTotal>0 then
        -- AnimPlayer.elapsed advances on the accelerated battle logic clock.
        -- Treat it as the choreography target, but limit the physical camera
        -- to the amount of progress that can occur in real presentation time.
        local targetProgress=math.max(0,math.min(1,elapsed/state.attack.animTotal))
        state.attack.progress=advanceAttackProgress(
          state.attack.progress,targetProgress,state.attack.animTotal,dt)
      else
        -- Defensive fallback for alternate animation players that do not expose
        -- compiled step durations. state.attack.time already uses camera time.
        state.attack.progress=math.max(state.attack.progress,math.min(0.98,state.attack.time/2.0))
      end
      state.attack.tail=0
    elseif state.attack.sawAnimation then
      -- Fast-forward may finish the battle animation before the real-time camera
      -- has traversed the shot. Finish the camera choreography at presentation
      -- speed; a later battle.move_used event can still replace it immediately.
      if state.attack.animTotal>0 and state.attack.progress<1 then
        state.attack.progress=advanceAttackProgress(
          state.attack.progress,1,state.attack.animTotal,dt)
        state.attack.tail=0
      else
        state.attack.progress=1
        state.attack.tail=state.attack.tail+dt
      end
      if state.attack.progress>=1 and state.attack.tail>=0.25 then
        local faintHandoff=state.faint.pending and faintCameraOn()
        clearAttack()
        if faintHandoff then
          beginFaint()
          logDiagnostic("stadium attack camera complete -> faint camera")
        else
          state.blend=0
          state.idle=0
          state.active=false
          logDiagnostic("stadium attack camera complete")
        end
      end
    end

    if state.attack.active then
      state.blend=1
      return result
    end
  end

  -- Faint Camera -----------------------------------------------------------
  -- With Attack Camera enabled, the hand-off above keeps the defeated Pokemon
  -- in view continuously from the finishing attack into its HP drain. With
  -- Attack Camera disabled, do not reveal the KO early: wait until the visible
  -- bar actually begins draining (or the engine enters the faint step).
  if state.faint.pending and not state.attack.active then
    local battler=state.faint.battler
    local shown=battler and tonumber(battler.shownHP) or nil
    local drainStarted=(shown~=nil and state.faint.shownStart~=nil
                        and shown<state.faint.shownStart)
    if drainStarted or (battler and battler.fainted) then
      beginFaint()
    end
  end

  if state.faint.active then
    local battler=state.faint.battler
    state.faint.time=state.faint.time+dt

    -- If the slot has already been replaced, the subject no longer exists.
    local current=nil
    if battle then current=state.faint.side=="player" and battle.player or battle.enemy end
    if current and battler and current~=battler then
      clearFaint()
      state.blend=0; state.idle=0; state.active=false
      logDiagnostic("faint camera cleared: battler replaced")
    else
      local shown=battler and tonumber(battler.shownHP) or nil
      if not state.faint.zeroReached then
        if (shown~=nil and shown<=0) or (battler and battler.fainted) then
          state.faint.zeroReached=true
          state.faint.zeroTime=0
          logDiagnostic("faint camera: visible HP reached zero")
        end
      else
        state.faint.zeroTime=state.faint.zeroTime+dt
      end

      local anim,showing,hasStadiumApi=stadiumFaintStatus(state.faint.side)
      if anim=="faint" then state.faint.stadiumSeen=true end

      local done=false
      if state.faint.stadiumSeen then
        -- Dramatic Shape 1.8+ keeps the Stadium model visible until its own
        -- species-specific faint animation has actually finished. Follow that
        -- live signal instead of guessing a universal collapse duration.
        if showing then
          state.faint.stadiumGone=0
        else
          state.faint.stadiumGone=state.faint.stadiumGone+dt
          if state.faint.stadiumGone>=0.30 then done=true end
        end
      elseif state.faint.zeroReached and state.faint.zeroTime>=2.35 then
        -- Generic/older-backend fallback: enough time for a readable KO hold
        -- without assuming Stadium.animOf/showing exists or a 3D pack is loaded.
        done=true
      end

      -- Bounded safety for an alternate backend that exposes a held "faint"
      -- state but never reports the model leaving the field.
      if state.faint.time>=15.0 then done=true end

      if done then
        clearFaint()
        state.blend=0
        state.idle=0
        state.active=false
        logDiagnostic("faint camera complete"..(hasStadiumApi and " (stadium-aware)" or " (fallback)"))
      else
        state.blend=1
        return result
      end
    end
  end

  -- Battle Intro ----------------------------------------------------------
  if battle and battleIntroOn() and state.rigSeen then
    local enemySending=not not battle.enemySendingOut
    local playerSending=not not battle.sendingOut

    -- Existing BC Hero behaviour is deliberately preserved: each side starts
    -- only once that side's 3D model is actually visible. This handles wild
    -- encounters, trainer send-outs and later switches.
    if state.intro.pendingEnemy and not battle.showEnemyTrainer and not enemySending then
      startIntro("enemy","hero")
    elseif state.intro.pendingPlayer and not playerSending and battle.player and not battle.showPlayerBack then
      startIntro("player","hero")
    end
    state.intro.enemyWasSending=enemySending
    state.intro.playerWasSending=playerSending
  end

  if state.intro.active then
    local introScale=introSpeedScale()
    state.intro.time=state.intro.time+dt*introScale
    state.blend=chase(state.blend,1,dt,BLEND_TIME/introScale)
    if state.intro.time>=HERO_INTRO_DURATION then
      local completed=state.intro.style..(state.intro.side and (" / "..state.intro.side) or "")
      clearIntro()
      state.blend=0
      state.idle=0
      state.active=false
      logDiagnostic("battle intro complete: "..tostring(completed))
    end
    return result
  end

  -- During an opening BC Hero intro the selected idle preset waits until its
  -- queued cinematography has completed. Switch portraits retain v0.7.3 logic.
  local introWaiting=battleIntroOn() and
    (state.intro.pendingEnemy or state.intro.pendingPlayer)
  if state.rigSeen and enabled() and not introWaiting then
    if not state.active then
      state.idle=state.idle+dt
      if state.idle>=idleDelay() then
        state.active=true; state.time=0
        logDiagnostic("cinematic active")
      end
    else state.time=state.time+dt end
  elseif not enabled() or introWaiting then
    state.active=false; state.idle=0
  end
  state.blend=chase(state.blend,(enabled() and state.active) and 1 or 0,dt,BLEND_TIME)
  return result
end,25,"BATTLE_CINEMATICS")

-- Input policy ------------------------------------------------------------
-- RESET CAMERA controls the selected idle preset. INTRO CANCEL controls
-- Battle Intro independently, allowing intros to remain uninterruptible,
-- dismiss only on a committed move/item, or dismiss on any input.
local function resetMode()
  return mod.options:get("inputReturn") or "confirmed"
end
local function cancelActiveIntro(reason)
  if not state.intro.active then return false end
  local side=state.intro.side
  clearIntro()
  state.blend=0
  state.idle=0
  state.active=false
  logDiagnostic("battle intro reset ("..tostring(reason).."): "..tostring(side))
  return true
end
local function confirmedAction()
  if state.intro.active then
    if introResetMode()=="confirmed" then cancelActiveIntro("move/item") end
    return
  end
  if resetMode() ~= "off" then
    activity()
    logDiagnostic("move/item returned camera")
  end
end
local function rawActivity()
  if state.intro.active then
    if introResetMode()=="any" then cancelActiveIntro("any input") end
    return
  end
  if resetMode()=="any" then activity() end
end

local function wrapMethod(tbl,name,handler)
  local inner=tbl and tbl[name]
  if type(inner)~="function" or tbl["__bc_"..name] then return end
  tbl[name]=function(self,...)
    handler()
    return inner(self,...)
  end
  tbl["__bc_"..name]=true
end
wrapMethod(Game,"keypressed",rawActivity)
wrapMethod(Game,"gamepadpressed",rawActivity)
wrapMethod(Game,"touchpressed",rawActivity)
wrapMethod(Game,"mousepressed",rawActivity)

-- Mouse/touch callbacks can bypass Game methods on some Android builds.
if love and not love.__bcInputWrapped then
  local oldTouch=love.touchpressed
  love.touchpressed=function(...) rawActivity(); if oldTouch then return oldTouch(...) end end
  local oldMouse=love.mousepressed
  love.mousepressed=function(...) rawActivity(); if oldMouse then return oldMouse(...) end end
  love.__bcInputWrapped=true
end

-- Sanctioned battle commitments. These wrappers do not alter the action;
-- they only apply the selected reset policy before the action is rendered.
local okBattle,BattleState=pcall(require,"src.battle.BattleState")
if okBattle and BattleState then
  wrapMethod(BattleState,"resolveTurn",confirmedAction)
  wrapMethod(BattleState,"tryRun",confirmedAction)
  wrapMethod(BattleState,"openItems",confirmedAction)
  wrapMethod(BattleState,"openParty",confirmedAction)
else
  mod.log:warn("move/item hooks unavailable; ANY INPUT remains supported")
end

-- Battle cinematography lifecycle ------------------------------------------
mod.events:on("battle.started",function(ev)
  state.battle=ev and ev.battle or nil
  state.intro.initial=true
  clearIntro()
  clearAttack()
  clearFaint()
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false

  local style=battleIntroStyle()
  if style=="hero" then
    state.intro.pendingEnemy=true
    state.intro.pendingPlayer=true
  end
  state.idle,state.time,state.active,state.blend=0,0,false,0
  logDiagnostic("battle started; intro style queued: "..style)
end)

mod.events:on("battle.battler_switched",function(ev)
  -- A replacement is an unambiguous end to any KO hold.
  if state.faint.pending or state.faint.active then clearFaint() end
  -- A no-animation move may leave the attack module armed; switching is an
  -- unambiguous lifecycle boundary, so discard that stale arm before queuing
  -- any preserved BC Hero switch portrait.
  if state.attack.pending then clearAttack() end
  -- Preserve the proven BC Hero switch portraits exactly.
  if battleIntroStyle()~="hero" or not ev then return end
  state.battle=ev.battle or state.battle
  local side=ev.side and ev.side.index
  if side==1 then queueIntro("player")
  elseif side==2 then queueIntro("enemy") end
  state.idle,state.time,state.active,state.blend=0,0,false,0
end)

mod.events:on("battle.fainted",function(ev)
  if not ev or not ev.battler then return end
  state.battle=ev.battle or state.battle
  local battle=ev.battle or state.battle
  local battler=ev.battler
  local side=nil
  if battler.isPlayer~=nil then
    side=battler.isPlayer and "player" or "enemy"
  elseif battle and battler==battle.player then side="player"
  elseif battle and battler==battle.enemy then side="enemy" end
  queueFaint(side,battler)
end)

mod.events:on("battle.move_used",function(ev)
  if not ev or not ev.user then return end
  state.battle=ev.battle or state.battle
  local side=ev.user.isPlayer and "player" or "enemy"
  local moveId=ev.move and ev.move.id or nil
  local mode=classifyAttackMove(ev.battle or state.battle,ev.move)
  armAttack(side,moveId,mode)
end)

mod.events:on("battle.turn_ended",function()
  -- Failed/nonvisual moves can legitimately never hand us AnimPlayer. Do not
  -- let that stale arm attach itself to the next animation from the same side.
  if state.attack.pending and not state.attack.active then clearAttack() end
end)

mod.events:on("battle.ended",function()
  state.battle=nil
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  clearIntro()
  clearAttack()
  clearFaint()
end)

mod.exports.version="0.7.7"
mod.exports.activity=activity
mod.log:info("Battle Cinematics v0.7.7 connected (%d camera backend%s)",#backends,#backends==1 and "" or "s")
