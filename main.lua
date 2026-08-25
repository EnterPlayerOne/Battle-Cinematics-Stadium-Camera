-- Battle Cinematics v1.2.1
-- Copyright (c) 2026 EnterPlayerOne. See LICENSE for permissions and restrictions.
-- Based exactly on the released v0.7.9 camera behaviour.
-- Clean companion mod. It never modifies a renderer's files.
--
-- Compatible Gen1 live-3D battle camera hosts currently mapped:
--   DRAMATIC_SHAPE          Dramatic Shape family
--   DRAMALESS_SHAPE         Dramaless Shape
--   BATTLE_ART_VOXEL_FORK   Battle Art Voxel Fork
--   potato_voxel            PotatoVoxel
--   VOXEL_ASCENDANT         Voxel Ascendant
--
-- All are optional at manifest level so any one compatible implementation can
-- satisfy Battle Cinematics. Runtime discovery still feature-tests the exported
-- BattleCam contract (rig + rigFor) before accepting a host. Gold/Randy uses its
-- separately gated live-world adapter below.
local mod = ...
local DIAGNOSTIC_BUILD = true
local DIAGNOSTIC_HUD = false

local BACKEND_IDS = { "DRAMATIC_SHAPE", "DRAMALESS_SHAPE", "BATTLE_ART_VOXEL_FORK", "potato_voxel", "VOXEL_ASCENDANT" }
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

-- Stadium2 Importer Gen1 live-presentation adapter -------------------------
-- STADIUM2_IMPORTER is not a Shape-family BattleCam host. It owns a complete
-- Stadium2 renderer and exposes the exact Camera table used by its live scene.
-- Build only the small BC-facing BattleCam semantic seam here; a later bridge
-- replaces Camera.frame() only while the importer's own Gen1 battle is active.
-- Gold uses the separately gated Stadium2 Importer Gen2 adapter below; Randy
-- remains an independent Gold provider when that host is active instead.
;(function()
  local okGV,GV=pcall(require,"src.core.GameVersion")
  if okGV and GV and type(GV.generation)=="function" then
    local okG,g=pcall(GV.generation)
    if okG and tonumber(g) and tonumber(g)~=1 then return end
  end
  local provider=mod.find("STADIUM2_IMPORTER")
  if not provider then return end
  local exports=provider.exports or {}
  local presentation=exports.presentation
  local Camera=type(presentation)=="table" and presentation.Camera or nil
  if type(Camera)~="table" or type(Camera.frame)~="function"
      or type(exports.battleStatus)~="function" then return end

  local host={provider=provider,exports=exports,presentation=presentation,
    Camera=Camera,providerFrame=Camera.frame,base=nil}
  local BattleCam={still=false,steerable=true,t=0,orbit=0,zoom=1,pitch=0}

  BattleCam.rigFor=function(_arena)
    local r=type(Camera.RIG)=="table" and Camera.RIG or {}
    return {side=tonumber(r.side) or 41.98,back=tonumber(r.back) or 41.16,
      height=tonumber(r.height) or 28.48,lookX=tonumber(r.lookX) or -3.24,
      lookY=tonumber(r.lookY) or -1.35,frameH=tonumber(r.frameH) or 53.40}
  end

  local function copyCamera(cam)
    if type(cam)~="table" or type(cam.eye)~="table" or type(cam.focus)~="table" then
      return nil
    end
    return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},
      focus={cam.focus[1],cam.focus[2],cam.focus[3]},up={0,1,0},
      fov=tonumber(cam.fov) or math.rad(55),curve=tonumber(cam.curve) or 0}
  end
  BattleCam.rig=function(_arena,_groundY,_canonical)
    local cam=copyCamera(host.base)
    if not cam then return nil,nil end
    local dx=(cam.eye[1] or 0)-(cam.focus[1] or 0)
    local dz=(cam.eye[3] or 0)-(cam.focus[3] or 0)
    local flat=math.sqrt(dx*dx+dz*dz)
    local pitch=math.atan2(flat,math.max(1e-3,(cam.eye[2] or 0)-(cam.focus[2] or 0)))
    return cam,pitch
  end

  local pos=type(Camera.positions)=="table" and Camera.positions or {}
  local pp=type(pos.player)=="table" and pos.player or {0,0,24}
  local ep=type(pos.enemy)=="table" and pos.enemy or {0,0,-24}
  local px,pz=tonumber(pp[1]) or 0,tonumber(pp[3]) or 24
  local ex,ez=tonumber(ep[1]) or 0,tonumber(ep[3]) or -24
  host.arena={player={px,pz},enemy={ex,ez},
    mid={(px+ex)*0.5,(pz+ez)*0.5},cam="stadium2_importer",
    stadium2Importer=true}

  local backend={id="STADIUM2_IMPORTER",version=provider.version,
    BattleCam=BattleCam,stadium2Importer=true}
  host.backend=backend
  backends.__stadium2importer=host
  backends[#backends+1]=backend
  mod.log:warn("[BC GEN1] Stadium2 Importer live-presentation adapter discovered")
end)()


-- Stadium2 Importer Gen2 live-presentation adapter --------------------------
-- Unlike Randy, the importer installs its Gold BattleState renderer lazily
-- after the real playthrough is active.  Do not wrap BattleState.drawWidescreen
-- here: the importer's later install legitimately replaces that method while
-- it owns the Stadium scene.  Instead capture the importer's exported Gen2
-- Scene object itself; its own draw path populates scene.screen, giving BC the
-- exact live presentation state without any load-order race.
;(function()
  local okGV,GV=pcall(require,"src.core.GameVersion")
  if not (okGV and GV and type(GV.generation)=="function") then return end
  local okG,g=pcall(GV.generation)
  if not (okG and tonumber(g)==2) then return end
  local provider=mod.find("STADIUM2_IMPORTER")
  if not provider then return end
  local exports=provider.exports or {}
  if type(exports.battleEnabled)=="function" then
    local okOn,on=pcall(exports.battleEnabled)
    if okOn and on==false then return end
  end
  local presentation=exports.presentation
  local Camera=type(presentation)=="table" and presentation.Camera or nil
  if type(Camera)~="table" or type(Camera.frame)~="function"
      or type(exports.battleStatus)~="function" then return end

  local okGen2,Gen2=pcall(require,"mods.STADIUM2_IMPORTER.lib.gen2_battle")
  local Scene=okGen2 and type(Gen2)=="table" and Gen2.Scene or nil
  if type(Scene)~="table" or type(Scene.new)~="function" then return end

  local function fovFromFrame(frame)
    local p=type(frame)=="table" and frame.projection or nil
    local f=p and math.abs(tonumber(p[6]) or 0) or 0
    if f>1e-5 then return 2*math.atan(1/f) end
    return math.rad(55)
  end
  local function copyFrame(cam)
    if type(cam)~="table" or type(cam.eye)~="table" or type(cam.focus)~="table" then
      return nil
    end
    return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},
      focus={cam.focus[1],cam.focus[2],cam.focus[3]},up={0,1,0},
      fov=tonumber(cam.fov) or fovFromFrame(cam),curve=tonumber(cam.curve) or 0}
  end

  local pos=type(Camera.positions)=="table" and Camera.positions or {}
  local pp=type(pos.player)=="table" and pos.player or {0,0,24}
  local ep=type(pos.enemy)=="table" and pos.enemy or {0,0,-24}
  local px,pz=tonumber(pp[1]) or 0,tonumber(pp[3]) or 24
  local ex,ez=tonumber(ep[1]) or 0,tonumber(ep[3]) or -24
  local arena={player={px,pz},enemy={ex,ez},mid={(px+ex)*0.5,(pz+ez)*0.5},
    cam="stadium2_importer",stadium2Importer=true}

  local gold={provider=provider,providerKind="stadium2_importer",exports=exports,
    presentation=presentation,Camera=Camera,originalCameraFrame=Camera.frame,
    arena=arena,scene=nil,base=nil,lastVisible=nil,lastManual=nil,manualWas=false,
    resume=1,frames=0,bcFrames=0,manualFrames=0,markerFrames=0,error=nil,
    battleLive=false,frameWidth=nil,frameHeight=nil}
  gold.isGold=function() return true end

  -- Capture the actual importer-owned scene object.  Gen2.ensure() calls this
  -- table's new() method, and the importer's own drawWidescreen subsequently
  -- writes scene.screen before BC ever reads it.
  if not Scene.__bcStadium2ImporterSceneTracked then
    Scene.__bcStadium2ImporterSceneTracked=true
    local originalNew=Scene.new
    Scene.new=function(...)
      local scene=originalNew(...)
      gold.scene=scene
      return scene
    end
    local originalRelease=Scene.release
    if type(originalRelease)=="function" then
      Scene.release=function(self,...)
        local out=originalRelease(self,...)
        if gold.scene==self then gold.scene=nil end
        return out
      end
    end
  end

  local BattleCam={still=false,steerable=true,t=0,orbit=0,zoom=1,pitch=0}
  BattleCam.rigFor=function(_arena)
    local r=type(Camera.RIG)=="table" and Camera.RIG or {}
    return {side=tonumber(r.side) or 41.98,back=tonumber(r.back) or 41.16,
      height=tonumber(r.height) or 28.48,lookX=tonumber(r.lookX) or -3.24,
      lookY=tonumber(r.lookY) or -1.35,frameH=tonumber(r.frameH) or 53.40}
  end
  local function fallbackBase()
    local r=type(Camera.RIG)=="table" and Camera.RIG or {}
    return {eye={tonumber(r.side) or 41.98,tonumber(r.height) or 28.48,
        tonumber(r.back) or 41.16},
      focus={tonumber(r.lookX) or -3.24,tonumber(r.lookY) or -1.35,0},
      up={0,1,0},fov=math.rad(55),curve=0}
  end
  BattleCam.rig=function(_arena,_groundY,_canonical)
    local cam=copyFrame(gold.base) or fallbackBase()
    local dx=(cam.eye[1] or 0)-(cam.focus[1] or 0)
    local dz=(cam.eye[3] or 0)-(cam.focus[3] or 0)
    local flat=math.sqrt(dx*dx+dz*dz)
    local pitch=math.atan2(flat,math.max(1e-3,(cam.eye[2] or 0)-(cam.focus[2] or 0)))
    return cam,pitch
  end
  gold.BattleCam=BattleCam

  -- Minimal semantic facade for the existing, already-proven Gold event/
  -- Attack/Faint/Send-In adapter.  It reads the importer's real screen; it does
  -- not make the importer imitate Randy's renderer.
  local BattleCinematic={}
  BattleCinematic.reset=function()
    if type(Camera.recentre)=="function" then pcall(Camera.recentre) end
    if type(Camera.reset)=="function" then pcall(Camera.reset) end
  end
  local OverworldBattle={}
  OverworldBattle.cameraContext=function()
    -- The captured importer Scene is the live ownership signal.  Do NOT call
    -- exports.battleStatus() here: on Stadium2 Importer that API validates the
    -- persistent model cache (including key enumeration) and is intentionally
    -- a status/query surface, not a per-frame camera primitive.
    if not gold.battleLive then return nil end
    local scene=gold.scene
    local screen=type(scene)=="table" and scene.screen or nil
    if type(screen)~="table" then return nil end
    return {arena=arena,groundY=0,screen=screen,battle=screen.battle}
  end
  gold.BattleCinematic=BattleCinematic
  gold.OverworldBattle=OverworldBattle
  gold.VoxelScene={}
  gold.Voxel3D={}
  gold.FirstPerson=nil
  gold.providerFrame=function(_dt)
    local w=tonumber(gold.frameWidth)
    local h=tonumber(gold.frameHeight)
    if not (w and h and w>0 and h>0) then
      local G=love and love.graphics
      w=G and G.getWidth and G.getWidth() or 1280
      h=G and G.getHeight and G.getHeight() or 720
    end
    local raw=gold.originalCameraFrame(w,h)
    return copyFrame(raw),arena.mid[1],arena.mid[2]
  end
  gold.providerRender=nil

  local backend={id="BC_GOLD_STADIUM2_IMPORTER",version=provider.version,
    BattleCam=BattleCam,OverworldBattle=OverworldBattle,gold=true,
    stadium2Importer=true}
  gold.backend=backend
  backends.__gold=gold
  backends[#backends+1]=backend
  mod.log:warn("[BC GOLD] Stadium2 Importer scene-backed Gen2 adapter discovered")
end)()

-- Gold compatibility Test 5B ------------------------------------------------
-- RandyADR's STADIUM2_OVERWORLD_MODELS is a presentation host, not a BC
-- camera preset.  Build a tiny synthetic BattleCam contract around its live
-- Gold battle camera so the *released BC 1.0.3 director* can run unchanged
-- above that host.  All helper locals live inside this closure so we do not
-- consume the already-tight main-chunk local-variable budget.
if #backends==0 then
(function()
  local provider=mod.find("STADIUM2_OVERWORLD_MODELS")
  if not provider then return end
  local exports=provider.exports or {}
  local V=exports.lib
  if type(V)~="table" or type(V.require)~="function" then return end
  -- Test 4B installs this adapter only when no proven Gen-1 BC backend was
  -- discovered. Test 4 incorrectly required V.game.world during mod load;
  -- Randy's exported library does not expose that as a reliable load-time
  -- generation discriminator, so the adapter was discarded before runtime.
  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local BattleCinematic=req("BattleCinematic")
  local OverworldBattle=req("OverworldBattle")
  local VoxelScene=req("VoxelScene")
  local Voxel3D=req("Voxel3D")
  local FirstPerson=req("FirstPerson")
  if not (BattleCinematic and OverworldBattle and VoxelScene and Voxel3D
      and type(BattleCinematic.frame)=="function"
      and type(OverworldBattle.cameraContext)=="function") then return end

  local gold={
    provider=provider,V=V,BattleCinematic=BattleCinematic,
    OverworldBattle=OverworldBattle,VoxelScene=VoxelScene,Voxel3D=Voxel3D,
    FirstPerson=FirstPerson,providerFrame=BattleCinematic.frame,
    providerRender=VoxelScene.render,base=nil,lastVisible=nil,lastManual=nil,
    manualWas=false,resume=1,frames=0,bcFrames=0,manualFrames=0,
    markerFrames=0,error=nil,battleLive=false,
  }
  gold.isGold=function()
    -- Presence of Randy as the sole camera host is the Test-4B Gold contract.
    -- Runtime battle/context checks below still gate actual camera ownership.
    return true
  end

  local BattleCam={still=false,steerable=true,t=0,orbit=0,zoom=1,pitch=0}
  BattleCam.rigFor=function(arena)
    local wide=arena and arena.cam=="wide"
    if wide then
      return {side=41.98,back=41.16,height=28.48,lookX=-3.24,lookY=-1.35,frameH=55.62}
    end
    return {side=78.79,back=144.96,height=37.88,lookX=-0.26,lookY=0.34,frameH=34.11}
  end
  local function copyCam(cam)
    if type(cam)~="table" then return nil end
    local eye=type(cam.eye)=="table" and {cam.eye[1],cam.eye[2],cam.eye[3]} or nil
    local focus=type(cam.focus)=="table" and {cam.focus[1],cam.focus[2],cam.focus[3]} or nil
    if not (eye and focus) then return nil end
    return {eye=eye,focus=focus,up={0,1,0},fov=tonumber(cam.fov) or math.rad(55),curve=tonumber(cam.curve) or 0}
  end
  local function fallbackBase(arena,groundY)
    if type(arena)~="table" or type(arena.player)~="table" or type(arena.enemy)~="table" then return nil end
    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
    local ex,ez=tonumber(arena.enemy[1]),tonumber(arena.enemy[2])
    if not (px and pz and ex and ez) then return nil end
    local mx,mz=(px+ex)*0.5,(pz+ez)*0.5
    local dx,dz=ex-px,ez-pz
    local len=math.sqrt(dx*dx+dz*dz); if len<1 then len=1 end
    dx,dz=dx/len,dz/len
    local rx,rz=-dz,dx
    local gy=tonumber(groundY) or 0
    return {eye={mx-dx*82+rx*42,gy+48,mz-dz*82+rz*42},focus={mx,gy+12,mz},up={0,1,0},fov=math.rad(55),curve=0}
  end
  BattleCam.rig=function(arena,groundY,canonical)
    local cam=copyCam(gold.base) or fallbackBase(arena,groundY)
    if not cam then return nil,nil end
    local dx=(cam.eye[1] or 0)-(cam.focus[1] or 0)
    local dz=(cam.eye[3] or 0)-(cam.focus[3] or 0)
    local flat=math.sqrt(dx*dx+dz*dz)
    local pitch=math.atan2(flat,math.max(1e-3,(cam.eye[2] or 0)-(cam.focus[2] or 0)))
    return cam,pitch
  end
  gold.BattleCam=BattleCam
  local backend={id="BC_GOLD_RANDY",version=provider.version,V=V,BattleCam=BattleCam,
    OverworldBattle=OverworldBattle,gold=true}
  gold.backend=backend
  backends.__gold=gold
  backends[#backends+1]=backend
  mod.log:warn("[BC GOLD] Randy live-world backend adapter discovered")
end)()
end


-- Randy Gen2 2D world-card + Sprite Facing adapter -------------------------
-- v1.1.1 Gen2 compatibility path. Randy's 2D world-card seam places native
-- Gold/Silver battle artwork at the provider's live 3D actor positions while
-- preserving provider battle-picture lifecycle. Camera-relative FRONT/BACK and
-- LEFT/RIGHT semantics are applied only on this 2D-card path. Crystal-on-Randy
-- uses its validated opposite horizontal handedness at the final card mirror
-- seam. Stadium models, Stadium2 Importer, vanilla Randy cards and every Gen1
-- presentation adapter remain isolated.
;(function()
  local provider=mod.find("STADIUM2_OVERWORLD_MODELS")
  if not provider then return end
  local exports=provider.exports or {}
  local V=exports.lib
  if type(V)~="table" or type(V.require)~="function" then return end
  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local OverworldBattle=req("OverworldBattle")
  local BattleScene=req("BattleScene")
  local BattleBillboard=req("BattleBillboard")
  local Voxel3D=req("Voxel3D")
  local Stadium=req("Stadium")
  local Mat4=req("Mat4")
  if not (OverworldBattle and BattleScene and BattleBillboard and Voxel3D and Stadium and Mat4
      and type(OverworldBattle.update)=="function"
      and type(OverworldBattle.cameraContext)=="function"
      and type(BattleScene.monCards)=="function"
      and type(BattleBillboard.mesh)=="function"
      and type(BattleBillboard.yawToward)=="function"
      and type(Voxel3D.draw)=="function"
      and type(Stadium.draw)=="function"
      and type(Mat4.mul)=="function" and type(Mat4.translate)=="function"
      and type(Mat4.scale)=="function" and type(Mat4.rotateY)=="function") then return end
  if OverworldBattle.__bcRandy2DWorldCard111 then return end

  local okBS,GoldBattleState=pcall(require,"src.ui.gen2.BattleState")
  if not okBS or type(GoldBattleState)~="table"
      or type(GoldBattleState.drawPic)~="function"
      or type(GoldBattleState.pic)~="function" then return end

  local crystal=mod.find("crystal_animated_sprites_with_shiny_visuals")
  local cache={screen=nil,textures=nil,drawn={player=false,enemy=false},capturing=false}
  local canvases={}
  local actor={
    player={side="back",turn="right",screenDelta=nil},
    enemy ={side="front",turn="left", screenDelta=nil},
  }

  local function facingMode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v=="dynamic" or v=="turn" then return v end
    return "host"
  end
  local function facingActive()
    if (mod.options:get("cameraAuthority") or "priority")=="disabled" then return false end
    if (mod.options:get("preset") or "dw3")=="external" then return false end
    return facingMode()~="host"
  end
  local function resetActors()
    actor.player.side,actor.player.turn,actor.player.screenDelta="back","right",nil
    actor.enemy.side,actor.enemy.turn,actor.enemy.screenDelta="front","left",nil
  end
  local function presentationSide(name)
    if facingActive() and facingMode()=="dynamic" then return actor[name].side end
    return name=="player" and "back" or "front"
  end

  local function modelsOff()
    if type(exports.modelsEnabled)=="function" then
      local ok,v=pcall(exports.modelsEnabled)
      if ok then return v==false end
    end
    -- Older Randy builds may not export the helper. Only act when the public
    -- option can be read positively as OFF; uncertainty fails closed to stable.
    local opts=provider.options
    if opts and type(opts.get)=="function" then
      local ok,v=pcall(opts.get,opts,"stadium3dSprites")
      if ok and v~=nil then
        return v==false or v==0 or v=="0" or v=="false" or v=="off"
      end
    end
    return false
  end

  local function liveContext()
    if not modelsOff() then return nil end
    local ok,ctx=pcall(OverworldBattle.cameraContext)
    if not (ok and type(ctx)=="table" and type(ctx.screen)=="table"
        and type(ctx.arena)=="table") then return nil end
    return ctx
  end

  local function updateActorOrientation(name,cell,other,cam,allowSide)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    -- FRONT/BACK: actor forward is actor -> opponent, identical to the Gen1
    -- product semantic. Hysteresis prevents a side-view camera from chattering.
    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
    local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
    local fl=math.sqrt(fx*fx+fz*fz)
    local vl=math.sqrt(vx*vx+vz*vz)
    if allowSide and fl>=0.001 and vl>=0.001 then
      local dot=(fx*vx+fz*vz)/(fl*vl)
      if a.side=="back" and dot>0.22 then a.side="front"
      elseif a.side=="front" and dot<(-0.22) then a.side="back" end
    end

    -- LEFT/RIGHT: decide which side of this actor the opponent occupies in the
    -- FINAL visible camera. This keeps both cards looking into the fight as BC
    -- crosses the axis instead of tying handedness to player/enemy identity.
    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(p)
          local dx=(tonumber(p[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(p[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
          return nil
        end
        local as,os=screenX(cell),screenX(other)
        if as and os then screenDelta=os-as else screenDelta=fx*rx+fz*rz end
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation(ctx)
    if not facingActive() then return end
    local arena=ctx and ctx.arena or nil
    local p,e=arena and arena.player,arena and arena.enemy
    local cam=OverworldBattle.__bcRandy2DWorldCardCamera
    if not (p and e and type(cam)=="table") then return end
    local dynamic=facingMode()=="dynamic"
    updateActorOrientation("player",p,e,cam,dynamic)
    updateActorOrientation("enemy",e,p,cam,dynamic)
  end

  local function canvasFor(side)
    if canvases[side] then return canvases[side] end
    local G=love and love.graphics
    if not (G and type(G.newCanvas)=="function") then return nil end
    local ok,c=pcall(G.newCanvas,160,144)
    if not (ok and c) then return nil end
    pcall(c.setFilter,c,"nearest","nearest")
    canvases[side]=c
    return c
  end

  local originalDrawPic=GoldBattleState.drawPic
  GoldBattleState.drawPic=function(self,mon,playerSide,...)
    if not cache.capturing and cache.screen==self then
      local side=playerSide and "player" or "enemy"
      -- Suppression is earned per frame only by a card that was actually
      -- submitted to Randy's world pass. Failure falls open to native Gold.
      if cache.drawn[side] then return end
    end
    return originalDrawPic(self,mon,playerSide,...)
  end

  local function captureSide(screen,side,forcedBack)
    local battle=screen and screen.battle
    local mon=battle and battle[side]
    if not mon then return nil end
    if side=="player" and screen.showPlayerTrainer then return nil end
    if side=="enemy" and screen.showEnemyTrainer then return nil end
    local canvas=canvasFor(side)
    if not canvas then return nil end
    local G=love and love.graphics
    if not G then return nil end

    -- Keep the PHYSICAL battle side passed to drawPic (animations, substitute,
    -- faint sink and side-specific slot lifecycle all depend on it) while asking
    -- only the pic resolver/scale resolver for the camera-selected representation.
    local wantBack
    if forcedBack~=nil then wantBack=forcedBack and true or false
    else wantBack=(presentationSide(side)=="back") end
    local rawPic=rawget(screen,"pic")
    local resolvePic=screen.pic
    local rawScale=rawget(screen,"picScale")
    local resolveScale=screen.picScale
    if type(resolvePic)~="function" then return nil end
    screen.pic=function(self,monArg,backArg)
      if monArg==mon then return resolvePic(self,monArg,wantBack) end
      return resolvePic(self,monArg,backArg)
    end
    if type(resolveScale)=="function" then
      screen.picScale=function(self,path,monArg,backArg)
        if monArg==mon then return resolveScale(self,path,monArg,wantBack) end
        return resolveScale(self,path,monArg,backArg)
      end
    end

    local prevCanvas=type(G.getCanvas)=="function" and G.getCanvas() or nil
    local ok=pcall(function()
      G.push("all")
      G.origin()
      G.setCanvas(canvas)
      G.clear(0,0,0,0)
      G.setBlendMode("alpha")
      G.setColor(1,1,1,1)
      cache.capturing=true
      screen:drawPic(mon,side=="player")
      cache.capturing=false
      G.pop()
    end)
    cache.capturing=false
    if rawPic~=nil then screen.pic=rawPic else screen.pic=nil end
    if rawScale~=nil then screen.picScale=rawScale else screen.picScale=nil end
    if not ok then pcall(G.pop) end
    if prevCanvas then pcall(G.setCanvas,G,prevCanvas) else pcall(G.setCanvas,G) end
    if not ok then return nil end

    -- Physical-side anchors stay Gold's own. Representation can change inside
    -- the canvas without moving the actor's feet/world cell.
    if side=="player" then
      return {canvas=canvas,ax=40,ay=96,trainer=true,bcSide=presentationSide(side)}
    end
    return {canvas=canvas,ax=124,ay=56,bcSide=presentationSide(side)}
  end

  -- Randy's monMatrix is intentionally small but its mirror flag is private to
  -- BattleScene.monCards and enemy cards cannot request it. Reproduce that exact
  -- provider formula only while Sprite Facing is active, changing solely the
  -- mirror decision. HOST DEFAULT/external keep TEST1's direct monCards path.
  local function facingCard(side,tex,ctx)
    local arena=ctx and ctx.arena or nil
    local cell=arena and ((side=="player") and arena.player or arena.enemy) or nil
    if not (tex and tex.canvas and type(cell)=="table") then return nil end
    local gbw=tonumber(BattleScene.GB_W) or 160
    local gbh=tonumber(BattleScene.GB_H) or 144
    local fullW=tonumber(BattleBillboard.FULL_W) or 16
    local fullPic=tonumber(BattleBillboard.FULL_PIC) or 56
    if fullPic==0 then return nil end
    local k=fullW/fullPic
    local w,h=gbw*k,gbh*k
    local ox=-(((tonumber(tex.ax) or gbw*0.5)/gbw)-0.5)*w
    local oy=-((gbh-(tonumber(tex.ay) or gbh))/gbh)*h
    local x,z=tonumber(cell[1]),tonumber(cell[2])
    if not (x and z) then return nil end
    local yaw=BattleBillboard.yawToward(x,z,Voxel3D.eye)
    local card=Mat4.mul(Mat4.translate(ox,oy,0),Mat4.scale(w,h,1))

    -- Polarity is anchored to TEST1's proven canonical frame:
    -- player BACK + opponent on screen-right = unmirrored;
    -- enemy FRONT + opponent on screen-left = unmirrored.
    -- Crossing either relation flips the corresponding artwork about its feet.
    local opponentRight=actor[side].turn=="right"
    local rep=tex.bcSide or presentationSide(side)
    local mirror
    if rep=="back" then
      mirror=not opponentRight
    else
      mirror=opponentRight
    end
    -- Crystal/Randy polarity correction. Runtime validation across DYNAMIC and
    -- TURN ONLY shows Crystal's live Gen2 battle-card output is horizontally
    -- opposite Randy's vanilla Gold/Silver card convention for both actors and
    -- both FRONT/BACK representations. Translate only this provider combination
    -- at the final world-card mirror seam. Vanilla Randy, Stadium models,
    -- Stadium2 Importer and every Gen1 presentation adapter remain untouched.
    -- Randy vanilla Gen2 cards have one additional handedness wrinkle relative
    -- to the Crystal path. Exact RC testing established the provider rule:
    -- under DYNAMIC the player card uses the opposite horizontal handedness for
    -- both FRONT and BACK representations, while TURN ONLY's canonical native
    -- pair (player BACK + enemy FRONT) both need that same correction. Keep this
    -- scoped to vanilla Randy world cards only; Crystal's validated polarity
    -- rule below and every other provider / Gen1 adapter remain untouched.
    if not crystal then
      local mode=facingMode()
      if mode=="turn" or (mode=="dynamic" and side=="player") then
        mirror=not mirror
      end
    end
    if crystal then mirror=not mirror end
    if mirror then card=Mat4.mul(Mat4.scale(-1,1,1),card) end
    return Mat4.mul(Mat4.mul(Mat4.translate(x,tonumber(ctx.groundY) or 0,z),
                             Mat4.rotateY(yaw)),card)
  end

  local originalUpdate=OverworldBattle.update
  OverworldBattle.update=function(dt,...)
    cache.drawn.player=false
    cache.drawn.enemy=false
    local ctx=liveContext()
    if ctx then
      if cache.screen~=ctx.screen then resetActors() end
      updateOrientation(ctx)
      local tex={}
      tex.enemy=captureSide(ctx.screen,"enemy")
      tex.player=captureSide(ctx.screen,"player")
      cache.screen=ctx.screen
      cache.textures=(tex.enemy or tex.player) and tex or nil
    else
      cache.screen=nil
      cache.textures=nil
      resetActors()
    end
    return originalUpdate(dt,...)
  end

  local originalStadiumDraw=Stadium.draw
  Stadium.draw=function(...)
    local out={originalStadiumDraw(...)}
    local ctx=liveContext()
    local textures=cache.textures
    if ctx and cache.screen==ctx.screen and textures then
      local function drawSide(side)
        local tex=textures[side]
        if not tex then return end
        local cards=nil
        if facingActive() then
          local model=facingCard(side,tex,ctx)
          if model then cards={{tex=tex.canvas,model=model}} end
        else
          local one={[side]=tex}
          local ok,got=pcall(BattleScene.monCards,ctx.arena,
            tonumber(ctx.groundY) or 0,one)
          if ok then cards=got end
        end
        if not (type(cards)=="table" and #cards>0) then return end
        local mesh=BattleBillboard.mesh()
        if not mesh then return end
        local submitted=false
        if type(Voxel3D.glass)=="function" then pcall(Voxel3D.glass,false) end
        if type(Voxel3D.seams)=="function" then pcall(Voxel3D.seams,false) end
        for _,card in ipairs(cards) do
          if card and card.tex and card.model then
            local okDraw=pcall(Voxel3D.draw,mesh,card.tex,card.model,
              tonumber(BattleBillboard.PULL) or 1.5)
            if okDraw then submitted=true end
          end
        end
        if type(Voxel3D.seams)=="function" then pcall(Voxel3D.seams,true) end
        if type(Voxel3D.glass)=="function" then pcall(Voxel3D.glass,true) end
        cache.drawn[side]=submitted
      end
      drawSide("enemy")
      drawSide("player")
    end
    return (table.unpack or unpack)(out)
  end

  local originalFinish=OverworldBattle.finish
  if type(originalFinish)=="function" then
    OverworldBattle.finish=function(...)
      cache.screen=nil; cache.textures=nil
      cache.drawn.player=false; cache.drawn.enemy=false
      OverworldBattle.__bcRandy2DWorldCardCamera=nil
      resetActors()
      return originalFinish(...)
    end
  end

  -- Secondary View consumer seam. Randy's 2D battle mode already owns the
  -- live world-card renderer, while Gold/Crystal own the actual art and
  -- animation. Capture only the current PLAYER FRONT representation into the
  -- same provider card contract, then let the independent PiP eye yaw it.
  -- This is deliberately independent from main Sprite Facing: PIP SIDE owns
  -- handedness, and the PiP remains one authored FRONT portrait.
  --
  -- Rebase29 splits CAPTURE from CARD BUILD. Gold/Crystal drawing is captured
  -- before Randy's private VoxelScene begins; once the 3D offscreen scene is
  -- active, each eye only rebuilds the billboard matrix from that already-live
  -- FRONT texture. This avoids nesting BattleState sprite capture inside a
  -- Voxel3D render pass and preserves the provider's animation ownership.
  OverworldBattle.__bcSecondaryViewPlayerTexture=function()
    local ctx=liveContext()
    if not (ctx and ctx.screen and ctx.arena) then return nil end
    local tex=captureSide(ctx.screen,"player",false)
    if not (tex and tex.canvas) then return nil end
    tex.bcSide="front"
    return tex
  end

  OverworldBattle.__bcSecondaryViewPlayerCards=function(tex)
    local ctx=liveContext()
    if not (ctx and ctx.screen and ctx.arena) then return nil end
    if not (tex and tex.canvas) then
      local capture=OverworldBattle.__bcSecondaryViewPlayerTexture
      if type(capture)~="function" then return nil end
      tex=capture()
    end
    if not (tex and tex.canvas) then return nil end
    local sideOpt=mod.options:get("secondaryViewSide") or "left"
    -- BattleScene.monCards mirrors player cards when trainer=false. Match the
    -- already-accepted Gen1 Secondary View flat-art polarity: LEFT mirrors,
    -- RIGHT does not. This flag is presentation metadata only; the captured
    -- image remains the provider's current FRONT animation frame.
    tex.trainer=(sideOpt=="right")
    tex.bcSide="front"
    local prior=tonumber(BattleBillboard.FULL_W) or 16
    BattleBillboard.FULL_W=prior*0.58
    local ok,cards=pcall(BattleScene.monCards,ctx.arena,tonumber(ctx.groundY) or 0,{player=tex})
    BattleBillboard.FULL_W=prior
    if not (ok and type(cards)=="table" and #cards>0) then return nil end
    return cards,{player=tex},"bc_secondary_randy_2d"
  end

  OverworldBattle.__bcRandy2DWorldCard111=true
  mod.log:info("Randy Gen2 2D world-card + Dynamic Sprite Facing adapter active")
end)()

if #backends==0 then
  -- A presentation backend is optional at loader level. Keep BC inert rather
  -- than failing the entire mod load so headless validation, launcher browsing
  -- and installations without a supported 3D host remain safe. Once a
  -- compatible backend is enabled, normal BC camera registration is unchanged.
  mod.log:warn("BATTLE_CINEMATICS: no compatible battle-camera backend found; BC will remain inactive until a supported live 3D battle host / Gold live-world host is enabled")
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
  { key="cameraAuthority", label="CAMERA AUTHORITY", type="choice", default="priority",
    choices={{"BC PRIORITY","priority"},{"COOPERATIVE","cooperative"},{"BC DISABLED","disabled"}} },
  { key="spriteFacing", label="SPRITE FACING", type="choice", default="dynamic",
    choices={{"HOST DEFAULT","host"},{"TURN ONLY","turn"},{"DYNAMIC","dynamic"}} },
  { key="preset", label="IDLE PRESET", type="choice", default="stadium",
    choices={{"DW3 CLASSIC","dw3"},{"HERO PORTRAIT","portrait_test"},{"STADIUM 64","stadium"},{"EXTERNAL","external"}} },
  -- Renderer-neutral optical modifier for ordinary BC passive/menu cameras.
  -- Uses BC's own framing vocabulary/scales and never moves the authored eye/focus.
  { key="idleView", label="IDLE VIEW", type="choice", default="standard",
    choices={{"STANDARD","standard"},{"WIDE","wide"},{"EXTRA WIDE","extra_wide"},{"ULTRA WIDE","ultra_wide"}} },
  { key="initialDelay", label="INITIAL DELAY", type="choice", default="quick_2",
    choices={{"IMMEDIATE (0s)","immediate"},{"2 SECONDS","quick_2"},
             {"4 SECONDS","quick_4"},{"SHORT (6s)","short"},
             {"STANDARD (9s)","standard"},{"LONG (12s)","long"},
             {"EXTRA LONG (15s)","extra_long"}} },
  -- Secondary View is a BC-wide optional presentation asset, not a DW3
  -- preset setting. Rebase 4 keeps the product semantics broad while the
  -- currently proven live render seam remains Dramaless/SBFX until adapters
  -- are validated one by one. Size is intentionally deferred to the next test.
  { key="secondaryView", label="SECOND VIEW PIP", type="choice", default="off",
    choices={{"OFF","off"},{"ON","on"}} },
  { key="secondaryViewSize", label="PIP SIZE", type="choice", default="small",
    choices={{"STANDARD","standard"},{"SMALL","small"}} },
  { key="secondaryViewFraming", label="PIP FRAMING", type="choice", default="normal",
    choices={{"NORMAL","normal"},{"CLOSE","close"}} },
  -- Secondary View owns a true arena-side camera independent from the main
  -- battle's SPRITE FACING. LEFT/RIGHT mean west/east 90-degree cameras, not
  -- merely a sprite mirror. LEFT remains the DW3-inspired default.
  { key="secondaryViewSide", label="PIP SIDE", type="choice", default="left",
    choices={{"LEFT (DW3)","left"},{"RIGHT","right"}} },
  { key="secondaryViewPlace", label="PIP PLACE", type="choice", default="mid_right",
    choices={{"MID CENTER","mid_center"},{"TOP RIGHT","top_right"},{"MID RIGHT","mid_right"},
             {"TOP LEFT","top_left"},{"MID LEFT","mid_left"},{"CUSTOM","custom"}} },
  -- Hidden normalized drag position (0..1000 across the available travel).
  -- These are filtered from the Mod Manager and only used when PIP PLACE=CUSTOM.
  { key="secondaryViewCustomX", label="PIP CUSTOM X", type="number", default=500, min=0, max=1000, step=1 },
  { key="secondaryViewCustomY", label="PIP CUSTOM Y", type="number", default=220, min=0, max=1000, step=1 },
  { key="dynamicIntro", label="PKMN INTRO CAM", type="choice", default="on",
    choices={{"BC HERO","on"},{"OFF","off"}} },
  -- Phenac/Colosseum encounter-opening work is deliberately retained but
  -- release-masked in v1.0.9. Keep it immediately after the Pokemon Intro
  -- system so it can return here when the interaction/lifecycle work is ready.
  { key="battleOpening", label="BATTLE INTRO", type="choice", default="off",
    choices={{"COLOSSEUM","colosseum"},{"OFF","off"}} },
  { key="introFraming", label="FRAMING", type="choice", default="wide",
    choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"NEAR","standard"},{"CLOSE","close"}} },
  { key="introSpeed", label="SPEED", type="choice", default="fast",
    choices={{"SLOW","slow"},{"NORMAL","normal"},{"FAST","fast"},{"FASTER","faster"}} },
  { key="introPan", label="HERO TILT", type="choice", default="off",
    choices={{"ON","on"},{"OFF","off"}} },
  { key="introReset", label="CANCEL", type="choice", default="b",
    choices={{"B BUTTON","b"},{"ANY INPUT","any"},{"ON MOVE/ITEM","confirmed"},{"OFF","off"}} },
  { key="attackCamera", label="ATTACK CAMERA", type="choice", default="stadium",
    choices={{"STADIUM","stadium"},{"OFF","off"}} },
  { key="faintCamera", label="FAINT CAMERA", type="choice", default="on",
    choices={{"ON","on"},{"OFF","off"}} },
  -- Preset-owned values. The Mod Manager wrapper below hides these rows from
  -- the main Battle Cinematics page and exposes them through CONFIGURE PRESET.
  -- They remain normal mod options underneath, so values are persisted by the
  -- launcher and survive preset switching / restarts.
  { key="dw3Framing", label="FRAMING", type="choice", default="standard",
    choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}} },
  { key="circleSpeed", label="ORBIT SPEED", type="choice", default="medium",
    choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}} },
  { key="dw3Height", label="HEIGHT", type="choice", default="standard",
    choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}} },
  { key="dw3Angle", label="ANGLE", type="choice", default="standard",
    choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}} },

  -- Stadium 64 and Hero Portrait now expose the same contextual tuning surface
  -- as DW3 Classic. Missing keys default to today's authored values; there is
  -- deliberately no migration or forced option change in v1.0.8.1.
  { key="stadiumFraming", label="FRAMING", type="choice", default="standard",
    choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}} },
  { key="stadiumSpeed", label="ORBIT SPEED", type="choice", default="medium",
    choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}} },
  { key="stadiumHeight", label="HEIGHT", type="choice", default="standard",
    choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}} },
  { key="stadiumAngle", label="ANGLE", type="choice", default="standard",
    choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}} },

  { key="heroFraming", label="FRAMING", type="choice", default="standard",
    choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}} },
  { key="heroSpeed", label="ORBIT SPEED", type="choice", default="medium",
    choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}} },
  { key="heroHeight", label="HEIGHT", type="choice", default="standard",
    choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}} },
  { key="heroAngle", label="ANGLE", type="choice", default="standard",
    choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}} },

  { key="inputReturn", label="RESET CAMERA", type="choice", default="off",
    choices={{"OFF","off"},{"CONFIRMED ACTION","confirmed"},{"ANY INPUT","any"}} },
  { key="diagnostics", label="DIAGNOSTICS", type="choice", default="off",
    choices={{"OFF","off"},{"ON","on"}} },
})

local state = {
  rigSeen=false, sinceRig=0, noRig=0,
  idle=0, time=0, active=false, blend=0,
  cameraAuthority={ game=nil, overrides={}, logged={} },
  directorPlan=1, directorBattle=0,
  battle=nil,
  -- APB presentation-language state. Renderer/host-specific adapters feed
  -- generic bounds here; camera modules consume only the shared semantics.
  apb={ arena=nil, groundY=nil, backend=nil, hudError=false },
  battleOpening={ pending=false, active=false, style=nil, time=0, duration=13.20,
                  phase="idle", holdTime=0, trainerPromptSeen=false, wildPrompt=false,
                  lastCamera=nil, lastPitch=nil },
  intro={ active=false, style=nil, side=nil, time=0, compact=false, compactDuration=3.8,
          pendingEnemy=false, pendingPlayer=false,
          initial=true, enemyWasSending=false, playerWasSending=false,
          enemyFreshSendIn=false, playerFaintReplacement=false,
          structuralHandoffNeeded=false,
          openingStructuralCamera=nil, openingStructuralMode=nil, openingStructuralPitch=nil,
          openingChainCamera=nil, openingChainPitch=nil, openingChainMode=nil,
          openingChainHold=false, openingBridgeActive=false },
  attack={ pending=false, active=false, side=nil, moveId=nil, mode="target", time=0, progress=0,
           sawAnimation=false, animTotal=0, tail=0 },
  faint={ pending=false, active=false, side=nil, battler=nil, time=0,
          shownStart=nil, zeroReached=false, zeroTime=0,
          stadiumSeen=false, stadiumGone=0 },
  stadiumMapBoundaryRisk=false,
  environmentFallback=nil,
  -- Secondary View Rebase 4: semantically ported from accepted Probe13 onto
  -- exact v1.1.1. Keep state on the shared table to avoid chunk-local pressure.
  secondaryViewProbe={
    enabled=true, backend=nil, camera=nil, pitch=nil, shot=nil, rendering=false,
    installed=false, frames=0, failure=nil, successLogged=false, failureLogged=false,
    renderAttempts=0, drawFrames=0, eligibleFrames=0, fixedStepCalls=0, renderFrameCalls=0,
    status="boot", diagBackend=false, diagV=false, diagOB=false, diagScene=false,
    diagV3=false, diagAA=false,
  },
  geomDiag={
    map=nil, backendId=nil, cache=nil, prevEye=nil, live=nil,
    lastHit=nil, hitHold=0, hudErrorLogged=false,
    action="NONE", rawEye=nil, wallClipActive=false, recoverFrames=0,
    liftActive=false, liftBlockedFrames=0, liftClearFrames=0,
    liftTargetY=nil, liftSource=nil, liftClaimed=false,
    canopyClearActive=false, canopyClearTop=nil, canopyClearTargetY=nil, canopyClearSource=nil,
    canopyPathToken=nil,
    canopyCrestToken=nil, canopyCrestY=nil, canopyCrestSource=nil,
    roofApproachToken=nil, roofApproachTop=nil, roofApproachComps=nil,
    roofApproachMode=nil, roofApproachTargetY=nil, roofApproachEntryY=nil,
    roofViewCrestToken=nil, roofViewCrestY=nil, roofViewLastStrongY=nil,
    roofViewCrestTop=nil, roofViewCrestComps=nil,
    passiveReadToken=nil, passiveReadFrames=0, passiveReadIntent=nil,
    passiveReadSource=nil, passiveReadTargetY=nil,
    passiveReadPlayerClear=nil, passiveReadPlayerFoliage=nil,
    passiveReadEnemyClear=nil, passiveReadEnemyFoliage=nil,
    featureReadActive=false, featureReadFrames=0, featureReadOffset=0,
    featureReadTargetOffset=nil, featureReadSide=nil, featureReadSource=nil,
    phaseHandoffRC3=nil,
  },
}

-- APB CROSS-GEN CONTRACT:
-- The semantic layer is generation-neutral. Gen1 and Gold register separate
-- presentation adapters; provider/manual-camera/lifecycle ownership remains
-- generation-specific and unchanged.

local BLEND_TIME=0.70

local function enabled()
  return (mod.options:get("cameraAuthority") or "priority") ~= "disabled"
end
local function idleDelay()
  return DELAYS[mod.options:get("initialDelay")] or DELAYS.quick_4
end
local function speedScale()
  local value=mod.options:get("circleSpeed") or "medium"
  for _,e in ipairs(SPEEDS) do if e.value==value then return e.scale end end
  return 1.0
end

-- Gen1Recomp fast-forward multiplies the fixed logic clock, so input.step can
-- run several 1/60 ticks during one real rendered frame. Battle Cinematics is
-- presentation-only: keep its ordinary timers on real presentation time rather
-- than making passive cameras/intros/blends run N times faster at N X speed.
--
-- Stadium Attack Camera progress deliberately remains tied to AnimPlayer.elapsed
-- below. The move animation is still the authority for attack timing; future
-- duration-aware grammar will simplify choreography when that effective window
-- becomes very short rather than letting camera motion drift past the FX.
local function effectiveLogicSpeed(game)
  if game and type(game.logicSpeed)=="function" then
    local ok,value=pcall(game.logicSpeed,game)
    value=ok and tonumber(value) or nil
    if value and value>0 then return value end
  end
  -- Compatibility fallback for older supported Gen1Recomp builds that expose
  -- the saved speed option but not Game:logicSpeed().
  local options=game and game.save and game.save.options
  local value=options and tonumber(options.speed) or nil
  return (value and value>0) and value or 1
end

local function cameraDelta(game,dt)
  dt=math.max(0,tonumber(dt) or 0)
  return dt/effectiveLogicSpeed(game)
end


-- Camera Authority ---------------------------------------------------------
-- BC PRIORITY is a unilateral camera-layer policy, not a renderer dependency.
-- BC declares only the phases its own modules are configured to own. Known
-- presentation hosts may consume that read-only contract, while BC separately
-- neutralizes explicit BC-targeted optical modifiers for the duration of a
-- battle. External model/animation/effect/audio ownership remains untouched.
function state.cameraAuthority.priority()
  return (mod.options:get("cameraAuthority") or "priority") == "priority"
end

function state.cameraAuthority.optionRow(schema,key)
  if type(schema)~="table" then return nil end
  for _,row in ipairs(schema) do
    if type(row)=="table" and row.key==key then return row end
  end
  return nil
end

function state.cameraAuthority.restore()
  local a=state.cameraAuthority
  local game=a.game
  local loader=game and game.mods
  if not (loader and type(loader.modOptions)=="table") then
    a.overrides={}
    return
  end
  for modId,keys in pairs(a.overrides or {}) do
    local bucket=loader.modOptions[modId]
    if type(bucket)=="table" then
      for key,record in pairs(keys) do
        if record.hadValue then bucket[key]=record.value else bucket[key]=nil end
      end
    end
  end
  a.overrides={}
end

function state.cameraAuthority.override(loader,modId,key,value)
  if modId==MOD_ID then return end
  loader.modOptions=loader.modOptions or {}
  local bucket=loader.modOptions[modId]
  if type(bucket)~="table" then return end
  local a=state.cameraAuthority
  a.overrides[modId]=a.overrides[modId] or {}
  if not a.overrides[modId][key] then
    a.overrides[modId][key]={ hadValue=bucket[key]~=nil, value=bucket[key] }
  end
  bucket[key]=value
  local tag=modId..":"..key
  if not a.logged[tag] then
    a.logged[tag]=true
    mod.log:info("camera authority: runtime-neutralized external BC camera modifier %s/%s",modId,key)
  end
end

function state.cameraAuthority.enforce(game)
  local a=state.cameraAuthority
  a.game=game or a.game
  game=a.game
  if not game then return end
  if not (a.priority() and enabled() and state.battle) then
    if next(a.overrides or {}) then a.restore() end
    return
  end
  local loader=game.mods
  local schemas=loader and loader.optionSchemas
  if not (loader and type(loader.modOptions)=="table" and type(schemas)=="table") then return end

  -- Generic host-adapter rule: if another mod exposes an option explicitly
  -- named as a Battle Cinematics zoom modifier, BC PRIORITY neutralizes only
  -- that camera-layer modifier while a battle is active. The user's saved value
  -- is restored immediately when the battle ends, BC is disabled, or authority
  -- returns to COOPERATIVE.
  for modId,schema in pairs(schemas) do
    if modId~=MOD_ID and a.optionRow(schema,"battle_cinematics_zoom") then
      a.override(loader,modId,"battle_cinematics_zoom","off")
    end
  end
end

local function diagnosticsOn()
  return mod.options:get("diagnostics") == "on"
end
local function logDiagnostic(message)
  if diagnosticsOn() then mod.log:info("[diagnostics] " .. message) end
end

-- Geometry diagnostic ------------------------------------------------------
-- This build keeps v0.7.9 choreography intact and layers conservative
-- geometry interventions: camera eye/path traversal through structural shape:wall volumes
-- and authored BUILDING FACADE quads only. Foreground cylinders/bollards/trees,
-- ledges, roof/top quads and ordinary object geometry remain non-blocking.
-- Test 3 specifically distinguishes a building's vertical shell (`q.own`) from
-- its roof so Power Plant wall crossings can be rejected without sterilising
-- the authored roof/ledge grazing that makes BC feel embedded in the world.
--
-- Why two geometry sources? `shapeAt` gives the coarse tile-volume classes
-- (walls, trees, furniture, etc.), while richer buildings/props can be emitted
-- as actual `objectQuads`. The latter is exactly the class of geometry that a
-- ground-height-only LOS test can miss.
local BC_GEOM_TILE=8.0
local BC_GEOM_BUCKET=16.0
local BC_GEOM_STEP=2.0
local BC_GEOM_EPS=1.20

local function bcDiagNum(v)
  v=tonumber(v)
  if not v then return "nil" end
  return string.format("%.1f",v)
end

local function bcDiagVec(v)
  if type(v)~="table" then return "nil" end
  return string.format("(%s,%s,%s)",bcDiagNum(v[1]),bcDiagNum(v[2]),bcDiagNum(v[3]))
end

local function bcGeomKey(tx,ty)
  return (ty+64)*4096+(tx+64)
end

local function bcGeomBucketKey(cx,cz)
  return tostring(cx)..":"..tostring(cz)
end

local function bcGeomBuild(backend,map)
  local out={supported=false, reason="unavailable", shapeAt=nil, buckets={}, allBoxes={}, quads=0, boxes=0, buildingWalls=0, verticalQuads=0, canopyBuckets={}, canopyStamps=0, canopyTopQuads=0, buildingEnv={}, buildingEnvCount=0, buildingComponents={}, buildingComponentCount=0, buildingFilledCells=0, buildingOwnedBoxes=0, buildingShellBoxes=0}
  if not (backend and backend.V and type(backend.V.require)=="function" and type(map)=="table") then
    out.reason="no backend/map"
    return out
  end

  local okMod,Structures=pcall(backend.V.require,"Structures")
  if not okMod or type(Structures)~="table" or type(Structures.forMap)~="function" then
    out.reason="Structures unavailable"
    return out
  end

  local okS,S=pcall(Structures.forMap,map)
  if not okS or type(S)~="table" then
    out.reason="Structures.forMap failed"
    return out
  end

  out.supported=true
  out.reason="Structures"
  out.shapeAt=type(S.shapeAt)=="table" and S.shapeAt or nil

  -- Composite Authority Test 36 ------------------------------------------
  -- A synthetic building must start with the backend's COMPLETE structural
  -- footprint, not only the subset of cells touched by whichever objectQuad
  -- AABBs happened to be indexed. Every shapeAt class=building cell becomes
  -- one BC body cell from ground upward; rendered quads supply local roof/top
  -- height hints. No backend data is modified.
  if out.shapeAt then
    for k,s in pairs(out.shapeAt) do
      if type(s)=="table" and tostring(s.class or ""):lower()=="building" then
        local nk=tonumber(k)
        if nk then
          local row=math.floor(nk/4096)
          local tx=nk-row*4096-64
          local tz=row-64
          local ck=bcGeomKey(tx,tz)
          if not out.buildingEnv[ck] then
            out.buildingEnv[ck]={bottom=0,top=nil,tx=tx,tz=tz,quadHits=0}
            out.buildingEnvCount=out.buildingEnvCount+1
          end
        end
      end
    end
  end

  local quads=type(S.objectQuads)=="table" and S.objectQuads or {}
  out.quads=#quads

  -- Build a lightweight X/Z spatial index over the backend's already-built
  -- object geometry. Quads remain approximated by their tight AABB here; this
  -- is a diagnostic detector, not yet the production collision algorithm.
  for _,q in ipairs(quads) do
    if type(q)=="table" and type(q[1])=="table" and type(q[2])=="table"
       and type(q[3])=="table" and type(q[4])=="table" then
      local x0,x1=math.huge,-math.huge
      local y0,y1=math.huge,-math.huge
      local z0,z1=math.huge,-math.huge
      local valid=true
      for i=1,4 do
        local c=q[i]
        local x,y,z=tonumber(c[1]),tonumber(c[2]),tonumber(c[3])
        if not (x and y and z) then valid=false break end
        x0,x1=math.min(x0,x),math.max(x1,x)
        y0,y1=math.min(y0,y),math.max(y1,y)
        z0,z1=math.min(z0,z),math.max(z1,z)
      end
      if valid then
        -- Preserve orientation even when a backend/fork strips the richer
        -- `q.own` metadata. Dramatic 1.8.0 still exposes the map's structural
        -- `shapeAt` class, and the Power Plant failure identifies the occupied
        -- cell as `building` even though its object quads no longer carry q.own.
        --
        -- This gives us a backend-neutral fallback:
        --   * horizontal/top quads remain cinematic foreground (roof skims stay)
        --   * vertical quads are only hard barriers when the map cell itself is
        --     structurally classed as a building (or q.own explicitly says so)
        local sx,sy,sz=x1-x0,y1-y0,z1-z0
        local axisThin=(sx<0.15 or sz<0.15)
        local vertical=(sy>1.0 and axisThin)
        local buildingWall=(q.own==true and vertical)
        local touchesBuilding=false
        local buildingKeys={}

        -- Rendered quads no longer DEFINE whether a building cell exists. The
        -- structural grid already did that above. They only contribute the
        -- local rendered top of cells they overlap. The synthetic fascia/body
        -- remains solid from ground (0) to that roof.
        if out.shapeAt then
          local tx0,tx1=math.floor(x0/BC_GEOM_TILE),math.floor(x1/BC_GEOM_TILE)
          local tz0,tz1=math.floor(z0/BC_GEOM_TILE),math.floor(z1/BC_GEOM_TILE)
          for tz=tz0,tz1 do
            for tx=tx0,tx1 do
              local s=out.shapeAt[bcGeomKey(tx,tz)]
              if type(s)=="table" and tostring(s.class or ""):lower()=="building" then
                touchesBuilding=true
                local k=bcGeomKey(tx,tz)
                buildingKeys[#buildingKeys+1]=k
                local e=out.buildingEnv[k]
                if not e then
                  e={bottom=0,top=nil,tx=tx,tz=tz,quadHits=0}
                  out.buildingEnv[k]=e
                  out.buildingEnvCount=out.buildingEnvCount+1
                end
                e.bottom=0
                e.quadHits=(tonumber(e.quadHits) or 0)+1
                if not tonumber(e.top) or y1>e.top then e.top=y1 end
              end
            end
          end
        end

        local box={x0=x0-BC_GEOM_EPS,x1=x1+BC_GEOM_EPS,
                   y0=y0-BC_GEOM_EPS,y1=y1+BC_GEOM_EPS,
                   z0=z0-BC_GEOM_EPS,z1=z1+BC_GEOM_EPS,
                   vertical=vertical, buildingWall=buildingWall,
                   buildingGeometry=touchesBuilding,
                   buildingKeys=touchesBuilding and buildingKeys or nil}
        if touchesBuilding then out.buildingOwnedBoxes=out.buildingOwnedBoxes+1 end
        out.boxes=out.boxes+1
        out.allBoxes[#out.allBoxes+1]=box
        if vertical then out.verticalQuads=out.verticalQuads+1 end
        if buildingWall then out.buildingWalls=out.buildingWalls+1 end
        local cx0,cx1=math.floor(box.x0/BC_GEOM_BUCKET),math.floor(box.x1/BC_GEOM_BUCKET)
        local cz0,cz1=math.floor(box.z0/BC_GEOM_BUCKET),math.floor(box.z1/BC_GEOM_BUCKET)
        for cz=cz0,cz1 do
          for cx=cx0,cx1 do
            local k=bcGeomBucketKey(cx,cz)
            local b=out.buckets[k]
            if not b then b={}; out.buckets[k]=b end
            b[#b+1]=box
          end
        end
      end
    end
  end

  -- Building Hull Test 35 --------------------------------------------------
  -- BC's synthetic building is a camera-volume object, not a point-cell.
  -- Canopy already benefits from the renderer's real round hull; building
  -- shapeAt cells do not. Give the derived facade/body and roof a small local
  -- camera-body perimeter so safety sees the structure BEFORE the camera
  -- centre has physically reached the rendered edge. This changes no backend.
  local BC_BUILDING_HULL_PAD=4.0

  -- Building Composite Test 34 ---------------------------------------------
  -- The backend is not modified. BC normalises the geometry it already exposes
  -- into one internal semantic object:
  --
  --   building body/fascia  <->  roof/top
  --
  -- This mirrors the relationship BC already exploits between stump/tree body
  -- and canopy top without pretending the backend itself named these roles.
  -- Connected building cells become one synthetic component. Each cell keeps
  -- its local rendered top (important for low/stepped roofs), while the
  -- component also records its overall footprint and highest top.
  local nextBuildingId=0
  for _,seed in pairs(out.buildingEnv) do
    if type(seed)=="table" and not seed.componentId then
      nextBuildingId=nextBuildingId+1
      local comp={id=nextBuildingId,cells={},cellCount=0,
                  bottom=0,top=-math.huge,knownTopCount=0,
                  tx0=math.huge,tx1=-math.huge,tz0=math.huge,tz1=-math.huge}
      local q={seed}; seed.componentId=nextBuildingId
      local qi=1
      while qi<=#q do
        local e=q[qi]; qi=qi+1
        local tx,tz=tonumber(e.tx),tonumber(e.tz)
        if tx and tz then
          e.bottom=0
          comp.cellCount=comp.cellCount+1
          comp.cells[#comp.cells+1]=e
          local et=tonumber(e.top)
          if et then
            comp.top=math.max(comp.top,et)
            comp.knownTopCount=comp.knownTopCount+1
          end
          comp.tx0=math.min(comp.tx0,tx); comp.tx1=math.max(comp.tx1,tx)
          comp.tz0=math.min(comp.tz0,tz); comp.tz1=math.max(comp.tz1,tz)
          for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local n=out.buildingEnv[bcGeomKey(tx+d[1],tz+d[2])]
            if type(n)=="table" and not n.componentId then
              n.componentId=nextBuildingId
              q[#q+1]=n
            end
          end
        end
      end

      if comp.top==-math.huge then comp.top=nil end

      -- Keep known local roof heights. For structural cells whose renderer did
      -- not give a direct quad/top sample, propagate a neighbouring local roof
      -- through this SAME connected component. Component max is only the final
      -- fallback, preventing holes without flattening a stepped roof when local
      -- information exists.
      if comp.top then
        for _=1,comp.cellCount do
          local pending={}
          for _,e in ipairs(comp.cells) do
            if not tonumber(e.top) then
              local best=nil
              local tx,tz=tonumber(e.tx),tonumber(e.tz)
              for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local n=out.buildingEnv[bcGeomKey(tx+d[1],tz+d[2])]
                if type(n)=="table" and n.componentId==comp.id and tonumber(n.top) then
                  best=best and math.max(best,n.top) or n.top
                end
              end
              if best then pending[#pending+1]={e=e,top=best} end
            end
          end
          if #pending==0 then break end
          for _,p in ipairs(pending) do
            if not tonumber(p.e.top) then
              p.e.top=p.top
              out.buildingFilledCells=out.buildingFilledCells+1
            end
          end
        end
        for _,e in ipairs(comp.cells) do
          if not tonumber(e.top) then
            e.top=comp.top
            out.buildingFilledCells=out.buildingFilledCells+1
          end
        end
      end

      comp.x0=comp.tx0*BC_GEOM_TILE; comp.x1=(comp.tx1+1)*BC_GEOM_TILE
      comp.z0=comp.tz0*BC_GEOM_TILE; comp.z1=(comp.tz1+1)*BC_GEOM_TILE
      comp.hullPad=BC_BUILDING_HULL_PAD
      out.buildingComponents[nextBuildingId]=comp
      out.buildingComponentCount=out.buildingComponentCount+1
    end
  end

  -- Composite Shell Test 37 ----------------------------------------------
  -- Test 36 unified the vocabulary but exposed a remaining representation gap:
  -- the structural `shapeAt=building` footprint can stop several world units
  -- short of the actually rendered facade/roof shell. At those edges BC could
  -- know a building existed yet still see the visible shell only as a nearby
  -- wall/ledge, so roof clearance started too late.
  --
  -- Keep every objectQuad that ALREADY overlapped a building cell as a private
  -- BC shell witness. Downstream systems never see "objectQuad": each witness
  -- is associated with the synthetic building component it belongs to and
  -- reports only the composite semantics fascia/body <-> roof/top.
  for _,b in ipairs(out.allBoxes) do
    if b.buildingGeometry and type(b.buildingKeys)=="table" then
      local chosenId=nil
      local localTop=nil
      for _,k in ipairs(b.buildingKeys) do
        local e=out.buildingEnv[k]
        if e and e.componentId then
          if not chosenId then chosenId=e.componentId end
          if e.componentId==chosenId then
            local et=tonumber(e.top)
            if et and (not localTop or et>localTop) then localTop=et end
          end
        end
      end
      if chosenId then
        b.buildingComponentId=chosenId
        local comp=out.buildingComponents[chosenId]
        b.buildingRoofTop=localTop or (comp and tonumber(comp.top) or nil)
        out.buildingShellBoxes=out.buildingShellBoxes+1
      end
    end
  end

  -- Actual rendered-shell point query. This is the "stump/body" half of the
  -- composite outside the coarse structural cells: hard only where the backend
  -- really rendered component-owned geometry.
  out.buildingShellPoint=function(wx,wy,wz)
    if not (wx and wy and wz) then return nil,nil,nil end
    local cx,cz=math.floor(wx/BC_GEOM_BUCKET),math.floor(wz/BC_GEOM_BUCKET)
    local bucket=out.buckets[bcGeomBucketKey(cx,cz)]
    if not bucket then return nil,nil,nil end
    local bestComp,bestTop,bestBox=nil,nil,nil
    for _,b in ipairs(bucket) do
      if b.buildingGeometry and b.buildingComponentId
          and wx>=b.x0 and wx<=b.x1 and wy>=b.y0 and wy<=b.y1
          and wz>=b.z0 and wz<=b.z1 then
        local comp=out.buildingComponents[b.buildingComponentId]
        local top=tonumber(b.buildingRoofTop) or (comp and tonumber(comp.top) or nil)
        if comp and (not bestTop or (top and top>bestTop)) then
          bestComp,bestTop,bestBox=comp,top,b
        end
      end
    end
    return bestComp,bestTop,bestBox
  end

  -- X/Z shell-proximity query. The shell's REAL rendered footprint, plus the
  -- same small camera-body allowance used by Test 35, is the "canopy hull"
  -- equivalent for buildings. This allows roof clearance to become known at
  -- the rendered facade edge even when shapeAt's building cell begins behind it.
  out.buildingShellNear=function(wx,wz,pad)
    if not (wx and wz) then return nil,nil,nil,nil end
    pad=math.max(0,tonumber(pad) or 0)
    local cx,cz=math.floor(wx/BC_GEOM_BUCKET),math.floor(wz/BC_GEOM_BUCKET)
    local rad=math.max(1,math.ceil(pad/BC_GEOM_BUCKET)+1)
    local bestComp,bestTop,bestDist,bestBox=nil,nil,math.huge,nil
    local seen={}
    for oz=-rad,rad do
      for ox=-rad,rad do
        local bucket=out.buckets[bcGeomBucketKey(cx+ox,cz+oz)]
        if bucket then
          for _,b in ipairs(bucket) do
            if b.buildingGeometry and b.buildingComponentId and not seen[b] then
              seen[b]=true
              local dx=0; if wx<b.x0 then dx=b.x0-wx elseif wx>b.x1 then dx=wx-b.x1 end
              local dz=0; if wz<b.z0 then dz=b.z0-wz elseif wz>b.z1 then dz=wz-b.z1 end
              local dist=math.sqrt(dx*dx+dz*dz)
              if dist<=pad+0.001 and dist<bestDist then
                local comp=out.buildingComponents[b.buildingComponentId]
                if comp then
                  bestComp=comp
                  bestTop=tonumber(b.buildingRoofTop) or tonumber(comp.top)
                  bestDist=dist
                  bestBox=b
                end
              end
            end
          end
        end
      end
    end
    return bestComp,bestTop,bestDist<math.huge and bestDist or nil,bestBox
  end

  -- Exact semantic lookup: returns the synthetic component and its local cell.
  out.buildingAt=function(wx,wz)
    if not (wx and wz) then return nil,nil end
    local tx,tz=math.floor(wx/BC_GEOM_TILE),math.floor(wz/BC_GEOM_TILE)
    local e=out.buildingEnv[bcGeomKey(tx,tz)]
    if not e then return nil,nil end
    return out.buildingComponents[e.componentId],e
  end

  -- Camera-body/proximity lookup. This is deliberately geometric rather than
  -- map-specific: a point slightly outside a facade can still know which roof
  -- belongs to the structure it is approaching.
  out.buildingNear=function(wx,wz,pad)
    if not (wx and wz) then return nil,nil,nil end
    local exactComp,exactEnv=out.buildingAt(wx,wz)
    if exactComp and exactEnv then return exactComp,exactEnv,0 end
    pad=math.max(0,tonumber(pad) or 0)
    local tx,tz=math.floor(wx/BC_GEOM_TILE),math.floor(wz/BC_GEOM_TILE)
    local rad=math.max(1,math.ceil(pad/BC_GEOM_TILE)+1)
    local bestComp,bestEnv,bestDist=nil,nil,math.huge
    for oz=-rad,rad do
      for ox=-rad,rad do
        local e=out.buildingEnv[bcGeomKey(tx+ox,tz+oz)]
        if e then
          local ex0=(e.tx or (tx+ox))*BC_GEOM_TILE
          local ex1=ex0+BC_GEOM_TILE
          local ez0=(e.tz or (tz+oz))*BC_GEOM_TILE
          local ez1=ez0+BC_GEOM_TILE
          local dx=0; if wx<ex0 then dx=ex0-wx elseif wx>ex1 then dx=wx-ex1 end
          local dz=0; if wz<ez0 then dz=ez0-wz elseif wz>ez1 then dz=wz-ez1 end
          local dist=math.sqrt(dx*dx+dz*dz)
          if dist<=pad+0.001 and dist<bestDist then
            bestDist=dist; bestEnv=e
            bestComp=out.buildingComponents[e.componentId]
          end
        end
      end
    end
    return bestComp,bestEnv,bestDist<math.huge and bestDist or nil
  end

  -- Synthetic facade/body lookup. This is the stump-equivalent side of the
  -- composite: hard below its associated local roof, but expanded just enough
  -- to represent camera body + rendered facade overhang rather than a point.
  out.buildingFasciaNear=function(wx,wz)
    local comp,e,dist=out.buildingNear(wx,wz,BC_BUILDING_HULL_PAD)
    if not (comp and e) then return nil,nil,nil end
    return comp,e,dist
  end

  -- Route query used by roof clearance. Samples only the X/Z course and asks
  -- the composite which LOCAL roof cells that course actually intersects.
  -- This means a small Route-12 building, a Power Plant shell, and a huge or
  -- stepped Saffron building all use the same language without a global height.
  out.buildingRouteTop=function(a,b,pad,step)
    if not (type(a)=="table" and type(b)=="table") then return nil,nil,nil end
    pad=math.max(0,tonumber(pad) or 0)
    step=math.max(0.5,tonumber(step) or 1.5)
    local ax,az=tonumber(a[1]) or 0,tonumber(a[3]) or 0
    local bx,bz=tonumber(b[1]) or 0,tonumber(b[3]) or 0
    local dx,dz=bx-ax,bz-az
    local len=math.sqrt(dx*dx+dz*dz)
    local steps=math.max(1,math.ceil(len/step))
    local bestTop,bestComp,firstDist=nil,nil,nil
    for i=0,steps do
      local t=i/steps
      local x,z=ax+dx*t,az+dz*t
      local comp,e=out.buildingNear(x,z,pad)
      local top=comp and e and (tonumber(e.top) or tonumber(comp.top)) or nil
      local shellComp,shellTop=out.buildingShellNear and out.buildingShellNear(x,z,pad) or nil,nil
      if shellComp and shellTop and (not top or shellTop>top) then
        comp,top=shellComp,shellTop
      end
      if comp and top then
        if not bestTop or top>bestTop then bestTop,bestComp=top,comp end
        if not firstDist then firstDist=len*t end
      end
    end
    return bestTop,bestComp,firstDist
  end

  -- Exact round-canopy surface index. Viridian's large tree canopies are not
  -- faithfully represented by shapeAt alone: one anchor cell is `canopy`,
  -- while partner cells may remain generic cylinder even though Structures
  -- renders one 32px-wide round hull across the whole group. The backend's
  -- own roundStamps preserve that actual hull. For stamps with r=16 (the
  -- grouped canopy archetype), index horizontal voxel faces by X/Z so BC can
  -- ask for the local rendered canopy top without making foliage a visual
  -- no-go zone.
  local stamps=type(S.roundStamps)=="table" and S.roundStamps or {}
  for _,st in ipairs(stamps) do
    local r=tonumber(type(st)=="table" and st.r) or 8
    local qs=type(st)=="table" and st.quads or nil
    local mx=tonumber(type(st)=="table" and st.mx) or 0
    local mz=tonumber(type(st)=="table" and st.mz) or 0
    if r>=15 and type(qs)=="table" then
      out.canopyStamps=out.canopyStamps+1
      for _,q in ipairs(qs) do
        if type(q)=="table" and type(q[1])=="table" and type(q[2])=="table"
           and type(q[3])=="table" and type(q[4])=="table" then
          local x0,x1=math.huge,-math.huge
          local y0,y1=math.huge,-math.huge
          local z0,z1=math.huge,-math.huge
          local valid=true
          for i=1,4 do
            local c=q[i]
            local x,y,z=tonumber(c[1]),tonumber(c[2]),tonumber(c[3])
            if not (x and y and z) then valid=false break end
            x=x+mx; z=z+mz
            x0,x1=math.min(x0,x),math.max(x1,x)
            y0,y1=math.min(y0,y),math.max(y1,y)
            z0,z1=math.min(z0,z),math.max(z1,z)
          end
          if valid and (y1-y0)<0.15 and y1>0.5 then
            -- Horizontal hull faces are the rendered top of each occupied
            -- voxel column. Their stepped heights preserve the rounded canopy.
            local face={x0=x0-0.08,x1=x1+0.08,z0=z0-0.08,z1=z1+0.08,top=y1}
            out.canopyTopQuads=out.canopyTopQuads+1
            local cx0,cx1=math.floor(face.x0/BC_GEOM_BUCKET),math.floor(face.x1/BC_GEOM_BUCKET)
            local cz0,cz1=math.floor(face.z0/BC_GEOM_BUCKET),math.floor(face.z1/BC_GEOM_BUCKET)
            for cz=cz0,cz1 do
              for cx=cx0,cx1 do
                local k=bcGeomBucketKey(cx,cz)
                local b=out.canopyBuckets[k]
                if not b then b={}; out.canopyBuckets[k]=b end
                b[#b+1]=face
              end
            end
          end
        end
      end
    end
  end
  return out
end

local function bcGeomCacheFor(backend,map)
  local g=state.geomDiag
  if g.cache and g.map==map and g.backendId==(backend and backend.id) then return g.cache end
  g.map=map
  g.backendId=backend and backend.id or nil
  g.prevEye=nil
  g.lastHit=nil
  g.hitHold=0
  g.action="NONE"
  g.rawEye=nil
  g.wallClipActive=false
  g.wallViewActive=false
  g.wallViewToken=nil
  g.lastWallViewEye=nil
  g.liftActive=false
  g.liftBlockedFrames=0
  g.liftClearFrames=0
  g.liftTargetY=nil
  g.liftSource=nil
  g.liftClaimed=false
  g.canopyClearActive=false
  g.canopyClearTop=nil
  g.canopyClearTargetY=nil
  g.canopyClearSource=nil
  g.canopyPathToken=nil
  g.canopyCrestToken=nil
  g.canopyCrestY=nil
  g.canopyCrestSource=nil
  g.structuralPreflightComponent=nil
  g.structuralPreflightFirstDist=nil
  g.recoverFrames=0
  local ok,cache=pcall(bcGeomBuild,backend,map)
  if ok and type(cache)=="table" then
    g.cache=cache
  else
    g.cache={supported=false,reason="probe error",shapeAt=nil,buckets={},quads=0,boxes=0}
  end
  return g.cache
end

local function bcGeomShapeAt(cache,wx,wz)
  if not (cache and cache.shapeAt and wx and wz) then return nil end
  local tx,ty=math.floor(wx/BC_GEOM_TILE),math.floor(wz/BC_GEOM_TILE)
  return cache.shapeAt[bcGeomKey(tx,ty)]
end

local function bcGeomPoint(cache,wx,wy,wz)
  if not (cache and cache.supported and wx and wy and wz) then return false,nil end

  -- Coarse structural volume. Do not treat flat floor/water/grass as camera
  -- obstruction. Building claims often carry h=0 because their true shell is
  -- in objectQuads, which is checked immediately below.
  local shape=bcGeomShapeAt(cache,wx,wz)
  if type(shape)=="table" and not shape.flat then
    local h=tonumber(shape.h) or 0
    if h>0 and wy>=-BC_GEOM_EPS and wy<=h+BC_GEOM_EPS then
      return true,"shape:"..tostring(shape.class or shape.art or "solid")
    end
  end

  local shapeClass=""
  if type(shape)=="table" then shapeClass=tostring(shape.class or ""):lower() end

  -- Composite Authority Test 36: generic LOS/readability now uses the same
  -- semantic fascia/body as hard camera occupancy. This is the missing link
  -- that previously let wall safety see a building while readability still saw
  -- unrelated anonymous objectQuad AABBs.
  if cache.buildingFasciaNear then
    local comp,env=cache.buildingFasciaNear(wx,wz)
    if comp and env then
      local top=tonumber(env.top) or tonumber(comp.top)
      if top and wy>=-BC_GEOM_EPS and wy<=top+BC_GEOM_EPS then
        return true,"shape:building-fascia",comp,top
      end
    end
  end

  if cache.buildingShellPoint then
    local shellComp,shellTop=cache.buildingShellPoint(wx,wy,wz)
    if shellComp then
      return true,"shape:building-fascia",shellComp,tonumber(shellTop) or tonumber(shellComp.top)
    end
  end

  local cx,cz=math.floor(wx/BC_GEOM_BUCKET),math.floor(wz/BC_GEOM_BUCKET)
  local bucket=cache.buckets[bcGeomBucketKey(cx,cz)]
  if bucket then
    for _,b in ipairs(bucket) do
      if not b.buildingGeometry
          and wx>=b.x0 and wx<=b.x1 and wy>=b.y0 and wy<=b.y1 and wz>=b.z0 and wz<=b.z1 then
        local inferredBuildingWall=(b.vertical and shapeClass=="building")
        return true,(b.buildingWall or inferredBuildingWall)
          and "objectQuad:building-wall" or "objectQuad"
      end
    end
  end
  return false,nil
end

local function bcGeomLine(cache,a,b)
  if not (cache and cache.supported and type(a)=="table" and type(b)=="table") then
    return false,nil,nil
  end
  local dx=(tonumber(b[1]) or 0)-(tonumber(a[1]) or 0)
  local dy=(tonumber(b[2]) or 0)-(tonumber(a[2]) or 0)
  local dz=(tonumber(b[3]) or 0)-(tonumber(a[3]) or 0)
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local steps=math.max(1,math.ceil(len/BC_GEOM_STEP))
  -- Include both ends. Eye occupancy is important here: a camera sitting
  -- immediately behind/inside a wall can look "frozen" even when it is moving.
  for i=0,steps do
    local t=i/steps
    local x=(tonumber(a[1]) or 0)+dx*t
    local y=(tonumber(a[2]) or 0)+dy*t
    local z=(tonumber(a[3]) or 0)+dz*t
    local blocked,source=bcGeomPoint(cache,x,y,z)
    if blocked then return true,source,{x,y,z} end
  end
  return false,nil,nil
end

local function bcGeomResult(cache,a,b)
  local blocked,source,pos=bcGeomLine(cache,a,b)
  return {blocked=blocked,source=source,pos=pos}
end

local BC_WALL_STEP=0.60
local BC_WALL_RECOVER_ALPHA=0.16
local BC_WALL_RECOVER_DONE=0.85

local function bcGeomWallPoint(cache,wx,wy,wz)
  if not (cache and cache.supported and wx and wy and wz) then return false,nil end

  -- Coarse structural volumes.
  --
  -- `wall` is the cave/interior class already proven by Tests 1-4.
  -- `stump` is intentionally added as a HARD OCCUPANCY/TRAVEL class only:
  -- Viridian Forest diagnostics show the ugly full-screen tree block occurs
  -- specifically when the camera eye itself and its travel segment are inside
  -- shape:stump. Canopy/cylinder/tree foreground remains untouched.
  local shape=bcGeomShapeAt(cache,wx,wz)
  local shapeClass=""
  if type(shape)=="table" and not shape.flat then
    shapeClass=tostring(shape.class or ""):lower()
    local h=tonumber(shape.h) or 0
    if h>0 and wy>=-BC_GEOM_EPS and wy<=h+BC_GEOM_EPS then
      if shapeClass=="wall" then return true,"shape:wall" end
      if shapeClass=="stump" then return true,"shape:stump" end
    end
  elseif type(shape)=="table" then
    shapeClass=tostring(shape.class or ""):lower()
  end

  -- Test 27 semantic building envelope:
  -- shapeAt tells us the cell is structurally a building; rendered objectQuads
  -- tell us how high that shell actually reaches. Treat the resulting prism as
  -- hard camera occupancy/path below the shell top, regardless of unreliable
  -- objectQuad face ordering. Looking AT a building remains legal.
  if cache.buildingFasciaNear then
    local comp,env=cache.buildingFasciaNear(wx,wz)
    if comp and env then
      local bottom=tonumber(env.bottom) or tonumber(comp.bottom) or 0
      local top=tonumber(env.top) or tonumber(comp.top)
      if top and wy>=bottom-BC_GEOM_EPS and wy<=top+BC_GEOM_EPS then
        return true,"shape:building-fascia"
      end
    end
  elseif cache.buildingAt then
    local comp,env=cache.buildingAt(wx,wz)
    if comp and env then
      local bottom=tonumber(env.bottom) or tonumber(comp.bottom) or 0
      local top=tonumber(env.top) or tonumber(comp.top)
      if top and wy>=bottom-BC_GEOM_EPS and wy<=top+BC_GEOM_EPS then
        return true,"shape:building-fascia"
      end
    end
  end

  -- Rendered component-owned shell extension. Unlike the old generic
  -- objectQuad path, this cannot leak anonymous renderer primitives downstream:
  -- a hit is already tied to one synthetic building component.
  if cache.buildingShellPoint then
    local shellComp,shellTop=cache.buildingShellPoint(wx,wy,wz)
    if shellComp then
      return true,"shape:building-fascia",shellComp,tonumber(shellTop) or tonumber(shellComp.top)
    end
  end

  -- Legacy explicit-orientation shell fallback for non-composite boxes:
  -- Dramaless may explicitly mark authored building shell quads (`q.own`).
  -- Dramatic 1.8.0 does not, but its `shapeAt` still identifies the occupied
  -- footprint as class=building. A VERTICAL object quad intersecting such a
  -- cell is therefore treated as a facade; horizontal roof/top quads are not.
  -- Generic objectQuads outside building cells remain cinematic/non-blocking.
  local cx,cz=math.floor(wx/BC_GEOM_BUCKET),math.floor(wz/BC_GEOM_BUCKET)
  local bucket=cache.buckets[bcGeomBucketKey(cx,cz)]
  if bucket then
    for _,b in ipairs(bucket) do
      local inside=wx>=b.x0 and wx<=b.x1 and wy>=b.y0 and wy<=b.y1
        and wz>=b.z0 and wz<=b.z1
      if (not b.buildingGeometry) and inside and b.vertical
          and (b.buildingWall or shapeClass=="building") then
        return true,"objectQuad:building-wall"
      end
    end
  end

  return false,nil
end

local function bcGeomWallLine(cache,a,b)
  if not (cache and cache.supported and type(a)=="table" and type(b)=="table") then
    return false,nil,nil,nil
  end
  local ax,ay,az=tonumber(a[1]) or 0,tonumber(a[2]) or 0,tonumber(a[3]) or 0
  local bx,by,bz=tonumber(b[1]) or 0,tonumber(b[2]) or 0,tonumber(b[3]) or 0
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local steps=math.max(1,math.ceil(len/BC_WALL_STEP))
  local lastSafe={ax,ay,az}
  for i=0,steps do
    local t=i/steps
    local p={ax+dx*t,ay+dy*t,az+dz*t}
    local blocked,source=bcGeomWallPoint(cache,p[1],p[2],p[3])
    if blocked then
      return true,source,p,lastSafe
    end
    lastSafe=p
  end
  return false,nil,nil,lastSafe
end

local function bcCopyCameraWithEye(camera,eye)
  if type(camera)~="table" or type(eye)~="table" then return camera end
  local out={}
  for k,v in pairs(camera) do out[k]=v end
  out.eye={eye[1],eye[2],eye[3]}
  if type(camera.focus)=="table" then
    out.focus={camera.focus[1],camera.focus[2],camera.focus[3]}
  end
  return out
end

-- Test 7: universal renderer-neutral floor guard.  The battle ground plane is
-- already part of every BC rig contract; only the CAMERA EYE is prevented from
-- crossing below it. Focus remains untouched because several proven authored
-- rigs legitimately look slightly below groundY. The small clearance avoids
-- near-plane/floor intersection while remaining visually inert for normal shots.
state.floorProtectCamera=function(camera,groundY)
  if not (type(camera)=="table" and type(camera.eye)=="table") then return camera end
  local minY=(tonumber(groundY) or 0)+1.50
  local eyeY=tonumber(camera.eye[2])
  if not eyeY or eyeY>=minY then return camera end
  return bcCopyCameraWithEye(camera,{camera.eye[1],minY,camera.eye[3]})
end

-- Native BC Idle View. Optical only: widen the lens using the same framing
-- language already established by v1.0.8.1 preset configuration. STANDARD is
-- identity; WIDE / EXTRA WIDE reuse BC's 1.16 / 1.32 frame scales and ULTRA
-- WIDE continues that BC ladder to 1.48. Eye, focus, path and safety stay fixed.
-- External is excluded by the caller because that preset belongs to the host.
state.applyIdleView=function(camera)
  if not (type(camera)=="table" and tonumber(camera.fov)) then return camera end
  local value=mod.options:get("idleView") or "standard"
  local scale=1.00
  if value=="wide" then scale=1.16
  elseif value=="extra_wide" then scale=1.32
  elseif value=="ultra_wide" then scale=1.48 end
  if scale<=1.0001 then return camera end
  local out={}
  for k,v in pairs(camera) do out[k]=v end
  if type(camera.eye)=="table" then out.eye={camera.eye[1],camera.eye[2],camera.eye[3]} end
  if type(camera.focus)=="table" then out.focus={camera.focus[1],camera.focus[2],camera.focus[3]} end
  out.fov=2*math.atan(math.tan((tonumber(camera.fov) or math.rad(55))*0.5)*scale)
  out.fov=math.max(math.rad(18),math.min(math.rad(110),out.fov))
  return out
end

function bcPitchForCamera(camera)
  if not (type(camera)=="table" and type(camera.eye)=="table" and type(camera.focus)=="table") then
    return nil
  end
  local dx=(tonumber(camera.eye[1]) or 0)-(tonumber(camera.focus[1]) or 0)
  local dy=(tonumber(camera.eye[2]) or 0)-(tonumber(camera.focus[2]) or 0)
  local dz=(tonumber(camera.eye[3]) or 0)-(tonumber(camera.focus[3]) or 0)
  local horiz=math.sqrt(dx*dx+dz*dz)
  return math.atan2(horiz,math.max(1e-3,dy))
end

local function bcVecDistance(a,b)
  if not (type(a)=="table" and type(b)=="table") then return math.huge end
  local dx=(tonumber(b[1]) or 0)-(tonumber(a[1]) or 0)
  local dy=(tonumber(b[2]) or 0)-(tonumber(a[2]) or 0)
  local dz=(tonumber(b[3]) or 0)-(tonumber(a[3]) or 0)
  return math.sqrt(dx*dx+dy*dy+dz*dz)
end

local function bcLerpVec(a,b,t)
  return {
    (tonumber(a[1]) or 0)+((tonumber(b[1]) or 0)-(tonumber(a[1]) or 0))*t,
    (tonumber(a[2]) or 0)+((tonumber(b[2]) or 0)-(tonumber(a[2]) or 0))*t,
    (tonumber(a[3]) or 0)+((tonumber(b[3]) or 0)-(tonumber(a[3]) or 0))*t,
  }
end

-- Canopy Clearance Test 15 ------------------------------------------------
-- Foliage may frame or partly hide a shot beautifully, but the physical camera
-- eye/path should not descend THROUGH the rendered canopy hull. This layer
-- treats only the canopy TOP as a vertical clearance floor. It preserves X/Z,
-- target, FOV and shot ownership; it neither rejects foliage in the frame nor
-- substitutes another preset.
local BC_CANOPY_CLEARANCE=1.35
local BC_CANOPY_RECOVER_ALPHA=0.22
local BC_CANOPY_RECOVER_DONE=0.40
local BC_CANOPY_PATH_STEP=0.70

local function bcCanopyTopAt(cache,wx,wz)
  if not (cache and cache.supported and wx and wz) then return nil,nil end
  local best=nil
  local bucket=cache.canopyBuckets and cache.canopyBuckets[bcGeomBucketKey(
    math.floor(wx/BC_GEOM_BUCKET),math.floor(wz/BC_GEOM_BUCKET))]
  if bucket then
    for _,f in ipairs(bucket) do
      if wx>=f.x0 and wx<=f.x1 and wz>=f.z0 and wz<=f.z1 then
        local top=tonumber(f.top)
        if top and (not best or top>best) then best=top end
      end
    end
  end
  local bestSource=best and "roundStamp" or nil

  -- Test 37: the rendered shell may extend outside shapeAt's coarse building
  -- footprint. If this X/Z lies on/near a component-owned shell, expose that
  -- SAME component's roof height before consulting the coarse cell body.
  if cache.buildingShellNear then
    local shellComp,shellTop=cache.buildingShellNear(wx,wz,4.0)
    if shellComp and shellTop and (not best or shellTop>best) then
      best=shellTop
      bestSource="shape:building-roof"
    end
  end

  -- Test 27: building shell tops use the same vertical-clearance concept as
  -- canopy. The semantic source is the building cell, not an objectQuad label.
  local shape=bcGeomShapeAt(cache,wx,wz)
  if cache.buildingFasciaNear then
    local comp,env=cache.buildingFasciaNear(wx,wz)
    local top=env and tonumber(env.top) or (comp and tonumber(comp.top) or nil)
    if top and (not best or top>best) then
      best=top
      bestSource="shape:building-roof"
    end
  elseif cache.buildingAt then
    local comp,env=cache.buildingAt(wx,wz)
    local top=env and tonumber(env.top) or (comp and tonumber(comp.top) or nil)
    if top and (not best or top>best) then
      best=top
      bestSource="shape:building-roof"
    end
  end

  -- Conservative fallback when a compatible backend exposes Structures but
  -- omits roundStamps. Never generalise `cylinder`: bollards share that class.
  shape=shape or bcGeomShapeAt(cache,wx,wz)
  if type(shape)=="table" and tostring(shape.class or ""):lower()=="canopy" then
    local h=tonumber(shape.h)
    if h and h>0 and (not best or h>best) then
      best=h
      bestSource="shape:canopy"
    end
  end
  return best,bestSource
end

local function bcCanopyPathViolation(cache,a,b)
  if not (cache and cache.supported and type(a)=="table" and type(b)=="table") then
    return 0,nil,nil
  end
  local ax,ay,az=tonumber(a[1]) or 0,tonumber(a[2]) or 0,tonumber(a[3]) or 0
  local bx,by,bz=tonumber(b[1]) or 0,tonumber(b[2]) or 0,tonumber(b[3]) or 0
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local steps=math.max(1,math.ceil(len/BC_CANOPY_PATH_STEP))
  local worst,worstTop,worstSource=0,nil,nil
  for i=0,steps do
    local t=i/steps
    local x,y,z=ax+dx*t,ay+dy*t,az+dz*t
    local top,source=bcCanopyTopAt(cache,x,z)
    if top then
      local margin=(tostring(source or ""):find("building-roof",1,true)~=nil) and 5.0 or BC_CANOPY_CLEARANCE
      local need=(top+margin)-y
      if need>worst then worst,worstTop,worstSource=need,top,source end
    end
  end
  return math.max(0,worst),worstTop,worstSource
end

local function bcApplyCanopyClearance(backend,arena,camera)
  local g=state.geomDiag
  if not (type(camera)=="table" and type(camera.eye)=="table"
      and type(arena)=="table" and type(arena.map)=="table" and not arena.discs) then
    g.canopyClearActive=false; g.canopyClearTop=nil; g.canopyClearTargetY=nil; g.canopyClearSource=nil
    g.canopyPathToken=nil
    return camera
  end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return camera end

  local desired={camera.eye[1],camera.eye[2],camera.eye[3]}

  -- Shot-Bound Escape Test 21 ---------------------------------------------
  -- Test 20 proved the local readable escape, but exposed an ownership bug at
  -- the NEXT authored passive shot. The previous rescued eye can be hundreds
  -- of units above the new authored eye. Treating that cut as a continuous
  -- physical travel segment makes canopy path protection raise the new eye
  -- back toward the old rescue; vertical recovery then stays claimed and Test
  -- 16's crest legitimately latches the inherited height again. The result is
  -- a positive feedback loop that can erase every later authored scene.
  --
  -- A passive shot-token boundary is therefore a discontinuity for PASSIVE
  -- canopy travel/recovery state. Hard endpoint safety is still evaluated on
  -- the new shot immediately below, and all ordinary within-shot path safety
  -- remains unchanged. No map/preset/shot number is special-cased.
  local passiveToken=(not state.battleOpening.active and not state.intro.active and not state.attack.active and not state.faint.active)
      and state.passiveShotToken or nil
  local passiveShotBoundary=passiveToken~=nil and g.canopyPathToken~=passiveToken
  if passiveToken~=nil then
    g.canopyPathToken=passiveToken
  else
    g.canopyPathToken=nil
  end

  if passiveShotBoundary then
    -- Release only soft state owned by the previous authored passive shot.
    -- The new shot may immediately acquire its own correction if its endpoint
    -- or subsequent within-shot path independently requires one.
    g.canopyClearActive=false
    g.canopyClearTop=nil
    g.canopyClearTargetY=nil
    g.canopyClearSource=nil
    g.canopyCrestToken=nil
    g.canopyCrestY=nil
    g.canopyCrestSource=nil
    g.liftActive=false
    g.liftBlockedFrames=0
    g.liftClearFrames=0
    g.liftTargetY=nil
    g.liftSource=nil
    g.liftClaimed=false
  end

  -- Do not invent a travel segment across an authored passive camera cut.
  -- Endpoint canopy occupancy is still checked below using the new raw eye.
  local prev=passiveShotBoundary and nil or g.prevEye
  local authoredY=tonumber(desired[2]) or 0
  local targetY=authoredY
  local top,source=bcCanopyTopAt(cache,desired[1],desired[3])

  -- Structural Convergence RC13 ------------------------------------------
  -- Building counterpart to the Viridian crest lesson. A high authored shot
  -- can begin cleanly above a roof, descend, then reach the roof floor and get
  -- pushed upward again. The visual result is the familiar shoulder bounce.
  --
  -- RC12 tried to remember the previous AUTHORED Y, but the safety stack can
  -- evaluate the same authored camera more than once before the final camera is
  -- committed, so that bookkeeping could already contain the current low Y by
  -- the time the roof correction acquired.
  --
  -- The previous FINAL eye is a stronger fact: it is the exact physical camera
  -- BC successfully presented on the immediately preceding frame, and `prev` is
  -- already shot-bound (nil at an authored cut). When a real building-roof
  -- correction first interrupts a descending shot, that previous physical Y is
  -- therefore the correct crest floor. X/Z, focus, FOV and token timing remain
  -- authored; only the invalid down->up excursion is removed.

  -- Structural Crest Test 29 ----------------------------------------------
  -- A building can be crossed only as a ROUTE, not used as a substitute
  -- endpoint. If the authored endpoint itself lives under a known building
  -- roof, leave it untouched here so hard safety can reject it and hand the
  -- shot to the backend-safe eye. This is the structural equivalent of BC's
  -- established "the environment cannot support this physical shot" fallback.
  -- Structural Shot Authority Test 38:
  -- Test 37 finally gave BC a rendered building shell, but this endpoint test
  -- was still using ONLY the old coarse shapeAt building cell. That meant an
  -- authored eye could live inside the new fascia/shell and be misread as a
  -- roof-crossing route; canopy clearance then tried to lift that impossible
  -- endpoint over the roof, producing the familiar corner bounce.
  --
  -- Ask the authoritative hard composite instead. If the authored endpoint is
  -- physically inside building fascia/shell, do NOT reinterpret it as an
  -- over-roof route. Leave it for wall safety to reject as an impossible shot.
  local endpointBlocked,endpointSource=bcGeomWallPoint(cache,desired[1],desired[2],desired[3])
  local endpointInsideBuilding=endpointBlocked and
      tostring(endpointSource or ""):find("building",1,true)~=nil

  if top and not endpointInsideBuilding then
    local margin=(tostring(source or ""):find("building-roof",1,true)~=nil) and 5.0 or BC_CANOPY_CLEARANCE
    targetY=math.max(targetY,top+margin)
  end

  -- Composite Authority Test 36 ------------------------------------------
  -- No speculative authored-tangent preflight lives here anymore. The mature
  -- synthetic building itself is authoritative: the actual safe->desired route
  -- samples its fascia/roof composite below, exactly when that structure is
  -- physically relevant.

  -- Viridian's final lesson, generalised to structural roofs:
  -- if the camera's X/Z route crosses a building, establish the required
  -- clearance height BEFORE advancing horizontally. A diagonal climb can still
  -- strike the near roof/facade corner; a vertical-first rise cannot.
  --
  -- Once the good high point is reached, keep that height across the authored
  -- route. Test 16's crest latch then owns the remainder of the passive shot.
  if prev and not endpointInsideBuilding then
    local ax,az=tonumber(prev[1]) or 0,tonumber(prev[3]) or 0
    local bx,bz=tonumber(desired[1]) or 0,tonumber(desired[3]) or 0
    local dx,dz=bx-ax,bz-az
    local structuralY=nil
    local routeTop52=nil
    if cache.buildingRouteTop then
      routeTop52=cache.buildingRouteTop(prev,desired,4.0,BC_CANOPY_PATH_STEP)
      if routeTop52 then structuralY=routeTop52+5.0 end
    end

    -- Structural Convergence RC1: preserve the proven Test52 stepped-roof fix.
    -- A desired X/Z already known to sit over a building roof has enough
    -- semantic information to require vertical-first entry even when the route
    -- sampler misses that component for a frame. This prevents a low->higher
    -- roof transition from diagonally clipping the near roof edge and inflating
    -- the required height.
    if top and tostring(source or ""):find("building-roof",1,true)~=nil then
      local endpointRoofTop=tonumber(top)
      if endpointRoofTop then
        local endpointRoofY=endpointRoofTop+5.0
        structuralY=structuralY and math.max(structuralY,endpointRoofY) or endpointRoofY
      end
    end

    if structuralY then
      local prevY=tonumber(prev[2]) or authoredY
      if prevY<structuralY-0.05 then
        local nextY=prevY+(structuralY-prevY)*0.34
        if nextY-prevY<0.85 then nextY=math.min(structuralY,prevY+0.85) end
        g.canopyClearActive=true
        g.canopyClearTop=structuralY-5.0
        g.canopyClearTargetY=structuralY
        g.canopyClearSource="shape:building-roof"
        g.action="STRUCTURAL_RISE"
        return bcCopyCameraWithEye(camera,{prev[1],nextY,prev[3]})
      end
      targetY=math.max(targetY,structuralY)
      top=math.max(tonumber(top) or -math.huge,structuralY-5.0)
      source="shape:building-roof"
    end
  end

  -- Protect the movement segment too, not merely its endpoint. Iteratively
  -- raise only Y until the straight per-frame segment clears the rounded hull.
  if prev and not endpointInsideBuilding then
    local candidate={desired[1],targetY,desired[3]}
    for _=1,4 do
      local miss,pathTop,pathSource=bcCanopyPathViolation(cache,prev,candidate)
      if miss<=0.02 then break end
      candidate[2]=candidate[2]+miss+0.08
      if pathTop and (not top or pathTop>top) then top=pathTop end
      source=pathSource or source
    end
    targetY=candidate[2]
  end

  if targetY>authoredY+0.02 then
    local roofDescentHold=false
    local previousPhysicalY=prev and tonumber(prev[2]) or nil
    if passiveToken~=nil
        and tostring(source or ""):find("building-roof",1,true)~=nil
        and previousPhysicalY
        and previousPhysicalY>authoredY+0.05
        and previousPhysicalY>targetY+0.02 then
      -- The immediately preceding final camera is already a proven-safe point
      -- on this same authored token. Keep that height rather than descending
      -- through the roof and correcting back upward on the next frame.
      targetY=previousPhysicalY
      roofDescentHold=true
      g.canopyCrestToken=passiveToken
      if g.canopyCrestY==nil or targetY>g.canopyCrestY then
        g.canopyCrestY=targetY
        g.canopyCrestSource="shape:building-roof"
      end
    end

    g.canopyClearActive=true
    g.canopyClearTop=top
    g.canopyClearTargetY=targetY
    g.canopyClearSource=source
    g.action=roofDescentHold and "ROOF_DESCENT_CREST" or "CANOPY_CLEAR"
    return bcCopyCameraWithEye(camera,{desired[1],targetY,desired[3]})
  end

  -- Relinquish the vertical floor smoothly once the authored path rises or
  -- leaves the canopy. Downward recovery is rechecked against the path floor.
  if g.canopyClearActive and prev then
    local fromY=tonumber(prev[2]) or authoredY
    if fromY>authoredY+BC_CANOPY_RECOVER_DONE then
      local nextY=fromY+(authoredY-fromY)*BC_CANOPY_RECOVER_ALPHA
      local candidate={desired[1],nextY,desired[3]}
      local miss,pathTop,pathSource=bcCanopyPathViolation(cache,prev,candidate)
      if miss>0.02 then
        candidate[2]=candidate[2]+miss+0.08
        g.canopyClearTop=pathTop
        g.canopyClearSource=pathSource
        g.action="CANOPY_CLEAR"
      else
        g.action="CANOPY_RECOVER"
      end
      g.canopyClearTargetY=candidate[2]
      return bcCopyCameraWithEye(camera,candidate)
    end
  end

  g.canopyClearActive=false
  g.canopyClearTop=nil
  g.canopyClearTargetY=nil
  g.canopyClearSource=nil
  return camera
end

-- Canopy Crest Hold Test 16 -----------------------------------------------
-- Test 15 proved that pointwise canopy clearance can find a good vertical
-- escape, but a long horizontal horseshoe can then descend again over every
-- local dip/gap in the rounded canopy. That creates the visible "riding" /
-- bouncing effect.  Once a passive shot has needed a foliage correction, hold
-- the HIGHEST safe eye height reached for the remainder of that authored shot.
-- X/Z, focus, FOV and timing remain untouched. A new shot gets a fresh budget.
-- This is deliberately passive-only; Test 10's proven Hero Intro protection is
-- not changed by this experiment.
local function bcFoliageLiftSource(source)
  local v=tostring(source or ""):lower()
  return v=="canopy" or v=="stump" or v=="tree"
      or v:find("canopy",1,true)~=nil or v:find("stump",1,true)~=nil
      or v:find("tree",1,true)~=nil or v:find("roundstamp",1,true)~=nil
      or v:find("building-roof",1,true)~=nil
end

local function bcApplyPassiveCanopyCrestHold(camera)
  local g=state.geomDiag
  local token=state.passiveShotToken
  if state.battleOpening.active or state.intro.active or state.attack.active or state.faint.active or token==nil
      or not (type(camera)=="table" and type(camera.eye)=="table") then
    g.canopyCrestToken=nil
    g.canopyCrestY=nil
    g.canopyCrestSource=nil
    return camera
  end

  if g.canopyCrestToken~=token then
    g.canopyCrestToken=token
    g.canopyCrestY=nil
    g.canopyCrestSource=nil
  end

  local foliageCorrection=(g.canopyClearActive and bcFoliageLiftSource(g.canopyClearSource))
      or (g.liftClaimed and bcFoliageLiftSource(g.liftSource))
  local eyeY=tonumber(camera.eye[2]) or 0
  if foliageCorrection then
    local crestCandidateY=eyeY
    local crestSource=g.canopyClearActive and g.canopyClearSource or g.liftSource
    -- Viridian can legitimately latch the final corrected canopy eye. Buildings
    -- cannot: wall-view recovery may move the camera toward a completely
    -- different native eye AFTER roof clearance, and Test 37 was then latching
    -- that unrelated height (e.g. ~84.6 for a ~78.6 roof target). For a
    -- building roof, remember only the height actually reached toward the roof
    -- clearance target, capped at that target. This preserves the smooth rise
    -- without allowing another safety system to inflate the structural crest.
    if g.canopyClearActive and tostring(g.canopyClearSource or ""):find("building-roof",1,true)~=nil then
      local roofTarget=tonumber(g.canopyClearTargetY)
      if roofTarget then crestCandidateY=math.min(eyeY,roofTarget) end
    end
    if g.canopyCrestY==nil or crestCandidateY>g.canopyCrestY then
      g.canopyCrestY=crestCandidateY
      g.canopyCrestSource=crestSource
    end
  end

  local holdY=tonumber(g.canopyCrestY)
  if holdY and eyeY<holdY-0.02 then
    g.action="CANOPY_CREST_HOLD"
    return bcCopyCameraWithEye(camera,{camera.eye[1],holdY,camera.eye[3]})
  end
  return camera
end

-- Passive Subject Readability Test 20 — Readable Escape (preserved) --------
-- Tests 18/19 established the passive presentation contract: presets declare
-- what an authored shot intends to show, while the shared safety layer judges
-- whether that subject is genuinely readable through a tolerant 3x3 envelope.
-- Test 19 correctly detects the remaining Stadium shot-3 mixed curtain, but its
-- vertical-only solver returns no readable height. That means the camera is
-- physically legal yet horizontally stranded behind a larger geometry mass.
--
-- Test 20 preserves every proven rule and adds ONE generic fallback only after
-- the vertical solver is exhausted: search a small camera-local lateral +
-- vertical neighbourhood for the nearest safe eye that restores the authored
-- subject contract. The search knows nothing about map names or presets beyond
-- their declared intent. Once found, the correction is latched as an OFFSET for
-- the remainder of that authored shot, preserving its movement rather than
-- freezing an absolute camera position. Focus, FOV, timing and ownership remain
-- authored. Test 16's crest latch remains authoritative for vertical stability.
local BC_PASSIVE_READ_TRIGGER_FRAMES=4
local BC_PASSIVE_READ_BAD_FOLIAGE=7   -- >=7/9 foliage-blocked: near-solid curtain
local BC_PASSIVE_READ_GOOD_CLEAR=6    -- >=6/9 clear: proven tolerable foreground level
local BC_PASSIVE_READ_MIXED_MAX_CLEAR=2 -- both-shot partner <=2/9 clear: essentially unreadable
local BC_PASSIVE_READ_LATERAL=3.25
local BC_PASSIVE_READ_HEIGHTS={4.5,9.0,13.5}
local BC_PASSIVE_READ_SEARCH_STEPS=18
local BC_PASSIVE_READ_STEP=2.0
local BC_PASSIVE_READ_ALPHA=0.34
local BC_PASSIVE_READ_MIN_RISE=0.75

-- Test 20 escape search. Sideways distances are world units in the camera's
-- local right-vector, not map-specific coordinates. 24 units is only 1.5
-- standard 16-unit map cells, keeping the experiment deliberately local.
local BC_PASSIVE_ESCAPE_SIDES={6.0,12.0,18.0,24.0}
local BC_PASSIVE_ESCAPE_RISES={0.0,4.0,8.0,12.0,16.0,22.0}
local BC_PASSIVE_ESCAPE_ALPHA=0.28
local BC_PASSIVE_ESCAPE_MAP_MARGIN=12.0

local function bcPassiveReadabilityEnvelope(cache,eye,subject,groundY)
  if not (cache and cache.supported and type(eye)=="table" and type(subject)=="table") then
    return nil
  end
  local sx,sz=tonumber(subject[1]),tonumber(subject[2])
  local ex,ez=tonumber(eye[1]),tonumber(eye[3])
  if not (sx and sz and ex and ez) then return nil end
  local dx,dz=sx-ex,sz-ez
  local len=math.sqrt(dx*dx+dz*dz)
  local rx,rz
  if len>1e-4 then rx,rz=-dz/len,dx/len else rx,rz=1,0 end
  local gy=tonumber(groundY) or 0
  local clear,foliage,structural,other,total=0,0,0,0,0
  local sources={}
  local structuralSources={}
  local laterals={-BC_PASSIVE_READ_LATERAL,0,BC_PASSIVE_READ_LATERAL}
  for _,h in ipairs(BC_PASSIVE_READ_HEIGHTS) do
    for _,lat in ipairs(laterals) do
      total=total+1
      local target={sx+rx*lat,gy+h,sz+rz*lat}
      local blocked,source=bcGeomLine(cache,eye,target)
      if not blocked then
        clear=clear+1
      elseif bcFoliageLiftSource(source) then
        foliage=foliage+1
        local key=tostring(source or "foliage")
        sources[key]=(sources[key] or 0)+1
      else
        local sv=tostring(source or ""):lower()
        local isStructural=(sv=="shape:wall" or sv=="shape:building-fascia"
          or sv=="objectquad" or sv:find("objectquad:",1,true)==1
          or sv:find("building-fascia",1,true)~=nil)
        if isStructural then
          structural=structural+1
          local key=tostring(source or "structural")
          structuralSources[key]=(structuralSources[key] or 0)+1
        else
          other=other+1
        end
      end
    end
  end
  local dominant,dominantN=nil,0
  for source,n in pairs(sources) do
    if n>dominantN then dominant,dominantN=source,n end
  end
  local dominantStructural,dominantStructuralN=nil,0
  for source,n in pairs(structuralSources) do
    if n>dominantStructuralN then
      dominantStructural,dominantStructuralN=source,n
    end
  end
  return {clear=clear,foliage=foliage,structural=structural,other=other,total=total,
          dominant=dominant,dominantN=dominantN,
          dominantStructural=dominantStructural,
          dominantStructuralN=dominantStructuralN}
end

local function bcPassiveReadBad(r)
  return r and (tonumber(r.foliage) or 0)>=BC_PASSIVE_READ_BAD_FOLIAGE
end

local function bcPassiveReadGood(r)
  return r and (tonumber(r.clear) or 0)>=BC_PASSIVE_READ_GOOD_CLEAR
end

local function bcPassiveReadEssentiallyUnreadable(r)
  return r and (tonumber(r.clear) or 0)<=BC_PASSIVE_READ_MIXED_MAX_CLEAR
end

local function bcPassiveReadIntentBad(intent,p,e)
  local pStructural=p and (tonumber(p.structural) or 0)>=6
  local eStructural=e and (tonumber(e.structural) or 0)>=6
  if intent=="player" then return bcPassiveReadBad(p) or pStructural end
  if intent=="enemy" then return bcPassiveReadBad(e) or eStructural end
  if intent=="both" then
    -- Preserve Test 19's conservative foliage rule. Structural curtains are
    -- different: if either required battler is near-totally hidden by a wall /
    -- objectQuad, the authored BOTH composition has failed.
    return (bcPassiveReadBad(p) and bcPassiveReadEssentiallyUnreadable(e))
        or (bcPassiveReadBad(e) and bcPassiveReadEssentiallyUnreadable(p))
        or pStructural or eStructural
  end
  return false
end

local function bcPassiveReadIntentGood(intent,p,e)
  if intent=="player" then return bcPassiveReadGood(p) end
  if intent=="enemy" then return bcPassiveReadGood(e) end
  if intent=="both" then return bcPassiveReadGood(p) and bcPassiveReadGood(e) end
  return false
end

local function bcPassiveReadSource(intent,p,e)
  local function sourceFor(r)
    if r and (tonumber(r.structural) or 0)>=6 then
      return r.dominantStructural or "structural"
    end
    return r and r.dominant or "foliage"
  end
  if intent=="player" then return sourceFor(p) end
  if intent=="enemy" then return sourceFor(e) end
  if p and (tonumber(p.structural) or 0)>=6 then return sourceFor(p) end
  if e and (tonumber(e.structural) or 0)>=6 then return sourceFor(e) end
  local ps,es=p and p.dominant,e and e.dominant
  if ps and es and ps==es then return ps end
  return ps or es or "foliage"
end

local function bcPassiveEscapeInsideArena(arena,eye)
  if not (type(eye)=="table" and type(arena)=="table") then return false end
  if arena.discs then return true end
  local map=arena.map
  if not (type(map)=="table" and type(map.widthCells)=="number" and type(map.heightCells)=="number") then
    return true
  end
  local x,z=tonumber(eye[1]),tonumber(eye[3])
  if not (x and z) then return false end
  local m=BC_PASSIVE_ESCAPE_MAP_MARGIN
  return x>=m and z>=m and x<=map.widthCells*16.0-m and z<=map.heightCells*16.0-m
end

local function bcPassiveEscapeSafe(cache,arena,startEye,candidateEye)
  if not bcPassiveEscapeInsideArena(arena,candidateEye) then return false end
  local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
  if hardEye then return false end
  if type(startEye)=="table" then
    if select(1,bcGeomWallLine(cache,startEye,candidateEye)) then return false end
    if select(1,bcCanopyPathViolation(cache,startEye,candidateEye))>0.02 then return false end
  end
  return true
end

local function bcPassiveEscapeClearScore(intent,p,e)
  if intent=="player" then return tonumber(p and p.clear) or 0 end
  if intent=="enemy" then return tonumber(e and e.clear) or 0 end
  if intent=="both" then
    local pc,ec=tonumber(p and p.clear) or 0,tonumber(e and e.clear) or 0
    -- Minimum readability dominates; total clarity breaks ties. A 9/3 result
    -- must never outrank a genuinely readable 6/6 battlefield composition.
    return math.min(pc,ec)*20+pc+ec
  end
  return 0
end

local function bcPassiveFindReadableEscape(cache,arena,groundY,camera,prev,intent)
  if not (type(camera)=="table" and type(camera.eye)=="table" and type(camera.focus)=="table") then
    return nil
  end
  local ex,ez=tonumber(camera.eye[1]),tonumber(camera.eye[3])
  local fx,fz=tonumber(camera.focus[1]),tonumber(camera.focus[3])
  if not (ex and ez and fx and fz) then return nil end

  -- Local right vector relative to the authored viewing direction. This makes
  -- the fallback portable: no world/map axis and no preset-specific escape side.
  local vx,vz=fx-ex,fz-ez
  local len=math.sqrt(vx*vx+vz*vz)
  if len<1e-4 then return nil end
  local rightX,rightZ=-vz/len,vx/len
  local startEye=type(prev)=="table" and prev or camera.eye
  local best=nil

  for _,sideMag in ipairs(BC_PASSIVE_ESCAPE_SIDES) do
    for _,sign in ipairs({-1,1}) do
      local side=sideMag*sign
      for _,rise in ipairs(BC_PASSIVE_ESCAPE_RISES) do
        local candidateEye={
          camera.eye[1]+rightX*side,
          camera.eye[2]+rise,
          camera.eye[3]+rightZ*side,
        }
        if bcPassiveEscapeSafe(cache,arena,startEye,candidateEye) then
          local pp=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.player,groundY) or nil
          local ee=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.enemy,groundY) or nil
          if bcPassiveReadIntentGood(intent,pp,ee) then
            local deviation=math.sqrt(side*side+rise*rise)
            local clarity=bcPassiveEscapeClearScore(intent,pp,ee)
            if not best or deviation<best.deviation-0.01
                or (math.abs(deviation-best.deviation)<=0.01 and clarity>best.clarity) then
              best={eye=candidateEye,dx=rightX*side,dy=rise,dz=rightZ*side,
                    side=side,rise=rise,deviation=deviation,clarity=clarity,
                    player=pp,enemy=ee}
            end
          end
        end
      end
    end
  end
  return best
end

local function bcPassiveClearEscape(g)
  g.passiveEscapeToken=nil
  g.passiveEscapeDX=nil; g.passiveEscapeDY=nil; g.passiveEscapeDZ=nil
  g.passiveEscapeSide=nil; g.passiveEscapeRise=nil; g.passiveEscapeDeviation=nil
end

local function bcPassiveApplyEscapeLatch(cache,arena,camera,prev,g)
  if not (g.passiveEscapeToken and type(camera)=="table" and type(camera.eye)=="table") then
    return nil
  end
  local dx,dy,dz=tonumber(g.passiveEscapeDX),tonumber(g.passiveEscapeDY),tonumber(g.passiveEscapeDZ)
  if not (dx and dy and dz) then return nil end

  -- Store an offset, not an absolute eye: authored camera motion continues under
  -- the correction. Test 16's crest may already have established a higher safe Y;
  -- honour it while evaluating the moved segment.
  local target={camera.eye[1]+dx,camera.eye[2]+dy,camera.eye[3]+dz}
  local crestY=tonumber(g.canopyCrestY)
  if crestY and target[2]<crestY then target[2]=crestY end
  local from=type(prev)=="table" and prev or camera.eye

  if not bcPassiveEscapeSafe(cache,arena,from,target) then return nil end
  local nextEye=bcLerpVec(from,target,BC_PASSIVE_ESCAPE_ALPHA)
  if not bcPassiveEscapeSafe(cache,arena,from,nextEye) then return nil end
  return nextEye,target
end

local function bcApplyPassiveSubjectReadability(backend,arena,groundY,camera,base)
  local g=state.geomDiag
  local token=state.passiveShotToken
  local intent=state.passiveShotIntent
  local validIntent=(intent=="player" or intent=="enemy" or intent=="both")
  if state.battleOpening.active or state.intro.active or state.attack.active or state.faint.active or token==nil
      or not validIntent or not (type(camera)=="table" and type(camera.eye)=="table"
      and type(arena)=="table" and type(arena.map)=="table" and not arena.discs) then
    g.passiveReadToken=nil; g.passiveReadFrames=0; g.passiveReadIntent=nil
    g.passiveReadSource=nil; g.passiveReadTargetY=nil
    g.passiveReadPlayerClear=nil; g.passiveReadPlayerFoliage=nil
    g.passiveReadPlayerStructural=nil
    g.passiveReadEnemyClear=nil; g.passiveReadEnemyFoliage=nil
    g.passiveReadEnemyStructural=nil
    g.passiveReadPlayerOther=nil; g.passiveReadEnemyOther=nil
    g.passiveStructuralFallbackToken=nil
    g.passiveCinematicFallbackToken=nil
    g.passiveCinematicFallbackMode=nil
    g.passiveCinematicFallbackLane=nil
    g.passiveCinematicFallbackStartTime=nil
    bcPassiveClearEscape(g)
    return camera
  end

  if g.passiveReadToken~=token then
    g.passiveReadToken=token; g.passiveReadFrames=0; g.passiveReadIntent=intent
    g.passiveReadSource=nil; g.passiveReadTargetY=nil
    g.passiveStructuralFallbackToken=nil
    g.passiveCinematicFallbackToken=nil
    g.passiveCinematicFallbackMode=nil
    g.passiveCinematicFallbackLane=nil
    g.passiveCinematicFallbackStartTime=nil
    bcPassiveClearEscape(g)
  else
    g.passiveReadIntent=intent
  end

  -- RC8: once a shared structural substitute has been proven for this
  -- authored token, do not rerun the expensive 3x3 vertical/local-escape search
  -- every frame behind the same building. The wrapper revalidates/reapplies the
  -- shared camera after the rest of hard safety. This is especially important
  -- for DW3 shoulder shots, where RC7 footage visibly chugged while the same
  -- PASSIVE_STRUCTURAL_BASE_UNREADABLE search repeated for the entire scene.
  if g.passiveCinematicFallbackToken==token then
    g.action=(g.passiveCinematicFallbackMode=="roof")
        and "PASSIVE_SHARED_ROOF_HOLD" or "PASSIVE_SHARED_SIDE_HOLD"
    return camera
  end

  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return camera end
  local p=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,camera.eye,arena.player,groundY) or nil
  local e=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,camera.eye,arena.enemy,groundY) or nil
  g.passiveReadPlayerClear=p and p.clear or nil
  g.passiveReadPlayerFoliage=p and p.foliage or nil
  g.passiveReadPlayerStructural=p and p.structural or nil
  g.passiveReadPlayerOther=p and p.other or nil
  g.passiveReadEnemyClear=e and e.clear or nil
  g.passiveReadEnemyFoliage=e and e.foliage or nil
  g.passiveReadEnemyStructural=e and e.structural or nil
  g.passiveReadEnemyOther=e and e.other or nil

  local prev=g.prevEye

  -- Test 24: a structural fallback belongs only to the authored shot/token
  -- that proved impossible. Test 21 semantics release it at the next token.
  if g.passiveStructuralFallbackToken==token and type(base)=="table"
      and type(base.eye)=="table" then
    g.action="PASSIVE_STRUCTURAL_FALLBACK_HOLD"
    return base
  end

  -- A proven escape is held for the authored shot. Because this is a relative
  -- offset, any underlying sweep/orbit still moves; only the unsafe viewing lane
  -- is shifted. Never release/reacquire on one-frame visibility fluctuations.
  if g.passiveEscapeToken==token then
    local nextEye,target=bcPassiveApplyEscapeLatch(cache,arena,camera,prev,g)
    if nextEye then
      g.passiveReadTargetY=target and target[2] or nil
      g.liftClaimed=true
      g.liftSource=g.passiveReadSource or "foliage"
      g.action="PASSIVE_ESCAPE_HOLD"
      return bcCopyCameraWithEye(camera,nextEye)
    end
    -- Geometry moved underneath the authored path and made the latched route
    -- physically unsafe. Drop only the escape latch; the ordinary detector may
    -- acquire a new solution if the sustained presentation failure still exists.
    bcPassiveClearEscape(g)
    g.action="PASSIVE_ESCAPE_UNSAFE"
  end

  if not bcPassiveReadIntentBad(intent,p,e) then
    g.passiveReadFrames=0; g.passiveReadSource=nil; g.passiveReadTargetY=nil
    return camera
  end

  g.passiveReadFrames=(g.passiveReadFrames or 0)+1
  g.passiveReadSource=bcPassiveReadSource(intent,p,e)
  if g.passiveReadFrames<BC_PASSIVE_READ_TRIGGER_FRAMES then
    g.action="PASSIVE_READ_ARM"
    return camera
  end

  -- First choice is STILL Test 18/19's least-invasive vertical-only correction.
  -- Keep that solver byte-for-byte in behaviour; Test 20 begins only if it fails.
  local targetEye=nil
  for i=1,BC_PASSIVE_READ_SEARCH_STEPS do
    local candidateEye={camera.eye[1],camera.eye[2]+BC_PASSIVE_READ_STEP*i,camera.eye[3]}
    local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
    local hardPath=prev and select(1,bcGeomWallLine(cache,prev,candidateEye)) or false
    local canopyMiss=prev and select(1,bcCanopyPathViolation(cache,prev,candidateEye)) or 0
    if not hardEye and not hardPath and canopyMiss<=0.02 then
      local pp=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.player,groundY) or nil
      local ee=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.enemy,groundY) or nil
      if bcPassiveReadIntentGood(intent,pp,ee) then
        targetEye=candidateEye
        break
      end
    end
  end

  if targetEye then
    local fromY=prev and (tonumber(prev[2]) or tonumber(camera.eye[2]) or 0)
        or (tonumber(camera.eye[2]) or 0)
    local targetY=tonumber(targetEye[2]) or fromY
    local nextY=fromY+(targetY-fromY)*BC_PASSIVE_READ_ALPHA
    if targetY>fromY and nextY-fromY<BC_PASSIVE_READ_MIN_RISE then
      nextY=math.min(targetY,fromY+BC_PASSIVE_READ_MIN_RISE)
    end
    g.passiveReadTargetY=targetY
    g.liftClaimed=true
    g.liftSource=g.passiveReadSource or "foliage"
    g.action="PASSIVE_READ_LIFT"
    return bcCopyCameraWithEye(camera,{camera.eye[1],nextY,camera.eye[3]})
  end

  -- Test 20 begins here: vertical search has proved insufficient. Search only a
  -- small local neighbourhood and accept NOTHING that fails the exact same >=6/9
  -- authored-subject readability contract or any existing hard/path/canopy/map
  -- safety test. The nearest qualifying correction wins.
  local escape=bcPassiveFindReadableEscape(cache,arena,groundY,camera,prev,intent)
  if not escape then
    g.passiveReadTargetY=nil

    local pStructural=p and (tonumber(p.structural) or 0)>=6
    local eStructural=e and (tonumber(e.structural) or 0)>=6
    local structuralFailure=(intent=="player" and pStructural)
        or (intent=="enemy" and eStructural)
        or (intent=="both" and (pStructural or eStructural))

    if structuralFailure and type(base)=="table" and type(base.eye)=="table" then
      local bp=type(arena.player)=="table"
          and bcPassiveReadabilityEnvelope(cache,base.eye,arena.player,groundY) or nil
      local be=type(arena.enemy)=="table"
          and bcPassiveReadabilityEnvelope(cache,base.eye,arena.enemy,groundY) or nil
      if bcPassiveReadIntentGood(intent,bp,be) then
        g.passiveStructuralFallbackToken=token
        g.action="PASSIVE_STRUCTURAL_FALLBACK"
        return base
      end
      g.action="PASSIVE_STRUCTURAL_BASE_UNREADABLE"
      return camera
    end

    g.action="PASSIVE_ESCAPE_UNRESOLVED"
    return camera
  end

  g.passiveEscapeToken=token
  g.passiveEscapeDX=escape.dx; g.passiveEscapeDY=escape.dy; g.passiveEscapeDZ=escape.dz
  g.passiveEscapeSide=escape.side; g.passiveEscapeRise=escape.rise
  g.passiveEscapeDeviation=escape.deviation
  g.passiveReadTargetY=escape.eye[2]
  g.liftClaimed=true
  g.liftSource=g.passiveReadSource or "foliage"

  local nextEye=bcLerpVec(prev or camera.eye,escape.eye,BC_PASSIVE_ESCAPE_ALPHA)
  if not bcPassiveEscapeSafe(cache,arena,prev or camera.eye,nextEye) then
    bcPassiveClearEscape(g)
    g.action="PASSIVE_ESCAPE_UNRESOLVED"
    return camera
  end
  g.action="PASSIVE_ESCAPE_ACQUIRE"
  return bcCopyCameraWithEye(camera,nextEye)
end

-- Wall Safety Test 6 -------------------------------------------------------
-- Intervention policy is intentionally strict:
--   * shape.class == "wall" OR a camera physically entering shape:stump
--     can alter the camera.
--   * stump handling is occupancy/travel only; canopy/cylinder/tree foreground
--     is still cinematic and remains untouched.
--   * vertical building-facade quads can also alter the camera when a backend
--     exposes enough metadata to identify them.
--   * Building facades are identified either by explicit q.own metadata OR by
--     a vertical objectQuad intersecting a shapeAt class=building cell.
--   * cylinders / bollards / trees / roof quads / generic objectQuads remain
--     untouched.
--   * if the authored eye/path enters a wall, stop at the last sampled safe point.
--   * once a clear route around the wall exists again, ease back toward the
--     authored eye along that verified-clear segment.
-- This is a proof-of-behaviour test, not the final production avoidance system.
local function bcApplyWallSafety(backend,arena,camera,base)
  local g=state.geomDiag
  -- Structural Convergence RC5: this flag tells later view arbitration that
  -- hard safety substituted the backend-safe eye for an impossible authored
  -- passive shot on THIS evaluation. View safety must then judge that degraded
  -- eye on its own terms rather than reusing the abandoned authored shot's
  -- roof/fascia classification.
  g.hardFallbackAppliedThisFrame=false
  g.action="NONE"
  g.rawEye=type(camera)=="table" and type(camera.eye)=="table"
    and {camera.eye[1],camera.eye[2],camera.eye[3]} or nil

  if not (type(camera)=="table" and type(camera.eye)=="table"
      and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs) then
    g.wallClipActive=false
    return camera
  end

  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then
    g.wallClipActive=false
    return camera
  end

  local desired={camera.eye[1],camera.eye[2],camera.eye[3]}

  -- Structural Glide Test 28 -----------------------------------------------
  -- Test 21 proved that an authored passive shot/token boundary is a camera
  -- CUT, not physical continuous travel from the previous corrected eye.
  -- Apply that same semantic rule to hard wall/building path safety.
  local passiveToken=(not state.battleOpening.active and not state.intro.active and not state.attack.active and not state.faint.active)
      and state.passiveShotToken or nil
  local passiveShotBoundary=passiveToken~=nil and g.wallPathToken~=passiveToken
  if passiveToken~=nil then
    g.wallPathToken=passiveToken
  else
    g.wallPathToken=nil
  end
  if passiveShotBoundary then
    g.wallClipActive=false
    g.hardShotFallbackToken=nil
  end

  -- Structural Shot Authority Test 38:
  -- A passive authored scene is a semantic camera shot, not a request to drag
  -- the corrected eye along a wall for several seconds. Once THIS token has
  -- proven that its physical endpoint/path crosses hard geometry, yield the
  -- whole shot to the backend-safe camera and hold that decision until the next
  -- authored token. Foreground geometry that never intersects the physical
  -- path remains untouched.
  if passiveToken~=nil and g.hardShotFallbackToken==passiveToken
      and type(base)=="table" and type(base.eye)=="table" then
    local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
    if not baseBlocked then
      g.hardFallbackAppliedThisFrame=true
      g.action="HARD_SHOT_FALLBACK_HOLD"
      return base
    end
    g.hardShotFallbackToken=nil
  end

  -- An authored endpoint inside a semantic building envelope is not a route
  -- problem: that shot simply cannot physically exist there. Do not spend the
  -- scene repeatedly clipping against the facade. Hand only that shot to the
  -- backend-safe eye when one exists; the next authored token gets a fresh try.
  local desiredBlocked,desiredSource=bcGeomWallPoint(cache,desired[1],desired[2],desired[3])
  local desiredInsideBuilding=desiredBlocked
      and (tostring(desiredSource or ""):find("building-fascia",1,true)~=nil
        or tostring(desiredSource or ""):find("building-envelope",1,true)~=nil)

  if passiveShotBoundary then
    g.structuralSafeToken=nil
  end

  if passiveToken~=nil and g.structuralSafeToken==passiveToken
      and type(base)=="table" and type(base.eye)=="table" then
    local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
    if not baseBlocked then
      g.action="STRUCTURAL_SAFE_HOLD"
      return bcCopyCameraWithEye(camera,base.eye)
    end
    g.structuralSafeToken=nil
  end

  if desiredBlocked and passiveToken~=nil and type(base)=="table" and type(base.eye)=="table" then
    local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
    if not baseBlocked then
      g.hardShotFallbackToken=passiveToken
      g.hardFallbackAppliedThisFrame=true
      -- Any roof/crest state acquired before this point belonged to the
      -- abandoned authored eye. Do not let it survive onto the backend-safe
      -- fallback eye and manufacture a sub-roof "crest" from stale semantics.
      g.canopyClearActive=false
      g.canopyClearTop=nil
      g.canopyClearTargetY=nil
      g.canopyClearSource=nil
      g.canopyCrestToken=nil
      g.canopyCrestY=nil
      g.canopyCrestSource=nil
      g.wallClipActive=false
      g.action="HARD_SHOT_FALLBACK"
      return base
    end
  elseif desiredInsideBuilding and type(base)=="table" and type(base.eye)=="table" then
    -- Preserve the pre-existing non-passive structural safe-eye behaviour.
    local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
    if not baseBlocked then
      if passiveToken~=nil then g.structuralSafeToken=passiveToken end
      g.wallClipActive=false
      g.action="STRUCTURAL_SAFE_EYE"
      return bcCopyCameraWithEye(camera,base.eye)
    end
  end

  -- New authored shot: evaluate the endpoint immediately, but do not invent
  -- a straight-line journey from the previous shot through intervening geometry.
  local prev=passiveShotBoundary and nil or g.prevEye
  if not prev then
    local eyeBlocked=bcGeomWallPoint(cache,desired[1],desired[2],desired[3])
    if not eyeBlocked then
      g.wallClipActive=false
      return camera
    end
    if type(base)=="table" and type(base.eye)=="table" then
      local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
      if not baseBlocked then
        if passiveToken~=nil then
          g.hardShotFallbackToken=passiveToken
          g.hardFallbackAppliedThisFrame=true
          g.canopyClearActive=false
          g.canopyClearTop=nil
          g.canopyClearTargetY=nil
          g.canopyClearSource=nil
          g.canopyCrestToken=nil
          g.canopyCrestY=nil
          g.canopyCrestSource=nil
          g.wallClipActive=false
          g.action="HARD_SHOT_FALLBACK"
          return base
        end
        g.wallClipActive=true
        g.action="SAFE_EYE"
        return bcCopyCameraWithEye(camera,base.eye)
      end
    end
    g.action="CLIP_PATH"
    return camera
  end

  local blocked,source,hit,lastSafe=bcGeomWallLine(cache,prev,desired)
  if blocked then
    if passiveToken~=nil and type(base)=="table" and type(base.eye)=="table" then
      local baseBlocked=bcGeomWallPoint(cache,base.eye[1],base.eye[2],base.eye[3])
      if not baseBlocked then
        g.hardShotFallbackToken=passiveToken
        g.hardFallbackAppliedThisFrame=true
        g.canopyClearActive=false
        g.canopyClearTop=nil
        g.canopyClearTargetY=nil
        g.canopyClearSource=nil
        g.canopyCrestToken=nil
        g.canopyCrestY=nil
        g.canopyCrestSource=nil
        g.wallClipActive=false
        g.action="HARD_SHOT_FALLBACK"
        return base
      end
    end
    g.wallClipActive=true
    g.action="CLIP_PATH"
    if type(lastSafe)=="table" and bcVecDistance(prev,lastSafe)>0.02 then
      return bcCopyCameraWithEye(camera,lastSafe)
    end
    -- Holding the previous verified output is safer than entering the wall.
    return bcCopyCameraWithEye(camera,prev)
  end

  if g.wallClipActive then
    local dist=bcVecDistance(prev,desired)
    if dist>BC_WALL_RECOVER_DONE then
      local candidate=bcLerpVec(prev,desired,BC_WALL_RECOVER_ALPHA)
      local recBlocked=bcGeomWallLine(cache,prev,candidate)
      if not recBlocked then
        g.action="RECOVER"
        return bcCopyCameraWithEye(camera,candidate)
      end
      g.action="CLIP_PATH"
      return bcCopyCameraWithEye(camera,prev)
    end
    g.wallClipActive=false
    g.action="NONE"
  end

  return camera
end


-- View-barrier classifier --------------------------------------------------
-- Power Plant exposes a second representation that Test 4 cannot orient:
-- the facade is rendered as generic objectQuads, while shapeAt at the hit cell
-- identifies class=building with h=0. The bad DW3 sequence is distinctive:
-- focus + player + enemy rays are all blocked by objectQuad hits on building
-- cells, while the liked roof skim has readable rays.
--
-- This classifier is VIEW-ONLY. It does NOT make every objectQuad solid and it
-- does NOT turn roofs into collision. It simply lets the existing minimal
-- VIEW_CLEAR / VIEW_RECOVER machinery recognise a total building curtain.
local function bcGeomViewBarrierPoint(cache,wx,wy,wz)
  if not (cache and cache.supported and wx and wy and wz) then return false,nil end

  local shape=bcGeomShapeAt(cache,wx,wz)
  local shapeClass=""
  if type(shape)=="table" then
    shapeClass=tostring(shape.class or ""):lower()
    if not shape.flat then
      local h=tonumber(shape.h) or 0
      if shapeClass=="wall" and h>0 and wy>=-BC_GEOM_EPS and wy<=h+BC_GEOM_EPS then
        return true,"shape:wall"
      end
    end
  end

  -- Shell View Owner Test 44 ----------------------------------------------
  -- Test 43 correctly propagated component ownership from buildingFasciaNear,
  -- but this earlier rendered-shell branch still returned only the semantic
  -- source string. Because it runs first on the awkward Power Plant facade,
  -- the view pipeline still lost the exact building/roof identity and fell
  -- through to legacy VIEW_CLEAR. Preserve the shell's owner and roof top here.
  if cache.buildingShellPoint then
    local shellComp,shellTop=cache.buildingShellPoint(wx,wy,wz)
    if shellComp then
      return true,"shape:building-fascia",shellComp,tonumber(shellTop) or tonumber(shellComp.top)
    end
  end

  -- Building view barriers use the exact same synthetic fascia/body as hard
  -- occupancy and generic LOS. Total-view recovery therefore receives one
  -- coherent structure instead of a broad anonymous objectQuad curtain.
  if cache.buildingFasciaNear then
    local comp,env=cache.buildingFasciaNear(wx,wz)
    if comp and env then
      local top=tonumber(env.top) or tonumber(comp.top)
      if top and wy>=-BC_GEOM_EPS and wy<=top+BC_GEOM_EPS then
        return true,"shape:building-fascia",comp,top
      end
    end
  end

  return false,nil
end

local function bcGeomViewBarrierLine(cache,a,b)
  if not (cache and cache.supported and type(a)=="table" and type(b)=="table") then
    return false,nil,nil
  end
  local ax,ay,az=tonumber(a[1]) or 0,tonumber(a[2]) or 0,tonumber(a[3]) or 0
  local bx,by,bz=tonumber(b[1]) or 0,tonumber(b[2]) or 0,tonumber(b[3]) or 0
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local steps=math.max(1,math.ceil(len/BC_GEOM_STEP))
  for i=0,steps do
    local t=i/steps
    local p={ax+dx*t,ay+dy*t,az+dz*t}
    local blocked,source,ownerComp,ownerTop=bcGeomViewBarrierPoint(cache,p[1],p[2],p[3])
    if blocked then
      -- Test 48: lineage repair / contiguous owner graft ------------------
      -- Test 47 was intended to add ONLY this association on top of the
      -- proven Test 46 semantic-view arbitration, but its packaged source
      -- accidentally came from an older branch and dropped Test 46's actual
      -- arbitration. Preserve Test 46 intact and graft the intended Test 47
      -- rule here: if the first view hit is an ownerless generic wall, follow
      -- only the uninterrupted blocked samples on this SAME ray. If that same
      -- continuous occluding mass becomes component-owned building fascia,
      -- let the first hit inherit that component/roof. A clear sample ends the
      -- relationship, so an unrelated wall cannot steal a distant building.
      if tostring(source or ""):lower()=="shape:wall" and not ownerComp then
        for j=i+1,steps do
          local tj=j/steps
          local q={ax+dx*tj,ay+dy*tj,az+dz*tj}
          local b2,s2,c2,t2=bcGeomViewBarrierPoint(cache,q[1],q[2],q[3])
          if not b2 then break end
          local sv2=tostring(s2 or ""):lower()
          if c2 and sv2:find("building%-fascia",1,false)~=nil then
            return true,"shape:building-fascia",p,c2,
                tonumber(t2) or tonumber(c2.top)
          end
          if sv2~="shape:wall" then break end
        end
      end
      return true,source,p,ownerComp,ownerTop
    end
  end
  return false,nil,nil
end


-- Sustained-view lift classifier -------------------------------------------
-- Test 6 adds a second, deliberately different response to geometry:
-- do NOT treat foreground scenery as collision. Instead, when the authored
-- camera is physically valid but the WHOLE battle remains hidden behind a
-- tree-family volume or an anonymous building curtain for several consecutive
-- camera evaluations, preserve X/Z/orbit/FOV and raise only the eye height.
--
-- This is intentionally separate from hard wall/stump traversal safety:
--   * brief ledge/bollard/tree wipes remain cinematic and untouched;
--   * Route 1/6/8 positive controls should therefore remain unchanged;
--   * Power Plant roof skims remain legal because a roof/objectQuad by itself
--     is never enough -- all three battle rays must be hidden persistently;
--   * Viridian Forest can "peek over" tree/stump/canopy geometry instead of
--     replacing the whole shot with a generic safe-eye camera.
local function bcGeomLiftBarrierPoint(cache,wx,wy,wz)
  if not (cache and cache.supported and wx and wy and wz) then return false,nil end

  local shape=bcGeomShapeAt(cache,wx,wz)
  local shapeClass=""
  if type(shape)=="table" then
    shapeClass=tostring(shape.class or ""):lower()
    if not shape.flat then
      local h=tonumber(shape.h) or 0
      if h>0 and wy>=-BC_GEOM_EPS and wy<=h+BC_GEOM_EPS then
        if shapeClass=="tree" or shapeClass=="stump" or shapeClass=="canopy" then
          return true,"shape:"..shapeClass
        end
      end
    end
  end

  -- Buildings are deliberately NOT inferred here anymore. The old generic
  -- whole-view lift predated the semantic composite and could skyrocket a shot
  -- while the newer intent-aware structural fallback was waiting behind it.
  -- Tree/stump/canopy keep this proven vertical-lift language; buildings now
  -- use fascia hard safety + roof clearance + structural readability.

  return false,nil
end

local function bcGeomLiftBarrierLine(cache,a,b)
  if not (cache and cache.supported and type(a)=="table" and type(b)=="table") then
    return false,nil,nil
  end
  local ax,ay,az=tonumber(a[1]) or 0,tonumber(a[2]) or 0,tonumber(a[3]) or 0
  local bx,by,bz=tonumber(b[1]) or 0,tonumber(b[2]) or 0,tonumber(b[3]) or 0
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local steps=math.max(1,math.ceil(len/BC_GEOM_STEP))
  for i=0,steps do
    local t=i/steps
    local p={ax+dx*t,ay+dy*t,az+dz*t}
    local blocked,source=bcGeomLiftBarrierPoint(cache,p[1],p[2],p[3])
    if blocked then return true,source,p end
  end
  return false,nil,nil
end

local function bcLiftViewFlags(cache,arena,groundY,camera)
  if not (cache and cache.supported and type(arena)=="table"
      and type(camera)=="table" and type(camera.eye)=="table") then
    return false,false,false,nil,nil,nil
  end
  local eye=camera.eye
  local f,fs=false,nil
  local p,ps=false,nil
  local e,es=false,nil
  if type(camera.focus)=="table" then
    f,fs=bcGeomLiftBarrierLine(cache,eye,camera.focus)
  end
  local gy=tonumber(groundY) or 0
  if type(arena.player)=="table" then
    p,ps=bcGeomLiftBarrierLine(cache,eye,{arena.player[1],gy+8.0,arena.player[2]})
  end
  if type(arena.enemy)=="table" then
    e,es=bcGeomLiftBarrierLine(cache,eye,{arena.enemy[1],gy+8.0,arena.enemy[2]})
  end
  return f and true or false,p and true or false,e and true or false,fs,ps,es
end

local function bcLiftViewUsable(cache,arena,groundY,camera)
  local f,p,e=bcLiftViewFlags(cache,arena,groundY,camera)
  -- Same readability contract as wall-view safety: authored focus plus at least
  -- one battler must be visible. The trigger is much stricter: all three rays
  -- must have been hidden for several consecutive evaluations.
  return (not f) and ((not p) or (not e)),f,p,e
end

local BC_VIEW_LIFT_TRIGGER_FRAMES=4
local BC_VIEW_LIFT_CLEAR_FRAMES=4
local BC_VIEW_LIFT_SEARCH_STEPS=16
local BC_VIEW_LIFT_STEP=2.0
local BC_VIEW_LIFT_ALPHA=0.34
local BC_VIEW_LIFT_RECOVER_ALPHA=0.18
local BC_VIEW_LIFT_DONE=0.55

local function bcLiftSourceLabel(fs,ps,es)
  local all={tostring(fs or ""),tostring(ps or ""),tostring(es or "")}
  for _,v in ipairs(all) do
    if v:find("building%-curtain",1,false) then return "building" end
  end
  for _,v in ipairs(all) do
    if v:find("canopy",1,true) then return "canopy" end
  end
  for _,v in ipairs(all) do
    if v:find("stump",1,true) then return "stump" end
  end
  for _,v in ipairs(all) do
    if v:find("tree",1,true) then return "tree" end
  end
  return "mixed"
end

local function bcApplyVerticalViewSafety(backend,arena,groundY,camera,base)
  local g=state.geomDiag
  g.liftClaimed=false

  if not (type(camera)=="table" and type(camera.eye)=="table"
      and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs) then
    g.liftActive=false
    g.liftBlockedFrames=0
    g.liftClearFrames=0
    g.liftTargetY=nil
    g.liftSource=nil
    return camera,false
  end

  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then
    g.liftActive=false
    g.liftBlockedFrames=0
    g.liftClearFrames=0
    return camera,false
  end

  local desired=camera
  local fBlocked,pBlocked,eBlocked,fs,ps,es=bcLiftViewFlags(cache,arena,groundY,desired)
  local allBlocked=fBlocked and pBlocked and eBlocked
  local prev=g.prevEye

  if allBlocked then
    g.liftBlockedFrames=(g.liftBlockedFrames or 0)+1
    g.liftClearFrames=0
    g.liftSource=bcLiftSourceLabel(fs,ps,es)
  else
    g.liftBlockedFrames=0
    if g.liftActive then
      g.liftClearFrames=(g.liftClearFrames or 0)+1
    else
      g.liftClearFrames=0
      g.liftSource=nil
    end
  end

  -- Debounce: a one-frame tree/rock/building wipe is exactly the environmental
  -- cinematography we want to preserve. Only claim the camera after sustained
  -- total occlusion. While arming, suppress the older lateral building-view
  -- fallback so this test genuinely measures the vertical-escape strategy.
  if allBlocked and not g.liftActive
      and (g.liftBlockedFrames or 0)<BC_VIEW_LIFT_TRIGGER_FRAMES then
    g.liftClaimed=true
    g.action="VIEW_LIFT_ARM"
    return desired,true
  end

  if allBlocked then
    local targetEye=nil
    for i=1,BC_VIEW_LIFT_SEARCH_STEPS do
      local candidateEye={desired.eye[1],desired.eye[2]+BC_VIEW_LIFT_STEP*i,desired.eye[3]}
      local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
      local hardPath=false
      if prev then hardPath=select(1,bcGeomWallLine(cache,prev,candidateEye)) end
      if not hardEye and not hardPath then
        local candidate=bcCopyCameraWithEye(desired,candidateEye)
        local usable=bcLiftViewUsable(cache,arena,groundY,candidate)
        if usable then
          targetEye=candidateEye
          break
        end
      end
    end

    if targetEye then
      g.liftActive=true
      g.liftClaimed=true
      g.liftTargetY=targetEye[2]
      local fromY=prev and tonumber(prev[2]) or tonumber(desired.eye[2]) or 0
      local targetY=tonumber(targetEye[2]) or fromY
      local nextY=fromY+(targetY-fromY)*BC_VIEW_LIFT_ALPHA
      -- Guarantee perceptible but still smooth progress out of a sustained
      -- obstruction instead of spending many frames buried in foliage.
      if targetY>fromY and (nextY-fromY)<0.75 then
        nextY=math.min(targetY,fromY+0.75)
      end
      local outEye={desired.eye[1],nextY,desired.eye[3]}
      if prev and select(1,bcGeomWallLine(cache,prev,outEye)) then
        -- If continuing the authored X/Z sweep would cross a proven hard wall,
        -- lift in place for this evaluation. Wall safety remains authoritative.
        outEye={prev[1],nextY,prev[3]}
      end
      if math.abs(targetY-nextY)<=BC_VIEW_LIFT_DONE then
        g.action="VIEW_LIFT_HOLD"
      else
        g.action="VIEW_LIFT"
      end
      return bcCopyCameraWithEye(desired,outEye),true
    end

    -- Could not find a readable vertical escape. Do not invent a blind height;
    -- let the already-proven wall/building fallback get a chance instead.
    g.liftActive=false
    g.liftClaimed=false
    g.liftTargetY=nil
    g.action="VIEW_LIFT_UNRESOLVED"
    return desired,false
  end

  if g.liftActive then
    g.liftClaimed=true
    if (g.liftClearFrames or 0)<BC_VIEW_LIFT_CLEAR_FRAMES then
      if prev then
        local holdY=math.max(tonumber(prev[2]) or 0,tonumber(desired.eye[2]) or 0)
        g.action="VIEW_LIFT_HOLD"
        return bcCopyCameraWithEye(desired,{desired.eye[1],holdY,desired.eye[3]}),true
      end
      g.action="VIEW_LIFT_HOLD"
      return desired,true
    end

    if prev then
      local fromY=tonumber(prev[2]) or tonumber(desired.eye[2]) or 0
      local authoredY=tonumber(desired.eye[2]) or fromY
      if math.abs(fromY-authoredY)>BC_VIEW_LIFT_DONE then
        local nextY=fromY+(authoredY-fromY)*BC_VIEW_LIFT_RECOVER_ALPHA
        local outEye={desired.eye[1],nextY,desired.eye[3]}
        if not select(1,bcGeomWallLine(cache,prev,outEye)) then
          g.action="VIEW_LIFT_RECOVER"
          return bcCopyCameraWithEye(desired,outEye),true
        end
      end
    end

    g.liftActive=false
    g.liftClaimed=false
    g.liftTargetY=nil
    g.liftSource=nil
    g.liftClearFrames=0
  end

  return desired,false
end


-- Wall-view Safety Test 5 --------------------------------------------------
-- Tests 1-4 proved that structural shape:wall handling fixes Mt. Moon and
-- Stadium wall traversal without disturbing the Route 1 / Route 6 / Route 8
-- foreground-graze controls. Test 5 adds two evidence-led gaps:
--
--   * shape:stump is a hard EYE/PATH obstacle only, for the Viridian Forest
--     full-screen trunk case. Canopy/cylinder/ordinary tree foreground remains.
--   * a generic objectQuad sampled on a shapeAt class=building cell may count
--     as a VIEW barrier, but only the existing all-three-rays trigger can move
--     the camera. This targets Dramatic 1.8's Power Plant facade representation.
--   * Facades with explicit q.own / orientation metadata remain supported too.
--   * roof/top objectQuads, ledges, cylinders, bollards and trees are untouched.
--   * a correction is considered only when focus + BOTH battlers are hidden
--     behind wall volumes at the same time.
--   * when that happens, move the eye the minimum amount toward the backend's
--     proven native eye until the focus and at least one battler are wall-clear.
--   * once the authored view becomes viable again, ease back rather than snap.
--
-- This intentionally preserves roof passes and environmental foreground wipes.
local BC_WALL_VIEW_SEARCH_STEPS=14
local BC_WALL_VIEW_RECOVER_ALPHA=0.18
local BC_WALL_VIEW_RECOVER_DONE=0.85

local function bcWallViewFlags(cache,arena,groundY,camera)
  if not (cache and cache.supported and type(arena)=="table"
      and type(camera)=="table" and type(camera.eye)=="table") then
    return false,false,false
  end
  local eye=camera.eye
  local focusBlocked=false
  if type(camera.focus)=="table" then
    focusBlocked=select(1,bcGeomViewBarrierLine(cache,eye,camera.focus)) and true or false
  end
  local gy=tonumber(groundY) or 0
  local playerBlocked=false
  local enemyBlocked=false
  if type(arena.player)=="table" then
    playerBlocked=select(1,bcGeomViewBarrierLine(cache,eye,{arena.player[1],gy+8.0,arena.player[2]})) and true or false
  end
  if type(arena.enemy)=="table" then
    enemyBlocked=select(1,bcGeomViewBarrierLine(cache,eye,{arena.enemy[1],gy+8.0,arena.enemy[2]})) and true or false
  end
  return focusBlocked,playerBlocked,enemyBlocked
end

local function bcWallViewUsable(cache,arena,groundY,camera)
  local f,p,e=bcWallViewFlags(cache,arena,groundY,camera)
  -- A usable correction must expose the authored focus and at least one actor.
  -- Triggering remains stricter than acceptance: we only intervene when all
  -- three rays are wall-blocked at the authored eye.
  return (not f) and ((not p) or (not e)),f,p,e
end

local function bcRememberWallView(g,camera,usable)
  if usable and type(camera)=="table" and type(camera.eye)=="table" then
    g.lastWallViewEye={camera.eye[1],camera.eye[2],camera.eye[3]}
  end
end

-- Fascia<->Roof View Test 39 ---------------------------------------------
-- Global helper names are intentional in this diagnostic build: main.lua is at
-- Lua's local-variable limit. They remain BC-prefixed and are not exported.
function bcBuildingRoofFromViewRay40(cache,a,b)
  if not (cache and type(a)=="table" and type(b)=="table") then return nil,nil,nil end

  -- Test 39 associated a blocked view with a roof by reverse-looking-up the
  -- barrier HIT point. That works on small/simple buildings (Route 12), but on
  -- large rendered facades the barrier sample can sit on the synthetic hull
  -- fringe where shellPoint/FasciaNear cannot recover a component. The HUD then
  -- says VIEW_CLEAR + shape:building-fascia while STRUCT VIEW ROOF stays nil.
  --
  -- Test 40 keeps the direct hit lookup first, then asks the SAME blocked view
  -- ray which BC building component its X/Z course crosses. This is the
  -- composite equivalent of asking a stump which canopy belongs above it: the
  -- relationship comes from the structure, not from the exact spelling/location
  -- of one sampled facade hit.
  local blocked,source,hit,ownerComp,ownerTop=bcGeomViewBarrierLine(cache,a,b)
  if not blocked then return nil,nil,hit end

  local sv=tostring(source or ""):lower()
  -- Composite View Owner Test 42 ------------------------------------------
  -- Test 41 proves the remaining Power Plant interaction is still acquired
  -- inside the CURRENT authored shot: VIEW_CLEAR begins while the HUD can
  -- already see shape:building-fascia, but STRUCT VIEW ROOF remains nil.
  -- The synthetic fascia query actually knows which component produced that
  -- barrier; older code threw that identity away and then tried to reverse-
  -- lookup the sampled hit point. Large/edge facades are exactly where that
  -- reverse lookup can fail. Preserve the owner through the barrier ray itself.
  local comp,top=ownerComp,tonumber(ownerTop)
  if not comp and sv:find("building%-fascia",1,false)~=nil and type(hit)=="table" then
    if cache.buildingShellPoint then comp,top=cache.buildingShellPoint(hit[1],hit[2],hit[3]) end
    if not comp and cache.buildingFasciaNear then
      local c,e=cache.buildingFasciaNear(hit[1],hit[3])
      comp=c; top=e and tonumber(e.top) or (c and tonumber(c.top) or nil)
    end
    if not comp and cache.buildingShellNear then comp,top=cache.buildingShellNear(hit[1],hit[3],4.0) end
  end

  if not comp and cache.buildingRouteTop then
    local routeTop,routeComp,firstDist=cache.buildingRouteTop(a,b,BC_BUILDING_HULL_PAD,1.0)
    if routeComp and routeTop then
      local accept=true
      if type(hit)=="table" and firstDist then
        local hx=(tonumber(hit[1]) or 0)-(tonumber(a[1]) or 0)
        local hy=(tonumber(hit[2]) or 0)-(tonumber(a[2]) or 0)
        local hz=(tonumber(hit[3]) or 0)-(tonumber(a[3]) or 0)
        local hitDist=math.sqrt(hx*hx+hy*hy+hz*hz)
        -- Only claim the barrier when the building begins at/before the barrier
        -- neighbourhood. A distant building behind an unrelated cave wall must
        -- not steal ordinary wall-view behaviour.
        accept=firstDist<=hitDist+BC_BUILDING_HULL_PAD+1.0
      end
      if accept then comp,top=routeComp,routeTop end
    end
  end

  top=tonumber(top) or (comp and tonumber(comp.top) or nil)
  return comp,top,hit
end

-- Authored View Provenance Test 45 -----------------------------------------
-- Diagnostic only: record the FIRST raw authored-eye view barrier before any
-- VIEW_CLEAR movement, plus any building owner/top and route association.
function bcViewTrace45(cache,a,b)
  if not (cache and type(a)=="table" and type(b)=="table") then return "n/a" end
  local blocked,source,hit,ownerComp,ownerTop=bcGeomViewBarrierLine(cache,a,b)
  if not blocked then return "clear" end
  local ownerId=ownerComp and tostring(ownerComp.id or "?") or "nil"
  local ownerY=tonumber(ownerTop) or (ownerComp and tonumber(ownerComp.top) or nil)
  local hitDist=nil
  if type(hit)=="table" then
    local dx=(tonumber(hit[1]) or 0)-(tonumber(a[1]) or 0)
    local dy=(tonumber(hit[2]) or 0)-(tonumber(a[2]) or 0)
    local dz=(tonumber(hit[3]) or 0)-(tonumber(a[3]) or 0)
    hitDist=math.sqrt(dx*dx+dy*dy+dz*dz)
  end
  local routeId="nil"
  local routeY=nil
  local firstDist=nil
  if cache.buildingRouteTop then
    local rt,rc,fd=cache.buildingRouteTop(a,b,BC_BUILDING_HULL_PAD,1.0)
    if rc and rt then
      routeId=tostring(rc.id or "?")
      routeY=tonumber(rt)
      firstDist=tonumber(fd)
    end
  end
  return string.format("src=%s own=%s/%s hit=%s route=%s/%s first=%s",
    tostring(source or "nil"),ownerId,bcDiagNum(ownerY),bcDiagNum(hitDist),
    routeId,bcDiagNum(routeY),bcDiagNum(firstDist))
end

function bcStructuralViewRoofTarget40(cache,arena,groundY,camera)
  if not (cache and type(arena)=="table" and type(camera)=="table" and type(camera.eye)=="table") then
    return nil,nil,nil
  end
  local eye=camera.eye
  local gy=tonumber(groundY) or 0
  local roofTop=nil
  local ids={}
  local seen={}
  local function add(target)
    if type(target)~="table" then return end
    local c,t=bcBuildingRoofFromViewRay40(cache,eye,target)
    if c and t then
      roofTop=roofTop and math.max(roofTop,t) or t
      local id=tostring(c.id or "?")
      if not seen[id] then ids[#ids+1]=id; seen[id]=true end
    end
  end
  if type(camera.focus)=="table" then add(camera.focus) end
  if type(arena.player)=="table" then add({arena.player[1],gy+8.0,arena.player[2]}) end
  if type(arena.enemy)=="table" then add({arena.enemy[1],gy+8.0,arena.enemy[2]}) end
  if not roofTop then return nil,nil,nil end
  return roofTop+5.0,roofTop,table.concat(ids,",")
end

-- Structural Convergence RC1 ---------------------------------------------
-- Tests 50-54 were intentionally NOT carried forward as behavioural layers.
-- Their Power Plant result exposed that a building-curtain failure could end
-- up in a whole-shot native-eye fallback before the newer side-glide code ever
-- ran. Return to the proven Test49 branch and solve the arbitration directly:
--   * when the eye is still in the local roof neighbourhood, the proven
--     Test39/40 roof lane gets first refusal;
--   * when the authored eye is already comfortably above that roof yet the
--     intended subject is hidden by fascia, do not climb and do not jump to the
--     backend eye. Hold the last purpose-readable point on the AUTHORED path and
--     advance it only as far as the current path remains readable. The result is
--     a geometry-derived facade standoff with gentle authored motion, not a
--     hardcoded map radius or an invented camera journey.
function bcConvergenceIntentGoodRC1(cache,arena,groundY,eye,intent)
  if not (cache and type(eye)=="table") then return false end
  local pp=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,eye,arena.player,groundY) or nil
  local ee=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,eye,arena.enemy,groundY) or nil
  return bcPassiveReadIntentGood(intent,pp,ee)
end

function bcConvergenceRoofLaneRC1(cache,arena,groundY,desired,intent,roofTarget,roofTop,roofComps)
  local eyeY=tonumber(desired.eye and desired.eye[2])
  roofTarget=tonumber(roofTarget); roofTop=tonumber(roofTop)
  if not (eyeY and roofTarget and roofTop) then return nil end

  -- RC14: classification no longer lives inside this vertical search. RC13
  -- proved that the old `roofTarget + 6` neighbourhood was semantically wrong:
  -- a DW3 shoulder eye could still be safely ABOVE the roof, cross that arbitrary
  -- height threshold, and suddenly be promoted to a much higher whole-view roof
  -- lane. The caller now distinguishes a true below-roof crossing from a shot
  -- that approached the same roof from above. This helper only answers: if a
  -- genuine roof-crossing shot needs a clean view lane, what is the first safe,
  -- readable Y at the current X/Z?

  -- Preserve Test39's useful vertical search depth for a proven roof-crossing.
  -- This remains relative to the local component roof, never a low/high map class.
  local searchTop=roofTarget+20.0
  local startY=math.max(eyeY,roofTarget)
  for i=0,10 do
    local y=startY+i*2.0
    if y>searchTop+0.25 then break end
    local candidateEye={desired.eye[1],y,desired.eye[3]}
    local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
    local hardPath=select(1,bcGeomWallLine(cache,desired.eye,candidateEye))
    if not hardEye and not hardPath then
      local candidate=bcCopyCameraWithEye(desired,candidateEye)
      local usable=bcWallViewUsable(cache,arena,groundY,candidate)
      if usable and bcConvergenceIntentGoodRC1(cache,arena,groundY,candidateEye,intent) then
        state.geomDiag.canopyClearActive=true
        state.geomDiag.canopyClearTop=roofTop
        state.geomDiag.canopyClearTargetY=y
        state.geomDiag.canopyClearSource="shape:building-roof"
        state.geomDiag.structuralViewRoofComps=roofComps
        state.geomDiag.structuralViewRoofTargetY=y
        return candidate
      end
    end
  end
  return nil
end

-- Structural Convergence RC14 --------------------------------------------
-- Test 16/21's canopy lesson translated to the building roof semantic:
-- the same roof can mean two very different things to a passive shot.
--
--   * CROSSING_BELOW: the authored camera first meets this local roof with its
--     eye below the roof plane. The shot is genuinely trying to cross the
--     building; give roof/top a clean vertical-first view lane before X/Z
--     continues (Route 12 / stepped-city pass language).
--
--   * DESCENDING_ABOVE: the shot first meets the roof while already above its
--     plane. Do NOT reinterpret that as a request to clear every view ray by
--     climbing. Let the physically-safe authored shot continue. If it later
--     descends into the roof clearance floor, the existing ROOF_DESCENT_CREST
--     remembers the previous presented Y for this token, like Test16's canopy
--     crest. This is the Celadon DW3 shoulder-bounce case.
--
-- Keep the classification for the same local roof event. A later stepped roof
-- (different owner/top) is a new event and is classified independently.
function bcRoofComponentOverlapRC14(a,b)
  a=tostring(a or "")
  b=tostring(b or "")
  if a=="" or b=="" then return a==b end
  local seen={}
  for id in a:gmatch("[^,]+") do seen[id]=true end
  for id in b:gmatch("[^,]+") do if seen[id] then return true end end
  return false
end

function bcRoofApproachModeRC14(g,token,authoredY,roofTop,roofComps)
  if not (g and token~=nil and tonumber(authoredY) and tonumber(roofTop)) then return nil end
  local ay,top=tonumber(authoredY),tonumber(roofTop)
  local comps=tostring(roofComps or "")
  local same=(g.roofApproachToken==token)
      and tonumber(g.roofApproachTop)
      and math.abs((tonumber(g.roofApproachTop) or top)-top)<=0.75
      and bcRoofComponentOverlapRC14(g.roofApproachComps,comps)
  if not same then
    g.roofApproachToken=token
    g.roofApproachTop=top
    g.roofApproachComps=comps
    g.roofApproachTargetY=nil
    g.roofApproachEntryY=ay
    g.roofApproachMode=(ay<=top+0.25) and "crossing_below" or "descending_above"
  elseif comps~="" then
    -- Keep the most recent witness set for diagnostics while preserving the
    -- first-contact classification for this local roof event.
    g.roofApproachComps=comps
  end
  return g.roofApproachMode
end

-- A true below-roof crossing gets the clean roof view lane on the FIRST frame
-- the semantic roof is known. Do not hold the previous X/Z while climbing: that
-- recreates the visual 'hang then catch up' we already rejected. The candidate
-- search above is a vertical move at the current, already hard-safe X/Z, so it
-- preserves the upstream Stadium/DW3 horizontal choreography while removing the
-- single low-arrival frame seen on Route 12.
function bcRoofEntryLaneRC14(g,candidate,roofTop,roofComps)
  if not (g and type(candidate)=="table" and type(candidate.eye)=="table") then return candidate end
  local targetY=tonumber(candidate.eye[2])
  if not targetY then return candidate end
  if g.roofApproachTargetY==nil or targetY>(tonumber(g.roofApproachTargetY) or targetY) then
    g.roofApproachTargetY=targetY
  end
  targetY=tonumber(g.roofApproachTargetY) or targetY
  local out=bcCopyCameraWithEye(candidate,{candidate.eye[1],math.max(tonumber(candidate.eye[2]) or targetY,targetY),candidate.eye[3]})
  g.canopyClearActive=true
  g.canopyClearTop=tonumber(roofTop)
  g.canopyClearTargetY=targetY
  g.canopyClearSource="shape:building-roof"
  g.structuralViewRoofComps=roofComps
  g.structuralViewRoofTargetY=targetY
  g.viewArbitration46="ROOF_CROSSING_PREARM"
  g.action="ROOF_ENTRY_LANE"
  return out
end


-- Structural Convergence RC15 --------------------------------------------
-- RC14 fixed the *physical* down/up roof bounce and restored the Route 12
-- crossing lane, but Celadon DW3 exposed the remaining presentation analogue
-- of Viridian Test16: a descending portrait can stay physically above a roof
-- while the roof becomes a sustained subject curtain.  RC1's facade standoff
-- then parks the camera at the last readable WORLD position.  The authored
-- DW3 X/Z keeps moving underneath, so the result looks frozen/hung behind the
-- roof even though the token timer continues.
--
-- Translate the proven canopy language instead of changing objective:
--   * only a subject-intent shot that FIRST met this roof from above;
--   * only once the authored eye is genuinely descending from that entry;
--   * only when the authored eye is itself over the owning building roof;
--   * remember the last strongly-readable Y (8/9) on this SAME token;
--   * if the roof curtain degrades the subject, preserve current authored X/Z
--     and raise only Y to that last-good crest (or the first higher strong lane);
--   * retain that crest for the remainder of the authored token, exactly like
--     Test16, then Test21's shot cut clears it.
--
-- This deliberately does NOT replace Power Plant's good side/facade standoff:
-- an already-high side shot that is not descending over the roof projection
-- never qualifies. Route 12's CROSSING_BELOW branch also returns before here.
BC_ROOF_VIEW_STRONG_CLEAR_RC15=8
BC_ROOF_VIEW_SEARCH_STEPS_RC15=10
BC_ROOF_VIEW_STEP_RC15=2.0

function bcRoofViewIntentClearRC15(cache,arena,groundY,eye,intent)
  local p=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,eye,arena.player,groundY) or nil
  local e=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,eye,arena.enemy,groundY) or nil
  if intent=="player" then return p and (tonumber(p.clear) or 0) or 0 end
  if intent=="enemy" then return e and (tonumber(e.clear) or 0) or 0 end
  if intent=="both" then
    local pc=p and (tonumber(p.clear) or 0) or 0
    local ec=e and (tonumber(e.clear) or 0) or 0
    return math.min(pc,ec)
  end
  return 0
end

function bcRoofViewCrestRC15(g,cache,arena,groundY,desired,intent,token,roofTop,roofComps,roofMode)
  if not (g and cache and type(desired)=="table" and type(desired.eye)=="table"
      and token~=nil and (intent=="player" or intent=="enemy" or intent=="both")
      and roofMode=="descending_above" and tonumber(roofTop)) then
    return nil
  end

  local eye=desired.eye
  local eyeY=tonumber(eye[2]) or 0
  local top=tonumber(roofTop)
  local entryY=tonumber(g.roofApproachEntryY) or eyeY

  -- The key side-vs-roof discriminator.  A facade may block a view ray while
  -- the camera is physically beside the building (Power Plant); that remains
  -- RC1 standoff language.  This canopy-style crest is only for a camera whose
  -- current authored X/Z is actually over a semantic building roof.
  local overheadTop,overheadSource=bcCanopyTopAt(cache,eye[1],eye[3])
  local overRoof=overheadTop
      and tostring(overheadSource or ""):find("building-roof",1,true)~=nil
      and math.abs((tonumber(overheadTop) or top)-top)<=2.0

  if g.roofViewCrestToken~=token then
    g.roofViewCrestToken=token
    g.roofViewCrestY=nil
    g.roofViewLastStrongY=nil
    g.roofViewCrestTop=top
    g.roofViewCrestComps=roofComps
  end

  local clearNow=bcRoofViewIntentClearRC15(cache,arena,groundY,eye,intent)
  if overRoof and clearNow>=BC_ROOF_VIEW_STRONG_CLEAR_RC15 and g.roofViewCrestY==nil then
    -- Keep the most recent strongly-readable point while the authored portrait
    -- naturally descends.  On the first bad frame this is the exact Test16-style
    -- crest we want, not an arbitrary roof+N threshold.
    g.roofViewLastStrongY=eyeY
  end

  local activeY=tonumber(g.roofViewCrestY)
  local descending=(eyeY<entryY-0.75)
  if not activeY and (not overRoof or not descending
      or clearNow>=BC_ROOF_VIEW_STRONG_CLEAR_RC15) then
    return nil
  end

  local seedY=math.max(eyeY,top+5.0,tonumber(g.roofViewLastStrongY) or eyeY)
  if activeY then seedY=math.max(seedY,activeY) end
  local prev=g.prevEye
  local strongCandidate=nil
  local ordinaryCandidate=nil
  for i=0,BC_ROOF_VIEW_SEARCH_STEPS_RC15 do
    local y=seedY+i*BC_ROOF_VIEW_STEP_RC15
    local candidateEye={eye[1],y,eye[3]}
    local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
    local hardPath=prev and select(1,bcGeomWallLine(cache,prev,candidateEye)) or false
    if not hardEye and not hardPath then
      local c=bcRoofViewIntentClearRC15(cache,arena,groundY,candidateEye,intent)
      if c>=BC_ROOF_VIEW_STRONG_CLEAR_RC15 then
        strongCandidate={eye=candidateEye,clear=c}
        break
      elseif not ordinaryCandidate and c>=BC_PASSIVE_READ_GOOD_CLEAR then
        ordinaryCandidate={eye=candidateEye,clear=c}
      end
    end
  end

  local chosen=strongCandidate or ordinaryCandidate
  if not chosen then
    -- Let the existing facade/shared fallbacks decide.  Never invent a blind
    -- height merely because the camera is over a roof.
    return nil
  end

  local chosenY=tonumber(chosen.eye[2]) or seedY
  if g.roofViewCrestY==nil or chosenY>(tonumber(g.roofViewCrestY) or chosenY) then
    g.roofViewCrestY=chosenY
  end
  local crestY=tonumber(g.roofViewCrestY) or chosenY
  local outY=math.max(eyeY,crestY)
  local outEye={eye[1],outY,eye[3]}

  -- Revalidate the exact held point.  If changing geometry makes it invalid,
  -- fall through rather than turning a stale crest into another hard lock.
  local outHard=select(1,bcGeomWallPoint(cache,outEye[1],outEye[2],outEye[3]))
  local outPath=prev and select(1,bcGeomWallLine(cache,prev,outEye)) or false
  if outHard or outPath then return nil end

  g.roofViewCrestTop=top
  g.roofViewCrestComps=roofComps
  g.canopyClearActive=true
  g.canopyClearTop=top
  g.canopyClearTargetY=crestY
  g.canopyClearSource="shape:building-roof"
  g.canopyCrestToken=token
  if g.canopyCrestY==nil or crestY>(tonumber(g.canopyCrestY) or crestY) then
    g.canopyCrestY=crestY
    g.canopyCrestSource="shape:building-roof"
  end
  g.structuralViewRoofComps=roofComps
  g.structuralViewRoofTargetY=crestY
  g.viewArbitration46="ROOF_VIEW_CREST"
  if activeY then
    g.action="ROOF_VIEW_CREST_HOLD"
  else
    g.action="ROOF_VIEW_CREST_ACQUIRE"
  end
  return bcCopyCameraWithEye(desired,outEye)
end

function bcConvergenceFacadeStandoffRC1(cache,arena,groundY,desired,intent,anchorEye)
  if not (type(anchorEye)=="table" and type(desired)=="table" and type(desired.eye)=="table") then return nil end
  if not bcConvergenceIntentGoodRC1(cache,arena,groundY,anchorEye,intent) then return nil end
  local ax,ay,az=tonumber(anchorEye[1]),tonumber(anchorEye[2]),tonumber(anchorEye[3])
  local bx,by,bz=tonumber(desired.eye[1]),tonumber(desired.eye[2]),tonumber(desired.eye[3])
  if not (ax and ay and az and bx and by and bz) then return nil end
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
  if dist<0.05 then return nil end

  -- Walk the current authored approach from the last good composition toward
  -- the requested eye. Keep the furthest point that remains physically legal
  -- AND fulfils the shot's declared subject intent. This is the view analogue
  -- of collision clipping, except the boundary is cinematic readability.
  local bestT=0.0
  local firstBadT=1.0
  for i=1,20 do
    local t=i/20.0
    local eye={ax+dx*t,ay+dy*t,az+dz*t}
    local hardEye=select(1,bcGeomWallPoint(cache,eye[1],eye[2],eye[3]))
    local hardPath=select(1,bcGeomWallLine(cache,anchorEye,eye))
    local candidate=bcCopyCameraWithEye(desired,eye)
    local usable=bcWallViewUsable(cache,arena,groundY,candidate)
    local good=(not hardEye) and (not hardPath) and usable
        and bcConvergenceIntentGoodRC1(cache,arena,groundY,eye,intent)
    if good then bestT=t else firstBadT=t; break end
  end

  if bestT<=0 then return bcCopyCameraWithEye(desired,{ax,ay,az}) end
  -- Refine the visual boundary so the standoff is determined by the rendered
  -- geometry/readability itself rather than a map-specific distance.
  local lo,hi=bestT,firstBadT
  for _=1,5 do
    local t=(lo+hi)*0.5
    local eye={ax+dx*t,ay+dy*t,az+dz*t}
    local hardEye=select(1,bcGeomWallPoint(cache,eye[1],eye[2],eye[3]))
    local hardPath=select(1,bcGeomWallLine(cache,anchorEye,eye))
    local candidate=bcCopyCameraWithEye(desired,eye)
    local usable=bcWallViewUsable(cache,arena,groundY,candidate)
    if (not hardEye) and (not hardPath) and usable
        and bcConvergenceIntentGoodRC1(cache,arena,groundY,eye,intent) then
      lo=t
    else
      hi=t
    end
  end
  -- A small world-space backoff keeps the camera from visibly kissing the
  -- fascia. It is applied along the authored approach, so the scene can still
  -- pan/rotate as that authored approach changes frame to frame.
  local backoffT=math.min(lo,4.0/math.max(dist,0.001))
  local t=math.max(0.0,lo-backoffT)
  local eye={ax+dx*t,ay+dy*t,az+dz*t}
  local candidate=bcCopyCameraWithEye(desired,eye)
  if bcConvergenceIntentGoodRC1(cache,arena,groundY,eye,intent) then return candidate end
  return bcCopyCameraWithEye(desired,{ax,ay,az})
end

-- Semantic View Arbitration Test 46 ---------------------------------------
-- Passive authored cinematography now has a mature purpose-aware readability
-- layer (Tests 18-21/24). The older whole-view wall solver predates that layer
-- and can drag an otherwise safe authored eye diagonally toward the backend
-- native eye before the intent-aware solver gets a turn. Building fascia is
-- also a legitimate foreground surface when a passive environment shot is
-- physically above/around its owning roof. Hard occupancy/path and roof
-- clearance remain authoritative; this helper only classifies the FIRST
-- view-only barrier for the environment-shot arbitration below.
function bcViewFirstBarrierIsBuildingFascia46(cache,a,b)
  if not (cache and type(a)=="table" and type(b)=="table") then return false end
  local blocked,source=bcGeomViewBarrierLine(cache,a,b)
  return blocked and tostring(source or ""):find("building-fascia",1,true)~=nil
end

local function bcApplyWallViewSafety(backend,arena,groundY,camera,base)
  local g=state.geomDiag
  g.viewArbitration46=nil
  if not (type(camera)=="table" and type(camera.eye)=="table"
      and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs) then
    g.wallViewActive=false
    return camera
  end

  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then
    g.wallViewActive=false
    return camera
  end

  -- Shot-Bound View Test 41 -----------------------------------------------
  -- Test 21 established that an authored passive token transition is a CAMERA
  -- CUT, not physical travel from the previous corrected shot. Hard-path safety
  -- already obeys that rule, but the older VIEW_CLEAR / VIEW_RECOVER state did
  -- not. Test 40 footage shows the exact leak: shot stadium:0:1 finishes with
  -- VIEW_CLEAR active; stadium:0:2 begins with a roof-clear target around 73,
  -- but inherits the previous shot's recovery eye (~84), drops toward the new
  -- shot (~73), then the roof crest reasserts (~78). Visually: the persistent
  -- Power Plant roof-corner "bounce".
  --
  -- Give wall-view correction the same authored-shot ownership as every other
  -- mature rescue. A new passive token releases VIEW_CLEAR / VIEW_RECOVER
  -- memory and must solve its own view independently.
  local passiveToken=(not state.battleOpening.active and not state.intro.active and not state.attack.active and not state.faint.active)
      and state.passiveShotToken or nil
  local passiveShotBoundary=passiveToken~=nil and g.wallViewToken~=passiveToken
  if passiveToken~=nil then
    g.wallViewToken=passiveToken
  else
    g.wallViewToken=nil
  end
  if passiveShotBoundary then
    g.wallViewActive=false
    g.lastWallViewEye=nil
    g.structuralViewRoofComps=nil
    g.structuralViewRoofTargetY=nil
    g.convergenceGoodToken=nil
    g.convergenceGoodEye=nil
    g.roofApproachToken=nil
    g.roofApproachTop=nil
    g.roofApproachComps=nil
    g.roofApproachMode=nil
    g.roofApproachTargetY=nil
    g.roofApproachEntryY=nil
    g.roofViewCrestToken=nil
    g.roofViewCrestY=nil
    g.roofViewLastStrongY=nil
    g.roofViewCrestTop=nil
    g.roofViewCrestComps=nil
  end

  local desired=camera
  local usable,fBlocked,pBlocked,eBlocked=bcWallViewUsable(cache,arena,groundY,desired)
  local allBlocked=fBlocked and pBlocked and eBlocked
  local intentRC1=passiveToken and state.passiveShotIntent or nil
  local subjectIntentRC1=(intentRC1=="player" or intentRC1=="enemy" or intentRC1=="both")

  -- RC14 classifies a roof event as soon as ANY owned roof/fascia view ray can
  -- identify its component/top, instead of waiting for the old all-three-ray
  -- trigger. A below-roof crossing can therefore establish its clean lane on
  -- the first visible roof frame. An above-roof shoulder shot is marked as a
  -- descent/crest problem and cannot be hijacked by whole-view roof lift.
  local roofTargetRC14,roofTopRC14,roofCompsRC14=nil,nil,nil
  local roofModeRC14=nil
  if subjectIntentRC1 then
    roofTargetRC14,roofTopRC14,roofCompsRC14=
        bcStructuralViewRoofTarget40(cache,arena,groundY,desired)
    if roofTargetRC14 and roofTopRC14 then
      local authoredYRC14=tonumber(desired.eye[2]) or 0
      if state and state.geomDiag and type(state.geomDiag.authoredEye)=="table" then
        authoredYRC14=tonumber(state.geomDiag.authoredEye[2]) or authoredYRC14
      end
      roofModeRC14=bcRoofApproachModeRC14(
          g,passiveToken,authoredYRC14,roofTopRC14,roofCompsRC14)
      if roofModeRC14=="crossing_below" then
        local roofCandidateRC14=bcConvergenceRoofLaneRC1(
            cache,arena,groundY,desired,intentRC1,roofTargetRC14,roofTopRC14,roofCompsRC14)
        if roofCandidateRC14 then
          local roofOutRC14=bcRoofEntryLaneRC14(
              g,roofCandidateRC14,roofTopRC14,roofCompsRC14)
          if roofOutRC14 then
            g.convergenceGoodToken=passiveToken
            g.convergenceGoodEye={roofCandidateRC14.eye[1],roofCandidateRC14.eye[2],roofCandidateRC14.eye[3]}
            return roofOutRC14
          end
        end
      elseif roofModeRC14=="descending_above" then
        local roofCrestRC15=bcRoofViewCrestRC15(
            g,cache,arena,groundY,desired,intentRC1,passiveToken,
            roofTopRC14,roofCompsRC14,roofModeRC14)
        if roofCrestRC15 then
          g.convergenceGoodToken=passiveToken
          g.convergenceGoodEye={roofCrestRC15.eye[1],roofCrestRC15.eye[2],roofCrestRC15.eye[3]}
          return roofCrestRC15
        end
      end
    end
  end

  -- Structural Convergence RC5 (retained in RC6) -------------------------
  -- Test RC4 Celadon proved a semantic ordering bug rather than another
  -- building-definition failure. Hard safety can legitimately reject an
  -- impossible authored Stadium eye and substitute the backend-safe eye.
  -- That fallback is physically safe, but it can itself sit only a few units
  -- above a real building roof and leave the entire intended view hidden.
  --
  -- Once hard fallback has happened, the ABANDONED authored eye must no longer
  -- classify this presentation as a high-fascia shot. Judge the fallback eye
  -- on its own terms and give its owning roof/top the first chance to produce
  -- a readable degraded composition. This is the same generic fascia/body <->
  -- roof/top semantic, applied after a deliberate physical-language fallback.
  if allBlocked and passiveToken~=nil and g.hardFallbackAppliedThisFrame then
    local roofTargetRC5,roofTopRC5,roofCompsRC5=
        bcStructuralViewRoofTarget40(cache,arena,groundY,desired)
    if roofTargetRC5 then
      local startY=math.max(tonumber(desired.eye[2]) or roofTargetRC5,roofTargetRC5)
      for i=0,12 do
        local y=startY+i*2.0
        local candidateEye={desired.eye[1],y,desired.eye[3]}
        local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
        local hardPath=select(1,bcGeomWallLine(cache,desired.eye,candidateEye))
        if not hardEye and not hardPath then
          local candidate=bcCopyCameraWithEye(desired,candidateEye)
          local candidateUsable=bcWallViewUsable(cache,arena,groundY,candidate)
          local intentGood=true
          if subjectIntentRC1 then
            intentGood=bcConvergenceIntentGoodRC1(
                cache,arena,groundY,candidateEye,intentRC1)
          end
          if candidateUsable and intentGood then
            g.wallViewActive=false
            g.canopyClearActive=true
            g.canopyClearTop=roofTopRC5
            g.canopyClearTargetY=y
            g.canopyClearSource="shape:building-roof"
            g.structuralViewRoofComps=roofCompsRC5
            g.structuralViewRoofTargetY=y
            g.viewArbitration46="FALLBACK_ROOF_VIEW"
            g.action="FALLBACK_ROOF_VIEW"
            return candidate
          end
        end
      end
      g.structuralViewRoofComps=roofCompsRC5
      g.structuralViewRoofTargetY=nil
    end
  end
  if subjectIntentRC1 and bcConvergenceIntentGoodRC1(cache,arena,groundY,desired.eye,intentRC1) then
    g.convergenceGoodToken=passiveToken
    g.convergenceGoodEye={desired.eye[1],desired.eye[2],desired.eye[3]}
  end

  -- Test 45: diagnostic only. Capture raw authored-eye barrier provenance.
  if allBlocked then
    g.view45Focus=(type(desired.focus)=="table")
      and bcViewTrace45(cache,desired.eye,desired.focus) or "n/a"
    g.view45Player=(type(arena.player)=="table")
      and bcViewTrace45(cache,desired.eye,
        {arena.player[1],(tonumber(groundY) or 0)+8.0,arena.player[2]}) or "n/a"
    g.view45Enemy=(type(arena.enemy)=="table")
      and bcViewTrace45(cache,desired.eye,
        {arena.enemy[1],(tonumber(groundY) or 0)+8.0,arena.enemy[2]}) or "n/a"
  else
    g.view45Focus=nil
    g.view45Player=nil
    g.view45Enemy=nil
  end

  -- Test 46: semantic arbitration -----------------------------------------
  -- Test 45 proved that the remaining "collision sends the camera flying"
  -- behaviour is frequently not a physical collision at all. The authored
  -- eye/path has already passed hard safety, but legacy VIEW_CLEAR then moves
  -- X/Z/Y toward the backend native eye solely because all three view rays are
  -- blocked. On player/enemy/both passive shots, the newer passive readability
  -- system immediately downstream already owns that presentation decision: it
  -- debounces the failure, preserves authored X/Z first, searches vertically,
  -- then uses a local escape or whole-shot fallback only when necessary.
  --
  -- Environment shots have no required portrait subject. A component-owned
  -- building fascia may therefore be cinematic foreground, exactly as canopy
  -- can be foreground while stump/body remains hard occupancy. If all three
  -- first view barriers are building fascia, keep the physically-safe authored
  -- lane and let roof/path safety do its job; do not invent a native-eye rescue.
  -- Ordinary shape:wall behaviour for environment shots is deliberately left
  -- untouched in this test. Intro/attack/faint ownership is also untouched.
  if allBlocked and passiveToken~=nil then
    local intent46=state.passiveShotIntent
    local subjectIntent46=(intent46=="player" or intent46=="enemy" or intent46=="both")

    -- RC14: the whole-view roof lane was already considered above and is only
    -- legal for a roof event first classified as CROSSING_BELOW. In particular,
    -- do not let an above-roof DW3 shoulder shot cross the old arbitrary
    -- `roofTarget+6` threshold and jump upward just to clear every view ray.
    -- Test46/passive intent remains authoritative there; if the physical eye
    -- later descends into the roof floor, ROOF_DESCENT_CREST handles it.
    if subjectIntent46 then
      if g.convergenceGoodToken==passiveToken and type(g.convergenceGoodEye)=="table" then
        local standRC1=bcConvergenceFacadeStandoffRC1(
            cache,arena,groundY,desired,intent46,g.convergenceGoodEye)
        if standRC1 then
          g.wallViewActive=false
          g.structuralViewRoofComps=roofCompsRC14
          g.structuralViewRoofTargetY=roofTargetRC14
          g.viewArbitration46="CONVERGENCE_STANDOFF"
          g.action="CONVERGENCE_FACADE_STANDOFF"
          g.convergenceGoodEye={standRC1.eye[1],standRC1.eye[2],standRC1.eye[3]}
          bcRememberWallView(g,standRC1,true)
          return standRC1
        end
      end
    end

    local environmentFascia46=false
    if intent46=="environment" then
      local gy46=tonumber(groundY) or 0
      local focusF46=type(desired.focus)=="table"
          and bcViewFirstBarrierIsBuildingFascia46(cache,desired.eye,desired.focus)
      local playerF46=type(arena.player)=="table"
          and bcViewFirstBarrierIsBuildingFascia46(cache,desired.eye,{arena.player[1],gy46+8.0,arena.player[2]})
      local enemyF46=type(arena.enemy)=="table"
          and bcViewFirstBarrierIsBuildingFascia46(cache,desired.eye,{arena.enemy[1],gy46+8.0,arena.enemy[2]})
      environmentFascia46=focusF46 and playerF46 and enemyF46
    end
    if subjectIntent46 or environmentFascia46 then
      -- Release any legacy wall-view memory in the same authored token so a
      -- previous VIEW_CLEAR cannot re-enter through VIEW_RECOVER after deferral.
      g.wallViewActive=false
      if not subjectIntent46 then g.lastWallViewEye=nil end
      g.structuralViewRoofComps=nil
      g.structuralViewRoofTargetY=nil
      if subjectIntent46 then
        g.viewArbitration46="PASSIVE_INTENT"
        g.action="VIEW_DEFER_PASSIVE"
      else
        g.viewArbitration46="ENV_BUILDING_FOREGROUND"
        g.action="VIEW_DEFER_ENV_FASCIA"
      end
      return desired
    end
  end

  -- Never invent a recovery/path segment across an authored camera cut.
  local prev=passiveShotBoundary and nil or g.prevEye

  -- Test 40: Test 39 proved the response was correct where the blocked view
  -- could be associated with a component, but Power Plant/Celadon large facades
  -- still fell through to VIEW_CLEAR because exact hit->component recovery failed.
  -- The route-based composite association above closes that last identity gap.
  --
  -- Test 39: the remaining Power Plant high-scene bounce is VIEW_CLEAR, not
  -- hard path collision. When the full authored view is blocked by our synthetic
  -- fascia, ask THAT SAME building for its roof before the old diagonal
  -- native-eye solver gets a turn. Search vertically only at the current X/Z.
  if allBlocked then
    local roofTarget,roofTop,roofComps=bcStructuralViewRoofTarget40(cache,arena,groundY,desired)
    if roofTarget then
      local startY=math.max(tonumber(desired.eye[2]) or 0,roofTarget)
      local intent=state.passiveShotIntent
      local validIntent=(intent=="player" or intent=="enemy" or intent=="both")
      for i=0,10 do
        local y=startY+i*2.0
        local candidateEye={desired.eye[1],y,desired.eye[3]}
        local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
        local hardPath=select(1,bcGeomWallLine(cache,desired.eye,candidateEye))
        if not hardEye and not hardPath then
          local candidate=bcCopyCameraWithEye(desired,candidateEye)
          local candidateUsable=bcWallViewUsable(cache,arena,groundY,candidate)
          local intentGood=true
          if validIntent then
            local pp=type(arena.player)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.player,groundY) or nil
            local ee=type(arena.enemy)=="table" and bcPassiveReadabilityEnvelope(cache,candidateEye,arena.enemy,groundY) or nil
            intentGood=bcPassiveReadIntentGood(intent,pp,ee)
          end
          if candidateUsable and intentGood then
            g.wallViewActive=false
            g.canopyClearActive=true
            g.canopyClearTop=roofTop
            g.canopyClearTargetY=y
            g.canopyClearSource="shape:building-roof"
            g.structuralViewRoofComps=roofComps
            g.structuralViewRoofTargetY=y
            g.action="STRUCTURAL_VIEW_ROOF"
            return candidate
          end
        end
      end
      g.structuralViewRoofComps=roofComps
      g.structuralViewRoofTargetY=nil
    else
      g.structuralViewRoofComps=nil
      g.structuralViewRoofTargetY=nil
    end
  end

  -- Recover gently from a previous wall-view correction once the authored view
  -- is viable again.  Keep both the recovery segment and candidate wall-safe.
  if g.wallViewActive and not allBlocked and prev then
    local dist=bcVecDistance(prev,desired.eye)
    if dist>BC_WALL_VIEW_RECOVER_DONE then
      local candidateEye=bcLerpVec(prev,desired.eye,BC_WALL_VIEW_RECOVER_ALPHA)
      local pathBlocked=select(1,bcGeomWallLine(cache,prev,candidateEye))
      if not pathBlocked then
        local candidate=bcCopyCameraWithEye(desired,candidateEye)
        local candidateUsable=bcWallViewUsable(cache,arena,groundY,candidate)
        if candidateUsable then
          g.action="VIEW_RECOVER"
          bcRememberWallView(g,candidate,true)
          return candidate
        end
      end
    end
    g.wallViewActive=false
    bcRememberWallView(g,desired,usable)
    return desired
  end

  if not allBlocked then
    g.wallViewActive=false
    bcRememberWallView(g,desired,usable)
    return desired
  end

  -- The entire authored view is behind a structural wall. Search only along the
  -- line toward the backend's native eye; first viable candidate wins, so the
  -- correction is the smallest one we can make rather than a generic reset.
  if type(base)=="table" and type(base.eye)=="table" then
    for i=1,BC_WALL_VIEW_SEARCH_STEPS do
      local t=i/BC_WALL_VIEW_SEARCH_STEPS
      local candidateEye=bcLerpVec(desired.eye,base.eye,t)
      local eyeBlocked=bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3])
      local pathBlocked=false
      if prev then pathBlocked=select(1,bcGeomWallLine(cache,prev,candidateEye)) end
      if not eyeBlocked and not pathBlocked then
        local candidate=bcCopyCameraWithEye(desired,candidateEye)
        local candidateUsable=bcWallViewUsable(cache,arena,groundY,candidate)
        if candidateUsable then
          g.wallViewActive=true
          g.action="VIEW_CLEAR"
          bcRememberWallView(g,candidate,true)
          return candidate
        end
      end
    end
  end

  -- If the direct native-eye search cannot produce a viable point without
  -- crossing a wall, prefer the most recent verified readable view. This is a
  -- diagnostic fallback and intentionally avoids teleporting through geometry.
  if prev and type(g.lastWallViewEye)=="table" then
    local pathBlocked=select(1,bcGeomWallLine(cache,prev,g.lastWallViewEye))
    if not pathBlocked then
      local candidateEye=bcLerpVec(prev,g.lastWallViewEye,0.25)
      local candidate=bcCopyCameraWithEye(desired,candidateEye)
      local candidateUsable=bcWallViewUsable(cache,arena,groundY,candidate)
      if candidateUsable then
        g.wallViewActive=true
        g.action="VIEW_HOLD"
        return candidate
      end
    end
  end

  -- Last resort: keep Test 1's physically-safe result rather than inventing a
  -- blind snap.  Telemetry will expose this as VIEW_UNRESOLVED for calibration.
  g.wallViewActive=true
  g.action="VIEW_UNRESOLVED"
  return desired
end

local bcApplyGeometrySafety

local function bcDiagOwner()
  if state.faint.active then return "faint" end
  if state.attack.active then return "attack" end
  if state.battleOpening.active then return "battle_intro" end
  if state.intro.active then return "intro" end
  if state.environmentFallback then return "dw3_passive[env]" end
  local p=mod.options:get("preset") or "dw3"
  if p=="stadium" then return "stadium_passive" end
  if p=="portrait_test" then return "hero_portrait" end
  return "dw3_passive"
end

local function bcDiagLatchHit(label,result)
  if result and result.blocked then
    state.geomDiag.lastHit={label=label,source=result.source,pos=result.pos}
    state.geomDiag.hitHold=90
  end
end

-- Readability envelope diagnostic -----------------------------------------
-- Test 8 does NOT alter the camera. Earlier tests proved that a single ray to
-- a battler's centre can say "clear" while a canopy visibly masks much of the
-- subject. Sample a small 3x3 world-space envelope around each battler instead:
-- three body heights x three camera-relative lateral points. This is deliberately
-- renderer-agnostic and is diagnostic data only; the next intervention can then
-- choose thresholds by shot purpose without sterilising foreground cinematography.
local BC_READABILITY_LATERAL=3.25
local BC_READABILITY_HEIGHTS={4.5,9.0,13.5}

local function bcReadabilityEnvelope(cache,eye,subject,groundY)
  if not (cache and cache.supported and type(eye)=="table" and type(subject)=="table") then
    return nil
  end
  local sx,sz=tonumber(subject[1]),tonumber(subject[2])
  local ex,ez=tonumber(eye[1]),tonumber(eye[3])
  if not (sx and sz and ex and ez) then return nil end
  local dx,dz=sx-ex,sz-ez
  local len=math.sqrt(dx*dx+dz*dz)
  local rx,rz
  if len>1e-4 then
    rx,rz=-dz/len,dx/len
  else
    rx,rz=1,0
  end
  local gy=tonumber(groundY) or 0
  local clear,total=0,0
  local sources={}
  local firstHit=nil
  local laterals={-BC_READABILITY_LATERAL,0,BC_READABILITY_LATERAL}
  for _,h in ipairs(BC_READABILITY_HEIGHTS) do
    for _,lat in ipairs(laterals) do
      total=total+1
      local target={sx+rx*lat,gy+h,sz+rz*lat}
      local blocked,source,pos=bcGeomLine(cache,eye,target)
      if blocked then
        local key=tostring(source or "?")
        sources[key]=(sources[key] or 0)+1
        if not firstHit then firstHit={source=source,pos=pos} end
      else
        clear=clear+1
      end
    end
  end
  local dominant=nil
  local dominantN=0
  for source,n in pairs(sources) do
    if n>dominantN then dominant,dominantN=source,n end
  end
  return {clear=clear,total=total,blocked=total-clear,ratio=total>0 and clear/total or 0,
          dominant=dominant,dominantN=dominantN,firstHit=firstHit}
end


-- Test 9: a larger featured-subject silhouette envelope. Test 8 proved that
-- the compact 3x3 body-centre probe can remain 9/9 clear while a large model
-- is visibly masked by canopy. This second envelope deliberately reaches over
-- a broader plausible battler silhouette (five heights x five laterals). It is
-- still diagnostic-only: no camera response is driven from this score yet.
local BC_READABILITY_FEATURED_LATERALS={-6.5,-3.25,0,3.25,6.5}
local BC_READABILITY_FEATURED_HEIGHTS={2.5,6.5,10.5,14.5,18.5}

local function bcReadabilityFeaturedEnvelope(cache,eye,subject,groundY)
  if not (cache and cache.supported and type(eye)=="table" and type(subject)=="table") then
    return nil
  end
  local sx,sz=tonumber(subject[1]),tonumber(subject[2])
  local ex,ez=tonumber(eye[1]),tonumber(eye[3])
  if not (sx and sz and ex and ez) then return nil end
  local dx,dz=sx-ex,sz-ez
  local len=math.sqrt(dx*dx+dz*dz)
  local rx,rz
  if len>1e-4 then rx,rz=-dz/len,dx/len else rx,rz=1,0 end
  local gy=tonumber(groundY) or 0
  local clear,total=0,0
  local sources={}
  local firstHit=nil
  for _,h in ipairs(BC_READABILITY_FEATURED_HEIGHTS) do
    for _,lat in ipairs(BC_READABILITY_FEATURED_LATERALS) do
      total=total+1
      local target={sx+rx*lat,gy+h,sz+rz*lat}
      local blocked,source,pos=bcGeomLine(cache,eye,target)
      if blocked then
        local key=tostring(source or "?")
        sources[key]=(sources[key] or 0)+1
        if not firstHit then firstHit={source=source,pos=pos} end
      else
        clear=clear+1
      end
    end
  end
  local dominant=nil
  local dominantN=0
  for source,n in pairs(sources) do
    if n>dominantN then dominant,dominantN=source,n end
  end
  return {clear=clear,total=total,blocked=total-clear,ratio=total>0 and clear/total or 0,
          dominant=dominant,dominantN=dominantN,firstHit=firstHit}
end

local function bcReadabilityFeaturedSide()
  if state.intro.active then return state.intro.side end
  if state.faint.active then return state.faint.side end
  if state.attack.active and state.attack.mode=="self" then return state.attack.side end
  return nil
end


-- Test 10: purpose-aware readability protection --------------------------------
-- Test 9 finally exposed a useful signal: as Viridian canopy first crosses the
-- featured Mewtwo intro, the broad envelope falls to 20/25 clear with canopy
-- hits. A few frames later the same rendered canopy can visually dominate the
-- image while individual geometry rays thread gaps and return 25/25 again.
-- Therefore readability is temporal, not a one-frame binary ray result.
--
-- This is a shared final-layer mechanism, but Test 10 enables only the strict
-- INTRO policy while we calibrate it. Passive cameras keep their much more
-- tolerant foreground language. Attack/Faint can opt into their own thresholds
-- later without duplicating geometry code.
local BC_READ_FEATURE_BLOCKED_POINTS=4   -- <=21/25 clear arms strict intro protection
local BC_READ_FEATURE_TRIGGER_FRAMES=2
local BC_READ_FEATURE_MIN_LIFT=4.0
local BC_READ_FEATURE_STEP=2.0
local BC_READ_FEATURE_SEARCH_STEPS=10
local BC_READ_FEATURE_ALPHA=0.32
local BC_READ_FEATURE_DONE=0.35

local function bcReadabilityBadFamily(r)
  if not r or (tonumber(r.blocked) or 0)<BC_READ_FEATURE_BLOCKED_POINTS then return false,nil end
  local d=tostring(r.dominant or ""):lower()
  if d:find("canopy",1,true) then return true,"canopy" end
  if d:find("stump",1,true) then return true,"stump" end
  if d:find("tree",1,true) then return true,"tree" end
  return false,nil
end

local function bcApplyFeaturedReadabilitySafety(backend,arena,groundY,camera,base)
  local g=state.geomDiag
  if not (type(camera)=="table" and type(camera.eye)=="table" and type(arena)=="table"
      and type(arena.map)=="table" and not arena.discs) then
    g.featureReadActive=false; g.featureReadFrames=0; g.featureReadOffset=0
    g.featureReadTargetOffset=nil; g.featureReadSide=nil; g.featureReadSource=nil
    return camera
  end

  -- Strict featured-subject policy is intentionally limited to Battle Intro in
  -- this calibration build. The mechanism itself sits in the common final layer.
  local side=bcReadabilityFeaturedSide()
  if not (state.intro.active and (side=="player" or side=="enemy")) then
    g.featureReadActive=false; g.featureReadFrames=0; g.featureReadOffset=0
    g.featureReadTargetOffset=nil; g.featureReadSide=nil; g.featureReadSource=nil
    return camera
  end

  if g.featureReadSide and g.featureReadSide~=side then
    g.featureReadActive=false; g.featureReadFrames=0; g.featureReadOffset=0
    g.featureReadTargetOffset=nil; g.featureReadSource=nil
  end
  g.featureReadSide=side

  local subject=(side=="player") and arena.player or arena.enemy
  if type(subject)~="table" then return camera end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return camera end

  local read=bcReadabilityFeaturedEnvelope(cache,camera.eye,subject,groundY)
  local bad,source=bcReadabilityBadFamily(read)
  if not g.featureReadActive then
    if bad then
      g.featureReadFrames=(g.featureReadFrames or 0)+1
      g.featureReadSource=source
      if g.featureReadFrames>=BC_READ_FEATURE_TRIGGER_FRAMES then
        -- Find a small vertical escape while preserving X/Z, target and FOV.
        -- Search from at least +4 world units so a one-cell geometric gap does
        -- not immediately collapse the correction back into the same canopy.
        local baseY=tonumber(camera.eye[2]) or 0
        local chosen=BC_READ_FEATURE_MIN_LIFT
        for i=2,BC_READ_FEATURE_SEARCH_STEPS do
          local off=i*BC_READ_FEATURE_STEP
          local probe={camera.eye[1],baseY+off,camera.eye[3]}
          local rr=bcReadabilityFeaturedEnvelope(cache,probe,subject,groundY)
          local rrBad=bcReadabilityBadFamily(rr)
          chosen=off
          if rr and (tonumber(rr.blocked) or 0)<=1 and not rrBad then break end
        end
        g.featureReadTargetOffset=math.max(BC_READ_FEATURE_MIN_LIFT,chosen)
        g.featureReadOffset=tonumber(g.featureReadOffset) or 0
        g.featureReadActive=true
        g.action="READ_LIFT"
      else
        g.action="READ_ARM"
      end
    else
      g.featureReadFrames=0
    end
  end

  if not g.featureReadActive then return camera end

  -- Once a featured intro shot has proved vulnerable, keep the minimum lift for
  -- that featured phase. Test 9 showed that later rays can falsely return clear
  -- while the rendered canopy still fills the image; releasing on those frames
  -- would simply bounce the camera back into the obstruction.
  local target=tonumber(g.featureReadTargetOffset) or BC_READ_FEATURE_MIN_LIFT
  local cur=tonumber(g.featureReadOffset) or 0
  cur=cur+(target-cur)*BC_READ_FEATURE_ALPHA
  g.featureReadOffset=cur
  if math.abs(target-cur)<=BC_READ_FEATURE_DONE then g.action="READ_HOLD" else g.action="READ_LIFT" end

  return {
    eye={camera.eye[1],camera.eye[2]+cur,camera.eye[3]},
    focus=camera.focus and {camera.focus[1],camera.focus[2],camera.focus[3]} or camera.focus,
    fov=camera.fov, curve=camera.curve or 0,
  }
end

-- Common final protection stack. Hard geometry first, then whole-view recovery,
-- then purpose-aware featured-subject readability as the final presentation pass.
bcApplyGeometrySafety=function(backend,arena,groundY,camera,base)
  -- Floor is a renderer-neutral hard boundary, unlike Kanto wall/roof grammar.
  -- Apply it before the Gold structural early-out so every BC-owned camera can
  -- never physically descend beneath the battle plane.
  camera=state.floorProtectCamera(camera,groundY)
  -- Gold Test 4: the mature Kanto structural grammar remains locked and is not
  -- guessed onto Game2 map data.  Randy already supplies its own live-world
  -- battle visibility clearing; Gold structural adaptation gets a dedicated
  -- later probe once its geometry contract is measured.
  if backend and backend.gold then return camera end
  -- Test 28 arbitration:
  -- A known elevated surface (canopy/building roof) may be cleared by raising
  -- only Y. Give that semantic route first refusal before the generic hard-wall
  -- clamp. Ordinary walls have no top-clearance route and remain authoritative.
  local surfaceSafe=bcApplyCanopyClearance(backend,arena,camera)
  local pathSafe=bcApplyWallSafety(backend,arena,surfaceSafe,base)
  local liftSafe,liftClaimed=bcApplyVerticalViewSafety(backend,arena,groundY,pathSafe,base)
  local viewSafe=liftClaimed and liftSafe or bcApplyWallViewSafety(backend,arena,groundY,liftSafe,base)

  -- Test 29: readability must judge the camera we are ACTUALLY holding.
  -- Previously passive readability ran before Test 16's crest hold; a roof
  -- could become a full subject curtain only after the held high trajectory was
  -- applied, leaving the detector one layer behind reality. Apply the existing
  -- crest first, evaluate readability there, then latch any newly discovered
  -- higher readable point in the same frame.
  local crestBeforeRead=bcApplyPassiveCanopyCrestHold(viewSafe)
  local passiveReadSafe=bcApplyPassiveSubjectReadability(backend,arena,groundY,crestBeforeRead,base)
  local crestSafe=bcApplyPassiveCanopyCrestHold(passiveReadSafe)
  return state.floorProtectCamera(
      bcApplyFeaturedReadabilitySafety(backend,arena,groundY,crestSafe,base),groundY)
end

local function bcDiagRecordCamera(backend,arena,groundY,camera,base)
  if backend and (backend.id=="DRAMATIC_SHAPE" or backend.id=="DRAMALESS_SHAPE" or backend.id=="BATTLE_ART_VOXEL_FORK" or backend.id=="potato_voxel" or backend.id=="VOXEL_ASCENDANT") and type(camera)=="table" and type(camera.eye)=="table" then
    state.spriteFacingCamera={
      eye={camera.eye[1],camera.eye[2],camera.eye[3]},
      focus=type(camera.focus)=="table" and {camera.focus[1],camera.focus[2],camera.focus[3]} or nil,
      fov=camera.fov, up=camera.up, curve=camera.curve,
    }
  end
  if not DIAGNOSTIC_BUILD then return end
  local ok,err=pcall(function()
    if not (type(camera)=="table" and type(camera.eye)=="table") then return end
    local map=type(arena)=="table" and arena.map or nil
    local live={
      backendId=backend and backend.id or nil,
      backendVersion=backend and backend.version or nil,
      owner=bcDiagOwner(), preset=mod.options:get("preset") or "dw3",
      envFallback=state.environmentFallback,
      cam=arena and arena.cam or nil, shape=arena and arena.shape or nil,
      discs=arena and arena.discs or nil, mapName=map and (map.id or map.name or map.mapId or map.mapID) or nil,
      eye={camera.eye[1],camera.eye[2],camera.eye[3]},
      focus=camera.focus and {camera.focus[1],camera.focus[2],camera.focus[3]} or nil,
      nativeEye=base and base.eye and {base.eye[1],base.eye[2],base.eye[3]} or nil,
      rawEye=state.geomDiag.rawEye and {state.geomDiag.rawEye[1],state.geomDiag.rawEye[2],state.geomDiag.rawEye[3]} or nil,
      action=state.geomDiag.action or "NONE",
      liftActive=state.geomDiag.liftActive and true or false,
      liftBlockedFrames=state.geomDiag.liftBlockedFrames or 0,
      liftClearFrames=state.geomDiag.liftClearFrames or 0,
      liftTargetY=state.geomDiag.liftTargetY,
      liftSource=state.geomDiag.liftSource,
      canopyClearActive=state.geomDiag.canopyClearActive and true or false,
      canopyClearTop=state.geomDiag.canopyClearTop,
      canopyClearTargetY=state.geomDiag.canopyClearTargetY,
      canopyClearSource=state.geomDiag.canopyClearSource,
      canopyCrestToken=state.geomDiag.canopyCrestToken,
      canopyCrestY=state.geomDiag.canopyCrestY,
      canopyCrestSource=state.geomDiag.canopyCrestSource,
      passiveShotIntent=state.passiveShotIntent,
      passiveReadToken=state.geomDiag.passiveReadToken,
      passiveReadFrames=state.geomDiag.passiveReadFrames or 0,
      passiveReadIntent=state.geomDiag.passiveReadIntent,
      passiveReadSource=state.geomDiag.passiveReadSource,
      passiveReadTargetY=state.geomDiag.passiveReadTargetY,
      passiveReadPlayerClear=state.geomDiag.passiveReadPlayerClear,
      passiveReadPlayerFoliage=state.geomDiag.passiveReadPlayerFoliage,
      passiveReadPlayerStructural=state.geomDiag.passiveReadPlayerStructural,
      passiveReadPlayerOther=state.geomDiag.passiveReadPlayerOther,
      passiveReadEnemyClear=state.geomDiag.passiveReadEnemyClear,
      passiveReadEnemyFoliage=state.geomDiag.passiveReadEnemyFoliage,
      passiveReadEnemyStructural=state.geomDiag.passiveReadEnemyStructural,
      passiveReadEnemyOther=state.geomDiag.passiveReadEnemyOther,
      featureReadActive=state.geomDiag.featureReadActive and true or false,
      featureReadFrames=state.geomDiag.featureReadFrames or 0,
      featureReadOffset=state.geomDiag.featureReadOffset or 0,
      featureReadTargetOffset=state.geomDiag.featureReadTargetOffset,
      featureReadSource=state.geomDiag.featureReadSource,
      view45Focus=state.geomDiag.view45Focus,
      view45Player=state.geomDiag.view45Player,
      view45Enemy=state.geomDiag.view45Enemy,
      viewArbitration46=state.geomDiag.viewArbitration46,
      boundary49=state.geomDiag.boundary49,
      phaseHandoffRC3=state.geomDiag.phaseHandoffRC3,
    }
    if arena and arena.player and arena.enemy then
      local dx=(tonumber(arena.enemy[1]) or 0)-(tonumber(arena.player[1]) or 0)
      local dz=(tonumber(arena.enemy[2]) or 0)-(tonumber(arena.player[2]) or 0)
      live.spacing=math.sqrt(dx*dx+dz*dz)
    end

    if not map or arena.discs then
      live.geom={supported=false,reason=arena and arena.discs and "B-stage exempt" or "no map",quads=0,boxes=0}
      state.geomDiag.prevEye={camera.eye[1],camera.eye[2],camera.eye[3]}
      state.geomDiag.live=live
      return
    end

    local cache=bcGeomCacheFor(backend,map)
    live.geom=cache
    if cache.supported and cache.buildingNear then
      local comp,env,dist=cache.buildingNear(camera.eye[1],camera.eye[3],4.0)
      live.buildingComp=comp and comp.id or nil
      live.buildingDist=dist
      live.buildingBottom=env and env.bottom or (comp and comp.bottom or nil)
      live.buildingTop=env and env.top or (comp and comp.top or nil)
    end
    if cache.supported and cache.buildingShellNear then
      local comp,top,dist=cache.buildingShellNear(camera.eye[1],camera.eye[3],4.0)
      live.buildingShellComp=comp and comp.id or nil
      live.buildingShellTop=top
      live.buildingShellDist=dist
    end
    if not cache.supported then
      state.geomDiag.prevEye={camera.eye[1],camera.eye[2],camera.eye[3]}
      state.geomDiag.live=live
      return
    end

    local eyeBlocked,eyeSource=bcGeomPoint(cache,camera.eye[1],camera.eye[2],camera.eye[3])
    live.eye={blocked=eyeBlocked,source=eyeSource,pos={camera.eye[1],camera.eye[2],camera.eye[3]}}

    if camera.focus then
      live.focusLOS=bcGeomResult(cache,camera.eye,camera.focus)
      bcDiagLatchHit("focusLOS",live.focusLOS)
    end

    local gy=tonumber(groundY) or 0
    if arena.player then
      live.playerLOS=bcGeomResult(cache,camera.eye,{arena.player[1],gy+8.0,arena.player[2]})
      bcDiagLatchHit("playerLOS",live.playerLOS)
    end
    if arena.enemy then
      live.enemyLOS=bcGeomResult(cache,camera.eye,{arena.enemy[1],gy+8.0,arena.enemy[2]})
      bcDiagLatchHit("enemyLOS",live.enemyLOS)
    end

    -- Multi-ray silhouette/readability envelopes. Diagnostic only.
    -- Keep Test 8's compact 3x3 score for comparison, and in Test 9 add a
    -- broader 5x5 envelope only for the featured subject.
    if arena.player then live.playerRead=bcReadabilityEnvelope(cache,camera.eye,arena.player,gy) end
    if arena.enemy then live.enemyRead=bcReadabilityEnvelope(cache,camera.eye,arena.enemy,gy) end
    live.featuredSide=bcReadabilityFeaturedSide()
    if live.featuredSide=="player" and arena.player then
      live.featuredRead=bcReadabilityFeaturedEnvelope(cache,camera.eye,arena.player,gy)
    elseif live.featuredSide=="enemy" and arena.enemy then
      live.featuredRead=bcReadabilityFeaturedEnvelope(cache,camera.eye,arena.enemy,gy)
    end

    local prev=state.geomDiag.prevEye
    if prev then
      live.travel=bcGeomResult(cache,prev,camera.eye)
      bcDiagLatchHit("travel",live.travel)
    end
    if eyeBlocked then
      bcDiagLatchHit("eye",live.eye)
    end

    local eyeShape=bcGeomShapeAt(cache,camera.eye[1],camera.eye[3])
    if type(eyeShape)=="table" then
      live.eyeShape=tostring(eyeShape.class or "nil").."/"..tostring(eyeShape.art or "nil").." h="..bcDiagNum(eyeShape.h)
    else
      live.eyeShape="nil"
    end

    state.geomDiag.prevEye={camera.eye[1],camera.eye[2],camera.eye[3]}
    if state.geomDiag.hitHold>0 then state.geomDiag.hitHold=state.geomDiag.hitHold-1 end
    state.geomDiag.live=live
  end)
  if not ok then
    state.geomDiag.live={backendId=backend and backend.id or nil,owner=bcDiagOwner(),
      geom={supported=false,reason="record error: "..tostring(err),quads=0,boxes=0}}
  end
end

local function bcDiagFlag(result)
  if not result then return "pending" end
  if result.blocked then return "BLOCKED["..tostring(result.source or "?").."]" end
  return "clear"
end

local function bcDiagReadability(r)
  if not r then return "pending" end
  local pct=math.floor((tonumber(r.ratio) or 0)*100+0.5)
  local src=r.dominant and (" "..tostring(r.dominant).."x"..tostring(r.dominantN or 0)) or ""
  return string.format("%d/%d clear (%d%%)%s",tonumber(r.clear) or 0,tonumber(r.total) or 0,pct,src)
end

local diagHudFont=nil
local function drawGeometryDiagnosticHud()
  if not DIAGNOSTIC_BUILD or not love or not love.graphics then return end
  local ok,err=pcall(function()
    local g=love.graphics
    if not diagHudFont then diagHudFont=g.newFont(12) end
    local d=state.geomDiag.live or {}
    local geom=d.geom or {}
    local lines={
      string.format("BC 1.2.1 | backend=%s %s | preset=%s | owner=%s",
        tostring(d.backendId or "nil"),tostring(d.backendVersion or ""),tostring(d.preset or "nil"),tostring(d.owner or "nil")),
      string.format("map=%s | cam=%s shape=%s discs=%s spacing=%s",
        tostring(d.mapName or "nil"),tostring(d.cam),tostring(d.shape),tostring(d.discs),bcDiagNum(d.spacing)),
      string.format("ENV FALLBACK: %s",tostring(d.envFallback or "none")),
      string.format("geom=%s | shapeAt=%s | objectQuads=%s boxes=%s canopy=%s/%s buildingCells=%s comps=%s filled=%s owned=%s shell=%s hull=4.0",
        geom.supported and tostring(geom.reason or "yes") or ("UNSUPPORTED:"..tostring(geom.reason or "?")),
        tostring(geom.shapeAt~=nil),tostring(geom.quads or 0),tostring(geom.boxes or 0),
        tostring(geom.canopyStamps or 0),tostring(geom.canopyTopQuads or 0),
        tostring(geom.buildingEnvCount or 0),tostring(geom.buildingComponentCount or 0),
        tostring(geom.buildingFilledCells or 0),tostring(geom.buildingOwnedBoxes or 0),
        tostring(geom.buildingShellBoxes or 0)),
      string.format("eye=%s | authored=%s | native=%s",
        bcDiagVec(d.eye and d.eye.pos or d.eye),bcDiagVec(state.geomDiag.authoredEye),bcDiagVec(d.nativeEye)),
      string.format("ACTION: %s | cell=%s",tostring(d.action or "NONE"),tostring(d.eyeShape or "nil")),
      string.format("LIFT: active=%s blockedFrames=%s clearFrames=%s source=%s targetY=%s",
        tostring(d.liftActive),tostring(d.liftBlockedFrames or 0),tostring(d.liftClearFrames or 0),
        tostring(d.liftSource or "nil"),bcDiagNum(d.liftTargetY)),
      string.format("CANOPY CLEAR: active=%s top=%s targetY=%s source=%s",
        tostring(d.canopyClearActive),bcDiagNum(d.canopyClearTop),
        bcDiagNum(d.canopyClearTargetY),tostring(d.canopyClearSource or "nil")),
      string.format("BUILDING: comp=%s dist=%s body=%s..%s | semantics=fascia<->roof",
        tostring(d.buildingComp or "nil"),bcDiagNum(d.buildingDist),
        bcDiagNum(d.buildingBottom),bcDiagNum(d.buildingTop)),
      string.format("SHELL: comp=%s dist=%s roofTop=%s",
        tostring(d.buildingShellComp or "nil"),bcDiagNum(d.buildingShellDist),
        bcDiagNum(d.buildingShellTop)),
      string.format("CANOPY CREST: token=%s holdY=%s source=%s",
        tostring(d.canopyCrestToken or "nil"),bcDiagNum(d.canopyCrestY),tostring(d.canopyCrestSource or "nil")),
      string.format("STRUCT VIEW ROOF: comps=%s targetY=%s",
        tostring(d.structuralViewRoofComps or "nil"),
        d.structuralViewRoofTargetY and string.format("%.1f",d.structuralViewRoofTargetY) or "nil"),
      "VIEW45 F: "..tostring(d.view45Focus or "-"),
      "VIEW45 P: "..tostring(d.view45Player or "-"),
      "VIEW45 E: "..tostring(d.view45Enemy or "-"),
      "VIEW46 ARB: "..tostring(d.viewArbitration46 or "legacy/none"),
      string.format("ROOF14: token=%s mode=%s top=%s targetY=%s",
        tostring(state.geomDiag.roofApproachToken or "nil"),
        tostring(state.geomDiag.roofApproachMode or "nil"),
        bcDiagNum(state.geomDiag.roofApproachTop),
        bcDiagNum(state.geomDiag.roofApproachTargetY)),
      string.format("ROOF15: token=%s entryY=%s lastStrong=%s crestY=%s top=%s",
        tostring(state.geomDiag.roofViewCrestToken or "nil"),
        bcDiagNum(state.geomDiag.roofApproachEntryY),
        bcDiagNum(state.geomDiag.roofViewLastStrongY),
        bcDiagNum(state.geomDiag.roofViewCrestY),
        bcDiagNum(state.geomDiag.roofViewCrestTop)),
      "BOUND49: "..tostring(d.boundary49 or "none"),
      "PHASE RC8: "..tostring(d.phaseHandoffRC3 or "none"),
      string.format("PASSIVE READ: token=%s intent=%s frames=%s source=%s targetY=%s",
        tostring(d.passiveReadToken or "nil"),tostring(d.passiveReadIntent or d.passiveShotIntent or "none"),
        tostring(d.passiveReadFrames or 0),tostring(d.passiveReadSource or "nil"),bcDiagNum(d.passiveReadTargetY)),
      string.format("PASSIVE ENV: P clear=%s/9 fol=%s struct=%s other=%s | E clear=%s/9 fol=%s struct=%s other=%s",
        tostring(d.passiveReadPlayerClear or "-"),tostring(d.passiveReadPlayerFoliage or "-"),
        tostring(d.passiveReadPlayerStructural or "-"),tostring(d.passiveReadPlayerOther or "-"),
        tostring(d.passiveReadEnemyClear or "-"),tostring(d.passiveReadEnemyFoliage or "-"),
        tostring(d.passiveReadEnemyStructural or "-"),tostring(d.passiveReadEnemyOther or "-")),
      string.format("PASSIVE ESCAPE: token=%s side=%s rise=%s dev=%s",
        tostring(d.passiveEscapeToken or "nil"),bcDiagNum(d.passiveEscapeSide),
        bcDiagNum(d.passiveEscapeRise),bcDiagNum(d.passiveEscapeDeviation)),
      "eye occupancy: "..bcDiagFlag(d.eye),
      "focus LOS: "..bcDiagFlag(d.focusLOS).." | player LOS: "..bcDiagFlag(d.playerLOS).." | enemy LOS: "..bcDiagFlag(d.enemyLOS),
      "READ core player: "..bcDiagReadability(d.playerRead).." | enemy: "..bcDiagReadability(d.enemyRead),
      "READ featured: "..tostring(d.featuredSide or "none").." SILHOUETTE: "..bcDiagReadability(d.featuredRead),
      string.format("READ PROTECT: active=%s frames=%s source=%s lift=%s/%s",
        tostring(d.featureReadActive),tostring(d.featureReadFrames or 0),tostring(d.featureReadSource or "nil"),
        bcDiagNum(d.featureReadOffset),bcDiagNum(d.featureReadTargetOffset)),
      "travel prev->eye: "..bcDiagFlag(d.travel),
    }
    if state.geomDiag.lastHit and state.geomDiag.hitHold>0 then
      local h=state.geomDiag.lastHit
      lines[#lines+1]="LAST HIT: "..tostring(h.label).." "..tostring(h.source or "?").." @ "..bcDiagVec(h.pos)
    else
      lines[#lines+1]="LAST HIT: none"
    end
    local lineH=15
    local pad=6
    local width=(g.getWidth and g.getWidth() or 1120)
    local boxW=math.min(width-16,900)
    local boxH=pad*2+#lines*lineH
    g.push("all")
    g.origin()
    g.setFont(diagHudFont)
    g.setColor(0,0,0,0.80)
    g.rectangle("fill",8,8,boxW,boxH,4,4)
    g.setColor(1,1,1,1)
    for i,line in ipairs(lines) do g.print(line,8+pad,8+pad+(i-1)*lineH) end
    g.pop()
  end)
  if not ok and not state.geomDiag.hudErrorLogged then
    state.geomDiag.hudErrorLogged=true
    mod.log:warn("[geometry diagnostics] HUD failed: %s",tostring(err))
  end
end

state.battleOpening.optionStyle=function()
  -- v1.0.9 release mask: keep the proven Phenac choreography/source in-tree,
  -- but do not expose or activate it until its remaining interaction work is
  -- complete. Returning OFF here also neutralises stale values from test builds.
  return "off"
end
state.battleOpening.enabled=function()
  return state.battleOpening.optionStyle()~="off"
end
state.battleOpening.skipToHold=function(reason)
  if not state.battleOpening.active or state.battleOpening.phase~="swoop" then
    return false
  end
  state.battleOpening.time=tonumber(state.battleOpening.duration) or 13.20
  state.battleOpening.phase="hold"
  state.battleOpening.holdTime=0
  -- This is an intentional camera-only CUT to the authored Phenac prompt
  -- composition. The logical B edge is consumed before BattleState sees it,
  -- so the game's encounter text/send-out lifecycle does not advance.
  state.blend=1
  logDiagnostic("battle opening skipped -> Phenac prompt hold ("..tostring(reason or "skip")..")")
  return true
end
state.battleOpening.clear=function()
  state.battleOpening.pending=false
  state.battleOpening.active=false
  state.battleOpening.style=nil
  state.battleOpening.time=0
  state.battleOpening.duration=13.20
  state.battleOpening.phase="idle"
  state.battleOpening.holdTime=0
  state.battleOpening.trainerPromptSeen=false
  state.battleOpening.wildPrompt=false
  state.battleOpening.lastCamera=nil
  state.battleOpening.lastPitch=nil
end
state.battleOpening.queue=function()
  state.battleOpening.clear()
  if enabled() and state.battleOpening.enabled() then
    state.battleOpening.pending=true
    state.battleOpening.style=state.battleOpening.optionStyle()
    state.battleOpening.duration=13.20
  end
end
state.battleOpening.begin=function()
  if not state.battleOpening.pending or not state.battleOpening.enabled() then return false end
  state.battleOpening.pending=false
  state.battleOpening.active=true
  state.battleOpening.style=state.battleOpening.optionStyle()
  state.battleOpening.time=0
  state.battleOpening.duration=13.20
  state.battleOpening.phase="swoop"
  state.battleOpening.holdTime=0
  local b=state.battle
  state.battleOpening.trainerPromptSeen=b and (not not b.showEnemyTrainer) or false
  state.battleOpening.wildPrompt=b and (not not b.wild) or false
  state.active=false
  state.idle=0
  state.blend=0
  logDiagnostic("battle opening started: "..tostring(state.battleOpening.style)
      ..(state.battleOpening.wildPrompt and " / wild" or ""))
  return true
end

local HERO_INTRO_DURATION=9.4
-- Compact Send-In Test 1: later player summons facing an already-active enemy
-- get a deliberately shorter portrait phrase rather than forcing the battle
-- engine to wait for the full ceremonial BC Hero entrance.
local function battleIntroStyle()
  -- Gold Test 5 deliberately enables the EXISTING BC Hero / Send-In Director
  -- through the same saved option as Gen 1.  The Gold adapter supplies the live
  -- presentation state; no separate Gold intro grammar is invented here.
  return mod.options:get("dynamicIntro")=="off" and "off" or "hero"
end
local function battleIntroOn()
  return battleIntroStyle() ~= "off"
end
local function attackCameraStyle()
  return mod.options:get("attackCamera") or "off"
end
local function stadiumAttackOn()
  -- Gold Test 6 routes the SAME released Stadium Attack Camera through the
  -- Gold presentation adapter.  The option still owns the phase: OFF yields
  -- cleanly to the host camera, exactly as Camera Authority requires.
  return attackCameraStyle()=="stadium"
end
local function faintCameraOn()
  -- Gold Test 6 likewise enables the existing Faint Camera rather than a
  -- generation-specific copy.  Adapter facts below supply Gold presentation
  -- timing while Gen-1 behaviour remains unchanged.
  return mod.options:get("faintCamera") ~= "off"
end
local function introFramingScale()
  local value=mod.options:get("introFraming") or "wide"
  -- Optical-only framing control. WIDE is the APB-era canonical BC Hero intro
  -- composition. The historical 1.00 "standard" value remains save-compatible
  -- but is now labelled NEAR because APB-aware subjects make it visibly tighter.
  -- EXTRA WIDE gives additional breathing room; CLOSE remains the intentional
  -- intimate portrait treatment.
  if value=="extra_wide" then return 1.75 end
  if value=="wide" then return 1.45 end
  if value=="close" then return 0.78 end
  return 1.00
end
local function introSpeedScale()
  local value=mod.options:get("introSpeed") or "fast"
  if value=="faster" then return 3.0 end    -- optional accelerated intro presentation
  if value=="fast" then return 2.0 end      -- established v0.7.1 default
  if value=="slow" then return 0.75 end     -- gentler presentation
  return 1.0                                -- normal / legacy normal
end
function bcIntroPanOn()
  return (mod.options:get("introPan") or "off") ~= "off"
end
local function introResetMode()
  return mod.options:get("introReset") or "b"
end
local cancelActiveIntro
local function clearIntro(preserveStructuralHandoff,preserveOpeningAnchor)
  state.intro.active=false
  state.intro.style=nil
  state.intro.side=nil
  state.intro.time=0
  state.intro.compact=false
  if not preserveOpeningAnchor then
    state.intro.openingStructuralCamera=nil
    state.intro.openingStructuralMode=nil
    state.intro.openingStructuralPitch=nil
    state.intro.openingChainCamera=nil
    state.intro.openingChainPitch=nil
    state.intro.openingChainMode=nil
    state.intro.openingChainHold=false
    state.intro.openingBridgeActive=false
  end
  if not preserveStructuralHandoff then
    state.intro.structuralHandoffNeeded=false
  end
end
local function queueIntro(side)
  if battleIntroStyle()~="hero" then return end
  -- A full encounter-level Battle Intro already presents the initial wild
  -- opponent. Keep that suppression authoritative across every event seam: a
  -- later battler_switched notification for the same opening must not re-arm
  -- the redundant enemy Pokemon Intro. Trainer battles are unaffected, and
  -- later non-initial enemy replacements remain eligible as before.
  if side=="enemy" and state.intro.initial and state.battle and state.battle.wild
      and state.battleOpening.enabled() then
    state.intro.pendingEnemy=false
    logDiagnostic("initial wild enemy Pokemon Intro suppressed by full Battle Intro")
    return
  end
  if side=="enemy" then state.intro.pendingEnemy=true
  elseif side=="player" then state.intro.pendingPlayer=true end
end
state.intro.playerUnderThreat=function(battle)
  -- Test 3 keeps Test 2's narrow rule but distinguishes an enemy that is
  -- merely live from a hostile action that can actually follow this Send-In.
  --
  -- Gen 1 trainer battles can offer the player a free change after an opponent
  -- faints. The foe's replacement is presented first and the player's agreed
  -- replacement follows. At that instant battle.enemy is live, but there is no
  -- immediate hostile action waiting to pre-empt the player's presentation.
  if state.intro.initial or not battle then return false end
  if state.intro.enemyFreshSendIn then return false end
  -- A forced replacement after the player's own faint begins only after the
  -- KO'ing action has completed. The next state after this Send-In is the
  -- player's command menu, so there is no immediate hostile action to outrun.
  if state.intro.playerFaintReplacement then return false end
  if battle.showEnemyTrainer or battle.enemySendingOut then return false end
  local enemy=battle.enemy
  if not enemy or enemy.fainted then return false end
  local shown=tonumber(enemy.shownHP)
  if shown~=nil and shown<=0 then return false end
  return true
end

local function startIntro(side,style,compact)
  style=style or "hero"
  state.intro.openingBridgeActive=false
  state.intro.active=true
  state.intro.style=style
  state.intro.side=side
  state.intro.time=0
  state.intro.compact=compact and true or false
  state.intro.structuralHandoffNeeded=false
  if side=="player" then
    -- This grace belongs only to the immediate replacement chain. Once the
    -- player's Send-In is classified, the newly arrived enemy becomes an
    -- ordinary established threat for any later voluntary switch.
    state.intro.enemyFreshSendIn=false
    state.intro.playerFaintReplacement=false
  end
  if side=="enemy" then
    state.intro.pendingEnemy=false
  elseif side=="player" then
    state.intro.pendingPlayer=false
  end
  state.active=false
  state.idle=0
  state.blend=0
  if state.intro.compact then
    logDiagnostic("compact send-in: "..tostring(side).." / live enemy")
  else
    logDiagnostic("battle intro: "..style..(side and (" / "..side) or ""))
  end
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
  state.attack.goldAnimToken=nil
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
  state.battleOpening.clear()
  local keepGoldEnemy=backends.__gold and state.intro.pendingEnemy or false
  local keepGoldPlayer=backends.__gold and state.intro.pendingPlayer or false
  clearIntro()
  state.intro.pendingEnemy=keepGoldEnemy
  state.intro.pendingPlayer=keepGoldPlayer
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
  state.attack.goldAnimToken=nil
  logDiagnostic("stadium attack armed: "..tostring(side).." / "..tostring(moveId).." / "..tostring(state.attack.mode))
end
local function beginAttack()
  if not state.attack.pending then return end
  state.battleOpening.clear()
  -- Gen 1 can safely discard a queued Intro when a real move starts. Gen 2 is
  -- presentation-late: its logic may already have emitted a future replacement
  -- battler_switched while the finishing move has not yet appeared on screen.
  -- Preserve those future Send-In arms on Gold so the visible replacement can
  -- still receive BC Hero after the current Attack Camera finishes.
  local keepGoldEnemy=backends.__gold and state.intro.pendingEnemy or false
  local keepGoldPlayer=backends.__gold and state.intro.pendingPlayer or false
  clearIntro()
  state.intro.pendingEnemy=keepGoldEnemy
  state.intro.pendingPlayer=keepGoldPlayer
  state.attack.pending=false
  state.attack.active=true
  state.attack.time=0
  state.attack.progress=0
  state.attack.sawAnimation=false
  state.attack.animTotal=0
  state.attack.tail=0
  state.attack.goldAnimToken=nil
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
  state.battleOpening.clear()
  state.directorBattle=(state.directorBattle or 0)+1
  state.directorPlan=((state.directorBattle-1)%3)+1
  clearIntro()
  clearAttack()
  clearFaint()
  state.stadiumMapBoundaryRisk=false
  state.geomDiag.prevEye=nil
  state.geomDiag.wallClipActive=false
  state.geomDiag.wallViewActive=false
  state.geomDiag.lastWallViewEye=nil
  state.geomDiag.liftActive=false
  state.geomDiag.liftBlockedFrames=0
  state.geomDiag.liftClearFrames=0
  state.geomDiag.liftTargetY=nil
  state.geomDiag.liftSource=nil
  state.geomDiag.liftClaimed=false
  state.geomDiag.canopyPathToken=nil
  state.geomDiag.roofApproachToken=nil
  state.geomDiag.roofApproachTop=nil
  state.geomDiag.roofApproachComps=nil
  state.geomDiag.roofApproachMode=nil
  state.geomDiag.roofApproachTargetY=nil
  state.geomDiag.roofApproachEntryY=nil
  state.geomDiag.roofViewCrestToken=nil
  state.geomDiag.roofViewCrestY=nil
  state.geomDiag.roofViewLastStrongY=nil
  state.geomDiag.roofViewCrestTop=nil
  state.geomDiag.roofViewCrestComps=nil
  state.geomDiag.passiveReadToken=nil
  state.geomDiag.passiveReadFrames=0
  state.geomDiag.passiveReadIntent=nil
  state.geomDiag.passiveReadSource=nil
  state.geomDiag.passiveEscapeToken=nil
  state.geomDiag.passiveEscapeDX=nil
  state.geomDiag.passiveEscapeDY=nil
  state.geomDiag.passiveEscapeDZ=nil
  state.geomDiag.passiveEscapeSide=nil
  state.geomDiag.passiveEscapeRise=nil
  state.geomDiag.passiveEscapeDeviation=nil
  state.geomDiag.passiveReadTargetY=nil
  state.geomDiag.passiveReadPlayerClear=nil
  state.geomDiag.passiveReadPlayerFoliage=nil
  state.geomDiag.passiveReadEnemyClear=nil
  state.geomDiag.passiveReadEnemyFoliage=nil
  state.geomDiag.featureReadActive=false
  state.geomDiag.featureReadFrames=0
  state.geomDiag.featureReadOffset=0
  state.geomDiag.featureReadTargetOffset=nil
  state.geomDiag.featureReadSide=nil
  state.geomDiag.featureReadSource=nil
  state.geomDiag.action="NONE"
  state.geomDiag.rawEye=nil
  state.geomDiag.authoredEye=nil
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

-- Environment grammar fallback ------------------------------------------------
-- Generic geometry safety remains the first line of defence.  A tiny number of
-- environments can nevertheless be fundamentally hostile to a preset's camera
-- language even when individual camera positions are technically recoverable.
-- Viridian Forest is the first proven case: its dense canopy repeatedly turns
-- Stadium Classic's low, wide travelling grammar into long foliage curtains,
-- while DW3 Classic remains readable and looks naturally at home in the same
-- space.
--
-- This is deliberately transient.  The user's stored preset is never changed;
-- only passive cinematography for this battle is degraded to a proven grammar.
-- Attack, faint and intro modules keep their own ownership and safety rules.
local function bcArenaMapKey(arena)
  local map=type(arena)=="table" and arena.map or nil
  if type(map)~="table" then return nil end
  local raw=map.id or map.name or map.mapId or map.mapID
  if raw==nil then return nil end
  local key=tostring(raw):upper():gsub("%s+","_")
  return key
end

local function passivePresetForArena(arena)
  -- Test 15 deliberately removes the Viridian Stadium->DW3 substitution so
  -- both raw DW3 and raw Stadium exercise the same shared canopy-clearance layer.
  -- The stored preset is untouched; production can restore the proven fallback
  -- unless this generic rule demonstrably makes it unnecessary.
  return selectedPreset(),nil
end

-- First Configure Preset proof: a DW3-owned framing profile.  This is saved
-- independently of the selected preset, so switching to Hero Portrait and
-- back restores the user's DW3 choice.  Framing is optical rather than a
-- positional push: the camera path remains inside the already-proven safe
-- volume while the field of view provides increasing degrees of closeness.
local function dw3FramingScale()
  local value=mod.options:get("dw3Framing") or "standard"
  if value=="extra_wide" then return 1.32 end
  if value=="wide" then return 1.16 end
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

-- Shared contextual preset controls. These are deliberately applied inside each
-- authored pose builder, before BC's existing hard/soft protection stack. The
-- defaults are identity transforms, so a fresh/update install renders exactly
-- like v1.0.8 until the user changes a setting.
state.presetTuning=state.presetTuning or {}
state.presetTuning.framingScale=function(key)
  local value=mod.options:get(key) or "standard"
  if value=="extra_wide" then return 1.32 end
  if value=="wide" then return 1.16 end
  if value=="near" then return 0.86 end
  if value=="close" then return 0.72 end
  return 1.00
end
state.presetTuning.speedScale=function(key)
  local value=mod.options:get(key) or "medium"
  for _,e in ipairs(SPEEDS) do if e.value==value then return e.scale end end
  return 1.00
end
state.presetTuning.heightDegrees=function(key)
  local value=mod.options:get(key) or "standard"
  if value=="low" then return -4.0 end
  if value=="high" then return 4.0 end
  return 0.0
end
state.presetTuning.heroAngleScale=function()
  local value=mod.options:get("heroAngle") or "standard"
  if value=="shallow" then return 0.72 end
  if value=="strong" then return 1.30 end
  return 1.00
end
state.presetTuning.stadiumAngleScale=function()
  local value=mod.options:get("stadiumAngle") or "standard"
  -- Stadium's source-derived yaw vocabulary is much broader than DW3's small
  -- shoulder arc, so keep the same SHALLOW/STANDARD/STRONG UI but use a
  -- conservative authored bias. Hard geometry safety still has final authority.
  if value=="shallow" then return 0.90 end
  if value=="strong" then return 1.10 end
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
  local t=((state.time or 0)/state.presetTuning.speedScale("heroSpeed"))%cycle
  local target,other,mirror,localT,targetSide
  if t<9.4 then
    target,other,mirror,localT,targetSide=arena.player,arena.enemy,1,t,"player"
  elseif t<10.2 then
    return nil,nil,0
  elseif t<19.6 then
    target,other,mirror,localT,targetSide=arena.enemy,arena.player,-1,t-10.2,"enemy"
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
  local elevation=math.rad(12.0+state.presetTuning.heightDegrees("heroHeight"))

  -- Mirror the successful V5 side offset across the arena. Swapping target
  -- and opponent reverses the forward axis; mirror reverses the lateral arc.
  local arc=mirror*(math.rad(24.0)+micro)*state.presetTuning.heroAngleScale()
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)

  local actorScale=poseActorScale(R)
  local apbLift,apbMinScale=0,nil
  if state.apb and type(state.apb.subjectFraming)=="function" then
    local fn=state.apb.subjectFramingCinematic or state.apb.subjectFraming
    apbLift,apbMinScale=fn(targetSide,R,1.30,R.lookY+4.9*actorScale)
  end
  local baseFocusY=(groundY or 0)+R.lookY+4.9*actorScale+apbLift
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
  local portraitFrameScale=math.max(0.46,tonumber(apbMinScale) or 0)
  local frame=R.frameH*portraitFrameScale
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end

-- Colosseum-inspired full battle opening -----------------------------------
-- This is deliberately a BATTLE-level grammar, separate from BC Hero's
-- per-Pokemon Send-In grammar. It establishes the arena first, then yields to
-- the ordinary trainer/wild encounter prompt and any queued Pokemon Intro.
--
-- Test 4 keeps Test 3's source-speed timing and continuous travel, but refines
-- the Phenac Stadium choreography from the supplied reference: the camera stays
-- low on entry, tips up only briefly, comes back down sooner, lets the player
-- re-enter the composition before crossing behind the opponent, then spends the
-- final part of the travelling phrase on the source-like opponent-side pan.
state.battleOpening.pose=function(arena,groundY,camera)
  if not state.battleOpening.active or state.battleOpening.style~="colosseum"
      or not arena or not arena.player or not arena.enemy then
    return nil,nil,0
  end

  local R=camera.rigFor(arena)
  if not R then return nil,nil,0 end

  local px,pz=arena.player[1],arena.player[2]
  local ex,ez=arena.enemy[1],arena.enemy[2]
  local mx,mz=(arena.mid and arena.mid[1]) or ((px+ex)*0.5),
              (arena.mid and arena.mid[2]) or ((pz+ez)*0.5)

  local fx,fz=ex-px,ez-pz
  local spacing=math.sqrt(fx*fx+fz*fz)
  if spacing<1e-4 then return nil,nil,0 end
  fx,fz=fx/spacing,fz/spacing
  local rx,rz=-fz,fx

  local duration=tonumber(state.battleOpening.duration) or 13.20
  local t=(state.battleOpening.phase=="hold") and duration
      or math.max(0,math.min(duration,tonumber(state.battleOpening.time) or 0))

  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local travelRadius=baseRadius
  if arena.cam=="wide" or spacing>56.0 then
    travelRadius=baseRadius*0.78
  end

  local actorScale=poseActorScale(R)
  local normalY=(groundY or 0)+R.lookY+2.1*actorScale

  -- The final Phenac opponent tableau consumes the same renderer-neutral APB
  -- placement/fit semantics as Stadium's subject shots. The authored eye/path
  -- remains Phenac; APB only tells the final LOOK target where the actually
  -- presented enemy body is and how much minimum optical room it needs.
  local finalAnchor=R.lookY+2.1*actorScale+0.018*travelRadius
  local finalEnemyLift,finalEnemyMinScale=0,nil
  if state.apb and type(state.apb.subjectFraming)=="function" then
    local fn=state.apb.subjectFramingCinematic or state.apb.subjectFraming
    finalEnemyLift,finalEnemyMinScale=fn("enemy",R,1.30,finalAnchor)
  end
  local finalFocusY=(groundY or 0)+finalAnchor+(tonumber(finalEnemyLift) or 0)

  local function point(af,ar,up)
    return {
      mx+fx*(af*travelRadius)+rx*(ar*travelRadius),
      normalY+up*travelRadius,
      mz+fz*(af*travelRadius)+rz*(ar*travelRadius),
    }
  end
  local function enemyPoint(af,ar,up)
    return {
      ex+fx*(af*travelRadius)+rx*(ar*travelRadius),
      normalY+up*travelRadius,
      ez+fz*(af*travelRadius)+rz*(ar*travelRadius),
    }
  end
  local function playerPoint(af,ar,up)
    return {
      px+fx*(af*travelRadius)+rx*(ar*travelRadius),
      normalY+up*travelRadius,
      pz+fz*(af*travelRadius)+rz*(ar*travelRadius),
    }
  end

  -- Time-aware cubic Hermite interpolation keeps velocity continuous through
  -- differently spaced source landmarks.  Phenac Test 5 adds an extra early
  -- landmark so the low approach stays predominantly an approach until the
  -- tilt reaches its crest; the major orbit/rightward movement follows that
  -- crest instead of anticipating it.
  local function timedSpline(points,times,now)
    local n=#points
    if n<2 then return points[1] end
    if now<=times[1] then return {points[1][1],points[1][2],points[1][3]} end
    if now>=times[n] then return {points[n][1],points[n][2],points[n][3]} end

    local seg=1
    while seg<n and now>times[seg+1] do seg=seg+1 end
    if seg>=n then seg=n-1 end

    local t0,t1=times[seg],times[seg+1]
    local h=math.max(1e-4,t1-t0)
    local u=math.max(0,math.min(1,(now-t0)/h))
    local u2,u3=u*u,u*u*u
    local h00=2*u3-3*u2+1
    local h10=u3-2*u2+u
    local h01=-2*u3+3*u2
    local h11=u3-u2

    local function velocity(i)
      if i<=1 then
        local dt=math.max(1e-4,times[2]-times[1])
        return {(points[2][1]-points[1][1])/dt,
                (points[2][2]-points[1][2])/dt,
                (points[2][3]-points[1][3])/dt}
      elseif i>=n then
        local dt=math.max(1e-4,times[n]-times[n-1])
        return {(points[n][1]-points[n-1][1])/dt,
                (points[n][2]-points[n-1][2])/dt,
                (points[n][3]-points[n-1][3])/dt}
      end
      local dt=math.max(1e-4,times[i+1]-times[i-1])
      return {(points[i+1][1]-points[i-1][1])/dt,
              (points[i+1][2]-points[i-1][2])/dt,
              (points[i+1][3]-points[i-1][3])/dt}
    end

    local a,b=points[seg],points[seg+1]
    local ma,mb=velocity(seg),velocity(seg+1)
    return {
      h00*a[1]+h10*h*ma[1]+h01*b[1]+h11*h*mb[1],
      h00*a[2]+h10*h*ma[2]+h01*b[2]+h11*h*mb[2],
      h00*a[3]+h10*h*ma[3]+h01*b[3]+h11*h*mb[3],
    }
  end

  -- PHENAC TEST 5 TIMING -------------------------------------------------
  --   0.00 -> 2.55  long, low outside-right approach
  --   2.55 -> 4.05  tilt begins/crests while travel is still mostly inward
  --   4.05 -> 5.35  the main lateral/orbit movement starts at the crest
  --   5.35 -> 6.65  camera is already tipping back below the opponent
  --   6.65 -> 8.55  player returns on the right
  --   8.55 -> 10.65 pass behind/across the opponent
  --  10.65 -> 13.20 move farther in FRONT of the opponent and settle right
  --   HOLD          same authored camera; slow right-then-left pan until input
  local knots={0.00,2.55,4.05,5.35,6.65,8.55,10.65,12.00,13.20}

  local eyePoints={
    point(-0.52, 2.58,0.045),
    point(-0.18, 1.28,0.050),
    point( 0.02, 0.96,0.072),
    enemyPoint( 0.46, 0.50,0.095),
    enemyPoint( 0.42,-0.52,0.055),
    point(-0.02,-1.18,0.048),
    enemyPoint( 0.04,-0.82,0.044),
    -- Keep a hint of Test 5's pleasing S language, but put this waypoint much
    -- nearer the direct chord into the final front/right settle. This removes
    -- the pronounced inward detour before the opponent-front arc.
    enemyPoint(-0.22,-0.15,0.043),
    enemyPoint(-0.42, 0.46,0.044),
  }
  local eye=timedSpline(eyePoints,knots,t)

  -- The focus opens back toward the battle axis/player before the crossing,
  -- then returns to the opponent.  The final focus is dead-centred on the
  -- opponent so entering HOLD is continuous; HOLD itself adds only a slow
  -- lateral look-pan and never teleports the physical eye.
  local focusLevel=normalY+travelRadius*0.040
  local pReturn=playerPoint(0.28,-0.05,0.020)
  local focusPoints={
    {mx-fx*(0.10*travelRadius),focusLevel,mz-fz*(0.10*travelRadius)},
    {mx+fx*(0.02*travelRadius),focusLevel,mz+fz*(0.02*travelRadius)},
    {mx+fx*(0.08*travelRadius),normalY+travelRadius*0.050,
       mz+fz*(0.08*travelRadius)},
    {ex-rx*(0.03*travelRadius),normalY+travelRadius*0.045,
       ez-rz*(0.03*travelRadius)},
    {mx-fx*(0.16*travelRadius)+rx*(0.05*travelRadius),
       normalY+travelRadius*0.026,
       mz-fz*(0.16*travelRadius)+rz*(0.05*travelRadius)},
    {pReturn[1],normalY+travelRadius*0.018,pReturn[3]},
    {ex+rx*(0.12*travelRadius),mix(normalY+travelRadius*0.018,finalFocusY,0.20),
       ez+rz*(0.12*travelRadius)},
    {ex-rx*(0.08*travelRadius),mix(normalY+travelRadius*0.018,finalFocusY,0.62),
       ez-rz*(0.08*travelRadius)},
    {ex,finalFocusY,ez},
  }
  local focus=timedSpline(focusPoints,knots,t)

  -- Source review: the lift begins earlier than Test 4, but the camera does
  -- not commit to the large orbit until the crest. It then looks back down
  -- almost immediately. This keeps Phenac's signature dome-look without
  -- spending several seconds on empty sky in today's flatter Recomp arenas.
  local tiltUp=0
  if t>2.15 and t<4.05 then
    tiltUp=smootherstep((t-2.15)/1.90)
  elseif t>=4.05 and t<5.55 then
    tiltUp=1-smootherstep((t-4.05)/1.50)
  end
  focus[2]=focus[2]+travelRadius*(0.28*tiltUp)
  if t>4.45 then
    local lookDown=smootherstep(math.min(1,(t-4.45)/1.45))
    focus[2]=focus[2]-travelRadius*(0.085*lookDown)
  end

  -- Once the travelling phrase has settled, keep the final physical eye and
  -- pan the LOOK target slowly to the right and then back left. At holdTime=0
  -- sin() is zero, so there is no positional/focus snap at the phase boundary.
  if state.battleOpening.phase=="hold" then
    local ht=tonumber(state.battleOpening.holdTime) or 0
    local pan=math.sin(ht*(2*math.pi/8.2))
    local amount=0.16*travelRadius*pan
    focus[1]=focus[1]+rx*amount
    focus[3]=focus[3]+rz*amount
  end

  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local flat=math.sqrt(dx*dx+dz*dz)
  local distance=math.sqrt(dx*dx+dy*dy+dz*dz)

  local frameScale
  if t<4.05 then
    frameScale=mix(1.78,1.46,smootherstep(t/4.05))
  elseif t<9.80 then
    frameScale=mix(1.46,1.20,smootherstep((t-4.05)/5.75))
  else
    frameScale=mix(1.20,1.08,smootherstep((t-9.80)/3.40))
  end
  if tonumber(finalEnemyMinScale) and t>=10.65 then
    local aq=smootherstep(math.max(0,math.min(1,(t-10.65)/(duration-10.65))))
    local needed=mix(frameScale,tonumber(finalEnemyMinScale),aq)
    frameScale=math.max(frameScale,needed)
  end
  local fov=2*math.atan(((R.frameH*frameScale)/2)/math.max(1,distance))
  fov=math.max(math.rad(24),math.min(math.rad(82),fov))
  local pitch=math.atan2(flat,math.max(1e-3,eye[2]-focus[2]))

  -- Acquire over about half a second at source speed. Hold remains fully BC-
  -- owned until the actual encounter prompt progresses into the send-out.
  local w=(state.battleOpening.phase=="hold") and 1
      or ((t<0.52) and smootherstep(t/0.52) or 1)
  local cam={eye=eye,focus=focus,fov=fov,curve=0}
  state.battleOpening.lastCamera=cam
  state.battleOpening.lastPitch=pitch
  return cam,pitch,w
end

local function dynamicIntroPose(arena,groundY,camera,sideOverride,timeOverride,allowInactive)
  if not arena or not arena.player or not arena.enemy then return nil,nil,0 end
  if not state.intro.active and not allowInactive then return nil,nil,0 end
  local R=camera.rigFor(arena)
  local side=sideOverride or state.intro.side
  if side~="player" and side~="enemy" then return nil,nil,0 end
  local target,other,mirror
  if side=="player" then target,other,mirror=arena.player,arena.enemy,1
  else target,other,mirror=arena.enemy,arena.player,-1 end
  local rawT=tonumber(timeOverride) or state.intro.time
  local compact=(timeOverride==nil and state.intro.compact) and true or false
  local localT=rawT
  if compact then
    -- Reuse only the strongest middle portion of the proven Hero portrait:
    -- immediate acquisition, a tiny reverse-horizontal drift, then release.
    -- The compact phrase deliberately omits the long upward Hero Tilt.
    local q=math.max(0,math.min(1,rawT/(state.intro.compactDuration or 3.8)))
    localT=3.0+3.35*smootherstep(q)
  end
  local tx,tz=target[1],target[2]
  local ox,oz=other[1],other[2]
  local fx,fz=ox-tx,oz-tz
  local len=math.sqrt(fx*fx+fz*fz)
  if len<1e-4 then return nil,nil,0 end
  fx,fz=fx/len,fz/len
  local rx,rz=-fz,fx
  local w
  if compact then
    -- state.blend supplies the quick acquisition. Hold the portrait cleanly,
    -- then soften only the final quarter so the passive/attack owner can take it.
    local q=math.max(0,math.min(1,rawT/(state.intro.compactDuration or 3.8)))
    if q<0.76 then w=1.0
    else w=1.0-smootherstep((q-0.76)/0.24) end
  elseif localT<2.6 then w=smootherstep(localT/2.6)
  elseif localT<6.8 then w=1.0
  else w=1.0-smootherstep((localT-6.8)/2.6) end
  local holdT=math.max(0,math.min(1,(localT-2.6)/4.2))
  local micro=math.sin(holdT*math.pi*2)*math.rad(0.35)
  local panUp=bcIntroPanOn() and not compact
  local tiltT=math.max(0,math.min(1,(localT-2.9)/2.75))
  local tiltEase=panUp and smootherstep(tiltT) or 0
  -- HERO TILT OFF keeps the established portrait height/framing but replaces
  -- the upward focus pan with a very small reverse horizontal movement over
  -- the same middle/hold window.  This fills the authored time without turning
  -- the option into a static freeze and leaves geometry safety fully active.
  local reverseT=math.max(0,math.min(1,(localT-3.0)/3.35))
  local reverseEase=(not panUp) and smootherstep(reverseT) or 0
  local actorScale=poseActorScale(R)
  local apbLift,apbMinScale=0,nil
  if state.apb and type(state.apb.subjectFraming)=="function" then
    local fn=state.apb.subjectFramingCinematic or state.apb.subjectFraming
    apbLift,apbMinScale=fn(side,R,1.30,R.lookY+4.9*actorScale)
  end
  -- APB solves base presentation height first. Hero Tilt, if enabled, remains
  -- an additional style movement layered on top of correct subject framing.
  local baseFocusY=(groundY or 0)+R.lookY+4.9*actorScale+apbLift

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
    local reverseBack=1.75*reverseEase
    local eye={
      mx + rx*(mirror*(lateral+microOffset)) - fx*(axial+reverseBack),
      baseFocusY + 10.5,
      mz + rz*(mirror*(lateral+microOffset)) - fz*(axial+reverseBack),
    }
    local cameraDistance=math.sqrt((eye[1]-tx)^2+(eye[3]-tz)^2)
    local focusRise=cameraDistance*math.tan(math.rad(2.25))*tiltEase
    local focus={tx,baseFocusY+focusRise,tz}
    -- Recover intimacy optically rather than by moving the eye closer.
    local introFrameScale=math.max(0.43*introFramingScale(),tonumber(apbMinScale) or 0)
    local frame=R.frameH*introFrameScale
    local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
    -- Wider intro framing is deliberately bounded to avoid replacing a
    -- close sprite crop with an exaggerated fisheye on constrained fallback
    -- rigs. The legacy 1.00 value remains available as NEAR.
    local introFrameChoice=mod.options:get("introFraming") or "wide"
    if introFrameChoice=="extra_wide" then
      fov=math.min(fov,math.rad(85.0))
    elseif introFrameChoice=="wide" then
      fov=math.min(fov,math.rad(78.0))
    end
    local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
    logDiagnostic(string.format("dynamic intro midpoint fallback: cam=%s spacing=%.1f",tostring(arena.cam),len))
    return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
  end

  -- Established Hero Portrait intro for normal arenas.
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local radius=baseRadius*0.80
  local elevation=math.rad(12.0)
  local reverseArc=math.rad(2.0)*reverseEase
  local arc=mirror*(math.rad(24.0)+micro-reverseArc)
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)
  local eye={tx+dx*flat,baseFocusY+radius*math.sin(elevation),tz+dz*flat}
  local horizontalDistance=math.max(1,flat)
  local focusRise=horizontalDistance*math.tan(math.rad(2.25))*tiltEase
  local focus={tx+rx*(len*0.010)*mirror,baseFocusY+focusRise,tz+rz*(len*0.010)*mirror}
  local cameraDistance=math.sqrt((eye[1]-focus[1])^2+(eye[3]-focus[3])^2)
  local introFrameScale=math.max(0.46*introFramingScale(),tonumber(apbMinScale) or 0)
  local frame=R.frameH*introFrameScale
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local introFrameChoice=mod.options:get("introFraming") or "wide"
  if introFrameChoice=="extra_wide" then
    fov=math.min(fov,math.rad(85.0))
  elseif introFrameChoice=="wide" then
    fov=math.min(fov,math.rad(78.0))
  end
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end


-- Shared safety for the new Stadium-derived modules. Like Stadium Classic's
-- existing boundary layer, this scales an eye back along its requested ray;
-- it never independently clamps X/Z, so the authored yaw is preserved.
local function clampEyeToArena(arena,anchorX,anchorZ,eye,maxFlat)
  if not eye then return eye,false end
  local bx,bz=eye[1]-anchorX,eye[3]-anchorZ
  local flat=math.sqrt(bx*bx+bz*bz)
  if flat<1e-4 then return eye,false end
  local limit=tonumber(maxFlat) or flat
  local mapLimited=false

  -- Synthetic 2D-3D B / Stadium B stages carry a map only for sky/palette
  -- context. That unrelated Kanto map must never constrain their camera.
  local map=(arena and not arena.discs) and arena.map or nil
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
    if edge~=math.huge and edge>8.0 and edge<limit then
      limit=edge
      mapLimited=true
    end
  end
  if limit<flat then
    local k=limit/flat
    eye[1]=anchorX+bx*k
    eye[3]=anchorZ+bz*k
  end
  return eye,mapLimited
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
  do
    local limited
    eye,limited=clampEyeToArena(arena,sx,sz,eye,baseRadius*0.96)
    if limited then state.stadiumMapBoundaryRisk=true end
  end

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

  -- APB attack semantics:
  -- Resolve both presentation subjects once for this frame. Attack choreography
  -- remains the existing Stadium grammar; APB only supplies vertical subject
  -- placement and a minimum optical fit for elevated actors.
  local apbAttackerLift,apbAttackerScale=0,nil
  local apbTargetLift,apbTargetScale=0,nil
  if mode~="field" and state.apb
      and type(state.apb.subjectFraming)=="function" then
    local attackAnchor=R.lookY+4.2*actorScale
    apbAttackerLift,apbAttackerScale=state.apb.subjectFraming(
      attackerIsPlayer and "player" or "enemy",R,1.18,attackAnchor)
    if mode=="target" then
      apbTargetLift,apbTargetScale=state.apb.subjectFraming(
        attackerIsPlayer and "enemy" or "player",R,1.18,attackAnchor)
    end
  end

  -- Before the real move animation starts, the authored establishing shot is
  -- explicitly attacker-centric.
  if mode~="field" then
    focusY=focusY+apbAttackerLift
  end

  -- Self-only moves (Barrier, Recover, stat boosts, Reflect, Rest, etc.)
  -- never spend animation time looking across the field. The whole available
  -- animation window becomes one restrained attacker portrait: a slow
  -- three-quarter pivot with the same upward focus tilt that made BC Hero's
  -- portrait shot work. Short vanilla animations therefore read as one clean
  -- move instead of racing through launch/track/impact/rise in under a second.
  if mode=="self" then
    local q=smootherstep(p)
    local mirror=attackerIsPlayer and 1 or -1
    local portraitY=baseY+4.9*actorScale+apbAttackerLift
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
    do
      local limited
      eye,limited=clampEyeToArena(arena,ax,az,eye,baseRadius*0.94)
      if limited then state.stadiumMapBoundaryRisk=true end
    end

    local horizontal=math.max(1,math.sqrt((eye[1]-ax)^2+(eye[3]-az)^2))
    local tilt=smootherstep(math.max(0,math.min(1,(p-0.12)/0.78)))
    local focusRise=horizontal*math.tan(math.rad(2.8))*tilt
    local focus={ax+rx*(spacing*0.008)*mirror,portraitY+focusRise,
                 az+rz*(spacing*0.008)*mirror}
    local dx2,dy2,dz2=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
    local dist=math.max(1,math.sqrt(dx2*dx2+dy2*dy2+dz2*dz2))
    local horiz=math.sqrt(dx2*dx2+dz2*dz2)
    local selfFrameScale=math.max(mix(0.52,0.47,q),tonumber(apbAttackerScale) or 0)
    local frame=R.frameH*selfFrameScale
    local fov=2*math.atan((frame/2)/dist)
    if state.apb then
      state.apb.attackPhase="self"
      state.apb.attackMode=mode
      state.apb.attackSide=state.attack.side
      state.apb.attackAttackerLift=apbAttackerLift
      state.apb.attackTargetLift=0
    end
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
    if state.apb then
      state.apb.attackAttackerLift=0
      state.apb.attackTargetLift=0
    end
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
    frameScale=math.max(mix(0.56,0.48,q),tonumber(apbAttackerScale) or 0)
  elseif p<0.58 then
    phase="track"
    local q=smootherstep((p-0.22)/0.36)
    -- Track the aim point across the battlefield as the source does during
    -- Flamethrower's travelling middle section. The eye stays laterally clear
    -- of the attack line, so 3D FX remain readable rather than hidden behind
    -- either Pokémon.
    focusX=mix(ax,tx,q)
    focusZ=mix(az,tz,q)
    local trackLift=mix(apbAttackerLift,apbTargetLift,q)
    focusY=baseY+mix(4.0,3.2,q)*actorScale+trackLift
    yaw=mix(105.0,78.0,q)
    elev=mix(8.0,11.0,q)
    radius=baseRadius*0.80

    -- The optical fit transitions with the featured subject rather than
    -- snapping from air to ground / ground to air at impact.
    local aFit=tonumber(apbAttackerScale) or 0
    local tFit=tonumber(apbTargetScale) or 0
    frameScale=math.max(0.72,mix(aFit,tFit,q))
  elseif p<0.82 then
    phase="impact"
    local q=smootherstep((p-0.58)/0.24)
    focusX,focusZ,focusY=tx,tz,baseY+4.0*actorScale+apbTargetLift
    yaw=mix(154.0,122.0,q)
    elev=mix(9.0,17.0,q)
    radius=baseRadius*mix(0.72,0.76,q)
    frameScale=math.max(mix(0.47,0.50,q),tonumber(apbTargetScale) or 0)
  else
    phase="rise"
    local q=smootherstep((p-0.82)/0.18)
    focusX,focusZ,focusY=tx,tz,baseY+(4.0+1.2*q)*actorScale+apbTargetLift
    yaw=mix(122.0,158.0,q)
    elev=mix(17.0,48.0,q)
    radius=baseRadius*mix(0.76,0.94,q)
    frameScale=math.max(mix(0.50,0.62,q),tonumber(apbTargetScale) or 0)
  end

  local function eyeAround(cx,cz,yawDeg,elevDeg,rad)
    local a=math.rad(yawDeg)
    local dirX,dirZ=fx*math.cos(a)+rx*math.sin(a),
                    fz*math.cos(a)+rz*math.sin(a)
    local e=math.rad(elevDeg)
    local flat=rad*math.cos(e)
    return {cx+dirX*flat,focusY+rad*math.sin(e),cz+dirZ*flat}
  end

  -- The pre-animation/declare attacker composition uses the default launch
  -- frameScale; give elevated attackers the same minimum fit without changing
  -- any phase timing.
  if mode=="target" and not state.attack.sawAnimation then
    frameScale=math.max(frameScale,tonumber(apbAttackerScale) or 0)
  end

  -- Lightweight breadcrumbs for phone-side validation/reporting.
  if state.apb then
    state.apb.attackPhase=phase
    state.apb.attackMode=mode
    state.apb.attackSide=state.attack.side
    state.apb.attackAttackerLift=apbAttackerLift
    state.apb.attackTargetLift=apbTargetLift
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
  do
    local limited
    eye,limited=clampEyeToArena(arena,anchorX,anchorZ,eye,baseRadius*0.94)
    if limited then state.stadiumMapBoundaryRisk=true end
  end

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
  local stadiumTime=(state.time or 0)/state.presetTuning.speedScale("stadiumSpeed")
  local cycleIndex=math.floor(stadiumTime/total)
  local t=stadiumTime%total
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
  state.passiveShotToken="stadium:"..tostring(cycleIndex)..":"..tostring(shot)
  -- Purpose metadata for the shared passive readability layer. This describes
  -- what the authored Stadium shot is trying to show; it does not alter the pose.
  if shot==1 or shot==2 or shot==7 then state.passiveShotIntent="player"
  elseif shot==4 or shot==5 or shot==8 then state.passiveShotIntent="enemy"
  elseif shot==3 then state.passiveShotIntent="both"
  else state.passiveShotIntent="environment" end

  -- APB Stadium subject-aware symmetry.
  -- Player shots 1/2/7 consume PLAYER APB; enemy shots 4/5/8 consume ENEMY APB.
  -- Both-subject/environmental shots remain canonical controls. The complete
  -- shot is translated vertically, preserving Stadium yaw/radius/pitch/FOV.
  local apbPlayerLift,apbEnemyLift=0,0
  local apbPlayerBounds,apbEnemyBounds=nil,nil
  if state.apb and type(state.apb.resolve)=="function" then
    if shot==1 or shot==2 or shot==7 then
      local ok,bounds=pcall(state.apb.resolve,"player",state.battle)
      if ok and type(bounds)=="table" and tonumber(bounds.elevation) then
        apbPlayerBounds=bounds
        apbPlayerLift=math.max(0,math.min(12.0,tonumber(bounds.elevation) or 0))
      end
    elseif shot==4 or shot==5 or shot==8 then
      local ok,bounds=pcall(state.apb.resolve,"enemy",state.battle)
      if ok and type(bounds)=="table" and tonumber(bounds.elevation) then
        apbEnemyBounds=bounds
        apbEnemyLift=math.max(0,math.min(12.0,tonumber(bounds.elevation) or 0))
      end
    end
  end
  local apbPlayerShapeLift,apbEnemyShapeLift=0,0
  local apbPlayerShapeScale,apbEnemyShapeScale=nil,nil

  -- Stadium's proven elevated Pidgeotto path above stays untouched.
  -- The new branch runs only when elevation is zero and the actor qualifies as
  -- tall-grounded. Each authored subject shot supplies its own vertical anchor
  -- below, so no field-centric shot is changed.
  local targetX,targetZ,targetY=mx,mz,baseY
  local yaw,elev,radius,frameScale
  local apbPlayerCloseScale,apbEnemyCloseScale=nil,nil
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
    if apbPlayerBounds and (tonumber(apbPlayerBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbPlayerShapeLift,apbPlayerShapeScale=state.apb.framingFromBounds(
        apbPlayerBounds,R,1.30,R.lookY+3.6*actorScale)
    end
    targetX,targetZ,targetY=px,pz,baseY+3.6*actorScale+apbPlayerLift+apbPlayerShapeLift
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
    if apbPlayerBounds and (tonumber(apbPlayerBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbPlayerShapeLift,apbPlayerShapeScale=state.apb.framingFromBounds(
        apbPlayerBounds,R,1.30,R.lookY+3.6*actorScale)
    end
    targetX,targetZ,targetY=px,pz,baseY+3.6*actorScale+apbPlayerLift+apbPlayerShapeLift
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
    if apbEnemyBounds and (tonumber(apbEnemyBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbEnemyShapeLift,apbEnemyShapeScale=state.apb.framingFromBounds(
        apbEnemyBounds,R,1.30,R.lookY+2.0*actorScale)
    end
    targetX,targetZ,targetY=ex,ez,baseY+2.0*actorScale+apbEnemyLift+apbEnemyShapeLift
    yaw=mix(140.0,180.0,u)
    elev=3.0
    radius=baseRadius*0.78
    frameScale=0.72
    focusOffset=(1-u)*spacing*0.44

  elseif shot==5 then
    -- Enemy portrait/hold.
    if apbEnemyBounds and (tonumber(apbEnemyBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbEnemyShapeLift,apbEnemyShapeScale=state.apb.framingFromBounds(
        apbEnemyBounds,R,1.30,R.lookY+3.6*actorScale)
    end
    targetX,targetZ,targetY=ex,ez,baseY+3.6*actorScale+apbEnemyLift+apbEnemyShapeLift
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
    if apbPlayerBounds and (tonumber(apbPlayerBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbPlayerShapeLift,apbPlayerShapeScale=state.apb.framingFromBounds(
        apbPlayerBounds,R,1.30,R.lookY+4.9*actorScale)
    end
    targetX,targetZ,targetY=px,pz,baseY+4.9*actorScale+apbPlayerLift+apbPlayerShapeLift
    yaw,elev,radius,frameScale=32.0,16.0,baseRadius*0.80,0.46

  elseif shot==8 then
    -- Mirrored close defender portrait.
    if apbEnemyBounds and (tonumber(apbEnemyBounds.elevation) or 0)<0.75
        and state.apb and type(state.apb.framingFromBounds)=="function" then
      apbEnemyShapeLift,apbEnemyShapeScale=state.apb.framingFromBounds(
        apbEnemyBounds,R,1.30,R.lookY+4.9*actorScale)
    end
    targetX,targetZ,targetY=ex,ez,baseY+4.9*actorScale+apbEnemyLift+apbEnemyShapeLift
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

  -- Contextual Stadium controls. STANDARD/MEDIUM are identity transforms and
  -- therefore remain the source-faithful v1.0.8 camera. Wide / Extra Wide
  -- expand the optical field without changing the source path; framing is
  -- applied before APB's minimum-fit max(), so a user's CLOSE choice can
  -- never defeat actor-presentation readability. Physical safety follows later.
  yaw=yaw*state.presetTuning.stadiumAngleScale()
  elev=elev+state.presetTuning.heightDegrees("stadiumHeight")
  frameScale=frameScale*state.presetTuning.framingScale("stadiumFraming")

  -- CINEMATIC CLOSE: derive the intimate subject-fit policy separately from
  -- the proven full-fit values. Placement/lift is unchanged.
  if state.apb and type(state.apb.cinematicFramingFromBounds)=="function" then
    if (shot==1 or shot==2 or shot==7) and apbPlayerBounds then
      local anchor=(shot==7) and (R.lookY+4.9*actorScale) or (R.lookY+3.6*actorScale)
      local _,s=state.apb.cinematicFramingFromBounds(apbPlayerBounds,R,1.30,anchor)
      apbPlayerCloseScale=s
    elseif (shot==4 or shot==5 or shot==8) and apbEnemyBounds then
      local anchor=(shot==4) and (R.lookY+2.0*actorScale)
          or ((shot==8) and (R.lookY+4.9*actorScale) or (R.lookY+3.6*actorScale))
      local _,s=state.apb.cinematicFramingFromBounds(apbEnemyBounds,R,1.30,anchor)
      apbEnemyCloseScale=s
    end
  end

  -- APB Stadium fit: elevation fixes WHERE the subject is; height + viewport
  -- aspect determines whether that subject can physically fit in the authored
  -- close framing. Test 2 proved that a position-only lift can look good in a
  -- portrait viewport yet still crop Pidgeotto badly in landscape.
  --
  -- The backend camera FOV behaves as a horizontal framing angle, so the world
  -- span required to preserve a vertical actor height grows with screen aspect.
  -- Only semantically ELEVATED subject shots consume this experimental fit;
  -- grounded/tall-grounded controls (e.g. Onix) remain canonical for now.
  local apbFitScale=nil
  local apbBounds=nil
  if shot==1 or shot==2 or shot==7 then apbBounds=apbPlayerBounds
  elseif shot==4 or shot==5 or shot==8 then apbBounds=apbEnemyBounds end

  if type(apbBounds)=="table"
      and (tonumber(apbBounds.elevation) or 0)>0.75
      and (tonumber(apbBounds.height) or 0)>1.0 then
    local aspect=16/9
    if love and love.graphics and type(love.graphics.getDimensions)=="function" then
      local ok,w,h=pcall(love.graphics.getDimensions)
      if ok and tonumber(w) and tonumber(h) and h>0 then
        aspect=math.max(0.35,math.min(3.5,w/h))
      end
    end
    -- 30% vertical breathing room around the measured posed body. In portrait,
    -- the authored close frame normally already exceeds this requirement, so
    -- max() leaves it untouched. Ultra-wide/desktop landscape gets the extra
    -- optical room it actually needs.
    local requiredHorizontalSpan=(tonumber(apbBounds.height) or 0)*1.30*aspect
    local fullFitScale=requiredHorizontalSpan/math.max(1e-3,R.frameH)

    -- WIDTH TEST 2: shot 1 is explicitly a wide presentation shot. Let a truly
    -- broad actor participate in the opening full-fit envelope, then preserve
    -- Cinematic Close's existing wide -> close transition. No other portrait
    -- or subject shot consumes breadth.
    if shot==1 and apbPlayerBounds
        and state.apb and type(state.apb.isBroadPresentation)=="function" then
      local broad=state.apb.isBroadPresentation(apbPlayerBounds,R)
      if broad then
        local widthFull=(tonumber(apbPlayerBounds.breadth) or 0)*1.05/math.max(1e-3,R.frameH)
        fullFitScale=math.max(fullFitScale,widthFull)
      end
    end

    local closeFitScale=(shot==1 or shot==2 or shot==7)
        and (tonumber(apbPlayerCloseScale) or fullFitScale)
        or (tonumber(apbEnemyCloseScale) or fullFitScale)

    if shot==1 then
      -- Preserve the glorious wide/rising opening horseshoe, then deliberately
      -- converge toward the intimate subject framing as the rotation resolves.
      local closeQ=smootherstep(math.max(0,math.min(1,(u-0.55)/0.45)))
      apbFitScale=mix(fullFitScale,closeFitScale,closeQ)
    else
      apbFitScale=closeFitScale
    end
    frameScale=math.max(frameScale,apbFitScale)
    state.apb.lastAspect=aspect
    state.apb.lastFitScale=apbFitScale
    state.apb.lastAuthoredScale=state.apb.lastAuthoredScale or frameScale
  else
    -- No elevated fit. A tall-grounded subject may still need the optical frame
    -- computed by the shape supplement above.
    local groundedShapeScale=nil
    local groundedCloseScale=nil
    if shot==1 or shot==2 or shot==7 then
      groundedShapeScale=apbPlayerShapeScale
      groundedCloseScale=apbPlayerCloseScale
    elseif shot==4 or shot==5 or shot==8 then
      groundedShapeScale=apbEnemyShapeScale
      groundedCloseScale=apbEnemyCloseScale
    end

    if shot==1 and tonumber(groundedShapeScale) and apbPlayerBounds
        and state.apb and type(state.apb.isBroadPresentation)=="function" then
      local broad=state.apb.isBroadPresentation(apbPlayerBounds,R)
      if broad then
        local widthFull=(tonumber(apbPlayerBounds.breadth) or 0)*1.05/math.max(1e-3,R.frameH)
        groundedShapeScale=math.max(groundedShapeScale,widthFull)
      end
    end

    if shot==1 and tonumber(groundedShapeScale) and tonumber(groundedCloseScale) then
      local closeQ=smootherstep(math.max(0,math.min(1,(u-0.55)/0.45)))
      groundedShapeScale=mix(groundedShapeScale,groundedCloseScale,closeQ)
    elseif tonumber(groundedCloseScale) then
      groundedShapeScale=groundedCloseScale
    end

    if tonumber(groundedShapeScale) and groundedShapeScale>0 then
      frameScale=math.max(frameScale,groundedShapeScale)
      if state.apb then
        local aspect=16/9
        if love and love.graphics and type(love.graphics.getDimensions)=="function" then
          local ok,w,h=pcall(love.graphics.getDimensions)
          if ok and tonumber(w) and tonumber(h) and h>0 then
            aspect=math.max(0.35,math.min(3.5,w/h))
          end
        end
        state.apb.lastAspect=aspect
        state.apb.lastFitScale=groundedShapeScale
      end
    elseif state.apb then
      state.apb.lastAspect=nil
      state.apb.lastFitScale=nil
    end
  end

  -- Cramped/problem rigs: preserve Stadium's composition but do not send a
  -- target-relative portrait eye through the known sprite deadzone. Subject
  -- shots become a midpoint/perpendicular safe composition; orbit/wide shots
  -- remain naturally midpoint-based.
  local subjectShot=(shot==1 or shot==2 or shot==4 or shot==5 or shot==7 or shot==8)
  if apbPlayerLift>0.001 then
    logDiagnostic(string.format("APB Stadium player elevation: shot=%d lift=%.2f",shot,apbPlayerLift))
  elseif apbEnemyLift>0.001 then
    logDiagnostic(string.format("APB Stadium enemy elevation: shot=%d lift=%.2f",shot,apbEnemyLift))
  elseif apbPlayerShapeLift>0.001 then
    logDiagnostic(string.format("APB Stadium player tall-grounded: shot=%d centreShift=%.2f",shot,apbPlayerShapeLift))
  elseif apbEnemyShapeLift>0.001 then
    logDiagnostic(string.format("APB Stadium enemy tall-grounded: shot=%d centreShift=%.2f",shot,apbEnemyShapeLift))
  end
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
        if edgeLimit<maxFlat then state.stadiumMapBoundaryRisk=true end
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
  local cycleIndex=math.floor(t/cycle)
  t=t%cycle
  local shot,localT,shotIndex
  for idx,candidate in ipairs(list) do
    local d=shotDuration(candidate)
    if t<d then shot,localT,shotIndex=candidate,t/d,idx break end
    t=t-d
  end
  if not shot then return nil end
  state.passiveShotToken="dw3:"..tostring(cycleIndex)..":"..tostring(shotIndex or 0)
  -- DW3 already knows the portrait target through shot.kind. Expose that intent
  -- to safety rather than asking the safety layer to reverse-engineer it from
  -- focus proximity. Orbits retain their deliberately environmental language.
  if shot.kind=="player" then state.passiveShotIntent="player"
  elseif shot.kind=="enemy" then state.passiveShotIntent="enemy"
  else state.passiveShotIntent="environment" end

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
  local dw3ApbLift,dw3ApbMinScale=0,nil
  if (shot.kind=="player" or shot.kind=="enemy")
      and state.apb and type(state.apb.subjectFraming)=="function" then
    local fn=state.apb.subjectFramingCinematic or state.apb.subjectFraming
    dw3ApbLift,dw3ApbMinScale=fn(shot.kind,R,1.30,R.lookY+3.6*poseActorScale(R))
  end
  if shot.kind~="orbit" then
    focusY=focusY+3.6*poseActorScale(R)+dw3ApbLift
  end
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
  -- is bit-for-bit the existing composition; Wide / Extra Wide open the lens
  -- while Near / Close narrow it, without moving the eye toward or away from
  -- either battler or changing the safe
  -- narrow-arena fallback trajectory.
  local opticalFrameScale=frameScale*dw3FramingScale()
  if shot.kind=="player" or shot.kind=="enemy" then
    opticalFrameScale=math.max(opticalFrameScale,tonumber(dw3ApbMinScale) or 0)
  end
  return {eye=eye,focus=focus,fov=2*math.atan(((R.frameH*opticalFrameScale)/2)/dist),curve=0},
         math.atan2(flat,math.max(1e-3,eye[2]-focusY)),1
end

-- Cross-generation structured configuration -------------------------------
-- Rebase 8: child configuration stays INSIDE the live ManagerState instance.
-- This is the compatibility boundary we actually want: ManagerState remains
-- the owner of navigation, values, input and persistence, while whichever UI
-- presentation is installed (vanilla, Colosseum, Stadium2 Overworld Models,
-- etc.) continues to own ManagerState's drawing.  No private Gen1 UI modules
-- are required and BC no longer pushes/draws a bespoke submenu screen.
;(function()
  local MOD_ID="BATTLE_CINEMATICS"

  local defs={
    cameraAuthority={label="CAMERA AUTHORITY",default="priority",choices={{"BC PRIORITY","priority"},{"COOPERATIVE","cooperative"},{"BC DISABLED","disabled"}}},
    spriteFacing={label="SPRITE FACING",default="dynamic",choices={{"HOST DEFAULT","host"},{"TURN ONLY","turn"},{"DYNAMIC","dynamic"}}},
    preset={label="IDLE PRESET",default="stadium",choices={{"DW3 CLASSIC","dw3"},{"HERO PORTRAIT","portrait_test"},{"STADIUM 64","stadium"},{"EXTERNAL","external"}}},
    idleView={label="IDLE VIEW",default="standard",choices={{"STANDARD","standard"},{"WIDE","wide"},{"EXTRA WIDE","extra_wide"},{"ULTRA WIDE","ultra_wide"}}},
    initialDelay={label="INITIAL DELAY",default="quick_2",choices={{"IMMEDIATE (0s)","immediate"},{"2 SECONDS","quick_2"},{"4 SECONDS","quick_4"},{"SHORT (6s)","short"},{"STANDARD (9s)","standard"},{"LONG (12s)","long"},{"EXTRA LONG (15s)","extra_long"}}},
    secondaryView={label="SECOND VIEW PIP",default="off",choices={{"OFF","off"},{"ON","on"}}},
    secondaryViewSize={label="PIP SIZE",default="small",choices={{"STANDARD","standard"},{"SMALL","small"}}},
    secondaryViewFraming={label="PIP FRAMING",default="normal",choices={{"NORMAL","normal"},{"CLOSE","close"}}},
    secondaryViewSide={label="PIP SIDE",default="left",choices={{"LEFT (DW3)","left"},{"RIGHT","right"}}},
    secondaryViewPlace={label="PIP PLACE",default="mid_right",choices={{"MID CENTER","mid_center"},{"TOP RIGHT","top_right"},{"MID RIGHT","mid_right"},{"TOP LEFT","top_left"},{"MID LEFT","mid_left"},{"CUSTOM","custom"}}},
    dynamicIntro={label="PKMN INTRO CAM",default="on",choices={{"BC HERO","on"},{"OFF","off"}}},
    attackCamera={label="ATTACK CAMERA",default="stadium",choices={{"STADIUM","stadium"},{"OFF","off"}}},
    faintCamera={label="FAINT CAMERA",default="on",choices={{"ON","on"},{"OFF","off"}}},
    diagnostics={label="DIAGNOSTICS",default="off",choices={{"OFF","off"},{"ON","on"}}},
    inputReturn={label="RESET CAMERA",default="off",choices={{"OFF","off"},{"CONFIRMED ACTION","confirmed"},{"ANY INPUT","any"}}},
    introFraming={label="FRAMING",default="wide",choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"NEAR","standard"},{"CLOSE","close"}}},
    introSpeed={label="SPEED",default="fast",choices={{"SLOW","slow"},{"NORMAL","normal"},{"FAST","fast"},{"FASTER","faster"}}},
    introPan={label="HERO TILT",default="off",choices={{"ON","on"},{"OFF","off"}}},
    introReset={label="CANCEL",default="b",choices={{"B BUTTON","b"},{"ANY INPUT","any"},{"ON MOVE/ITEM","confirmed"},{"OFF","off"}}},
    dw3Framing={label="FRAMING",default="standard",choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}}},
    circleSpeed={label="ORBIT SPEED",default="medium",choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}}},
    dw3Height={label="HEIGHT",default="standard",choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}}},
    dw3Angle={label="ANGLE",default="standard",choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}}},
    stadiumFraming={label="FRAMING",default="standard",choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}}},
    stadiumSpeed={label="ORBIT SPEED",default="medium",choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}}},
    stadiumHeight={label="HEIGHT",default="standard",choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}}},
    stadiumAngle={label="ANGLE",default="standard",choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}}},
    heroFraming={label="FRAMING",default="standard",choices={{"EXTRA WIDE","extra_wide"},{"WIDE","wide"},{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}}},
    heroSpeed={label="ORBIT SPEED",default="medium",choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}}},
    heroHeight={label="HEIGHT",default="standard",choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}}},
    heroAngle={label="ANGLE",default="standard",choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}}},
  }

  local PRESET_KEYS={
    dw3Framing=true,circleSpeed=true,dw3Height=true,dw3Angle=true,
    stadiumFraming=true,stadiumSpeed=true,stadiumHeight=true,stadiumAngle=true,
    heroFraming=true,heroSpeed=true,heroHeight=true,heroAngle=true,
  }

  local function value(key)
    local d=defs[key]
    local v=mod.options:get(key)
    if v==nil and d then v=d.default end
    return v
  end

  local function labelFor(key)
    local d=defs[key]
    if not d then return "----" end
    local v=value(key)
    for _,c in ipairs(d.choices or {}) do if c[2]==v then return c[1] end end
    return tostring(v or "----")
  end

  local function bucket(container)
    if type(container)~="table" then return nil end
    container.modOptions=container.modOptions or {}
    container.modOptions[MOD_ID]=container.modOptions[MOD_ID] or {}
    return container.modOptions[MOD_ID]
  end

  local function setOption(game,key,v)
    local loader=game and game.mods
    if loader then
      local b=bucket(loader)
      if b then b[key]=v end
    end
    local opts=game and game.save and game.save.options
    if opts then
      local b=bucket(opts)
      if b then b[key]=v end
    end
    if game then
      if type(game.writeOptions)=="function" then pcall(game.writeOptions,game)
      elseif type(game.persistOptions)=="function" then pcall(game.persistOptions,game) end
    end
    local events=loader and loader.events
    if events and type(events.emit)=="function" then
      pcall(events.emit,events,"mod.options_changed",{mod=MOD_ID,key=key,value=v})
    end
  end

  state.secondaryViewProbe.setOption=setOption

  local function step(game,key,dir)
    local d=defs[key]
    local choices=d and d.choices or nil
    if not (choices and #choices>0) then return end
    local cur=value(key)
    local idx=1
    for i,c in ipairs(choices) do if c[2]==cur then idx=i break end end
    idx=((idx-1+(dir or 1))%#choices)+1
    setOption(game,key,choices[idx][2])
  end

  local function optRow(key)
    return {id=key,label=defs[key].label,value=function() return labelFor(key) end,
      step=function(g,dir) step(g,key,dir); return true end}
  end

  local function actionRow(id,label,getValue,activate)
    return {id=id,label=label,value=getValue or function() return "" end,activate=activate}
  end

  local function clearSkinHints(self)
    -- These fields are presentation hints only. Randy's ManagerState skin uses
    -- them for category titles; other UI presenters safely ignore them.
    self._stadium2OptionCategory=nil
    self._stadium2OptionCategoryLabel=nil
    self._stadium2OptionCategoryDescription=nil
  end

  local function restoreRoot(self)
    if not self._bcOptionSubmenu then return false end
    self.optionRows=self._bcOptionRootRows or self.optionRows or {}
    self.cursor=tonumber(self._bcOptionRootCursor) or 1
    self.scroll=tonumber(self._bcOptionRootScroll) or 0
    self._bcOptionSubmenu=nil
    self._bcOptionSubmenuTitle=nil
    self._bcOptionSubmenuDescription=nil
    self._bcOptionRootRows=nil
    self._bcOptionRootCursor=nil
    self._bcOptionRootScroll=nil
    clearSkinHints(self)
    return true
  end

  local function showSubmenu(self,title,description,rows)
    if type(self)~="table" or type(rows)~="table" then return end
    if not self._bcOptionSubmenu then
      self._bcOptionRootRows=self.optionRows
      self._bcOptionRootCursor=self.cursor
      self._bcOptionRootScroll=self.scroll
    end
    self._bcOptionSubmenu=true
    self._bcOptionSubmenuTitle=title
    self._bcOptionSubmenuDescription=description
    self.optionRows=rows
    self.cursor=1
    self.scroll=0
    -- Randy's custom ManagerState presentation deliberately exposes these
    -- category-label fields; filling them lets its own renderer name BC's child
    -- page while ManagerState remains the logic owner. No draw code is borrowed.
    self._stadium2OptionCategory="battle_cinematics"
    self._stadium2OptionCategoryLabel=title
    self._stadium2OptionCategoryDescription=description
  end

  local function presetRows(manager)
    local p=value("preset") or "stadium"
    local rows={}
    local title="PRESET SETTINGS"
    local desc="Battle Cinematics preset settings."
    local keys
    if p=="dw3" then
      title="DW3 SETTINGS"; desc="DW3 Classic camera settings."
      keys={"dw3Framing","circleSpeed","dw3Height","dw3Angle"}
    elseif p=="stadium" then
      title="STADIUM SETTINGS"; desc="Stadium 64 camera settings."
      rows[#rows+1]=actionRow("stadiumInfo","STADIUM 64",function() return "SOURCE FAITHFUL" end)
      keys={"stadiumFraming","stadiumSpeed","stadiumHeight","stadiumAngle"}
    elseif p=="external" then
      title="EXTERNAL SETTINGS"; desc="External provider ownership."
      rows[#rows+1]=actionRow("info1","EXTERNAL CAMERA",function() return "HOST OWNED" end)
      rows[#rows+1]=actionRow("info2","BC PHASE MODULES",function() return "INDEPENDENT" end)
    else
      title="HERO SETTINGS"; desc="Hero Portrait camera settings."
      keys={"heroFraming","heroSpeed","heroHeight","heroAngle"}
    end
    for _,k in ipairs(keys or {}) do rows[#rows+1]=optRow(k) end
    if keys then
      rows[#rows+1]=actionRow("reset","RESET TO DEFAULT",function() return "" end,function()
        for _,k in ipairs(keys) do setOption(manager.game,k,defs[k].default) end
      end)
    end
    return title,desc,rows
  end

  local function introRows(manager)
    local rows={optRow("introFraming"),optRow("introSpeed"),optRow("introPan"),optRow("introReset")}
    rows[#rows+1]=actionRow("reset","RESET TO DEFAULT",function() return "" end,function()
      for _,k in ipairs({"introFraming","introSpeed","introPan","introReset"}) do
        setOption(manager.game,k,defs[k].default)
      end
    end)
    return "BC HERO INTRO","Battle Cinematics Pokemon intro settings.",rows
  end

  local function pipRows(manager)
    local rows={optRow("secondaryViewPlace"),optRow("secondaryViewSize"),optRow("secondaryViewSide"),optRow("secondaryViewFraming")}
    rows[#rows+1]=actionRow("reset","RESET TO DEFAULT",function() return "" end,function()
      for _,k in ipairs({"secondaryViewPlace","secondaryViewSize","secondaryViewSide","secondaryViewFraming"}) do
        setOption(manager.game,k,defs[k].default)
      end
      -- CUSTOM coordinates are presentation state rather than visible options,
      -- but resetting them makes the next drag begin from the canonical centre.
      setOption(manager.game,"secondaryViewCustomX",500)
      setOption(manager.game,"secondaryViewCustomY",220)
    end)
    return "PIP CONFIG","Secondary View placement, size, authored side and portrait framing.",rows
  end

  local function legacyRows(manager)
    local rows={optRow("inputReturn")}
    rows[#rows+1]=actionRow("reset","RESET TO DEFAULT",function() return "" end,function()
      setOption(manager.game,"inputReturn",defs.inputReturn.default)
    end)
    return "LEGACY OPTIONS","Legacy Battle Cinematics behavior.",rows
  end

  local function presetValue()
    local p=value("preset") or "stadium"
    if p=="dw3" then return "DW3 CLASSIC" end
    if p=="stadium" then return "STADIUM 64" end
    if p=="external" then return "EXTERNAL" end
    return "HERO PORTRAIT"
  end

  local function patchManagerState(manager)
    if type(manager)~="table" or manager.__bcStructuredOptionsPatched then return end
    if manager.screenId~="ManagerState" or type(manager.buildOptionRows)~="function" then return end

    local originalBuild=manager.buildOptionRows
    manager.buildOptionRows=function(self,m,schema)
      local rows=originalBuild(self,m,schema)
      if not (m and m.id==MOD_ID and type(rows)=="table") then return rows end

      local filtered={}
      local secondaryRootRow=nil
      for _,row in ipairs(rows) do
        if row.id=="secondaryView" then
          -- Keep the host-created option row intact, but move it to the bottom
          -- beside CONFIG PIP so every ManagerState skin still owns presentation.
          secondaryRootRow=row
        elseif not PRESET_KEYS[row.id]
            and row.id~="battleOpening"
            and row.id~="introFraming" and row.id~="introSpeed"
            and row.id~="introPan" and row.id~="introReset"
            and row.id~="inputReturn"
            and row.id~="secondaryViewSize" and row.id~="secondaryViewSide"
            and row.id~="secondaryViewFraming"
            and row.id~="secondaryViewPlace"
            and row.id~="secondaryViewCustomX" and row.id~="secondaryViewCustomY" then
          filtered[#filtered+1]=row
        end
      end

      local insertAt=#filtered
      for i,row in ipairs(filtered) do if row.id=="preset" then insertAt=i+1 break end end
      table.insert(filtered,insertAt,{
        id="__bc_configure_preset",label="CONFIGURE PRESET",value=presetValue,
        activate=function()
          local title,desc,child=presetRows(self)
          showSubmenu(self,title,desc,child)
        end,
      })

      -- CONFIG INTRO CAM belongs directly beneath PKMN INTRO CAM. Keep the
      -- parent toggle and its child configuration visually paired; Secondary View
      -- is inserted later after ATTACK / FAINT. Host ManagerState still owns all
      -- row presentation and skinning.
      local introAt=#filtered+1
      for i,row in ipairs(filtered) do if row.id=="dynamicIntro" then introAt=i+1 break end end
      table.insert(filtered,introAt,{
        id="__bc_intro_config",label="CONFIG INTRO CAM",value=function() return "BC HERO" end,
        activate=function()
          local title,desc,child=introRows(self)
          showSubmenu(self,title,desc,child)
        end,
      })

      -- Secondary View belongs at the end of the CAMERA/product controls, but not
      -- below maintenance rows. Insert its immediate toggle + consolidated child
      -- page after ATTACK / FAINT; LEGACY / DIAGNOSTICS / host reset rows remain
      -- beneath them in their established order.
      local pipAt=#filtered+1
      for i,row in ipairs(filtered) do if row.id=="faintCamera" then pipAt=i+1 break end end
      table.insert(filtered,pipAt,secondaryRootRow or optRow("secondaryView"))
      table.insert(filtered,pipAt+1,{
        id="__bc_pip_config",label="CONFIG PIP",value=function() return "PLACE / SIZE / SIDE / FRAME" end,
        activate=function()
          local title,desc,child=pipRows(self)
          showSubmenu(self,title,desc,child)
        end,
      })

      local legacyAt=#filtered+1
      for i,row in ipairs(filtered) do if row.id=="diagnostics" then legacyAt=i break end end
      table.insert(filtered,legacyAt,{
        id="__bc_legacy_config",label="LEGACY OPTIONS",value=function() return "RESET CAMERA" end,
        activate=function()
          local title,desc,child=legacyRows(self)
          showSubmenu(self,title,desc,child)
        end,
      })
      return filtered
    end

    -- ManagerState remains the screen and therefore remains visible to every
    -- installed Mod Manager skin. Only B needs one extra level: child -> BC root
    -- instead of ManagerState's ordinary options -> detail transition.
    local originalUpdate=manager.updateOptions
    if type(originalUpdate)=="function" then
      manager.updateOptions=function(self,input,...)
        if self._bcOptionSubmenu and input and type(input.wasPressed)=="function"
            and input:wasPressed("b") then
          restoreRoot(self)
          return
        end
        return originalUpdate(self,input,...)
      end
    end

    manager.__bcStructuredOptionsPatched=true
    mod.log:info("BC structured options attached inside live ManagerState (theme-preserving)")
  end

  mod.events:on("screen.pushed",function(ev)
    patchManagerState(ev and ev.state)
    local P=state.secondaryViewProbe
    if P then P.drag=nil; P.lastRect=nil end
  end)

  mod.events:on("game.ready",function(ev)
    local game=ev and ev.game
    local stack=game and game.stack
    local top=nil
    if stack and type(stack.top)=="function" then
      local ok,v=pcall(stack.top,stack); if ok then top=v end
    end
    patchManagerState(top)
  end)

  mod.log:info("cross-generation structured settings registered through ManagerState ownership")
end)()

local Game=select(2,pcall(require,"src.core.Game"))
if type(Game)~="table" then Game={} end

-- Camera Authority / Enabled consolidation ---------------------------------
-- v1.0.11 removes the redundant visible ENABLED row. Preserve the only user
-- state that mattered: an existing ENABLED=OFF becomes CAMERA AUTHORITY=
-- BC DISABLED exactly once; existing ON installs keep their authority choice.
mod.events:on("game.ready",function(ev)
  local game=ev and ev.game
  if not game or mod.options:get("__bcEnabledFolded111") == "done" then return end
  local loader=game.mods
  if not loader then return end
  loader.modOptions=loader.modOptions or {}
  loader.modOptions[MOD_ID]=loader.modOptions[MOD_ID] or {}
  local bucket=loader.modOptions[MOD_ID]
  if bucket.enabled=="off" then bucket.cameraAuthority="disabled" end
  bucket.__bcEnabledFolded111="done"
  if game.save and game.save.options then
    local options=game.save.options
    options.modOptions=options.modOptions or {}
    options.modOptions[MOD_ID]=options.modOptions[MOD_ID] or {}
    local saved=options.modOptions[MOD_ID]
    if saved.enabled=="off" then saved.cameraAuthority="disabled" end
    saved.__bcEnabledFolded111="done"
    if game.writeOptions then game:writeOptions() end
  end
  if loader.events and bucket.cameraAuthority=="disabled" then
    loader.events:emit("mod.options_changed",{mod=MOD_ID,key="cameraAuthority",value="disabled"})
  end
end)

-- 1.0 preset migration -----------------------------------------------------
-- Battle Cinematics 1.0 performs a one-time preset migration. Existing
-- installs are moved to Stadium 64 exactly once; after the
-- marker is written, any later preset choice belongs entirely to the user.
-- The marker is stored in modOptions but intentionally omitted from the public
-- schema so RESET DEFAULTS can never re-arm the migration.
mod.events:on("game.ready",function(ev)
  local game=ev and ev.game
  if not game or mod.options:get("__bcPreset10Migrated")=="done" then return end
  local loader=game.mods
  if not loader then return end
  loader.modOptions=loader.modOptions or {}
  loader.modOptions[MOD_ID]=loader.modOptions[MOD_ID] or {}
  loader.modOptions[MOD_ID].preset="stadium"
  loader.modOptions[MOD_ID].__bcPreset10Migrated="done"
  if game.save and game.save.options then
    local options=game.save.options
    options.modOptions=options.modOptions or {}
    options.modOptions[MOD_ID]=options.modOptions[MOD_ID] or {}
    options.modOptions[MOD_ID].preset="stadium"
    options.modOptions[MOD_ID].__bcPreset10Migrated="done"
    if game.writeOptions then game:writeOptions() end
  end
  if loader.events then
    loader.events:emit("mod.options_changed",{mod=MOD_ID,key="preset",value="stadium"})
  end
  mod.log:info("1.0 preset migration: Stadium 64 selected")
end)

-- APB Hero Tilt 1.0.6 release migration ------------------------------------
-- APB now owns functional subject height/placement. The old upward Hero Tilt
-- is therefore a style option rather than a framing correction. Migrate every
-- existing install to the new canonical OFF state exactly once for the official
-- 1.0.6 release. The release-specific hidden marker intentionally does not reuse
-- prerelease APB test markers, so development/test installs cannot suppress the
-- public upgrade migration. RESET DEFAULTS and later user choices cannot re-arm it.
mod.events:on("game.ready",function(ev)
  local game=ev and ev.game
  if not game or mod.options:get("__bcHeroTiltOffMigrated106Release")=="done" then return end
  local loader=game.mods
  if not loader then return end

  loader.modOptions=loader.modOptions or {}
  loader.modOptions[MOD_ID]=loader.modOptions[MOD_ID] or {}
  loader.modOptions[MOD_ID].introPan="off"
  loader.modOptions[MOD_ID].__bcHeroTiltOffMigrated106Release="done"

  if game.save and game.save.options then
    local options=game.save.options
    options.modOptions=options.modOptions or {}
    options.modOptions[MOD_ID]=options.modOptions[MOD_ID] or {}
    options.modOptions[MOD_ID].introPan="off"
    options.modOptions[MOD_ID].__bcHeroTiltOffMigrated106Release="done"
    if game.writeOptions then game:writeOptions() end
  end

  if loader.events then
    loader.events:emit("mod.options_changed",{mod=MOD_ID,key="introPan",value="off"})
  end
  mod.log:info("APB Hero Tilt migration: Hero Tilt set to OFF once")
end)

-- APB Battle Intro framing 1.0.6 release migration -------------------------
-- The entire APB intro validation line was effectively exercised with WIDE
-- framing. APB-aware STANDARD/1.00 is now a deliberately nearer composition,
-- not the canonical baseline. Force every existing install to WIDE once for the
-- official 1.0.6 release, using a release-specific marker so prerelease APB tests
-- cannot suppress the public upgrade migration; then permanently return ownership
-- of the setting to the user.
mod.events:on("game.ready",function(ev)
  local game=ev and ev.game
  if not game or mod.options:get("__bcIntroWideMigrated106Release")=="done" then return end
  local loader=game.mods
  if not loader then return end

  loader.modOptions=loader.modOptions or {}
  loader.modOptions[MOD_ID]=loader.modOptions[MOD_ID] or {}
  loader.modOptions[MOD_ID].introFraming="wide"
  loader.modOptions[MOD_ID].__bcIntroWideMigrated106Release="done"

  if game.save and game.save.options then
    local options=game.save.options
    options.modOptions=options.modOptions or {}
    options.modOptions[MOD_ID]=options.modOptions[MOD_ID] or {}
    options.modOptions[MOD_ID].introFraming="wide"
    options.modOptions[MOD_ID].__bcIntroWideMigrated106Release="done"
    if game.writeOptions then game:writeOptions() end
  end

  if loader.events then
    loader.events:emit("mod.options_changed",{mod=MOD_ID,key="introFraming",value="wide"})
  end
  mod.log:info("APB Battle Intro migration: Framing set to WIDE once")
end)

-- Structural Convergence RC3 ------------------------------------------------
-- Phase handoff helper. The mature building system can already tell us when an
-- otherwise-normal backend camera is completely hidden behind a component-owned
-- facade. This is especially important around Battle Intro, where the old
-- physical blend could travel from a perfectly safe intro portrait back through
-- a roof/facade toward the native eye before passive Stadium began.
function bcTransitionBuildingBlocked(backend,arena,groundY,camera)
  if not (backend and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs and type(camera)=="table" and type(camera.eye)=="table") then
    return false,nil
  end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return false,cache end
  local gy=tonumber(groundY) or 0
  local focusBlocked=type(camera.focus)=="table"
      and bcViewFirstBarrierIsBuildingFascia46(cache,camera.eye,camera.focus)
  local playerBlocked=type(arena.player)=="table"
      and bcViewFirstBarrierIsBuildingFascia46(cache,camera.eye,{arena.player[1],gy+8.0,arena.player[2]})
  local enemyBlocked=type(arena.enemy)=="table"
      and bcViewFirstBarrierIsBuildingFascia46(cache,camera.eye,{arena.enemy[1],gy+8.0,arena.enemy[2]})
  return focusBlocked and playerBlocked and enemyBlocked,cache
end

function bcIntroReturnCrossesBuilding(backend,arena,cine,base)
  if not (backend and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs and type(cine)=="table" and type(cine.eye)=="table"
      and type(base)=="table" and type(base.eye)=="table") then return false end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return false end
  local hit,source=bcGeomWallLine(cache,cine.eye,base.eye)
  if hit and tostring(source or ""):find("building",1,true) then return true end
  local miss,_,surfaceSource=bcCanopyPathViolation(cache,cine.eye,base.eye)
  if (tonumber(miss) or 0)>0.02 and tostring(surfaceSource or ""):find("building%-roof",1,false) then
    return true
  end
  if cache.buildingRouteTop then
    local top=cache.buildingRouteTop(cine.eye,base.eye,4.0,BC_CANOPY_PATH_STEP)
    if top then return true end
  end
  return false
end

-- During the short pre-intro wait, never let a component-owned building curtain
-- be the presentation merely because the cinematic blend is still zero. Keep
-- the backend X/Z/focus and search only the owning roof's local vertical lane.
-- This does NOT start the intro early and does not move toward an intro portrait.
function bcIntroWaitRoofSafeCamera(backend,arena,groundY,base,poseCamera,sideOverride,roofOnly)
  local blocked,cache=bcTransitionBuildingBlocked(backend,arena,groundY,base)
  if not blocked or not cache then return nil,nil end

  -- RC6 keeps the cheap/local answer first: if the same backend X/Z can simply
  -- rise above the owning roof and recover a usable composition, do that.
  local roofTarget,_,_=bcStructuralViewRoofTarget40(cache,arena,groundY,base)
  if roofTarget then
    local startY=math.max(tonumber(base.eye[2]) or 0,tonumber(roofTarget) or 0)
    -- RC8 opening/trainer evidence: on Celadon the first usable same-X/Z
    -- camera appears around roof+29 (manual right-stick proof), beyond RC6's
    -- old roof+25 ceiling. Search a little farther but still accept the FIRST
    -- usable height, so ordinary low roofs remain minimally corrected.
    for i=0,20 do
      local candidateEye={base.eye[1],startY+i*2.0,base.eye[3]}
      local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
      if not hardEye then
        local candidate=bcCopyCameraWithEye(base,candidateEye)
        if bcWallViewUsable(cache,arena,groundY,candidate) then
          return candidate,"roof"
        end
      end
    end
  end

  if roofOnly then return nil,nil end

  -- Structural Convergence RC6 -------------------------------------------
  -- Celadon RC5 proves that a broad roof can remain a complete view curtain
  -- even when the backend-safe eye is technically above roofTop. More vertical
  -- search at the same X/Z is then the wrong camera language: the eye must leave
  -- the roof's projected footprint. BC already has a mature, generic side-lane
  -- construction that does exactly that -- the Hero Intro portrait geometry.
  -- Promote that GEOMETRIC PRIMITIVE to the shared transition layer rather than
  -- copying map coordinates or inventing a Celadon special case. This does not
  -- start the Intro early; it only supplies a safe presentation eye while the
  -- normal send-out lifecycle is still pending.
  local side=sideOverride
  if side~="player" and side~="enemy" then
    if state.intro.pendingEnemy then side="enemy"
    elseif state.intro.pendingPlayer then side="player"
    elseif state.intro.active then side=state.intro.side end
  end
  if (side=="player" or side=="enemy") and poseCamera then
    local intent=side
    -- Sample a few points from the established Hero hold. The physical lane is
    -- almost unchanged across these times, but the tiny authored micro/tilt can
    -- make one candidate preferable on unusual future geometry.
    local times={3.2,4.7,6.2}
    for _,sampleT in ipairs(times) do
      local candidate=select(1,dynamicIntroPose(arena,groundY,poseCamera,side,sampleT,true))
      if type(candidate)=="table" and type(candidate.eye)=="table"
          and bcPassiveEscapeInsideArena(arena,candidate.eye) then
        local hardEye=select(1,bcGeomWallPoint(cache,candidate.eye[1],candidate.eye[2],candidate.eye[3]))
        if not hardEye then
          local usable=bcWallViewUsable(cache,arena,groundY,candidate)
          local intentGood=bcConvergenceIntentGoodRC1(cache,arena,groundY,candidate.eye,intent)
          if usable and intentGood then
            return candidate,"side"
          end
        end
      end
    end
  end

  return nil,nil
end

-- Structural Convergence RC9 -----------------------------------------------
-- Opening/trainer presentation ownership.
--
-- RC7 manual-camera footage proved two separate facts:
--   1) before BC has an authored shot, eye==native and authoredEye==nil, so the
--      slow left/right sway is the backend's native battle camera, not BC;
--   2) simply raising that SAME native X/Z to the first roof-safe vertical lane
--      makes the trainer presentation readable. At ~Y64 on Celadon the existing
--      INTRO_WAIT_ROOF acceptance already agrees.
--
-- Treat the trainer/send-out seam as a real BC presentation phase instead of
-- applying Pokemon-shot intent before a Pokemon shot exists. When a building
-- curtain owns the opening view, find the minimum usable vertical roof lane,
-- latch its complete eye/focus for the short trainer phase (so backend sway
-- cannot drag it back across the roof), and hand that stable camera to the Hero
-- Intro as its blend base. No map coordinates and no trainer-coordinate guess.
function bcOpeningTrainerPhaseRC8()
  if state.battleOpening.active or state.intro.active or state.attack.active or state.faint.active then
    return false
  end
  local b=state.battle
  if b then
    return (not not b.showEnemyTrainer) or (not not b.showPlayerBack)
  end
  -- Gen1Recomp can expose the battle rig/arena before battle.started hands BC
  -- the battle object. RC7 Celadon footage spends this exact pre-event window
  -- in the backend roof curtain. With no battle object there is by definition
  -- no Pokemon-authored BC phase to preserve, so the same structural opening
  -- contract may own only this rig-visible/tokenless presentation seam.
  return state.rigSeen and state.passiveShotToken==nil
end

function bcOpeningStructuralCameraRC8(backend,arena,groundY,base,poseCamera,allowSide)
  if not (type(base)=="table" and type(base.eye)=="table") then return nil,nil end

  local held=state.intro.openingStructuralCamera
  if type(held)=="table" and type(held.eye)=="table" then
    local cache=bcGeomCacheFor(backend,arena.map)
    if cache.supported
        and not select(1,bcGeomWallPoint(cache,held.eye[1],held.eye[2],held.eye[3]))
        and bcWallViewUsable(cache,arena,groundY,held) then
      return held,state.intro.openingStructuralMode or "roof"
    end
    state.intro.openingStructuralCamera=nil
    state.intro.openingStructuralMode=nil
    state.intro.openingStructuralPitch=nil
  end

  -- Trainer/opening presentation prefers a pure vertical answer. This is the
  -- exact motion the manual-camera control demonstrated and avoids replacing a
  -- trainer tableau with a Hero-style side portrait before send-out.
  local safe,mode=bcIntroWaitRoofSafeCamera(
      backend,arena,groundY,base,poseCamera,nil,true)
  if not safe and allowSide then
    safe,mode=bcIntroWaitRoofSafeCamera(
        backend,arena,groundY,base,poseCamera,nil,false)
  end
  if safe then
    state.intro.openingStructuralCamera=safe
    state.intro.openingStructuralMode=mode
  end
  return safe,mode
end

-- Structural Convergence RC9 -----------------------------------------------
-- True battle-opening semantics. RC8 deliberately stopped spending a Pokemon
-- passive token during the trainer tableau, which exposed the backend's real
-- native opening pan. Celadon proves that this is the right horizontal camera
-- language, but its own focus ray can run straight through a building roof.
-- Do not judge this phase with Pokemon player/enemy readability: they are not
-- the authored subjects yet. Preserve the backend eye X/Z, focus, FOV and pan
-- and lift ONLY Y to the first physically safe height whose OWN native focus
-- ray is no longer blocked by the owning building. Re-evaluate against the
-- current native eye every frame so the normal slow opening pan remains alive
-- instead of latching an obsolete world-space camera and creating a cross-map
-- zoom. The latest safe camera is still remembered only as the Hero Intro's
-- blend base.
function bcBattleOpeningRoofTrackRC9(backend,arena,groundY,base)
  if not (backend and type(arena)=="table" and type(arena.map)=="table"
      and not arena.discs and type(base)=="table" and type(base.eye)=="table"
      and type(base.focus)=="table") then return nil,nil end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return nil,nil end

  -- Opening ownership is keyed to the backend camera's own intended focus, not
  -- to Pokemon anchors that may not exist yet or may still be moving through
  -- send-out. If the focus is not building-blocked, leave the native opening
  -- completely untouched.
  local comp,roofTop=bcBuildingRoofFromViewRay40(cache,base.eye,base.focus)
  roofTop=tonumber(roofTop) or (comp and tonumber(comp.top) or nil)
  if not (comp and roofTop) then return nil,nil end

  local startY=math.max(tonumber(base.eye[2]) or 0,roofTop+5.0)
  for i=0,20 do
    local y=startY+i*2.0
    local candidateEye={base.eye[1],y,base.eye[3]}
    local hardEye=select(1,bcGeomWallPoint(cache,candidateEye[1],candidateEye[2],candidateEye[3]))
    if not hardEye then
      local focusBlocked=select(1,bcGeomViewBarrierLine(cache,candidateEye,base.focus))
      if not focusBlocked then
        return bcCopyCameraWithEye(base,candidateEye),roofTop
      end
    end
  end
  return nil,roofTop
end

-- Structural Convergence RC9 / retained RC7 fallback -----------------------
-- Shared passive presentation fallback.  RC6 proved the Hero-derived side lane
-- itself is valid on Celadon (INTRO_WAIT_SIDE becomes fully readable), but it
-- only became eligible once the Intro lifecycle had already been queued.  The
-- long roof/fascia curtain happens earlier while Stadium passive token 0:1 owns
-- the camera and passive readability has already exhausted every local answer:
-- vertical lift failed, local escape failed, and even the backend-safe base is
-- unreadable (PASSIVE_STRUCTURAL_BASE_UNREADABLE).
--
-- That state is already BC's strongest semantic proof that this authored
-- physical presentation cannot be made readable locally.  Promote the same
-- proven subject-side cinematic lane to a BC-level LAST RESORT for that token.
-- This is not Intro-specific behaviour, does not start Intro early, does not
-- special-case Celadon, and does not alter any hard-geometry decision.
--
-- The fallback is shot-bound: once a passive token needs this stronger
-- degradation, keep the cinematic lane for that token rather than flickering
-- between an unreadable authored/base eye and the readable substitute.
local function bcPassiveStructuralIntentBadAtEyeRC10(cache,arena,groundY,eye,intent)
  if not (cache and type(arena)=="table" and type(eye)=="table") then return false end
  local p=type(arena.player)=="table"
      and bcPassiveReadabilityEnvelope(cache,eye,arena.player,groundY) or nil
  local e=type(arena.enemy)=="table"
      and bcPassiveReadabilityEnvelope(cache,eye,arena.enemy,groundY) or nil
  local pStructural=p and (tonumber(p.structural) or 0)>=6
  local eStructural=e and (tonumber(e.structural) or 0)>=6
  if intent=="player" then return pStructural and true or false end
  if intent=="enemy" then return eStructural and true or false end
  if intent=="both" then return (pStructural or eStructural) and true or false end
  return false
end

function bcSharedPassiveStructuralCamera(backend,arena,groundY,base,poseCamera,intent,authoredCamera,preferredLane,motionElapsed)
  if intent~="player" and intent~="enemy" then return nil,nil,nil end
  local cache=bcGeomCacheFor(backend,arena.map)
  if not cache.supported then return nil,nil,nil end

  local roofCandidate,roofMode=bcIntroWaitRoofSafeCamera(
      backend,arena,groundY,base,poseCamera,nil,true)
  if roofCandidate and bcConvergenceIntentGoodRC1(
      cache,arena,groundY,roofCandidate.eye,intent) then
    state.geomDiag.sharedLaneRC9="roof"
    return roofCandidate,roofMode or "roof","roof"
  end

  if not poseCamera then return nil,nil,nil end
  local best=nil
  local reference=type(base)=="table" and type(base.eye)=="table" and base.eye or nil
  local authoredY=type(authoredCamera)=="table" and type(authoredCamera.eye)=="table"
      and tonumber(authoredCamera.eye[2]) or nil
  local laneOrder={"player","enemy"}
  if preferredLane=="player" or preferredLane=="enemy" then
    laneOrder=(preferredLane=="player") and {"player","enemy"} or {"enemy","player"}
  end
  local elapsed=math.max(0,tonumber(motionElapsed) or 0)

  for _,laneSide in ipairs(laneOrder) do
    for _,sampleT in ipairs({3.2,4.7,6.2}) do
      local candidate=select(1,dynamicIntroPose(
          arena,groundY,poseCamera,laneSide,sampleT,true))
      if type(candidate)=="table" and type(candidate.eye)=="table" then
        -- RC11: a building-side substitute must preserve the authored shot's
        -- vertical intent. RC10's DW3 0:3 cut used a Hero side lane at ~Y34
        -- even though the authored shoulder was already ~Y59, producing the
        -- remaining down/up 'bounce'.  Keep the safe side X/Z but never pull
        -- the replacement below the authored eye simply because Hero portrait
        -- geometry happens to be lower.
        if authoredY and candidate.eye[2]<authoredY then
          candidate=bcCopyCameraWithEye(candidate,
              {candidate.eye[1],authoredY,candidate.eye[3]})
        end

        -- RC11 subtle structural motion. Once a difficult shot has degraded to
        -- a shared side lane, do not leave it dead-static for the entire token.
        -- Drift a few degrees around the intended subject over ~10 seconds,
        -- keeping distance/height/focus intact and revalidating every frame.
        -- This is presentation motion only; it never tries to reproduce the
        -- impossible original camera path.
        local drift=math.min(1,elapsed/10.0)*math.rad(4.0)
        local dir=(laneSide=="player") and 1 or -1
        if drift>0 and type(candidate.focus)=="table" then
          local fx,fz=candidate.focus[1],candidate.focus[3]
          local ox=candidate.eye[1]-fx
          local oz=candidate.eye[3]-fz
          local ca,sa=math.cos(drift*dir),math.sin(drift*dir)
          candidate=bcCopyCameraWithEye(candidate,{
              fx+ox*ca-oz*sa,
              candidate.eye[2],
              fz+ox*sa+oz*ca,
          })
        end

        if bcPassiveEscapeInsideArena(arena,candidate.eye) then
          local hardEye=select(1,bcGeomWallPoint(
              cache,candidate.eye[1],candidate.eye[2],candidate.eye[3]))
          if not hardEye then
            local usable=bcWallViewUsable(cache,arena,groundY,candidate)
            local intentGood=bcConvergenceIntentGoodRC1(
                cache,arena,groundY,candidate.eye,intent)
            if usable and intentGood then
              local deviation=0
              if reference then
                local dx=(candidate.eye[1] or 0)-(reference[1] or 0)
                local dy=(candidate.eye[2] or 0)-(reference[2] or 0)
                local dz=(candidate.eye[3] or 0)-(reference[3] or 0)
                deviation=dx*dx+dy*dy+dz*dz
              end
              -- Once a lane has acquired, strongly prefer keeping the same
              -- physical side so the gentle drift cannot chatter across arena.
              if preferredLane and laneSide~=preferredLane then
                deviation=deviation+1000000
              end
              if not best or deviation<best.deviation then
                best={camera=candidate,lane=laneSide,deviation=deviation}
              end
            end
          end
        end
      end
    end
  end
  if best then
    state.geomDiag.sharedLaneRC9=best.lane
    return best.camera,"side",best.lane
  end
  state.geomDiag.sharedLaneRC9=nil
  return nil,nil,nil
end
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
    -- Secondary View Rebase 2: during BC's private Dramaless world render,
    -- return ONLY the authored secondary camera. Primary ownership is untouched.
    local probe=state.secondaryViewProbe
    if probe and probe.rendering and probe.backend==backend
        and type(probe.camera)=="table" then
      local cam=probe.camera
      return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},
        focus={cam.focus[1],cam.focus[2],cam.focus[3]},up={0,1,0},
        fov=cam.fov,curve=cam.curve or 0},probe.pitch or bcPitchForCamera(cam)
    end
    local rawBase,rawPitch=originalRig(arena,groundY,canonical)
    if canonical then return rawBase,rawPitch end

    state.rigSeen=true; state.noRig=0
    state.backendId=backend.id
    if state.apb then
      state.apb.arena=arena
      state.apb.groundY=groundY
      state.apb.backend=backend
    end

    -- Compatibility contract: when BC is enabled, Dramaless is normalized to
    -- the exact upstream camera geometry that all 0.7.3 choreography was tuned
    -- against. When BC is disabled, the fork's own camera is returned untouched.
    local base,pitch=rawBase,rawPitch
    if backend.id=="DRAMALESS_SHAPE" and enabled() then
      local normalized,normalizedPitch=
        drAmalessNormalizedBase(backend,arena,groundY,BattleCam,false)
      if normalized then base,pitch=normalized,normalizedPitch end
    end

    if type(base)~="table" then
      bcDiagRecordCamera(backend,arena,groundY,base,base)
      return base,pitch
    end

    -- EXTERNAL is a passive-phase yield, not a global BC disable. During an
    -- ordinary idle/menu battle view return the provider's own raw camera
    -- untouched. BC Hero / Send-In, Stadium Attack and Faint remain independent
    -- modules and can still claim their respective phases. Keep queued BC Hero
    -- ownership alive so the provider can hand cleanly into the configured Intro.
    local externalPassive=(selectedPreset()=="external")
    local externalIntroQueued=battleIntroOn() and not state.intro.active
        and (state.intro.pendingEnemy or state.intro.pendingPlayer)
    if externalPassive and not state.battleOpening.active
        and not state.intro.active and not state.attack.active
        and not state.faint.active and not externalIntroQueued then
      bcDiagRecordCamera(backend,arena,groundY,rawBase,rawBase)
      return rawBase,rawPitch
    end

    -- Preset/transition geometry sees the same upstream reference rig under
    -- Dramaless. RC6 needs this before the pending-Intro seam because the proven
    -- Hero side lane is now also a shared safe transition candidate.
    local poseCamera=bcPoseCamera(backend,BattleCam)

    -- RC9 true battle-opening presentation. RC8 correctly stopped Pokemon
    -- passive time during the trainer tableau, but then judged the opening with
    -- Pokemon readability and could expose/reacquire an unstable world-space
    -- camera. Keep the backend's native slow pan and focus as the authored
    -- opening language; when THAT focus is hidden by a building, track the same
    -- X/Z/focus and raise only Y to the minimum clear roof lane.
    if bcOpeningTrainerPhaseRC8() then
      local openingSafe,openingRoof=bcBattleOpeningRoofTrackRC9(
          backend,arena,groundY,base)
      if openingSafe then
        state.intro.openingStructuralCamera=openingSafe
        state.intro.openingStructuralMode="roof"
        state.intro.openingStructuralPitch=pitch
        -- RC12: the inter-Intro return point is the LAST proven trainer/opening
        -- composition before the first Pokemon Intro takes ownership, not the
        -- first safe frame seen at battle start.  RC11 froze the first safe
        -- opening frame; by the time Arbok's Intro ended that obsolete camera
        -- was a wide/white-space destination, so INTRO_CHAIN_HOME_HOLD merely
        -- flew back to the wrong "home".  While the trainer/opening phase is
        -- genuinely active, continuously refresh the return anchor from the
        -- same roof-safe backend composition that is actually being shown.
        -- startIntro() ends this phase, naturally freezing the final good frame.
        state.intro.openingChainCamera=bcCopyCameraWithEye(openingSafe,openingSafe.eye)
        state.intro.openingChainPitch=pitch
        state.intro.openingChainMode="roof"
        state.geomDiag.phaseHandoffRC3="BATTLE_OPENING_ROOF_TRACK"
        state.geomDiag.action="BATTLE_OPENING_ROOF_TRACK"
        state.geomDiag.structuralViewRoofTargetY=openingSafe.eye and openingSafe.eye[2] or nil
        bcDiagRecordCamera(backend,arena,groundY,openingSafe,base)
        return openingSafe,pitch
      end
    end

    -- RC4/RC6: a queued Hero intro owns the presentation contract even while its
    -- model/send-out lifecycle is still waiting. First try the local roof lane;
    -- if a broad roof still fills the view, RC6 may use the same generic side-lane
    -- geometry that the upcoming Hero Intro has already proved safe/readable.
    -- This does NOT start the Intro early.
    if battleIntroOn() and not state.intro.active
        and (state.intro.pendingEnemy or state.intro.pendingPlayer) then
      -- Phenac Test 7 wild handoff. The full opening already owns the enemy's
      -- encounter presentation, so once the player advances that prompt the
      -- waiting camera immediately adopts the exact START pose of the queued
      -- player Hero Intro. No timer is consumed and no actor visibility rule is
      -- bypassed; when the player model becomes visible, startIntro() acquires
      -- from this same camera rather than looking back at the wild opponent.
      if state.intro.openingBridgeActive and state.intro.initial
          and state.intro.pendingPlayer and not state.intro.pendingEnemy then
        state.intro.openingChainCamera,state.intro.openingChainPitch=
            dynamicIntroPose(arena,groundY,poseCamera,"player",0,true)
        state.passiveShotToken=nil
        state.passiveShotIntent=nil
        if type(state.intro.openingChainCamera)=="table"
            and type(state.intro.openingChainCamera.eye)=="table" then
          state.intro.openingChainCamera=bcApplyGeometrySafety(
              backend,arena,groundY,state.intro.openingChainCamera,base)
          state.intro.openingChainPitch=bcPitchForCamera(state.intro.openingChainCamera)
              or state.intro.openingChainPitch
          state.intro.openingChainMode="wild_player"
          state.intro.openingChainHold=true
          state.geomDiag.phaseHandoffRC3="WILD_PROMPT_TO_PLAYER_INTRO"
          bcDiagRecordCamera(backend,arena,groundY,state.intro.openingChainCamera,base)
          return state.intro.openingChainCamera,state.intro.openingChainPitch or pitch
        end
      end
      -- RC13 inter-Intro ownership. RC12 proved that a frozen trainer camera is
      -- the wrong object to return to after the enemy Pokemon Intro: the eye can
      -- be identical to the good opening eye while the backend has legitimately
      -- changed its focus/projection for the new "Arbok is out / Go Mewtwo"
      -- presentation, leaving the frozen camera aimed into white space.
      --
      -- Rejoin the backend's CURRENT inter-Intro composition instead, applying
      -- exactly the same generic roof-safe vertical tracking that fixed the true
      -- battle opening. This preserves the backend's current X/Z/focus/FOV and
      -- only raises Y when its own view is building-blocked. The latest result
      -- is also stored as the next Pokemon Intro's blend base.
      if state.intro.openingChainHold then
        local chain,chainRoof=bcBattleOpeningRoofTrackRC9(
            backend,arena,groundY,base)
        local chainMode="roof"
        if not chain then
          -- If the backend's current inter-Intro view is already structurally
          -- clear, it is itself the correct handoff camera. Do not force a stale
          -- absolute trainer anchor merely because an earlier roof was awkward.
          chain=base
          chainMode="native"
        end

        if type(chain)=="table" and type(chain.eye)=="table" then
          local cache=bcGeomCacheFor(backend,arena.map)
          local hardEye=cache.supported and
              select(1,bcGeomWallPoint(cache,chain.eye[1],chain.eye[2],chain.eye[3]))
          if not hardEye then
            state.intro.openingChainCamera=bcCopyCameraWithEye(chain,chain.eye)
            state.intro.openingChainPitch=pitch
            state.intro.openingChainMode=chainMode
            state.intro.openingStructuralCamera=state.intro.openingChainCamera
            state.intro.openingStructuralPitch=pitch
            state.intro.openingStructuralMode=chainMode
            state.geomDiag.phaseHandoffRC3=(chainMode=="roof")
                and "INTRO_CHAIN_RETURN_TRACK" or "INTRO_CHAIN_RETURN_NATIVE"
            state.geomDiag.action=state.geomDiag.phaseHandoffRC3
            state.geomDiag.structuralViewRoofTargetY=(chainMode=="roof")
                and chain.eye[2] or nil
            bcDiagRecordCamera(backend,arena,groundY,chain,base)
            return chain,pitch
          end
        end
      end

      local waitSafe,waitMode=bcOpeningStructuralCameraRC8(
          backend,arena,groundY,base,poseCamera,true)
      if waitSafe then
        if state.intro.openingStructuralPitch==nil then
          state.intro.openingStructuralPitch=pitch
        end
        state.geomDiag.phaseHandoffRC3=(waitMode=="side")
            and "INTRO_WAIT_SIDE" or "INTRO_WAIT_ROOF"
        state.geomDiag.action=state.geomDiag.phaseHandoffRC3
        bcDiagRecordCamera(backend,arena,groundY,waitSafe,base)
        return waitSafe,state.intro.openingStructuralPitch or bcPitchForCamera(waitSafe) or pitch
      end
    end

    -- RC12: no absolute "skip-home bridge".  RC11 proved that holding a stale
    -- opening camera after the final Pokemon Intro is cancelled can itself
    -- expose white/empty space.  cancelActiveIntro() now cuts directly to the
    -- selected passive camera when no initial Intro remains.  If the *other*
    -- initial Pokemon Intro is still pending, the ordinary inter-Intro return
    -- hold above remains authoritative.

    if state.blend<=0 then
      state.geomDiag.phaseHandoffRC3=nil
      bcDiagRecordCamera(backend,arena,groundY,base,base)
      return base,pitch
    end

    -- Preset math also sees the upstream reference rig under Dramaless. This
    -- prevents its fork-specific back/height changes from stretching BC radii,
    -- orbit heights, safety envelopes or optical framing.

    -- RC4 Intro entry base. startIntro() correctly resets blend to zero, but that
    -- means the opening frames of the Hero Intro normally interpolate from the
    -- backend-native camera. On Celadon that native camera is itself behind the
    -- roof, so RC3 still showed a brief roof curtain at Intro acquisition even
    -- though the authored Hero eye was already excellent. When the native base is
    -- a confirmed component-owned building curtain, use the same roof-safe waiting
    -- camera only as the *blend base* for the Intro ramp-in. The authored Hero eye,
    -- timing, focus language and send-out lifecycle remain unchanged.
    local introEntryBase=nil
    local introEntryPitch=nil
    if state.intro.active and (tonumber(state.intro.time) or 0)<2.6 then
      local entryMode=nil
      if state.intro.openingChainHold
          and type(state.intro.openingChainCamera)=="table"
          and type(state.intro.openingChainCamera.eye)=="table" then
        introEntryBase=state.intro.openingChainCamera
        introEntryPitch=state.intro.openingChainPitch or bcPitchForCamera(introEntryBase)
        entryMode=state.intro.openingChainMode or "roof"
      elseif type(state.intro.openingStructuralCamera)=="table"
          and type(state.intro.openingStructuralCamera.eye)=="table" then
        introEntryBase=state.intro.openingStructuralCamera
        introEntryPitch=state.intro.openingStructuralPitch
        entryMode=state.intro.openingStructuralMode or "roof"
      else
        introEntryBase,entryMode=bcIntroWaitRoofSafeCamera(
            backend,arena,groundY,base,poseCamera,state.intro.side)
        if introEntryBase then introEntryPitch=pitch end
      end
      if introEntryBase then
        state.geomDiag.phaseHandoffRC3=(entryMode=="side")
            and "INTRO_ENTRY_SIDE_BASE" or "INTRO_ENTRY_SAFE_BASE"
      end
    end

    local cine,cinePitch,shotWeight
    state.passiveShotToken=nil
    state.passiveShotIntent=nil
    local passivePreset,environmentFallback=passivePresetForArena(arena)
    -- Only describe the fallback as active while the passive preset owns the
    -- camera. Higher-priority intro/attack/faint modules are not replaced.
    if not state.faint.active and not state.attack.active
        and not state.battleOpening.active and not state.intro.active then
      state.environmentFallback=environmentFallback
    else
      state.environmentFallback=nil
    end
    -- Per-frame safety signal. Stadium-derived pose builders set this when a
    -- requested physical eye has to be shortened to fit a real A-stage map.
    -- Synthetic B stages deliberately never set it.
    state.stadiumMapBoundaryRisk=false
    state.geomDiag.boundary49=nil
    state.geomDiag.phaseHandoffRC3=nil

    -- Priority is intentionally additive: a confirmed faint owns the camera
    -- only after the move camera releases it, then an actual Stadium attack,
    -- then the established BC Hero intro, then the ordinary passive preset.
    -- Proven v0.7.3 intro/preset math remains intact.
    if state.faint.active then
      cine,cinePitch,shotWeight=faintCameraPose(arena,groundY,poseCamera)
    elseif state.attack.active then
      cine,cinePitch,shotWeight=stadiumAttackPose(arena,groundY,poseCamera)
    elseif state.battleOpening.active then
      cine,cinePitch,shotWeight=state.battleOpening.pose(arena,groundY,poseCamera)
    elseif state.intro.active then
      cine,cinePitch,shotWeight=dynamicIntroPose(arena,groundY,poseCamera)
    elseif passivePreset=="portrait_test" then
      cine,cinePitch,shotWeight=portraitTestPose(arena,groundY,poseCamera)
    elseif passivePreset=="stadium" then
      cine,cinePitch,shotWeight=stadiumClassicPose(arena,groundY,poseCamera)
      if state.active and state.intro.structuralHandoffNeeded then
        state.geomDiag.phaseHandoffRC3="INTRO_TO_PASSIVE_CUT"
        state.intro.structuralHandoffNeeded=false
      end
    else
      cine,cinePitch,shotWeight=cinematicPose(arena,groundY,poseCamera)
    end
    if not cine then
      bcDiagRecordCamera(backend,arena,groundY,base,base)
      return base,pitch
    end

    -- Preserve the preset's TRUE requested eye for diagnostics before
    -- wide/dead-zone safety can zero-travel-lock the physical camera.
    state.geomDiag.authoredEye=type(cine.eye)=="table"
      and {cine.eye[1],cine.eye[2],cine.eye[3]} or nil

    local stadiumDerived=state.attack.active or state.faint.active or
      ((not state.intro.active) and passivePreset=="stadium")
    local w=state.blend*(shotWeight or 1)

    -- RC3 phase-aware Intro exit. The Hero intro eye itself is already a proven
    -- safe composition. On building-heavy maps the old fade could physically
    -- interpolate from that safe eye toward a backend-native eye through a roof
    -- or facade. When that exact return path is structurally invalid, keep the
    -- intro's physical eye until the authored phase ends; the next passive shot
    -- begins as a camera cut instead of inventing a journey through the building.
    if state.intro.active and (tonumber(state.intro.time) or 0)>=6.8
        and bcIntroReturnCrossesBuilding(backend,arena,cine,base) then
      w=state.blend
      state.intro.structuralHandoffNeeded=true
      state.geomDiag.phaseHandoffRC3="INTRO_EXIT_HOLD"
    end

    -- Stadium map-boundary safety -----------------------------------------
    -- A requested Stadium shot can be geometrically valid yet exceed the
    -- physical space of a real A-stage map. The old clamp parked the eye on
    -- the map edge, which can be a hedge/wall/border voxel. When the map itself
    -- had to shorten a Stadium-derived eye, use the backend's already-proven
    -- native eye and preserve the intended composition optically instead.
    --
    -- This applies equally to Stadium Classic, Stadium Attack Camera and Faint
    -- Camera. Synthetic B stages are exempt because their carried map is not
    -- physical battle geometry.
    if stadiumDerived and state.stadiumMapBoundaryRisk and not (arena and arena.discs) then
      -- Modern Boundary Arbitration Test 49 -------------------------------
      -- v0.7.8's boundary fallback predates BC's mature semantic geometry
      -- stack. At the time, any Stadium eye shortened by the map rectangle had
      -- to be abandoned wholesale for the backend-native eye because BC could
      -- not reliably tell whether the pulled-in endpoint/path was physically
      -- usable. Test 48 now exposes the cost of keeping that old coarse rule:
      -- Power Plant's high Stadium circle remains authored at ~Y117 until its
      -- already-clamped X reaches the 12-unit map margin, then the wrapper
      -- swaps the entire physical eye to native X/Z; roof clearance can only
      -- raise that unrelated native eye to roof+margin, visually collapsing
      -- the high orbit. Celadon's opening shows the same native-eye signature.
      --
      -- Passive Stadium now lets the ALREADY map-clamped cinematic eye continue
      -- into the modern shared geometry stack. StadiumClassicPose has already
      -- pulled it inward along the authored ray and recomputed FOV from that
      -- final distance. Hard occupancy/path, building roof clearance, view
      -- arbitration and readability then decide whether the physical lane is
      -- actually supportable. This is not permission to leave the map.
      --
      -- Attack/Faint keep the proven conservative zero-travel boundary rule.
      -- And the separate narrow/dead-zone block below is deliberately left
      -- intact: Route 22/24-style unsafe rigs still zero-travel even for passive
      -- Stadium if cam/spacing says the renderer itself cannot support travel.
      local passiveStadium49=(not state.faint.active and not state.attack.active
          and not state.intro.active and passivePreset=="stadium")
      if passiveStadium49 then
        state.geomDiag.boundary49="PASSIVE_GEOM_VALIDATE"
        if diagnosticsOn() then
          logDiagnostic("stadium map-boundary pull-in -> shared geometry validation")
        end
        -- Fall through. Do NOT return here: the ordinary dead-zone check below
        -- must retain final authority on genuinely cramped renderer rigs.
      else
        state.geomDiag.boundary49="ZERO_TRAVEL"
        if diagnosticsOn() then
          logDiagnostic("stadium map-boundary fallback -> safe-eye optical framing")
        end
        local locked,lockedPitch=zeroTravelCamera(base,cine,w)
        local outPitch=lockedPitch or mix(pitch,cinePitch,w)
        locked=bcApplyGeometrySafety(backend,arena,groundY,locked,base)
        if not state.battleOpening.active and not state.intro.active
            and not state.attack.active and not state.faint.active
            and passivePreset~="external" then
          locked=state.applyIdleView(locked)
        end
        bcDiagRecordCamera(backend,arena,groundY,locked,base)
        return locked,outPitch
      end
    end

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
        local heroSafety=state.battleOpening.active or state.intro.active
            or passivePreset=="portrait_test"
        -- B-stage arenas are synthetic carried stages, not cramped map rigs.
        -- Across every supported backend using this arena contract, let passive
        -- Stadium Classic use its authored physical eye path instead of the
        -- Route 22/24 zero-travel fallback.
        local passiveStadium=((not state.intro.active) and passivePreset=="stadium")
        local stadiumSafety=state.attack.active or state.faint.active or
          (passiveStadium and not arena.discs)
        if heroSafety or stadiumSafety then
          local locked,lockedPitch=zeroTravelCamera(base,cine,w)
          local outPitch=lockedPitch or mix(pitch,cinePitch,w)
          locked=bcApplyGeometrySafety(backend,arena,groundY,locked,base)
          if not state.battleOpening.active and not state.intro.active
              and not state.attack.active and not state.faint.active
              and passivePreset~="external" then
            locked=state.applyIdleView(locked)
          end
          bcDiagRecordCamera(backend,arena,groundY,locked,base)
          return locked,outPitch
        end
      end
    end

    local blendBase=(state.intro.active and introEntryBase) or base
    local outCamera=mixCamera(blendBase,cine,w)
    local pitchBase=(state.intro.active and introEntryPitch) or pitch
    local outPitch=mix(pitchBase,cinePitch,w)
    outCamera=bcApplyGeometrySafety(backend,arena,groundY,outCamera,base)

    -- Structural Convergence RC10 ----------------------------------------
    -- Test21's most important lesson applies to a hard building fallback too:
    -- a new authored token is a CUT.  RC9's DW3 shoulder footage showed the
    -- remaining "bounce" was not a roof-height oscillation.  The new token was
    -- first abandoned to the backend/native eye, sat there behind component-owned
    -- roof/fascia for the four-frame readability debounce, and only THEN jumped
    -- to the already-proven shared side lane.  Visually: previous shot -> native
    -- roof curtain -> readable substitute, which looks exactly like a correction
    -- bounce and makes the authored rotation appear to vanish.
    --
    -- If hard safety has just yielded THIS token and its backend-safe base is
    -- itself structurally unreadable for the intended subject, skip that
    -- meaningless intermediate camera and cut directly to the validated shared
    -- roof/side substitute.  The physical authored shot is still gracefully
    -- degraded (Test38 remains authoritative); we simply no longer invent a
    -- one-second journey through a camera BC already knows cannot present the
    -- shot.  Later frames retain the same token latch and avoid the expensive
    -- repeated 3x3/lift/escape search.
    if not state.battleOpening.active and not state.intro.active
        and not state.attack.active and not state.faint.active
        and (passivePreset=="stadium" or passivePreset=="dw3")
        and state.passiveShotToken~=nil
        and (state.passiveShotIntent=="player" or state.passiveShotIntent=="enemy") then
      local g=state.geomDiag
      local token=state.passiveShotToken
      local immediateStructuralCut=false
      if g.hardFallbackAppliedThisFrame and type(outCamera)=="table"
          and type(outCamera.eye)=="table" and type(arena.map)=="table" then
        local cache=bcGeomCacheFor(backend,arena.map)
        if cache.supported then
          immediateStructuralCut=bcPassiveStructuralIntentBadAtEyeRC10(
              cache,arena,groundY,outCamera.eye,state.passiveShotIntent)
        end
      end

      local needsShared=(g.passiveCinematicFallbackToken==token)
          or (g.action=="PASSIVE_STRUCTURAL_BASE_UNREADABLE")
          or immediateStructuralCut
      if needsShared then
        local elapsed=0
        if g.passiveCinematicFallbackToken==token and g.passiveCinematicFallbackStartTime then
          elapsed=math.max(0,(tonumber(state.time) or 0)-(tonumber(g.passiveCinematicFallbackStartTime) or 0))
        end
        local shared,sharedMode,sharedLane=bcSharedPassiveStructuralCamera(
            backend,arena,groundY,base,poseCamera,state.passiveShotIntent,cine,
            g.passiveCinematicFallbackLane,elapsed)
        if shared then
          local newlyAcquired=(g.passiveCinematicFallbackToken~=token)
          g.passiveCinematicFallbackToken=token
          g.passiveCinematicFallbackMode=sharedMode
          if newlyAcquired then
            g.passiveCinematicFallbackStartTime=tonumber(state.time) or 0
          end
          if sharedLane and sharedLane~="roof" then
            g.passiveCinematicFallbackLane=sharedLane
          end
          if immediateStructuralCut then
            g.action=(sharedMode=="roof")
                and "PASSIVE_SHARED_ROOF_CUT" or "PASSIVE_SHARED_SIDE_CUT"
          elseif not newlyAcquired and sharedMode=="side" then
            g.action="PASSIVE_SHARED_SIDE_DRIFT"
          elseif not newlyAcquired and sharedMode=="roof" then
            g.action="PASSIVE_SHARED_ROOF_HOLD"
          else
            g.action=(sharedMode=="roof")
                and "PASSIVE_SHARED_ROOF_FALLBACK" or "PASSIVE_SHARED_SIDE_FALLBACK"
          end
          outCamera=shared
          outPitch=bcPitchForCamera(shared) or outPitch
        elseif g.passiveCinematicFallbackToken==token then
          -- Never keep a stale substitute if changing geometry invalidates it.
          g.passiveCinematicFallbackToken=nil
          g.passiveCinematicFallbackMode=nil
          g.passiveCinematicFallbackLane=nil
          g.passiveCinematicFallbackStartTime=nil
        end
      end
    end

    if not state.battleOpening.active and not state.intro.active
        and not state.attack.active and not state.faint.active
        and passivePreset~="external" then
      outCamera=state.applyIdleView(outCamera)
    end

    bcDiagRecordCamera(backend,arena,groundY,outCamera,base)
    return outCamera,outPitch
  end
  BattleCam.__bcStandaloneDW3Wrapped=true
  mod.log:info("camera backend connected: %s %s",backend.id,tostring(backend.version or ""))
  if backend.id=="DRAMALESS_SHAPE" then
    mod.log:info("Dramaless camera normalized to Battle Cinematics 0.7.3 reference geometry")
    mod.log:info("Dramaless actor-height framing normalization active")
  end
end

for _,backend in ipairs(backends) do installBackendCamera(backend) end

-- Secondary View / PiP -- v1.2.0 ------------------------------------------
-- Semantic port of the accepted v1.0.9 Probe13 capability. This rebase does
-- NOT broaden providers or redesign framing: Dramaless 2.0.3 owns the private
-- local-world pass; StadiumBattleFX's built-in/default live Stadium provider
-- can supply the already-live rigs. Animation is never advanced twice.
state.secondaryViewProbe.eligible=function(backend)
  local P=state.secondaryViewProbe
  if not (P and P.enabled and backend and backend.id=="DRAMALESS_SHAPE") then return false end
  -- Secondary View is independent of the selected idle preset. The current
  -- rebase still proves only the Dramaless live-world render seam; provider
  -- breadth is a later adapter task, not a product-level DW3 restriction.
  if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
  if not (state.battle and state.active) then return false end
  if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
  if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
  if state.attack and (state.attack.pending or state.attack.active) then return false end
  if state.faint and (state.faint.pending or state.faint.active) then return false end
  local b=state.battle
  if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
  return true
end

state.secondaryViewProbe.cameraFor=function(backend,arena,groundY,actorMode)
  if not (backend and arena and type(arena.player)=="table" and type(arena.enemy)=="table") then return nil,nil end
  local poseCamera=bcPoseCamera(backend,backend.BattleCam)
  local R=poseCamera and poseCamera.rigFor and poseCamera.rigFor(arena) or nil
  if type(R)~="table" then return nil,nil end
  local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
  local ex,ez=tonumber(arena.enemy[1]),tonumber(arena.enemy[2])
  if not (px and pz and ex and ez) then return nil,nil end
  local fx,fz=ex-px,ez-pz; local spacing=math.sqrt(fx*fx+fz*fz)
  if spacing<1e-4 then return nil,nil end
  fx,fz=fx/spacing,fz/spacing; local rx,rz=-fz,fx
  local actorScale=poseActorScale(R); local lift,minScale,bounds=0,nil,nil
  local A=state.apb
  -- Secondary View may deliberately use a different actor provider from the
  -- primary Dramaless world. Consume the same Importer -> APB semantic sensor
  -- directly in that case; ordinary primary-camera arbitration remains gated
  -- to whichever provider actually owns the live battle presentation.
  if actorMode=="stadium2_importer" and A
      and type(A.stadium2ImporterPresentationBounds)=="function"
      and type(A.cinematicFramingFromBounds)=="function" then
    local okBounds,value=pcall(A.stadium2ImporterPresentationBounds,"player",state.battle)
    if okBounds and type(value)=="table" then
      bounds=value
      lift,minScale=A.cinematicFramingFromBounds(bounds,R,1.30,R.lookY+5.45*actorScale)
    end
  end
  -- Gold Importer can supply the same APB record from its already-live actor
  -- when the installed provider predates exports.models API v2.
  if type(bounds)~="table" and actorMode=="stadium2_importer"
      and type(state.secondaryViewProbe._goldImporterBounds)=="table"
      and A and type(A.cinematicFramingFromBounds)=="function" then
    bounds=state.secondaryViewProbe._goldImporterBounds
    lift,minScale=A.cinematicFramingFromBounds(bounds,R,1.30,R.lookY+5.45*actorScale)
  end
  -- Rebase56: Dramatic Shape's independently-owned native Stadium actor
  -- supplies the same renderer-neutral posed-bounds semantic as every other
  -- genuine 3D Secondary View actor. No species camera rules.
  if type(bounds)~="table" and actorMode=="dramatic_stadium"
      and type(state.secondaryViewProbe._dramaticStadiumBounds)=="table"
      and A and type(A.cinematicFramingFromBounds)=="function" then
    bounds=state.secondaryViewProbe._dramaticStadiumBounds
    lift,minScale=A.cinematicFramingFromBounds(bounds,R,1.30,R.lookY+5.45*actorScale)
  end
  -- Rebase37: Battle Art 2D is deliberately normalized to the same canonical
  -- flat FRONT portrait contract as the proven Dramaless/Randy sprite paths.
  -- Do not let Battle Art's large MAIN-stage card/APB describe this separate
  -- portrait actor; that was the source of the quasi-Stadium framing seen in
  -- rejected Rebases34-35. Genuine 3D providers still consume shared APB.
  if actorMode~="battle_art_2d" and actorMode~="voxel_ascendant_2d"
      and actorMode~="potato_2d" and actorMode~="dramatic_2d"
      and type(bounds)~="table" and A and type(A.subjectFraming)=="function" then
    local fn=A.subjectFramingCinematic or A.subjectFraming
    lift,minScale,bounds=fn("player",R,1.30,R.lookY+5.45*actorScale)
  end
  local gy=tonumber(groundY) or 0
  local focusY=gy+R.lookY+5.35*actorScale+(tonumber(lift) or 0)
  -- Rebase22 vertical semantic-focus probe. Probe13's fixed 79% upper-segment
  -- target works well for compact/upright portraits but over-assumes that the
  -- useful subject area of every very large or broad presentation lives near
  -- the top of its APB. Keep 79% for ordinary actors; only blend downward for
  -- actors that are extreme in presented height, or both broad and large.
  -- This is renderer-neutral APB composition: no species, model or anatomy
  -- knowledge is used, and it does not claim that the resulting point is a head.
  if type(bounds)=="table" then
    local bottom=tonumber(bounds.visualBottomY)
    local top=tonumber(bounds.visualTopY)
    local height=tonumber(bounds.height)
    if bottom and top and height and height>1e-3 then
      local frameH=math.max(1e-3,tonumber(R.frameH) or 34.11)
      local heightRel=height/frameH
      local breadthRatio=math.max(0,tonumber(bounds.breadthHeightRatio) or 0)

      local function sat(v) return math.max(0,math.min(1,v)) end
      -- Imported Stadium presentations normally occupy roughly 0.2..0.53 of
      -- the authored frame height. Only the upper end of that range counts as
      -- genuinely large; this protects Mewtwo/Pidgeotto/Squirtle-like portraits.
      local large=sat((heightRel-0.34)/0.18)
      local broad=sat((breadthRatio-0.95)/0.90)
      local extremeTall=sat((heightRel-0.46)/0.08)
      local semanticPressure=math.max(broad*large,extremeTall*0.68)

      -- Ordinary portraits remain at Probe13's 79%. Extreme geometry may blend
      -- smoothly toward 60%, i.e. upper-middle rather than geometric top.
      local focusFrac=0.79-0.19*semanticPressure
      local semanticY=bottom+height*focusFrac
      focusY=math.max(focusY,gy+semanticY)
    end
  end
  -- LEFT/RIGHT remain genuine authored arena-side cameras, independent from
  -- main-battle SPRITE FACING. Rebase 18 corrects their semantic polarity: the
  -- saved LEFT value now resolves to the actual left side of the battle axis,
  -- and RIGHT to the actual right. The accepted Rebase 17 three-quarter grammar
  -- remains otherwise unchanged: instead of an exact 90-degree profile, the camera
  -- looks inward from 60 degrees off the player->enemy battle axis and breathes
  -- slowly within a narrow 52..68 degree wedge. It never crosses centre or the
  -- opposite side. Flat sprites keep the already-accepted shallow 90-degree pan
  -- so this test changes only genuine 3D Secondary View composition.
  local secondarySide=mod.options:get("secondaryViewSide") or "left"
  local sideSign=(secondarySide=="left") and -1 or 1
  local is3D=(actorMode=="stadium2_importer" or actorMode=="sbfx"
      or actorMode=="randy_stadium2" or actorMode=="dramatic_stadium")
  local baseArc=math.rad(is3D and 60.0 or 90.0)*sideSign
  local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
  local sway
  if is3D then
    sway=math.sin(now*0.30)*math.rad(8.0)*sideSign
  else
    sway=math.sin(now*0.42)*math.rad(6.0)*sideSign
  end
  local arc=baseArc+sway
  local radius=math.max(9.0,math.min(13.5,spacing*0.24))
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local elevation=math.rad(10.0)
  local focusLead=math.max(0.20,math.min(0.85,spacing*0.05))
  local focus={px+fx*focusLead,focusY,pz+fz*focusLead}
  -- Rebase 23: freeze Rebase22 NORMAL portrait composition exactly and add
  -- one authored CLOSE preference. CLOSE changes only the starting optical
  -- frame scale; the same projected-width, vertical portrait-fit and semantic
  -- focus protections remain in force, so extreme shapes can still pull back.
  local pipFraming=mod.options:get("secondaryViewFraming") or "normal"
  local frameScale=(pipFraming=="close") and 0.17 or 0.18
  local frame=(tonumber(R.frameH) or 34.11)*frameScale

  local function eyeForRadius(r)
    local flat=r*math.cos(elevation)
    return {px+dx*flat,focusY+r*math.sin(elevation),pz+dz*flat}
  end
  local eye=eyeForRadius(radius)
  local dist=math.sqrt((eye[1]-focus[1])^2+(eye[2]-focus[2])^2+(eye[3]-focus[3])^2)
  local fov=2*math.atan((frame*0.5)/math.max(1,dist)); fov=math.max(math.rad(18),math.min(math.rad(40),fov))

  -- Rebase 21 optical-fit pass 3: preserve generic projected-breadth and
  -- vertical safety, but redefine them as PORTRAIT limits rather than full-body
  -- fit. Wide/long actors may crop at the edges and tall actors need only keep
  -- a useful ~42% vertical window. This spends the small PiP on the actor rather
  -- than empty arena while retaining generic escape room for extreme shapes.
  -- Rebase21 occupancy limits remain frozen. Rebase22 changes only the APB
  -- vertical focus target above; optical fit/zoom stays bit-for-bit otherwise.
  if is3D and type(bounds)=="table" then
    local pipAspect=16/9
    local tanHalf=math.max(1e-4,math.tan(fov*0.5))
    local requiredDist=dist

    local sx=math.abs(tonumber(bounds.spanX) or 0)
    local sz=math.abs(tonumber(bounds.spanZ) or 0)
    local projected=nil
    if sx>1e-3 or sz>1e-3 then
      projected=sx*math.abs(math.cos(arc))+sz*math.abs(math.sin(arc))
    else
      projected=math.abs(tonumber(bounds.breadth) or 0)
    end
    if projected and projected>1e-3 then
      local requiredHorizontal=projected*0.92
      local horizontalDist=(requiredHorizontal/pipAspect)*0.5/tanHalf
      requiredDist=math.max(requiredDist,horizontalDist)
    end

    local presentedHeight=math.abs(tonumber(bounds.height) or 0)
    if presentedHeight>1e-3 then
      -- A portrait is allowed to crop aggressively. Keeping roughly two-fifths of
      -- total posed height available prevents catastrophic one-segment views while
      -- letting ordinary subjects occupy the viewport like the DW3 reference.
      local requiredVertical=presentedHeight*0.42
      local verticalDist=requiredVertical*0.5/tanHalf
      requiredDist=math.max(requiredDist,verticalDist)
    end

    if requiredDist>dist+0.05 then
      local ratio=requiredDist/math.max(1e-3,dist)
      radius=math.min(22.0,radius*math.max(1.0,ratio))
      eye=eyeForRadius(radius)
      dist=math.sqrt((eye[1]-focus[1])^2+(eye[2]-focus[2])^2+(eye[3]-focus[3])^2)
    end
  end
  local cam={eye=eye,focus=focus,up={0,1,0},fov=fov,curve=0}; cam=state.floorProtectCamera(cam,groundY)
  return cam,bcPitchForCamera(cam)
end

state.secondaryViewProbe.clear=function()
  local P=state.secondaryViewProbe
  P.shot=nil; P.camera=nil; P.pitch=nil; P.rendering=false; P.accum=0
  if P.s2Instance and type(P.s2Instance.release)=="function" then
    pcall(P.s2Instance.release,P.s2Instance)
  end
  P.s2Instance=nil; P.s2Identity=nil; P.s2Metrics=nil; P.s2LastTime=nil

  -- Rebase38 Battle Art + Importer uses an independently-owned public
  -- presentation Actor. It belongs to Secondary View and must be released
  -- explicitly; unlike Gold Importer below it is NOT borrowed from a live scene.
  if P.battleArtImporterActor and type(P.battleArtImporterActor.release)=="function" then
    pcall(P.battleArtImporterActor.release,P.battleArtImporterActor)
  end
  P.battleArtImporterActor=nil
  P.battleArtImporterMon=nil
  P.battleArtImporterLastTime=nil
  P.battleArtImporterFailure=nil

  -- Rebase53 Potato + Stadium2 Importer uses the same independently-owned
  -- public presentation Actor contract as accepted Battle Art/Ascendant.
  if P.potatoImporterActor and type(P.potatoImporterActor.release)=="function" then
    pcall(P.potatoImporterActor.release,P.potatoImporterActor)
  end
  P.potatoImporterActor=nil
  P.potatoImporterMon=nil
  P.potatoImporterLastTime=nil
  P.potatoImporterFailure=nil

  -- Rebase56 base Dramatic private actors are independently owned by Secondary View.
  if P.dramaticImporterActor and type(P.dramaticImporterActor.release)=="function" then
    pcall(P.dramaticImporterActor.release,P.dramaticImporterActor)
  end
  P.dramaticImporterActor=nil; P.dramaticImporterMon=nil; P.dramaticImporterLastTime=nil; P.dramaticImporterFailure=nil
  if P.dramaticNativeActor and type(P.dramaticNativeActor.release)=="function" then
    pcall(P.dramaticNativeActor.release,P.dramaticNativeActor)
  end
  P.dramaticNativeActor=nil; P.dramaticNativeDex=nil; P.dramaticNativeLastTime=nil; P.dramaticNativeFailure=nil
  P._dramaticStadiumBounds=nil

  -- Rebase45 Voxel Ascendant + Importer uses a second independently-owned
  -- presentation Actor plus one transparent depth-backed actor layer. Neither
  -- belongs to Ascendant or the Importer's live main battle and both are BC's
  -- responsibility to release.
  if P.voxelAscendantImporterActor and type(P.voxelAscendantImporterActor.release)=="function" then
    pcall(P.voxelAscendantImporterActor.release,P.voxelAscendantImporterActor)
  end
  P.voxelAscendantImporterActor=nil
  P.voxelAscendantImporterMon=nil
  P.voxelAscendantImporterLastTime=nil
  P.voxelAscendantImporterFailure=nil
  for _,v in ipairs({P.voxelAscendantImporterCanvas,P.voxelAscendantImporterDepth}) do
    if v and type(v.release)=="function" then pcall(v.release,v) end
  end
  P.voxelAscendantImporterCanvas=nil
  P.voxelAscendantImporterDepth=nil
  P.voxelAscendantImporterRW=nil
  P.voxelAscendantImporterRH=nil

  -- Rebase24 Gold/Importer secondary scene owns only its render targets.
  -- Its actor is borrowed read-only from the provider's live scene and must
  -- never be released by BC.
  local scene=P.goldImporterSecondaryScene
  if type(scene)=="table" then
    for _,v in ipairs({scene.canvas,scene.depth,scene.presentCanvas,scene.compositeCanvas}) do
      if v and type(v.release)=="function" then pcall(v.release,v) end
    end
    scene.canvas,scene.depth,scene.presentCanvas,scene.compositeCanvas=nil,nil,nil,nil
  end
  P.goldImporterSecondaryScene=nil
end

state.secondaryViewProbe.install=function()
  local P=state.secondaryViewProbe; P.status="Dramaless secondary-world seam scan"; P.failure=nil
  for _,backend in ipairs(backends) do if backend.id=="DRAMALESS_SHAPE" then
    P.backend=backend; P.diagVersion=tostring(backend.version or "?"); P.diagV=backend.V and type(backend.V.require)=="function"
    local handle=mod.find("DRAMALESS_SHAPE"); local exports=handle and handle.exports or nil
    P.arenaProvider=exports and exports.voxelArenaProvider or nil
    P.cardProvider=exports and exports.voxelCardProvider or nil
    if P.diagV then
      local okS,S=pcall(backend.V.require,"VoxelBattleScene"); local okV,V3=pcall(backend.V.require,"Voxel3D"); local okA,AA=pcall(backend.V.require,"AntiAlias")
      P.Scene=(okS and type(S)=="table" and type(S.render)=="function") and S or nil; P.Voxel3D=(okV and type(V3)=="table") and V3 or nil; P.AntiAlias=(okA and type(AA)=="table") and AA or nil
    end
    -- Stadium2 Importer is the maintained first-class Stadium actor source.
    -- Its models API v2 is explicitly scene-neutral: BC can create its own
    -- independently-owned player instance and draw it into the caller-bound
    -- Dramaless world/depth target without taking over Importer's battle stage.
    local s2=mod.find("STADIUM2_IMPORTER"); local s2x=s2 and s2.exports or nil
    P.s2Exports=s2x; P.s2Models=s2x and s2x.models or nil
    P.s2Version=tostring((s2x and s2x.version) or "?")
    local s2caps=nil
    if type(P.s2Models)=="table" and type(P.s2Models.capabilities)=="function" then
      local okCaps,value=pcall(P.s2Models.capabilities)
      if okCaps and type(value)=="table" then s2caps=value end
    end
    P.s2Capabilities=s2caps
    P.diagS2=type(P.s2Models)=="table" and tonumber(P.s2Models.apiVersion)>=2
      and type(P.s2Models.newInstance)=="function"
      and (not s2caps or s2caps.sceneNeutralDraw==true)

    -- SBFX remains a legacy compatibility source only. It is no longer the
    -- definition or first choice of Secondary View actor presentation.
    local sb=mod.find("STADIUM_BATTLE_FX"); local sx=sb and sb.exports or nil
    P.sbfxVersion=tostring((sx and sx.version) or "?")
    P.battles=sx and sx.battles or nil; P.modelProvider=sx and sx.modelProvider or nil; P.modelsApi=sx and sx.models or nil
    P.diagScene=P.Scene and true or false; P.diagV3=P.Voxel3D and true or false; P.diagAA=P.AntiAlias and true or false
    P.diagArena=type(P.arenaProvider)=="table"
    P.diagCard=type(P.cardProvider)=="table" and type(P.cardProvider.drawWorld)=="function"
    P.diagSB=type(P.battles)=="table" and P.battles.version==1
    P.diagMP=type(P.modelProvider)=="table" and type(P.modelProvider.drawWorld)=="function"
    P.diagMA=type(P.modelsApi)=="table" and P.modelsApi.version==1 and type(P.modelsApi.withRenderer)=="function"
    -- Secondary View requires only the world seam. Actor presentation resolves
    -- every frame in provider order: Stadium2 Importer scene-neutral model,
    -- legacy live SBFX model when genuinely available, then renderer-owned 2D.
    P.installed=P.diagScene and P.diagV3 and P.diagAA and P.diagArena
    P.failure=P.installed and nil or (("world gate SC:%s V3:%s AA:%s AR:%s"):format(P.diagScene and "Y" or "N",P.diagV3 and "Y" or "N",P.diagAA and "Y" or "N",P.diagArena and "Y" or "N"))
    if P.installed then mod.log:warn("[SECONDARY VIEW] Dramaless secondary-world seam armed; actor provider resolves per frame") end
    break
  end end
end

-- Scene-neutral Stadium2 Importer actor bridge --------------------------------
-- Keep all instance ownership on Secondary View state to avoid chunk-local
-- pressure and to make teardown explicit. This bridge consumes only public
-- STADIUM2_IMPORTER exports.models API v2 capabilities.
state.secondaryViewProbe.resolveS2Actor=function()
  local P=state.secondaryViewProbe
  local api=P and P.s2Models or nil
  if not (P and P.diagS2 and type(api)=="table") then return false end
  if P.s2Exports and type(P.s2Exports.modelsEnabled)=="function" then
    local okEnabled,value=pcall(P.s2Exports.modelsEnabled)
    if okEnabled and value==false then return false end
  end
  local battle=state.battle
  local battler=battle and battle.player or nil
  local mon=battler and battler.mon or nil
  if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
  if type(mon)~="table" then return false end

  local species=mon.species
  local dex=nil
  if type(species)=="number" then
    local n=math.floor(species); if n>=1 and n<=251 then dex=n end
  end
  if not dex and battle and battle.data and battle.data.pokemon and species~=nil then
    local def=battle.data.pokemon[species]
    local n=def and tonumber(def.dex or def.index) or nil
    if n then n=math.floor(n); if n>=1 and n<=251 then dex=n end end
  end
  if not dex then return false end

  local shiny=mon.shiny==true
  if mon.shiny==nil and type(mon.dvs)=="table" then
    local d=mon.dvs
    local atk=tonumber(d.attack)
    local shinyAtk=atk==2 or atk==3 or atk==6 or atk==7 or atk==10 or atk==11 or atk==14 or atk==15
    shiny=(tonumber(d.defense)==10 and tonumber(d.speed)==10 and tonumber(d.special)==10 and shinyAtk) and true or false
  end
  local variant=shiny and "shiny" or "normal"
  local identity=tostring(dex)..":"..variant
  if P.s2Instance and P.s2Identity==identity then return true end

  if P.s2Instance and type(P.s2Instance.release)=="function" then pcall(P.s2Instance.release,P.s2Instance) end
  P.s2Instance=nil; P.s2Identity=nil; P.s2Metrics=nil; P.s2LastTime=nil
  local okNew,instance,err=pcall(api.newInstance,dex,variant,{textureFilter="nearest",anchorTravel=true})
  if not okNew then P.s2Failure="newInstance error: "..tostring(instance); return false end
  if not instance then P.s2Failure="newInstance rejected: "..tostring(err); return false end
  P.s2Instance=instance; P.s2Identity=identity; P.s2Failure=nil
  if type(instance.play)=="function" then pcall(instance.play,instance,"idle",true) end
  if type(instance.metrics)=="function" then
    local okMetrics,value=pcall(instance.metrics,instance)
    if okMetrics and type(value)=="table" then P.s2Metrics=value end
  end
  return true
end

state.secondaryViewProbe.drawS2Actor=function(view,arena,groundY,cam)
  local P=state.secondaryViewProbe
  local api=P and P.s2Models or nil
  local instance=P and P.s2Instance or nil
  if not (api and instance and view and type(view.vp)=="table" and arena
      and type(arena.player)=="table" and type(arena.enemy)=="table") then return false end

  local metrics=P.s2Metrics
  if not metrics and type(instance.metrics)=="function" then
    local okMetrics,value=pcall(instance.metrics,instance)
    if okMetrics and type(value)=="table" then metrics=value; P.s2Metrics=value end
  end
  local height=metrics and tonumber(metrics.height) or nil
  if not (height and height>1e-4) then P.s2Failure="model metrics unavailable"; return false end

  -- Match Importer's own classic-stage physical scaling contract rather than
  -- inventing BC species sizes: model height maps generically into a 5..18
  -- world-unit envelope, then its real model floor is grounded to the voxel map.
  local worldHeight=math.max(5,math.min(18,14*math.sqrt(height/52.25)))
  local k=worldHeight/height
  local floor=tonumber(metrics.floor) or 0
  -- Preserve Importer's own classic-scene grounding/hover transform. This is
  -- generic authored model metadata, not a species exception: positive model
  -- floor can represent an intentionally elevated presentation (Pidgeotto is
  -- exactly the kind of actor APB needs to distinguish from grounded models).
  local hover=math.min(math.max(floor,0),height*0.5)
  local px,pz=tonumber(arena.player[1]) or 0,tonumber(arena.player[2]) or 0
  local ex,ez=tonumber(arena.enemy[1]) or 0,tonumber(arena.enemy[2]) or 0
  local yaw=math.atan2(ex-px,ez-pz)
  local matrixApi=api.matrix or api.matrices
  if not (type(matrixApi)=="table" and type(matrixApi.transform)=="function") then
    P.s2Failure="model matrix API unavailable"; return false
  end
  local okMatrix,modelMatrix=pcall(matrixApi.transform,{
    position={px,(tonumber(groundY) or 0)-(floor-hover)*k,pz},
    rotation={0,yaw,0}, scale=k,
  })
  if not (okMatrix and type(modelMatrix)=="table") then
    P.s2Failure="model transform failed: "..tostring(modelMatrix); return false
  end

  -- Advance this independently-owned idle actor from presentation time only.
  local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
  local dt=P.s2LastTime and (now-P.s2LastTime) or 0.10
  P.s2LastTime=now
  dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10))
  if type(instance.update)=="function" then pcall(instance.update,instance,dt) end

  local viewMatrix=view.view
  if type(viewMatrix)~="table" and cam and type(matrixApi.lookAt)=="function" then
    local okView,value=pcall(matrixApi.lookAt,cam.eye,cam.focus,cam.up or {0,1,0})
    if okView and type(value)=="table" then viewMatrix=value end
  end
  local okDraw,a,b=pcall(instance.draw,instance,{
    modelMatrix=modelMatrix,
    camera={viewProjection=view.vp,view=viewMatrix},
    disableCulling=true,
  })
  if not okDraw then P.s2Failure="model draw error: "..tostring(a); return false end
  if a==false then P.s2Failure="model draw rejected: "..tostring(b); return false end
  P.s2Failure=nil
  return true
end

state.secondaryViewProbe.install()

-- Gold/Silver Stadium2 Importer Secondary View ------------------------------
-- Rebase24 broadens only the renderer/provider seam. The accepted Rebase22/23
-- compositor remains one shared camera language. On Gold the Importer already
-- owns a complete live Stadium scene; BC borrows its live PLAYER actor
-- read-only and redraws that actor into a private Importer Scene using an
-- independent camera. No animation step is performed here, so the provider
-- remains the sole animation owner.
state.secondaryViewProbe.goldImporterContext=function()
  local P=state.secondaryViewProbe
  local gold=backends.__gold
  if not (P and gold and gold.providerKind=="stadium2_importer"
      and gold.battleLive and type(gold.scene)=="table"
      and type(gold.scene.actors)=="table") then return nil end
  local scene=gold.scene
  local screen=scene.screen
  local actor=scene.actors.player
  if not (type(screen)=="table" and type(actor)=="table" and actor.renderer) then return nil end
  return gold,scene,screen,actor
end

state.secondaryViewProbe.goldImporterEligible=function()
  local P=state.secondaryViewProbe
  local gold,scene,screen=P.goldImporterContext()
  if not gold then return false end
  if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
  if not (state.battle and state.active) then return false end
  if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
  if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
  if state.attack and (state.attack.pending or state.attack.active) then return false end
  if state.faint and (state.faint.pending or state.faint.active) then return false end
  local b=state.battle
  if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
  -- Preserve the accepted "no PiP under menu ownership" rule on Gold.
  -- Gold's ordinary command menu is the passive/idle presentation window and
  -- must remain PiP-visible. Only actual subordinate ownership screens suppress
  -- Secondary View here, matching the accepted Gen1 lifecycle semantics.
  if screen.phase=="party" or screen.phase=="item" then return false end
  return true
end

state.secondaryViewProbe.goldImporterLiveBounds=function()
  local P=state.secondaryViewProbe
  local gold,scene,screen,actor=P.goldImporterContext()
  if not (gold and actor and actor.renderer
      and type(actor.renderer.poseBounds)=="function"
      and type(actor.renderer.worldMetrics)=="function") then return nil end
  local okB,b=pcall(actor.renderer.poseBounds,actor.renderer)
  local okM,m=pcall(actor.renderer.worldMetrics,actor.renderer)
  if not (okB and okM and type(b)=="table" and type(m)=="table") then return nil end

  local minX,maxX=tonumber(b.minX),tonumber(b.maxX)
  local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
  local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ)
  local modelH=tonumber(m.height)
  if not (minX and maxX and minY and maxY and minZ and maxZ
      and modelH and modelH>1e-4 and maxY>minY) then return nil end

  -- Exact Importer classic-scene presentation transform: normalized world
  -- height plus authored floor/hover. This is the live-reader fallback for
  -- Importer builds that do not expose the later scene-neutral models API.
  local worldH=math.max(5,math.min(18,14*math.sqrt(modelH/52.25)))
  local k=worldH/modelH
  local floor=tonumber(m.floor) or 0
  local hover=math.min(math.max(floor,0),modelH*0.5)
  local offset=floor-hover
  local bottom=(minY-offset)*k
  local top=(maxY-offset)*k
  local height=top-bottom
  if height<=1e-3 then return nil end
  local spanX=math.max(0,(maxX-minX)*k)
  local spanZ=math.max(0,(maxZ-minZ)*k)
  local breadth=math.sqrt(spanX*spanX+spanZ*spanZ)
  local elevation=math.max(0,bottom)
  local elevationNorm=elevation/height
  if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
  return {
    visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,
    breadth=breadth,spanX=spanX,spanZ=spanZ,
    breadthHeightRatio=breadth/math.max(1e-3,height),
    elevation=elevation,elevationNorm=elevationNorm,
    source="STADIUM2_IMPORTER_GOLD_LIVE_POSED_V1",confidence="medium",
  }
end

state.secondaryViewProbe.renderGoldImporterFrame=function()
  local P=state.secondaryViewProbe
  if not P.goldImporterEligible() then P.shot=nil; return end
  local gold,liveScene,screen,actor=P.goldImporterContext()
  if not gold then P.shot=nil; return end

  local presentation=gold.presentation
  local Scene=presentation and presentation.Scene or nil
  local Camera=gold.Camera
  local okR,Renderer=pcall(require,"mods.STADIUM2_IMPORTER.lib.renderer")
  if not (type(Scene)=="table" and type(Scene.new)=="function"
      and type(Camera)=="table" and type(Camera.frame)=="function"
      and okR and type(Renderer)=="table" and type(Renderer.lookAt)=="function"
      and type(Renderer.perspective)=="function" and type(Renderer.matMul)=="function") then
    P.shot=nil; P.failure="Gold Stadium2 Importer secondary render API unavailable"; return
  end

  local cam,pitch=P.cameraFor(gold.backend,gold.arena,0,"stadium2_importer")
  if not cam then P.shot=nil; P.failure="Gold Stadium2 Importer portrait camera unavailable"; return end

  -- If the later scene-neutral APB API is absent, cameraFor can still consume
  -- the exact live provider pose through this temporary shared semantic record.
  -- Do not mutate the registry or primary camera adapter.
  local oldLive=P._goldImporterBounds
  P._goldImporterBounds=P.goldImporterLiveBounds()
  cam,pitch=P.cameraFor(gold.backend,gold.arena,0,"stadium2_importer")
  P._goldImporterBounds=oldLive
  if not cam then P.shot=nil; P.failure="Gold Stadium2 Importer portrait solve failed"; return end

  local secondary=P.goldImporterSecondaryScene
  if type(secondary)~="table" then
    local okNew,value=pcall(Scene.new,{actors={player=actor},label="BC Secondary View"})
    if not (okNew and type(value)=="table") then
      P.shot=nil; P.failure="Gold Stadium2 Importer secondary scene create failed: "..tostring(value); return
    end
    secondary=value
    P.goldImporterSecondaryScene=secondary
  end
  secondary.actors=secondary.actors or {}
  secondary.actors.player=actor
  secondary.actors.enemy=nil
  secondary.screen=screen
  secondary.game=screen.game

  local g=love and love.graphics
  local sw=(g and g.getWidth and g.getWidth()) or 1280
  local sh=(g and g.getHeight and g.getHeight()) or 720
  local sizeMode=mod.options:get("secondaryViewSize") or "small"
  local frac=(sizeMode=="small") and 0.20 or 0.27
  local minW=(sizeMode=="small") and 132 or 180
  local rw=math.max(minW,math.floor(sw*frac))
  local rh=math.max(1,math.floor(math.min(sh*0.34,rw*9/16)))

  local originalFrame=Camera.frame
  local LOVE_CANVAS_Y={1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1}
  local function secondaryFrame(width,height)
    width=math.max(1,tonumber(width) or rw)
    height=math.max(1,tonumber(height) or rh)
    local e,f=cam.eye,cam.focus
    local view=Renderer.lookAt(e[1],e[2],e[3],f[1],f[2],f[3])
    local projection=Renderer.matMul(LOVE_CANVAS_Y,
      Renderer.perspective(tonumber(cam.fov) or math.rad(35),width/height,.1,1000))
    local fit=(type(Camera.fitScale)=="function") and Camera.fitScale(width,height) or 1
    local ox,oy=0,0
    if type(Camera.fitOrigin)=="function" then ox,oy=Camera.fitOrigin(width,height,fit) end
    return {
      view=view,projection=projection,vp=Renderer.matMul(projection,view),
      eye={e[1],e[2],e[3]},focus={f[1],f[2],f[3]},
      letterbox={lx=ox,ly=oy,scale=fit,pw=width,ph=height},
    }
  end

  -- Scene:render only redraws. It does not step the borrowed live actor.
  -- Restore both the provider camera function and actor dynamic-object slot even
  -- if rendering fails.
  local oldDynamic=actor.dynamicObjectIndex
  Camera.frame=secondaryFrame
  P.rendering=true
  local okRender,value=pcall(secondary.render,secondary,rw,rh)
  P.rendering=false
  Camera.frame=originalFrame
  actor.dynamicObjectIndex=oldDynamic

  local canvas=secondary.presentCanvas or secondary.canvas
  if okRender and value and canvas then
    P.shot={canvas=canvas}; P.failure=nil; P.frames=(P.frames or 0)+1
    P.actorMode="stadium2_importer_gold_live"
  else
    P.shot=nil
    P.failure=okRender and ("Gold Stadium2 Importer secondary render returned "..tostring(value))
      or ("Gold Stadium2 Importer secondary render error: "..tostring(value))
  end
end

-- Gold/Silver STADIUM2_OVERWORLD_MODELS / Randy Secondary View ------------
-- Rebase27 reuses Randy's own alternate-eye/VR world pass. The provider keeps
-- the live world, model/card animation clock and ordinary camera/right-stick
-- ownership. BC supplies only an independent portrait camera and asks the
-- existing scene to redraw read-only presentation state at the conservative
-- Secondary View cadence.
state.secondaryViewProbe.randyContext=function()
  local P=state.secondaryViewProbe
  local gold=backends.__gold
  if not (P and gold and gold.battleLive and gold.backend
      and gold.backend.id=="BC_GOLD_RANDY"
      and gold.OverworldBattle and type(gold.OverworldBattle.cameraContext)=="function"
      and gold.V and gold.V.game and gold.V.game.world) then return nil end
  local ok,ctx=pcall(gold.OverworldBattle.cameraContext)
  if not (ok and type(ctx)=="table" and type(ctx.arena)=="table"
      and type(ctx.screen)=="table") then return nil end
  return gold,ctx,ctx.screen,gold.V.game.world
end

state.secondaryViewProbe.randyRenderState=function(gold,world)
  local P=state.secondaryViewProbe
  local V=gold and gold.V or nil
  local adapt=V and V.goldStateForWorld or nil
  if type(adapt)~="function" then
    P.randyStateStatus="goldStateForWorld unavailable"
    return nil
  end
  local ok,rs=pcall(adapt,world)
  if not (ok and type(rs)=="table" and rs.map and rs.camera and rs.player) then
    P.randyStateStatus=ok and "goldStateForWorld returned invalid state"
      or ("goldStateForWorld error: "..tostring(rs))
    return nil
  end
  -- Match OverworldBattle's frozen-battle draw lists without mutating the
  -- provider's live Gold world. The player remains because provider systems
  -- still key world-space placement from it; ordinary overworld NPC/ghost
  -- cast is omitted from this private portrait eye.
  rs.entities={rs.player}
  rs.ghosts={}
  -- This is the provider's own live-battle marker. VoxelScene uses it to draw
  -- Stadium world actors / battle occlusion. In Randy 2D mode Stadium.draw is
  -- privately suppressed below and the fixed FRONT card is supplied instead.
  rs._stadiumLiveBattle=true
  P.randyStateStatus="adapted"
  return rs
end

state.secondaryViewProbe.randyEligible=function()
  local P=state.secondaryViewProbe
  local gold,ctx,screen=P.randyContext()
  if not gold then return false end
  if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
  if not (state.battle and state.active) then return false end
  if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
  if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
  if state.attack and (state.attack.pending or state.attack.active) then return false end
  if state.faint and (state.faint.pending or state.faint.active) then return false end
  local b=state.battle
  if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
  -- Gold's ordinary command menu is the passive/idle window. Only subordinate
  -- party/item ownership suppresses PiP, matching the accepted Importer rule.
  if screen.phase=="party" or screen.phase=="item" then return false end
  return true
end

state.secondaryViewProbe.warmRandyScene=function()
  local P=state.secondaryViewProbe
  local gold,ctx,screen,world=P.randyContext()
  if not gold then return false end
  -- Warm only when Secondary View is actually requested.  Visibility remains
  -- governed by randyEligible(): Intro / Send-In / Attack / Faint / menus are
  -- still suppressed exactly as before.  Randy's VoxelScene.prefetch is the
  -- provider's own read-only terrain-cache path and does not advance battle or
  -- actor animation.
  if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
  local V=gold.V
  if not (V and type(V.require)=="function") then return false end
  local okVS,VoxelScene=pcall(V.require,"VoxelScene")
  if not (okVS and type(VoxelScene)=="table" and type(VoxelScene.prefetch)=="function") then return false end
  local rs=type(P.randyRenderState)=="function" and P.randyRenderState(gold,world) or nil
  if not rs then return false end
  local ok,terrain=pcall(VoxelScene.prefetch,rs)
  P.randyWarmCalls=(P.randyWarmCalls or 0)+1
  if ok and terrain then P.randyWarmReady=true end
  return ok and terrain and true or false
end

state.secondaryViewProbe.renderRandyFrame=function()
  local P=state.secondaryViewProbe
  if not P.randyEligible() then P.shot=nil; return end
  local gold,ctx,screen,world=P.randyContext()
  if not gold then P.shot=nil; return end
  local V=gold.V
  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local VoxelScene=gold.VoxelScene or req("VoxelScene")
  local Voxel3D=gold.Voxel3D or req("Voxel3D")
  local Stadium=req("Stadium")
  local OW=gold.OverworldBattle
  if not (VoxelScene and type(VoxelScene.render)=="function" and Voxel3D and Stadium and OW) then
    P.shot=nil; P.failure="Randy Secondary View renderer API unavailable"; return
  end
  local renderState=type(P.randyRenderState)=="function" and P.randyRenderState(gold,world) or nil
  if not renderState then
    P.shot=nil; P.failure="Randy Secondary View adapted Gold state unavailable: "..tostring(P.randyStateStatus); return
  end

  local stadiumShowing=false
  if type(Stadium.showing)=="function" then
    local ok,v=pcall(Stadium.showing,"player")
    stadiumShowing=ok and v and true or false
  end
  local actorMode=stadiumShowing and "randy_stadium2" or "randy_sprite"
  P.actorMode=actorMode
  local cam,pitch=P.cameraFor(gold.backend,ctx.arena,tonumber(ctx.groundY) or 0,actorMode)
  if not cam then P.shot=nil; P.failure="Randy portrait camera unavailable"; return end

  local g=love and love.graphics
  local sw=(g and g.getWidth and g.getWidth()) or 1280
  local sh=(g and g.getHeight and g.getHeight()) or 720
  local sizeMode=mod.options:get("secondaryViewSize") or "small"
  local frac=(sizeMode=="small") and 0.20 or 0.27
  local minW=(sizeMode=="small") and 132 or 180
  local rw=math.max(minW,math.floor(sw*frac))
  local rh=math.max(1,math.floor(math.min(sh*0.34,rw*9/16)))
  local R=gold.BattleCam and type(gold.BattleCam.rigFor)=="function"
      and gold.BattleCam.rigFor(ctx.arena) or nil
  local vh=math.max(8,tonumber(R and R.frameH) or 34.11)
  local vw=vh*(rw/math.max(1,rh))
  local eyes={{camera=cam,w=rw,h=rh,slot="bc_secondary_view_randy"}}
  local mid=ctx.arena.mid
  if type(mid)=="table" then eyes.cx=tonumber(mid[1]); eyes.cy=tonumber(mid[2]) end

  local actorDrawn=false
  local oldCamera=Voxel3D.camera
  local oldBeginScene=Voxel3D.beginScene
  local oldStadiumDraw=Stadium.draw
  local oldStadiumGuard=Stadium.guard
  local oldWorldCards=OW.worldCards
  local oldWorldAnim=OW.worldAnim
  local restoreNeeded=true
  local function restore()
    if not restoreNeeded then return end
    restoreNeeded=false
    Voxel3D.camera=oldCamera
    Voxel3D.beginScene=oldBeginScene
    Stadium.draw=oldStadiumDraw
    if oldStadiumGuard~=nil then Stadium.guard=oldStadiumGuard end
    OW.worldCards=oldWorldCards
    if oldWorldAnim~=nil then OW.worldAnim=oldWorldAnim else OW.worldAnim=nil end
  end

  -- The alternate-eye pass normally includes every live battle actor. PiP is
  -- a player portrait, so narrow it to exactly one already-live presentation.
  if stadiumShowing then
    OW.worldCards=function() return nil end
    OW.worldAnim=function() return nil end

    -- Rebase29: use Randy's OWN live Stadium.draw path instead of re-submitting
    -- the APB sampler's copy of the rig. Stadium.draw owns the provider-private
    -- current session/model matrices and is the path already proven on the main
    -- world. Its public guard seam names each side, letting this private eye
    -- suppress only ENEMY while the PLAYER executes the exact native draw.
    if type(oldStadiumGuard)=="function" then
      Stadium.guard=function(side,mon,what,fn)
        if what=="draw" and side=="enemy" then return true end
        if what=="draw" and side=="player" and type(fn)=="function" then
          local wrapped=function(...)
            actorDrawn=true
            return fn(...)
          end
          return oldStadiumGuard(side,mon,what,wrapped)
        end
        return oldStadiumGuard(side,mon,what,fn)
      end
    end
    Stadium.draw=oldStadiumDraw
  else
    Stadium.draw=function() end
    OW.worldAnim=function() return nil end

    -- Capture Gold/Crystal FRONT before VoxelScene opens its offscreen 3D pass.
    -- Per-eye worldCards calls then only rebuild the matrix/yaw from this stable
    -- live texture, avoiding nested BattleState drawing inside Voxel3D.render.
    local spriteTex=nil
    local capture=OW.__bcSecondaryViewPlayerTexture
    if type(capture)=="function" then
      local okTex,value=pcall(capture)
      if okTex then spriteTex=value end
    end
    OW.worldCards=function()
      local fn=OW.__bcSecondaryViewPlayerCards
      if type(fn)~="function" then return nil end
      local cards,tex,token=fn(spriteTex)
      if type(cards)=="table" and #cards>0 then actorDrawn=true end
      return cards,tex,token
    end
  end

  -- Rebase31: use Randy's exact Gold->VoxelScene adapter, the same contract
  -- its own GoldVoxelBridge exports for sibling modules. Raw game.world is NOT
  -- the object VoxelScene normally receives on Gold. Preflight the exact state
  -- so a nil result can be separated from terrain readiness.
  local preOK,preTerrain=pcall(VoxelScene.prefetch,renderState)
  P.randyDiagPrefetch=preOK and preTerrain and true or false
  local beginSeen,beginOK,beginErr=false,nil,nil
  if type(oldBeginScene)=="function" then
    Voxel3D.beginScene=function(...)
      beginSeen=true
      local okBegin,value=pcall(oldBeginScene,...)
      if not okBegin then
        beginOK=false; beginErr=tostring(value); error(value,0)
      end
      beginOK=value and true or false
      return value
    end
  end

  P.rendering=true
  local okRender,value=pcall(VoxelScene.render,renderState,rw,rh,vw,vh,nil,eyes)
  P.rendering=false
  P.randyDiagBeginSeen=beginSeen
  P.randyDiagBeginOK=beginOK
  P.randyDiagBeginErr=beginErr
  restore()
  local canvas=(okRender and type(value)=="table") and value[1] or nil
  if okRender and canvas and actorDrawn then
    P.shot={canvas=canvas}; P.failure=nil; P.frames=(P.frames or 0)+1
    P.actorMode=actorMode
  else
    P.shot=nil
    if okRender and canvas and not actorDrawn then
      P.failure="Randy Secondary View player actor/card unavailable"
    elseif not P.randyDiagPrefetch then
      P.failure="Randy adapted VoxelScene terrain unavailable"
    elseif not okRender then
      P.failure="Randy Secondary View render error: "..tostring(value)
    elseif not beginSeen then
      P.failure="Randy Secondary View nil before beginScene"
    elseif beginOK==false then
      P.failure="Randy Secondary View beginScene declined"..(beginErr and (": "..beginErr) or "")
    else
      P.failure="Randy Secondary View nil after beginScene"
    end
  end
end

-- Rebase39 Voxel Ascendant 2.0.1 Secondary View -- MAP/2D proof -----------
-- Voxel Ascendant 2.0.1 publishes a read-only compatibility facade containing
-- VoxelScene, Voxel3D, BattleArena/BattleCam and OverworldBattle. It deliberately
-- does NOT publish its private BattleScene/BattleBillboard/TerrainAtlas modules.
-- Respect that contract: BC never invokes or mutates the staged battle renderer.
--
-- This first proof supports the ordinary MAP rung with a fixed-FRONT 2D actor.
-- The secondary WORLD comes from VoxelScene.render under an independent
-- Voxel3D.camera; the ordinary overworld cast is removed from a shallow view copy
-- so no entity pose advances twice. After the provider returns its private world
-- canvas, BC overlays the one normalized FRONT portrait using the still-live
-- projection matrix. Portable ARENA/DISCS and Importer 3D are intentionally
-- deferred because the public 2.0.1 facade exposes no safe alternate-eye staged
-- battle/3D-actor insertion seam for those modes.
;(function()
  local P=state.secondaryViewProbe
  local handle=mod.find("VOXEL_ASCENDANT")
  local ex=handle and handle.exports or nil
  local V=ex and ex.lib or nil
  if not (P and ex and tostring(ex.version or "")=="2.0.1"
      and V and type(V.require)=="function") then return end

  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local OW=req("OverworldBattle")
  local VS=req("VoxelScene")
  local V3=req("Voxel3D")
  local VState=req("VoxelState")
  if not (OW and VS and V3 and VState and type(OW.arena)=="function"
      and type(OW.enabled)=="function" and type(VS.render)=="function"
      and type(VS.prefetch)=="function" and type(VS.groundAt)=="function"
      and type(V3.project)=="function") then return end

  local backend=nil
  for _,b in ipairs(backends) do
    if b and b.id=="VOXEL_ASCENDANT" then backend=b; break end
  end
  if not backend then return end
  P.voxelAscendantBackend=backend
  P.voxelAscendantModules={OverworldBattle=OW,VoxelScene=VS,Voxel3D=V3,VoxelState=VState}

  -- Rebase45: current Stadium2 Importer exposes a generation-neutral public
  -- presentation Actor API. Ascendant itself intentionally has no Stadium
  -- model API, so keep responsibilities separated: Ascendant supplies the MAP
  -- world, Importer supplies one independently-owned PLAYER model, BC supplies
  -- the Secondary View camera. No private Ascendant staged-renderer module is
  -- consumed.
  local function importerContext()
    local h=mod.find("STADIUM2_IMPORTER")
    local x=h and h.exports or nil
    local presentation=x and x.presentation or nil
    if not (x and presentation and type(presentation.newActor)=="function") then return nil end
    local function flag(name)
      local fn=x[name]
      if type(fn)~="function" then return false end
      local ok,v=pcall(fn)
      if not ok then ok,v=pcall(fn,x) end
      return ok and v==true
    end
    if not (flag("modelsEnabled") and flag("battleEnabled")) then return nil end
    return x,presentation
  end

  local function monForBattle(battle)
    local battler=battle and battle.player or nil
    local mon=battler and battler.mon or nil
    if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
    return type(mon)=="table" and mon or nil
  end

  local function resolveImporterActor(battle)
    local x,presentation=importerContext()
    P.voxelAscendantImporterRequested=(x~=nil)
    P.voxelAscendantImporterFailure=nil
    if not x then return nil end
    local mon=monForBattle(battle)
    if not mon then P.voxelAscendantImporterFailure="player mon unavailable"; return nil end

    local actor=P.voxelAscendantImporterActor
    if not actor then
      local ok,a=pcall(presentation.newActor,"player",{label="BC Voxel Ascendant Secondary View"})
      if not (ok and type(a)=="table") then
        P.voxelAscendantImporterFailure="Importer Actor.new failed: "..tostring(a)
        return nil
      end
      actor=a; P.voxelAscendantImporterActor=actor
    end
    if P.voxelAscendantImporterMon~=mon or not actor.renderer then
      local okLoad,loaded=pcall(actor.load,actor,battle and battle.data or nil,mon,nil)
      if not (okLoad and loaded and actor.renderer) then
        if type(actor.release)=="function" then pcall(actor.release,actor) end
        P.voxelAscendantImporterActor=nil
        P.voxelAscendantImporterMon=nil
        P.voxelAscendantImporterFailure="Importer player actor load failed"
        return nil
      end
      P.voxelAscendantImporterMon=mon
      P.voxelAscendantImporterLastTime=nil
    end

    local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
    local dt=P.voxelAscendantImporterLastTime and (now-P.voxelAscendantImporterLastTime) or 0.10
    P.voxelAscendantImporterLastTime=now
    dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10))
    if type(actor.update)=="function" then pcall(actor.update,actor,dt) end
    return actor
  end

  local function importerBounds(actor)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.poseBounds)=="function"
        and type(renderer.worldMetrics)=="function") then return nil end
    local okB,b=pcall(renderer.poseBounds,renderer)
    local okM,m=pcall(renderer.worldMetrics,renderer)
    if not (okB and okM and type(b)=="table" and type(m)=="table") then return nil end
    local minX,maxX=tonumber(b.minX),tonumber(b.maxX)
    local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
    local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ)
    local modelH=tonumber(m.height)
    if not (minX and maxX and minY and maxY and minZ and maxZ
        and modelH and modelH>1e-4 and maxY>minY) then return nil end
    local worldH=math.max(5,math.min(18,14*math.sqrt(modelH/52.25)))
    local k=worldH/modelH
    local floor=tonumber(m.floor) or 0
    local hover=math.min(math.max(floor,0),modelH*0.5)
    local offset=floor-hover
    local bottom=(minY-offset)*k
    local top=(maxY-offset)*k
    local height=top-bottom
    if height<=1e-3 then return nil end
    local sx=math.max(0,(maxX-minX)*k)
    local sz=math.max(0,(maxZ-minZ)*k)
    local breadth=math.sqrt(sx*sx+sz*sz)
    local elevation=math.max(0,bottom)
    local elevationNorm=elevation/height
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {
      visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,
      breadth=breadth,spanX=sx,spanZ=sz,
      breadthHeightRatio=breadth/math.max(1e-3,height),
      elevation=elevation,elevationNorm=elevationNorm,
      source="STADIUM2_IMPORTER_VOXEL_ASCENDANT_MAP_POSED_V1",confidence="medium",
    }
  end

  local DEPTH_FORMATS={"depth24stencil8","depth24","depth16","depth32f"}
  local function newDepthCanvas(g,w,h)
    for _,format in ipairs(DEPTH_FORMATS) do
      local ok,d=pcall(g.newCanvas,w,h,{format=format,readable=false,dpiscale=1})
      if ok and d then return d end
    end
    return nil
  end

  local function ensureImporterTarget(g,w,h)
    local c=P.voxelAscendantImporterCanvas
    if c and P.voxelAscendantImporterRW==w and P.voxelAscendantImporterRH==h then
      return c,P.voxelAscendantImporterDepth
    end
    for _,v in ipairs({P.voxelAscendantImporterCanvas,P.voxelAscendantImporterDepth}) do
      if v and type(v.release)=="function" then pcall(v.release,v) end
    end
    local ok,canvas=pcall(g.newCanvas,w,h,{format="rgba8",readable=true,dpiscale=1})
    if not (ok and canvas) then return nil,nil end
    if type(canvas.setFilter)=="function" then pcall(canvas.setFilter,canvas,"nearest","nearest") end
    local depth=newDepthCanvas(g,w,h)
    P.voxelAscendantImporterCanvas=canvas
    P.voxelAscendantImporterDepth=depth
    P.voxelAscendantImporterRW=w
    P.voxelAscendantImporterRH=h
    return canvas,depth
  end

  local function matTranslate(x,y,z)
    return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1}
  end
  local function matScale(v)
    return {v,0,0,0,0,v,0,0,0,0,v,0,0,0,0,1}
  end
  local function matRotateY(a)
    local c,ss=math.cos(a),math.sin(a)
    return {c,0,ss,0,0,1,0,0,-ss,0,c,0,0,0,0,1}
  end

  local function drawImporterIntoActiveScene(actor,cam,arena,groundY)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.worldMetrics)=="function"
        and type(renderer.drawScene)=="function" and type(V3.vp)=="table") then
      return false,"Importer actor renderer/VP unavailable"
    end
    local okM,metrics=pcall(renderer.worldMetrics,renderer)
    local height=okM and metrics and tonumber(metrics.height) or nil
    if not (height and height>1e-4) then return false,"Importer actor metrics unavailable" end

    local okIR,IR=pcall(require,"mods.STADIUM2_IMPORTER.lib.renderer")
    if not (okIR and type(IR)=="table" and type(IR.matMul)=="function"
        and type(IR.lookAt)=="function" and type(IR.normalMatrix)=="function") then
      return false,"Importer shared-scene renderer API unavailable"
    end

    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
    local exx,ezz=tonumber(arena.enemy and arena.enemy[1]),tonumber(arena.enemy and arena.enemy[2])
    if not (px and pz and exx and ezz) then return false,"Importer arena actor anchors unavailable" end

    -- Exact accepted Importer/Battle-Art presentation transform.  Do not tune
    -- this for Ascendant: only the world provider changed.  The player actor,
    -- APB semantics, scale/hover and camera grammar remain the Rebase38 path.
    local worldH=math.max(5,math.min(18,14*math.sqrt(height/52.25)))
    local grow=type(actor.scale)=="function" and actor:scale() or 1
    grow=math.max(0,math.min(1,tonumber(grow) or 1))
    local k=worldH/height*grow
    local floor=tonumber(metrics.floor) or 0
    local hover=math.min(math.max(floor,0),height*0.5)
    local yaw=math.atan2(exx-px,ezz-pz)
    local model=IR.matMul(matTranslate(px,groundY,pz),
      IR.matMul(matRotateY(yaw),
        IR.matMul(matScale(k),matTranslate(0,-(floor-hover),0))))
    local viewMatrix=IR.lookAt(cam.eye[1],cam.eye[2],cam.eye[3],
      cam.focus[1],cam.focus[2],cam.focus[3])
    local tint=V3.tint or {1,1,1}
    local ctx={
      viewProjection=V3.vp,viewMatrix=viewMatrix,
      normalMatrix=IR.normalMatrix(yaw,0,false),
      lightDir={0.35,0.7,0.62},ambient={0.46,0.46,0.46},
      diffuse={0.72,0.72,0.72},flipWinding=true,disableCulling=true,
      tint={tint[1] or 1,tint[2] or 1,tint[3] or 1,1},flashAmount=0,
    }
    for _,pass in ipairs({"opaque","additive"}) do
      local okD,a,b=pcall(renderer.drawScene,renderer,pass,model,ctx)
      if not okD then return false,"Importer actor draw error: "..tostring(a) end
      if a==false then return false,"Importer actor draw rejected: "..tostring(b) end
    end
    return true
  end

  local function lifecycleEligible()
    if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
    if not (state.battle and state.active) then return false end
    if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
    if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
    if state.attack and (state.attack.pending or state.attack.active) then return false end
    if state.faint and (state.faint.pending or state.faint.active) then return false end
    local b=state.battle
    if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
    return true
  end

  P.voxelAscendantEligible=function()
    if not lifecycleEligible() then return false end
    local okE,on=pcall(OW.enabled)
    if not okE or not on then return false end
    -- Rebase39 is deliberately the public MAP seam only. ARENA/DISCS are
    -- staged by private modules not present in Ascendant's reviewed facade.
    if type(OW.portable)=="function" then
      local okP,portable=pcall(OW.portable)
      if okP and portable then return false end
    end
    local okA,arena=pcall(OW.arena)
    return okA and type(arena)=="table" and type(arena.player)=="table"
      and type(arena.enemy)=="table"
  end

  local function dims(img)
    if not (img and type(img.getDimensions)=="function") then return nil,nil end
    local ok,w,h=pcall(img.getDimensions,img)
    if not ok then return nil,nil end
    return tonumber(w),tonumber(h)
  end

  -- Rebase47: Crystal MAP must use the exact already-proven flat portrait
  -- contract rather than another Ascendant-specific percentage fit. This is
  -- the same optical language used by Dramaless/Battle Art: a 160x144 portrait
  -- surface, subject normalized to max 56 px, feet at 80/96, and the canonical
  -- 0.58 world-card factor. The live Crystal FRONT remains provider-owned.
  local PORTRAIT_W,PORTRAIT_H=160,144
  local PORTRAIT_AX,PORTRAIT_AY=80,96
  local PORTRAIT_MAX=56
  local PORTRAIT_FULL_W=16
  local PORTRAIT_WORLD_SCALE=0.58
  local crystalPortraitCanvas=nil

  local function canonicalCrystalPortrait(g,img)
    if not (g and img and type(g.newCanvas)=="function" and type(g.draw)=="function") then
      return nil,"portrait graphics unavailable"
    end
    if not crystalPortraitCanvas then
      local ok,c=pcall(g.newCanvas,PORTRAIT_W,PORTRAIT_H,{dpiscale=1})
      if not (ok and c) then return nil,"portrait canvas unavailable" end
      if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
      crystalPortraitCanvas=c
    end
    local w,h=dims(img)
    if not (w and h and w>0 and h>0) then return nil,"portrait dimensions unavailable" end
    local scale=PORTRAIT_MAX/math.max(w,h)
    if not (scale>0.01 and scale<32) then return nil,"portrait normalization invalid" end

    local unpack_=table.unpack or unpack
    local prior={}
    if type(g.getCanvas)=="function" then prior={g.getCanvas()} end
    local pushed=false
    local ok,err=pcall(function()
      if type(g.push)=="function" then g.push("all"); pushed=true end
      g.setCanvas(crystalPortraitCanvas)
      g.clear(0,0,0,0)
      if type(g.origin)=="function" then g.origin() end
      if type(g.setScissor)=="function" then g.setScissor() end
      if type(g.setShader)=="function" then g.setShader() end
      if type(g.setDepthMode)=="function" then g.setDepthMode() end
      g.setBlendMode("alpha")
      g.setColor(1,1,1,1)
      g.draw(img,PORTRAIT_AX-w*scale/2,PORTRAIT_AY-h*scale,0,scale,scale)
    end)
    if pushed and type(g.pop)=="function" then pcall(g.pop) end
    pcall(function()
      if #prior>0 then g.setCanvas(unpack_(prior)) else g.setCanvas() end
    end)
    if not ok then return nil,tostring(err) end
    -- Return the normalized source-frame rectangle as presentation metadata.
    -- Rebase50b uses only its HEIGHT for a one-way top-visibility guard; it
    -- never re-anchors the feet, scans alpha, or changes Rebase49 scale.
    return crystalPortraitCanvas,nil,{subjectW=w*scale,subjectH=h*scale}
  end

  local function drawCanonicalCrystalPortrait(g,portrait,px,groundY,pz,meta)
    if not (g and portrait and type(V3.project)=="function") then
      return false,"canonical portrait projection unavailable"
    end
    local sx,sy=V3.project(px,groundY,pz)
    if not (sx and sy) then return false,"player anchor projection unavailable" end

    -- Exact canonical card world scale: FULL_W/FULL_PIC, then 0.58. Ascendant
    -- does not publish BattleBillboard, so use the frozen public contract values
    -- directly instead of inventing a backend-specific fit percentage.
    local worldPerPixel=(PORTRAIT_FULL_W/PORTRAIT_MAX)*PORTRAIT_WORLD_SCALE
    -- Parity correction: the 160x144 canvas is only a carrier/anchor surface.
    -- The accepted Dramaless/Battle Art contract sizes the NORMALIZED SUBJECT:
    -- 56 canonical pixels occupy FULL_W * 0.58 = 9.28 world units. Rebase47
    -- mistakenly projected the whole 144px carrier as subject height, which
    -- greatly over-scaled ink-heavy Crystal frames such as Charizard/Onix.
    local _,topY=V3.project(px,groundY+PORTRAIT_MAX*worldPerPixel,pz)
    if not topY then return false,"canonical portrait top projection unavailable" end
    local drawScale=math.abs(sy-topY)/PORTRAIT_MAX
    if not (drawScale>0 and drawScale<64) then return false,"canonical portrait scale invalid" end

    -- Fixed FRONT remains fixed FRONT. PIP SIDE alone owns flat-art handedness,
    -- exactly as on the established Dramaless/Battle Art portrait paths.
    local mirror=(mod.options:get("secondaryViewSide") or "left")=="left"
    local dx=mirror and -drawScale or drawScale
    local x=sx-PORTRAIT_AX*dx
    local y=sy-PORTRAIT_AY*drawScale

    -- Rebase50b: Rebase49 is the proven scale/baseline. The remaining bad
    -- Crystal case is top clipping: the correct established portrait language
    -- is allowed to lose lower body/legs before it loses the readable upper
    -- silhouette. Apply only a one-way SCREEN-EDGE safety shift when the
    -- normalized source-frame rectangle itself would cross the top of the
    -- 320x180 PiP. This is not optical recentring and does not inspect alpha,
    -- species, anatomy or the frame bottom. Ordinary Rebase49 shots therefore
    -- remain bit-for-bit in placement whenever their source rectangle fits.
    local subjectH=meta and tonumber(meta.subjectH) or nil
    if subjectH and subjectH>0 then
      local subjectTop=sy-subjectH*drawScale
      if subjectTop<0 then y=y-subjectTop end
    end

    local pushed=false
    local ok,err=pcall(function()
      if type(g.push)=="function" then g.push("all"); pushed=true end
      if type(g.origin)=="function" then g.origin() end
      if type(g.setScissor)=="function" then g.setScissor() end
      if type(g.setShader)=="function" then g.setShader() end
      if type(g.setDepthMode)=="function" then g.setDepthMode() end
      g.setBlendMode("alpha")
      g.setColor(1,1,1,1)
      g.draw(portrait,x,y,0,dx,drawScale)
    end)
    if pushed and type(g.pop)=="function" then pcall(g.pop) end
    if not ok then return false,tostring(err) end
    return true
  end

  local function shallowWorld(world,arena,vw,vh)
    local view={}
    for k,v in pairs(world) do view[k]=v end
    -- Never advance/render the frozen overworld player or NPC poses again.
    view.entities={}
    view.ghosts={}
    view.flyAnim=nil
    view.camera={x=(arena.mid[1] or 0)-vw/2,y=(arena.mid[2] or 0)-vh/2}
    return view
  end

  P.renderVoxelAscendantFrame=function()
    if not P.voxelAscendantEligible() then P.shot=nil; return end
    local battle=state.battle
    local okA,arena=pcall(OW.arena)
    if not (okA and type(arena)=="table") then
      P.shot=nil; P.failure="Voxel Ascendant arena unavailable"; return
    end
    local GameModule=select(2,pcall(require,"src.core.Game"))
    local world=type(GameModule)=="table" and GameModule.overworld or nil
    if not (world and world.map and world.player and world.camera) then
      P.shot=nil; P.failure="Voxel Ascendant read-only world unavailable"; return
    end
    if arena.map and arena.map~=world.map then
      P.shot=nil; P.failure="Voxel Ascendant cross-floor MAP view deferred"; return
    end

    -- Resolve actor CLASS before camera composition. Importer 3D gets the
    -- shared semantic/APB three-quarter compositor; ordinary Ascendant cards
    -- retain the accepted flat fixed-FRONT MAP contract.
    local importerActor=resolveImporterActor(battle)
    if P.voxelAscendantImporterRequested and not importerActor then
      P.shot=nil
      P.failure="Voxel Ascendant + Importer 3D actor unavailable: "
        ..tostring(P.voxelAscendantImporterFailure or "unknown")
      return
    end
    local actorMode=importerActor and "stadium2_importer" or "voxel_ascendant_2d"
    local img,src,iw,ih=nil,nil,nil,nil
    if not importerActor then
      local fixedFront=P.voxelAscendantFixedFront
      if type(fixedFront)~="function" then
        P.shot=nil; P.failure="Voxel Ascendant fixed-FRONT seam unavailable"; return
      end
      local okImg,value,source=pcall(fixedFront,battle)
      if not (okImg and value) then
        P.shot=nil; P.failure="Voxel Ascendant FRONT unavailable: "..tostring(source or value); return
      end
      img,src=value,source
      iw,ih=dims(img)
      if not (iw and ih and iw>0 and ih>0) then
        P.shot=nil; P.failure="Voxel Ascendant FRONT dimensions unavailable"; return
      end
    else
      src="stadium2_importer_actor"
    end

    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
    local pcx,pcy=arena.playerCell and tonumber(arena.playerCell[1]),arena.playerCell and tonumber(arena.playerCell[2])
    if not (px and pz and pcx and pcy) then
      P.shot=nil; P.failure="Voxel Ascendant player anchor unavailable"; return
    end
    local okGY,groundY=pcall(VS.groundAt,world.map,pcx,pcy)
    groundY=(okGY and tonumber(groundY)) or 0
    local oldBounds=P._goldImporterBounds
    if importerActor then P._goldImporterBounds=importerBounds(importerActor) end
    local cam,pitch=P.cameraFor(backend,arena,groundY,actorMode)
    P._goldImporterBounds=oldBounds
    if not cam then
      P.shot=nil; P.failure="Voxel Ascendant portrait camera unavailable"; return
    end

    -- Small independent world canvas. VoxelScene owns terrain/sky/weather;
    -- BC only supplies the placed camera through Voxel3D's documented camera
    -- record and an actor-free shallow view state.
    local rw,rh=320,180
    local vw,vh=160,90
    local view=shallowWorld(world,arena,vw,vh)
    local g=love and love.graphics or nil
    if not g then P.shot=nil; P.failure="Voxel Ascendant graphics unavailable"; return end

    -- Crystal alone moves to the canonical 160x144 flat portrait surface.
    -- Vanilla keeps Rebase46's tolerated path; Importer 3D remains untouched.
    local crystalPortrait=nil
    local crystalPortraitMeta=nil
    if not importerActor and src=="crystal_live_front" then
      local why=nil
      crystalPortrait,why,crystalPortraitMeta=canonicalCrystalPortrait(g,img)
      if not crystalPortrait then
        P.shot=nil; P.failure="Voxel Ascendant Crystal portrait unavailable: "..tostring(why); return
      end
    end

    local unpack_=table.unpack or unpack
    local prevCanvas={}
    if type(g.getCanvas)=="function" then prevCanvas={g.getCanvas()} end
    local prevShader=type(g.getShader)=="function" and g.getShader() or nil
    local br,ba="alpha",nil
    if type(g.getBlendMode)=="function" then br,ba=g.getBlendMode() end
    local cr,cg,cb,ca=1,1,1,1
    if type(g.getColor)=="function" then cr,cg,cb,ca=g.getColor() end
    local dm,dw=nil,nil
    if type(g.getDepthMode)=="function" then dm,dw=g.getDepthMode() end
    local cull=type(g.getMeshCullMode)=="function" and g.getMeshCullMode() or nil

    local oldCamera=V3.camera
    -- Rebase44: VoxelScene.prefetch() writes the provider-global VoxelState.ready
    -- gate.  That gate belongs to Ascendant's MAIN pipeline; a private PiP
    -- camera must never make the host briefly fall back to its flat 2D path.
    -- Preserve the provider's exact readiness receipt around this read-only
    -- secondary render.
    local oldVoxelReady=VState.ready
    local oldTint=V3.tint
    local oldGlassMask,oldGlassNight=V3.glassMask,V3.glassNight
    local oldGlassPhase,oldGlassGlint=V3.glassPhase,V3.glassGlint
    local oldShadowAlpha=V3.SHADOW_ALPHA
    local canvas=nil
    local oldEndScene=V3.endScene
    local importerInjected=false
    local importerDrawError=nil
    local crystalInjected=false
    local crystalDrawError=nil
    if (importerActor or crystalPortrait) and type(oldEndScene)=="function" then
      -- Rebase46's validated Importer transplant remains byte-for-byte in
      -- behavior. Rebase47 adds only the flat Crystal portrait at this same
      -- live-scene seam, before Ascendant closes its private MAP target.
      -- There is still no second actor canvas/composite and no camera retraining.
      -- ALWAYS call Ascendant's original endScene even if an optional actor draw
      -- fails so the provider can never be left in a stranded render state.
      V3.endScene=function(...)
        if importerActor and not importerInjected and not importerDrawError then
          local drawn,why=drawImporterIntoActiveScene(importerActor,cam,arena,groundY)
          if drawn then importerInjected=true else importerDrawError=tostring(why) end
        elseif crystalPortrait and not crystalInjected and not crystalDrawError then
          local drawn,why=drawCanonicalCrystalPortrait(g,crystalPortrait,px,groundY,pz,crystalPortraitMeta)
          if drawn then crystalInjected=true else crystalDrawError=tostring(why) end
        end
        return oldEndScene(...)
      end
    end

    local okRender,errRender=pcall(function()
      V3.camera=cam
      canvas=VS.render(view,rw,rh,vw,vh,nil)
      if not canvas then error("public VoxelScene.render returned nil",0) end
      if importerActor and importerDrawError then
        error("Importer actor in-scene draw failed: "..importerDrawError,0)
      end
      if importerActor and not importerInjected then
        error("Importer actor was not reached by Ascendant endScene",0)
      end
      if crystalPortrait and crystalDrawError then
        error("Crystal canonical portrait in-scene draw failed: "..crystalDrawError,0)
      end
      if crystalPortrait and not crystalInjected then
        error("Crystal canonical portrait was not reached by Ascendant endScene",0)
      end

      if not importerActor and not crystalPortrait then
        -- Vanilla/ROM remains exactly on the tolerated Rebase46 projection path.
        -- Do not reopen its known provider-scale quirk for v1.2.0.
        local sx,sy=V3.project(px,groundY,pz)
        if not (sx and sy) then error("player anchor projection unavailable",0) end
        local maxDim=math.max(iw,ih)
        local worldMax=16*0.58
        local worldH=worldMax*(ih/maxDim)
        local _,topY=V3.project(px,groundY+worldH,pz)
        local projectedH=(topY and math.abs(sy-topY)) or nil
        local drawScale=(projectedH and projectedH>1)
          and (projectedH/ih)
          or ((rh*0.82)/maxDim)
        local mirror=(mod.options:get("secondaryViewSide") or "left")=="left"
        local dx=mirror and -drawScale or drawScale
        local x=sx-(iw*dx)/2
        local y=sy-ih*drawScale
        g.setCanvas(canvas)
        g.setShader()
        g.setDepthMode()
        g.setBlendMode("alpha")
        g.setColor(1,1,1,1)
        g.draw(img,x,y,0,dx,drawScale)
        g.setCanvas()
      end
    end)

    if (importerActor or crystalPortrait) and type(oldEndScene)=="function" then V3.endScene=oldEndScene end
    V3.camera=oldCamera
    VState.ready=oldVoxelReady
    V3.tint=oldTint
    V3.glassMask,V3.glassNight=oldGlassMask,oldGlassNight
    V3.glassPhase,V3.glassGlint=oldGlassPhase,oldGlassGlint
    V3.SHADOW_ALPHA=oldShadowAlpha
    pcall(function()
      if #prevCanvas>0 then g.setCanvas(unpack_(prevCanvas)) else g.setCanvas() end
      if type(g.setShader)=="function" then g.setShader(prevShader) end
      if type(g.setDepthMode)=="function" then
        if dm then g.setDepthMode(dm,dw) else g.setDepthMode() end
      end
      if cull and type(g.setMeshCullMode)=="function" then g.setMeshCullMode(cull) end
      if type(g.setBlendMode)=="function" then
        if ba~=nil then g.setBlendMode(br,ba) else g.setBlendMode(br) end
      end
      g.setColor(cr,cg,cb,ca)
    end)

    if okRender and canvas then
      P.shot={canvas=canvas}; P.failure=nil; P.actorMode=actorMode
      P.frames=(P.frames or 0)+1; P.voxelAscendantLastSource=src
    else
      P.shot=nil; P.failure="Voxel Ascendant MAP render error: "..tostring(errRender)
    end
  end

  mod.log:warn("[SECONDARY VIEW] Voxel Ascendant 2.0.1 MAP adapter armed")
end)()

-- Rebase38 Battle Art Secondary View -- locked 2D + Importer 3D ------------
-- Rebase37 proved the only safe Battle Art world seam so far: render below
-- BattleScene/provider ownership using Battle Art's lower-level voxel terrain
-- modules and a private canvas. Rebase38 LOCKS that entire 2D path and adds one
-- actor class only: a public Stadium2 Importer presentation Actor, drawn directly
-- into the already-proven private Battle Art depth target.
--
-- Still forbidden here:
--   * BattleScene.render()
--   * providerBegin/providerRender/providerFinish
--   * sideTexture
--   * mutation of Battle Art's live session/shot
-- Importer owns model assets/animation/shader. BC owns only this independent
-- PiP actor instance, its camera, and where it is submitted in the private world.
;(function()
  local P=state.secondaryViewProbe
  local handle=mod.find("BATTLE_ART_VOXEL_FORK")
  local ex=handle and handle.exports or nil
  local V=ex and ex.lib or nil
  if not (P and V and type(V.require)=="function") then return end

  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local OW=req("OverworldBattle")
  local VS=req("VoxelScene")
  local V3=req("Voxel3D")
  local TA=req("TerrainAtlas")
  local M4=req("Mat4")
  local BB=req("BattleBillboard")
  local SM=req("StadiumModels")
  local BA=req("BattleArt")
  if not (OW and VS and V3 and TA and M4 and BB and BA
      and type(OW.arena)=="function" and type(OW.battle)=="function"
      and type(VS.prefetch)=="function" and type(V3.beginScene)=="function"
      and type(V3.endScene)=="function" and type(V3.draw)=="function"
      and type(TA.forMap)=="function" and type(BB.mesh)=="function"
      and type(BB.matrix)=="function" and type(BB.yawToward)=="function") then
    return
  end

  local backend=nil
  for _,b in ipairs(backends) do
    if b and b.id=="BATTLE_ART_VOXEL_FORK" then backend=b; break end
  end
  if not backend then return end

  P.battleArtBackend=backend
  P.battleArtModules={OverworldBattle=OW,VoxelScene=VS,Voxel3D=V3,
    TerrainAtlas=TA,Mat4=M4,BattleBillboard=BB,StadiumModels=SM,BattleArt=BA}

  local function lifecycleEligible()
    if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
    if not (state.battle and state.active) then return false end
    if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
    if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
    if state.attack and (state.attack.pending or state.attack.active) then return false end
    if state.faint and (state.faint.pending or state.faint.active) then return false end
    local b=state.battle
    if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
    return true
  end

  local function importerContext()
    local h=mod.find("STADIUM2_IMPORTER")
    local x=h and h.exports or nil
    local p=x and x.presentation or nil
    if not (x and p and type(p.newActor)=="function") then return nil end
    local function flag(name)
      local fn=x[name]
      if type(fn)~="function" then return false end
      local ok,v=pcall(fn)
      if not ok then ok,v=pcall(fn,x) end
      return ok and v==true
    end
    if not (flag("modelsEnabled") and flag("battleEnabled")) then return nil end
    return x,p
  end

  P.battleArtImporterEnabled=function()
    return importerContext()~=nil
  end

  P.battleArtEligible=function()
    if not lifecycleEligible() then return false end
    local b=OW.battle()
    if not b or b~=state.battle then return false end
    local arena=OW.arena()
    if type(arena)~="table" or type(arena.player)~="table" then return false end
    -- Rebase37 hard-yielded every StadiumModels-active presentation. Rebase38
    -- allows exactly one proven 3D provider class through that gate: current
    -- Stadium2 Importer's public presentation Actor API. Any other Stadium
    -- provider remains a hard yield rather than silently becoming a sprite.
    if SM and type(SM.active)=="function" then
      local ok,on=pcall(SM.active)
      if ok and on and not P.battleArtImporterEnabled() then return false end
    end
    return true
  end

  local function monForBattle(battle)
    local battler=battle and battle.player or nil
    local mon=battler and battler.mon or nil
    if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
    return type(mon)=="table" and mon or nil
  end

  P.resolveBattleArtImporterActor=function(battle)
    local x,presentation=importerContext()
    P.battleArtImporterRequested=(x~=nil)
    P.battleArtImporterFailure=nil
    if not x then return nil end
    local mon=monForBattle(battle)
    if not mon then P.battleArtImporterFailure="player mon unavailable"; return nil end

    local actor=P.battleArtImporterActor
    if not actor then
      local ok,a=pcall(presentation.newActor,"player",{label="BC Battle Art Secondary View"})
      if not (ok and type(a)=="table") then
        P.battleArtImporterFailure="Importer Actor.new failed: "..tostring(a)
        return nil
      end
      actor=a; P.battleArtImporterActor=actor
    end
    if P.battleArtImporterMon~=mon or not actor.renderer then
      local okLoad,loaded=pcall(actor.load,actor,battle and battle.data or nil,mon,nil)
      if not (okLoad and loaded and actor.renderer) then
        if type(actor.release)=="function" then pcall(actor.release,actor) end
        P.battleArtImporterMon=nil
        P.battleArtImporterFailure="Importer player actor load failed"
        return nil
      end
      P.battleArtImporterMon=mon
      P.battleArtImporterLastTime=nil
    end

    -- This actor belongs only to Secondary View. Advance one idle timeline at
    -- the PiP render cadence; the provider's live/main actor is never touched.
    local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
    local dt=P.battleArtImporterLastTime and (now-P.battleArtImporterLastTime) or 0.10
    P.battleArtImporterLastTime=now
    dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10))
    if type(actor.update)=="function" then pcall(actor.update,actor,dt) end
    return actor
  end

  P.battleArtImporterBounds=function(actor)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.poseBounds)=="function"
        and type(renderer.worldMetrics)=="function") then return nil end
    local okB,b=pcall(renderer.poseBounds,renderer)
    local okM,m=pcall(renderer.worldMetrics,renderer)
    if not (okB and okM and type(b)=="table" and type(m)=="table") then return nil end
    local minX,maxX=tonumber(b.minX),tonumber(b.maxX)
    local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
    local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ)
    local modelH=tonumber(m.height)
    if not (minX and maxX and minY and maxY and minZ and maxZ
        and modelH and modelH>1e-4 and maxY>minY) then return nil end
    local worldH=math.max(5,math.min(18,14*math.sqrt(modelH/52.25)))
    local k=worldH/modelH
    local floor=tonumber(m.floor) or 0
    local hover=math.min(math.max(floor,0),modelH*0.5)
    local offset=floor-hover
    local bottom=(minY-offset)*k
    local top=(maxY-offset)*k
    local height=top-bottom
    if height<=1e-3 then return nil end
    local sx=math.max(0,(maxX-minX)*k)
    local sz=math.max(0,(maxZ-minZ)*k)
    local breadth=math.sqrt(sx*sx+sz*sz)
    local elevation=math.max(0,bottom)
    local elevationNorm=elevation/height
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {
      visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,
      breadth=breadth,spanX=sx,spanZ=sz,
      breadthHeightRatio=breadth/math.max(1e-3,height),
      elevation=elevation,elevationNorm=elevationNorm,
      source="STADIUM2_IMPORTER_BATTLE_ART_LOWER_LEVEL_POSED_V1",confidence="medium",
    }
  end

  local function copyState(world,arena,vw,vh)
    local view={}
    for k,v in pairs(world) do view[k]=v end
    view.entities={}
    view.ghosts={}
    view.camera={x=(arena.mid[1] or 0)-vw/2,y=(arena.mid[2] or 0)-vh/2}
    return view
  end

  local function dims(img)
    if not img or type(img.getDimensions)~="function" then return nil,nil end
    local ok,w,h=pcall(img.getDimensions,img)
    if ok then return tonumber(w),tonumber(h) end
    return nil,nil
  end

  P.renderBattleArtFrame=function()
    if not P.battleArtEligible() then P.shot=nil; return end
    local battle=state.battle
    local arena=OW.arena()
    local GameModule=select(2,pcall(require,"src.core.Game"))
    local world=type(GameModule)=="table" and GameModule.overworld or nil
    if not (world and world.map and world.player) then
      P.shot=nil; P.failure="Battle Art read-only world unavailable"; return
    end
    if arena.map and arena.map~=world.map then
      P.shot=nil; P.failure="Battle Art Rebase38 cross-floor arena deferred"; return
    end

    -- Resolve actor CLASS before the camera. Importer 3D consumes the frozen
    -- semantic APB/three-quarter compositor; otherwise the exact accepted
    -- Rebase37 fixed-FRONT 2D contract remains byte-for-byte in spirit.
    local importerActor=P.resolveBattleArtImporterActor(battle)
    if P.battleArtImporterRequested and not importerActor then
      P.shot=nil
      P.failure="Battle Art + Importer 3D actor unavailable: "..tostring(P.battleArtImporterFailure or "unknown")
      return
    end
    local actorMode=importerActor and "stadium2_importer" or "battle_art_2d"

    local img,source=nil,nil
    if not importerActor then
      local fixedFront=state.secondaryViewProbe.battleArtFixedFront
      if type(fixedFront)~="function" then
        P.shot=nil; P.failure="Battle Art fixed-FRONT seam unavailable"; return
      end
      local okImg,value,src=pcall(fixedFront,battle)
      if not (okImg and value) then
        P.shot=nil; P.failure="Battle Art fixed-FRONT unavailable: "..tostring(src or value); return
      end
      img,source=value,src
    else
      source="stadium2_importer_actor"
    end

    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
    local exx,ezz=tonumber(arena.enemy and arena.enemy[1]),tonumber(arena.enemy and arena.enemy[2])
    if not (px and pz and exx and ezz) then P.shot=nil; P.failure="Battle Art arena actors unavailable"; return end
    local map=world.map
    local cx,cz=math.floor(px/16),math.floor(pz/16)
    local okGY,groundY=pcall(VS.groundAt,map,cx,cz)
    groundY=(okGY and tonumber(groundY)) or 0

    local oldBounds=P._goldImporterBounds
    if importerActor then P._goldImporterBounds=P.battleArtImporterBounds(importerActor) end
    local cam,pitch=P.cameraFor(backend,arena,groundY,actorMode)
    P._goldImporterBounds=oldBounds
    if not cam then P.shot=nil; P.failure="Battle Art portrait camera unavailable"; return end

    local terrain,nbMesh,water,nbWater,ready=VS.prefetch(world)
    if not (ready and terrain) then
      P.shot=nil; P.failure="Battle Art lower-level terrain not ready"; return
    end

    local rw,rh=320,180
    local vw,vh=160,90
    local viewState=copyState(world,arena,vw,vh)
    P.battleArtViewState=viewState

    local function atlasFor(m)
      local colors=type(VS._modeColors)=="function" and VS._modeColors(nil,m) or nil
      return TA.forMap(m,colors)
    end

    local g=love and love.graphics or nil
    if not g then P.shot=nil; P.failure="Battle Art graphics unavailable"; return end
    local unpack_=table.unpack or unpack
    local prevCanvas={}
    if type(g.getCanvas)=="function" then prevCanvas={g.getCanvas()} end
    local prevShader=type(g.getShader)=="function" and g.getShader() or nil
    local br,ba=type(g.getBlendMode)=="function" and g.getBlendMode() or "alpha",nil
    if type(g.getBlendMode)=="function" then br,ba=g.getBlendMode() end
    local cr,cg,cb,ca=1,1,1,1
    if type(g.getColor)=="function" then cr,cg,cb,ca=g.getColor() end
    local dm,dw=nil,nil
    if type(g.getDepthMode)=="function" then dm,dw=g.getDepthMode() end
    local cull=type(g.getMeshCullMode)=="function" and g.getMeshCullMode() or nil

    local oldCamera=V3.camera
    local oldTint=V3.tint
    local oldGlassMask,oldGlassNight=V3.glassMask,V3.glassNight
    local oldGlassPhase,oldGlassGlint=V3.glassPhase,V3.glassGlint
    local oldShadowAlpha=V3.SHADOW_ALPHA
    local canvas=nil
    local actorDrawn=false

    local okRender,errRender=pcall(function()
      V3.camera=cam
      local sky=type(VS.skyColor)=="function" and VS.skyColor(map,1) or nil
      if not V3.beginScene(rw,rh,arena.mid[1],arena.mid[2],vw,vh,sky,
          "bc_secondary_battle_art_world") then
        error("beginScene declined",0)
      end
      V3.draw(terrain,atlasFor(map),nil)
      for i,nb in ipairs(world.neighbors or {}) do
        local mesh=nbMesh and nbMesh[i] or nil
        if mesh and nb and nb.map then
          V3.draw(mesh,atlasFor(nb.map),M4.translate(nb.ox or 0,0,nb.oy or 0))
        end
      end
      if water then V3.draw(water,atlasFor(map),nil) end
      for i,nb in ipairs(world.neighbors or {}) do
        local mesh=nbWater and nbWater[i] or nil
        if mesh and nb and nb.map then
          V3.draw(mesh,atlasFor(nb.map),M4.translate(nb.ox or 0,0,nb.oy or 0))
        end
      end

      if importerActor then
        local renderer=importerActor.renderer
        if not (renderer and type(renderer.worldMetrics)=="function"
            and type(renderer.drawScene)=="function") then
          error("Importer actor renderer unavailable",0)
        end
        local okM,metrics=pcall(renderer.worldMetrics,renderer)
        local height=okM and metrics and tonumber(metrics.height) or nil
        if not (height and height>1e-4) then error("Importer actor metrics unavailable",0) end

        local okIR,IR=pcall(require,"mods.STADIUM2_IMPORTER.lib.renderer")
        if not (okIR and type(IR)=="table" and type(IR.matMul)=="function"
            and type(IR.lookAt)=="function" and type(IR.normalMatrix)=="function") then
          error("Importer shared-scene renderer API unavailable",0)
        end

        -- Exact Importer classic presentation scale/hover, but placed at the
        -- Battle Art voxel arena's player anchor and facing its enemy anchor.
        local worldH=math.max(5,math.min(18,14*math.sqrt(height/52.25)))
        local grow=type(importerActor.scale)=="function" and importerActor:scale() or 1
        grow=math.max(0,math.min(1,tonumber(grow) or 1))
        local k=worldH/height*grow
        local floor=tonumber(metrics.floor) or 0
        local hover=math.min(math.max(floor,0),height*0.5)
        local yaw=math.atan2(exx-px,ezz-pz)
        local model=M4.mul(M4.translate(px,groundY,pz),
          M4.mul(M4.rotateY(yaw),
            M4.mul(M4.scale(k,k,k),M4.translate(0,-(floor-hover),0))))
        local viewMatrix=IR.lookAt(cam.eye[1],cam.eye[2],cam.eye[3],
          cam.focus[1],cam.focus[2],cam.focus[3])
        local tint=V3.tint or {1,1,1}
        local ctx={
          viewProjection=V3.vp,
          viewMatrix=viewMatrix,
          normalMatrix=IR.normalMatrix(yaw,0,false),
          lightDir={0.35,0.7,0.62},ambient={0.46,0.46,0.46},
          diffuse={0.72,0.72,0.72},flipWinding=true,disableCulling=true,
          tint={tint[1] or 1,tint[2] or 1,tint[3] or 1,1},flashAmount=0,
        }
        for _,pass in ipairs({"opaque","additive"}) do
          local okD,a,b=pcall(renderer.drawScene,renderer,pass,model,ctx)
          if not okD then error("Importer actor draw error: "..tostring(a),0) end
          if a==false then error("Importer actor draw rejected: "..tostring(b),0) end
        end
        actorDrawn=true
      else
        -- EXACT accepted Rebase37 2D actor contract.
        local iw,ih=dims(img)
        local mesh=BB.mesh()
        if not (iw and ih and iw>0 and ih>0 and mesh) then
          error("fixed FRONT dimensions unavailable",0)
        end
        local norm=56/math.max(iw,ih)
        local worldPerPixel=(tonumber(BB.FULL_W) or 16)/(tonumber(BB.FULL_PIC) or 56)
        local cardScale=worldPerPixel*norm*0.58
        local cw,ch=iw*cardScale,ih*cardScale
        local yaw=BB.yawToward(px,pz,V3.eye)
        local mirror=(mod.options:get("secondaryViewSide") or "left")=="left"
        local sx=mirror and -cw or cw
        local model=M4.mul(M4.mul(M4.translate(px,groundY,pz),M4.rotateY(yaw)),
          M4.scale(sx,ch,1))
        if type(V3.seams)=="function" then V3.seams(false) end
        if type(V3.glass)=="function" then V3.glass(false) end
        if type(V3.lighting)=="function" then V3.lighting(false) end
        V3.draw(mesh,img,model,tonumber(BB.PULL) or 1.5)
        if type(V3.lighting)=="function" then V3.lighting(true) end
        if type(V3.glass)=="function" then V3.glass(true) end
        if type(V3.seams)=="function" then V3.seams(true) end
        actorDrawn=true
      end
      canvas=V3.endScene()
    end)

    V3.camera=oldCamera
    V3.tint=oldTint
    V3.glassMask,V3.glassNight=oldGlassMask,oldGlassNight
    V3.glassPhase,V3.glassGlint=oldGlassPhase,oldGlassGlint
    V3.SHADOW_ALPHA=oldShadowAlpha
    pcall(function()
      if #prevCanvas>0 then g.setCanvas(unpack_(prevCanvas)) else g.setCanvas() end
      if type(g.setShader)=="function" then g.setShader(prevShader) end
      if type(g.setDepthMode)=="function" then
        if dm then g.setDepthMode(dm,dw) else g.setDepthMode() end
      end
      if cull and type(g.setMeshCullMode)=="function" then g.setMeshCullMode(cull) end
      if type(g.setBlendMode)=="function" then
        if ba~=nil then g.setBlendMode(br,ba) else g.setBlendMode(br) end
      end
      g.setColor(cr,cg,cb,ca)
    end)

    if okRender and canvas and actorDrawn then
      P.shot={canvas=canvas}; P.failure=nil; P.actorMode=actorMode
      P.frames=(P.frames or 0)+1
      P.battleArtLastSource=source
    else
      P.shot=nil
      P.failure="Battle Art Rebase38 lower-level render error: "..tostring(errRender)
    end
  end

  mod.log:warn("[SECONDARY VIEW] Battle Art flat + Stadium2 Importer 3D adapter armed")
end)()

state.secondaryViewProbe.renderFrame=function()
  local P=state.secondaryViewProbe; P.renderFrameCalls=(P.renderFrameCalls or 0)+1
  if not (P.installed and P.backend and P.eligible(P.backend)) then P.shot=nil; return end
  P.eligibleFrames=(P.eligibleFrames or 0)+1
  local world=P.arenaProvider and P.arenaProvider.state or nil
  if not (world and world.map) then P.shot=nil; P.failure="Dramaless voxel arena not active"; return end
  local okArena,arena=pcall(P.arenaProvider.arena,P.arenaProvider,{services={}})
  if not (okArena and type(arena)=="table") then P.shot=nil; P.failure="Dramaless arena unavailable: "..tostring(arena); return end

  -- Actor-provider arbitration. Stadium2 Importer's public scene-neutral model
  -- API is the maintained premier Stadium source and therefore resolves first.
  -- SBFX remains legacy compatibility; sprites remain the universal fallback.
  local actorMode=nil
  if type(P.resolveS2Actor)=="function" then
    local okS2,value=pcall(P.resolveS2Actor)
    if okS2 and value then actorMode="stadium2_importer" end
  end
  local sbfxShowing=false
  if not actorMode and P.diagSB and P.diagMP and P.diagMA and P.battles then
    local okResolve,provider,entry=pcall(P.battles.resolve,P.battles,"models")
    if okResolve and provider==P.modelProvider and type(P.modelProvider.showing)=="function" then
      local okShow,value=pcall(P.modelProvider.showing,P.modelProvider,nil,"player")
      sbfxShowing=okShow and value and true or false
      if sbfxShowing then actorMode="sbfx" end
    end
  end
  local spriteSource=state.secondarySpriteSource
  if not actorMode and type(spriteSource)=="table" and type(spriteSource.drawPlayer)=="function" then actorMode="sprite" end
  if not actorMode then
    P.shot=nil; P.failure=P.s2Failure or (sbfxShowing and "secondary actor unavailable" or "no compatible Secondary View actor provider")
    return
  end

  local cam,pitch=P.cameraFor(P.backend,arena,0,actorMode)
  if not cam then P.shot=nil; P.failure="no portrait camera"; return end

  P.renderAttempts=(P.renderAttempts or 0)+1
  local V3,AA=P.Voxel3D,P.AntiAlias; local oldBegin,oldResolve=V3.beginScene,AA.resolve
  V3.beginScene=function(rw,rh,cx,cy,vw,vh,sky,slot) if slot=="battle" then slot="bc_secondary_view" end; return oldBegin(rw,rh,cx,cy,vw,vh,sky,slot) end
  AA.resolve=function(canvas,w,h,slot,...) if slot=="battle" then slot="bc_secondary_view" end; return oldResolve(canvas,w,h,slot,...) end
  local actorErr=nil
  local function drawActors(view)
    if not (view and type(view.vp)=="table") then actorErr="secondary world supplied no VP"; return end
    if tonumber(view.groundY) then
      local nextCam,nextPitch=P.cameraFor(P.backend,arena,view.groundY,actorMode)
      if nextCam then cam,pitch=nextCam,nextPitch end
    end
    if actorMode=="stadium2_importer" then
      local okDraw,value=pcall(P.drawS2Actor,view,arena,tonumber(view.groundY) or 0,cam)
      if not okDraw then actorErr="Stadium2 Importer model draw error: "..tostring(value)
      elseif not value then actorErr=P.s2Failure or "Stadium2 Importer model unavailable" end
    elseif actorMode=="sbfx" then
      local okDraw,a,b=pcall(P.modelsApi.withRenderer,view.vp,function()
        P.modelProvider:drawWorld(nil,0)
        return true
      end)
      if not okDraw then actorErr="SBFX live-model draw error: "..tostring(a)
      elseif not a then actorErr="SBFX Stadium renderer rejected: "..tostring(b) end
    else
      local okDraw,value=pcall(spriteSource.drawPlayer,view,arena,tonumber(view.groundY) or 0,cam)
      if not okDraw then actorErr="2D portrait draw error: "..tostring(value)
      elseif not value then actorErr="2D portrait source unavailable" end
    end
    if not actorErr then P.actorDraws=(P.actorDraws or 0)+1 end
  end
  P.camera,P.pitch=cam,pitch; P.rendering=true; P.actorMode=actorMode
  local ok,canvas=pcall(P.Scene.render,world,arena,drawActors,{pose=cam,pitch=pitch})
  P.rendering=false; P.camera=nil; P.pitch=nil
  V3.beginScene=oldBegin; AA.resolve=oldResolve
  if actorErr then P.shot=nil; P.failure=actorErr
  elseif ok and canvas then
    P.shot={canvas=canvas}; P.failure=nil; P.frames=(P.frames or 0)+1
    if P.lastLoggedActorMode~=actorMode then
      P.lastLoggedActorMode=actorMode
      local label=(actorMode=="stadium2_importer" and "Stadium2 Importer scene-neutral model")
        or (actorMode=="sbfx" and "SBFX Stadium models")
        or "Dramaless/native 2D player portrait"
      mod.log:warn("[SECONDARY VIEW] live actor path: %s",label)
    end
  else P.shot=nil; P.failure=ok and ("render returned "..tostring(canvas)) or ("render error: "..tostring(canvas)) end
end

state.secondaryViewProbe.fixedStep=function()
  local P=state.secondaryViewProbe; if not P then return end; P.fixedStepCalls=(P.fixedStepCalls or 0)+1

  -- Gold Stadium2 Importer owns a complete Stadium scene, so it does not need
  -- the Gen1 Dramaless world seam. Keep the same conservative ~10 fps cadence.
  if type(P.goldImporterEligible)=="function" and P.goldImporterEligible() then
    P.status="eligible / Secondary View / Gold Stadium2 Importer live scene"
    P.accum=(tonumber(P.accum) or 0)+1/60
    if P.accum<0.10 and P.shot then return end
    P.accum=0
    return P.renderGoldImporterFrame()
  end
  -- Rebase28: Randy's alternate-eye renderer returns nil on a fresh pass until
  -- its terrain cache is prefetched.  Warm that provider-owned cache while BC
  -- is still suppressing PiP during the fast Gen2 Intro/Send-In lifecycle, so
  -- the first eligible idle/menu frame does not pay the cold-start delay.
  if type(P.warmRandyScene)=="function" then pcall(P.warmRandyScene) end
  if type(P.randyEligible)=="function" and P.randyEligible() then
    P.status="eligible / Secondary View / Randy live world + "..tostring(P.actorMode or "actor scan")
    -- Rebase30: Randy's VoxelScene is a live graphics pass.  Keep the accepted
    -- ~10 fps scheduler here, but only MARK a render due; the actual private
    -- alternate-eye draw runs from render.hud where LOVE/Randy are already in
    -- a graphics context.  Importer/Dramaless retain their proven fixed-step
    -- renderer paths.
    P.accum=(tonumber(P.accum) or 0)+1/60
    if (not P.shot) or P.accum>=0.10 then
      P.randyRenderDue=true
      P.accum=0
    end
    return
  end

  -- Rebase39 Voxel Ascendant public VoxelScene alternate-camera pass renders
  -- from render.hud. Keep the accepted ~10 fps scheduler here and preserve
  -- the last good canvas between due frames.
  if type(P.voxelAscendantEligible)=="function" and P.voxelAscendantEligible() then
    P.status="eligible / Secondary View / Voxel Ascendant public MAP world"
    P.accum=(tonumber(P.accum) or 0)+1/60
    if (not P.shot) or P.accum>=0.10 then
      P.voxelAscendantRenderDue=true
      P.accum=0
    end
    return
  end

  -- Rebase38 Battle Art private world renders from render.hud only. Keep the
  -- fixed-step director from clearing its last good canvas while Battle Art is
  -- the active proven eligibility seam.
  if type(P.battleArtEligible)=="function" and P.battleArtEligible() then
    P.status="eligible / Secondary View / Battle Art lower-level world"
    return
  end

  -- Rebase58 base Dramatic: never perform the second 3D world render from the
  -- fixed-step/update seam. 1.6.x predates the newer draw-safe provider paths
  -- and a private Voxel/BattleScene pass here stalls simulation/input on Android.
  -- Fixed-step only schedules a conservative ~6.7 fps PiP refresh; render.hud
  -- performs the graphics work in an actual draw context and preserves the last
  -- good canvas between refreshes.
  if type(P.dramaticEligible)=="function" and P.dramaticEligible() then
    P.status="eligible / Secondary View / Dramatic draw-scheduled world"
    P.accum=(tonumber(P.accum) or 0)+1/60
    if not P.drag and ((not P.shot) or P.accum>=0.15) then
      P.dramaticRenderDue=true
      P.accum=0
    end
    return
  end

  -- Rebase52 PotatoVoxel: its own OverworldBattle.update deliberately renders
  -- the staged BattleScene from update time with no caller canvas bound. Mirror
  -- that provider-safe timing for the private Secondary View, throttled to the
  -- established ~10 fps cadence. The private render uses its own canvas slots,
  -- so it cannot overwrite Potato's main staged shot.
  if type(P.potatoEligible)=="function" and P.potatoEligible() then
    P.status="eligible / Secondary View / PotatoVoxel staged world"
    P.accum=(tonumber(P.accum) or 0)+1/60
    if P.accum<0.10 and P.shot then return end
    P.accum=0
    if type(P.renderPotatoFrame)=="function" then return P.renderPotatoFrame() end
    P.shot=nil; P.failure="PotatoVoxel Secondary View renderer unavailable"
    return
  end

  if not P.installed then P.status="fixed-step alive / seam blocked"; P.shot=nil; return end
  if not P.eligible(P.backend) then P.status="fixed-step alive / not eligible"; P.shot=nil; P.accum=0; return end
  P.status="eligible / Secondary View / Dramaless world + "..tostring(P.actorMode or "actor scan"); P.accum=(tonumber(P.accum) or 0)+1/60
  if P.accum<0.10 and P.shot then return end; P.accum=0; P.renderFrame()
end

state.secondaryViewProbe.placementXY=function(sw,sh,targetW,targetH)
  local P=state.secondaryViewProbe
  -- While a pointer drag is active, draw from the live absolute top-left.
  if P and P.drag and P.drag.active and P.drag.x and P.drag.y then
    local maxX=math.max(0,sw-targetW)
    local maxY=math.max(0,sh-targetH)
    return math.max(0,math.min(maxX,P.drag.x)),math.max(0,math.min(maxY,P.drag.y))
  end

  local mode=mod.options:get("secondaryViewPlace") or "mid_right"
  if mode=="custom" then
    local nx=math.max(0,math.min(1000,tonumber(mod.options:get("secondaryViewCustomX")) or 500))/1000
    local ny=math.max(0,math.min(1000,tonumber(mod.options:get("secondaryViewCustomY")) or 220))/1000
    return math.floor(math.max(0,sw-targetW)*nx+0.5),
           math.floor(math.max(0,sh-targetH)*ny+0.5)
  end

  -- "MID" means the DW3-inspired middle band, but kept above the stock white
  -- battle UI. Its bottom edge targets ~65% of screen height instead of true
  -- vertical centre, which overlapped the command box in Rebase 3.
  local midY=math.max(12,math.floor(sh*0.65-targetH-8))
  local y=(mode=="mid_right" or mode=="mid_left" or mode=="mid_center") and midY or 12
  if mode=="top_left" or mode=="mid_left" then return 12,y end
  if mode=="mid_center" then return math.floor((sw-targetW)*0.5),y end
  if mode=="mid_right" then return sw-targetW-12,y end
  return sw-targetW-12,12
end

state.secondaryViewProbe.draw=function()
  local P=state.secondaryViewProbe
  if not (P and love and love.graphics) then
    if P then P.lastRect=nil end
    return
  end
  -- Rebase26: the compositor is shared by two independently proven renderer
  -- seams. Gen1 Dramaless uses P.backend/P.eligible; Gold/Silver Stadium2
  -- Importer bypasses that world seam and uses its own live-scene eligibility.
  -- Do not require the Gen1 backend in order to display an already-rendered
  -- Gold Importer Secondary View shot.
  local worldEligible=P.backend and P.eligible(P.backend) or false
  local goldEligible=type(P.goldImporterEligible)=="function" and P.goldImporterEligible() or false
  local randyEligible=type(P.randyEligible)=="function" and P.randyEligible() or false
  local voxelAscendantEligible=type(P.voxelAscendantEligible)=="function" and P.voxelAscendantEligible() or false
  local battleArtEligible=type(P.battleArtEligible)=="function" and P.battleArtEligible() or false
  local potatoEligible=type(P.potatoEligible)=="function" and P.potatoEligible() or false
  local dramaticEligible=type(P.dramaticEligible)=="function" and P.dramaticEligible() or false
  if not (worldEligible or goldEligible or randyEligible or voxelAscendantEligible or battleArtEligible or potatoEligible or dramaticEligible) then
    P.lastRect=nil
    return
  end
  local g=love.graphics

  -- Rebase30: Randy's provider-native VoxelScene alternate-eye renderer must
  -- execute from a DRAW seam.  Rebase27-29 invoked it from BattleState.update;
  -- terrain prefetch could succeed there, but VoxelScene.render kept returning
  -- nil before either the 3D Stadium actor or 2D card could be submitted.
  --
  -- Preserve the HUD's current render target around Randy's pass because
  -- Voxel3D.endScene intentionally unbinds its own canvas.  The provider's
  -- internal camera/world/card state is restored by renderRandyFrame itself.
  -- Rebase39 Voxel Ascendant uses its published VoxelScene/Voxel3D facade and
  -- therefore also executes from a real draw context. Its fixed-step path only
  -- marks frames due.
  if voxelAscendantEligible and (P.voxelAscendantRenderDue or not P.shot)
      and type(P.renderVoxelAscendantFrame)=="function" then
    P.voxelAscendantRenderDue=false
    local okVA,errVA=pcall(P.renderVoxelAscendantFrame)
    if not okVA then
      P.shot=nil; P.failure="Voxel Ascendant MAP draw-context error: "..tostring(errVA)
    end
  end

  -- Rebase38 Battle Art world: render only from this draw seam and throttle
  -- independently of the main staged battle. No provider ownership transfer.
  if battleArtEligible and type(P.renderBattleArtFrame)=="function" then
    local now=((love and love.timer and love.timer.getTime)
      and love.timer.getTime() or os.clock())
    local last=tonumber(P.battleArtLastRender) or -1e9
    if (not P.shot) or now-last>=0.10 then
      P.battleArtLastRender=now
      local okBA,errBA=pcall(P.renderBattleArtFrame)
      if not okBA then
        P.shot=nil; P.failure="Battle Art Rebase38 draw-context error: "..tostring(errBA)
      end
    end
  end

  -- Rebase58 Dramatic 1.6.x: execute the private Secondary View render only
  -- from this HUD/draw seam. Preserve the caller's graphics state/canvas around
  -- the provider pass; older Dramatic was not designed to render a second scene
  -- from BattleState.update, and doing so caused gameplay/input stalls on Android.
  if dramaticEligible and not P.drag and (P.dramaticRenderDue or not P.shot)
      and type(P.renderDramaticFrame)=="function" then
    P.dramaticRenderDue=false
    local prevCanvas={}
    if type(g.getCanvas)=="function" then
      local okPrev,a,b,c,d=pcall(g.getCanvas)
      if okPrev and a~=nil then prevCanvas={a,b,c,d} end
    end
    local pushed=false
    if type(g.push)=="function" then pushed=pcall(g.push,"all") end
    local okDR,errDR=pcall(P.renderDramaticFrame)
    if pushed and type(g.pop)=="function" then pcall(g.pop) end
    if #prevCanvas>0 then pcall(g.setCanvas,(table.unpack or unpack)(prevCanvas))
    else pcall(g.setCanvas) end
    if not okDR then
      P.shot=nil; P.failure="Dramatic draw-context error: "..tostring(errDR)
    end
  end

  if randyEligible and (P.randyRenderDue or not P.shot) then
    P.randyRenderDue=false
    local prevCanvas=nil
    if type(g.getCanvas)=="function" then
      local okPrev,value=pcall(g.getCanvas)
      if okPrev then prevCanvas=value end
    end
    local okRender,errRender=pcall(P.renderRandyFrame)
    if prevCanvas~=nil then pcall(g.setCanvas,prevCanvas)
    else pcall(g.setCanvas) end
    if not okRender then
      P.shot=nil
      P.failure="Randy Secondary View draw-context error: "..tostring(errRender)
    end
  end
  local pushed=false
  local ok,err=pcall(function()
    local sw,sh=g.getDimensions(); local sizeMode=mod.options:get("secondaryViewSize") or "standard"; local frac=(sizeMode=="small") and 0.20 or 0.27; local minW=(sizeMode=="small") and 132 or 180; local targetW=math.max(minW,math.floor(sw*frac)); local targetH=math.min(sh*0.34,targetW*9/16); local x,y=P.placementXY(sw,sh,targetW,targetH)
    P.lastRect={x=x-6,y=y-6,w=targetW+12,h=targetH+12,sw=sw,sh=sh,targetW=targetW,targetH=targetH}
    g.push("all"); pushed=true; g.origin(); g.setBlendMode("alpha"); g.setColor(0,0,0,0.78); g.rectangle("fill",x-6,y-6,targetW+12,targetH+12,5,5)
    local canvas=P.shot and P.shot.canvas or nil
    if canvas then local cw,ch=canvas:getDimensions(); g.setColor(1,1,1,1); g.draw(canvas,x,y,0,targetW/cw,targetH/ch)
    else
      g.setColor(1,1,1,0.23); g.rectangle("fill",x,y,targetW,targetH); g.setColor(1,1,1,1); g.setLineWidth(4); g.line(x+12,y+12,x+targetW-12,y+targetH-12); g.line(x+targetW-12,y+12,x+12,y+targetH-12)
      local flags=("SC:%s V3:%s AA:%s AR:%s CARD:%s SB:%s"):format(P.diagScene and "Y" or "N",P.diagV3 and "Y" or "N",P.diagAA and "Y" or "N",P.diagArena and "Y" or "N",P.diagCard and "Y" or "N",P.diagSB and "Y" or "N")
      local counts=("FIX:%d RF:%d EL:%d TRY:%d ACT:%d"):format(P.fixedStepCalls or 0,P.renderFrameCalls or 0,P.eligibleFrames or 0,P.renderAttempts or 0,P.actorDraws or 0)
      g.print(tostring(P.failure or P.status),x+8,y+6,0,0.50,0.50); g.print(flags,x+8,y+21,0,0.43,0.43); g.print(counts,x+8,y+35,0,0.43,0.43); g.print("DR:"..tostring(P.diagVersion or "?").." ACT:"..tostring(P.actorMode or "?").." SBFX:"..tostring(P.sbfxVersion or "?"),x+8,y+49,0,0.43,0.43)
    end
    g.setColor(1,1,1,1); g.setLineWidth(3); g.rectangle("line",x-3,y-3,targetW+6,targetH+6,4,4)
  end)
  -- Always restore graphics state, including error paths. The old pcall could
  -- swallow an exception after push("all") and leave later UI draws transformed.
  if pushed then pcall(g.pop) end
  g.setColor(1,1,1,1)
  if not ok then
    P.failure="PiP draw error: "..tostring(err)
    mod.log:warn("Secondary View compositor draw failed: %s",tostring(err))
  end
end

-- Direct Secondary View placement ------------------------------------------------
-- Current Recomp exposes uncaptured touch/mouse input through input.pointer.
-- TouchControls keeps first refusal, so dragging the PiP cannot steal a press
-- that began on the virtual D-pad / A / B / Start / Select controls.
do
  local P=state.secondaryViewProbe
  local okPointer=pcall(function()
    mod.hooks:wrap("input.pointer",function(nextFn,game,ev)
      local worldEligible=P and P.backend and P.eligible(P.backend) or false
      local goldEligible=P and type(P.goldImporterEligible)=="function" and P.goldImporterEligible() or false
      local randyEligible=P and type(P.randyEligible)=="function" and P.randyEligible() or false
      local voxelAscendantEligible=P and type(P.voxelAscendantEligible)=="function" and P.voxelAscendantEligible() or false
      local battleArtEligible=P and type(P.battleArtEligible)=="function" and P.battleArtEligible() or false
      local potatoEligible=P and type(P.potatoEligible)=="function" and P.potatoEligible() or false
      local dramaticEligible=P and type(P.dramaticEligible)=="function" and P.dramaticEligible() or false
      if not (P and ev and P.lastRect and (worldEligible or goldEligible or randyEligible or voxelAscendantEligible or battleArtEligible or potatoEligible or dramaticEligible)) then
        return nextFn(game,ev)
      end

      local d=P.drag
      local id=ev.id
      if ev.phase=="pressed" then
        local r=P.lastRect
        local x,y=tonumber(ev.x),tonumber(ev.y)
        if x and y and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then
          P.drag={
            id=id, startX=x, startY=y, pointerX=x, pointerY=y,
            originX=r.x+6, originY=r.y+6,
            offsetX=x-(r.x+6), offsetY=y-(r.y+6),
            x=r.x+6, y=r.y+6, active=false
          }
          return true
        end
      elseif d and d.id==id then
        if ev.phase=="moved" then
          local x,y=tonumber(ev.x) or d.pointerX,tonumber(ev.y) or d.pointerY
          d.pointerX,d.pointerY=x,y
          if not d.active then
            local dx,dy=x-d.startX,y-d.startY
            if dx*dx+dy*dy>=16 then d.active=true end
          end
          if d.active then
            local r=P.lastRect
            local maxX=math.max(0,(r.sw or 0)-(r.targetW or 0))
            local maxY=math.max(0,(r.sh or 0)-(r.targetH or 0))
            d.x=math.max(0,math.min(maxX,x-d.offsetX))
            d.y=math.max(0,math.min(maxY,y-d.offsetY))
          end
          return true
        elseif ev.phase=="released" or ev.phase=="cancelled" then
          if ev.phase=="released" and d.active then
            local r=P.lastRect
            local maxX=math.max(1,(r.sw or 1)-(r.targetW or 0))
            local maxY=math.max(1,(r.sh or 1)-(r.targetH or 0))
            local nx=math.floor(math.max(0,math.min(1,(d.x or 0)/maxX))*1000+0.5)
            local ny=math.floor(math.max(0,math.min(1,(d.y or 0)/maxY))*1000+0.5)
            local set=P.setOption
            if type(set)=="function" then
              set(game,"secondaryViewCustomX",nx)
              set(game,"secondaryViewCustomY",ny)
              set(game,"secondaryViewPlace","custom")
            end
          end
          P.drag=nil
          return true
        end
      end
      return nextFn(game,ev)
    end)
  end)
  if okPointer then
    mod.log:info("Secondary View direct-drag placement attached through input.pointer")
  else
    mod.log:warn("Secondary View direct-drag unavailable on this Recomp build; placement presets remain supported")
  end
end

-- Rebase58 Dramatic 1.6.x legacy-touch bridge -----------------------------------
-- Dramatic 1.6.x predates input.pointer and wraps Game.touchpressed/moved/released
-- directly for battle-camera drags. On Android that legacy wrapper can claim an
-- open-screen finger before the newer pointer chain ever delivers BC a complete
-- press/move/release gesture. Install a Dramatic-only outer Game touch wrapper so
-- a gesture that BEGINS inside the PiP belongs to the PiP; all other touches pass
-- through untouched to Dramatic/TouchControls. This is Game-level API 2-safe input
-- handling, not a global love.* callback.
do
  local P=state.secondaryViewProbe
  local okGame,Game=pcall(require,"src.core.Game")
  if okGame and type(Game)=="table" and P and not Game.__bcSecondaryViewDramaticTouchDrag then
    local function eligible()
      return type(P.dramaticEligible)=="function" and P.dramaticEligible()
    end
    local function beginDrag(id,x,y)
      if not (eligible() and P.lastRect) then return false end
      x,y=tonumber(x),tonumber(y)
      local r=P.lastRect
      if not (x and y and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h) then return false end
      P.drag={
        id=id,startX=x,startY=y,pointerX=x,pointerY=y,
        originX=r.x+6,originY=r.y+6,
        offsetX=x-(r.x+6),offsetY=y-(r.y+6),
        x=r.x+6,y=r.y+6,active=false,legacyDramatic=true
      }
      return true
    end
    local function moveDrag(id,x,y)
      local d=P.drag
      if not (d and d.id==id and d.legacyDramatic) then return false end
      x,y=tonumber(x) or d.pointerX,tonumber(y) or d.pointerY
      d.pointerX,d.pointerY=x,y
      if not d.active then
        local dx,dy=x-d.startX,y-d.startY
        if dx*dx+dy*dy>=16 then d.active=true end
      end
      if d.active and P.lastRect then
        local r=P.lastRect
        local maxX=math.max(0,(r.sw or 0)-(r.targetW or 0))
        local maxY=math.max(0,(r.sh or 0)-(r.targetH or 0))
        d.x=math.max(0,math.min(maxX,x-d.offsetX))
        d.y=math.max(0,math.min(maxY,y-d.offsetY))
      end
      return true
    end
    local function endDrag(game,id,released)
      local d=P.drag
      if not (d and d.id==id and d.legacyDramatic) then return false end
      if released and d.active and P.lastRect then
        local r=P.lastRect
        local maxX=math.max(1,(r.sw or 1)-(r.targetW or 0))
        local maxY=math.max(1,(r.sh or 1)-(r.targetH or 0))
        local nx=math.floor(math.max(0,math.min(1,(d.x or 0)/maxX))*1000+0.5)
        local ny=math.floor(math.max(0,math.min(1,(d.y or 0)/maxY))*1000+0.5)
        if type(P.setOption)=="function" then
          P.setOption(game,"secondaryViewCustomX",nx)
          P.setOption(game,"secondaryViewCustomY",ny)
          P.setOption(game,"secondaryViewPlace","custom")
        end
      end
      P.drag=nil
      return true
    end

    local pressed=Game.touchpressed
    if type(pressed)=="function" then
      Game.touchpressed=function(self,id,x,y,...)
        if beginDrag(id,x,y) then return true end
        return pressed(self,id,x,y,...)
      end
    end
    local moved=Game.touchmoved
    if type(moved)=="function" then
      Game.touchmoved=function(self,id,x,y,...)
        if moveDrag(id,x,y) then return true end
        return moved(self,id,x,y,...)
      end
    end
    local released=Game.touchreleased
    if type(released)=="function" then
      Game.touchreleased=function(self,id,x,y,...)
        if endDrag(self,id,true) then return true end
        return released(self,id,x,y,...)
      end
    end
    local focus=Game.focus
    if type(focus)=="function" then
      Game.focus=function(self,...)
        if P.drag and P.drag.legacyDramatic then P.drag=nil end
        return focus(self,...)
      end
    end
    Game.__bcSecondaryViewDramaticTouchDrag=true
    mod.log:info("Secondary View Dramatic legacy Game-touch drag bridge active")
  end
end

mod.hooks:wrap("render.hud",function(nextFn,game,viewport)
  local result=nextFn(game,viewport); state.secondaryViewProbe.draw(); return result
end)

-- Sprite Facing / Dual Actor Presentation -----------------------------------
-- Sprite Facing exposes one product surface across supported 2D-card hosts and
-- applies the same camera-relative semantics independently to BOTH battlers.
--
-- SPRITE FACING:
--   HOST DEFAULT - BC does not alter sprite representation or orientation.
--   TURN ONLY    - keep the host/provider's chosen front/back representation,
--                  but turn each world card left/right toward its opponent.
--   DYNAMIC      - camera chooses FRONT/BACK independently for each battler,
--                  while left/right turning still points each actor toward the
--                  opposing battler. Crystal keeps ownership of live front
--                  animation; Dramaless keeps ownership of world placement.
--
-- This remains a Dramaless adapter. Battle Art/3D hosts are deliberately not
-- consumed here; HOST DEFAULT is therefore a safe no-op everywhere else.
;(function()
  local handle=mod.find("DRAMALESS_SHAPE")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  local setting=V and V.backSpritesSetting or nil
  local provider=exports and exports.voxelCardProvider or nil
  if type(setting)~="table" or type(setting.get)~="function"
      or type(provider)~="table" then return end
  if provider.__bcSpriteFacingDualActorInstalled then return end

  local savedGet=setting.get
  local unpack_=table.unpack or unpack
  local depth=0
  local targetExtent=56
  do
    local okBB0,bb0=pcall(V.require,"BattleBillboard")
    if okBB0 and type(bb0)=="table" then
      local fp=tonumber(bb0.FULL_PIC)
      if fp and fp>0 then targetExtent=fp end
    end
  end

  local BattleState,Sprites,Assets,PaletteFX=nil,nil,nil,nil
  do
    local okBS,bs=pcall(require,"src.battle.BattleState")
    if okBS and type(bs)=="table" then BattleState=bs end
    local okSp,sp=pcall(require,"src.pokemon.Sprites")
    if okSp and type(sp)=="table" then Sprites=sp end
    local okAs,a=pcall(require,"src.render.Assets")
    if okAs and type(a)=="table" then Assets=a end
    local okPa,pal=pcall(require,"src.render.PaletteFX")
    if okPa and type(pal)=="table" then PaletteFX=pal end
  end

  local crystal=nil
  do
    local h=mod.find("crystal_animated_sprites_with_shiny_visuals")
    local ex=h and h.exports or nil
    if ex and type(ex.applyOption)=="function"
        and type(ex.frontPrefEnabled)=="function" then
      crystal={exports=ex,lastApplied=nil}
    end
  end

  local actor={
    player={side="back",turn="right",screenDelta=nil,scale=1,liveFront=nil,liveBack=nil,liveBackOwner=nil},
    enemy ={side="front",turn="left", screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
  }
  local battleRef=nil
  local contextRef=nil
  local imageCache={}
  local lastMode=nil
  local hudFont=nil
  -- Dramaless provider.update may run re-entrantly from inside BattleState.update.
  -- While BC is advancing Crystal's authoritative FRONT stream, do not let the
  -- main Dynamic presentation substitute FRONT/BACK into battler.sprite until
  -- that stream has been captured.
  local crystalFrontCaptureDepth=0

  local function dims(img)
    if img and type(img.getDimensions)=="function" then
      local ok,w,h=pcall(img.getDimensions,img)
      if ok then return tonumber(w),tonumber(h) end
    end
    return nil,nil
  end

  local function mode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v~="turn" and v~="dynamic" then return "host" end
    return v
  end

  local function active()
    return enabled() and selectedPreset()~="external" and mode()~="host"
  end

  local function dynamic()
    return active() and mode()=="dynamic"
  end

  local function hostBackEnabled()
    local ok,v=pcall(savedGet,setting)
    return ok and v and true or false
  end

  local function crystalPref()
    if not crystal then return nil end
    local ok,v=pcall(crystal.exports.frontPrefEnabled)
    if ok then return v and true or false end
    return nil
  end

  local function setCrystal(v)
    if not crystal then return false end
    local ok=pcall(crystal.exports.applyOption,"crystalFront",v and true or false)
    if ok then crystal.lastApplied=v and true or false end
    return ok
  end

  local function restoreCrystal(v)
    if crystal and v~=nil then setCrystal(v and true or false) end
  end

  local function resetBattle(battle)
    if battle==battleRef then return end
    battleRef=battle
    contextRef=nil
    imageCache={}
    actor.player.side,actor.player.turn="back","right"
    actor.enemy.side,actor.enemy.turn="front","left"
    for _,a in pairs(actor) do
      a.screenDelta=nil; a.scale=1; a.liveFront=nil; a.liveBack=nil
      if a==actor.player then a.liveBackOwner=nil end
    end
    if crystal then crystal.lastApplied=crystalPref() end
    lastMode=mode()
  end

  local function actorCell(arena,name)
    return arena and arena[name] or nil
  end

  local function updateActorOrientation(name,cell,other,cam)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    -- FRONT/BACK: actor forward is always actor -> opponent.
    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
    local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
    local fl=math.sqrt(fx*fx+fz*fz)
    local vl=math.sqrt(vx*vx+vz*vz)
    if fl>=0.001 and vl>=0.001 then
      local dot=(fx*vx+fz*vz)/(fl*vl)
      if a.side=="back" and dot>0.22 then a.side="front"
      elseif a.side=="front" and dot<(-0.22) then a.side="back" end
    end

    -- LEFT/RIGHT: use final-camera perspective screen ordering. Each actor asks
    -- on which side of itself the opposing actor appears.
    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(p)
          local dx=(tonumber(p[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(p[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
          return nil
        end
        local as=screenX(cell)
        local os=screenX(other)
        if as and os then screenDelta=os-as else screenDelta=fx*rx+fz*rz end
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation(context)
    contextRef=context or contextRef
    if not active() then return end
    local arena=context and context.arena or nil
    local p,e=actorCell(arena,"player"),actorCell(arena,"enemy")
    local cam=state.spriteFacingCamera
    if not (p and e and cam) then return end
    if dynamic() then
      updateActorOrientation("player",p,e,cam)
      updateActorOrientation("enemy",e,p,cam)
    else
      -- TURN ONLY keeps host/provider representation, but still derives an
      -- independent horizontal turn for each actor from the same final camera.
      local ps,es=actor.player.side,actor.enemy.side
      updateActorOrientation("player",p,e,cam)
      updateActorOrientation("enemy",e,p,cam)
      actor.player.side,actor.enemy.side=ps,es
    end
  end

  local function hostPlayerSide()
    if not hostBackEnabled() then return "front" end
    if crystal and crystalPref()==true then return "front" end
    return "back"
  end

  local function presentationSide(name)
    if mode()=="dynamic" then return actor[name].side end
    if name=="enemy" then return "front" end
    return hostPlayerSide()
  end

  local function temporarilyCrystalOff(fn)
    if not crystal then return fn() end
    local prior=crystalPref()
    if prior~=false then pcall(crystal.exports.applyOption,"crystalFront",false) end
    local r={pcall(fn)}
    if prior~=nil then pcall(crystal.exports.applyOption,"crystalFront",prior) end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  local function staticImage(context,name,side)
    local battle=context and context.battle or battleRef
    local battler=battle and battle[name] or nil
    local mon=battler and battler.mon or nil
    local species=mon and mon.species or nil
    if not (battle and species and Sprites and type(Sprites.path)=="function" and Assets) then return nil end

    local function resolve()
      local ok,path,tc=pcall(Sprites.path,battle.data,species,side,{mon=mon,kind="battle"})
      if not ok or type(path)~="string" or path=="" then return nil,nil end
      return path,tc
    end
    local path,tc
    if crystal and side=="back" then path,tc=temporarilyCrystalOff(resolve)
    else path,tc=resolve() end
    if not path then return nil end

    local palName="truecolor"
    if not tc and PaletteFX and type(PaletteFX.monPalName)=="function" then
      local okN,n=pcall(PaletteFX.monPalName,battle.data,species,false)
      if okN and n then palName=tostring(n) end
    end
    local key=table.concat({tostring(path),palName,name,side},"#")
    if imageCache[key] then return imageCache[key] end

    local img=nil
    if tc or not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
      local okI,v=pcall(Assets.image,path)
      if okI then img=v end
    else
      local okD,id=pcall(Assets.imageData,path)
      if okD and id then
        local pal=PaletteFX and type(PaletteFX.monPal)=="function"
          and PaletteFX.monPal(battle.data,species,false) or nil
        if pal then
          local c=pal
          pcall(id.mapPixel,id,function(_,_,r,g,b,a)
            if a==0 then return r,g,b,a end
            local col=r>0.83 and c[1] or r>0.5 and c[2] or r>0.17 and c[3] or c[4]
            return col[1]/255,col[2]/255,col[3]/255,a
          end)
        end
        local okI,v=pcall(love.graphics.newImage,id)
        if okI then img=v end
      end
    end
    if img and type(img.setFilter)=="function" then pcall(img.setFilter,img,"nearest","nearest") end
    imageCache[key]=img
    return img,displayScale
  end

  local function captureProviderLives(battle,frontAuthoritative)
    if not battle then return end
    if crystal then
      local p=battle.player
      local e=battle.enemy
      -- v1.2.0 RC1 Dramaless Crystal ownership correction: battle.player.sprite
      -- is a mutable presentation field. The main Dynamic camera may borrow a
      -- BACK image while Crystal's animation marker remains attached, so that
      -- field is not by itself proof of FRONT semantics. Only the exact
      -- BattleState.update window where BC explicitly enabled Crystal FRONT may
      -- advance the cached player FRONT used by Secondary View. This is the
      -- same provider-state ownership rule already runtime-proven on Potato.
      if frontAuthoritative==true and p and p.__crystalAnimation and p.sprite then
        actor.player.liveFront=p.sprite
      end
      if e and e.__crystalAnimation and e.sprite then actor.enemy.liveFront=e.sprite end
      if not actor.player.liveBack and hostBackEnabled() and crystalPref()==false
          and p and p.sprite and not p.__crystalAnimation then
        actor.player.liveBack=p.sprite
        actor.player.liveBackOwner=p
      end
    end
  end

  local function applySelectedRepresentations(context)
    if not active() then return end
    local battle=context and context.battle or battleRef
    if not battle then return end

    if battle.player and not battle.safari and not battle.demo
        and not battle.showPlayerBack and not battle.sendingOut then
      local side=presentationSide("player")
      local img=nil
      if crystal and side=="front" and (dynamic() or crystalPref()==true) then
        img=actor.player.liveFront
      elseif crystal and side=="back" then
        -- Crystal's FRONT animator is kept alive under DYNAMIC by temporarily
        -- enabling its crystalFront preference around BattleState.update. A
        -- player switch is executed *inside* that update, so the engine can
        -- construct the replacement battler while Crystal is transiently in
        -- FRONT mode. Never let a BACK cache outlive the battler it belongs to:
        -- resolve the current battler's provider-owned BACK art on an owner
        -- mismatch and bind that image to this exact battler instance.
        if actor.player.liveBackOwner~=battle.player then
          actor.player.liveBack=staticImage({battle=battle},"player","back")
          actor.player.liveBackOwner=actor.player.liveBack and battle.player or nil
        end
        img=actor.player.liveBack or staticImage({battle=battle},"player","back")
      else
        img=staticImage(context,"player",side)
      end
      if img then battle.player.sprite=img end
    end

    if battle.enemy and not battle.showEnemyTrainer and not battle.enemySendingOut then
      local side=presentationSide("enemy")
      local img=(crystal and side=="front" and actor.enemy.liveFront) or staticImage(context,"enemy",side)
      if img then battle.enemy.sprite=img end
    end
  end

  -- Crystal switch lifecycle repair. BC deliberately turns Crystal FRONT on
  -- only while Crystal's own Gen1 animator advances, but Gen1Recomp also
  -- replaces `battle.player` from inside that same BattleState.update when a
  -- party switch completes. The replacement's canonical BACK must therefore be
  -- captured from the new battler identity with Crystal temporarily restored to
  -- BACK resolution; otherwise the lead battler's cached back can survive the
  -- switch. `battle.battler_switched` is the engine's authoritative lifecycle
  -- seam for voluntary, forced and SHIFT replacements, so no species guessing
  -- or polling is needed here.
  if crystal then
    mod.events:on("battle.battler_switched",function(ev)
      if not dynamic() then return end
      local battle=ev and ev.battle or nil
      local side=ev and ev.side and ev.side.index or nil
      if side~=1 or not battle or battle~=battleRef then return end
      local battler=ev.battler or battle.player
      if not battler or battler~=battle.player then return end

      -- Drop both live identities immediately. Crystal's wrapped update will
      -- repopulate liveFront for the new species before this frame returns.
      actor.player.liveFront=nil
      actor.player.liveBack=nil
      actor.player.liveBackOwner=nil

      -- staticImage("back") already uses temporarilyCrystalOff(), so even
      -- though this event is raised while BC's transient FRONT preference is
      -- active, the image resolved here is the actual current mon's BACK art.
      local back=staticImage({battle=battle},"player","back")
      if back then
        actor.player.liveBack=back
        actor.player.liveBackOwner=battler
        -- makeBattler itself ran while BC's transient Crystal FRONT preference
        -- was active, so repair the new battler's canonical send-out sprite too.
        -- The engine sets sendingOut immediately after this event; Crystal then
        -- correctly leaves this BACK image alone until the send-out completes.
        battler.sprite=back
      end
    end)
  end

  -- HOST DEFAULT is deliberately zero-touch. When the user yields from TURN
  -- ONLY/DYNAMIC, BC stops substituting/placing/orienting immediately and the
  -- provider's own next lifecycle pass becomes authoritative again. Do not
  -- synthesize a "restored" frame here: that would no longer be host default.
  local function syncMode(context)
    lastMode=mode()
  end

  local function updateScale(name,battle)
    local a=actor[name]
    if not active() then a.scale=1 return end
    if crystal then a.scale=1 return end
    local battler=battle and battle[name] or nil
    local img=battler and battler.sprite or nil
    local w,h=dims(img)
    local ext=math.max(tonumber(w) or 0,tonumber(h) or 0)
    local f=(ext>0) and (targetExtent/ext) or 1
    if not (f>0.05 and f<8) then f=1 end
    a.scale=f
  end

  local function updateScales(battle)
    if not battle then return end
    if battle.showPlayerBack or battle.sendingOut then actor.player.scale=1 else updateScale("player",battle) end
    if battle.showEnemyTrainer or battle.enemySendingOut then actor.enemy.scale=1 else updateScale("enemy",battle) end
  end

  -- Crystal lifecycle bridge. Under DYNAMIC, BC transiently enables Crystal's
  -- own player-front animator for the duration of Crystal's BattleState.update
  -- even while a back view is being presented. Both front animations therefore
  -- keep advancing underneath; BC only selects which live/static side Dramaless
  -- presents after the provider has advanced its state.
  if crystal and BattleState and type(BattleState.update)=="function"
      and not BattleState.__bcSpriteFacingDualActorInstalled then
    local inner=BattleState.update
    BattleState.update=function(self,dt,...)
      resetBattle(self)
      local priorPref=crystalPref()
      local frontWindow=dynamic()
      if frontWindow then
        if actor.player.liveFront and self.player and not self.showPlayerBack then
          self.player.sprite=actor.player.liveFront
        end
        if actor.enemy.liveFront and self.enemy and not self.showEnemyTrainer then
          self.enemy.sprite=actor.enemy.liveFront
        end
        setCrystal(true)
        crystalFrontCaptureDepth=crystalFrontCaptureDepth+1
      end
      local r={pcall(inner,self,dt,...)}
      -- Dramaless provider.update can be nested inside `inner`. Its BC wrapper
      -- is suppressed while crystalFrontCaptureDepth>0, so battler.sprite here
      -- is still Crystal's genuine animated FRONT rather than the main camera's
      -- temporary BACK representation. Capture first, then reopen presentation.
      captureProviderLives(self,frontWindow)
      if frontWindow then
        crystalFrontCaptureDepth=math.max(0,crystalFrontCaptureDepth-1)
        restoreCrystal(priorPref)
      end
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      if active() then applySelectedRepresentations(contextRef or {battle=self}) end
      return unpack_(r)
    end
    BattleState.__bcSpriteFacingDualActorInstalled=true
  end

  local function withWorldPlacement(fn,self,context,...)
    if type(fn)~="function" then return nil end
    if not active() then return fn(self,context,...) end
    depth=depth+1
    if depth==1 then setting.get=function() return false end end
    local r={pcall(fn,self,context,...)}
    depth=depth-1
    if depth==0 then setting.get=savedGet end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  for _,name in ipairs({"begin","update"}) do
    local original=provider[name]
    if type(original)=="function" then
      provider[name]=function(self,context,...)
        resetBattle(context and context.battle or nil)
        contextRef=context or contextRef
        syncMode(context)
        updateOrientation(context)
        captureProviderLives(context and context.battle)
        if active() and crystalFrontCaptureDepth==0 then applySelectedRepresentations(context) end
        updateScales(context and context.battle)
        local r={withWorldPlacement(original,self,context,...)}
        captureProviderLives(context and context.battle)
        if active() and crystalFrontCaptureDepth==0 then applySelectedRepresentations(context) end
        updateScales(context and context.battle)
        return unpack_(r)
      end
    end
  end

  local originalFinish=provider.finish
  if type(originalFinish)=="function" then
    provider.finish=function(self,...)
      battleRef=nil; contextRef=nil; imageCache={}
      local r={originalFinish(self,...)}
      return unpack_(r)
    end
  end

  local originalLocked=provider.cameraLocked
  provider.cameraLocked=function(self,...)
    if active() then return false end
    if type(originalLocked)=="function" then return originalLocked(self,...) end
    return false
  end

  local function matrixActor(x,z)
    local context=contextRef
    local arena=context and context.arena or nil
    if not arena then return nil end
    local function near(cell)
      if type(cell)~="table" then return false end
      local dx=(tonumber(x) or 0)-(tonumber(cell[1]) or 0)
      local dz=(tonumber(z) or 0)-(tonumber(cell[2]) or 0)
      return dx*dx+dz*dz<0.01
    end
    if near(arena.player) then return "player" end
    if near(arena.enemy) then return "enemy" end
    return nil
  end

  local function orientationMirror(name)
    local a=actor[name]
    local opponentRight=(a.turn=="right")
    local side=presentationSide(name)

    -- Runtime-proven handedness map:
    --   * BACK art for either battler uses Dramaless's ordinary convention.
    --   * ENEMY FRONT art (vanilla or Crystal) is intrinsically opposite.
    --   * PLAYER static FRONT art is also opposite.
    --   * Crystal's live PLAYER FRONT animation is the one front representation
    --     already proven to use the ordinary convention in 2L2.
    if side=="back" then return opponentRight end
    if name=="enemy" then return not opponentRight end
    if crystal and name=="player" and (dynamic() or crystalPref()==true) then
      return opponentRight
    end
    return not opponentRight
  end

  local okBB,Billboard=pcall(V.require,"BattleBillboard")
  if okBB and type(Billboard)=="table" and type(Billboard.matrix)=="function"
      and not Billboard.__bcSpriteFacingDualActorInstalled then
    local originalMatrix=Billboard.matrix
    Billboard.matrix=function(texture,anchorX,anchorY,x,y,z,mirror)
      if not active() then return originalMatrix(texture,anchorX,anchorY,x,y,z,mirror) end
      local name=matrixActor(x,z)
      if not name then return originalMatrix(texture,anchorX,anchorY,x,y,z,mirror) end
      local battle=battleRef
      if name=="player" and battle and (battle.showPlayerBack or battle.sendingOut) then
        return originalMatrix(texture,anchorX,anchorY,x,y,z,mirror)
      end
      if name=="enemy" and battle and (battle.showEnemyTrainer or battle.enemySendingOut) then
        return originalMatrix(texture,anchorX,anchorY,x,y,z,mirror)
      end
      local outMirror=orientationMirror(name)
      local factor=tonumber(actor[name].scale) or 1
      if not (factor>0 and factor<8) then factor=1 end
      if math.abs(factor-1)<0.001 then
        return originalMatrix(texture,anchorX,anchorY,x,y,z,outMirror)
      end
      local prior=tonumber(Billboard.FULL_W) or 16
      Billboard.FULL_W=prior*factor
      local r={pcall(originalMatrix,texture,anchorX,anchorY,x,y,z,outMirror)}
      Billboard.FULL_W=prior
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      return unpack_(r)
    end
    Billboard.__bcSpriteFacingDualActorInstalled=true

    -- Secondary View 2D portrait adapter. This intentionally lives beside the
    -- Dramaless sprite-facing adapter so it can consume the same renderer-owned
    -- sprite resolution (vanilla replacements and Crystal live fronts) while
    -- bypassing the primary-camera Billboard.matrix orientation wrapper.
    -- BC supplies only a second camera/view; the sprite art remains provider/
    -- engine-owned. The 56px normalization mirrors Dramaless's own world-card
    -- contract, giving every Gen1 battle sprite the same predictable world fit.
    do
      local portraitCanvas=nil
      local portraitW,portraitH=160,144
      local portraitAX,portraitAY=80,96
      local function canvasForImage(img)
        if not (img and love and love.graphics and type(love.graphics.newCanvas)=="function") then return nil end
        if not portraitCanvas then
          local ok,c=pcall(love.graphics.newCanvas,portraitW,portraitH,{dpiscale=1})
          if not (ok and c) then return nil end
          if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
          portraitCanvas=c
        end
        local w,h=dims(img)
        if not (w and h and w>0 and h>0) then return nil end
        local scale=56/math.max(w,h)
        if not (scale>0.01 and scale<32) then scale=1 end
        local g=love.graphics
        local prior=g.getCanvas()
        g.push("all")
        g.setCanvas(portraitCanvas); g.clear(0,0,0,0)
        if g.setShader then g.setShader() end
        g.setBlendMode("alpha"); g.setColor(1,1,1,1)
        g.draw(img,portraitAX-w*scale/2,portraitAY-h*scale,0,scale,scale)
        g.pop()
        if prior then g.setCanvas(prior) else g.setCanvas() end
        return portraitCanvas
      end

      local function frontImage()
        local battle=state.battle or battleRef
        if not battle then return nil,false end
        -- LEFT/RIGHT remain authored fixed Secondary View CAMERA positions.
        -- Crystal liveFront is still one FRONT representation: consuming it
        -- restores the provider's animation without allowing the primary
        -- Dynamic camera to choose PiP front/back state. PIP SIDE alone owns
        -- viewpoint and handedness. Static/vanilla fronts remain unchanged.
        if crystal and actor.player.liveFront then return actor.player.liveFront,true end
        return staticImage({battle=battle},"player","front"),false
      end

      local function mirrorForSecondary()
        -- Native/Crystal front sprites follow the ordinary battle-front
        -- convention. The Secondary View CAMERA supplies the authored arena-side
        -- grammar; this mirror only keeps the flat art's handedness
        -- coherent on the opposite side. It is independent from SPRITE FACING.
        return (mod.options:get("secondaryViewSide") or "left")=="left"
      end

      state.secondarySpriteSource={
        id="DRAMALESS_SHAPE:native-player-portrait",
        drawPlayer=function(view,arena,groundY,cam)
          local img,crystalLive=frontImage()
          local canvas=canvasForImage(img)
          local mesh=type(Billboard.mesh)=="function" and Billboard.mesh() or nil
          local Voxel3D=V.require("Voxel3D")
          if not (canvas and mesh and Voxel3D and type(Voxel3D.draw)=="function"
              and arena and type(arena.player)=="table") then return false end
          local mirror=mirrorForSecondary()
          -- The model-oriented Probe13 camera is intentionally close. A full
          -- Dramaless 56px world card is therefore too large in the PiP. Since
          -- Gen1 front sprites share a bounded 56px presentation contract, use
          -- one fixed portrait-card scale rather than species tuning.
          local priorFullW=tonumber(Billboard.FULL_W) or 16
          Billboard.FULL_W=priorFullW*0.58
          local okModel,model=pcall(originalMatrix,canvas,portraitAX,portraitAY,
            arena.player[1],tonumber(groundY) or 0,arena.player[2],mirror)
          Billboard.FULL_W=priorFullW
          if not (okModel and model) then return false end
          Voxel3D.seams(false); Voxel3D.glass(false)
          Voxel3D.draw(mesh,canvas,model,Billboard.PULL)
          Voxel3D.glass(true); Voxel3D.seams(true)
          return true
        end,
      }
      mod.log:info("[SECONDARY VIEW] Dramaless/native 2D portrait adapter registered")
    end
  end

  -- Diagnostics are now opt-in through BC's existing DIAGNOSTICS option so the
  -- product menu can be tested without a permanent development HUD.
  pcall(function()
    mod.hooks:wrap("render.hud",function(nextFn,game,viewport)
      local result=nextFn(game,viewport)
      if battleRef and active() and mod.options:get("diagnostics")=="on"
          and love and love.graphics then
        pcall(function()
          local g=love.graphics
          if not hudFont then hudFont=g.newFont(11) end
          local p,e=actor.player,actor.enemy
          local lines={
            string.format("BC SPRITE FACE DRAMALESS mode=%s crystal=%s",mode(),crystal and "Y" or "N"),
            string.format("P side=%s turn=%s scale=%.3f dx=%s",presentationSide("player"),p.turn,p.scale,p.screenDelta and string.format("%.3f",p.screenDelta) or "?"),
            string.format("E side=%s turn=%s scale=%.3f dx=%s",presentationSide("enemy"),e.turn,e.scale,e.screenDelta and string.format("%.3f",e.screenDelta) or "?"),
            string.format("hostBack=%s crystalFront=%s",hostBackEnabled() and "ON" or "OFF",tostring(crystalPref())),
          }
          g.push("all"); g.origin(); g.setFont(hudFont)
          g.setColor(0,0,0,.84); g.rectangle("fill",8,8,610,66,4,4)
          g.setColor(1,1,1,1)
          for i,line in ipairs(lines) do g.print(line,13,10+(i-1)*14) end
          g.pop()
        end)
      end
      return result
    end)
  end)

  provider.__bcSpriteFacingDualActorInstalled=true
  mod.log:warn("[BC SPRITE FACE] Dramaless dual-actor adapter armed")
end)()

-- Dramatic Shape Sprite Facing / Dual Actor Presentation -------------------
-- Dramatic Shape adapter consumes the host's own staged 2D-card seam. The host still
-- owns arena rendering, texture capture, shadows, lighting, move FX and camera
-- projection.  BC contributes only the same final-camera actor orientation
-- semantic already proven on Dramaless/Battle Art.  Stadium-model rungs are a
-- hard yield: real 3D models are never converted into sprite cards here.
;(function()
  local handle=mod.find("DRAMATIC_SHAPE")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  if not (V and type(V.require)=="function") then return end

  local okOB,OverworldBattle=pcall(V.require,"OverworldBattle")
  if not okOB or type(OverworldBattle)~="table"
      or type(OverworldBattle.sideTexture)~="function"
      or type(OverworldBattle.backPinned)~="function" then return end
  if OverworldBattle.__bcSpriteFacingDramaticInstalled then return end

  local setting=OverworldBattle.backSetting
  local savedBackPinned=OverworldBattle.backPinned
  if type(setting)~="table" or type(setting.get)~="function" then return end
  local savedSettingGet=setting.get
  local unpack_=table.unpack or unpack

  local BattleState,Sprites,Assets,PaletteFX=nil,nil,nil,nil
  do
    local okBS,bs=pcall(require,"src.battle.BattleState")
    if okBS and type(bs)=="table" then BattleState=bs end
    local okSp,sp=pcall(require,"src.pokemon.Sprites")
    if okSp and type(sp)=="table" then Sprites=sp end
    local okAs,a=pcall(require,"src.render.Assets")
    if okAs and type(a)=="table" then Assets=a end
    local okPa,pal=pcall(require,"src.render.PaletteFX")
    if okPa and type(pal)=="table" then PaletteFX=pal end
  end
  if not (BattleState and Sprites and Assets) then return end

  local crystal=nil
  do
    local h=mod.find("crystal_animated_sprites_with_shiny_visuals")
    local ex=h and h.exports or nil
    if ex and type(ex.applyOption)=="function"
        and type(ex.frontPrefEnabled)=="function" then
      crystal={exports=ex}
    end
  end

  local actor={
    player={side="back",turn="right",screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
    enemy ={side="front",turn="left", screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
  }
  local battleRef=nil
  local imageCache={}
  local flipped={}

  local function mode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v~="turn" and v~="dynamic" then return "host" end
    return v
  end

  local function isStadium()
    if type(OverworldBattle.stadium)~="function" then return false end
    local ok,v=pcall(OverworldBattle.stadium)
    return ok and v and true or false
  end

  local function active()
    if not enabled() or selectedPreset()=="external" or mode()=="host" then return false end
    if type(OverworldBattle.enabled)=="function" then
      local ok,v=pcall(OverworldBattle.enabled)
      if not ok or not v then return false end
    end
    if isStadium() then return false end
    return true
  end

  local function dynamic() return active() and mode()=="dynamic" end

  local function hostBackEnabled()
    local ok,v=pcall(savedSettingGet,setting)
    return ok and v and true or false
  end

  local function crystalPref()
    if not crystal then return nil end
    local ok,v=pcall(crystal.exports.frontPrefEnabled)
    return ok and (v and true or false) or nil
  end

  local function setCrystal(v)
    if not crystal then return false end
    return pcall(crystal.exports.applyOption,"crystalFront",v and true or false)
  end

  local function resetBattle(battle)
    if battle==battleRef then return end
    battleRef=battle
    imageCache={}
    actor.player.side,actor.player.turn="back","right"
    actor.enemy.side,actor.enemy.turn="front","left"
    for _,a in pairs(actor) do
      a.screenDelta=nil; a.scale=1; a.liveFront=nil; a.liveBack=nil
    end
  end

  local function updateOne(name,cell,other,cam)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
    local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
    local fl=math.sqrt(fx*fx+fz*fz)
    local vl=math.sqrt(vx*vx+vz*vz)
    if fl>=0.001 and vl>=0.001 then
      local dot=(fx*vx+fz*vz)/(fl*vl)
      if a.side=="back" and dot>0.22 then a.side="front"
      elseif a.side=="front" and dot<(-0.22) then a.side="back" end
    end

    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(pt)
          local dx=(tonumber(pt[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(pt[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
        end
        local aa,oo=screenX(cell),screenX(other)
        screenDelta=(aa and oo) and (oo-aa) or (fx*rx+fz*rz)
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation()
    if not active() then return end
    local okA,arena=pcall(OverworldBattle.arena)
    if not okA or type(arena)~="table" then return end
    local p,e=arena.player,arena.enemy
    local cam=state.spriteFacingCamera
    if not (p and e and cam) then return end
    if dynamic() then
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
    else
      local ps,es=actor.player.side,actor.enemy.side
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
      actor.player.side,actor.enemy.side=ps,es
    end
  end

  local function hostPlayerSide()
    if not hostBackEnabled() then return "front" end
    if crystal and crystalPref()==true then return "front" end
    return "back"
  end

  local function presentationSide(name)
    if mode()=="dynamic" then return actor[name].side end
    if name=="enemy" then return "front" end
    return hostPlayerSide()
  end

  -- While BC is actively consuming sprite orientation, the player's card must
  -- remain in Dramatic's world-card pass.  The saved BACK SPRITES preference is
  -- still read above for TURN ONLY; only the host's pinning side effect yields.
  OverworldBattle.backPinned=function(...)
    if active() then return false end
    return savedBackPinned(...)
  end

  local nativeResolveScale=BattleState.resolveBattleScale

  local function temporarilyCrystalOff(fn)
    if not crystal then return fn() end
    local prior=crystalPref()
    if prior~=false then setCrystal(false) end
    local r={pcall(fn)}
    if prior~=nil then setCrystal(prior) end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  local function staticRep(name,side,battle)
    local battler=battle and battle[name] or nil
    local mon=battler and battler.mon or nil
    local species=mon and mon.species or nil
    if not species then return nil,1 end

    local function resolvePath()
      local ok,path,tc=pcall(Sprites.path,battle.data,species,side,{mon=mon,kind="battle"})
      if not ok or type(path)~="string" or path=="" then return nil,nil end
      return path,tc
    end
    local function resolveNativeSide()
      -- Dramatic-derived staged-battle hosts deliberately rewrite every
      -- battle BACK request to FRONT while their 2D-3D world-card mode is
      -- active (OverworldBattle.wantsFront).  TURN ONLY never notices because
      -- it keeps the host representation, but DYNAMIC must be able to request
      -- the genuine back asset when the final BC camera crosses behind an
      -- actor.  Suppress only that host-side rewrite for this one path lookup;
      -- the saved host setting and its normal renderer behaviour are untouched.
      local wf=OverworldBattle.wantsFront
      if side=="back" and type(wf)=="function" then
        OverworldBattle.wantsFront=function() return false end
      end
      local r={pcall(resolvePath)}
      if side=="back" and type(wf)=="function" then
        OverworldBattle.wantsFront=wf
      end
      if not r[1] then error(r[2],0) end
      return r[2],r[3]
    end

    local path,tc
    if crystal and side=="back" then path,tc=temporarilyCrystalOff(resolveNativeSide)
    else path,tc=resolveNativeSide() end
    if not path then return nil,1 end

    local scale=1
    local okS,v=pcall(nativeResolveScale,battle.data,side,path,species)
    if okS and tonumber(v) and tonumber(v)>0 then scale=tonumber(v) end

    local palName="truecolor"
    if not tc and PaletteFX and type(PaletteFX.monPalName)=="function" then
      local okN,n=pcall(PaletteFX.monPalName,battle.data,species,false)
      if okN and n then palName=tostring(n) end
    end
    local key=table.concat({tostring(path),palName,name,side},"#")
    if imageCache[key] then return imageCache[key],scale end

    local img=nil
    if tc or not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
      local okI,vv=pcall(Assets.image,path); if okI then img=vv end
    else
      local okD,id=pcall(Assets.imageData,path)
      if okD and id then
        local pal=PaletteFX and type(PaletteFX.monPal)=="function"
          and PaletteFX.monPal(battle.data,species,false) or nil
        if pal then
          local c=pal
          pcall(id.mapPixel,id,function(_,_,r,g,b,a)
            if a==0 then return r,g,b,a end
            local col=r>0.83 and c[1] or r>0.5 and c[2] or r>0.17 and c[3] or c[4]
            return col[1]/255,col[2]/255,col[3]/255,a
          end)
        end
        local okI,vv=pcall(love.graphics.newImage,id); if okI then img=vv end
      end
    end
    if img and type(img.setFilter)=="function" then pcall(img.setFilter,img,"nearest","nearest") end
    imageCache[key]=img
    return img,scale
  end

  local function captureLives(battle,frontAuthoritative)
    if not (crystal and battle) then return end
    local p,e=battle.player,battle.enemy
    -- Rebase56 ports the user-validated Potato Rebase54 ownership correction
    -- back to base Dramatic. battle.player.sprite is a presentation field: a
    -- Dynamic BACK borrowed for one staged-card capture must never become the
    -- next cached Crystal FRONT. Only the update window where BC explicitly
    -- enabled Crystal FRONT is authoritative for the player stream.
    if frontAuthoritative==true and p and p.__crystalAnimation and p.sprite then
      actor.player.liveFront=p.sprite
    end
    if e and e.__crystalAnimation and e.sprite then actor.enemy.liveFront=e.sprite end
  end

  local function applyRep(name,battle)
    if not (active() and battle) then return end
    if name=="player" and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then return end
    if name=="enemy" and (battle.showEnemyTrainer or battle.enemySendingOut) then return end
    local battler=battle[name]
    if not battler then return end
    local side=presentationSide(name)
    local img,scale=nil,1
    if crystal and side=="front" then
      img=actor[name].liveFront
      if not img then img,scale=staticRep(name,side,battle) end
    else
      img,scale=staticRep(name,side,battle)
    end
    if img then battler.sprite=img end
    actor[name].scale=(tonumber(scale) and tonumber(scale)>0) and tonumber(scale) or 1
  end

  -- Keep Crystal's real player-front animation alive under DYNAMIC without
  -- changing the user's saved Crystal option.  This is the same lifecycle
  -- ownership rule already proven on Dramaless.
  if crystal and type(BattleState.update)=="function"
      and not BattleState.__bcSpriteFacingDramaticInstalled then
    local innerUpdate=BattleState.update
    BattleState.update=function(self,dt,...)
      resetBattle(self)
      local prior=crystalPref()
      if dynamic() then
        if actor.player.liveFront and self.player and not self.showPlayerBack then
          self.player.sprite=actor.player.liveFront
        end
        if actor.enemy.liveFront and self.enemy and not self.showEnemyTrainer then
          self.enemy.sprite=actor.enemy.liveFront
        end
        setCrystal(true)
      end
      local r={pcall(innerUpdate,self,dt,...)}
      captureLives(self,dynamic())
      if dynamic() and prior~=nil then setCrystal(prior) end
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      -- Camera-selected art is now borrowed only inside sideTexture below; do
      -- not persist it back into provider battler state after the update.
      return unpack_(r)
    end
    BattleState.__bcSpriteFacingDramaticInstalled=true
  end

  local function desiredMirror(name)
    local side=presentationSide(name)
    local opponentRight=(actor[name].turn=="right")
    -- Dramatic's BattleScene documents raw FRONT art as facing left: its
    -- ordinary player card is mirrored and its enemy card is not.  Native BACK
    -- art is authored in the opposite direction.  Translate the universal BC
    -- turn semantic into that host convention; no species knowledge involved.
    if side=="front" then return not opponentRight end
    return opponentRight
  end

  local function flipCanvas(src,key)
    if not (src and love and love.graphics and type(src.getDimensions)=="function") then return nil end
    local w,h=src:getDimensions()
    if not (w and h and w>0 and h>0) then return nil end
    local rec=flipped[key]
    if not rec or rec.w~=w or rec.h~=h then
      local ok,c=pcall(love.graphics.newCanvas,w,h,{dpiscale=1})
      if not ok or not c then return nil end
      if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
      rec={canvas=c,w=w,h=h}; flipped[key]=rec
    end
    local g=love.graphics
    local prev=g.getCanvas()
    local bm,ba=g.getBlendMode()
    local cr,cg,cb,ca=g.getColor()
    local ok=pcall(function()
      g.setCanvas(rec.canvas); g.clear(0,0,0,0); g.setBlendMode("alpha")
      g.setColor(1,1,1,1); g.draw(src,w,0,0,-1,1)
    end)
    if prev then g.setCanvas(prev) else g.setCanvas() end
    g.setBlendMode(bm or "alpha",ba); g.setColor(cr,cg,cb,ca)
    if not ok then return nil end
    return rec.canvas,w
  end

  local originalSideTexture=OverworldBattle.sideTexture
  OverworldBattle.sideTexture=function(battle,side)
    if not active() then return originalSideTexture(battle,side) end
    resetBattle(battle)
    updateOrientation()

    -- Rebase56: one-capture representation ownership. This is the exact
    -- Potato Rebase54 fix the user validated as removing PiP FRONT/BACK leak
    -- and the apparent stray/fifth Crystal back frame.
    local battler=battle and battle[side] or nil
    local repSide=presentationSide(side)
    local displayScale=1
    local priorSprite=nil
    local swapped=false
    local canBorrow=(side=="player" or side=="enemy") and battler~=nil
    if side=="player" and battle
        and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then
      canBorrow=false
    elseif side=="enemy" and battle
        and (battle.showEnemyTrainer or battle.enemySendingOut) then
      canBorrow=false
    end
    if canBorrow then
      local img=nil
      if crystal and repSide=="front" and actor[side].liveFront then
        img=actor[side].liveFront
      else
        img,displayScale=staticRep(side,repSide,battle)
      end
      displayScale=(tonumber(displayScale) and tonumber(displayScale)>0) and tonumber(displayScale) or 1
      actor[side].scale=displayScale
      if img then
        priorSprite=battler.sprite
        battler.sprite=img
        swapped=true
      end
    end

    local savedResolve=nil
    if dynamic() and not crystal and presentationSide(side)=="back"
        and type(BattleState.resolveBattleScale)=="function" then
      local factor=tonumber(actor[side].scale) or 1
      if factor<=1.001 and type(OverworldBattle.SLOT_W)=="table" then
        local fw=tonumber(OverworldBattle.SLOT_W.front)
        local bw=tonumber(OverworldBattle.SLOT_W.back)
        if fw and bw and bw>0 then factor=math.max(1,math.floor(fw/bw+0.5)) end
      end
      if factor>1.001 and factor<8 then
        savedResolve=BattleState.resolveBattleScale
        BattleState.resolveBattleScale=function(...) return factor end
      end
    end
    local r={pcall(originalSideTexture,battle,side)}
    if savedResolve then BattleState.resolveBattleScale=savedResolve end
    if swapped then battler.sprite=priorSprite end
    if not r[1] then error(r[2],0) end
    local tex=r[2]
    if not (tex and not tex.trainer and tex.canvas) then return tex end

    local hostMirror=(side=="player")
    local want=desiredMirror(side)
    if hostMirror~=want then
      local c,w=flipCanvas(tex.canvas,side)
      if c then
        tex.canvas=c
        if tonumber(tex.ax) then tex.ax=w-tonumber(tex.ax) end
      end
    end
    return tex
  end

  -- Base Dramatic fixed-FRONT Secondary View producer. Crystal never samples
  -- battle.player.sprite here; that field may be the main camera's borrowed
  -- BACK. The authoritative animated FRONT cache above feeds the canonical
  -- 160x144 / X80 / Y96 / max-56px portrait directly.
  local secondaryCardCanvas=nil
  local secondaryCardW,secondaryCardH=nil,nil

  local function ensureSecondaryCanvas(w,h)
    if secondaryCardCanvas and secondaryCardW==w and secondaryCardH==h then return secondaryCardCanvas end
    if secondaryCardCanvas and type(secondaryCardCanvas.release)=="function" then pcall(secondaryCardCanvas.release,secondaryCardCanvas) end
    local okC,c=pcall(love.graphics.newCanvas,w,h,{dpiscale=1})
    if not (okC and c) then return nil end
    if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
    secondaryCardCanvas,secondaryCardW,secondaryCardH=c,w,h
    return c
  end

  local function copyProviderCard(tex)
    if not (tex and tex.canvas and type(tex.canvas.getDimensions)=="function") then return nil,"provider card unavailable" end
    local w,h=tex.canvas:getDimensions()
    if not (w and h and w>0 and h>0) then return nil,"provider card dimensions unavailable" end
    local out=ensureSecondaryCanvas(w,h); if not out then return nil,"private card canvas unavailable" end
    local g=love.graphics
    local prior=nil; if type(g.getCanvas)=="function" then local okP,v=pcall(g.getCanvas); if okP then prior=v end end
    local pushed=false
    local okCopy,errCopy=pcall(function()
      g.push("all"); pushed=true; g.origin(); g.setCanvas(out); g.clear(0,0,0,0)
      if g.setShader then g.setShader() end
      g.setBlendMode("alpha"); g.setColor(1,1,1,1)
      if (mod.options:get("secondaryViewSide") or "left")=="right" then g.draw(tex.canvas,w,0,0,-1,1) else g.draw(tex.canvas,0,0) end
    end)
    if pushed then pcall(g.pop) end
    if prior~=nil then pcall(g.setCanvas,prior) else pcall(g.setCanvas) end
    if not okCopy then return nil,"private card copy failed: "..tostring(errCopy) end
    local ax=tonumber(tex.ax) or tonumber(OverworldBattle.TEX_AX) or 80
    if (mod.options:get("secondaryViewSide") or "left")=="right" then ax=w-ax end
    return {canvas=out,ax=ax,ay=tonumber(tex.ay) or tonumber(OverworldBattle.TEX_AY) or 96,trainer=false},"provider_front"
  end

  local function crystalFrontCard(img)
    if not (img and type(img.getDimensions)=="function") then return nil,"Crystal FRONT frame unavailable" end
    local okD,iw,ih=pcall(img.getDimensions,img); iw,ih=tonumber(iw),tonumber(ih)
    if not (okD and iw and ih and iw>0 and ih>0) then return nil,"Crystal FRONT dimensions unavailable" end
    local out=ensureSecondaryCanvas(160,144); if not out then return nil,"private Crystal card canvas unavailable" end
    local scale=56/math.max(iw,ih)
    local mirror=(mod.options:get("secondaryViewSide") or "left")=="right"
    local dx=mirror and -scale or scale
    local x=80-(iw*dx)/2; local y=96-ih*scale
    local g=love.graphics
    local prior=nil; if type(g.getCanvas)=="function" then local okP,v=pcall(g.getCanvas); if okP then prior=v end end
    local pushed=false
    local okDraw,errDraw=pcall(function()
      g.push("all"); pushed=true; g.origin(); g.setCanvas(out); g.clear(0,0,0,0)
      if g.setShader then g.setShader() end
      g.setBlendMode("alpha"); g.setColor(1,1,1,1); g.draw(img,x,y,0,dx,scale)
    end)
    if pushed then pcall(g.pop) end
    if prior~=nil then pcall(g.setCanvas,prior) else pcall(g.setCanvas) end
    if not okDraw then return nil,"Crystal FRONT card draw failed: "..tostring(errDraw) end
    return {canvas=out,ax=80,ay=96,trainer=false},"crystal_live_front_locked"
  end

  OverworldBattle.__bcSecondaryViewPlayerTexture=function()
    local battle=state.battle or battleRef
    if not (battle and battle.player) then return nil,"battle/player unavailable" end
    resetBattle(battle)
    if crystal and actor.player.liveFront then return crystalFrontCard(actor.player.liveFront) end
    local img=select(1,staticRep("player","front",battle)); if not img then return nil,"fixed FRONT unavailable" end
    local battler=battle.player; local savedSprite=battler.sprite; local savedShow=battle.showPlayerBack
    battler.sprite=img; battle.showPlayerBack=false
    local okTex,tex=pcall(originalSideTexture,battle,"player")
    battler.sprite=savedSprite; battle.showPlayerBack=savedShow
    if not okTex then return nil,tostring(tex) end
    return copyProviderCard(tex)
  end

  local originalFinish=OverworldBattle.finish
  if type(originalFinish)=="function" then
    OverworldBattle.finish=function(...)
      battleRef=nil; imageCache={}
      return originalFinish(...)
    end
  end
  local originalInvalidate=OverworldBattle.invalidate
  if type(originalInvalidate)=="function" then
    OverworldBattle.invalidate=function(...)
      flipped={}
      return originalInvalidate(...)
    end
  end

  OverworldBattle.__bcSpriteFacingDramaticInstalled=true
  mod.log:info("Dramatic Shape sprite-facing adapter active: scoped card borrowing + Crystal FRONT ownership lock + final-camera orientation; Stadium models yielded")
end)()



-- PotatoVoxel Sprite Facing / Dual Actor Presentation -------------------
-- PotatoVoxel adapter consumes the host's own staged 2D-card seam. The host still
-- owns arena rendering, texture capture, shadows, lighting, move FX and camera
-- projection.  BC contributes only the same final-camera actor orientation
-- semantic already proven on Dramaless/Battle Art.  Model-based rungs are a hard yield when the host exposes them: real 3D models are never converted into sprite cards here.
;(function()
  local handle=mod.find("potato_voxel")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  if not (V and type(V.require)=="function") then return end

  local okOB,OverworldBattle=pcall(V.require,"OverworldBattle")
  if not okOB or type(OverworldBattle)~="table"
      or type(OverworldBattle.sideTexture)~="function"
      or type(OverworldBattle.backPinned)~="function" then return end
  if OverworldBattle.__bcSpriteFacingPotatoVoxelInstalled then return end

  local setting=OverworldBattle.backSetting
  local savedBackPinned=OverworldBattle.backPinned
  if type(setting)~="table" or type(setting.get)~="function" then return end
  local savedSettingGet=setting.get
  local unpack_=table.unpack or unpack

  local BattleState,Sprites,Assets,PaletteFX=nil,nil,nil,nil
  do
    local okBS,bs=pcall(require,"src.battle.BattleState")
    if okBS and type(bs)=="table" then BattleState=bs end
    local okSp,sp=pcall(require,"src.pokemon.Sprites")
    if okSp and type(sp)=="table" then Sprites=sp end
    local okAs,a=pcall(require,"src.render.Assets")
    if okAs and type(a)=="table" then Assets=a end
    local okPa,pal=pcall(require,"src.render.PaletteFX")
    if okPa and type(pal)=="table" then PaletteFX=pal end
  end
  if not (BattleState and Sprites and Assets) then return end

  local crystal=nil
  do
    local h=mod.find("crystal_animated_sprites_with_shiny_visuals")
    local ex=h and h.exports or nil
    if ex and type(ex.applyOption)=="function"
        and type(ex.frontPrefEnabled)=="function" then
      crystal={exports=ex}
    end
  end

  local actor={
    player={side="back",turn="right",screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
    enemy ={side="front",turn="left", screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
  }
  local battleRef=nil
  local imageCache={}
  local flipped={}

  local function mode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v~="turn" and v~="dynamic" then return "host" end
    return v
  end

  local function isStadium()
    if type(OverworldBattle.stadium)~="function" then return false end
    local ok,v=pcall(OverworldBattle.stadium)
    return ok and v and true or false
  end

  local function active()
    if not enabled() or selectedPreset()=="external" or mode()=="host" then return false end
    if type(OverworldBattle.enabled)=="function" then
      local ok,v=pcall(OverworldBattle.enabled)
      if not ok or not v then return false end
    end
    if isStadium() then return false end
    return true
  end

  local function dynamic() return active() and mode()=="dynamic" end

  local function hostBackEnabled()
    local ok,v=pcall(savedSettingGet,setting)
    return ok and v and true or false
  end

  local function crystalPref()
    if not crystal then return nil end
    local ok,v=pcall(crystal.exports.frontPrefEnabled)
    return ok and (v and true or false) or nil
  end

  local function setCrystal(v)
    if not crystal then return false end
    return pcall(crystal.exports.applyOption,"crystalFront",v and true or false)
  end

  local function resetBattle(battle)
    if battle==battleRef then return end
    battleRef=battle
    imageCache={}
    actor.player.side,actor.player.turn="back","right"
    actor.enemy.side,actor.enemy.turn="front","left"
    for _,a in pairs(actor) do
      a.screenDelta=nil; a.scale=1; a.liveFront=nil; a.liveBack=nil
    end
  end

  local function updateOne(name,cell,other,cam)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
    local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
    local fl=math.sqrt(fx*fx+fz*fz)
    local vl=math.sqrt(vx*vx+vz*vz)
    if fl>=0.001 and vl>=0.001 then
      local dot=(fx*vx+fz*vz)/(fl*vl)
      if a.side=="back" and dot>0.22 then a.side="front"
      elseif a.side=="front" and dot<(-0.22) then a.side="back" end
    end

    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(pt)
          local dx=(tonumber(pt[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(pt[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
        end
        local aa,oo=screenX(cell),screenX(other)
        screenDelta=(aa and oo) and (oo-aa) or (fx*rx+fz*rz)
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation()
    if not active() then return end
    local okA,arena=pcall(OverworldBattle.arena)
    if not okA or type(arena)~="table" then return end
    local p,e=arena.player,arena.enemy
    local cam=state.spriteFacingCamera
    if not (p and e and cam) then return end
    if dynamic() then
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
    else
      local ps,es=actor.player.side,actor.enemy.side
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
      actor.player.side,actor.enemy.side=ps,es
    end
  end

  local function hostPlayerSide()
    if not hostBackEnabled() then return "front" end
    if crystal and crystalPref()==true then return "front" end
    return "back"
  end

  local function presentationSide(name)
    if mode()=="dynamic" then return actor[name].side end
    if name=="enemy" then return "front" end
    return hostPlayerSide()
  end

  -- While BC is actively consuming sprite orientation, the player's card must
  -- remain in PotatoVoxel's world-card pass.  The saved BACK SPRITES preference is
  -- still read above for TURN ONLY; only the host's pinning side effect yields.
  OverworldBattle.backPinned=function(...)
    if active() then return false end
    return savedBackPinned(...)
  end

  local nativeResolveScale=BattleState.resolveBattleScale

  local function temporarilyCrystalOff(fn)
    if not crystal then return fn() end
    local prior=crystalPref()
    if prior~=false then setCrystal(false) end
    local r={pcall(fn)}
    if prior~=nil then setCrystal(prior) end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  local function staticRep(name,side,battle)
    local battler=battle and battle[name] or nil
    local mon=battler and battler.mon or nil
    local species=mon and mon.species or nil
    if not species then return nil,1 end

    local function resolvePath()
      local ok,path,tc=pcall(Sprites.path,battle.data,species,side,{mon=mon,kind="battle"})
      if not ok or type(path)~="string" or path=="" then return nil,nil end
      return path,tc
    end
    local function resolveNativeSide()
      -- Dramatic-derived staged-battle hosts deliberately rewrite every
      -- battle BACK request to FRONT while their 2D-3D world-card mode is
      -- active (OverworldBattle.wantsFront).  TURN ONLY never notices because
      -- it keeps the host representation, but DYNAMIC must be able to request
      -- the genuine back asset when the final BC camera crosses behind an
      -- actor.  Suppress only that host-side rewrite for this one path lookup;
      -- the saved host setting and its normal renderer behaviour are untouched.
      local wf=OverworldBattle.wantsFront
      if side=="back" and type(wf)=="function" then
        OverworldBattle.wantsFront=function() return false end
      end
      local r={pcall(resolvePath)}
      if side=="back" and type(wf)=="function" then
        OverworldBattle.wantsFront=wf
      end
      if not r[1] then error(r[2],0) end
      return r[2],r[3]
    end

    local path,tc
    if crystal and side=="back" then path,tc=temporarilyCrystalOff(resolveNativeSide)
    else path,tc=resolveNativeSide() end
    if not path then return nil,1 end

    local scale=1
    local okS,v=pcall(nativeResolveScale,battle.data,side,path,species)
    if okS and tonumber(v) and tonumber(v)>0 then scale=tonumber(v) end

    local palName="truecolor"
    if not tc and PaletteFX and type(PaletteFX.monPalName)=="function" then
      local okN,n=pcall(PaletteFX.monPalName,battle.data,species,false)
      if okN and n then palName=tostring(n) end
    end
    local key=table.concat({tostring(path),palName,name,side},"#")
    if imageCache[key] then return imageCache[key],scale end

    local img=nil
    if tc or not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
      local okI,vv=pcall(Assets.image,path); if okI then img=vv end
    else
      local okD,id=pcall(Assets.imageData,path)
      if okD and id then
        local pal=PaletteFX and type(PaletteFX.monPal)=="function"
          and PaletteFX.monPal(battle.data,species,false) or nil
        if pal then
          local c=pal
          pcall(id.mapPixel,id,function(_,_,r,g,b,a)
            if a==0 then return r,g,b,a end
            local col=r>0.83 and c[1] or r>0.5 and c[2] or r>0.17 and c[3] or c[4]
            return col[1]/255,col[2]/255,col[3]/255,a
          end)
        end
        local okI,vv=pcall(love.graphics.newImage,id); if okI then img=vv end
      end
    end
    if img and type(img.setFilter)=="function" then pcall(img.setFilter,img,"nearest","nearest") end
    imageCache[key]=img
    return img,scale
  end

  local function captureLives(battle,frontAuthoritative)
    if not (crystal and battle) then return end
    local p,e=battle.player,battle.enemy
    -- Rebase54: battle.player.sprite is a presentation field, not a semantic
    -- FRONT. Under Dynamic the Potato sideTexture bridge may temporarily borrow
    -- a BACK image while the Crystal animation marker remains attached. Only
    -- the exact BattleState.update window where BC has explicitly enabled the
    -- Crystal FRONT animator is allowed to replace the cached player FRONT.
    if frontAuthoritative==true and p and p.__crystalAnimation and p.sprite then
      actor.player.liveFront=p.sprite
    end
    -- Crystal owns the enemy as a FRONT animation stream; BC's Potato card
    -- representation is temporary, so the underlying enemy field remains
    -- provider-authored FRONT between captures.
    if e and e.__crystalAnimation and e.sprite then actor.enemy.liveFront=e.sprite end
  end

  local function applyRep(name,battle)
    if not (active() and battle) then return end
    if name=="player" and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then return end
    if name=="enemy" and (battle.showEnemyTrainer or battle.enemySendingOut) then return end
    local battler=battle[name]
    if not battler then return end
    local side=presentationSide(name)
    local img,scale=nil,1
    if crystal and side=="front" then
      img=actor[name].liveFront
      if not img then img,scale=staticRep(name,side,battle) end
    else
      img,scale=staticRep(name,side,battle)
    end
    if img then battler.sprite=img end
    actor[name].scale=(tonumber(scale) and tonumber(scale)>0) and tonumber(scale) or 1
  end

  -- Keep Crystal's real player-front animation alive under DYNAMIC without
  -- changing the user's saved Crystal option.  This is the same lifecycle
  -- ownership rule already proven on Dramaless.
  if crystal and type(BattleState.update)=="function"
      and not BattleState.__bcSpriteFacingPotatoVoxelInstalled then
    local innerUpdate=BattleState.update
    BattleState.update=function(self,dt,...)
      resetBattle(self)
      local prior=crystalPref()
      if dynamic() then
        if actor.player.liveFront and self.player and not self.showPlayerBack then
          self.player.sprite=actor.player.liveFront
        end
        if actor.enemy.liveFront and self.enemy and not self.showEnemyTrainer then
          self.enemy.sprite=actor.enemy.liveFront
        end
        setCrystal(true)
      end
      local r={pcall(innerUpdate,self,dt,...)}
      -- Capture the player stream only while Crystal FRONT is authoritative.
      -- Do not persist a camera-selected FRONT/BACK image into the battler after
      -- update; Potato sideTexture borrows that representation for one capture
      -- and restores the provider-owned sprite immediately.
      captureLives(self,dynamic())
      if dynamic() and prior~=nil then setCrystal(prior) end
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      return unpack_(r)
    end
    BattleState.__bcSpriteFacingPotatoVoxelInstalled=true
  end

  local function desiredMirror(name)
    local side=presentationSide(name)
    local opponentRight=(actor[name].turn=="right")
    -- PotatoVoxel's BattleScene documents raw FRONT art as facing left: its
    -- ordinary player card is mirrored and its enemy card is not.  Native BACK
    -- art is authored in the opposite direction.  Translate the universal BC
    -- turn semantic into that host convention; no species knowledge involved.
    if side=="front" then return not opponentRight end
    return opponentRight
  end

  local function flipCanvas(src,key)
    if not (src and love and love.graphics and type(src.getDimensions)=="function") then return nil end
    local w,h=src:getDimensions()
    if not (w and h and w>0 and h>0) then return nil end
    local rec=flipped[key]
    if not rec or rec.w~=w or rec.h~=h then
      local ok,c=pcall(love.graphics.newCanvas,w,h,{dpiscale=1})
      if not ok or not c then return nil end
      if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
      rec={canvas=c,w=w,h=h}; flipped[key]=rec
    end
    local g=love.graphics
    local prev=g.getCanvas()
    local bm,ba=g.getBlendMode()
    local cr,cg,cb,ca=g.getColor()
    local ok=pcall(function()
      g.setCanvas(rec.canvas); g.clear(0,0,0,0); g.setBlendMode("alpha")
      g.setColor(1,1,1,1); g.draw(src,w,0,0,-1,1)
    end)
    if prev then g.setCanvas(prev) else g.setCanvas() end
    g.setBlendMode(bm or "alpha",ba); g.setColor(cr,cg,cb,ca)
    if not ok then return nil end
    return rec.canvas,w
  end

  local originalSideTexture=OverworldBattle.sideTexture
  OverworldBattle.sideTexture=function(battle,side)
    if not active() then return originalSideTexture(battle,side) end
    resetBattle(battle)
    updateOrientation()

    -- Rebase54 adopts the already-proven Ascendant ownership rule: the
    -- camera-selected card is a ONE-CAPTURE representation, never persistent
    -- battler state. This prevents Potato's Dynamic BACK from contaminating the
    -- cached Crystal FRONT stream and removes the apparent extra BACK animation
    -- frame in the PiP.
    local battler=battle and battle[side] or nil
    local repSide=presentationSide(side)
    local displayScale=1
    local priorSprite=nil
    local swapped=false
    local canBorrow=(side=="player" or side=="enemy") and battler~=nil
    if side=="player" and battle
        and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then
      canBorrow=false
    elseif side=="enemy" and battle
        and (battle.showEnemyTrainer or battle.enemySendingOut) then
      canBorrow=false
    end
    if canBorrow then
      local img=nil
      if crystal and repSide=="front" and actor[side].liveFront then
        img=actor[side].liveFront
      else
        img,displayScale=staticRep(side,repSide,battle)
      end
      displayScale=(tonumber(displayScale) and tonumber(displayScale)>0) and tonumber(displayScale) or 1
      actor[side].scale=displayScale
      if img then
        priorSprite=battler.sprite
        battler.sprite=img
        swapped=true
      end
    end

    -- Dynamic vanilla BACK is a real 32px Gen1 back picture. The Shape-family
    -- host deliberately forces battle-card capture to 1x while texturing,
    -- because its normal staged mode only ever asks for 56px FRONT art. Once
    -- BC legitimately selects BACK, that same 1x rule makes the genuine back
    -- look tiny. Re-expose ONLY this selected card's host-native integer scale
    -- for the duration of this one sideTexture render. No global scale hook,
    -- no camera compensation, and Crystal keeps its already-good provider path.
    local savedResolve=nil
    if dynamic() and not crystal and presentationSide(side)=="back"
        and type(BattleState.resolveBattleScale)=="function" then
      local factor=tonumber(actor[side].scale) or 1
      if factor<=1.001 and type(OverworldBattle.SLOT_W)=="table" then
        local fw=tonumber(OverworldBattle.SLOT_W.front)
        local bw=tonumber(OverworldBattle.SLOT_W.back)
        if fw and bw and bw>0 then factor=math.max(1,math.floor(fw/bw+0.5)) end
      end
      if factor>1.001 and factor<8 then
        savedResolve=BattleState.resolveBattleScale
        BattleState.resolveBattleScale=function(...) return factor end
      end
    end
    local r={pcall(originalSideTexture,battle,side)}
    if savedResolve then BattleState.resolveBattleScale=savedResolve end
    if swapped then battler.sprite=priorSprite end
    if not r[1] then error(r[2],0) end
    local tex=r[2]
    if not (tex and not tex.trainer and tex.canvas) then return tex end

    local hostMirror=(side=="player") -- PotatoVoxel's documented monCards default.
    local want=desiredMirror(side)
    if hostMirror~=want then
      local c,w=flipCanvas(tex.canvas,side)
      if c then
        tex.canvas=c
        if tonumber(tex.ax) then tex.ax=w-tonumber(tex.ax) end
      end
    end
    return tex
  end

  -- Rebase53 Potato Secondary View fixed-FRONT producer. Vanilla keeps the
  -- provider's proven sideTexture capture. Crystal is deliberately different:
  -- its live animation hook can choose FRONT/BACK from the primary camera while
  -- sideTexture is being captured, so feeding battler.sprite is not a hard
  -- representation lock. For Crystal only, build the canonical 160x144 carrier
  -- directly from the already-owned animated FRONT frame. This is the exact
  -- flat-portrait contract used across BC: max 56px subject, X=80, feet Y=96;
  -- PIP SIDE alone owns horizontal handedness. No main-camera state is read.
  local secondaryCardCanvas=nil
  local secondaryCardW,secondaryCardH=nil,nil

  local function ensureSecondaryCanvas(w,h)
    if secondaryCardCanvas and secondaryCardW==w and secondaryCardH==h then
      return secondaryCardCanvas
    end
    if secondaryCardCanvas and type(secondaryCardCanvas.release)=="function" then
      pcall(secondaryCardCanvas.release,secondaryCardCanvas)
    end
    local okC,c=pcall(love.graphics.newCanvas,w,h,{dpiscale=1})
    if not (okC and c) then return nil end
    if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
    secondaryCardCanvas,secondaryCardW,secondaryCardH=c,w,h
    return c
  end

  local function copyProviderCard(tex)
    if not (tex and tex.canvas and type(tex.canvas.getDimensions)=="function") then return nil,"provider card unavailable" end
    local w,h=tex.canvas:getDimensions()
    if not (w and h and w>0 and h>0) then return nil,"provider card dimensions unavailable" end
    local out=ensureSecondaryCanvas(w,h)
    if not out then return nil,"private card canvas unavailable" end
    local g=love.graphics
    local prior=nil
    if type(g.getCanvas)=="function" then local okP,v=pcall(g.getCanvas); if okP then prior=v end end
    local pushed=false
    local okCopy,errCopy=pcall(function()
      g.push("all"); pushed=true
      g.origin(); g.setCanvas(out); g.clear(0,0,0,0)
      if g.setShader then g.setShader() end
      g.setBlendMode("alpha"); g.setColor(1,1,1,1)
      if (mod.options:get("secondaryViewSide") or "left")=="right" then
        g.draw(tex.canvas,w,0,0,-1,1)
      else
        g.draw(tex.canvas,0,0)
      end
    end)
    if pushed then pcall(g.pop) end
    if prior~=nil then pcall(g.setCanvas,prior) else pcall(g.setCanvas) end
    if not okCopy then return nil,"private card copy failed: "..tostring(errCopy) end
    local ax=tonumber(tex.ax) or tonumber(OverworldBattle.TEX_AX) or 80
    if (mod.options:get("secondaryViewSide") or "left")=="right" then ax=w-ax end
    return {canvas=out,ax=ax,ay=tonumber(tex.ay) or tonumber(OverworldBattle.TEX_AY) or 96,trainer=false},"provider_front"
  end

  local function crystalFrontCard(img)
    if not (img and type(img.getDimensions)=="function") then return nil,"Crystal FRONT frame unavailable" end
    local okD,iw,ih=pcall(img.getDimensions,img)
    iw,ih=tonumber(iw),tonumber(ih)
    if not (okD and iw and ih and iw>0 and ih>0) then return nil,"Crystal FRONT dimensions unavailable" end
    local w,h=160,144
    local out=ensureSecondaryCanvas(w,h)
    if not out then return nil,"private Crystal card canvas unavailable" end
    local scale=56/math.max(iw,ih)
    local mirror=(mod.options:get("secondaryViewSide") or "left")=="right"
    local dx=mirror and -scale or scale
    local x=80-(iw*dx)/2
    local y=96-ih*scale
    local g=love.graphics
    local prior=nil
    if type(g.getCanvas)=="function" then local okP,v=pcall(g.getCanvas); if okP then prior=v end end
    local pushed=false
    local okDraw,errDraw=pcall(function()
      g.push("all"); pushed=true
      g.origin(); g.setCanvas(out); g.clear(0,0,0,0)
      if g.setShader then g.setShader() end
      g.setBlendMode("alpha"); g.setColor(1,1,1,1)
      g.draw(img,x,y,0,dx,scale)
    end)
    if pushed then pcall(g.pop) end
    if prior~=nil then pcall(g.setCanvas,prior) else pcall(g.setCanvas) end
    if not okDraw then return nil,"Crystal FRONT card draw failed: "..tostring(errDraw) end
    return {canvas=out,ax=80,ay=96,trainer=false},"crystal_live_front_locked"
  end

  OverworldBattle.__bcSecondaryViewPlayerTexture=function()
    local battle=state.battle or battleRef
    if not (battle and battle.player) then return nil,"battle/player unavailable" end
    resetBattle(battle)
    -- Never sample battle.player.sprite from the PiP producer. Under Dynamic it
    -- may be whichever representation the main staged card most recently used.
    -- liveFront advances only from the authoritative Crystal FRONT update above.

    if crystal and actor.player.liveFront then
      return crystalFrontCard(actor.player.liveFront)
    end

    local img=select(1,staticRep("player","front",battle))
    if not img then return nil,"fixed FRONT unavailable" end
    local battler=battle.player
    local savedSprite=battler.sprite
    local savedShow=battle.showPlayerBack
    battler.sprite=img
    battle.showPlayerBack=false
    local okTex,tex=pcall(originalSideTexture,battle,"player")
    battler.sprite=savedSprite
    battle.showPlayerBack=savedShow
    if not okTex then return nil,tostring(tex) end
    return copyProviderCard(tex)
  end

  local originalFinish=OverworldBattle.finish
  if type(originalFinish)=="function" then
    OverworldBattle.finish=function(...)
      battleRef=nil; imageCache={}
      return originalFinish(...)
    end
  end
  local originalInvalidate=OverworldBattle.invalidate
  if type(originalInvalidate)=="function" then
    OverworldBattle.invalidate=function(...)
      flipped={}
      return originalInvalidate(...)
    end
  end

  OverworldBattle.__bcSpriteFacingPotatoVoxelInstalled=true
  mod.log:info("PotatoVoxel sprite-facing adapter active: genuine back seam + scoped vanilla-back scale + final-camera orientation; model rungs yielded")
end)()



-- PotatoVoxel Secondary View ------------------------------------------------
-- Rebase53 preserves Rebase52's proven Potato staged-world camera/renderer and
-- changes actor sourcing only: Crystal is a truly fixed animated FRONT carrier,
-- while Stadium2 Importer uses the same independent public 3D presentation
-- Actor/APB camera language already accepted on Battle Art and Ascendant.
;(function()
  local P=state.secondaryViewProbe
  local handle=mod.find("potato_voxel")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  if not (P and V and type(V.require)=="function") then return end

  local function req(name)
    local ok,v=pcall(V.require,name)
    return ok and type(v)=="table" and v or nil
  end
  local OB=req("OverworldBattle")
  local BS=req("BattleScene")
  local BB=req("BattleBillboard")
  local V3=req("Voxel3D")
  local AA=req("AntiAlias")
  local UP=req("Upscale")
  local M4=req("Mat4")
  local VS=req("VoxelScene")
  local DA=req("DiscArena")
  local VState=req("VoxelState")
  local Sky=req("Sky")
  if not (OB and BS and BB and V3 and AA and UP and M4 and VS and DA and VState
      and type(OB.stage)=="function"
      and type(OB.enabled)=="function"
      and type(OB.__bcSecondaryViewPlayerTexture)=="function"
      and type(BS.render)=="function"
      and type(BB.FULL_W)=="number") then
    P.potatoFailure="Potato exported staged-world contract incomplete"
    return
  end

  local backend=nil
  for _,b in ipairs(backends) do if b.id=="potato_voxel" then backend=b; break end end
  if not backend then P.potatoFailure="Potato BattleCam backend unavailable"; return end

  P.potatoBackend=backend
  P.potatoModules={OverworldBattle=OB,BattleScene=BS,BattleBillboard=BB,
    Voxel3D=V3,AntiAlias=AA,Upscale=UP,Mat4=M4,VoxelScene=VS,DiscArena=DA,VoxelState=VState}

  local function lifecycleEligible()
    if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
    -- Do NOT gate on state.backendId. In the mixed-provider configuration that
    -- matters most here, Potato owns the staged WORLD while Stadium2 Importer
    -- owns the live battle presentation/model. Rebase38 established that world
    -- eligibility and actor ownership are independent contracts. OB.stage()
    -- below is the authoritative Potato-world signal.
    if not (state.battle and state.active) then return false end
    if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
    if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
    if state.attack and (state.attack.pending or state.attack.active) then return false end
    if state.faint and (state.faint.pending or state.faint.active) then return false end
    local b=state.battle
    if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
    return true
  end

  local function importerContext()
    local h=mod.find("STADIUM2_IMPORTER")
    local x=h and h.exports or nil
    local presentation=x and x.presentation or nil
    if not (x and presentation and type(presentation.newActor)=="function") then return nil end
    local function flag(name)
      local fn=x[name]
      if type(fn)~="function" then return false end
      local ok,v=pcall(fn)
      if not ok then ok,v=pcall(fn,x) end
      return ok and v==true
    end
    if not (flag("modelsEnabled") and flag("battleEnabled")) then return nil end
    return x,presentation
  end

  local function monForBattle(battle)
    local battler=battle and battle.player or nil
    local mon=battler and battler.mon or nil
    if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
    return type(mon)=="table" and mon or nil
  end

  local function resolveImporterActor(battle)
    local x,presentation=importerContext()
    P.potatoImporterRequested=(x~=nil)
    P.potatoImporterFailure=nil
    if not x then return nil end
    local mon=monForBattle(battle)
    if not mon then P.potatoImporterFailure="player mon unavailable"; return nil end
    local actor=P.potatoImporterActor
    if not actor then
      local ok,a=pcall(presentation.newActor,"player",{label="BC Potato Secondary View"})
      if not (ok and type(a)=="table") then
        P.potatoImporterFailure="Importer Actor.new failed: "..tostring(a); return nil
      end
      actor=a; P.potatoImporterActor=actor
    end
    if P.potatoImporterMon~=mon or not actor.renderer then
      local okLoad,loaded=pcall(actor.load,actor,battle and battle.data or nil,mon,nil)
      if not (okLoad and loaded and actor.renderer) then
        if type(actor.release)=="function" then pcall(actor.release,actor) end
        P.potatoImporterActor=nil; P.potatoImporterMon=nil
        P.potatoImporterFailure="Importer player actor load failed"; return nil
      end
      P.potatoImporterMon=mon; P.potatoImporterLastTime=nil
    end
    local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
    local dt=P.potatoImporterLastTime and (now-P.potatoImporterLastTime) or 0.10
    P.potatoImporterLastTime=now
    dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10))
    if type(actor.update)=="function" then pcall(actor.update,actor,dt) end
    return actor
  end

  local function importerBounds(actor)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.poseBounds)=="function" and type(renderer.worldMetrics)=="function") then return nil end
    local okB,b=pcall(renderer.poseBounds,renderer)
    local okM,m=pcall(renderer.worldMetrics,renderer)
    if not (okB and okM and type(b)=="table" and type(m)=="table") then return nil end
    local minX,maxX=tonumber(b.minX),tonumber(b.maxX)
    local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
    local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ)
    local modelH=tonumber(m.height)
    if not (minX and maxX and minY and maxY and minZ and maxZ and modelH and modelH>1e-4 and maxY>minY) then return nil end
    local worldH=math.max(5,math.min(18,14*math.sqrt(modelH/52.25)))
    local k=worldH/modelH
    local floor=tonumber(m.floor) or 0
    local hover=math.min(math.max(floor,0),modelH*0.5)
    local offset=floor-hover
    local bottom=(minY-offset)*k
    local top=(maxY-offset)*k
    local height=top-bottom
    if height<=1e-3 then return nil end
    local sx=math.max(0,(maxX-minX)*k)
    local sz=math.max(0,(maxZ-minZ)*k)
    local breadth=math.sqrt(sx*sx+sz*sz)
    local elevation=math.max(0,bottom)
    local elevationNorm=elevation/height
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,
      breadth=breadth,spanX=sx,spanZ=sz,breadthHeightRatio=breadth/math.max(1e-3,height),
      elevation=elevation,elevationNorm=elevationNorm,
      source="STADIUM2_IMPORTER_POTATO_POSED_V1",confidence="medium"}
  end

  local function drawImporter(actor,cam,arena,groundY)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.worldMetrics)=="function" and type(renderer.drawScene)=="function") then
      return false,"Importer actor renderer unavailable"
    end
    local okM,metrics=pcall(renderer.worldMetrics,renderer)
    local height=okM and metrics and tonumber(metrics.height) or nil
    if not (height and height>1e-4) then return false,"Importer actor metrics unavailable" end
    local okIR,IR=pcall(require,"mods.STADIUM2_IMPORTER.lib.renderer")
    if not (okIR and type(IR)=="table" and type(IR.lookAt)=="function" and type(IR.normalMatrix)=="function") then
      return false,"Importer shared-scene renderer API unavailable"
    end
    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2])
    local ex,ez=tonumber(arena.enemy[1]),tonumber(arena.enemy[2])
    if not (px and pz and ex and ez) then return false,"Potato arena actor anchors unavailable" end
    local worldH=math.max(5,math.min(18,14*math.sqrt(height/52.25)))
    local grow=type(actor.scale)=="function" and actor:scale() or 1
    grow=math.max(0,math.min(1,tonumber(grow) or 1))
    local k=worldH/height*grow
    local floor=tonumber(metrics.floor) or 0
    local hover=math.min(math.max(floor,0),height*0.5)
    local yaw=math.atan2(ex-px,ez-pz)
    local model=M4.mul(M4.translate(px,groundY,pz),
      M4.mul(M4.rotateY(yaw),M4.mul(M4.scale(k,k,k),M4.translate(0,-(floor-hover),0))))
    local viewMatrix=IR.lookAt(cam.eye[1],cam.eye[2],cam.eye[3],cam.focus[1],cam.focus[2],cam.focus[3])
    local tint=V3.tint or {1,1,1}
    local ctx={viewProjection=V3.vp,viewMatrix=viewMatrix,normalMatrix=IR.normalMatrix(yaw,0,false),
      lightDir={0.35,0.7,0.62},ambient={0.46,0.46,0.46},diffuse={0.72,0.72,0.72},
      flipWinding=true,disableCulling=true,tint={tint[1] or 1,tint[2] or 1,tint[3] or 1,1},flashAmount=0}
    for _,pass in ipairs({"opaque","additive"}) do
      local okD,a,b=pcall(renderer.drawScene,renderer,pass,model,ctx)
      if not okD then return false,"Importer actor draw error: "..tostring(a) end
      if a==false then return false,"Importer actor draw rejected: "..tostring(b) end
    end
    return true
  end

  P.potatoEligible=function()
    if not lifecycleEligible() then return false end
    local okE,v=pcall(OB.enabled); if not (okE and v) then return false end
    local okS,arena=pcall(OB.stage)
    return okS and type(arena)=="table" and type(arena.player)=="table" and type(arena.enemy)=="table"
  end

  -- Rebase55: keep the now-validated Rebase54 flat Potato renderer byte-for-byte
  -- in behavior, but NEVER send Stadium2 Importer through Potato's full
  -- BattleScene.render(). That renderer owns Potato's live staged battle/UI
  -- contract and is not a scene-neutral compositor. Rebase54 proved the actor
  -- itself is valid (it appeared initially), then BattleScene returned nil and
  -- provider presentation disappeared with it. For Importer only, use Potato's
  -- public lower-level world renderer (MAP) or DiscArena geometry (B) and draw
  -- the already-proven public Importer Actor directly into that private scene.
  local function shallowPotatoWorld(world,arena)
    local view={}
    for k,v in pairs(world or {}) do view[k]=v end
    view.entities={}
    view.ghosts={}
    view.flyAnim=nil
    view.camera={x=(arena.mid[1] or 0)-80,y=(arena.mid[2] or 0)-45}
    return view
  end

  local function renderImporterPrivate(importerActor,cam,arena,groundY)
    local GameModule=select(2,pcall(require,"src.core.Game"))
    local world=type(GameModule)=="table" and GameModule.overworld or nil
    if not (world and world.map) then return nil,"Potato read-only world unavailable" end
    if arena.map and arena.map~=world.map and not arena.discs then
      return nil,"Potato cross-floor MAP view deferred"
    end

    local g=love and love.graphics or nil
    if not g then return nil,"Potato graphics unavailable" end
    local unpack_=table.unpack or unpack
    local prevCanvas={}
    if type(g.getCanvas)=="function" then prevCanvas={g.getCanvas()} end
    local prevShader=type(g.getShader)=="function" and g.getShader() or nil
    local br,ba="alpha",nil
    if type(g.getBlendMode)=="function" then br,ba=g.getBlendMode() end
    local cr,cg,cb,ca=1,1,1,1
    if type(g.getColor)=="function" then cr,cg,cb,ca=g.getColor() end
    local dm,dw=nil,nil
    if type(g.getDepthMode)=="function" then dm,dw=g.getDepthMode() end
    local cull=type(g.getMeshCullMode)=="function" and g.getMeshCullMode() or nil

    local oldCamera=V3.camera
    local oldTint=V3.tint
    local oldFog=V3.fog
    local oldGlassMask,oldGlassNight=V3.glassMask,V3.glassNight
    local oldGlassPhase,oldGlassGlint=V3.glassPhase,V3.glassGlint
    local oldShadowAlpha=V3.SHADOW_ALPHA
    local oldReady=VState.ready
    local oldEnd=V3.endScene
    local canvas=nil
    local actorDrawn=false
    local actorErr=nil
    local okRender,errRender=pcall(function()
      V3.camera=cam
      if arena.discs then
        -- Potato B is a carried two-disc stage. Render exactly that provider
        -- geometry under the provider's own sky, without invoking BattleScene
        -- or any live BattleState/UI seam.
        local host=arena.map or world.map
        local sky=type(VS.skyColor)=="function" and VS.skyColor(host,1) or nil
        if not sky and type(VS.skyShade)=="function" then sky=VS.skyShade(4,1) end
        if sky and sky.bands and Sky and type(Sky.dress)=="function" then
          local okDress,dressed=pcall(Sky.dress,sky)
          if okDress and dressed then sky=dressed end
        end
        if not V3.beginScene(320,180,arena.mid[1],arena.mid[2],160,90,sky,
            "bc_secondary_potato_importer") then
          error("Potato private disc beginScene declined: "..tostring(V3.beginFailure),0)
        end
        DA.draw(arena,groundY)
        local okD,why=drawImporter(importerActor,cam,arena,groundY)
        if not okD then error(tostring(why),0) end
        actorDrawn=true
        canvas=V3.endScene()
        if not canvas then error("Potato private disc endScene returned nil",0) end
      else
        -- MAP uses Potato's public overworld world renderer, but with an
        -- actor-free shallow state and BC's placed PiP camera. The Importer
        -- actor is inserted immediately before Potato closes this PRIVATE
        -- scene, mirroring the accepted Ascendant Rebase46 transplant.
        local view=shallowPotatoWorld(world,arena)
        V3.endScene=function(...)
          if not actorDrawn and not actorErr then
            local okD,why=drawImporter(importerActor,cam,arena,groundY)
            if okD then actorDrawn=true else actorErr=tostring(why) end
          end
          return oldEnd(...)
        end
        canvas=VS.render(view,320,180,160,90,nil)
        if actorErr then error("Importer actor in-scene draw failed: "..actorErr,0) end
        if not actorDrawn then error("Importer actor was not reached by Potato VoxelScene.endScene",0) end
        if not canvas then error("Potato public VoxelScene.render returned nil",0) end
      end
    end)

    V3.endScene=oldEnd
    V3.camera=oldCamera
    V3.tint=oldTint
    V3.fog=oldFog
    V3.glassMask,V3.glassNight=oldGlassMask,oldGlassNight
    V3.glassPhase,V3.glassGlint=oldGlassPhase,oldGlassGlint
    V3.SHADOW_ALPHA=oldShadowAlpha
    VState.ready=oldReady
    pcall(function()
      if #prevCanvas>0 then g.setCanvas(unpack_(prevCanvas)) else g.setCanvas() end
      if type(g.setShader)=="function" then g.setShader(prevShader) end
      if type(g.setDepthMode)=="function" then
        if dm then g.setDepthMode(dm,dw) else g.setDepthMode() end
      end
      if cull and type(g.setMeshCullMode)=="function" then g.setMeshCullMode(cull) end
      if type(g.setBlendMode)=="function" then
        if ba~=nil then g.setBlendMode(br,ba) else g.setBlendMode(br) end
      end
      g.setColor(cr,cg,cb,ca)
    end)
    if okRender and canvas and actorDrawn then return canvas end
    return nil,"Potato Importer private render error: "..tostring(errRender)
  end

  P.renderPotatoFrame=function()
    if not P.potatoEligible() then P.shot=nil; return end
    local battle=state.battle
    local okStage,arena,groundY=pcall(OB.stage)
    if not (okStage and type(arena)=="table") then P.shot=nil; P.failure="Potato stage unavailable"; return end
    groundY=tonumber(groundY) or 0

    local importerActor=resolveImporterActor(battle)
    if P.potatoImporterRequested and not importerActor then
      P.shot=nil; P.failure="Potato + Importer 3D actor unavailable: "..tostring(P.potatoImporterFailure or "unknown"); return
    end
    local actorMode=importerActor and "stadium2_importer" or "potato_2d"

    local tex,src=nil,nil
    if not importerActor then
      tex,src=OB.__bcSecondaryViewPlayerTexture()
      if not (tex and tex.canvas) then P.shot=nil; P.failure="Potato fixed FRONT unavailable: "..tostring(src); return end
    else
      src="stadium2_importer_actor"
    end

    local oldBounds=P._goldImporterBounds
    if importerActor then P._goldImporterBounds=importerBounds(importerActor) end
    local cam,pitch=P.cameraFor(backend,arena,groundY,actorMode)
    P._goldImporterBounds=oldBounds
    if not cam then P.shot=nil; P.failure="Potato Secondary View camera unavailable"; return end
    P.camera,P.pitch=cam,pitch

    if importerActor then
      local canvas,why=renderImporterPrivate(importerActor,cam,arena,groundY)
      if canvas then
        P.shot={canvas=canvas}; P.frames=(P.frames or 0)+1; P.failure=nil
        P.actorMode=actorMode; P.potatoLastSource=src
        if P.potatoLastLoggedMode~=actorMode then
          P.potatoLastLoggedMode=actorMode
          mod.log:warn("[SECONDARY VIEW] PotatoVoxel actor path: Stadium2 Importer genuine 3D")
        end
      else
        P.shot=nil; P.failure=tostring(why or "Potato Importer private render unavailable")
      end
      return
    end

    -- FLAT PATH: intentionally preserve validated Rebase54 behavior exactly.
    local oldLetterbox=BS.letterbox
    local oldRig=backend.BattleCam.rig
    local oldBegin=V3.beginScene
    local oldResolve=AA.resolve
    local oldUpscale=UP.apply
    local oldFullW=BB.FULL_W
    local oldCamera=V3.camera
    local oldRendering=P.rendering
    local oldBackend=P.backend
    local sceneSlot="bc_secondary_view_potato"

    local function restoreFlat()
      BS.letterbox=oldLetterbox; backend.BattleCam.rig=oldRig
      V3.beginScene=oldBegin
      AA.resolve=oldResolve; UP.apply=oldUpscale; BB.FULL_W=oldFullW
      V3.camera=oldCamera; P.rendering=oldRendering; P.backend=oldBackend
    end

    local okRender,shot=pcall(function()
      BS.letterbox=function() return 80,18,1,320,180 end
      backend.BattleCam.rig=function(_arena,_groundY,_canonical)
        return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},focus={cam.focus[1],cam.focus[2],cam.focus[3]},
          up={0,1,0},fov=cam.fov,curve=cam.curve or 0},pitch or bcPitchForCamera(cam)
      end
      V3.beginScene=function(w,h,cx,cy,vw,vh,sky,slot,...)
        if slot=="battle" then slot=sceneSlot end
        return oldBegin(w,h,cx,cy,vw,vh,sky,slot,...)
      end
      AA.resolve=function(canvas,w,h,slot,...)
        if slot=="battle" then slot=sceneSlot end
        return oldResolve(canvas,w,h,slot,...)
      end
      UP.apply=function(canvas,w,h,slot,...)
        if slot=="battle" then slot=sceneSlot end
        return oldUpscale(canvas,w,h,slot,...)
      end
      BB.FULL_W=oldFullW*0.58
      P.rendering=true; P.backend=backend
      local token=(P.potatoToken or 0)+1; P.potatoToken=token
      return BS.render(Game.overworld,arena,{player=tex,flash=false},token)
    end)
    restoreFlat()

    if okRender and type(shot)=="table" and shot.canvas then
      P.shot={canvas=shot.canvas}; P.frames=(P.frames or 0)+1; P.failure=nil
      P.actorMode=actorMode; P.potatoLastSource=src
      if P.potatoLastLoggedMode~=actorMode then
        P.potatoLastLoggedMode=actorMode
        mod.log:warn("[SECONDARY VIEW] PotatoVoxel actor path: fixed-FRONT flat portrait")
      end
    else
      P.shot=nil; P.failure=okRender and ("Potato render returned "..tostring(shot)) or ("Potato render error: "..tostring(shot))
    end
  end

  mod.log:warn("[SECONDARY VIEW] PotatoVoxel flat/Crystal + Stadium2 Importer adapter armed")
end)()



-- Dramatic Shape Secondary View --------------------------------------------
-- Rebase56 treats base Dramatic as what it actually is: the upstream staged
-- battle architecture many supported forks descend from. The private PiP uses
-- Dramatic's own BattleScene/BattleCam/world geometry, but owns only one player
-- presentation: fixed-FRONT flat art, an independent native StadiumMon, or an
-- independent Stadium2 Importer Actor. The live battle/UI renderer is never
-- re-entered and no provider is asked to surrender its main presentation.
;(function()
  local P=state.secondaryViewProbe
  local handle=mod.find("DRAMATIC_SHAPE")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  if not (P and V and type(V.require)=="function") then return end
  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local OB=req("OverworldBattle")
  local BS=req("BattleScene")
  local BB=req("BattleBillboard")
  local V3=req("Voxel3D")
  local AA=req("AntiAlias")
  local VS=req("VoxelScene")
  local VState=req("VoxelState")
  local Stage=req("StadiumStage")
  local Sky=req("Sky")
  local Stadium=req("Stadium")
  local StadiumMon=req("StadiumMon")
  if not (OB and BS and BB and V3 and AA and VS and VState and Stage and Sky and Stadium and StadiumMon
      and type(OB.stage)=="function" and type(BS.render)=="function"
      and type(OB.__bcSecondaryViewPlayerTexture)=="function") then
    P.dramaticFailure="Dramatic exported staged-world contract incomplete"
    return
  end
  local backend=nil
  for _,b in ipairs(backends) do if b.id=="DRAMATIC_SHAPE" then backend=b; break end end
  if not backend then P.dramaticFailure="Dramatic BattleCam backend unavailable"; return end
  P.dramaticBackend=backend
  P.dramaticModules={OverworldBattle=OB,BattleScene=BS,BattleBillboard=BB,
    Voxel3D=V3,AntiAlias=AA,VoxelScene=VS,VoxelState=VState,StadiumStage=Stage,Sky=Sky,
    Stadium=Stadium,StadiumMon=StadiumMon}

  local function lifecycleEligible()
    if not enabled() or (mod.options:get("secondaryView") or "off")~="on" then return false end
    if not (state.battle and state.active) then return false end
    if state.battleOpening and (state.battleOpening.pending or state.battleOpening.active) then return false end
    if state.intro and (state.intro.active or state.intro.pendingEnemy or state.intro.pendingPlayer) then return false end
    if state.attack and (state.attack.pending or state.attack.active) then return false end
    if state.faint and (state.faint.pending or state.faint.active) then return false end
    local b=state.battle
    if b and (b.showEnemyTrainer or b.showPlayerBack or b.enemySendingOut or b.sendingOut) then return false end
    return true
  end

  local function importerContext()
    local p=mod.find("STADIUM2_IMPORTER")
    local x=p and p.exports or nil
    local presentation=x and x.presentation or nil
    if not (x and presentation and type(presentation.newActor)=="function") then return nil end
    local function flag(name)
      local fn=x[name]; if type(fn)~="function" then return false end
      local ok,v=pcall(fn); if not ok then ok,v=pcall(fn,x) end
      return ok and v==true
    end
    if not (flag("modelsEnabled") and flag("battleEnabled")) then return nil end
    return x,presentation
  end
  local function monForBattle(battle)
    local battler=battle and battle.player or nil
    local mon=battler and battler.mon or nil
    if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
    return type(mon)=="table" and mon or nil
  end
  local function resolveImporterActor(battle)
    local x,presentation=importerContext()
    P.dramaticImporterRequested=(x~=nil); P.dramaticImporterFailure=nil
    if not x then return nil end
    local mon=monForBattle(battle); if not mon then P.dramaticImporterFailure="player mon unavailable"; return nil end
    local actor=P.dramaticImporterActor
    if not actor then
      local ok,a=pcall(presentation.newActor,"player",{label="BC Dramatic Secondary View"})
      if not (ok and type(a)=="table") then P.dramaticImporterFailure="Importer Actor.new failed: "..tostring(a); return nil end
      actor=a; P.dramaticImporterActor=actor
    end
    if P.dramaticImporterMon~=mon or not actor.renderer then
      local okLoad,loaded=pcall(actor.load,actor,battle and battle.data or nil,mon,nil)
      if not (okLoad and loaded and actor.renderer) then
        if type(actor.release)=="function" then pcall(actor.release,actor) end
        P.dramaticImporterActor=nil; P.dramaticImporterMon=nil
        P.dramaticImporterFailure="Importer player actor load failed"; return nil
      end
      P.dramaticImporterMon=mon; P.dramaticImporterLastTime=nil
    end
    local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
    local dt=P.dramaticImporterLastTime and (now-P.dramaticImporterLastTime) or 0.10
    P.dramaticImporterLastTime=now; dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10))
    if type(actor.update)=="function" then pcall(actor.update,actor,dt) end
    return actor
  end
  local function importerBounds(actor)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.poseBounds)=="function" and type(renderer.worldMetrics)=="function") then return nil end
    local okB,b=pcall(renderer.poseBounds,renderer); local okM,m=pcall(renderer.worldMetrics,renderer)
    if not (okB and okM and type(b)=="table" and type(m)=="table") then return nil end
    local minX,maxX=tonumber(b.minX),tonumber(b.maxX); local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
    local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ); local modelH=tonumber(m.height)
    if not (minX and maxX and minY and maxY and minZ and maxZ and modelH and modelH>1e-4 and maxY>minY) then return nil end
    local worldH=math.max(5,math.min(18,14*math.sqrt(modelH/52.25))); local k=worldH/modelH
    local floor=tonumber(m.floor) or 0; local hover=math.min(math.max(floor,0),modelH*0.5); local offset=floor-hover
    local bottom=(minY-offset)*k; local top=(maxY-offset)*k; local height=top-bottom; if height<=1e-3 then return nil end
    local sx=math.max(0,(maxX-minX)*k); local sz=math.max(0,(maxZ-minZ)*k); local breadth=math.sqrt(sx*sx+sz*sz)
    local elevation=math.max(0,bottom); local elevationNorm=elevation/height; if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,breadth=breadth,
      spanX=sx,spanZ=sz,breadthHeightRatio=breadth/math.max(1e-3,height),elevation=elevation,elevationNorm=elevationNorm,
      source="STADIUM2_IMPORTER_DRAMATIC_POSED_V1",confidence="medium"}
  end

  local function drawImporter(actor,cam,arena,groundY)
    local renderer=actor and actor.renderer or nil
    if not (renderer and type(renderer.worldMetrics)=="function" and type(renderer.drawScene)=="function") then return false,"Importer actor renderer unavailable" end
    local okM,metrics=pcall(renderer.worldMetrics,renderer); local height=okM and metrics and tonumber(metrics.height) or nil
    if not (height and height>1e-4) then return false,"Importer actor metrics unavailable" end
    local okIR,IR=pcall(require,"mods.STADIUM2_IMPORTER.lib.renderer")
    local okM4,M4=pcall(V.require,"Mat4")
    if not (okIR and type(IR)=="table" and type(IR.lookAt)=="function" and type(IR.normalMatrix)=="function"
        and okM4 and type(M4)=="table") then return false,"Importer shared-scene renderer API unavailable" end
    local px,pz=tonumber(arena.player[1]),tonumber(arena.player[2]); local ex,ez=tonumber(arena.enemy[1]),tonumber(arena.enemy[2])
    if not (px and pz and ex and ez) then return false,"Dramatic arena actor anchors unavailable" end
    local worldH=math.max(5,math.min(18,14*math.sqrt(height/52.25))); local grow=type(actor.scale)=="function" and actor:scale() or 1
    grow=math.max(0,math.min(1,tonumber(grow) or 1)); local k=worldH/height*grow
    local floor=tonumber(metrics.floor) or 0; local hover=math.min(math.max(floor,0),height*0.5); local yaw=math.atan2(ex-px,ez-pz)
    local model=M4.mul(M4.translate(px,groundY,pz),M4.mul(M4.rotateY(yaw),M4.mul(M4.scale(k,k,k),M4.translate(0,-(floor-hover),0))))
    local viewMatrix=IR.lookAt(cam.eye[1],cam.eye[2],cam.eye[3],cam.focus[1],cam.focus[2],cam.focus[3])
    local tint=V3.tint or {1,1,1}; local ctx={viewProjection=V3.vp,viewMatrix=viewMatrix,normalMatrix=IR.normalMatrix(yaw,0,false),
      lightDir={0.35,0.7,0.62},ambient={0.46,0.46,0.46},diffuse={0.72,0.72,0.72},flipWinding=true,disableCulling=true,
      tint={tint[1] or 1,tint[2] or 1,tint[3] or 1,1},flashAmount=0}
    for _,pass in ipairs({"opaque","additive"}) do
      local okD,a,b=pcall(renderer.drawScene,renderer,pass,model,ctx)
      if not okD then return false,"Importer actor draw error: "..tostring(a) end
      if a==false then return false,"Importer actor draw rejected: "..tostring(b) end
    end
    return true
  end

  local function dexForBattle(battle)
    local mon=monForBattle(battle); if not mon then return nil end
    local species=mon.species
    if type(species)=="number" then local n=math.floor(species); if n>=1 and n<=151 then return n end end
    local def=battle and battle.data and battle.data.pokemon and battle.data.pokemon[species] or nil
    local n=def and tonumber(def.dex or def.index) or nil; if n then n=math.floor(n); if n>=1 and n<=151 then return n end end
    return nil
  end
  local function nativeBounds(actor)
    local rig,model=actor and actor.rig,actor and actor.model
    if not (rig and model and type(rig.posedBounds)=="function" and type(actor.worldHeight)=="function") then return nil end
    local ok,lx,ly,lz,hx,hy,hz=pcall(rig.posedBounds,rig)
    lx,ly,lz,hx,hy,hz=tonumber(lx),tonumber(ly),tonumber(lz),tonumber(hx),tonumber(hy),tonumber(hz)
    if not (ok and lx and ly and lz and hx and hy and hz and hx>=lx and hy>ly and hz>=lz) then return nil end
    local modelH=tonumber(model.height) or 0; if modelH<=1e-4 then return nil end
    local root=tonumber(model.rootScale) or 1; if root<=0 then root=1 end
    local okH,worldH=pcall(actor.worldHeight,actor); worldH=okH and tonumber(worldH) or nil; if not (worldH and worldH>0) then return nil end
    local floor=tonumber(model.floor) or 0; local hoverCap=tonumber(StadiumMon.HOVER_CAP) or 0.5
    local hover=math.min(math.max(floor,0),hoverCap*modelH); local lift=(floor-hover)/root; local k=root*worldH/modelH
    local bottom=(ly-lift)*k; local top=(hy-lift)*k; local height=top-bottom; if height<=1e-3 then return nil end
    local sx=(hx-lx)*k; local sz=(hz-lz)*k; local breadth=math.sqrt(sx*sx+sz*sz)
    local elevation=math.max(0,bottom); local elevationNorm=elevation/height; if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,breadth=breadth,
      spanX=sx,spanZ=sz,breadthHeightRatio=breadth/math.max(1e-3,height),elevation=elevation,elevationNorm=elevationNorm,
      source="DRAMATIC_NATIVE_STADIUM_POSED_V1",confidence="medium"}
  end
  local function resolveNativeActor(battle,arena,groundY)
    local okSel,selected=pcall(OB.stadium); if not (okSel and selected) then return nil,false end
    local okShow,show=pcall(Stadium.showing,"player"); if not (okShow and show) then return nil,false end
    local dex=dexForBattle(battle); if not dex then P.dramaticNativeFailure="player dex unavailable"; return nil,true end
    local actor=P.dramaticNativeActor
    if not actor then actor=StadiumMon.new("player"); P.dramaticNativeActor=actor end
    if P.dramaticNativeDex~=dex or not actor.rig then
      local okSet,ready=pcall(actor.setSpecies,actor,dex)
      if not (okSet and ready and actor.rig) then P.dramaticNativeFailure="native Stadium model unavailable"; return nil,true end
      P.dramaticNativeDex=dex; P.dramaticNativeLastTime=nil
    end
    local now=((love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock())
    local dt=P.dramaticNativeLastTime and (now-P.dramaticNativeLastTime) or 0.10; P.dramaticNativeLastTime=now
    dt=math.max(0,math.min(0.20,tonumber(dt) or 0.10)); pcall(actor.update,actor,dt)
    local px,pz=arena.player[1],arena.player[2]; local ex,ez=arena.enemy[1],arena.enemy[2]
    actor.scale=1; actor.model_matrix=actor:matrix(px,groundY,pz,ex-px,ez-pz)
    local okBuild,built=pcall(actor.build,actor)
    if not (okBuild and built and actor.rig and actor.model_matrix) then P.dramaticNativeFailure="native Stadium actor build failed"; return nil,true end
    P.dramaticNativeFailure=nil
    return actor,true
  end

  -- Rebase58: Stadium2 Importer must never re-enter Dramatic's full
  -- BattleScene.render(). Rebase56 runtime proved that path can return nil
  -- after the opening and, worse, disturb the live provider/UI render state
  -- all the way through battle exit (persistent white screen). Flat/Crystal
  -- already pass A+B and remain on the validated staged renderer. Importer
  -- alone gets the same lower-level private-world architecture proven by
  -- Potato Rebase55 and Ascendant Rebase46.
  local function shallowDramaticWorld(world,arena)
    local view={}
    for k,v in pairs(world or {}) do view[k]=v end
    local mt=getmetatable(world)
    if mt then setmetatable(view,mt) end
    view.entities={}
    view.ghosts={}
    view.flyAnim=nil
    view.camera={x=(arena.mid[1] or 0)-80,y=(arena.mid[2] or 0)-45}
    return view
  end

  local function renderDramaticImporterPrivate(importerActor,cam,arena,groundY)
    local okGame,GameModule=pcall(require,"src.core.Game")
    local world=okGame and type(GameModule)=="table" and GameModule.overworld or nil
    if not (world and world.map) then return nil,"Dramatic read-only world unavailable" end
    if arena.map and arena.map~=world.map and not arena.discs then
      return nil,"Dramatic cross-floor MAP view deferred"
    end

    local g=love and love.graphics or nil
    if not g then return nil,"Dramatic graphics unavailable" end
    local unpack_=table.unpack or unpack
    local prevCanvas={}
    if type(g.getCanvas)=="function" then prevCanvas={g.getCanvas()} end
    local prevShader=type(g.getShader)=="function" and g.getShader() or nil
    local br,ba="alpha",nil
    if type(g.getBlendMode)=="function" then br,ba=g.getBlendMode() end
    local cr,cg,cb,ca=1,1,1,1
    if type(g.getColor)=="function" then cr,cg,cb,ca=g.getColor() end
    local dm,dw=nil,nil
    if type(g.getDepthMode)=="function" then dm,dw=g.getDepthMode() end
    local cull=type(g.getMeshCullMode)=="function" and g.getMeshCullMode() or nil

    local oldCamera=V3.camera
    local oldTint=V3.tint
    local oldFog=V3.fog
    local oldGlassMask,oldGlassNight=V3.glassMask,V3.glassNight
    local oldGlassPhase,oldGlassGlint=V3.glassPhase,V3.glassGlint
    local oldShadowAlpha=V3.SHADOW_ALPHA
    local oldReady=VState.ready
    local oldEnd=V3.endScene
    local canvas=nil
    local actorDrawn=false
    local actorErr=nil
    local okRender,errRender=pcall(function()
      V3.camera=cam
      if arena.discs then
        -- Dramatic B is the provider's carried StadiumStage. Draw only that
        -- geometry and the independent Importer actor into a private scene.
        local host=arena.map or world.map
        local sky=type(VS.skyColor)=="function" and VS.skyColor(host,1) or nil
        if not sky and type(VS.skyShade)=="function" then sky=VS.skyShade(4,1) end
        if sky and sky.bands and type(Sky.dress)=="function" then
          local okDress,dressed=pcall(Sky.dress,sky)
          if okDress and dressed then sky=dressed end
        elseif sky and type(VS.skyColor)=="function" and VS.skyColor(host,1)
            and type(Sky.dress)=="function" then
          -- Base Dramatic's BattleScene dresses outdoor B skies here too.
          local okDress,dressed=pcall(Sky.dress,sky)
          if okDress and dressed then sky=dressed end
        end
        if not V3.beginScene(320,180,arena.mid[1],arena.mid[2],160,90,sky,
            "bc_secondary_dramatic_importer") then
          error("Dramatic private disc beginScene declined: "..tostring(V3.beginFailure),0)
        end
        Stage.draw(arena,groundY)
        local okD,why=drawImporter(importerActor,cam,arena,groundY)
        if not okD then error(tostring(why),0) end
        actorDrawn=true
        canvas=V3.endScene()
        if not canvas then error("Dramatic private disc endScene returned nil",0) end
      else
        -- MAP: provider terrain/world only. Inject Importer immediately before
        -- this PRIVATE VoxelScene closes its scene; never touch live BattleScene.
        local view=shallowDramaticWorld(world,arena)
        V3.endScene=function(...)
          if not actorDrawn and not actorErr then
            local okD,why=drawImporter(importerActor,cam,arena,groundY)
            if okD then actorDrawn=true else actorErr=tostring(why) end
          end
          return oldEnd(...)
        end
        canvas=VS.render(view,320,180,160,90,nil)
        if actorErr then error("Importer actor in-scene draw failed: "..actorErr,0) end
        if not actorDrawn then error("Importer actor was not reached by Dramatic VoxelScene.endScene",0) end
        if not canvas then error("Dramatic public VoxelScene.render returned nil",0) end
      end
    end)

    V3.endScene=oldEnd
    V3.camera=oldCamera
    V3.tint=oldTint
    V3.fog=oldFog
    V3.glassMask,V3.glassNight=oldGlassMask,oldGlassNight
    V3.glassPhase,V3.glassGlint=oldGlassPhase,oldGlassGlint
    V3.SHADOW_ALPHA=oldShadowAlpha
    VState.ready=oldReady
    pcall(function()
      if #prevCanvas>0 then g.setCanvas(unpack_(prevCanvas)) else g.setCanvas() end
      if type(g.setShader)=="function" then g.setShader(prevShader) end
      if type(g.setDepthMode)=="function" then
        if dm then g.setDepthMode(dm,dw) else g.setDepthMode() end
      end
      if cull and type(g.setMeshCullMode)=="function" then g.setMeshCullMode(cull) end
      if type(g.setBlendMode)=="function" then
        if ba~=nil then g.setBlendMode(br,ba) else g.setBlendMode(br) end
      end
      g.setColor(cr,cg,cb,ca)
    end)
    if okRender and canvas and actorDrawn then return canvas end
    return nil,"Dramatic Importer private render error: "..tostring(errRender)
  end

  P.dramaticEligible=function()
    if not lifecycleEligible() then return false end
    local okE,v=pcall(OB.enabled); if not (okE and v) then return false end
    local okS,arena=pcall(OB.stage)
    return okS and type(arena)=="table" and type(arena.player)=="table" and type(arena.enemy)=="table"
  end

  P.renderDramaticFrame=function()
    if not P.dramaticEligible() then P.shot=nil; return end
    local battle=state.battle
    local okStage,arena,groundY=pcall(OB.stage)
    if not (okStage and type(arena)=="table") then P.shot=nil; P.failure="Dramatic stage unavailable"; return end
    groundY=tonumber(groundY) or 0

    local importerActor=resolveImporterActor(battle)
    if P.dramaticImporterRequested and not importerActor then
      P.shot=nil; P.failure="Dramatic + Importer 3D actor unavailable: "..tostring(P.dramaticImporterFailure or "unknown"); return
    end
    local nativeActor,nativeRequested=nil,false
    if not importerActor then nativeActor,nativeRequested=resolveNativeActor(battle,arena,groundY) end
    if nativeRequested and not nativeActor then
      P.shot=nil; P.failure="Dramatic native Stadium actor unavailable: "..tostring(P.dramaticNativeFailure or "unknown"); return
    end
    local actorMode=importerActor and "stadium2_importer" or (nativeActor and "dramatic_stadium" or "dramatic_2d")

    local tex,src=nil,nil
    if not importerActor and not nativeActor then
      local okTex,a,b=pcall(OB.__bcSecondaryViewPlayerTexture)
      if okTex then tex,src=a,b end
      if not (tex and tex.canvas) then P.shot=nil; P.failure="Dramatic fixed FRONT unavailable: "..tostring(src or a); return end
    else src=importerActor and "stadium2_importer_actor" or "dramatic_native_stadium" end

    local oldImp=P._goldImporterBounds; local oldDram=P._dramaticStadiumBounds
    if importerActor then P._goldImporterBounds=importerBounds(importerActor) end
    if nativeActor then P._dramaticStadiumBounds=nativeBounds(nativeActor) end
    local cam,pitch=P.cameraFor(backend,arena,groundY,actorMode)
    P._goldImporterBounds=oldImp; P._dramaticStadiumBounds=oldDram
    if not cam then P.shot=nil; P.failure="Dramatic Secondary View camera unavailable"; return end

    if importerActor then
      local canvas,why=renderDramaticImporterPrivate(importerActor,cam,arena,groundY)
      if canvas then
        P.shot={canvas=canvas}; P.frames=(P.frames or 0)+1; P.failure=nil
        P.actorMode=actorMode; P.dramaticLastSource=src
        if P.dramaticLastLoggedMode~=actorMode then
          P.dramaticLastLoggedMode=actorMode
          mod.log:warn("[SECONDARY VIEW] Dramatic actor path: Stadium2 Importer genuine 3D")
        end
      else
        P.shot=nil; P.failure=tostring(why or "Dramatic Importer private render unavailable")
      end
      return
    end

    local oldLetterbox=BS.letterbox; local oldRig=backend.BattleCam.rig
    local oldBegin=V3.beginScene; local oldResolve=AA.resolve; local oldFullW=BB.FULL_W
    local oldStadiumDraw=Stadium.draw; local oldStadiumCast=Stadium.cast
    local oldCamera=V3.camera; local oldRendering=P.rendering; local oldBackend=P.backend
    local actorDrawn=false; local actorErr=nil; local sceneSlot="bc_secondary_view_dramatic"
    local function restore()
      BS.letterbox=oldLetterbox; backend.BattleCam.rig=oldRig; V3.beginScene=oldBegin; AA.resolve=oldResolve
      BB.FULL_W=oldFullW; Stadium.draw=oldStadiumDraw; Stadium.cast=oldStadiumCast
      V3.camera=oldCamera; P.rendering=oldRendering; P.backend=oldBackend
    end
    local okRender,shot=pcall(function()
      BS.letterbox=function() return 80,18,1,320,180 end
      backend.BattleCam.rig=function(_arena,_groundY,_canonical)
        return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},focus={cam.focus[1],cam.focus[2],cam.focus[3]},
          up={0,1,0},fov=cam.fov,curve=cam.curve or 0},pitch or bcPitchForCamera(cam)
      end
      V3.beginScene=function(w,h,cx,cy,vw,vh,sky,slot,...)
        if slot=="battle" then slot=sceneSlot end
        return oldBegin(w,h,cx,cy,vw,vh,sky,slot,...)
      end
      AA.resolve=function(canvas,w,h,slot,...)
        if slot=="battle" then slot=sceneSlot end
        return oldResolve(canvas,w,h,slot,...)
      end
      BB.FULL_W=(actorMode=="dramatic_2d") and oldFullW*0.58 or oldFullW
      Stadium.cast=function(shadowMap)
        if nativeActor and nativeActor.rig and nativeActor.model_matrix and type(nativeActor.rig.caster)=="function" then
          pcall(nativeActor.rig.caster,nativeActor.rig,shadowMap,nativeActor.model_matrix)
        end
      end
      Stadium.draw=function(pull)
        if nativeActor and nativeActor.rig and nativeActor.model_matrix then
          local okD,why=pcall(nativeActor.rig.draw,nativeActor.rig,nativeActor.model_matrix,pull or BB.PULL)
          if okD then actorDrawn=true else actorErr=tostring(why) end
        elseif importerActor then
          local okD,why=drawImporter(importerActor,cam,arena,groundY)
          if okD then actorDrawn=true else actorErr=tostring(why) end
        end
      end
      P.rendering=true; P.backend=backend
      local token=(P.dramaticToken or 0)+1; P.dramaticToken=token
      local textures=(actorMode=="dramatic_2d") and {player=tex,flash=false} or {flash=false}
      return BS.render(require("src.core.Game").overworld,arena,textures,token)
    end)
    restore()
    if actorErr then P.shot=nil; P.failure="Dramatic actor draw failed: "..actorErr; return end
    local needActor=(actorMode~="dramatic_2d")
    if okRender and type(shot)=="table" and shot.canvas and (not needActor or actorDrawn) then
      P.shot={canvas=shot.canvas}; P.frames=(P.frames or 0)+1; P.failure=nil; P.actorMode=actorMode; P.dramaticLastSource=src
      if P.dramaticLastLoggedMode~=actorMode then
        P.dramaticLastLoggedMode=actorMode
        mod.log:warn("[SECONDARY VIEW] Dramatic actor path: %s",actorMode)
      end
    else
      P.shot=nil; P.failure=okRender and ("Dramatic render returned "..tostring(shot).." actor="..tostring(actorDrawn)) or ("Dramatic render error: "..tostring(shot))
    end
  end

  mod.log:warn("[SECONDARY VIEW] Dramatic Shape flat/Crystal + Stadium2 Importer adapter armed")
end)()


-- Voxel Ascendant Sprite Facing / Dual Actor Presentation ----------------
-- Voxel Ascendant adapter uses the same staged 2D-card capability seam. The host still
-- owns arena rendering, texture capture, shadows, lighting, move FX and camera
-- projection.  BC contributes only the same final-camera actor orientation
-- semantic already proven on Dramaless/Battle Art.  Model-based rungs are a hard yield when the host exposes them: real 3D models are never converted into sprite cards here.
;(function()
  local handle=mod.find("VOXEL_ASCENDANT")
  local exports=handle and handle.exports or nil
  local V=exports and exports.lib or nil
  if not (V and type(V.require)=="function") then return end

  local okOB,OverworldBattle=pcall(V.require,"OverworldBattle")
  if not okOB or type(OverworldBattle)~="table"
      or type(OverworldBattle.sideTexture)~="function"
      or type(OverworldBattle.backPinned)~="function" then return end
  if OverworldBattle.__bcSpriteFacingVoxelAscendantInstalled then return end

  local setting=OverworldBattle.backSetting
  local savedBackPinned=OverworldBattle.backPinned
  if type(setting)~="table" or type(setting.get)~="function" then return end
  local savedSettingGet=setting.get
  local unpack_=table.unpack or unpack

  local BattleState,Sprites,Assets,PaletteFX=nil,nil,nil,nil
  do
    local okBS,bs=pcall(require,"src.battle.BattleState")
    if okBS and type(bs)=="table" then BattleState=bs end
    local okSp,sp=pcall(require,"src.pokemon.Sprites")
    if okSp and type(sp)=="table" then Sprites=sp end
    local okAs,a=pcall(require,"src.render.Assets")
    if okAs and type(a)=="table" then Assets=a end
    local okPa,pal=pcall(require,"src.render.PaletteFX")
    if okPa and type(pal)=="table" then PaletteFX=pal end
  end
  if not (BattleState and Sprites and Assets) then return end

  local crystal=nil
  do
    local h=mod.find("crystal_animated_sprites_with_shiny_visuals")
    local ex=h and h.exports or nil
    if ex and type(ex.applyOption)=="function"
        and type(ex.frontPrefEnabled)=="function" then
      crystal={exports=ex}
    end
  end

  local actor={
    player={side="back",turn="right",screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
    enemy ={side="front",turn="left", screenDelta=nil,scale=1,liveFront=nil,liveBack=nil},
  }
  local battleRef=nil
  local imageCache={}
  local flipped={}
  
  local function mode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v~="turn" and v~="dynamic" then return "host" end
    return v
  end

  local function isStadium()
    if type(OverworldBattle.stadium)~="function" then return false end
    local ok,v=pcall(OverworldBattle.stadium)
    return ok and v and true or false
  end

  local function active()
    if not enabled() or selectedPreset()=="external" or mode()=="host" then return false end
    if type(OverworldBattle.enabled)=="function" then
      local ok,v=pcall(OverworldBattle.enabled)
      if not ok or not v then return false end
    end
    if isStadium() then return false end
    return true
  end

  local function dynamic() return active() and mode()=="dynamic" end

  local function hostBackEnabled()
    local ok,v=pcall(savedSettingGet,setting)
    return ok and v and true or false
  end

  local function crystalPref()
    if not crystal then return nil end
    local ok,v=pcall(crystal.exports.frontPrefEnabled)
    return ok and (v and true or false) or nil
  end

  local function setCrystal(v)
    if not crystal then return false end
    return pcall(crystal.exports.applyOption,"crystalFront",v and true or false)
  end

  local function resetBattle(battle)
    if battle==battleRef then return end
    battleRef=battle
    imageCache={}
    actor.player.side,actor.player.turn="back","right"
    actor.enemy.side,actor.enemy.turn="front","left"
    for _,a in pairs(actor) do
      a.screenDelta=nil; a.scale=1; a.liveFront=nil; a.liveBack=nil
    end
  end

  local function updateOne(name,cell,other,cam)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
    local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
    local fl=math.sqrt(fx*fx+fz*fz)
    local vl=math.sqrt(vx*vx+vz*vz)
    if fl>=0.001 and vl>=0.001 then
      local dot=(fx*vx+fz*vz)/(fl*vl)
      if a.side=="back" and dot>0.22 then a.side="front"
      elseif a.side=="front" and dot<(-0.22) then a.side="back" end
    end

    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(pt)
          local dx=(tonumber(pt[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(pt[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
        end
        local aa,oo=screenX(cell),screenX(other)
        screenDelta=(aa and oo) and (oo-aa) or (fx*rx+fz*rz)
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation()
    if not active() then return end
    local okA,arena=pcall(OverworldBattle.arena)
    if not okA or type(arena)~="table" then return end
    local p,e=arena.player,arena.enemy
    local cam=state.spriteFacingCamera
    if not (p and e and cam) then return end
    if dynamic() then
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
    else
      local ps,es=actor.player.side,actor.enemy.side
      updateOne("player",p,e,cam); updateOne("enemy",e,p,cam)
      actor.player.side,actor.enemy.side=ps,es
    end
  end

  local function hostPlayerSide()
    if not hostBackEnabled() then return "front" end
    if crystal and crystalPref()==true then return "front" end
    return "back"
  end

  local function presentationSide(name)
    if mode()=="dynamic" then return actor[name].side end
    if name=="enemy" then return "front" end
    return hostPlayerSide()
  end

  -- While BC is actively consuming sprite orientation, the player's card must
  -- remain in Voxel Ascendant's world-card pass.  The saved BACK SPRITES preference is
  -- still read above for TURN ONLY; only the host's pinning side effect yields.
  OverworldBattle.backPinned=function(...)
    if active() then return false end
    return savedBackPinned(...)
  end

  local nativeResolveScale=BattleState.resolveBattleScale

  local function temporarilyCrystalOff(fn)
    if not crystal then return fn() end
    local prior=crystalPref()
    if prior~=false then setCrystal(false) end
    local r={pcall(fn)}
    if prior~=nil then setCrystal(prior) end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  local function staticRep(name,side,battle)
    local battler=battle and battle[name] or nil
    local mon=battler and battler.mon or nil
    local species=mon and mon.species or nil
    if not species then return nil,1 end

    local function resolvePath()
      -- Voxel Ascendant 2.0.1 intentionally routes the engine's normal
      -- player BACK request to FRONT whenever a staged MAP battle wants both
      -- battlers facing the main camera. BC Dynamic needs an explicit BACK
      -- representation for its own camera-relative actor grammar, so suspend
      -- only that provider FRONT-routing predicate around this one explicit
      -- BACK lookup. The host's saved PKMN BACK option and staged main battle
      -- remain untouched.
      local savedWantsFront=nil
      if side=="back" and type(OverworldBattle.wantsFront)=="function" then
        savedWantsFront=OverworldBattle.wantsFront
        OverworldBattle.wantsFront=function() return false end
      end
      local ok,path,tc=pcall(Sprites.path,battle.data,species,side,{mon=mon,kind="battle"})
      if savedWantsFront then OverworldBattle.wantsFront=savedWantsFront end
      if not ok or type(path)~="string" or path=="" then return nil,nil end
      return path,tc
    end
    local path,tc
    if crystal and side=="back" then path,tc=temporarilyCrystalOff(resolvePath)
    else path,tc=resolvePath() end
    if not path then return nil,1 end

    local scale=1
    local okS,v=pcall(nativeResolveScale,battle.data,side,path,species)
    if okS and tonumber(v) and tonumber(v)>0 then scale=tonumber(v) end

    local palName="truecolor"
    if not tc and PaletteFX and type(PaletteFX.monPalName)=="function" then
      local okN,n=pcall(PaletteFX.monPalName,battle.data,species,false)
      if okN and n then palName=tostring(n) end
    end
    local key=table.concat({tostring(path),palName,name,side},"#")
    if imageCache[key] then return imageCache[key],scale end

    local img=nil
    if tc or not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
      local okI,vv=pcall(Assets.image,path); if okI then img=vv end
    else
      local okD,id=pcall(Assets.imageData,path)
      if okD and id then
        local pal=PaletteFX and type(PaletteFX.monPal)=="function"
          and PaletteFX.monPal(battle.data,species,false) or nil
        if pal then
          local c=pal
          pcall(id.mapPixel,id,function(_,_,r,g,b,a)
            if a==0 then return r,g,b,a end
            local col=r>0.83 and c[1] or r>0.5 and c[2] or r>0.17 and c[3] or c[4]
            return col[1]/255,col[2]/255,col[3]/255,a
          end)
        end
        local okI,vv=pcall(love.graphics.newImage,id); if okI then img=vv end
      end
    end
    if img and type(img.setFilter)=="function" then pcall(img.setFilter,img,"nearest","nearest") end
    imageCache[key]=img
    return img,scale
  end

  local function captureLives(battle,frontAuthoritative)
    if not (crystal and battle) then return end
    local p,e=battle.player,battle.enemy
    -- Rebase43: only the exact update during which BC has deliberately enabled
    -- Crystal FRONT is allowed to advance/replace the player PiP FRONT cache.
    -- The user's saved FRONT preference is not sufficient evidence here: BC
    -- Dynamic may have temporarily presented BACK in the staged card while the
    -- preference itself remains ON. Never infer semantics from the field image.
    if frontAuthoritative==true and p and p.__crystalAnimation and p.sprite then
      actor.player.liveFront=p.sprite
    end
    -- Enemy Crystal art is always a genuine FRONT stream in Crystal itself.
    if e and e.__crystalAnimation and e.sprite then actor.enemy.liveFront=e.sprite end
  end

  -- Rebase40: Ascendant MAP-mode Secondary View actor feed belongs to the
  -- Ascendant adapter itself. Rebase39 accidentally registered this helper in
  -- the Dramatic Shape adapter, leaving Ascendant with a live world but no
  -- fixed-FRONT producer unless Dramatic happened to be installed too.
  -- Keep the already-proven representation contract: Crystal live FRONT wins;
  -- otherwise resolve the genuine provider/ROM FRONT without touching the
  -- host's saved back-sprite option or the main camera's Dynamic side.
  state.secondaryViewProbe.voxelAscendantFixedFront=function(battle)
    if not battle then return nil,"battle unavailable" end
    resetBattle(battle)
    -- Never sample battle.player.sprite here: under DYNAMIC that field is the
    -- currently PRESENTED side, not a semantic FRONT. liveFront is captured
    -- only from Crystal's genuine FRONT-animation update window above.
    if crystal and actor.player.liveFront then
      return actor.player.liveFront,"crystal_live_front",1
    end
    local img,scale=staticRep("player","front",battle)
    if img then return img,"provider_front",scale end
    return nil,"front unavailable",1
  end

  -- Rebase43: keep the battler's underlying engine/Crystal sprite independent
  -- from the staged world-card representation. Voxel Ascendant's sideTexture
  -- is already the correct one-frame capture seam; FRONT/BACK substitution is
  -- therefore temporary for that capture instead of being written persistently
  -- into battle.player.sprite after every update. This mirrors the successful
  -- Battle Art actor-ownership pattern and gives Secondary View a stable FRONT.
  local function representationFor(name,battle)
    local repSide=presentationSide(name)
    if crystal and repSide=="front" and actor[name].liveFront then
      actor[name].scale=1
      return actor[name].liveFront,repSide,1
    end
    local img,scale=staticRep(name,repSide,battle)
    scale=(tonumber(scale) and tonumber(scale)>0) and tonumber(scale) or 1
    actor[name].scale=scale
    return img,repSide,scale
  end

  local function applyRep(name,battle)
    if not (active() and battle) then return end
    if name=="player" and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then return end
    if name=="enemy" and (battle.showEnemyTrainer or battle.enemySendingOut) then return end
    local battler=battle[name]
    if not battler then return end
    local side=presentationSide(name)
    local img,scale=nil,1
    if crystal and side=="front" then
      img=actor[name].liveFront
      if not img then img,scale=staticRep(name,side,battle) end
    else
      img,scale=staticRep(name,side,battle)
    end
    if img then battler.sprite=img end
    actor[name].scale=(tonumber(scale) and tonumber(scale)>0) and tonumber(scale) or 1
  end

  -- Keep Crystal's real player-front animation alive under DYNAMIC without
  -- changing the user's saved Crystal option.  This is the same lifecycle
  -- ownership rule already proven on Dramaless.
  if crystal and type(BattleState.update)=="function"
      and not BattleState.__bcSpriteFacingVoxelAscendantInstalled then
    local innerUpdate=BattleState.update
    BattleState.update=function(self,dt,...)
      resetBattle(self)
      local prior=crystalPref()
      local priorVoxel=self.__crystalVoxel
      local facingActive=active()
      -- Crystal 2.0.2 predates Voxel Ascendant.  Whenever BC is consuming
      -- Ascendant's world-card presentation (TURN ONLY or DYNAMIC), mark only
      -- this live update as voxel-presented so Crystal does not apply its
      -- vanilla battle-slot mirror underneath BC.  TURN ONLY deliberately
      -- leaves Crystal's chosen FRONT/BACK representation untouched; DYNAMIC
      -- additionally enables the live front lifecycle as before.
      if facingActive then self.__crystalVoxel=true end
      if dynamic() then
        if actor.player.liveFront and self.player and not self.showPlayerBack then
          self.player.sprite=actor.player.liveFront
        end
        if actor.enemy.liveFront and self.enemy and not self.showEnemyTrainer then
          self.enemy.sprite=actor.enemy.liveFront
        end
        setCrystal(true)
      end
      local r={pcall(innerUpdate,self,dt,...)}
      -- We set Crystal FRONT immediately above only for DYNAMIC. Capture the
      -- player stream while that exact update is still authoritative, then
      -- restore the provider's broad voxel marker/persistent preference.
      captureLives(self,dynamic())
      if facingActive then self.__crystalVoxel=priorVoxel end
      if dynamic() and prior~=nil then setCrystal(prior) end
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      -- Do NOT install the camera-selected representation persistently here.
      -- The underlying player sprite stays as Crystal's genuine FRONT stream
      -- (or the engine/provider canonical sprite); sideTexture borrows the
      -- requested FRONT/BACK only for the staged card draw below.
      return unpack_(r)
    end
    BattleState.__bcSpriteFacingVoxelAscendantInstalled=true
  end

  local function needsHostRelativeFlip(name,repSide)
    -- Voxel Ascendant's BattleScene always mirrors the ordinary PLAYER card
    -- and leaves the ENEMY card unmirrored. Raw Gen1/Crystal FRONT art is
    -- authored facing left; raw BACK art is authored facing right. Derive the
    -- finished host polarity from those two facts, then pre-flip only when the
    -- final BC screen-space turn asks for the opposite direction. No provider-
    -- or species-specific exception is required.
    local hostRight
    if name=="player" then
      hostRight=(repSide=="front") -- host mirror: FRONT->right, vanilla BACK->left
    else
      hostRight=(repSide=="back")  -- no host mirror: FRONT->left, vanilla BACK->right
    end
    -- Rebase46: Rebase45 keyed this correction merely on the Crystal MOD being
    -- installed, contaminating vanilla/ROM cards whenever Crystal was loaded in
    -- the mod set. Apply the polarity translation only to a battler that is
    -- actually owned by Crystal's animation lifecycle. Runtime Rebase45 shows
    -- the same provider polarity applies to BOTH Crystal battlers; this also
    -- corrects the remaining enemy FRONT inversion without changing vanilla.
    local battler=battleRef and battleRef[name] or nil
    local crystalOwned=crystal and battler and battler.__crystalAnimation~=nil
    if crystalOwned then hostRight=not hostRight end
    local desiredRight=(actor[name].turn=="right")
    return desiredRight~=hostRight
  end

  local function flipCanvas(src,key)
    if not (src and love and love.graphics and type(src.getDimensions)=="function") then return nil end
    local w,h=src:getDimensions()
    if not (w and h and w>0 and h>0) then return nil end
    local rec=flipped[key]
    if not rec or rec.w~=w or rec.h~=h then
      local ok,c=pcall(love.graphics.newCanvas,w,h,{dpiscale=1})
      if not ok or not c then return nil end
      if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
      rec={canvas=c,w=w,h=h}; flipped[key]=rec
    end
    local g=love.graphics
    local prev=g.getCanvas()
    local bm,ba=g.getBlendMode()
    local cr,cg,cb,ca=g.getColor()
    local ok=pcall(function()
      g.setCanvas(rec.canvas); g.clear(0,0,0,0); g.setBlendMode("alpha")
      g.setColor(1,1,1,1); g.draw(src,w,0,0,-1,1)
    end)
    if prev then g.setCanvas(prev) else g.setCanvas() end
    g.setBlendMode(bm or "alpha",ba); g.setColor(cr,cg,cb,ca)
    if not ok then return nil end
    return rec.canvas,w
  end

  local scaledRepresentation=setmetatable({}, {__mode="k"})
  local function scaledRepImage(src,factor)
    if not (src and love and love.graphics and type(src.getDimensions)=="function") then return src end
    factor=tonumber(factor) or 1
    if factor<=1.001 or factor>=8 then return src end
    local byFactor=scaledRepresentation[src]
    if not byFactor then byFactor={}; scaledRepresentation[src]=byFactor end
    local key=tostring(factor)
    if byFactor[key] then return byFactor[key] end
    local w,h=src:getDimensions()
    if not (w and h and w>0 and h>0) then return src end
    local ow,oh=math.max(1,math.floor(w*factor+0.5)),math.max(1,math.floor(h*factor+0.5))
    local ok,c=pcall(love.graphics.newCanvas,ow,oh,{dpiscale=1})
    if not ok or not c then return src end
    if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
    local g=love.graphics
    local prev=g.getCanvas(); local bm,ba=g.getBlendMode(); local cr,cg,cb,ca=g.getColor()
    local drawn=pcall(function()
      g.setCanvas(c); g.clear(0,0,0,0); g.setBlendMode("alpha")
      g.setColor(1,1,1,1); g.draw(src,0,0,0,factor,factor)
    end)
    if prev then g.setCanvas(prev) else g.setCanvas() end
    g.setBlendMode(bm or "alpha",ba); g.setColor(cr,cg,cb,ca)
    if not drawn then return src end
    byFactor[key]=c
    return c
  end

  local originalSideTexture=OverworldBattle.sideTexture
  OverworldBattle.sideTexture=function(battle,side)
    if not active() then return originalSideTexture(battle,side) end
    resetBattle(battle)
    updateOrientation()

    local battler=battle and battle[side] or nil
    local repSide=presentationSide(side)
    local displayScale=1
    local swapped=false
    local priorSprite=nil
    local canBorrow=(side=="player" or side=="enemy") and battler~=nil
    if side=="player" and battle
        and (battle.safari or battle.demo or battle.showPlayerBack or battle.sendingOut) then
      canBorrow=false
    elseif side=="enemy" and battle
        and (battle.showEnemyTrainer or battle.enemySendingOut) then
      canBorrow=false
    end

    if canBorrow then
      local img
      img,repSide,displayScale=representationFor(side,battle)
      if img then
        -- Ascendant intentionally captures all cards at 1x. For the genuine
        -- half-resolution Gen1 BACK, recreate the engine/provider-authored
        -- integer display scale on the IMAGE before capture. This is local to
        -- the Pokemon representation: trainer/send-out/UI scaling cannot leak,
        -- and the provider's own fixed card anchor/faint motion stays intact.
        if repSide=="back" and not crystal and tonumber(displayScale)
            and tonumber(displayScale)>1.001 then
          img=scaledRepImage(img,tonumber(displayScale))
        end
        priorSprite=battler.sprite
        battler.sprite=img
        swapped=true
      end
    end

    local r={pcall(originalSideTexture,battle,side)}
    if swapped then battler.sprite=priorSprite end
    if not r[1] then error(r[2],0) end
    local tex=r[2]
    if not (tex and not tex.trainer and tex.canvas) then return tex end

    if needsHostRelativeFlip(side,repSide) then
      local c,w=flipCanvas(tex.canvas,side.."_"..tostring(repSide))
      if c then
        tex.canvas=c
        if tonumber(tex.ax) then tex.ax=w-tonumber(tex.ax) end
      end
    end
    return tex
  end

  local originalFinish=OverworldBattle.finish
  if type(originalFinish)=="function" then
    OverworldBattle.finish=function(...)
      battleRef=nil; imageCache={}
      return originalFinish(...)
    end
  end
  local originalInvalidate=OverworldBattle.invalidate
  if type(originalInvalidate)=="function" then
    OverworldBattle.invalidate=function(...)
      flipped={}
      return originalInvalidate(...)
    end
  end

  OverworldBattle.__bcSpriteFacingVoxelAscendantInstalled=true
  mod.log:info("Voxel Ascendant sprite-facing adapter active: temporary card representations + fixed Crystal FRONT + pre-capture vanilla BACK image scale")
end)()



-- Battle Art Sprite Facing / Dual Actor Presentation ------------------------
-- Battle Art 1.9.6 already owns the useful things BC must NOT duplicate:
-- selected front/back collections, static/animated decoding, per-frame sprite
-- lifecycle, world metrics and staged placement. BC contributes only the final
-- camera-relative semantics. HOST DEFAULT is a literal delegation path.
;(function()
  local handle=mod.find("BATTLE_ART_VOXEL_FORK")
  local ex=handle and handle.exports or nil
  local V=ex and ex.lib or nil
  if not (V and type(V.require)=="function") then return end

  local okBA,BattleArt=pcall(V.require,"BattleArt")
  local okAA,AnimatedBattleArt=pcall(V.require,"AnimatedBattleArt")
  local okOW,OverworldBattle=pcall(V.require,"OverworldBattle")
  local okSM,StadiumModels=pcall(V.require,"StadiumModels")
  if not okSM then StadiumModels=nil end
  if not (okBA and okAA and okOW and type(BattleArt)=="table"
      and type(AnimatedBattleArt)=="table" and type(OverworldBattle)=="table") then return end
  if BattleArt.__bcSpriteFacingBattleArtInstalled then return end

  local viewSetting=BattleArt.viewSetting
  local placementSetting=BattleArt.backPlacementSetting
  if not (type(viewSetting)=="table" and type(viewSetting.get)=="function"
      and type(placementSetting)=="table" and type(placementSetting.get)=="function") then return end

  local savedViewGet=viewSetting.get
  local savedPlacementGet=placementSetting.get
  local unpack_=table.unpack or unpack
  local forcedSide=nil
  local battleRef=nil
  local proxy={ player={}, enemy={} }
  local actor={
    player={side="back",turn="right",screenDelta=nil},
    enemy ={side="front",turn="left", screenDelta=nil},
  }
  local mirroredCanvas={}
  local imageCache={}

  -- Battle Art can stage provider/ROM pictures without owning their species
  -- images. Dynamic still needs an explicit way to ask that provider chain for
  -- the opposite FRONT/BACK representation; viewSetting alone cannot do that
  -- after the battler has already been constructed. Keep this bridge scoped to
  -- Battle Art's ROM/MODDED picture path so its own static/animated collections
  -- remain entirely provider-owned.
  local BattleState,Sprites,Assets,PaletteFX=nil,nil,nil,nil
  do
    local okBS,bs=pcall(require,"src.battle.BattleState")
    if okBS and type(bs)=="table" then BattleState=bs end
    local okSp,sp=pcall(require,"src.pokemon.Sprites")
    if okSp and type(sp)=="table" then Sprites=sp end
    local okAs,a=pcall(require,"src.render.Assets")
    if okAs and type(a)=="table" then Assets=a end
    local okPa,pal=pcall(require,"src.render.PaletteFX")
    if okPa and type(pal)=="table" then PaletteFX=pal end
  end

  local crystal=nil
  do
    local h=mod.find("crystal_animated_sprites_with_shiny_visuals")
    local cex=h and h.exports or nil
    if cex and type(cex.applyOption)=="function"
        and type(cex.frontPrefEnabled)=="function" then
      crystal={exports=cex}
    end
  end

  local function mode()
    local v=mod.options:get("spriteFacing") or "dynamic"
    if v~="turn" and v~="dynamic" then return "host" end
    return v
  end

  local function active()
    if not (enabled() and selectedPreset()~="external" and mode()~="host") then return false end
    -- Stadium-model presentation is already genuine 3D orientation. Sprite
    -- Facing is a 2D-card consumer only and must not take ownership underneath.
    if StadiumModels and type(StadiumModels.active)=="function" then
      local ok,on=pcall(StadiumModels.active)
      if ok and on then return false end
    end
    return true
  end

  local function externalRepresentationPath()
    local art=BattleArt.setting and type(BattleArt.setting.get)=="function"
              and BattleArt.setting:get() or nil
    local owns=true
    if type(BattleArt.ownsSpeciesArt)=="function" then
      local ok,v=pcall(BattleArt.ownsSpeciesArt)
      if ok then owns=v and true or false end
    end
    return art=="rom" or not owns
  end

  local function fullSideCapable()
    if not externalRepresentationPath() then
      -- Battle Art's own STATIC/ANIMATED collections already expose both sides
      -- through its native viewSetting seam; retain that proven path unchanged.
      return true
    end
    -- ROM/MODDED still has both semantic sides in the engine/provider chain,
    -- but Battle Art only captures whichever image is currently attached to the
    -- battler. This adapter resolves the requested side just for that capture.
    return Sprites and type(Sprites.path)=="function" and Assets and true or false
  end

  local function hostPlayerSide()
    local ok,v=pcall(savedViewGet,viewSetting)
    return ok and v=="front" and "front" or "back"
  end

  local function crystalPref()
    if not crystal then return nil end
    local ok,v=pcall(crystal.exports.frontPrefEnabled)
    return ok and (v and true or false) or nil
  end

  local function setCrystal(v)
    if not crystal then return false end
    return pcall(crystal.exports.applyOption,"crystalFront",v and true or false)
  end

  local function resetBattle(battle)
    if battle==battleRef then return end
    battleRef=battle
    actor.player.side=hostPlayerSide()
    actor.enemy.side="front"
    actor.player.turn,actor.enemy.turn="right","left"
    actor.player.screenDelta,actor.enemy.screenDelta=nil,nil
    proxy.player,proxy.enemy={},{}
    actor.player.liveFront=nil
    actor.enemy.liveFront=nil
  end

  local function updateActorOrientation(name,cell,other,cam,allowSide)
    local a=actor[name]
    local eye=cam and cam.eye or nil
    local focus=cam and cam.focus or nil
    if not (type(cell)=="table" and type(other)=="table" and type(eye)=="table") then return end

    if allowSide then
      local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
      local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
      local vx=(tonumber(eye[1]) or 0)-(tonumber(cell[1]) or 0)
      local vz=(tonumber(eye[3]) or 0)-(tonumber(cell[2]) or 0)
      local fl=math.sqrt(fx*fx+fz*fz)
      local vl=math.sqrt(vx*vx+vz*vz)
      if fl>=0.001 and vl>=0.001 then
        local dot=(fx*vx+fz*vz)/(fl*vl)
        if a.side=="back" and dot>0.22 then a.side="front"
        elseif a.side=="front" and dot<(-0.22) then a.side="back" end
      end
    end

    local fx=(tonumber(other[1]) or 0)-(tonumber(cell[1]) or 0)
    local fz=(tonumber(other[2]) or 0)-(tonumber(cell[2]) or 0)
    local screenDelta=nil
    if type(focus)=="table" then
      local cfx=(tonumber(focus[1]) or 0)-(tonumber(eye[1]) or 0)
      local cfz=(tonumber(focus[3]) or 0)-(tonumber(eye[3]) or 0)
      local cfl=math.sqrt(cfx*cfx+cfz*cfz)
      if cfl>=0.001 then
        cfx,cfz=cfx/cfl,cfz/cfl
        local rx,rz=cfz,-cfx
        local function screenX(p)
          local dx=(tonumber(p[1]) or 0)-(tonumber(eye[1]) or 0)
          local dz=(tonumber(p[2]) or 0)-(tonumber(eye[3]) or 0)
          local dep=dx*cfx+dz*cfz
          local lat=dx*rx+dz*rz
          if dep>0.05 then return lat/dep end
          return nil
        end
        local as=screenX(cell)
        local os=screenX(other)
        if as and os then screenDelta=os-as else screenDelta=fx*rx+fz*rz end
      end
    end
    if screenDelta~=nil then
      a.screenDelta=screenDelta
      local dead=0.035
      if a.turn=="right" and screenDelta<(-dead) then a.turn="left"
      elseif a.turn=="left" and screenDelta>dead then a.turn="right" end
    end
  end

  local function updateOrientation(battle)
    resetBattle(battle)
    if not active() then return end
    local arena=type(OverworldBattle.arena)=="function" and OverworldBattle.arena() or nil
    local p=arena and arena.player or nil
    local e=arena and arena.enemy or nil
    local cam=state.spriteFacingCamera
    if not (p and e and cam) then return end
    local allowSide=mode()=="dynamic" and fullSideCapable()
    if not allowSide then
      actor.player.side=hostPlayerSide()
      actor.enemy.side="front"
    end
    updateActorOrientation("player",p,e,cam,allowSide)
    updateActorOrientation("enemy",e,p,cam,allowSide)
  end

  local function presentationSide(name)
    if mode()=="dynamic" and fullSideCapable() then return actor[name].side end
    if name=="player" then return hostPlayerSide() end
    return "front"
  end

  -- The player's selected side is already a first-class Battle Art setting.
  -- While DYNAMIC is active, answer that existing query with BC's semantic;
  -- TURN ONLY and HOST DEFAULT preserve the user's own setting. A forced side
  -- is used only while asking Battle Art to update/capture the enemy as though
  -- it were the player, which lets Battle Art's own back animator remain owner.
  viewSetting.get=function(self)
    if active() then
      if forcedSide then return forcedSide end
      -- Before a staged battle exists, preserve Battle Art's saved PLAYER
      -- choice so its pokemon.sprite construction hook is not pre-empted.
      if battleRef and mode()=="dynamic" and fullSideCapable() then return actor.player.side end
    end
    return savedViewGet(self)
  end

  -- TURN ONLY/DYNAMIC need the selected player representation in the world so
  -- BC's moving camera remains coherent. HOST DEFAULT returns the exact saved
  -- placement choice and therefore retains OG UI/AUTO pinning when requested.
  placementSetting.get=function(self)
    if active() then
      -- PLAYER SPRITE FACING applies to Pokemon, not the trainer intro. Keep
      -- Battle Art's own trainer-back placement exactly as configured.
      local b=type(OverworldBattle.battle)=="function" and OverworldBattle.battle() or nil
      if b and b.showPlayerBack and b.playerBackPic then return savedPlacementGet(self) end
      return "world"
    end
    return savedPlacementGet(self)
  end

  local function proxyFor(name,battle)
    local p=proxy[name]
    p.player=battle and battle[name] or nil
    p.enemy=nil
    p.showPlayerBack=false
    p.showEnemyTrainer=false
    p.playerBackPic=nil
    p.trainerPic=nil
    p.demo=false
    p.safari=false
    p.data=battle and battle.data or nil
    p.phase=battle and battle.phase or nil
    return p
  end

  local function withForcedSide(side,fn)
    local prior=forcedSide
    forcedSide=side
    local r={pcall(fn)}
    forcedSide=prior
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  local function temporarilyCrystalOff(fn)
    if not crystal then return fn() end
    local prior=crystalPref()
    if prior~=false then setCrystal(false) end
    local r={pcall(fn)}
    if prior~=nil then setCrystal(prior) end
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  -- Resolve one ordinary engine/provider representation without asking Battle
  -- Art to own it. `forcedSide` prevents Battle Art's own pokemon.sprite hook
  -- from rewriting a requested BACK into FRONT; Crystal is additionally forced
  -- to genuine BACK only for that lookup. The resulting image is used only by
  -- the staged card capture and never becomes Battle Art-owned art.
  local function staticRepresentation(name,side,battle)
    local battler=battle and battle[name] or nil
    local mon=battler and battler.mon or nil
    local species=mon and mon.species or nil
    if not (battle and species and Sprites and type(Sprites.path)=="function" and Assets) then
      return nil
    end

    local function resolve()
      return withForcedSide(side,function()
        local ok,path,tc=pcall(Sprites.path,battle.data,species,side,{mon=mon,kind="battle"})
        if not ok or type(path)~="string" or path=="" then return nil,nil end
        return path,tc
      end)
    end

    local path,tc
    if crystal and side=="back" then path,tc=temporarilyCrystalOff(resolve)
    else path,tc=resolve() end
    if not path then return nil end

    local palName="truecolor"
    if not tc and PaletteFX and type(PaletteFX.monPalName)=="function" then
      local okN,n=pcall(PaletteFX.monPalName,battle.data,species,false)
      if okN and n then palName=tostring(n) end
    end
    local key=table.concat({tostring(path),palName,name,side},"#")

    -- The world-card capture itself always renders at 1x. Preserve the
    -- provider/engine's authored DISPLAY scale separately so a Gen1 ROM
    -- backsprite (the deliberate half-resolution 32px picture) still occupies
    -- its intended 2x presentation in the 3D world, while full-resolution
    -- Crystal/modded backs remain 1x. Ask the shared engine scale seam rather
    -- than guessing from species or hard-coding a provider asset size.
    local displayScale=1
    if side=="back" and BattleState and type(BattleState.resolveBattleScale)=="function" then
      local okS,v=pcall(BattleState.resolveBattleScale,battle.data,side,path,species)
      if okS and tonumber(v) and tonumber(v)>0 then displayScale=tonumber(v) end
    end
    if imageCache[key] then return imageCache[key],displayScale end

    local img=nil
    if tc or not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then
      local okI,v=pcall(Assets.image,path)
      if okI then img=v end
    else
      local okD,id=pcall(Assets.imageData,path)
      if okD and id then
        local pal=PaletteFX and type(PaletteFX.monPal)=="function"
          and PaletteFX.monPal(battle.data,species,false) or nil
        if pal then
          local c=pal
          pcall(id.mapPixel,id,function(_,_,r,g,b,a)
            if a==0 then return r,g,b,a end
            local col=r>0.83 and c[1] or r>0.5 and c[2] or r>0.17 and c[3] or c[4]
            return col[1]/255,col[2]/255,col[3]/255,a
          end)
        end
        local okI,v=pcall(love.graphics.newImage,id)
        if okI then img=v end
      end
    end
    if img and type(img.setFilter)=="function" then pcall(img.setFilter,img,"nearest","nearest") end
    imageCache[key]=img
    return img
  end

  local function captureCrystalLives(battle)
    if not (crystal and battle) then return end
    local p,e=battle.player,battle.enemy
    if p and p.__crystalAnimation and p.sprite then actor.player.liveFront=p.sprite end
    if e and e.__crystalAnimation and e.sprite then actor.enemy.liveFront=e.sprite end
  end

  -- Crystal's player FRONT animator is preference-gated. Under Battle Art's
  -- ROM/MODDED path, keep that provider-owned stream advancing beneath BC
  -- Dynamic exactly as on the validated Dramaless path, but never change the
  -- user's saved Crystal preference. The actual card capture remains temporary.
  if crystal and BattleState and type(BattleState.update)=="function"
      and not BattleState.__bcSpriteFacingBattleArtCrystalInstalled then
    local innerUpdate=BattleState.update
    BattleState.update=function(self,dt,...)
      resetBattle(self)
      local bridge=active() and mode()=="dynamic" and externalRepresentationPath()
      local prior=crystalPref()
      if bridge then
        if actor.player.liveFront and self.player and not self.showPlayerBack then
          self.player.sprite=actor.player.liveFront
        end
        if actor.enemy.liveFront and self.enemy and not self.showEnemyTrainer then
          self.enemy.sprite=actor.enemy.liveFront
        end
        setCrystal(true)
      end
      local r={pcall(innerUpdate,self,dt,...)}
      captureCrystalLives(self)
      if bridge and prior~=nil then setCrystal(prior) end
      if not r[1] then error(r[2],0) end
      table.remove(r,1)
      return unpack_(r)
    end
    BattleState.__bcSpriteFacingBattleArtCrystalInstalled=true
  end

  -- A player replacement can be constructed inside the transient Crystal FRONT
  -- update above. Repair only that new battler's canonical BACK immediately so
  -- the send-out phase never inherits FRONT art; subsequent staged captures are
  -- still temporary and use presentationSide().
  if crystal then
    mod.events:on("battle.battler_switched",function(ev)
      if not (active() and mode()=="dynamic" and externalRepresentationPath()) then return end
      local battle=ev and ev.battle or nil
      local side=ev and ev.side and ev.side.index or nil
      if side~=1 or not battle or battle~=battleRef then return end
      local battler=ev.battler or battle.player
      if not battler or battler~=battle.player then return end
      actor.player.liveFront=nil
      local back=staticRepresentation("player","back",battle)
      if back then battler.sprite=back end
    end)
  end

  local function representationFor(name,battle)
    local side=presentationSide(name)
    if crystal and side=="front" and actor[name].liveFront then
      return actor[name].liveFront,side,1
    end
    local img,displayScale=staticRepresentation(name,side,battle)
    return img,side,displayScale or 1
  end

  -- Rebase37 Secondary View art-only seam. This does NOT ask Battle Art to
  -- render a second battle scene and does not touch provider ownership. It
  -- exposes one fixed FRONT image for a private BC portrait while Battle Art
  -- continues to own the main staged battler.
  --
  -- STATIC/ANIMATED collections are read from Battle Art's own image/atlas
  -- helpers. ANIMATED uses an independent read-only phase derived from wall
  -- time; it never calls AnimatedBattleArt.update() and therefore never steps
  -- the live main actor twice. ROM/MODDED falls through the existing engine /
  -- Crystal representation bridge, including Crystal's already-maintained live
  -- FRONT stream.
  state.secondaryViewProbe.battleArtFixedFront=function(battle)
    if not battle then return nil,"no battle" end
    resetBattle(battle)
    captureCrystalLives(battle)

    local battler=battle.player
    local species=battler and type(BattleArt.speciesFor)=="function"
      and BattleArt.speciesFor(battler) or nil
    local art=BattleArt.setting and type(BattleArt.setting.get)=="function"
      and BattleArt.setting:get() or "rom"

    if art=="static" and species and type(BattleArt.image)=="function" then
      local ok,img=pcall(BattleArt.image,species,"front",battler)
      if ok and img then return img,"battle_art_static" end
    elseif art=="animated" and species
        and type(AnimatedBattleArt.interfaceFront)=="function" then
      local generation=BattleArt.frontAnimationSetting
        and type(BattleArt.frontAnimationSetting.get)=="function"
        and BattleArt.frontAnimationSetting:get() or "gen5"
      local displayMode=type(BattleArt.displayMode)=="function"
        and BattleArt.displayMode() or "pixel"
      local ok,frames,durations=pcall(AnimatedBattleArt.interfaceFront,
        species,generation,displayMode,"bc_secondary_view")
      if ok and type(frames)=="table" and #frames>0 then
        local now=((love and love.timer and love.timer.getTime)
          and love.timer.getTime() or 0)
        local total=0
        for i=1,#frames do
          total=total+math.max(0.001,(tonumber(durations and durations[i]) or 100)/1000)
        end
        if total<=0 then return frames[1],"battle_art_animated" end
        local t=now%total
        for i=1,#frames do
          local d=math.max(0.001,(tonumber(durations and durations[i]) or 100)/1000)
          if t<d then return frames[i],"battle_art_animated" end
          t=t-d
        end
        return frames[#frames],"battle_art_animated"
      end
      -- Missing atlas is Battle Art's own ROM fallback contract.
    end

    if crystal and actor.player.liveFront then
      return actor.player.liveFront,"crystal_live_front"
    end
    local img=staticRepresentation("player","front",battle)
    if img then return img,"rom_or_modded_front" end
    return nil,"fixed FRONT unavailable"
  end

  local function withExternalRepresentation(name,battle,fn)
    if not (externalRepresentationPath() and mode()=="dynamic" and fullSideCapable()) then
      return fn()
    end
    local battler=battle and battle[name] or nil
    if not battler then return fn() end
    local img=representationFor(name,battle)
    if not img then return fn() end
    local prior=battler.sprite
    battler.sprite=img
    local r={pcall(fn)}
    battler.sprite=prior
    if not r[1] then error(r[2],0) end
    table.remove(r,1)
    return unpack_(r)
  end

  -- Static Battle Art: call its own apply path once per battler with that actor
  -- occupying the module's existing player-side seam. No image paths, species
  -- names, scales or palettes are reconstructed by BC.
  if type(BattleArt.apply)=="function" and not BattleArt.__bcSpriteFacingApplyInstalled then
    local originalApply=BattleArt.apply
    BattleArt.apply=function(battle)
      if not active() then return originalApply(battle) end
      updateOrientation(battle)
      if type(BattleArt.applyTrainers)=="function" then BattleArt.applyTrainers(battle) end
      for _,name in ipairs({"player","enemy"}) do
        local side=presentationSide(name)
        withForcedSide(side,function()
          originalApply(proxyFor(name,battle))
        end)
      end
    end
    BattleArt.__bcSpriteFacingApplyInstalled=true
  end

  -- Animated Battle Art: keep the module's private animation state in charge.
  -- Its updater was authored for enemy-front + selectable-player-side, so BC
  -- feeds each real battler through that selectable player seam separately.
  -- This advances the selected live FRONT or BACK collection exactly once
  -- per frame for each actor, including Gen 3/5 animated backs, without BC decoding it.
  if type(AnimatedBattleArt.update)=="function"
      and not AnimatedBattleArt.__bcSpriteFacingUpdateInstalled then
    local originalUpdate=AnimatedBattleArt.update
    AnimatedBattleArt.update=function(battle,dt)
      if not active() then return originalUpdate(battle,dt) end
      updateOrientation(battle)
      if not battle then return end

      -- Preserve Battle Art's trainer lifecycle on the real battle identity,
      -- but hide both Pokemon from this pass so neither receives an unwanted
      -- default-side update.
      local bp,be=battle.player,battle.enemy
      battle.player,battle.enemy=nil,nil
      local trainerResult={pcall(originalUpdate,battle,dt)}
      battle.player,battle.enemy=bp,be
      if not trainerResult[1] then error(trainerResult[2],0) end

      for _,name in ipairs({"player","enemy"}) do
        local side=presentationSide(name)
        withForcedSide(side,function()
          originalUpdate(proxyFor(name,battle),dt)
        end)
      end
    end
    AnimatedBattleArt.__bcSpriteFacingUpdateInstalled=true
  end

  -- BattleScene's local card builder mirrors only the player by design. Rather
  -- than replacing Battle Art's renderer, adapt the captured texture metadata:
  -- player orientation uses its existing noMirror flag; an enemy that needs a
  -- horizontal turn receives a mirrored copy of its tiny side canvas with the
  -- anchor reflected with it. Battle Art still owns dimensions, lighting,
  -- shadows, depth and world placement.
  local function desiredMirror(name,side,tex)
    local desiredRight=actor[name].turn=="right"
    local mirror
    if side=="back" then
      -- Runtime validation established that Battle Art's supplied back-art handedness is the
      -- opposite of the assumption used by the first adapter. Keep the BC
      -- turn semantic unchanged and invert only the Battle Art consumer.
      mirror=not desiredRight
    elseif name=="player" then
      -- Preserve Battle Art's DEFAULT/noMirror distinction, then apply the
      -- provider-specific polarity correction established in runtime validation.
      local intrinsicRight=tex and tex.noMirror and true or false
      mirror=desiredRight~=intrinsicRight
    else
      mirror=desiredRight
    end
    return not mirror
  end

  local function flipCanvas(src,key)
    if not (src and love and love.graphics and type(src.getDimensions)=="function") then return nil end
    local w,h=src:getDimensions()
    if not (w and h and w>0 and h>0) then return nil end
    local rec=mirroredCanvas[key]
    if not rec or rec.w~=w or rec.h~=h then
      local ok,c=pcall(love.graphics.newCanvas,w,h)
      if not ok or not c then return nil end
      if type(c.setFilter)=="function" then pcall(c.setFilter,c,"nearest","nearest") end
      rec={canvas=c,w=w,h=h}; mirroredCanvas[key]=rec
    end
    local g=love.graphics
    local prevCanvas=g.getCanvas()
    local br,ba=g.getBlendMode()
    local cr,cg,cb,ca=g.getColor()
    local ok=pcall(function()
      g.setCanvas(rec.canvas)
      g.clear(0,0,0,0)
      g.setBlendMode("alpha")
      g.setColor(1,1,1,1)
      g.draw(src,w,0,0,-1,1)
    end)
    if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
    g.setBlendMode(br or "alpha",ba)
    g.setColor(cr,cg,cb,ca)
    if not ok then return nil end
    return rec.canvas,w,h
  end

  if type(OverworldBattle.sideTexture)=="function"
      and not OverworldBattle.__bcSpriteFacingSideTextureInstalled then
    local originalSideTexture=OverworldBattle.sideTexture
    OverworldBattle.sideTexture=function(battle,side)
      if side=="player" or side=="enemy" then updateOrientation(battle) end
      local externalDisplayScale=1
      if (side=="player" or side=="enemy") and externalRepresentationPath() then
        -- Resolve the same semantic representation that the card is about to
        -- show even in TURN ONLY. This does NOT install the image in TURN ONLY;
        -- it only recovers the engine/provider's intended display scale lost
        -- when Battle Art deliberately captures the card texture at 1x.
        local _,repSide,scale=representationFor(side,battle)
        if repSide=="back" and tonumber(scale) and tonumber(scale)>0 then
          externalDisplayScale=tonumber(scale)
        end
      end
      local tex
      if side=="player" or side=="enemy" then
        tex=withExternalRepresentation(side,battle,function()
          return originalSideTexture(battle,side)
        end)
      else
        tex=originalSideTexture(battle,side)
      end
      if not (active() and tex and not tex.trainer
          and (side=="player" or side=="enemy")) then return tex end
      local name=side
      local rep=presentationSide(name)
      if externalRepresentationPath() and rep=="back" and externalDisplayScale~=1 then
        tex.presentationScale=(tonumber(tex.presentationScale) or 1)*externalDisplayScale
      end
      local mirror=desiredMirror(name,rep,tex)
      if name=="player" then
        -- BattleScene computes player mirror as `not tex.noMirror`.
        tex.noMirror=not mirror
      elseif mirror and tex.canvas then
        local flipped,w=flipCanvas(tex.canvas,"enemy")
        if flipped then
          tex.canvas=flipped
          if tonumber(tex.ax) then tex.ax=w-tonumber(tex.ax) end
        end
      end
      return tex
    end
    OverworldBattle.__bcSpriteFacingSideTextureInstalled=true
  end

  local hudFont=nil
  pcall(function()
    mod.hooks:wrap("render.hud",function(nextFn,game,viewport)
      local result=nextFn(game,viewport)
      if battleRef and active() and mod.options:get("diagnostics")=="on"
          and love and love.graphics then
        pcall(function()
          local g=love.graphics
          if not hudFont then hudFont=g.newFont(11) end
          local art=BattleArt.setting and BattleArt.setting:get() or "?"
          local lines={
            string.format("BC SPRITE FACE BATTLE ART mode=%s art=%s",mode(),tostring(art)),
            string.format("P side=%s turn=%s dx=%s",presentationSide("player"),actor.player.turn,actor.player.screenDelta and string.format("%.3f",actor.player.screenDelta) or "?"),
            string.format("E side=%s turn=%s dx=%s",presentationSide("enemy"),actor.enemy.turn,actor.enemy.screenDelta and string.format("%.3f",actor.enemy.screenDelta) or "?"),
          }
          g.setFont(hudFont)
          local y=42
          for _,line in ipairs(lines) do
            g.setColor(0,0,0,0.8); g.rectangle("fill",6,y-1,hudFont:getWidth(line)+8,14)
            g.setColor(1,1,1,1); g.print(line,10,y); y=y+15
          end
          g.setColor(1,1,1,1)
        end)
      end
      return result
    end)
  end)

  local function clearBattleRef()
    battleRef=nil
    forcedSide=nil
    proxy.player,proxy.enemy={},{}
    actor.player.liveFront=nil
    actor.enemy.liveFront=nil
  end

  if type(OverworldBattle.finish)=="function"
      and not OverworldBattle.__bcSpriteFacingFinishInstalled then
    local originalFinish=OverworldBattle.finish
    OverworldBattle.finish=function(...)
      clearBattleRef()
      return originalFinish(...)
    end
    OverworldBattle.__bcSpriteFacingFinishInstalled=true
  end

  if type(OverworldBattle.invalidate)=="function"
      and not OverworldBattle.__bcSpriteFacingInvalidateInstalled then
    local originalInvalidate=OverworldBattle.invalidate
    OverworldBattle.invalidate=function(...)
      clearBattleRef()
      return originalInvalidate(...)
    end
    OverworldBattle.__bcSpriteFacingInvalidateInstalled=true
  end

  BattleArt.__bcSpriteFacingBattleArtInstalled=true
  mod.log:info("Battle Art 1.9.6 sprite-facing consumer active: native + ROM/MODDED HOST DEFAULT / TURN ONLY / DYNAMIC")
end)()


-- Stadium2 Importer live-frame bridge ---------------------------------------
-- Keep the importer's own 3D scene. BC supplies only camera eye/focus/FOV when
-- one of its phases owns the frame. EXTERNAL and BC-disabled frames are returned
-- byte-for-byte from the provider camera, preserving its native right-stick,
-- drift, letterbox and renderer composition.
;(function(host)
  if not host then return end
  local Camera,originalFrame,BattleCam=host.Camera,host.providerFrame,host.backend.BattleCam
  if Camera.__bcLiveFrameWrapped then return end
  local LOVE_CANVAS_Y={1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1}
  local function matMul(a,b)
    local o={}
    for r=0,3 do for c=0,3 do
      local v=0
      for k=0,3 do v=v+a[r*4+k+1]*b[k*4+c+1] end
      o[r*4+c+1]=v
    end end
    return o
  end
  local function perspective(fovy,aspect,near,far)
    local f=1/math.tan(fovy*.5)
    return {f/aspect,0,0,0, 0,f,0,0,
      0,0,(far+near)/(near-far),(2*far*near)/(near-far), 0,0,-1,0}
  end
  local function lookAt(ex,ey,ez,tx,ty,tz)
    local fx,fy,fz=tx-ex,ty-ey,tz-ez
    local fl=math.sqrt(fx*fx+fy*fy+fz*fz); if fl==0 then fl=1 end
    fx,fy,fz=fx/fl,fy/fl,fz/fl
    local sx,sy,sz=fy*0-fz*1,fz*0-fx*0,fx*1-fy*0
    local sl=math.sqrt(sx*sx+sy*sy+sz*sz); if sl==0 then sx,sy,sz,sl=1,0,0,1 end
    sx,sy,sz=sx/sl,sy/sl,sz/sl
    local ux,uy,uz=sy*fz-sz*fy,sz*fx-sx*fz,sx*fy-sy*fx
    return {sx,sy,sz,-(sx*ex+sy*ey+sz*ez),
      ux,uy,uz,-(ux*ex+uy*ey+uz*ez),
      -fx,-fy,-fz,fx*ex+fy*ey+fz*ez, 0,0,0,1}
  end
  local function fovFromFrame(frame)
    local p=type(frame)=="table" and frame.projection or nil
    local f=p and math.abs(tonumber(p[6]) or 0) or 0
    if f>1e-5 then return 2*math.atan(1/f) end
    return math.rad(55)
  end
  local function baseFromFrame(frame)
    if type(frame)~="table" or type(frame.eye)~="table" or type(frame.focus)~="table" then return nil end
    return {eye={frame.eye[1],frame.eye[2],frame.eye[3]},
      focus={frame.focus[1],frame.focus[2],frame.focus[3]},up={0,1,0},
      fov=fovFromFrame(frame),curve=0}
  end
  local function sameCamera(a,b)
    if not (a and b and a.eye and b.eye and a.focus and b.focus) then return false end
    local d=0
    for i=1,3 do d=d+math.abs((a.eye[i] or 0)-(b.eye[i] or 0))
      +math.abs((a.focus[i] or 0)-(b.focus[i] or 0)) end
    d=d+math.abs((tonumber(a.fov) or 0)-(tonumber(b.fov) or 0))*20
    return d<1e-5
  end
  local function bcFrame(cam,provider,width,height)
    width=math.max(1,tonumber(width) or 1); height=math.max(1,tonumber(height) or 1)
    local eye,focus=cam.eye,cam.focus
    local view=lookAt(eye[1],eye[2],eye[3],focus[1],focus[2],focus[3])
    local projection=matMul(LOVE_CANVAS_Y,perspective(tonumber(cam.fov) or math.rad(55),
      width/height,.1,1000))
    return {view=view,projection=projection,vp=matMul(projection,view),
      eye={eye[1],eye[2],eye[3]},focus={focus[1],focus[2],focus[3]},
      letterbox=provider and provider.letterbox or nil}
  end

  local wasActive=false
  Camera.frame=function(width,height)
    local okStatus,status=pcall(host.exports.battleStatus)
    local active=okStatus and type(status)=="table" and status.active or false
    if active and not wasActive then
      -- The importer Camera module is shared across Gen1 battle sessions and its
      -- native Gen1 finish path clears stick input without recentering orbit,
      -- pitch or zoom. Start each BC/importer battle from the provider's own
      -- canonical neutral camera exactly once; subsequent native right-stick
      -- input remains entirely provider-owned whenever its frame is visible.
      if type(Camera.recentre)=="function" then pcall(Camera.recentre) end
      if type(Camera.reset)=="function" then pcall(Camera.reset) end
    end
    wasActive=active
    local providerFrame=originalFrame(width,height)
    if not active then return providerFrame end
    if not enabled() then return providerFrame end
    host.base=baseFromFrame(providerFrame)
    if not host.base then return providerFrame end
    local okCam,cam=pcall(BattleCam.rig,host.arena,0,false)
    if not okCam or type(cam)~="table" or type(cam.eye)~="table"
        or type(cam.focus)~="table" then return providerFrame end
    if sameCamera(cam,host.base) then return providerFrame end
    return bcFrame(cam,providerFrame,width,height)
  end
  Camera.__bcLiveFrameWrapped=true
  mod.log:warn("[BC GEN1] Stadium2 Importer live Camera.frame bridge active")
end)(backends.__stadium2importer)

-- Provider-independent manual right-stick camera ----------------------------
-- Gen 1 ONLY initialization. Current Gold intentionally leaves manual right-stick
-- control to the active provider whenever that provider owns the visible camera.
-- BC-owned Gold phases remain authored BC shots; the Gen1 controller is excluded
-- whenever the Gold adapter is active, so the two input systems never compete.
-- manual state or input polling added around it.
if not backends.__gold then
-- v1.0.4 release requirement: this is BC camera behaviour, not a Gold/Randy
-- feature. Gold keeps its already-proven adapter-specific implementation below;
-- Gen 1 gets the same user contract here above every compatible BC backend:
-- grab the EXACT currently visible camera, orbit its current focus while the
-- right stick is held, briefly hold, then softly reacquire the authored BC shot.
--
-- Keep this closure self-contained: main.lua is already close to Lua's local
-- limit, and manual-camera helper locals do not belong in the main chunk.
(function()
  local M={
    active=false,hold=0,returning=false,reacquire=1,
    angle=0,radius=80,elev=0.35,focus=nil,fov=math.rad(55),
    lastVisible=nil,lastManual=nil,seedCamera=nil,
    inputArmed=false,neutralTime=0,
  }
  state.manualCamera=M

  local function clamp(x,a,b)
    x=tonumber(x) or 0
    if x<a then return a elseif x>b then return b end
    return x
  end
  local function smooth(t)
    t=clamp(t,0,1)
    return t*t*t*(t*(t*6-15)+10)
  end
  local function mix(a,b,t)
    return (tonumber(a) or 0)+((tonumber(b) or 0)-(tonumber(a) or 0))*t
  end
  local function copy(cam)
    if type(cam)~="table" or type(cam.eye)~="table" or type(cam.focus)~="table" then return nil end
    return {
      eye={cam.eye[1],cam.eye[2],cam.eye[3]},
      focus={cam.focus[1],cam.focus[2],cam.focus[3]},
      up={0,1,0},fov=tonumber(cam.fov) or math.rad(55),curve=tonumber(cam.curve) or 0,
    }
  end
  local function blend(a,b,t)
    if not a then return b end
    if not b then return a end
    t=smooth(t)
    return {
      eye={mix(a.eye[1],b.eye[1],t),mix(a.eye[2],b.eye[2],t),mix(a.eye[3],b.eye[3],t)},
      focus={mix(a.focus[1],b.focus[1],t),mix(a.focus[2],b.focus[2],t),mix(a.focus[3],b.focus[3],t)},
      up={0,1,0},fov=mix(a.fov,b.fov,t),curve=mix(a.curve,b.curve,t),
    }
  end

  -- Gen1Recomp's ordinary Input abstraction intentionally consumes the LEFT
  -- stick as Game Boy directions and does not expose the right stick as a GB
  -- action. Poll LOVE's standardized gamepad right axes read-only instead.
  -- This does not assign or replace any love.* callback and therefore preserves
  -- BC's Mod API 2 rule.
  local function pollRightStick()
    local js=love and love.joystick
    if not (js and type(js.getJoysticks)=="function") then return 0,0,false end
    local ok,list=pcall(js.getJoysticks)
    if not ok or type(list)~="table" then return 0,0,false end
    local bestX,bestY,bestMag=0,0,-1
    local available=false
    for _,j in ipairs(list) do
      if j and type(j.getGamepadAxis)=="function" then
        local okX,x=pcall(j.getGamepadAxis,j,"rightx")
        local okY,y=pcall(j.getGamepadAxis,j,"righty")
        x=okX and tonumber(x) or nil
        y=okY and tonumber(y) or nil
        if x and y then
          available=true
          local mag=x*x+y*y
          if mag>bestMag then bestX,bestY,bestMag=x,y,mag end
        end
      end
    end
    return bestX,bestY,available
  end

  local function seedFromVisible()
    local cam=M.lastVisible
    if not cam then return false end
    local dx=(cam.eye[1] or 0)-(cam.focus[1] or 0)
    local dy=(cam.eye[2] or 0)-(cam.focus[2] or 0)
    local dz=(cam.eye[3] or 0)-(cam.focus[3] or 0)
    local flat=math.sqrt(dx*dx+dz*dz)
    local r=math.sqrt(flat*flat+dy*dy)
    if r<1 then return false end
    M.angle=math.atan2(dx,dz)
    M.radius=r
    M.elev=math.atan2(dy,math.max(1e-3,flat))
    M.focus={cam.focus[1],cam.focus[2],cam.focus[3]}
    M.fov=tonumber(cam.fov) or math.rad(55)
    M.seedCamera=copy(cam)
    M.lastManual=copy(cam)
    M.active=true
    M.hold=0.70
    M.returning=false
    M.reacquire=0
    return true
  end

  function M.reset()
    M.active=false; M.hold=0; M.returning=false; M.reacquire=1
    M.focus=nil; M.lastManual=nil; M.seedCamera=nil
  end

  -- A fresh Gen 1 battle must prove that the physical right stick has returned
  -- to neutral before BC can interpret movement as a manual-camera request.
  -- This prevents stale overworld axis state / controller drift from seeding an
  -- unintended continuous orbit on the first visible battle frames.
  function M.resetInputBoundary()
    M.reset()
    M.lastVisible=nil
    M.inputArmed=false
    M.neutralTime=0
  end

  -- Ticked from BC's existing input.step hook using cameraDelta(), so manual
  -- motion remains presentation-time based under accelerated game speed.
  function M.step(dt)
    if backends.__gold then return end -- Gold has its proven host adapter below.
    dt=math.max(0,math.min(0.1,tonumber(dt) or 0))
    if not enabled() or not state.rigSeen then
      if M.active or M.returning then M.reset() end
      return
    end

    local rx,ry=0,0
    local x,y,available=pollRightStick()
    if available then rx,ry=x,y end
    if math.abs(rx)<=0.10 then rx=0 end
    if math.abs(ry)<=0.10 then ry=0 end
    local moving=(rx~=0 or ry~=0)

    -- Battle-boundary neutral arming. A non-neutral value inherited from the
    -- overworld is ignored until the stick has been cleanly neutral for a short
    -- continuous window. Once armed, normal 0.10-deadzone control is unchanged.
    if not M.inputArmed then
      if not available or moving then
        M.neutralTime=0
      else
        M.neutralTime=M.neutralTime+dt
        if M.neutralTime>=0.06 then M.inputArmed=true end
      end
      return
    end

    if moving and not M.active then seedFromVisible() end
    if M.active then
      if moving then
        M.angle=M.angle-rx*dt*2.9
        M.elev=clamp(M.elev-ry*dt*1.65,-0.18,0.95)
        M.hold=0.70
      else
        M.hold=M.hold-dt
        if M.hold<=0 then
          M.active=false
          M.returning=true
          M.reacquire=0
        end
      end
    elseif M.returning then
      M.reacquire=clamp(M.reacquire+dt/0.38,0,1)
      if M.reacquire>=1 then
        M.returning=false
        M.lastManual=nil
        M.seedCamera=nil
      end
    end
  end

  local function manualCamera()
    if not (M.focus and M.radius and M.angle and M.elev) then return nil end
    local flat=M.radius*math.cos(M.elev)
    return {
      eye={M.focus[1]+math.sin(M.angle)*flat,
           M.focus[2]+M.radius*math.sin(M.elev),
           M.focus[3]+math.cos(M.angle)*flat},
      focus={M.focus[1],M.focus[2],M.focus[3]},
      up={0,1,0},fov=M.fov,curve=0,
    }
  end

  -- Manual is allowed to look away from the subjects, so the soft readability
  -- grammar must NOT fight the player. It still receives stateless hard world
  -- protection: map envelope, canopy/roof route clearance, and wall/building
  -- occupancy/path rejection. Authored-shot safety state is left untouched so
  -- the director can continue invisibly underneath and be reacquired cleanly.
  local function hardProtect(backend,arena,camera,groundY)
    if not (camera and camera.eye and camera.focus) then return camera end
    local eye={camera.eye[1],camera.eye[2],camera.eye[3]}
    clampEyeToArena(arena,camera.focus[1],camera.focus[3],eye,M.radius)
    local out=state.floorProtectCamera(bcCopyCameraWithEye(camera,eye),groundY)
    if not (type(arena)=="table" and type(arena.map)=="table" and not arena.discs) then
      return out
    end
    local cache=bcGeomCacheFor(backend,arena.map)
    if not cache.supported then return out end

    local start=(M.lastVisible and M.lastVisible.eye)
        or (M.seedCamera and M.seedCamera.eye) or out.eye

    -- Clear known canopy/building-roof surfaces vertically without borrowing
    -- the authored shot's stateful crest/readability machinery.
    local top,source=bcCanopyTopAt(cache,out.eye[1],out.eye[3])
    if top then
      local margin=(tostring(source or ""):find("building-roof",1,true)~=nil)
          and 5.0 or BC_CANOPY_CLEARANCE
      if out.eye[2]<top+margin then
        out=bcCopyCameraWithEye(out,{out.eye[1],top+margin,out.eye[3]})
      end
    end
    if start then
      local candidate={out.eye[1],out.eye[2],out.eye[3]}
      for _=1,4 do
        local miss=select(1,bcCanopyPathViolation(cache,start,candidate))
        if not miss or miss<=0.02 then break end
        candidate[2]=candidate[2]+miss+0.08
      end
      out=bcCopyCameraWithEye(out,candidate)
    end

    local blocked=select(1,bcGeomWallPoint(cache,out.eye[1],out.eye[2],out.eye[3]))
    if blocked then return copy(M.lastVisible) or copy(M.seedCamera) or out end
    if start then
      local hit,_,_,lastSafe=bcGeomWallLine(cache,start,out.eye)
      if hit then
        if lastSafe then out=bcCopyCameraWithEye(out,lastSafe)
        else return copy(M.lastVisible) or copy(M.seedCamera) or out end
      end
    end
    return out
  end

  local function wrapBackend(backend)
    if backend.gold then return end
    local BattleCam=backend.BattleCam
    if type(BattleCam)~="table" or type(BattleCam.rig)~="function"
        or BattleCam.__bcManualTakeoverWrapped then return end
    local inner=BattleCam.rig
    BattleCam.rig=function(arena,groundY,canonical)
      local cam,pitch=inner(arena,groundY,canonical)
      if canonical then return cam,pitch end
      if not (type(cam)=="table" and type(cam.eye)=="table" and type(cam.focus)=="table") then
        return cam,pitch
      end

      local out=cam
      if enabled() and M.active then
        out=manualCamera() or cam
        out=hardProtect(backend,arena,out,groundY) or cam
        M.lastManual=copy(out)
      elseif enabled() and M.returning and M.lastManual then
        out=blend(M.lastManual,cam,M.reacquire)
        out=hardProtect(backend,arena,out,groundY) or cam
      end

      M.lastVisible=copy(out)
      -- Sprite-facing must consume the camera that is ACTUALLY visible after
      -- manual takeover, not the authored camera captured by the inner BC rig.
      -- A one-frame-late provider update is sufficient and keeps this read-only.
      if (backend.id=="DRAMATIC_SHAPE" or backend.id=="DRAMALESS_SHAPE" or backend.id=="BATTLE_ART_VOXEL_FORK" or backend.id=="potato_voxel" or backend.id=="VOXEL_ASCENDANT") and M.lastVisible then
        state.spriteFacingCamera=copy(M.lastVisible)
      end
      if out~=cam then
        return out,bcPitchForCamera(out) or pitch
      end
      return cam,pitch
    end
    BattleCam.__bcManualTakeoverWrapped=true
  end

  for _,backend in ipairs(backends) do wrapBackend(backend) end
  mod.log:info("provider-independent manual right-stick camera active on Gen 1 backends")
end)()
end

-- Gold Test 6B runtime bridge ------------------------------------------------
-- Tests 4/5B proved the released BC passive director, BC Hero / Send-In Director
-- and provider-independent manual camera can run above Randy's live Gold battle
-- space. Test 6 adds only the presentation facts required by the EXISTING
-- Stadium Attack Camera and Faint Camera.  No duplicate Gold choreography is
-- invented and no Gen-1 structural/world-geometry assumptions are added here.
if backends.__gold then
  (function(gold)
    local BC=gold.BattleCinematic
    local OW=gold.OverworldBattle
    local VS=gold.VoxelScene
    local V3=gold.Voxel3D
    local FP=gold.FirstPerson
    local originalFrame=gold.providerFrame
    local originalRender=gold.providerRender

    -- Gold's move semantics and animation clock are generation-specific adapter
    -- evidence.  Gen 1's Attack Camera consumes move_effects/AnimPlayer; Gold
    -- exposes a different effect table and a frame-stepped AnimRunner.  Keep
    -- those differences private to this bridge instead of weakening the shared
    -- Stadium grammar.
    local okGoldEffects,GoldEffects=pcall(require,"src.battle.gen2.Effects")
    if not okGoldEffects then GoldEffects=nil end
    local okGoldBattle,GoldBattle=pcall(require,"src.battle.gen2.Battle")
    if not okGoldBattle then GoldBattle=nil end
    local okGoldRunner,GoldAnimRunner=pcall(require,"src.battle.gen2.AnimRunner")
    if not okGoldRunner then GoldAnimRunner=nil end
    local goldAnimTotals={}
    local function clamp(x,a,b) return math.max(a,math.min(b,tonumber(x) or 0)) end
    local function mix(a,b,t) return (tonumber(a) or 0)+((tonumber(b) or 0)-(tonumber(a) or 0))*t end
    local function smooth(t) t=clamp(t,0,1); return t*t*t*(t*(t*6-15)+10) end
    local function copy(cam)
      if type(cam)~="table" or type(cam.eye)~="table" or type(cam.focus)~="table" then return nil end
      return {eye={cam.eye[1],cam.eye[2],cam.eye[3]},focus={cam.focus[1],cam.focus[2],cam.focus[3]},
        up={0,1,0},fov=tonumber(cam.fov) or math.rad(55),curve=tonumber(cam.curve) or 0}
    end
    local function blend(a,b,t)
      if not a then return b end; if not b then return a end; t=smooth(t)
      return {eye={mix(a.eye[1],b.eye[1],t),mix(a.eye[2],b.eye[2],t),mix(a.eye[3],b.eye[3],t)},
        focus={mix(a.focus[1],b.focus[1],t),mix(a.focus[2],b.focus[2],t),mix(a.focus[3],b.focus[3],t)},
        up={0,1,0},fov=mix(a.fov,b.fov,t),curve=mix(a.curve,b.curve,t)}
    end
    local function stickActive()
      if type(FP)~="table" then return false end
      if type(FP.pollMappedRightStick)=="function" then pcall(FP.pollMappedRightStick) end
      local rx=type(FP.stickX)=="function" and tonumber(FP.stickX()) or 0
      local ry=type(FP.stickY)=="function" and tonumber(FP.stickY()) or 0
      return math.abs(rx or 0)>0.10 or math.abs(ry or 0)>0.10
    end
    local function seedManual(ctx)
      local cam=gold.lastVisible
      if not (cam and ctx and type(ctx.arena)=="table") then return end
      local gy=tonumber(ctx.groundY) or 0
      local fx,fz=cam.focus[1],cam.focus[3]
      local dx,dz=cam.eye[1]-fx,cam.eye[3]-fz
      local r=math.sqrt(dx*dx+dz*dz)
      if r<1 then return end
      BC.angle=math.atan2(dx,dz)
      BC.radius=r
      BC.height=(cam.eye[2] or gy+48)-gy
      BC.manualPitch=0
      BC.focusX,BC.focusZ=fx,fz
      BC.manualHold=0
    end

    -- Gen 2 intentionally shares BC's battle event vocabulary, but its live
    -- BattleState screen uses different presentation fields.  Keep a stable
    -- proxy per underlying mon so Faint Camera can hold the defeated visual
    -- subject across frames without mutating Gold's own battle objects.
    local monViews=setmetatable({}, {__mode="k"})
    local function monView(mon,shownHP)
      if type(mon)~="table" then return mon end
      local view=monViews[mon]
      if not view then
        view={__goldMon=mon}
        setmetatable(view,{__index=mon})
        monViews[mon]=view
      end
      view.shownHP=shownHP
      view.fainted=((tonumber(mon.hp) or 0)<=0)
      return view
    end
    -- Gold classification equivalent of classifyAttackMove().  The old shared
    -- classifier deliberately understands Gen 1's move_effects records, including
    -- accuracyChecked.  Gold instead exposes gen2MoveEffects and explicit effect
    -- direction tables.  Without this adapter, opponent-directed zero-power moves
    -- such as String Shot fall through to SELF even though their actual target is
    -- across the field.
    gold.classifyAttackMove=function(logic,move)
      if not move then return "target" end
      if (tonumber(move.power) or 0)>0 then return "target" end
      local effect=move.effect
      if move.id=="HAZE" or effect=="EFFECT_HAZE" then return "field" end
      if GoldEffects then
        local change=GoldEffects.STAT_CHANGES and GoldEffects.STAT_CHANGES[effect] or nil
        if type(change)=="table" then
          return change[3]=="foe" and "target" or "self"
        end
        if GoldEffects.WEATHER and GoldEffects.WEATHER[effect] then return "field" end
      end
      if GoldBattle and type(GoldBattle.moveEffectRecordFor)=="function" then
        local ok,record=pcall(GoldBattle.moveEffectRecordFor,logic and logic.data or nil,effect)
        if ok and type(record)=="table" and record.kind=="primary" and record.status then
          return "target"
        end
      end
      -- Unknown zero-power Gold effects remain conservative/self, matching the
      -- established Gen 1 fallback rather than inventing a target.
      return "self"
    end

    -- Compute the ACTUAL duration of Gold's native move script once, using the
    -- same frame-stepped AnimRunner the BattleState is already presenting.  This
    -- gives the shared Stadium launch/track/impact/rise grammar the same kind of
    -- normalized progress signal it receives from Gen 1 AnimPlayer.  A capped
    -- no-op simulation is deterministic for ordinary move scripts and cached by
    -- move/turn/param; failure simply falls back to the existing visual seams.
    local function goldAnimTotalFrames(screen,anim)
      if not (GoldAnimRunner and type(GoldAnimRunner.new)=="function"
          and type(screen)=="table" and type(anim)=="table"
          and type(anim.env)=="table" and anim.clearsHud) then return nil end
      local moveId=anim.env.animId
      if type(moveId)~="string" or moveId:match("^ANIM_") then return nil end
      local script=screen.anims and screen.anims.moves and screen.anims.moves[moveId] or nil
      if not script then return nil end
      local turn=tonumber(anim.env.battleTurn) or 0
      local param=tonumber(anim.param) or 0
      local key=moveId.."|"..tostring(turn).."|"..tostring(param)
      if goldAnimTotals[key] then return goldAnimTotals[key] end
      local ok,total=pcall(function()
        local runner=GoldAnimRunner.new({
          data=screen.anims or anim.data or {},
          constants=anim.constants or {},
          battleTurn=turn,param=param,sfxOrder=anim.sfxOrder or {},hooks={}
        })
        runner:start(script)
        local frames=0
        for _=1,3600 do
          frames=frames+1
          if not runner:step() then break end
        end
        if frames>=3600 then return nil end
        return math.max(1,frames)
      end)
      if ok and total then goldAnimTotals[key]=total; return total end
      return nil
    end

    local function activeAnim(screen)
      local anim=type(screen and screen.anim)=="table" and screen.anim or nil
      if not anim then return nil,false end
      local done=false
      if type(anim.done)=="function" then
        local ok,v=pcall(anim.done,anim); done=ok and v and true or false
      end
      -- Gen 2 can retain a finished keepsprites runner for drawing OAM.  That
      -- runner no longer owns presentation timing and must not pin Attack Camera.
      if done and anim.keepSprites then return anim,false end
      return anim,true
    end
    local function battleView(ctx)
      local screen=ctx and ctx.screen
      local logic=ctx and (ctx.battle or (screen and screen.battle))
      if not (type(screen)=="table" and type(logic)=="table") then return nil end
      local after=type(screen.afterSendOut)=="table" and screen.afterSendOut or nil
      local shown=type(screen.shownHp)=="table" and screen.shownHp or nil
      -- Gold deliberately keeps the *visually presented* battlers in shownMon.
      -- Logic battle.player/enemy may already point at an incoming replacement
      -- while the outgoing defeated Pokemon is still finishing its faint scene.
      -- Feed BC the visual actor, not the prematurely rebound logic slot.
      local shownMon=type(screen.shownMon)=="table" and screen.shownMon or nil
      local visualPlayer=(shownMon and shownMon.player) or logic.player
      local visualEnemy=(shownMon and shownMon.enemy) or logic.enemy
      local playerView=monView(visualPlayer,shown and tonumber(shown.player) or nil)
      local enemyView=monView(visualEnemy,shown and tonumber(shown.enemy) or nil)
      local anim,animPlaying=activeAnim(screen)
      -- Randy's live-world presenter deliberately keeps an acting-side marker
      -- across the whole resolving turn.  On current Gold/Android stacks the
      -- native OBJ/AnimRunner layer may be absent even though the move itself
      -- is genuinely being presented.  Treat that provider-side resolving seam
      -- as the visual attack window rather than requiring `screen.anim`.
      local turnSide=(screen._stadiumActiveSide=="player" or screen._stadiumActiveSide=="enemy")
          and screen._stadiumActiveSide or nil
      local fainting=type(screen.faintSlide)=="table"
      if (not animPlaying) and screen.phase=="resolving" and turnSide and not fainting then
        animPlaying=true
      elseif fainting then
        -- Once Gold begins the visible faint slide, release Attack so BC's
        -- existing Faint Camera can take the next rightful phase.
        animPlaying=false
      end
      local animSide=nil
      if anim then
        if anim.hudSide=="player" or anim.hudSide=="enemy" then
          animSide=anim.hudSide
        elseif type(anim.env)=="table" then
          animSide=(tonumber(anim.env.battleTurn) or 0)==0 and "player" or "enemy"
        end
      end
      if not animSide then animSide=turnSide end
      return {
        player=playerView,
        enemy=enemyView,
        wild=logic.wild,
        showEnemyTrainer=screen.showEnemyTrainer and true or false,
        showPlayerBack=screen.showPlayerTrainer and true or false,
        sendingOut=(after and after.side=="player") and true or false,
        enemySendingOut=(after and after.side=="enemy") and true or false,
        phase=screen.phase,
        -- Existing Attack Camera lifecycle vocabulary. Gen 2's AnimRunner is a
        -- frame-step interpreter rather than Gen 1 AnimPlayer, so BC uses its
        -- established defensive time-progress fallback while the real runner is
        -- active and releases when that presentation ends.
        animPlaying=animPlaying,
        animAttackerIsPlayer=(animSide~=nil) and (animSide=="player") or nil,
        animName=anim and type(anim.env)=="table" and anim.env.animId or nil,
        -- Gen 2 exposes the real move script and the immediately chained
        -- ANIM_*_DAMAGE shake as distinct visual subphases.  Unlike the old
        -- time-only fallback, this gives BC an authoritative IMPACT seam even
        -- when a short move finishes before the four-shot Stadium grammar can
        -- naturally advance to the defender.
        animImpact=anim and ((type(anim.env)=="table" and
          (anim.env.animId=="ANIM_PLAYER_DAMAGE" or anim.env.animId=="ANIM_ENEMY_DAMAGE"))
          and true or false) or false,
        -- Native Gold AnimRunner progress. Runner.frames is already the real 60 Hz
        -- script clock; total is a cached dry-run of that exact move script.
        animElapsedFrames=(anim and anim.clearsHud) and tonumber(anim.frames) or nil,
        animTotalFrames=(anim and anim.clearsHud) and goldAnimTotalFrames(screen,anim) or nil,
        -- A real Gold move runner is uniquely identifiable even on current host
        -- frames where the attacker-side label is temporarily unavailable.
        -- Non-move after-anims do not set clearsHud, so this token cleanly
        -- distinguishes the next actual move from the previous move's damage
        -- shake / HP presentation without changing the engine queue.
        animMoveToken=(anim and anim.clearsHud) and anim or nil,
        -- HP drain is an additional authoritative defender-impact seam and stays
        -- useful when a host replaces/hides Gold's native damage shake.
        hpImpactSide=(type(screen.hpAnim)=="table") and screen.hpAnim.side or nil,
        animPlayer=nil,
        faintSlide=type(screen.faintSlide)=="table" and screen.faintSlide or nil,
        __goldScreen=screen,
        __goldLogic=logic,
      }
    end
    gold.battleView=function()
      local okCtx,ctx=pcall(OW.cameraContext)
      if not okCtx then return nil end
      return battleView(ctx)
    end
    gold.visualBattler=function(side)
      local view=gold.battleView()
      if not view then return nil end
      return side=="player" and view.player or side=="enemy" and view.enemy or nil
    end

    -- Gen 2 resolves the full logic turn before BattleState replays that turn's
    -- presentation queue. Consequently battle.move_used can fire for BOTH sides
    -- before the first visible attack begins. Keep a Gold-only FIFO instead of
    -- letting the second logic event overwrite the first pending BC Attack.
    gold.attackQueue={}
    -- Replacement events are also logic-early in Gen 2. Keep the exact incoming
    -- mon identity so BC Hero cannot consume the pending Intro on the outgoing
    -- fainted actor during the shift prompt / EXP gap before the real send-out.
    gold.expectedIntroMon={player=nil,enemy=nil}
    gold.queueAttack=function(side,moveId,mode)
      if side~="player" and side~="enemy" then return end
      gold.attackQueue[#gold.attackQueue+1]={side=side,moveId=moveId,mode=mode or "target"}
      if #gold.attackQueue>6 then table.remove(gold.attackQueue,1) end
    end
    gold.claimAttack=function(side)
      if side~="player" and side~="enemy" then return nil end
      for i,entry in ipairs(gold.attackQueue) do
        if entry.side==side then
          table.remove(gold.attackQueue,i)
          return entry
        end
      end
      return nil
    end
    -- Gold's logic queue is already in presentation order. On current Randy /
    -- Recomp combinations a real move AnimRunner can briefly exist without a
    -- usable hudSide/_stadiumActiveSide label. In that narrow case consume the
    -- next queued logical move in FIFO order rather than allowing the previous
    -- side's Attack Camera to absorb the new move.
    gold.claimNextAttack=function()
      if #gold.attackQueue<1 then return nil end
      return table.remove(gold.attackQueue,1)
    end

    -- battle.ended is a LOGIC boundary in Gen 2, not the end of the visible
    -- BattleState presentation. A final KO still has HP drain/faint/EXP work to
    -- show after the event has fired. Defer BC teardown until the live screen is
    -- actually done or Randy's cameraContext disappears. This preserves the
    -- proven Test6F provider reset while allowing Faint Camera to see the real
    -- visual faint window.
    gold.finishVisualBattle=function(reason)
      if not gold.battleLive and not gold.logicEnded then return end
      gold.battleLive=false
      gold.logicEnded=false
      gold.endResult=nil
      if type(gold.resetBattleBridge)=="function" then pcall(gold.resetBattleBridge,reason or "visual battle end") end
      state.cameraAuthority.restore()
      state.intro.enemyFreshSendIn=false
      state.intro.playerFaintReplacement=false
      state.battle=nil
      state.intro.pendingEnemy=false
      state.intro.pendingPlayer=false
      clearIntro()
      clearAttack()
      clearFaint()
    end

    -- Provider-independent manual camera. Test 5 still depended on Randy's
    -- STADIUM BATTLE CAMERA being enabled because its frame() was the only
    -- place that converted right-stick input into a manual rig. BC should not
    -- require another author's automatic camera merely to preserve a human
    -- camera grab. Seed from the currently visible BC shot, orbit that exact
    -- focus while the stick is held, then give BC a short soft reacquisition.
    local manual={active=false,hold=0,angle=0,radius=80,elev=0.35,focus=nil,fov=math.rad(55)}

    -- Battle-boundary reset. BC wraps Randy's BattleCinematic.frame so the
    -- provider can keep ticking underneath BC-owned phases, but no BC/provider
    -- camera state is allowed to survive from one encounter into the next.
    -- In particular, seedManual() deliberately writes Randy's own camera fields
    -- while a human is steering; restore those fields through Randy's native
    -- reset() at BOTH battle boundaries rather than waiting for an overworld
    -- frame that may never call the battle camera after the session is removed.
    gold.resetBattleBridge=function(reason)
      manual.active=false
      manual.hold=0
      manual.angle=0
      manual.radius=80
      manual.elev=0.35
      manual.focus=nil
      manual.fov=math.rad(55)
      gold.base=nil
      gold.lastVisible=nil
      OW.__bcRandy2DWorldCardCamera=nil
      gold.lastManual=nil
      gold.manualWas=false
      gold.resume=1
      gold.stickWas=false
      gold.error=nil
      gold.attackQueue={}
      if type(gold.expectedIntroMon)=="table" then
        gold.expectedIntroMon.player=nil
        gold.expectedIntroMon.enemy=nil
      end
      gold.logicEnded=false
      gold.endResult=nil
      for mon in pairs(monViews) do monViews[mon]=nil end
      if type(BC.reset)=="function" then pcall(BC.reset) end
      if reason then
        mod.log:info("[BC GOLD LIFECYCLE] bridge/provider reset: %s",tostring(reason))
      end
    end

    local function beginOwnManual()
      local cam=gold.lastVisible
      if not (cam and cam.eye and cam.focus) then return false end
      local dx=(cam.eye[1] or 0)-(cam.focus[1] or 0)
      local dy=(cam.eye[2] or 0)-(cam.focus[2] or 0)
      local dz=(cam.eye[3] or 0)-(cam.focus[3] or 0)
      local flat=math.sqrt(dx*dx+dz*dz)
      local r=math.sqrt(flat*flat+dy*dy)
      if r<1 then return false end
      manual.angle=math.atan2(dx,dz)
      manual.radius=r
      manual.elev=math.atan2(dy,math.max(1e-3,flat))
      manual.focus={cam.focus[1],cam.focus[2],cam.focus[3]}
      manual.fov=tonumber(cam.fov) or math.rad(55)
      manual.active=true; manual.hold=0.70
      return true
    end
    local function ownManualCam(dt)
      local FP=gold.FirstPerson
      if type(FP)~="table" then return nil,false end
      if type(FP.pollMappedRightStick)=="function" then pcall(FP.pollMappedRightStick) end
      local rx=type(FP.stickX)=="function" and (tonumber(FP.stickX()) or 0) or 0
      local ry=type(FP.stickY)=="function" and (tonumber(FP.stickY()) or 0) or 0
      if math.abs(rx)<=0.10 then rx=0 end
      if math.abs(ry)<=0.10 then ry=0 end
      local moving=(rx~=0 or ry~=0)
      if moving and not manual.active then beginOwnManual() end
      if not manual.active then return nil,false end
      dt=math.max(0,math.min(0.1,tonumber(dt) or 1/60))
      if moving then
        manual.angle=manual.angle-rx*dt*2.9
        manual.elev=clamp(manual.elev-ry*dt*1.65,-0.18,0.95)
        manual.hold=0.70
      else
        manual.hold=manual.hold-dt
        if manual.hold<=0 then manual.active=false; return nil,false end
      end
      if not manual.focus then return nil,false end
      local flat=manual.radius*math.cos(manual.elev)
      local cam={
        eye={manual.focus[1]+math.sin(manual.angle)*flat,
             manual.focus[2]+manual.radius*math.sin(manual.elev),
             manual.focus[3]+math.cos(manual.angle)*flat},
        focus={manual.focus[1],manual.focus[2],manual.focus[3]},
        up={0,1,0},fov=manual.fov,curve=0,
      }
      return cam,true
    end

    BC.frame=function(dt)
      gold.frames=gold.frames+1
      local okCtx,ctx=pcall(OW.cameraContext)
      if not okCtx then ctx=nil end

      -- Randy's provider lifecycle always ticks first. Outside a BC-confirmed
      -- live battle this wrapper is a pure pass-through: no BC state hydration,
      -- no manual seeding, no reacquisition state and no camera substitution.
      -- This gives Randy's own frame() its normal nil-context/reset opportunity
      -- and prevents an ended battle from being re-adopted through a lingering
      -- cameraContext during teardown.
      local okP,providerCam,cx,cz=pcall(originalFrame,dt)
      if not okP then gold.error=tostring(providerCam); providerCam=nil end
      if gold.logicEnded and (not ctx or (ctx.screen and ctx.screen.phase=="done")) then
        if type(gold.finishVisualBattle)=="function" then pcall(gold.finishVisualBattle,"provider visual end") end
        return providerCam,cx,cz
      end
      if not gold.battleLive then
        return providerCam,cx,cz
      end

      -- Gold presentation-state adapter. Randy exposes the live Gold BattleState
      -- as cameraContext().screen; it carries the same send-out/trainer/player/
      -- enemy presentation facts BC Hero consumes. Keep BC pointed at that live
      -- screen even if a shared event payload uses a lower-level logic object.
      if ctx and type(ctx.screen)=="table" then
        local view=battleView(ctx)
        if view then state.battle=view end
      end

      if providerCam then gold.base=copy(providerCam) end

      -- Current Gold host manual-camera ownership:
      -- Randy's current BattleCinematic now owns/polls right-stick camera input
      -- itself.  Do not sample, seed, shorten, yield to, or reacquire from any
      -- manual camera state in BC's Gold bridge.  Gen1 manual camera remains
      -- untouched below its existing `if not backends.__gold` gate.
      gold.stickWas=false
      gold.manualWas=false
      gold.resume=1
      gold.lastManual=nil

      local phase=ctx and ctx.screen and ctx.screen.phase or nil
      local okBC,bcCam=true,nil
      if ctx and ctx.arena then
        -- Evaluate BC every staged battle frame. This is required before the
        -- command menu because BC Hero begins at the send-out/presentation seam;
        -- Test 4's menu-only call could never set rigSeen early enough for Intro.
        okBC,bcCam=pcall(gold.BattleCam.rig,ctx.arena,ctx.groundY,false)
        if not okBC then gold.error=tostring(bcCam); bcCam=nil end
      end

      -- Phase-scoped ownership, now through the real BC modules. Manual human
      -- takeover above still wins immediately. Opening/pending send-outs remain
      -- provider-owned until BC Hero starts; attacks/faints are owned only when
      -- their corresponding saved BC options have actually armed the modules.
      local externalPassive=(selectedPreset()=="external")
      local bcOwns=(state.battleOpening.active and true) or (state.intro.active and true)
          or state.attack.active or state.faint.active or (phase=="menu" and not externalPassive)
      if bcOwns and type(bcCam)=="table" and type(bcCam.eye)=="table" then
        if gold.manualWas then gold.manualWas=false; gold.resume=0 end
        if gold.resume<1 and gold.lastManual then
          gold.resume=clamp(gold.resume+(tonumber(dt) or 1/60)/0.38,0,1)
          bcCam=blend(gold.lastManual,bcCam,gold.resume)
        else gold.resume=1; gold.lastManual=nil end
        gold.bcFrames=gold.bcFrames+1
        gold.lastVisible=copy(bcCam)
        OW.__bcRandy2DWorldCardCamera=copy(bcCam)
        local a=ctx.arena
        local mx=(type(a.mid)=="table" and tonumber(a.mid[1])) or cx
        local mz=(type(a.mid)=="table" and tonumber(a.mid[2])) or cz
        return bcCam,mx or cx,mz or cz
      end

      if providerCam then
        gold.lastVisible=copy(providerCam)
        OW.__bcRandy2DWorldCardCamera=copy(providerCam)
      end
      return providerCam,cx,cz
    end

    -- TEMPORARY ACTOR MARKERS. Randy's current Gold path deliberately skips
    -- the Gen-1 pic-texture billboard build, and Android cannot yet import the
    -- Stadium ROM in the user's tested stack. These screen-facing cards are
    -- development landmarks only: they prove where BC thinks player/enemy are
    -- while framing is calibrated. They are removed once a real actor source is
    -- available and never become core BC presentation.
    if false and type(originalRender)=="function" and type(V3.project)=="function" then
      VS.render=function(...)
        local out=originalRender(...)
        if not (out and gold.isGold()) then return out end
        local okCtx,ctx=pcall(OW.cameraContext)
        if not (okCtx and ctx and type(ctx.arena)=="table") then return out end
        local G=love and love.graphics
        if not G then return out end
        local previous=G.getCanvas()
        local ok=pcall(function()
          G.setCanvas(out); G.push("all"); G.origin(); G.setShader(); G.setDepthMode(); G.setBlendMode("alpha")
          local gy=tonumber(ctx.groundY) or 0
          local function marker(side,cell,r,g,b,label)
            if type(cell)~="table" then return end
            local x,z=tonumber(cell[1]),tonumber(cell[2]); if not (x and z) then return end
            local gx,gy2=V3.project(x,gy+0.5,z)
            local hx,hy,sc=V3.project(x,gy+18,z)
            if not (gx and gy2 and hx and hy) then return end
            local h=math.max(18,math.abs(gy2-hy)); local w=math.max(12,math.min(34,18*(tonumber(sc) or 1)))
            local left=hx-w*0.5; local top=math.min(hy,gy2)
            G.setColor(r,g,b,0.22); G.rectangle("fill",left,top,w,h,4,4)
            G.setColor(r,g,b,0.95); G.setLineWidth(2); G.rectangle("line",left,top,w,h,4,4)
            G.line(hx,top-6,hx,top+h+6); G.line(hx-6,(top+top+h)*0.5,hx+6,(top+top+h)*0.5)
            G.setColor(0,0,0,0.72); G.circle("fill",hx,top-10,9)
            G.setColor(1,1,1,1); G.print(label,hx-4,top-16)
          end
          marker("player",ctx.arena.player,0.20,0.90,1.00,"P")
          marker("enemy",ctx.arena.enemy,1.00,0.35,0.38,"E")
          G.pop()
        end)
        if not ok then pcall(G.pop) end
        if previous then pcall(G.setCanvas,previous) else pcall(G.setCanvas) end
        if ok then gold.markerFrames=gold.markerFrames+1 end
        return out
      end
    end

    mod.exports.goldCompatProbe=function()
      return {mode="gold-current-host-v1.0.5",provider=(gold.providerKind=="stadium2_importer") and "STADIUM2_IMPORTER" or "STADIUM2_OVERWORLD_MODELS",providerVersion=gold.provider.version,
        frames=gold.frames,bcFrames=gold.bcFrames,manualFrames=gold.manualFrames,markerFrames=gold.markerFrames,
        preset=mod.options:get("preset"),error=gold.error}
    end
    mod.log:warn("[BC GOLD] current-host bridge + explicit battle-boundary provider/bridge teardown active")
  end)(backends.__gold)
end


-- Stadium2 Importer Gen2 lightweight Camera.frame bridge --------------------
-- Test3 called the entire Gold provider director from inside Camera.frame().
-- That was the wrong seam for this renderer: Camera.frame() is already inside
-- the importer's Stadium scene render.  Here the render bridge does only the
-- minimum required work: sample the provider frame once, feed that as BC's
-- baseline, ask the already-installed BC BattleCam for the authored pose, and
-- substitute matrices only when a BC phase actually owns the shot.  Gold event
-- normalization continues on BC's normal fixed-step path above.
if backends.__gold and backends.__gold.providerKind=="stadium2_importer" then
(function(gold)
  local Camera=gold.Camera
  local originalFrame=gold.originalCameraFrame
  if not (Camera and type(originalFrame)=="function") then return end
  if Camera.__bcGoldImporterLightFrameWrapped then return end

  local LOVE_CANVAS_Y={1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1}
  local function matMul(a,b)
    local o={}
    for r=0,3 do for c=0,3 do
      local v=0
      for k=0,3 do v=v+a[r*4+k+1]*b[k*4+c+1] end
      o[r*4+c+1]=v
    end end
    return o
  end
  local function perspective(fovy,aspect,near,far)
    local f=1/math.tan(fovy*.5)
    return {f/aspect,0,0,0, 0,f,0,0,
      0,0,(far+near)/(near-far),(2*far*near)/(near-far), 0,0,-1,0}
  end
  local function lookAt(ex,ey,ez,tx,ty,tz)
    local fx,fy,fz=tx-ex,ty-ey,tz-ez
    local fl=math.sqrt(fx*fx+fy*fy+fz*fz); if fl==0 then fl=1 end
    fx,fy,fz=fx/fl,fy/fl,fz/fl
    local sx,sy,sz=fy*0-fz*1,fz*0-fx*0,fx*1-fy*0
    local sl=math.sqrt(sx*sx+sy*sy+sz*sz); if sl==0 then sx,sy,sz,sl=1,0,0,1 end
    sx,sy,sz=sx/sl,sy/sl,sz/sl
    local ux,uy,uz=sy*fz-sz*fy,sz*fx-sx*fz,sx*fy-sy*fx
    return {sx,sy,sz,-(sx*ex+sy*ey+sz*ez),
      ux,uy,uz,-(ux*ex+uy*ey+uz*ez),
      -fx,-fy,-fz,fx*ex+fy*ey+fz*ez, 0,0,0,1}
  end
  local function fovFromRaw(raw)
    local p=type(raw)=="table" and raw.projection or nil
    local f=p and math.abs(tonumber(p[6]) or 0) or 0
    return (f>1e-5) and 2*math.atan(1/f) or math.rad(55)
  end
  local function simple(raw)
    if type(raw)~="table" or type(raw.eye)~="table" or type(raw.focus)~="table" then return nil end
    return {eye={raw.eye[1],raw.eye[2],raw.eye[3]},
      focus={raw.focus[1],raw.focus[2],raw.focus[3]},
      up={0,1,0},fov=fovFromRaw(raw),curve=0}
  end
  local function rendererFrame(cam,raw,width,height)
    width=math.max(1,tonumber(width) or 1)
    height=math.max(1,tonumber(height) or 1)
    local eye,focus=cam.eye,cam.focus
    local view=lookAt(eye[1],eye[2],eye[3],focus[1],focus[2],focus[3])
    local projection=matMul(LOVE_CANVAS_Y,perspective(tonumber(cam.fov) or math.rad(55),
      width/height,.1,1000))
    return {view=view,projection=projection,vp=matMul(projection,view),
      eye={eye[1],eye[2],eye[3]},focus={focus[1],focus[2],focus[3]},
      letterbox=raw and raw.letterbox or nil}
  end

  -- Stadium2 Importer owns Gold right-stick input. Its Camera state keeps the
  -- provider's smoothed orbit/pitch/zoom even while BC substitutes an authored
  -- passive frame.  Test6 therefore polled the stick correctly but hid its
  -- visible result whenever a BC passive preset owned the menu camera.
  --
  -- Apply ONLY that provider-owned manual delta on top of BC passive/menu shots.
  -- Intro/Attack/Faint remain authored phase cameras, External already returns
  -- the provider frame untouched, and Randy never enters this importer-specific
  -- bridge.  No RBY grab/soft-return subsystem is enabled on Gold.
  local function providerManualOnPassive(cam)
    if type(cam)~="table" or type(cam.eye)~="table" or type(cam.focus)~="table" then return cam end
    if type(Camera.state)~="function" then return cam end
    local ok,st=pcall(Camera.state)
    if not (ok and type(st)=="table") then return cam end
    local orbit=tonumber(st.orbit) or 0
    local pitch=tonumber(st.pitch) or 0
    local zoom=tonumber(st.zoom) or 1
    if math.abs(orbit)<1e-5 and math.abs(pitch)<1e-5 and math.abs(zoom-1)<1e-5 then return cam end

    local focus=cam.focus
    local dx=(tonumber(cam.eye[1]) or 0)-(tonumber(focus[1]) or 0)
    local dy=(tonumber(cam.eye[2]) or 0)-(tonumber(focus[2]) or 0)
    local dz=(tonumber(cam.eye[3]) or 0)-(tonumber(focus[3]) or 0)
    local flat=math.sqrt(dx*dx+dz*dz)
    local radius=math.sqrt(flat*flat+dy*dy)
    if radius<1e-4 then return cam end

    local rig=type(Camera.RIG)=="table" and Camera.RIG or {}
    local side=tonumber(rig.side) or 41.98
    local back=tonumber(rig.back) or 41.16
    local orbitRange=math.max(0,math.pi/2-math.atan2(side,back))
    local yaw=math.atan2(dx,dz)-orbit*orbitRange
    local elev=math.atan2(dy,math.max(1e-4,flat))
      + pitch*(tonumber(Camera.PITCH_RANGE) or math.rad(45))
    elev=math.max(math.rad(-80),math.min(math.rad(85),elev))
    local nextFlat=radius*math.cos(elev)

    local out={
      eye={focus[1]+math.sin(yaw)*nextFlat,
           focus[2]+radius*math.sin(elev),
           focus[3]+math.cos(yaw)*nextFlat},
      focus={focus[1],focus[2],focus[3]},
      up={0,1,0},
      fov=tonumber(cam.fov) or math.rad(55),
      curve=tonumber(cam.curve) or 0,
    }
    -- Preserve the provider's native zoom state as a field-of-view multiplier.
    -- Positive Stadium2 zoom notches pull out; negative ones move in.
    if zoom>0 then
      out.fov=2*math.atan(math.tan(out.fov*.5)*zoom)
      out.fov=math.max(math.rad(18),math.min(math.rad(110),out.fov))
    end
    return state.floorProtectCamera(out,0)
  end

  Camera.frame=function(width,height)
    gold.frameWidth,gold.frameHeight=width,height
    local raw=originalFrame(width,height)

    -- Scene.new()/release() is already captured above, and drawWidescreen /
    -- drawPic keep scene.screen pointed at the exact live Gold BattleState.
    -- This avoids battleStatus(), whose cache validation is far too expensive
    -- to poll from a 60 Hz camera/render seam.
    if not gold.battleLive then return raw end
    local scene=gold.scene
    local screen=type(scene)=="table" and scene.screen or nil
    if type(screen)~="table" then return raw end

    -- The importer owns a valid live 3D battle even during opening frames where
    -- BC deliberately yields the camera.  Keep the shared backend watchdog
    -- alive without evaluating an authored rig: otherwise the generic 0.75 s
    -- no-rig timeout calls resetBattle(), erasing the initial enemy/player Intro
    -- queues before their visible send-out seams arrive.  This is only an
    -- ownership heartbeat; it performs no camera solve or provider query.
    state.rigSeen=true
    state.noRig=0
    state.backendId=gold.backend and gold.backend.id or state.backendId

    local phase=screen.phase
    local externalPassive=(selectedPreset()=="external")
    local bcOwns=(state.battleOpening.active and true) or (state.intro.active and true)
        or state.attack.active or state.faint.active or (phase=="menu" and not externalPassive)

    -- Provider-owned phases are a true fast pass-through.  In particular,
    -- External and Gold resolving/menu gaps do not pay for BC's authored rig,
    -- APB or safety stack merely to return the provider camera unchanged.
    if not bcOwns then
      gold.lastVisible=simple(raw)
      return raw
    end

    -- The importer's right-stick/drift camera is the live provider baseline.
    -- Evaluate BC only when BC actually owns this visible phase.
    gold.base=simple(raw)
    local okBC,bcCam=pcall(gold.BattleCam.rig,gold.arena,0,false)
    if not okBC then
      gold.error=tostring(bcCam)
      return raw
    end

    if not (type(bcCam)=="table"
        and type(bcCam.eye)=="table" and type(bcCam.focus)=="table") then
      gold.lastVisible=simple(raw)
      return raw
    end

    -- On Gold passive/menu shots, preserve Stadium2 Importer's own right-stick
    -- orbit/pitch/zoom semantics above the authored BC composition. BC-owned
    -- Intro/Attack/Faint remain phase-authoritative and are intentionally not
    -- steerable here; External has already passed through above.
    if phase=="menu" and not externalPassive
        and not state.battleOpening.active
        and not state.intro.active and not state.attack.active and not state.faint.active then
      bcCam=providerManualOnPassive(bcCam)
    end

    gold.frames=gold.frames+1
    gold.bcFrames=gold.bcFrames+1
    gold.lastVisible={eye={bcCam.eye[1],bcCam.eye[2],bcCam.eye[3]},
      focus={bcCam.focus[1],bcCam.focus[2],bcCam.focus[3]},
      up={0,1,0},fov=tonumber(bcCam.fov) or math.rad(55),
      curve=tonumber(bcCam.curve) or 0}
    return rendererFrame(bcCam,raw,width,height)
  end
  Camera.__bcGoldImporterLightFrameWrapped=true
  mod.log:warn("[BC GOLD] Stadium2 Importer lightweight live Camera.frame bridge active")
end)(backends.__gold)
end

-- Gold / Stadium2 presentation-bounds sampler ------------------------------
-- Randy's current Stadium2 actor stack skins the live model before drawing it
-- and exposes StadiumRig:posedBounds() as a public read-only query. BC samples
-- that already-built pose after build(); it never seeks animation, rebuilds a
-- second actor, steers the camera or touches the provider's right-stick path.
--
-- Vertical semantics use a stable mean of ordinary full-scale idle presentation
-- rather than raw frame values, so animated hover/bob motion can describe the
-- actor without making the camera breathe. Horizontal breadth retains a
-- conservative maximum. Entrance/attack/faint/send-out growth are excluded
-- from the stable idle record.
if backends.__gold then
(function(gold)
  local V=gold and gold.V
  if type(V)~="table" or type(V.require)~="function" then return end
  local function req(name)
    local ok,v=pcall(V.require,name)
    return (ok and type(v)=="table") and v or nil
  end
  local StadiumMon=req("StadiumMon")
  local Stadium=req("Stadium")
  if not (StadiumMon and Stadium and type(StadiumMon.build)=="function") then
    mod.log:warn("[APB STADIUM2] current StadiumMon/Stadium modules unavailable; canonical Gold camera fallback retained")
    return
  end

  local sampler={side={player={},enemy={}},errors=0}

  local function finite(v)
    v=tonumber(v)
    return v and v==v and v>-1e10 and v<1e10 and v or nil
  end
  local function validSide(side)
    return side=="player" or side=="enemy"
  end
  local function sameLivePresentation(mon,side)
    if not (gold.battleLive and validSide(side) and mon and mon.visible) then return false end
    if type(Stadium.showing)=="function" then
      local ok,showing=pcall(Stadium.showing,side)
      if not ok or showing~=true then return false end
    end
    if type(Stadium.animOf)=="function" then
      local ok,stateName=pcall(Stadium.animOf,side)
      if ok and stateName~=nil and tostring(stateName)~=tostring(mon.state) then return false end
    end
    if type(Stadium.scaleOf)=="function" then
      local ok,scale=pcall(Stadium.scaleOf,side)
      if ok and tonumber(scale) and math.abs((tonumber(scale) or 0)-(tonumber(mon.scale) or 0))>1e-5 then
        return false
      end
    end
    return true
  end

  local function resetIdle(d,mon)
    d.species=tonumber(mon and mon.species) or (mon and mon.species) or nil
    d.mon=mon
    d.idleSamples=0
    d.idleBottomSum=0; d.idleTopSum=0; d.idleHSum=0
    d.idleSpanXSum=0; d.idleSpanZSum=0; d.idleDiagMax=nil
  end

  local function capture(mon)
    local side=mon and mon.side
    if not sameLivePresentation(mon,side) then return end
    local rig,model=mon.rig,mon.model
    if not (rig and model and type(rig.posedBounds)=="function") then return end
    local ok,loX,loY,loZ,hiX,hiY,hiZ=pcall(rig.posedBounds,rig)
    loX,loY,loZ=finite(loX),finite(loY),finite(loZ)
    hiX,hiY,hiZ=finite(hiX),finite(hiY),finite(hiZ)
    if not (ok and loX and loY and loZ and hiX and hiY and hiZ
        and hiX>=loX and hiY>=loY and hiZ>=loZ) then return end

    local modelH=math.max(1e-6,tonumber(model.height) or 0)
    if not (modelH>1e-6) then return end
    local root=tonumber(model.rootScale) or 1
    if root<=0 then root=1 end
    local worldH=nil
    if type(mon.worldHeight)=="function" then
      local okH,h=pcall(mon.worldHeight,mon)
      if okH then worldH=tonumber(h) end
    end
    if not (worldH and worldH>1e-6) then return end

    local floor=tonumber(model.floor) or 0
    local hoverCap=tonumber(StadiumMon.HOVER_CAP) or 0.5
    local hover=math.min(math.max(floor,0),hoverCap*math.max(modelH,0))
    local lift=(floor-hover)/root
    local k=root*worldH/modelH

    local bottom=(loY-lift)*k
    local top=(hiY-lift)*k
    local height=top-bottom
    local spanX=(hiX-loX)*k
    local spanZ=(hiZ-loZ)*k
    local diag=math.sqrt(spanX*spanX+spanZ*spanZ)
    if height<=1e-3 then return end

    local d=sampler.side[side]
    if d.mon~=mon or tostring(d.species)~=tostring(mon.species) then resetIdle(d,mon) end
    d.full={bottom=bottom,top=top,height=height,spanX=spanX,spanZ=spanZ,diag=diag}

    local drawScale=tonumber(mon.scale) or 1
    if tostring(mon.state)=="idle" and math.abs(drawScale-1)<0.02 then
      d.idleSamples=(d.idleSamples or 0)+1
      d.idleBottomSum=(d.idleBottomSum or 0)+bottom
      d.idleTopSum=(d.idleTopSum or 0)+top
      d.idleHSum=(d.idleHSum or 0)+height
      d.idleSpanXSum=(d.idleSpanXSum or 0)+spanX
      d.idleSpanZSum=(d.idleSpanZSum or 0)+spanZ
      d.idleDiagMax=math.max(d.idleDiagMax or diag,diag)
    end
  end

  -- Preserve the provider's true parent method if a diagnostic/APB build was
  -- hot-loaded earlier in the same process; never stack BC wrappers.
  StadiumMon._bcApbOriginalBuild=StadiumMon._bcApbOriginalBuild
      or StadiumMon._bcApbReadonlyOriginalBuild or StadiumMon.build
  local originalBuild=StadiumMon._bcApbOriginalBuild
  StadiumMon.build=function(self,...)
    local result=originalBuild(self,...)
    if result==true then
      local ok,err=pcall(capture,self)
      if not ok then
        sampler.errors=sampler.errors+1
        if sampler.errors<=3 then mod.log:warn("[APB STADIUM2] posed-bounds sample failed safely: %s",tostring(err)) end
      end
    end
    return result
  end

  sampler.drawSide=function(side,pull)
    if not validSide(side) then return false end
    local d=sampler.side[side]
    local mon=d and d.mon or nil
    if not (mon and sameLivePresentation(mon,side) and mon.rig and mon.model_matrix
        and type(mon.rig.draw)=="function") then return false end
    local ok=pcall(mon.rig.draw,mon.rig,mon.model_matrix,tonumber(pull) or 0)
    return ok and true or false
  end

  sampler.resolve=function(side)
    if not validSide(side) then return nil end
    local d=sampler.side[side]
    local mon=d and d.mon or nil
    if not (d and mon and sameLivePresentation(mon,side) and type(d.full)=="table") then return nil end

    local n=tonumber(d.idleSamples) or 0
    local bottom,top,height,spanX,spanZ,breadth,confidence
    if n>=12 then
      bottom=(tonumber(d.idleBottomSum) or 0)/n
      top=(tonumber(d.idleTopSum) or 0)/n
      height=(tonumber(d.idleHSum) or (top-bottom)*n)/n
      spanX=(tonumber(d.idleSpanXSum) or 0)/n
      spanZ=(tonumber(d.idleSpanZSum) or 0)/n
      breadth=tonumber(d.idleDiagMax) or math.sqrt(spanX*spanX+spanZ*spanZ)
      confidence=(n>=30) and "high" or "medium"
    else
      bottom=tonumber(d.full.bottom); top=tonumber(d.full.top); height=tonumber(d.full.height)
      spanX=tonumber(d.full.spanX); spanZ=tonumber(d.full.spanZ); breadth=tonumber(d.full.diag)
      confidence="medium"
    end
    if not (bottom and top and height and height>1e-3) then return nil end
    local elevation=math.max(0,bottom)
    local elevationNorm=elevation/math.max(1e-3,height)
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end
    return {
      visualBottomY=bottom, visualTopY=top, centerY=(bottom+top)*0.5, height=height,
      breadth=breadth, spanX=spanX, spanZ=spanZ,
      breadthHeightRatio=(breadth and breadth/math.max(1e-3,height)) or nil,
      elevation=elevation, elevationNorm=elevationNorm,
      source="RANDY_STADIUM2_IDLE_POSED_V1", confidence=confidence,
    }
  end

  gold.apbStadium2Sampler=sampler
  mod.log:info("[APB STADIUM2] live posed-bounds presentation adapter available")
end)(backends.__gold)
end


-- Actor Presentation Bounds — semantic registry --------------------------------

-- Gen1/RBY only.  Uses StadiumBattleFX's public model API v1 and exported live
-- model provider.  It does NOT modify, seek, draw, replace or steer the live
-- actors.  Isolated API actors are acquired only to read geometry, then cached
-- per species and released on change/end.
(function()
  -- The APB semantic registry is generation-neutral.  Renderer-specific
  -- adapters remain isolated: SBFX/sprite on Gen1, Randy Stadium2 on Gold.

  local A=state.apb
  if not A then return end

  -- BC-owned semantic adapter registry ------------------------------------
  -- Camera modules consume only:
  --   A.actorPresentationBounds(side,battle)
  -- and generic framing helpers below.
  --
  -- Renderer/host specifics are private adapters. A future Crystal/static
  -- sprite adapter and a future Stadium2/Gold adapter can register here
  -- without changing Stadium/DW3/Hero/Attack camera language.
  A.adapters={}
  A.adapterVersion=1

  A.registerAdapter=function(id,priority,resolve)
    if type(id)~="string" or type(resolve)~="function" then return false end
    A.adapters[#A.adapters+1]={
      id=id,
      priority=tonumber(priority) or 0,
      resolve=resolve,
    }
    table.sort(A.adapters,function(a,b)
      if a.priority==b.priority then return a.id<b.id end
      return a.priority>b.priority
    end)
    return true
  end

  A.actorPresentationBounds=function(side,battle)
    if side~="player" and side~="enemy" then return nil end
    if type(battle)~="table" then return nil end
    for _,adapter in ipairs(A.adapters) do
      local ok,bounds=pcall(adapter.resolve,side,battle)
      if ok and type(bounds)=="table"
          and tonumber(bounds.height) and bounds.height>1e-3 then
        bounds.adapter=adapter.id
        return bounds
      end
    end
    return nil
  end

  -- Backwards-compatible internal name for the already-proven camera
  -- consumers. This is an alias to BC's semantic contract, not a renderer API.
  A.resolve=A.actorPresentationBounds

  -- Private Gen1 SBFX posed-bounds adapter --------------------------------
  -- We still need private posed geometry because SBFX 2.1.5's public models
  -- API does not expose presentation bounds. The private seam is quarantined
  -- entirely inside this adapter. It is guarded at every step and failure
  -- returns nil -> canonical BC framing.
  --
  -- Unlike the research branch:
  --   * no diagnostic HUD
  --   * no render.hud hook
  --   * no live actor mutation
  --   * no isolated actor retained across frames/battles
  --   * successful bounds cached by model source+dex+variant
  local sbfxCache={}
  local sbfxMod=nil
  local sbfxModels=nil
  local sbfxSources=nil

  local function refreshSbfxApi()
    local found=mod.find("STADIUM_BATTLE_FX")
    if found~=sbfxMod then
      sbfxMod=found
      local ex=found and found.exports or nil
      local models=ex and ex.models or nil
      if type(models)=="table" and tonumber(models.version)==1 then
        sbfxModels=models
        sbfxSources=ex and ex.modelSources or nil
      else
        sbfxModels=nil
        sbfxSources=nil
      end
    end
    return sbfxModels
  end

  local function selectedSourceId()
    if type(sbfxSources)=="table" and type(sbfxSources.selectedId)=="function" then
      local ok,v=pcall(sbfxSources.selectedId)
      if ok and v~=nil then return tostring(v) end
    end
    return "selected"
  end

  local function speciesDexVariant(battle,side)
    local battler=battle and battle[side]
    local mon=battler and battler.mon
    local species=mon and mon.species
    local def=species and battle and battle.data and battle.data.pokemon
        and battle.data.pokemon[species] or nil
    local dex=def and tonumber(def.dex) or nil
    local variant=(mon and mon.shiny==true) and "shiny" or "normal"
    return dex,variant
  end

  local function stats(values)
    if #values==0 then return nil,nil,nil end
    local lo,hi,sum=values[1],values[1],0
    for _,v in ipairs(values) do
      if v<lo then lo=v end
      if v>hi then hi=v end
      sum=sum+v
    end
    return lo,hi,sum/#values
  end

  local function worldXYZ(m,x,y,z)
    x,y,z=tonumber(x) or 0,tonumber(y) or 0,tonumber(z) or 0
    return
      (tonumber(m[1]) or 0)*x+(tonumber(m[2]) or 0)*y+(tonumber(m[3]) or 0)*z+(tonumber(m[4]) or 0),
      (tonumber(m[5]) or 0)*x+(tonumber(m[6]) or 0)*y+(tonumber(m[7]) or 0)*z+(tonumber(m[8]) or 0),
      (tonumber(m[9]) or 0)*x+(tonumber(m[10]) or 0)*y+(tonumber(m[11]) or 0)*z+(tonumber(m[12]) or 0)
  end

  local function measureIsolatedActor(actor)
    local mon=actor and rawget(actor,"_mon") or nil
    local rig=type(mon)=="table" and rawget(mon,"rig") or nil
    local model=type(mon)=="table" and rawget(mon,"model") or nil
    if not (mon and rig and model and type(rig.parts)=="table"
        and type(mon.build)=="function" and type(mon.matrix)=="function") then
      return nil
    end

    local animIndex=mon.anim
    local rec=animIndex and model.anims and model.anims[animIndex] or nil
    local frames=rec and tonumber(rec.frames) or 1
    if not (frames and frames>0) then frames=1 end
    local samples=math.min(12,math.max(1,math.floor(frames)))

    local bottoms,tops,centroids,boxCenters={},{},{},{}
    local spansX,spansZ,breadths={},{},{}
    local oldTime,oldDt=mon.time,mon.dt

    local okMeasure,err=pcall(function()
      for s=1,samples do
        local f=(samples==1) and 0 or ((s-1)*(frames-1)/(samples-1))
        mon.time=f/30
        mon.dt=nil
        mon:build()
        local m=mon:matrix(0,0,0,0,1)
        if type(m)=="table" then
          local yLo,yHi,sumY,count=nil,nil,0,0
          local xLo,xHi,zLo,zHi,sumX,sumZ=nil,nil,nil,nil,0,0

          for _,part in ipairs(rig.parts or {}) do
            for _,row in ipairs(part.rows or {}) do
              local x,y,z=worldXYZ(m,row[1],row[2],row[3])
              if yLo==nil or y<yLo then yLo=y end
              if yHi==nil or y>yHi then yHi=y end
              if xLo==nil or x<xLo then xLo=x end
              if xHi==nil or x>xHi then xHi=x end
              if zLo==nil or z<zLo then zLo=z end
              if zHi==nil or z>zHi then zHi=z end
              sumX=sumX+x; sumY=sumY+y; sumZ=sumZ+z; count=count+1
            end
          end

          if yLo and yHi and xLo and xHi and zLo and zHi and count>0 then
            local cx,cz=sumX/count,sumZ/count
            local maxR=0
            for _,part in ipairs(rig.parts or {}) do
              for _,row in ipairs(part.rows or {}) do
                local x,_,z=worldXYZ(m,row[1],row[2],row[3])
                local dx,dz=x-cx,z-cz
                local rr=math.sqrt(dx*dx+dz*dz)
                if rr>maxR then maxR=rr end
              end
            end

            bottoms[#bottoms+1]=yLo
            tops[#tops+1]=yHi
            centroids[#centroids+1]=sumY/count
            boxCenters[#boxCenters+1]=(yLo+yHi)*0.5
            spansX[#spansX+1]=xHi-xLo
            spansZ[#spansZ+1]=zHi-zLo
            breadths[#breadths+1]=maxR*2
          end
        end
      end
    end)

    mon.time,mon.dt=oldTime,oldDt
    pcall(mon.build,mon)

    if not okMeasure then
      mod.log:warn("[APB] SBFX posed-bounds measurement failed safely: %s",tostring(err))
      return nil
    end

    local _,_,bottomMean=stats(bottoms)
    local _,_,topMean=stats(tops)
    local _,_,centerMean=stats(boxCenters)
    local _,_,spanXMean=stats(spansX)
    local _,_,spanZMean=stats(spansZ)
    local _,_,breadthMean=stats(breadths)

    if not (bottomMean and topMean and centerMean and #bottoms>=6) then
      return nil
    end

    local height=topMean-bottomMean
    if not (height and height>1e-3) then return nil end

    local elevation=math.max(0,bottomMean)
    local elevationNorm=elevation/height
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end

    return {
      visualBottomY=bottomMean,
      visualTopY=topMean,
      centerY=centerMean,
      height=height,
      breadth=breadthMean,
      spanX=spanXMean,
      spanZ=spanZMean,
      breadthHeightRatio=(breadthMean and breadthMean/height) or nil,
      elevation=elevation,
      elevationNorm=elevationNorm,
      source="SBFX_POSED_BOUNDS_V1",
      confidence=(#bottoms>=10) and "high" or "medium",
    }
  end

  local function resolveSbfx(side,battle)
    local models=refreshSbfxApi()
    if not models then return nil end

    local dex,variant=speciesDexVariant(battle,side)
    if not dex then return nil end

    local sourceId=selectedSourceId()
    local key=sourceId..":"..tostring(dex)..":"..tostring(variant)
    local cached=sbfxCache[key]
    if cached then return cached end

    local source=models.SELECTED or "selected"
    local okAvail,available=pcall(models.available,source,dex)
    if not (okAvail and available) then return nil end

    local okAcquire,actor,acquireErr=pcall(models.acquire,source,dex,variant,{side=side})
    if not (okAcquire and actor) then
      if acquireErr then
        mod.log:warn("[APB] SBFX isolated actor acquire failed safely: %s",tostring(acquireErr))
      end
      return nil
    end

    local bounds=nil
    local okBounds,measureErr=pcall(function()
      bounds=measureIsolatedActor(actor)
    end)

    if type(actor.release)=="function" then
      pcall(actor.release,actor)
    end

    if not okBounds then
      mod.log:warn("[APB] SBFX adapter failed safely: %s",tostring(measureErr))
      return nil
    end
    if type(bounds)~="table" then return nil end

    sbfxCache[key]=bounds
    return bounds
  end

  if not backends.__gold then A.registerAdapter("sbfx_posed_v1",100,resolveSbfx) end

  -- Shared semantic framing ------------------------------------------------
  -- These rules are renderer-neutral and deliberately unchanged from the
  -- validated APB camera line.
  A.framingFromBounds=function(b,R,margin,anchorY)
    if type(b)~="table" or type(R)~="table" then return 0,nil,b,"none" end
    local height=tonumber(b.height) or 0
    if height<=1.0 then return 0,nil,b,"none" end

    local aspect=16/9
    if love and love.graphics and type(love.graphics.getDimensions)=="function" then
      local okDim,w,h=pcall(love.graphics.getDimensions)
      if okDim and tonumber(w) and tonumber(h) and h>0 then
        aspect=math.max(0.35,math.min(3.5,w/h))
      end
    end

    local elevation=math.max(0,tonumber(b.elevation) or 0)
    if elevation>=0.75 then
      local requiredSpan=height*(tonumber(margin) or 1.30)*aspect
      return math.min(12.0,elevation),
             requiredSpan/math.max(1e-3,R.frameH),
             b,"elevated"
    end

    local bottom=tonumber(b.visualBottomY) or 0
    local contactTol=math.max(0.75,math.min(1.10,height*0.035))
    local frameRatio=height/math.max(1e-3,tonumber(R.frameH) or 1)

    if math.abs(bottom)<=contactTol and frameRatio>=0.50 then
      local centre=tonumber(b.centerY)
      if centre==nil then centre=bottom+height*0.50 end
      local authoredAnchor=tonumber(anchorY) or 0
      local centreShift=math.max(0,math.min(12.0,centre-authoredAnchor))
      local requiredSpan=height*1.12*aspect
      return centreShift,
             requiredSpan/math.max(1e-3,R.frameH),
             b,"tall_grounded"
    end

    return 0,nil,b,"canonical"
  end

  A.subjectFraming=function(side,R,margin,anchorY)
    local b=A.actorPresentationBounds(side,state.battle)
    if type(b)~="table" then return 0,nil,nil,"none" end
    return A.framingFromBounds(b,R,margin,anchorY)
  end

  A.cinematicFramingFromBounds=function(b,R,margin,anchorY)
    local lift,_,bounds,class=A.framingFromBounds(b,R,margin,anchorY)
    if type(bounds)~="table" or class=="none" or class=="canonical" then
      return lift,nil,bounds,class
    end

    local aspect=16/9
    if love and love.graphics and type(love.graphics.getDimensions)=="function" then
      local okDim,w,h=pcall(love.graphics.getDimensions)
      if okDim and tonumber(w) and tonumber(h) and h>0 then
        aspect=math.max(0.35,math.min(3.5,w/h))
      end
    end
    local fitAspect=aspect
    if aspect>1.0 then fitAspect=1.0+(aspect-1.0)*0.35 end

    local height=tonumber(bounds.height) or 0
    local fitMargin=(class=="tall_grounded") and 1.12 or (tonumber(margin) or 1.30)
    local scale=(height*fitMargin*fitAspect)/math.max(1e-3,R.frameH)
    return lift,scale,bounds,class
  end

  A.subjectFramingCinematic=function(side,R,margin,anchorY)
    local b=A.actorPresentationBounds(side,state.battle)
    if type(b)~="table" then return 0,nil,nil,"none" end
    return A.cinematicFramingFromBounds(b,R,margin,anchorY)
  end

  A.isBroadPresentation=function(b,R)
    if type(b)~="table" or type(R)~="table" then return false,0,0 end
    local breadth=tonumber(b.breadth) or 0
    local ratio=tonumber(b.breadthHeightRatio) or 0
    local rel=breadth/math.max(1e-3,tonumber(R.frameH) or 1)
    return ratio>=2.30 and rel>=1.50,ratio,rel
  end

  mod.log:info("[APB] BC presentation-bounds semantic layer active")
end)()

-- Stadium2 Importer scene-neutral posed-bounds adapter ---------------------
-- Importer owns model geometry/animation; BC only translates its public API
-- v2 measurements into the renderer-neutral Actor Presentation Bounds record.
-- Primary-camera arbitration is deliberately gated to an Importer-owned live
-- backend. Secondary View may explicitly query the same sensor when it chooses
-- an Importer actor inside a Dramaless secondary world.
if state.apb and type(state.apb.registerAdapter)=="function" then
(function(A)
  local cache={}
  local providerToken=nil
  local provider=nil
  local exports=nil
  local models=nil

  local function refreshImporter()
    local found=mod.find("STADIUM2_IMPORTER")
    if found~=providerToken then
      providerToken=found
      provider=found
      exports=found and found.exports or nil
      models=exports and exports.models or nil
      cache={}
    end
    if not (type(models)=="table" and tonumber(models.apiVersion)>=2
        and type(models.newInstance)=="function") then
      return nil
    end
    return models
  end

  local function importerModelsEnabled()
    if exports and type(exports.modelsEnabled)=="function" then
      local ok,value=pcall(exports.modelsEnabled)
      if ok and value==false then return false end
    end
    return true
  end

  local function monForSide(battle,side)
    local battler=battle and battle[side] or nil
    local mon=battler and battler.mon or nil
    if type(mon)~="table" and type(battler)=="table" and battler.species then mon=battler end
    return type(mon)=="table" and mon or nil
  end

  local function speciesDexVariant(battle,side)
    local mon=monForSide(battle,side)
    if not mon then return nil,nil end
    local species=mon.species
    local dex=nil
    if type(species)=="number" then
      local n=math.floor(species)
      if n>=1 and n<=251 then dex=n end
    end
    if not dex and battle and battle.data and battle.data.pokemon and species~=nil then
      local def=battle.data.pokemon[species]
      local n=def and tonumber(def.dex or def.index) or nil
      if n then n=math.floor(n); if n>=1 and n<=251 then dex=n end end
    end
    if not dex then return nil,nil end

    local shiny=mon.shiny==true
    if mon.shiny==nil and type(mon.dvs)=="table" then
      local d=mon.dvs
      local atk=tonumber(d.attack)
      local shinyAtk=atk==2 or atk==3 or atk==6 or atk==7
          or atk==10 or atk==11 or atk==14 or atk==15
      shiny=(tonumber(d.defense)==10 and tonumber(d.speed)==10
          and tonumber(d.special)==10 and shinyAtk) and true or false
    end
    return dex,shiny and "shiny" or "normal"
  end

  local function mean(values)
    if #values==0 then return nil end
    local sum=0
    for _,v in ipairs(values) do sum=sum+v end
    return sum/#values
  end

  local function providerVersion()
    return tostring((exports and exports.version)
        or (provider and provider.version) or "?")
  end

  local function measure(side,battle)
    local api=refreshImporter()
    if not api or not importerModelsEnabled() then return nil end
    local dex,variant=speciesDexVariant(battle,side)
    if not dex then return nil end
    local key=providerVersion()..":"..tostring(dex)..":"..tostring(variant)
    local cached=cache[key]
    if type(cached)=="table" then return cached end

    local okNew,instance,err=pcall(api.newInstance,dex,variant,{
      textureFilter="nearest", anchorTravel=true,
    })
    if not (okNew and instance) then
      if err then mod.log:warn("[APB IMPORTER] isolated actor acquire failed safely: %s",tostring(err)) end
      return nil
    end

    local function release()
      if instance and type(instance.release)=="function" then pcall(instance.release,instance) end
      instance=nil
    end

    if type(instance.play)=="function" then pcall(instance.play,instance,"idle",true) end
    local metrics=nil
    if type(instance.metrics)=="function" then
      local okMetrics,value=pcall(instance.metrics,instance)
      if okMetrics and type(value)=="table" then metrics=value end
    end
    local modelHeight=metrics and tonumber(metrics.height) or nil
    if not (modelHeight and modelHeight>1e-4) then release(); return nil end

    -- This is the same physical model-height mapping already used by the
    -- accepted Rebase11 scene-neutral Importer draw bridge. Keeping the sensor
    -- in those presented world units lets existing APB consumers remain
    -- renderer-neutral and preserves provider ownership of raw model scale.
    local worldHeight=math.max(5,math.min(18,14*math.sqrt(modelHeight/52.25)))
    local k=worldHeight/modelHeight
    local floor=tonumber(metrics.floor) or 0
    local hover=math.min(math.max(floor,0),modelHeight*0.5)
    local presentedOffset=floor-hover
    local bottoms,tops,spanXs,spanZs,breadths={},{},{},{},{}

    -- Sample an isolated looping idle actor just as historical SBFX/Randy APB
    -- samples stable presentation rather than entrance/attack/faint growth.
    -- Twelve samples keep the old APB evidence cadence without mutating the
    -- provider's live actor or advancing its animation twice.
    for sample=1,12 do
      if type(instance.bounds)=="function" then
        local okBounds,b=pcall(instance.bounds,instance)
        if okBounds and type(b)=="table" then
          local minY,maxY=tonumber(b.minY),tonumber(b.maxY)
          local minX,maxX=tonumber(b.minX),tonumber(b.maxX)
          local minZ,maxZ=tonumber(b.minZ),tonumber(b.maxZ)
          if minY and maxY and maxY>minY then
            -- Apply the same Y transform as Importer's classic battle scene:
            -- scale the posed geometry after subtracting only floor-hover.
            -- The residual hover is the provider-authored elevation APB needs.
            local bottom=(minY-presentedOffset)*k
            local top=(maxY-presentedOffset)*k
            bottoms[#bottoms+1]=bottom
            tops[#tops+1]=top
            if minX and maxX then spanXs[#spanXs+1]=math.max(0,(maxX-minX)*k) end
            if minZ and maxZ then spanZs[#spanZs+1]=math.max(0,(maxZ-minZ)*k) end
            if minX and maxX and minZ and maxZ then
              local sx,sz=(maxX-minX)*k,(maxZ-minZ)*k
              breadths[#breadths+1]=math.sqrt(sx*sx+sz*sz)
            end
          end
        end
      end
      if sample<12 and type(instance.update)=="function" then
        pcall(instance.update,instance,0.10)
      end
    end
    release()

    if #bottoms<6 then return nil end
    local bottomMean,topMean=mean(bottoms),mean(tops)
    local spanXMean,spanZMean=mean(spanXs),mean(spanZs)
    local breadth=nil
    for _,v in ipairs(breadths) do if not breadth or v>breadth then breadth=v end end
    if not (bottomMean and topMean) then return nil end
    local height=topMean-bottomMean
    if not (height and height>1e-3) then return nil end
    local centerY=(bottomMean+topMean)*0.5
    local elevation=math.max(0,bottomMean)
    local elevationNorm=elevation/height
    -- Preserve the accepted APB grounding threshold exactly. elevationNorm is
    -- intentionally the measured ratio even when tiny absolute lift is
    -- suppressed, matching the existing SBFX/Randy record convention.
    if elevation<0.75 or elevationNorm<0.05 then elevation=0 end

    local out={
      visualBottomY=bottomMean,
      visualTopY=topMean,
      centerY=centerY,
      height=height,
      breadth=breadth,
      spanX=spanXMean,
      spanZ=spanZMean,
      breadthHeightRatio=(breadth and breadth/height) or nil,
      elevation=elevation,
      elevationNorm=elevationNorm,
      source="STADIUM2_IMPORTER_IDLE_POSED_V1",
      confidence=(#bottoms>=10) and "high" or "medium",
    }
    cache[key]=out
    return out
  end

  local function primaryResolve(side,battle)
    local backend=A.backend
    if not (type(backend)=="table" and backend.stadium2Importer==true) then return nil end
    return measure(side,battle)
  end

  -- Priority 110 is intentional: when Importer owns the primary presentation,
  -- this adapter must answer before a merely-installed legacy SBFX provider.
  -- When Importer does not own the primary backend, the resolver returns nil
  -- and existing SBFX/Randy/sprite arbitration is untouched.
  A.registerAdapter("stadium2_importer_posed_v1",110,primaryResolve)
  A.stadium2ImporterPresentationBounds=function(side,battle)
    return measure(side,battle)
  end
  mod.log:info("[APB] Stadium2 Importer posed-bounds adapter registered")
end)(state.apb)
end

-- Gold / Randy Stadium2 private evidence adapter ---------------------------
-- The camera language above remains generation-neutral. This adapter merely
-- translates Randy's already-built live posed presentation into that contract.
if backends.__gold and state.apb and type(state.apb.registerAdapter)=="function" then
(function(gold,A)
  local sampler=gold and gold.apbStadium2Sampler
  if sampler and type(sampler.resolve)=="function" then
    A.registerAdapter("randy_stadium2_posed_v1",100,function(side,battle)
      return sampler.resolve(side,battle)
    end)
    mod.log:info("[APB] Randy Stadium2 posed-bounds adapter registered")
  end
end)(backends.__gold,state.apb)
end

-- Gen1/RBY sprite presentation-bounds adapter -----------------------------
-- Fixed-card Gen1/Gen2-era battle artwork is already authored to fit its
-- presentation box, so the expected result for ordinary sprites is usually a
-- non-regression: APB understands the card and leaves an already-good shot
-- alone. The same adapter contract remains useful for richer/animated sprite
-- presentations without creating renderer-specific camera choreography.
if not backends.__gold then
(function()
  local function imageDims(img)
    if img==nil then return nil,nil end
    local okFn,fn=pcall(function() return img.getDimensions end)
    if not okFn or type(fn)~="function" then return nil,nil end
    local ok,w,h=pcall(fn,img)
    if ok and tonumber(w) and tonumber(h) then return tonumber(w),tonumber(h) end
    return nil,nil
  end

  local readbackCanvases={}

  local function imageDataForReadback(img,w,h)
    -- Prefer direct texture readback when exposed. Current Recomp builds may
    -- omit it, so fall back to a tiny off-screen readable Canvas. Results are
    -- cached per presented Image below, making this a one-time cost per image
    -- token rather than a per-camera-frame readback.
    local okFn,fn=pcall(function() return img.newImageData end)
    if okFn and type(fn)=="function" then
      local ok,id=pcall(fn,img)
      if ok and id then return id end
    end

    local okOld,oldFn=pcall(function() return img.getData end)
    if okOld and type(oldFn)=="function" then
      local ok,id=pcall(oldFn,img)
      if ok and id and type(id.getPixel)=="function" then return id end
    end

    local g=love and love.graphics
    if not (g and type(g.newCanvas)=="function" and type(g.draw)=="function") then return nil end
    local key=tostring(w).."x"..tostring(h)
    local canvas=readbackCanvases[key]
    if not canvas then
      local ok,c=pcall(g.newCanvas,w,h,{format="rgba8",readable=true})
      if not ok or not c then ok,c=pcall(g.newCanvas,w,h) end
      if not ok or not c then return nil end
      canvas=c; readbackCanvases[key]=canvas
    end

    local previous=(type(g.getCanvas)=="function") and g.getCanvas() or nil
    local pushed=false
    local okDraw=pcall(function()
      if type(g.push)=="function" then g.push("all"); pushed=true end
      g.setCanvas(canvas)
      if type(g.origin)=="function" then g.origin() end
      if type(g.setScissor)=="function" then g.setScissor() end
      if type(g.setShader)=="function" then g.setShader() end
      if type(g.setColor)=="function" then g.setColor(1,1,1,1) end
      g.clear(0,0,0,0)
      g.draw(img,0,0)
      if pushed then g.pop(); pushed=false end
      if previous then g.setCanvas(previous) else g.setCanvas() end
    end)
    if pushed and type(g.pop)=="function" then pcall(g.pop) end
    if not okDraw then
      if previous then pcall(g.setCanvas,previous) else pcall(g.setCanvas) end
      return nil
    end

    local okNew,newFn=pcall(function() return canvas.newImageData end)
    if okNew and type(newFn)=="function" then
      local ok,id=pcall(newFn,canvas)
      if ok and id then return id end
    end
    local okGet,getFn=pcall(function() return canvas.getImageData end)
    if okGet and type(getFn)=="function" then
      local ok,id=pcall(getFn,canvas)
      if ok and id then return id end
    end
    return nil
  end

  local function alphaBounds(img)
    local w,h=imageDims(img)
    if not (w and h and w>0 and h>0) then return nil end
    local id=imageDataForReadback(img,w,h)
    if not id then return nil end
    local ok,result=pcall(function()
      local iw,ih=id:getDimensions()
      local left,right,top,bottom=iw,-1,ih,-1
      for y=0,ih-1 do
        for x=0,iw-1 do
          local _,_,_,a=id:getPixel(x,y)
          if (tonumber(a) or 0)>0.01 then
            if x<left then left=x end; if x>right then right=x end
            if y<top then top=y end; if y>bottom then bottom=y end
          end
        end
      end
      if right<left or bottom<top then return nil end
      return {
        w=iw,h=ih,visW=right-left+1,visH=bottom-top+1,
        padT=top,padB=ih-1-bottom,
      }
    end)
    return ok and result or nil
  end

  local function presentedImage(battle,battler)
    if type(battler)~="table" then return nil end
    local shown=battler.sprite
    if type(battle)=="table" and type(battle.picImage)=="function" and shown then
      local ok,img=pcall(battle.picImage,battle,shown)
      if ok and img then shown=img end
    end
    return shown
  end

  local spriteAPB=state.apb
  local billboardModule=nil
  local billboardAttempted=false
  local measureCache=setmetatable({}, {__mode="k"})
  local envelopes={player={},enemy={}}

  local function battleBillboard()
    if billboardAttempted then return billboardModule end
    billboardAttempted=true
    for _,backend in ipairs(backends) do
      if not backend.gold and backend.V and type(backend.V.require)=="function" then
        local ok,bb=pcall(backend.V.require,"BattleBillboard")
        if ok and type(bb)=="table" and type(bb.sizeFor)=="function" then
          billboardModule=bb; break
        end
      end
    end
    return billboardModule
  end

  local function modelPresentationActive()
    for _,backend in ipairs(backends) do
      local stadium=backend and backend.Stadium
      if stadium and type(stadium.active)=="function" then
        local ok,active=pcall(stadium.active)
        if ok and active==true then return true end
      end
    end
    return false
  end

  local function measuredSpriteBounds(shown)
    if shown==nil then return nil end
    local cached=measureCache[shown]
    if cached~=nil then return cached or nil end
    local m=alphaBounds(shown)
    if not (type(m)=="table" and m.w and m.h and m.w>0 and m.h>0) then
      measureCache[shown]=false; return nil
    end
    local pw,ph=imageDims(shown)
    local bb=battleBillboard()
    if not (pw and ph and bb) then measureCache[shown]=false; return nil end
    local ok,fullW,fullH=pcall(bb.sizeFor,pw,ph)
    fullW,fullH=tonumber(fullW),tonumber(fullH)
    if not (ok and fullW and fullH and fullW>1e-3 and fullH>1e-3) then
      measureCache[shown]=false; return nil
    end

    -- Normalize alpha bounds before multiplying by the renderer's own logical
    -- world-card size, so high-DPI pixel readback cannot alter APB units.
    local bottom=fullH*(m.padB/math.max(1,m.h))
    local top=fullH*(1-m.padT/math.max(1,m.h))
    local height=top-bottom
    local breadth=fullW*(m.visW/math.max(1,m.w))
    if height<=1e-3 then measureCache[shown]=false; return nil end
    local out={
      visualBottomY=bottom,visualTopY=top,centerY=(bottom+top)*0.5,height=height,
      breadth=breadth,spanX=breadth,spanZ=0,
      breadthHeightRatio=breadth/math.max(1e-3,height),
      elevation=math.max(0,bottom),
      elevationNorm=math.max(0,bottom)/math.max(1e-3,height),
      source="SPRITE_ALPHA_BOUNDS_V1",confidence="medium",
    }
    measureCache[shown]=out
    return out
  end

  local function resolveSpriteAPB(side,battle)
    if modelPresentationActive() then return nil end
    local battler=type(battle)=="table" and battle[side] or nil
    if type(battler)~="table" then return nil end
    local shown=presentedImage(battle,battler)
    local b=measuredSpriteBounds(shown)
    if type(b)~="table" then return nil end

    -- Keep a non-shrinking presentation envelope for the live battler. Animated
    -- art may reveal more of the actor, but subsequent smaller frames cannot
    -- make the authored camera pulse in and out.
    local species=(type(battler.mon)=="table" and battler.mon.species) or battler.name
    local e=envelopes[side]
    if e.battler~=battler or e.species~=species then
      e={battler=battler,species=species,bottom=b.visualBottomY,top=b.visualTopY,
         breadth=b.breadth,tokens=0}
      envelopes[side]=e
    else
      e.bottom=math.min(e.bottom or b.visualBottomY,b.visualBottomY)
      e.top=math.max(e.top or b.visualTopY,b.visualTopY)
      e.breadth=math.max(e.breadth or b.breadth,b.breadth)
    end
    e.tokens=(e.tokens or 0)+1

    local height=(e.top or 0)-(e.bottom or 0)
    if height<=1e-3 then return nil end
    local elevation=math.max(0,e.bottom or 0)
    return {
      visualBottomY=e.bottom,visualTopY=e.top,
      centerY=((e.bottom or 0)+(e.top or 0))*0.5,height=height,
      breadth=e.breadth,spanX=e.breadth,spanZ=0,
      breadthHeightRatio=(e.breadth or 0)/math.max(1e-3,height),
      elevation=elevation,elevationNorm=elevation/math.max(1e-3,height),
      source="SPRITE_ALPHA_ENVELOPE_V1",
      confidence=(e.tokens>=2) and "high" or "medium",
    }
  end

  if spriteAPB and type(spriteAPB.registerAdapter)=="function" then
    -- Posed model geometry remains the higher-fidelity Gen1 source. Sprite
    -- evidence is used only when no model presentation resolves the actor.
    spriteAPB.registerAdapter("sprite_alpha_v1",40,resolveSpriteAPB)
    mod.log:info("[APB SPRITE] alpha-bounds presentation adapter registered")
  end
end)()
end

if DIAGNOSTIC_BUILD and DIAGNOSTIC_HUD then
  mod.log:info("[geometry diagnostics] Battle Cinematics v1.2.1")
  mod.log:info("[geometry diagnostics] shot-owned environmental recovery active")
  local okHud,errHud=pcall(function()
    mod.hooks:wrap("render.hud",function(nextFn,game,viewport)
      local result=nextFn(game,viewport)
      drawGeometryDiagnosticHud()
      return result
    end)
  end)
  if not okHud then mod.log:warn("[wall safety test] render.hud hook unavailable: %s",tostring(errHud)) end
end

mod.hooks:wrap("input.step",function(nextFn,game,dt)
  state.cameraAuthority.enforce(game)
  local result=nextFn(game,dt)
  state.cameraAuthority.enforce(game)

  -- INTRO CANCEL / B BUTTON uses Gen1Recomp's logical Game Boy B action, not
  -- the raw physical controller button named "b".  This therefore follows the
  -- user's Recomp binding (e.g. Xbox X mapped to Game Boy B) and also respects
  -- keyboard/custom mappings.  Raw input remains reserved for ANY INPUT mode.
  if state.intro.active and introResetMode()=="b" and cancelActiveIntro
      and game and game.input and type(game.input.wasPressed)=="function" then
    local okPressed,pressed=pcall(game.input.wasPressed,game.input,"b")
    if okPressed and pressed then cancelActiveIntro("B button") end
  end

  dt=cameraDelta(game,dt)
  state.noRig=state.noRig+dt
  if state.noRig>0.75 and state.rigSeen then
    state.rigSeen=false; resetBattle()
  end
  if not backends.__gold and state.manualCamera and type(state.manualCamera.step)=="function" then
    state.manualCamera.step(dt)
  end

  local battle=state.battle
  -- Gold Test 5B: refresh the normalized presentation view on the fixed-step
  -- side as well as the render side. Gen 2 battle events carry the shared
  -- logic Battle object, while BC Hero needs the live BattleState presentation
  -- seam (trainer/send-out visibility). Never make the core director guess.
  if backends.__gold and type(backends.__gold.battleView)=="function" then
    local okView,view=pcall(backends.__gold.battleView)
    if okView and view then state.battle=view; battle=view end
  end

  -- Gold's logic battle may have emitted battle.ended while its BattleState is
  -- still visibly presenting the finishing KO. Complete teardown only when the
  -- provider says that presentation is truly gone/done. Check here as well as
  -- in the render bridge so lifecycle cleanup does not depend on a render call.
  if backends.__gold and backends.__gold.logicEnded then
    local gold=backends.__gold
    local okCtx,ctx=pcall(gold.OverworldBattle.cameraContext)
    if (not okCtx) or not ctx or (ctx.screen and ctx.screen.phase=="done") then
      if type(gold.finishVisualBattle)=="function" then pcall(gold.finishVisualBattle,"fixed-step visual end") end
      battle=nil
    end
  end

  -- Gen 2 logic produces the whole turn before the UI presents it. Pair the
  -- current VISUAL acting side with the queued move_used record now, rather
  -- than letting the later logical attacker overwrite the earlier one.
  local isGold=backends.__gold and backends.__gold.isGold and backends.__gold.isGold()
  if isGold and battle and battle.phase=="menu" and not state.attack.active then
    if not state.attack.pending then backends.__gold.attackQueue={} end
  end
  if isGold and not state.attack.pending and not state.attack.active
      and battle and battle.animPlaying then
    local entry=nil
    if battle.animAttackerIsPlayer~=nil and type(backends.__gold.claimAttack)=="function" then
      local visualSide=battle.animAttackerIsPlayer and "player" or "enemy"
      entry=backends.__gold.claimAttack(visualSide)
    elseif battle.animMoveToken and type(backends.__gold.claimNextAttack)=="function" then
      -- Current host can momentarily hide the side label even though the native
      -- Gold move runner is real. The logical FIFO still knows whose move this
      -- is and is already ordered exactly as BattleState will present it.
      entry=backends.__gold.claimNextAttack()
      if entry then
        logDiagnostic("gold attack token/FIFO arm: "..tostring(entry.side))
      end
    end
    if entry then armAttack(entry.side,entry.moveId,entry.mode) end
  end

  -- Gen 2's faint lifecycle is likewise presentation-late. The native
  -- BattleState faintSlide is the authoritative visible KO seam; queue Faint
  -- Camera here instead of at the earlier logic event. activeMon/shownMon in
  -- the adapter keeps the outgoing defeated actor stable even if logic has
  -- already rebound the slot to a replacement.
  if isGold and battle and type(battle.faintSlide)=="table"
      and not state.faint.pending and not state.faint.active and faintCameraOn() then
    local side=battle.faintSlide.side
    local battler=(side=="player") and battle.player or (side=="enemy" and battle.enemy or nil)
    if battler then queueFaint(side,battler) end
  end

  -- Full Battle Intro ----------------------------------------------------
  -- Separate from per-Pokemon Intro. Phenac Test 5 is:
  --   SWOOP -> authored opponent close/pan HOLD -> battle progress.
  -- HOLD is user-paced and remains BC-owned; there is no provider hard cut.
  -- B during SWOOP is a camera-only skip into HOLD. A/B text progression after
  -- that remains the engine's normal encounter lifecycle.
  if state.battleOpening.pending and state.rigSeen and battle then
    state.battleOpening.begin()
  end
  if state.battleOpening.active then
    state.blend=chase(state.blend,1,dt,0.30)

    if state.battleOpening.phase=="swoop" then
      state.battleOpening.time=state.battleOpening.time+dt
      local duration=tonumber(state.battleOpening.duration) or 13.20
      if state.battleOpening.time>=duration then
        state.battleOpening.time=duration
        state.battleOpening.phase="hold"
        state.battleOpening.holdTime=0
        state.blend=1
        logDiagnostic("Phenac battle opening settled -> authored prompt hold")
      end
    else
      state.battleOpening.holdTime=(tonumber(state.battleOpening.holdTime) or 0)+dt

      local wild=(battle and battle.wild) and true or state.battleOpening.wildPrompt
      if battle and battle.showEnemyTrainer then
        state.battleOpening.trainerPromptSeen=true
      end

      local progressed=false
      if wild then
        -- Wild opponent is already the encounter tableau. The full Battle
        -- Intro deliberately replaces the redundant initial enemy Pokemon
        -- portrait; advancing "Wild ... appeared" begins the player's send-out.
        progressed=(battle and battle.sendingOut) and true or false
      elseif state.battleOpening.trainerPromptSeen then
        -- Trainer prompt remains host-owned. Once the trainer tableau clears /
        -- enemy send-out begins, release this battle-level module so the normal
        -- queued Pokemon Intro can wait for the visible incoming actor.
        progressed=(battle and ((not battle.showEnemyTrainer)
                    or battle.enemySendingOut or battle.sendingOut)) and true or false
      else
        -- Defensive provider-neutral release for a host that does not expose a
        -- trainer flag but has clearly entered a send-out/action phase.
        progressed=(battle and (battle.enemySendingOut or battle.sendingOut
                    or battle.animPlaying or battle.phase=="menu")) and true or false
      end

      if progressed then
        local style=state.battleOpening.style
        -- Initial wild opponent has already been fully presented by Phenac.
        -- Keep camera ownership pointed toward the queued PLAYER Intro from the
        -- instant the encounter prompt advances, instead of spending the send-
        -- out gap on a provider/enemy-facing waiting view. The actual Pokemon
        -- Intro timer still waits for its normal visible-actor lifecycle seam.
        if wild and battleIntroOn() and state.intro.pendingPlayer
            and not state.intro.pendingEnemy then
          state.intro.openingBridgeActive=true
        end
        state.battleOpening.clear()
        state.blend=0
        state.active=false
        state.idle=0
        logDiagnostic("battle opening prompt released: "..tostring(style))
      end
    end
  end

  -- Stadium attack camera -------------------------------------------------
  -- Gen 1 still arms from battle.move_used. Gold arms from the visual-side
  -- queue bridge immediately above. In both cases camera ownership starts only
  -- when a real/synthesised presentation window is visible.
  if state.attack.pending and battle and battle.animPlaying then
    local sideMatches=true
    if battle.animAttackerIsPlayer~=nil then
      sideMatches=(not not battle.animAttackerIsPlayer)==(state.attack.side=="player")
    end
    if sideMatches then beginAttack() end
  end

  if state.attack.active then
    state.attack.time=state.attack.time+dt

    -- Current-host diagnostics proved the former enemy "boomerang" was not a
    -- recipient-hold problem: during Pidgey's real enemy Tackle BC was STILL
    -- running the preceding PLAYER attack state because the current host exposed
    -- a new native move runner but no usable side label. Detect that definitive
    -- new MOVE token first. If a queued move exists, hand Attack Camera to that
    -- move immediately in FIFO order. This is presentation-order reconciliation,
    -- not a timer or camera-grammar change.
    if isGold and state.attack.sawAnimation and battle and battle.animMoveToken
        and state.attack.goldAnimToken
        and battle.animMoveToken~=state.attack.goldAnimToken
        and type(backends.__gold.claimNextAttack)=="function" then
      local nextEntry=backends.__gold.claimNextAttack()
      if nextEntry then
        clearAttack()
        armAttack(nextEntry.side,nextEntry.moveId,nextEntry.mode)
        beginAttack()
        state.attack.goldAnimToken=battle.animMoveToken
        logDiagnostic("gold attack native-token handoff: "..tostring(nextEntry.side))
      end
    end

    -- Gold can move directly from one visible attacker to the other while BC's
    -- generic 0.25s Attack tail is still breathing. If the visual side changes
    -- and the matching logic move is queued, cut directly into the next Attack
    -- Camera instead of spending the opening of that move finishing the prior
    -- side's tail. Gen 1 retains its established tail unchanged.
    if isGold and state.attack.sawAnimation and battle and battle.animPlaying
        and battle.animAttackerIsPlayer~=nil and type(backends.__gold.claimAttack)=="function" then
      local visualSide=battle.animAttackerIsPlayer and "player" or "enemy"
      if visualSide~=state.attack.side then
        local nextEntry=backends.__gold.claimAttack(visualSide)
        if nextEntry then
          clearAttack()
          armAttack(nextEntry.side,nextEntry.moveId,nextEntry.mode)
          beginAttack()
          logDiagnostic("gold attack visual-side handoff: "..tostring(visualSide))
        end
      end
    end

    local sideMatches=true
    if battle and battle.animAttackerIsPlayer~=nil then
      sideMatches=(not not battle.animAttackerIsPlayer)==(state.attack.side=="player")
    end
    -- Deliberately do not require animName == moveId. Charge animations and
    -- external Stadium FX replacements may use a different animation id while
    -- retaining the same attacker, and the camera should follow them.
    local animationMatches=battle and battle.animPlaying and sideMatches
    if isGold and animationMatches and state.attack.goldAnimToken
        and battle and battle.animMoveToken
        and battle.animMoveToken~=state.attack.goldAnimToken then
      animationMatches=false
    end

    if animationMatches then
      if not state.attack.sawAnimation then
        state.attack.sawAnimation=true
        if isGold and battle.animMoveToken then
          state.attack.goldAnimToken=battle.animMoveToken
        end
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
      local goldElapsed=isGold and tonumber(battle.animElapsedFrames) or nil
      local goldTotal=isGold and tonumber(battle.animTotalFrames) or nil
      if goldElapsed and goldTotal and goldTotal>0 then
        -- This is the missing parity with Gen 1: use the move animation's REAL
        -- normalized progress, even if BC joins an enemy attack after it has
        -- already begun visually. Do not restart Stadium grammar at p=0 merely
        -- because the logic/UI queue handoff happened late.
        state.attack.progress=math.max(0,math.min(1,goldElapsed/goldTotal))
      elseif isGold and (battle.animImpact
          or (battle.hpImpactSide and battle.hpImpactSide~=state.attack.side)) then
        -- Damage shake / HP drain both mean the defender is now the authored
        -- subject.  This is only a fallback when native move-total measurement
        -- is unavailable or the move script has already handed off.
        state.attack.progress=math.max(state.attack.progress,0.70)
      elseif elapsed and state.attack.animTotal>0 then
        state.attack.progress=math.max(0,math.min(1,elapsed/state.attack.animTotal))
      else
        -- Last-resort alternate-host fallback only. Gold's native runner path
        -- above is preferred; Gen 1 keeps its established AnimPlayer path.
        state.attack.progress=math.max(state.attack.progress,math.min(0.98,state.attack.time/2.0))
      end
      state.attack.tail=0
    elseif state.attack.sawAnimation then
      -- Let the finishing shot breathe for a fraction of a second after the FX
      -- releases the animation player, then hand the camera back to the normal
      -- BC lifecycle cleanly.
      state.attack.progress=1
      state.attack.tail=state.attack.tail+dt
      if state.attack.tail>=0.25 then
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
    local isGold=backends.__gold and backends.__gold.isGold and backends.__gold.isGold()
    local slideActive=isGold and battle and type(battle.faintSlide)=="table"
                      and battle.faintSlide.side==state.faint.side
    local shownZero=(shown~=nil and shown<=0)
    -- Gen 2 fires the logic faint event before its queued HP/faint presentation.
    -- Do not steal the camera early from an external/Off attack phase merely
    -- because logic HP is already zero; wait for visible drain/zero/slide truth.
    if drainStarted or ((not isGold) and battler and battler.fainted)
        or (isGold and (shownZero or slideActive)) then
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
      local isGold=backends.__gold and backends.__gold.isGold and backends.__gold.isGold()
      local slideActive=isGold and battle and type(battle.faintSlide)=="table"
                        and battle.faintSlide.side==state.faint.side
      local shownZero=(shown~=nil and shown<=0)
      if not state.faint.zeroReached then
        if shownZero or ((not isGold) and battler and battler.fainted)
            or (isGold and slideActive) then
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

  -- While the full Battle Intro owns the camera, do not let the passive
  -- scheduler pull the shared blend back toward zero. Attack/Faint above may
  -- still pre-empt it if battle progression somehow outruns the opening.
  if state.battleOpening.active then
    return result
  end

  -- Pokemon Intro ---------------------------------------------------------
  if battle and battleIntroOn() and state.rigSeen
      and not state.battleOpening.pending and not state.battleOpening.active then
    local enemySending=not not battle.enemySendingOut
    local playerSending=not not battle.sendingOut

    -- Existing BC Hero behaviour is deliberately preserved: each side starts
    -- only once that side's 3D model is actually visible. This handles wild
    -- encounters, trainer send-outs and later switches.
    local goldExpected=backends.__gold and backends.__gold.expectedIntroMon or nil
    local enemyExpectedOk=true
    local playerExpectedOk=true
    if goldExpected then
      if goldExpected.enemy then
        enemyExpectedOk=battle.enemy and battle.enemy.__goldMon==goldExpected.enemy
      end
      if goldExpected.player then
        playerExpectedOk=battle.player and battle.player.__goldMon==goldExpected.player
      end
    end
    if state.intro.pendingEnemy and enemyExpectedOk
        and not battle.showEnemyTrainer and not enemySending then
      startIntro("enemy","hero",false)
      if goldExpected then goldExpected.enemy=nil end
    elseif state.intro.pendingPlayer and playerExpectedOk
        and not playerSending and battle.player and not battle.showPlayerBack then
      startIntro("player","hero",state.intro.playerUnderThreat(battle))
      if goldExpected then goldExpected.player=nil end
    end
    state.intro.enemyWasSending=enemySending
    state.intro.playerWasSending=playerSending
  end

  if state.intro.active then
    local introScale=introSpeedScale()
    state.intro.time=state.intro.time+dt*introScale
    state.blend=chase(state.blend,1,dt,BLEND_TIME/introScale)
    local introDuration=state.intro.compact and (state.intro.compactDuration or 3.8) or HERO_INTRO_DURATION
    if state.intro.time>=introDuration then
      local wasCompact=state.intro.compact and true or false
      local completed=(wasCompact and "compact send-in" or state.intro.style)
          ..(state.intro.side and (" / "..state.intro.side) or "")
      local structuralHandoff=state.intro.structuralHandoffNeeded and true or false
      -- RC10 initial-intro chain ownership. Enemy and player Pokemon intros are
      -- two authored phases separated by a prompt/send-out seam. Do not clear the
      -- known-good trainer/opening anchor after the enemy Intro while the player
      -- Intro is still pending, and do not temporarily start passive Stadium/DW3
      -- in that gap. The same complete camera + projection anchor becomes the
      -- stable "Go <Pokemon>" presentation and the next Intro's blend base.
      local moreInitialIntro=(state.intro.pendingEnemy or state.intro.pendingPlayer)
          and true or false
      if state.intro.initial and not moreInitialIntro then
        state.intro.initial=false
      end
      clearIntro(structuralHandoff,moreInitialIntro)
      if moreInitialIntro then
        state.blend=0
        state.idle=0
        state.time=0
        state.active=false
        state.intro.openingChainHold=type(state.intro.openingChainCamera)=="table"
        state.geomDiag.phaseHandoffRC3="INTRO_CHAIN_RETURN_TRACK"
      elseif structuralHandoff then
        -- The environment has already proved that the native return path is a
        -- building curtain. Treat the final intro->passive transition as the
        -- authored cut it really is instead of spending another initial-delay
        -- window on the hidden backend eye. Normal/open arenas retain the
        -- established post-intro delay and blend unchanged.
        state.blend=1
        state.idle=0
        state.time=0
        state.active=true
        state.geomDiag.phaseHandoffRC3="INTRO_TO_PASSIVE_CUT"
      else
        state.blend=0
        state.idle=0
        state.active=false
      end
      logDiagnostic("battle intro complete: "..tostring(completed)..(structuralHandoff and " / structural cut" or ""))
    end
    return result
  end

  -- During an opening BC Hero intro the selected idle preset waits until its
  -- queued cinematography has completed. Switch portraits retain v0.7.3 logic.
  local introWaiting=(state.battleOpening.pending or state.battleOpening.active)
      or (battleIntroOn() and (state.intro.pendingEnemy or state.intro.pendingPlayer))
  -- RC8 lifecycle semantics: passive preset time does not begin before the
  -- battle object exists, while trainer sprites own the opening tableau, or
  -- during either side's send-out. This prevents a Stadium/DW3 Pokemon shot
  -- from being spent behind geometry before its intended Pokemon even exists.
  local trainerWaiting=battle and
      ((not not battle.showEnemyTrainer) or (not not battle.showPlayerBack))
  local sendoutWaiting=battle and
      ((not not battle.enemySendingOut) or (not not battle.sendingOut))
  if state.rigSeen and enabled() and battle and not introWaiting
      and not trainerWaiting and not sendoutWaiting then
    if not state.active then
      state.idle=state.idle+dt
      if state.idle>=idleDelay() then
        state.active=true; state.time=0
        state.intro.openingBridgeActive=false
        state.intro.openingChainHold=false
        logDiagnostic("cinematic active")
      end
    else state.time=state.time+dt end
  elseif not enabled() or not battle or introWaiting or trainerWaiting or sendoutWaiting then
    state.active=false; state.idle=0
  end
  state.blend=chase(state.blend,(enabled() and state.active) and 1 or 0,dt,BLEND_TIME)

  -- Secondary View Rebase 2: retain Probe13's conservative ~10 fps private
  -- render cadence while the DW3 passive phase owns the battle view.
  if state.secondaryViewProbe and type(state.secondaryViewProbe.fixedStep)=="function" then
    state.secondaryViewProbe.fixedStep()
  end
  return result
end,25,"BATTLE_CINEMATICS")

-- Input policy ------------------------------------------------------------
-- RESET CAMERA controls the selected idle preset. INTRO CANCEL controls
-- the per-Pokemon Intro independently; the separate full BATTLE INTRO is not
-- wired to that cancel option in this first proof. Pokemon intros can remain uninterruptible,
-- dismiss only on a committed move/item, or dismiss on any input.
local function resetMode()
  return mod.options:get("inputReturn") or "confirmed"
end
cancelActiveIntro=function(reason)
  if not state.intro.active then return false end
  local side=state.intro.side
  local hasChain=type(state.intro.openingChainCamera)=="table"
  local moreInitialIntro=(state.intro.pendingEnemy or state.intro.pendingPlayer) and true or false
  local preserve=hasChain
  if state.intro.initial and not moreInitialIntro then
    state.intro.initial=false
  end
  clearIntro(false,preserve)

  if hasChain and moreInitialIntro then
    -- Enemy Intro skipped/completed while the player's initial Intro is still
    -- pending: return to the last proven trainer/opening composition.
    state.intro.openingChainHold=true
    state.intro.openingBridgeActive=false
    state.blend=0
    state.idle=0
    state.active=false
  elseif hasChain then
    -- Final initial Pokemon Intro was deliberately skipped.  Do not invent an
    -- absolute trainer-camera bridge (RC11 could point at white space).  A skip
    -- means "finish the Intro phase", so cut straight to the selected passive
    -- camera and let the shared geometry stack validate that shot immediately.
    state.intro.openingChainHold=false
    state.intro.openingBridgeActive=false
    state.blend=1
    state.idle=0
    state.time=0
    state.active=true
    state.geomDiag.phaseHandoffRC3="INTRO_SKIP_TO_PASSIVE"
  else
    state.blend=0
    state.idle=0
    state.active=false
  end

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

(function()
  -- Camera-only B skip ------------------------------------------------------
  -- Do NOT guess keyboard/gamepad button names. Let Gen1Recomp's normal input
  -- mapper run first, then inspect only the logical actions appended to this
  -- Game instance's pressQueue. If one is GB B during the Phenac SWOOP, remove
  -- that new edge before Input:step promotes it, and cut the CAMERA to HOLD.
  -- The game's prompt therefore does not advance from the same press.
  local function consumeBattleOpeningSkip(game,before)
    if not (state.battleOpening.active and state.battleOpening.phase=="swoop") then
      return false
    end
    local input=game and game.input
    local q=input and input.pressQueue
    if type(q)~="table" then return false end
    before=math.max(0,tonumber(before) or 0)
    local sawB=false
    for i=#q,before+1,-1 do
      if q[i]=="b" then
        table.remove(q,i)
        sawB=true
      end
    end
    if sawB then
      return state.battleOpening.skipToHold("B button")
    end
    return false
  end

  local function wrapInputPressMethod(tbl,name)
    local inner=tbl and tbl[name]
    local flag="__bcPhenacSkip_"..tostring(name)
    if type(inner)~="function" or tbl[flag] then return end
    tbl[name]=function(self,...)
      rawActivity()
      local input=self and self.input
      local before=(input and type(input.pressQueue)=="table") and #input.pressQueue or 0
      local result=inner(self,...)
      consumeBattleOpeningSkip(self,before)
      return result
    end
    tbl[flag]=true
  end
  wrapInputPressMethod(Game,"keypressed")
  wrapInputPressMethod(Game,"gamepadpressed")
  wrapInputPressMethod(Game,"joystickpressed")
  wrapInputPressMethod(Game,"touchpressed")
  -- A physical mouse is not a gameplay GB-button path, but retain BC's existing
  -- ANY INPUT activity semantics for desktop pointer presses.
  wrapMethod(Game,"mousepressed",rawActivity)
end)()
-- Mod API 2 content sandboxes do not permit mods to replace global LÖVE callbacks.
-- Game-level key/gamepad/touch/mouse methods above are BC's supported input seam.
-- Keep raw Android input handling inside Game rather than mutating love.* globals.

-- Sanctioned battle commitments. These wrappers do not alter the action;
-- they only apply the selected reset policy before the action is rendered.
local okBattle,BattleState=pcall(require,"src.battle.BattleState")
if okBattle and BattleState then
  -- Player trainer-pic suppression experiment removed in Test 6. The host
  -- presentation is left completely untouched here.

  wrapMethod(BattleState,"resolveTurn",confirmedAction)
  wrapMethod(BattleState,"tryRun",confirmedAction)
  wrapMethod(BattleState,"openItems",confirmedAction)
  wrapMethod(BattleState,"openParty",confirmedAction)
else
  mod.log:warn("move/item hooks unavailable; ANY INPUT remains supported")
end

-- Battle cinematography lifecycle ------------------------------------------
mod.events:on("battle.started",function(ev)
  if not backends.__gold and state.manualCamera
      and type(state.manualCamera.resetInputBoundary)=="function" then
    pcall(state.manualCamera.resetInputBoundary)
  end
  if backends.__gold then
    local gold=backends.__gold
    if type(gold.resetBattleBridge)=="function" then pcall(gold.resetBattleBridge,"battle.started") end
    gold.battleLive=true
  end
  state.battle=ev and ev.battle or nil
  state.intro.initial=true
  -- A pre-event battle rig can already have established RC8's safe opening
  -- roof anchor. Preserve that current-battle presentation across the moment
  -- battle.started gives us the battle object; battle.ended has already cleared
  -- any previous-battle anchor.
  local openingCamera=state.intro.openingStructuralCamera
  local openingMode=state.intro.openingStructuralMode
  local openingPitch=state.intro.openingStructuralPitch
  local chainCamera=state.intro.openingChainCamera
  local chainMode=state.intro.openingChainMode
  local chainPitch=state.intro.openingChainPitch
  clearIntro()
  state.battleOpening.clear()
  state.intro.openingStructuralCamera=openingCamera
  state.intro.openingStructuralMode=openingMode
  state.intro.openingStructuralPitch=openingPitch
  state.intro.openingChainCamera=chainCamera
  state.intro.openingChainMode=chainMode
  state.intro.openingChainPitch=chainPitch
  clearAttack()
  clearFaint()
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  state.intro.enemyFreshSendIn=false
  state.intro.playerFaintReplacement=false

  state.battleOpening.queue()
  local style=battleIntroStyle()
  if style=="hero" then
    local wildBattle=state.battle and state.battle.wild and true or false
    if state.battleOpening.enabled() and wildBattle then
      -- Colosseum-style full Battle Intro already presents the static wild
      -- opponent under the encounter prompt.  Do not immediately replay that
      -- same opponent as a second BC Hero intro; preserve the player's Intro.
      state.intro.pendingEnemy=false
      state.intro.pendingPlayer=true
    else
      state.intro.pendingEnemy=true
      state.intro.pendingPlayer=true
    end
  else
    state.intro.initial=false
  end
  state.idle,state.time,state.active,state.blend=0,0,false,0
  logDiagnostic("battle started; battle opening="..tostring(state.battleOpening.optionStyle())
      .." / Pokemon intro="..style)
end)

mod.events:on("battle.battler_switched",function(ev)
  -- Gen 1 reports this after its KO presentation. Gen 2 can emit the logical
  -- replacement before BattleState has shown the outgoing faint; let the Gold
  -- visual actor/faintSlide lifecycle end that camera instead.
  if not backends.__gold and (state.faint.pending or state.faint.active) then clearFaint() end
  -- A no-animation move may leave the attack module armed; switching is an
  -- unambiguous lifecycle boundary, so discard that stale arm before queuing
  -- any preserved BC Hero switch portrait.
  if state.attack.pending then clearAttack() end
  -- Later player summons are treated as Send-Ins. The classifier decides
  -- whether this specific lifecycle window needs Compact or can safely use Full.
  if battleIntroStyle()~="hero" or not ev then return end
  state.battle=ev.battle or state.battle
  local side=ev.side and ev.side.index
  if side==1 then
    if backends.__gold and type(backends.__gold.expectedIntroMon)=="table" then
      backends.__gold.expectedIntroMon.player=ev.battler
    end
    queueIntro("player")
  elseif side==2 then
    if backends.__gold and type(backends.__gold.expectedIntroMon)=="table" then
      backends.__gold.expectedIntroMon.enemy=ev.battler
    end
    state.intro.enemyFreshSendIn=true
    queueIntro("enemy")
  end
  state.idle,state.time,state.active,state.blend=0,0,false,0
end)

mod.events:on("battle.fainted",function(ev)
  if not ev or not ev.battler then return end
  state.battle=ev.battle or state.battle
  local battle=ev.battle or state.battle
  local battler=ev.battler
  local side=nil
  if ev.side=="player" or ev.side=="enemy" then
    side=ev.side
  elseif type(ev.side)=="table" and tonumber(ev.side.index) then
    side=(tonumber(ev.side.index)==1) and "player" or "enemy"
  elseif battler.isPlayer~=nil then
    side=battler.isPlayer and "player" or "enemy"
  elseif battle and battler==battle.player then side="player"
  elseif battle and battler==battle.enemy then side="enemy" end
  if side=="player" then
    -- Forced replacement grace. Do NOT clear this at battle.turn_ended: in Gen 1
    -- the KO/turn seam occurs before the mandatory replacement is presented.
    -- The marker is consumed when that replacement's Send-In is classified.
    state.intro.playerFaintReplacement=true
  end
  -- Gold raises this while generating the logic queue, before the native
  -- BattleState has reached HP drain / faintSlide. The fixed-step adapter queues
  -- Gold Faint Camera from that VISUAL seam instead. Gen 1 keeps its established
  -- event-time queue unchanged.
  if not backends.__gold then
    queueFaint(side,battler)
  end
end)

mod.events:on("battle.move_used",function(ev)
  if not ev or not ev.user then return end
  state.battle=ev.battle or state.battle
  state.intro.enemyFreshSendIn=false
  -- If a move can commit, any forced-replacement grace is stale by definition.
  state.intro.playerFaintReplacement=false

  -- Send-In ownership never delays battle progression. If the engine commits
  -- a move while any BC introduction is still presenting, finish that camera
  -- phase immediately; Stadium Attack Camera may then claim the move, or an
  -- external/engine camera remains free to present it when BC Attack is Off.
  if state.intro.active and cancelActiveIntro then
    cancelActiveIntro("battle action")
  end

  local side=nil
  if ev.side=="player" or ev.side=="enemy" then
    side=ev.side
  elseif type(ev.side)=="table" and tonumber(ev.side.index) then
    side=(tonumber(ev.side.index)==1) and "player" or "enemy"
  elseif ev.user.isPlayer~=nil then
    side=ev.user.isPlayer and "player" or "enemy"
  else
    local logic=ev.battle or (state.battle and state.battle.__goldLogic)
    if logic and ev.user==logic.player then side="player"
    elseif logic and ev.user==logic.enemy then side="enemy" end
  end
  if not side then side="enemy" end
  local moveId=ev.move and ev.move.id or ev.moveId
  local mode
  if backends.__gold and type(backends.__gold.classifyAttackMove)=="function" then
    mode=backends.__gold.classifyAttackMove(ev.battle or state.battle,ev.move)
  else
    mode=classifyAttackMove(ev.battle or state.battle,ev.move)
  end
  if backends.__gold and type(backends.__gold.queueAttack)=="function" then
    if enabled() and stadiumAttackOn() then backends.__gold.queueAttack(side,moveId,mode) end
  else
    armAttack(side,moveId,mode)
  end
end)

mod.events:on("battle.turn_ended",function()
  state.intro.enemyFreshSendIn=false
  -- Gen 1 reaches this seam after its presentation opportunity; clearing a move
  -- that never produced AnimPlayer prevents stale ownership. Gen 2 is different:
  -- Battle.lua emits turn_ended when it has GENERATED the UI event queue, before
  -- BattleState has replayed the move animation. Keep the Gold arm until that
  -- queue either starts an animation or visibly returns to the menu.
  local isGold=backends.__gold and backends.__gold.isGold and backends.__gold.isGold()
  if not isGold and state.attack.pending and not state.attack.active then clearAttack() end
end)

mod.events:on("battle.ended",function(ev)
  if state.secondaryViewProbe and type(state.secondaryViewProbe.clear)=="function" then
    pcall(state.secondaryViewProbe.clear)
  end
  if not backends.__gold and state.manualCamera
      and type(state.manualCamera.resetInputBoundary)=="function" then
    pcall(state.manualCamera.resetInputBoundary)
  end
  if backends.__gold then
    -- Gen 2 emits this from the LOGIC battle as soon as the outcome is known.
    -- BattleState can still have the finishing HP drain, faint slide, EXP and
    -- closing presentation queued. Keep the proven Gold bridge alive until the
    -- provider's actual live battle screen reaches done/disappears.
    local gold=backends.__gold
    gold.logicEnded=true
    gold.endResult=ev and ev.result or nil
    return
  end
  state.cameraAuthority.restore()
  state.intro.enemyFreshSendIn=false
  state.intro.playerFaintReplacement=false
  state.battle=nil
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  state.battleOpening.clear()
  clearIntro()
  clearAttack()
  clearFaint()
end)

-- Public camera-layer ownership contract. This is intentionally independent of
-- any particular consumer: presentation hosts may query it, but BC neither
-- discovers nor depends on them. CAMERA AUTHORITY controls whether BC also
-- protects those authored phases from external post-camera modifiers.
mod.exports.cameraOwnership=function()
  local on=enabled()
  return {
    protocol=1,
    authority=state.cameraAuthority.priority() and "priority" or "cooperative",
    claims={
      passive=on and selectedPreset()~="external",
      intro=on and (state.battleOpening.enabled() or battleIntroOn()),
      attack=on and stadiumAttackOn(),
      faint=on and faintCameraOn(),
    },
  }
end

mod.exports.version="1.2.1"
mod.exports.activity=activity
mod.log:info("Battle Cinematics v1.2.1 connected (%d camera backend%s)",#backends,#backends==1 and "" or "s")
