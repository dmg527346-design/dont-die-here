-- Pure pose recipes for ReplicatedStorage.SelectedItemCharacterEffects.
-- No update loops, connections, tasks, remotes, instances or private state.
-- The EXISTING ItemDraftEffects owner publishes DraftSelectedItem/Start/Until.
-- Existing CharacterMotionClient and VoiceMouthClient call Evaluate at their
-- final native pose point. Never multiply last frame's already-scaled values.
-- Identity is the normal native result, not a frozen rest pose.
--
-- Descriptor contract:
-- eyes.Left/Right:
--   size, pupilSize, stalkScale : Vector3 multipliers of the owner's bases
--   stalkOffset : Vector3 studs; stalkAngles : Vector3 radians
--   lidOffset : additive radians after the native blink/squint angle
-- mouth:
--   scale : Vector3 multiplier of THIS FRAME's native voiced/smile shape
--   offset : Vector3 studs; angles : Vector3 radians
--   teethChatter : instantaneous signed stud displacement; upper/lower rows
--                  use opposite signs so the teeth visibly chatter in place
-- body:
--   torsoScale, leftFootScale, rightFootScale, leftHandScale, rightHandScale
--      : Vector3 multipliers of saved native bases
--   neckOffset : Vector3 studs; neckAngles, waistAngles : Vector3 radians
--
-- Hooks: CharacterMotionClient applies stalkOffset/Angles AFTER its gaze/bob,
-- eye size/pupilSize before the matching lid shell is sized, then lidOffset.
-- VoiceMouthClient applies mouth scale to all mouth shell/inside/throat/depth/
-- back components AFTER native voice/smile/sad/kiss shaping, and applies the
-- same offset/angles to their joints AND the fourteen teeth. Do not move lips
-- alone away from their mouth interior. Respect native missing/broken teeth.
-- Body sizes need an owner base cache and restore on expired/cleared lease,
-- character replacement, death and leave. Compose with the native helium scale
-- if present; do not race another callback or change collision/Humanoid scales.
-- Local render application on every client uses the replicated selected lease,
-- making the real character deformation visible to holder and teammates.
-- Root-owned BackwardsHairdryer and NoseyMagnifier intentionally omitted.
local M = {}
local V = Vector3.new
local ZERO = V(0, 0, 0)
local ONE = V(1, 1, 1)
local TAU = math.pi * 2
local function angle(x, y, z) return V(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0)) end
local function wave(t, period, phase) return math.sin(t * TAU / period + (phase or 0)) end
local function breath(t, period, phase) return .5 + .5 * wave(t, period, phase) end
local function finite(x, fallback)
    return type(x) == 'number' and x == x and math.abs(x) < 1e9 and x or fallback
end
local function eye()
    return {size = ONE, pupilSize = ONE, stalkScale = ONE, stalkOffset = ZERO, stalkAngles = ZERO, lidOffset = 0}
end
function M.Identity()
    return {eyes = {Left = eye(), Right = eye()},
        mouth = {scale = ONE, offset = ZERO, angles = ZERO, teethChatter = 0},
        body = {torsoScale = ONE, neckOffset = ZERO, neckAngles = ZERO, waistAngles = ZERO,
            leftFootScale = ONE, rightFootScale = ONE, leftHandScale = ONE, rightHandScale = ONE}}
end
local recipes = {}
recipes.BackwardsHairdryer=function(d,t,moving)
 local flutter=math.sin(t*24)
 for _,side in {'Left','Right'}do local e=d.eyes[side];local sign=side=='Left'and-1 or 1
  e.stalkAngles=V(math.rad(-102)+flutter*.035,0,sign*.14)
  e.stalkOffset=V(sign*.12,.04,-.28)
  e.size=V(1.04,.88,1.08);e.pupilSize=V(.75,1.18,1)
  e.lidOffset=0
 end
 d.mouth.scale=V(1.6,.58,1.05);d.mouth.offset=V(0,.06,-.15);d.mouth.angles=V(-.15,0,flutter*.025)
 d.body.neckAngles=V(-.12,0,0);d.body.torsoScale=V(.96,1.03,1)
end
recipes.NoseyMagnifier=function(d,t,moving)
 local e=d.eyes.Left;e.size=V(2.0,2.0,2.0);e.pupilSize=V(1.62,1.62,1)
 e.stalkOffset=V(-.20,.16,.14);e.stalkAngles=V(-.06,-.08,-.06)
 d.eyes.Right.size=V(.90,.90,.90);d.eyes.Right.lidOffset=math.rad(-23)
 d.mouth.scale=V(.72,1.03,1.08);d.body.neckAngles=V(0,.08,.035)
end


recipes.SpringyWhisk = function(d, t, moving)
    local spin, bounce = wave(t, 1.8), breath(t, 1.8)
    d.eyes.Left.stalkScale = V(.9, 1.05 + .28 * bounce, .9)
    d.eyes.Right.stalkScale = V(.9, 1.05 + .28 * (1 - bounce), .9)
    d.eyes.Left.stalkAngles = angle(12 * spin, 17 * spin, 18 * spin)
    d.eyes.Right.stalkAngles = angle(-12 * spin, -17 * spin, -18 * spin)
    d.eyes.Left.stalkOffset = V(.08, .12 * bounce, 0)
    d.eyes.Right.stalkOffset = V(-.08, .12 * (1 - bounce), 0)
    d.mouth.scale = V(.8, 1.16, 1.12)
    d.mouth.angles = angle(0, 0, 5 * spin)
    d.body.waistAngles = angle(0, 10 * spin, 0)
    d.body.neckAngles = angle(4 * spin, -12 * spin, 0)
end
recipes.PoutingSugarBowl = function(d, t, moving)
    local sulk = breath(t, 4)
    d.mouth.scale = V(.7, 1.38, 1.28)
    d.mouth.offset = V(0, -.14 - .04 * sulk, .1)
    d.mouth.angles = angle(-8, 0, 0)
    d.eyes.Left.stalkAngles = angle(13, 0, -17)
    d.eyes.Right.stalkAngles = angle(13, 0, 17)
    d.eyes.Left.size = V(1.1, .85, 1)
    d.eyes.Right.size = V(1.1, .85, 1)
    d.eyes.Left.lidOffset = math.rad(-20)
    d.eyes.Right.lidOffset = math.rad(-20)
    d.body.torsoScale = V(1.2, .93, 1.15)
    d.body.neckAngles = angle(-7, 0, 5 * sulk)
end
recipes.RockingSeahorseToy = function(d, t, moving)
    local rock = wave(t, 3.8)
    d.body.torsoScale = V(.88, 1.2, .9)
    d.body.waistAngles = angle(13 * rock, 0, 0)
    d.body.neckOffset = V(0, .24, -.12)
    d.body.neckAngles = angle(-14 - 10 * rock, 0, 0)
    d.body.leftFootScale = V(.9, 1, 1.3)
    d.body.rightFootScale = V(.9, 1, 1.3)
    d.eyes.Left.stalkScale = V(.9, 1.16, .9)
    d.eyes.Right.stalkScale = V(.9, 1.16, .9)
    d.eyes.Left.stalkAngles = angle(-10 + 8 * rock, 0, -5)
    d.eyes.Right.stalkAngles = angle(-10 + 8 * rock, 0, 5)
    d.mouth.scale = V(.58, .8, 1.4)
    d.mouth.offset = V(0, 0, .1)
end
recipes.OrbitingAtomModel = function(d, t, moving)
    local orbit = t * TAU / 4.2
    local x, y = math.cos(orbit) * .21, math.sin(orbit) * .19
    d.eyes.Left.stalkOffset = V(.18 + x, y, .06)
    d.eyes.Right.stalkOffset = V(-.18 - x, -y, -.06)
    d.eyes.Left.stalkAngles = angle(0, 10 * math.sin(orbit), 12 * math.cos(orbit))
    d.eyes.Right.stalkAngles = angle(0, -10 * math.sin(orbit), -12 * math.cos(orbit))
    d.eyes.Left.pupilSize = V(1.2, 1.2, 1)
    d.eyes.Right.pupilSize = V(1.2, 1.2, 1)
    d.body.neckAngles = angle(0, 7 * math.sin(orbit), 0)
    d.mouth.scale = V(.75, 1.2, 1)
end
recipes.PeekingNestingDoll = function(d, t, moving)
    local peek = breath(t, 5.2)
    d.body.torsoScale = V(1.28, .84, 1.2)
    d.body.neckOffset = V(0, -.46 + .38 * peek, 0)
    d.eyes.Left.stalkScale = V(1, .58 + .28 * peek, 1)
    d.eyes.Right.stalkScale = V(1, .58 + .28 * peek, 1)
    d.eyes.Left.stalkOffset = V(-.12, -.08, 0)
    d.eyes.Right.stalkOffset = V(.12, -.08, 0)
    d.eyes.Left.size = V(.86, .86, .86)
    d.eyes.Right.size = V(.86, .86, .86)
    d.mouth.scale = V(.65, .7, .9)
    d.body.leftHandScale = V(.8, .8, .8)
    d.body.rightHandScale = V(.8, .8, .8)
end
recipes.RestlessToyExcavator = function(d, t, moving)
    local dig = breath(t, 4.4)
    d.body.waistAngles = angle(8 + 16 * dig, 0, 0)
    d.body.neckOffset = V(0, -.1, .1)
    d.body.neckAngles = angle(-11 * dig, 0, 0)
    d.eyes.Left.stalkAngles = angle(16 + 8 * dig, 0, -6)
    d.eyes.Right.stalkAngles = angle(16 + 8 * dig, 0, 6)
    d.mouth.scale = V(1.12, .65 + .7 * dig, 1.18)
    d.mouth.offset = V(0, -.08 - .08 * dig, .08)
    d.mouth.angles = angle(-12 * dig, 0, 0)
    d.body.leftHandScale = V(1.35, 1.2, 1.25)
end
recipes.BobbingBirdBath = function(d, t, moving)
    local bob = wave(t, 3.6)
    d.mouth.scale = V(1.48, .58, 1.2)
    d.mouth.offset = V(0, -.05, .08)
    d.eyes.Left.stalkOffset = V(.2, -.05 + .07 * bob, 0)
    d.eyes.Right.stalkOffset = V(-.2, -.05 - .07 * bob, 0)
    d.eyes.Left.stalkAngles = angle(10, 0, -19)
    d.eyes.Right.stalkAngles = angle(10, 0, 19)
    d.eyes.Left.lidOffset = math.rad(-10)
    d.eyes.Right.lidOffset = math.rad(-10)
    d.body.torsoScale = V(1.16, .93, 1.1)
    d.body.neckAngles = angle(5 * bob, 0, 0)
end
recipes.CrinklyPaperBag = function(d, t, moving)
    local crinkle = wave(t, 2.3)
    d.body.torsoScale = V(1.1 + .09 * crinkle, 1.06 - .06 * crinkle, .84)
    d.eyes.Left.size = V(1.16, .7 + .16 * breath(t, 2.3), .9)
    d.eyes.Right.size = V(.88, 1.05, .9)
    d.eyes.Left.stalkAngles = angle(0, 0, -12 - 7 * crinkle)
    d.eyes.Right.stalkAngles = angle(0, 0, 12 - 7 * crinkle)
    d.mouth.scale = V(1.15, 1.08, .7 + .15 * crinkle)
    d.mouth.angles = angle(0, 0, 7 * crinkle)
    d.body.waistAngles = angle(0, 0, -4 * crinkle)
end
recipes.SleepyMeasuringJug = function(d, t, moving)
    -- A recognizable drowsy nod and brief yawn; retain the character's normal silhouette.
    local phase=(t%6.8)/6.8
    local nod=math.sin(math.pi*phase)^2
    local yawn=math.max(0,math.sin((phase-.42)*math.pi/.38))
    if phase<.42 or phase>.80 then yawn=0 end
    yawn=yawn*yawn
    d.body.neckAngles=angle(3+19*nod,0,-3*nod)
    d.body.waistAngles=angle(2*nod,0,0)
    for _,side in {'Left','Right'} do
        local e=d.eyes[side]
        e.lidOffset=math.rad(-37-12*nod)
        e.stalkAngles=angle(5+8*nod,0,side=='Left'and-3 or 3)
    end
    d.mouth.scale=V(.87-.12*yawn,.72+1.05*yawn,1)
    d.mouth.offset=V(0,-.025-.045*yawn,0)
end
recipes.TopsyChessRook = function(d, t, moving)
    local tower = wave(t, 6.5)
    d.body.torsoScale = V(.88, 1.38, .94)
    d.body.neckOffset = V(0, .26, 0)
    d.body.neckAngles = angle(0, 18 * tower, 0)
    d.eyes.Left.stalkScale = V(1, 1.15, 1)
    d.eyes.Right.stalkScale = V(1, 1.15, 1)
    d.eyes.Left.stalkAngles = angle(0, 0, -12)
    d.eyes.Right.stalkAngles = angle(0, 0, 12)
    d.eyes.Left.lidOffset = math.rad(-8)
    d.eyes.Right.lidOffset = math.rad(-8)
    d.body.leftFootScale = V(1.35, 1, 1.2)
    d.body.rightFootScale = V(1.35, 1, 1.2)
    d.mouth.scale = V(1.1, .62, 1)
end
recipes.RestlessNutcracker = function(d, t, moving)
    local clap = breath(t, 1.7)
    d.mouth.scale = V(1.12, .72 + .75 * clap, 1.08)
    d.mouth.offset = V(0, -.14 * clap, .04)
    d.mouth.angles = angle(-6 * clap, 0, 0)
    d.mouth.teethChatter = .035 * wave(t, 1.7)
    d.eyes.Left.size = V(1.12, .75, 1)
    d.eyes.Right.size = V(1.12, .75, 1)
    d.eyes.Left.lidOffset = math.rad(-18)
    d.eyes.Right.lidOffset = math.rad(-18)
    d.body.torsoScale = V(.94, 1.12, 1)
    d.body.neckOffset = V(0, .1, 0)
end
recipes.SillySatelliteDish = function(d, t, moving)
    local scan = wave(t, 7)
    d.body.neckAngles = angle(-8, 26 * scan, 0)
    d.eyes.Left.size = V(1.25, 1.15, .72)
    d.eyes.Right.size = V(1.25, 1.15, .72)
    d.eyes.Left.pupilSize = V(.72, .72, 1)
    d.eyes.Right.pupilSize = V(.72, .72, 1)
    d.eyes.Left.stalkOffset = V(.16, .1, 0)
    d.eyes.Right.stalkOffset = V(-.16, .1, 0)
    d.eyes.Left.stalkAngles = angle(-14, 0, -22)
    d.eyes.Right.stalkAngles = angle(-14, 0, 22)
    d.mouth.scale = V(.55, 1.28, 1)
    d.body.torsoScale = V(.95, 1.08, .95)
end
recipes.FidgetCalculator = function(d, t, moving)
    local tap = wave(t, 2.1)
    local alternate = wave(t, 2.1, math.pi)
    d.eyes.Left.pupilSize = V(1.25, .65, 1)
    d.eyes.Right.pupilSize = V(1.25, .65, 1)
    d.eyes.Left.stalkOffset = V(0, .12 * tap, 0)
    d.eyes.Right.stalkOffset = V(0, .12 * alternate, 0)
    d.eyes.Left.stalkAngles = angle(0, 8 * tap, 0)
    d.eyes.Right.stalkAngles = angle(0, -8 * tap, 0)
    d.mouth.scale = V(1.22, .55, .9)
    d.mouth.offset = V(.06 * tap, 0, 0)
    d.mouth.teethChatter = .012 * tap
    d.body.torsoScale = V(1.1, .96, .8)
    d.body.neckAngles = angle(0, 0, 5 * tap)
end
recipes.FoldingTravelStool = function(d, t, moving)
    local fold = breath(t, 5)
    d.body.torsoScale = V(1.24, .62 + .1 * fold, 1.12)
    d.body.neckOffset = V(0, -.22 + .08 * fold, 0)
    d.body.waistAngles = angle(8 + 6 * fold, 0, 0)
    d.body.leftFootScale = V(1.32, .9, 1.42)
    d.body.rightFootScale = V(1.32, .9, 1.42)
    d.eyes.Left.stalkScale = V(.95, .78, .95)
    d.eyes.Right.stalkScale = V(.95, .78, .95)
    d.eyes.Left.stalkAngles = angle(0, 0, -11)
    d.eyes.Right.stalkAngles = angle(0, 0, 11)
    d.mouth.scale = V(1.2, .72, 1)
end
recipes.TumblingDominoRack = function(d, t, moving)
    local tumble = wave(t, 3.2)
    d.eyes.Left.stalkAngles = angle(0, 0, 24 * tumble)
    d.eyes.Right.stalkAngles = angle(0, 0, 24 * wave(t, 3.2, -.9))
    d.eyes.Left.stalkScale = V(1, 1 + .18 * tumble, 1)
    d.eyes.Right.stalkScale = V(1, 1 - .18 * tumble, 1)
    d.body.waistAngles = angle(0, 0, -9 * tumble)
    d.body.neckAngles = angle(0, 0, 11 * tumble)
    d.mouth.angles = angle(0, 0, -8 * tumble)
    d.mouth.scale = V(.9, 1.1, 1)
end
recipes.RebelliousToyDrum = function(d, t, moving)
    local beat = breath(t, 1.2)
    local otherBeat = breath(t, 1.2, math.pi)
    d.body.torsoScale = V(1.12, 1, 1.03 + .13 * beat)
    d.body.leftHandScale = V(1.12 + .2 * beat, 1.12, 1.12)
    d.body.rightHandScale = V(1.12 + .2 * otherBeat, 1.12, 1.12)
    d.body.neckAngles = angle(7 * wave(t, 1.2), 0, 0)
    d.eyes.Left.stalkOffset = V(0, .1 * beat, 0)
    d.eyes.Right.stalkOffset = V(0, .1 * otherBeat, 0)
    d.mouth.offset = V(0, .045 * wave(t, 1.2), 0)
    d.mouth.scale = V(1.12, .9 + .15 * beat, 1)
end
recipes.WindUpCrabToy = function(d, t, moving)
    local scuttle = wave(t, 2.6)
    d.eyes.Left.stalkAngles = angle(-8, 0, -23)
    d.eyes.Right.stalkAngles = angle(-8, 0, 23)
    d.eyes.Left.stalkOffset = V(.24, .16, 0)
    d.eyes.Right.stalkOffset = V(-.24, .16, 0)
    d.eyes.Left.stalkScale = V(.8, 1.22, .8)
    d.eyes.Right.stalkScale = V(.8, 1.22, .8)
    d.body.leftHandScale = V(1.45, 1.2, 1.35)
    d.body.rightHandScale = V(1.45, 1.2, 1.35)
    d.body.leftFootScale = V(1.25, .9, 1)
    d.body.rightFootScale = V(1.25, .9, 1)
    d.body.neckAngles = angle(0, 0, 7 * scuttle)
    d.mouth.scale = V(.86, .65 + .2 * breath(t, 2.6), 1.28)
end
recipes.OrigamiCrane = function(d, t, moving)
    local glide = wave(t, 5.8)
    d.body.torsoScale = V(.88, 1.18, .64)
    d.body.neckOffset = V(0, .2, .05)
    d.body.neckAngles = angle(-10, 0, 6 * glide)
    d.body.leftFootScale = V(.82, .7, 1.3)
    d.body.rightFootScale = V(.82, .7, 1.3)
    d.eyes.Left.stalkScale = V(.78, 1.22, .8)
    d.eyes.Right.stalkScale = V(.78, 1.22, .8)
    d.eyes.Left.stalkAngles = angle(-11, 0, -9)
    d.eyes.Right.stalkAngles = angle(-11, 0, 9)
    d.mouth.scale = V(.6, .65, 1.42)
    d.mouth.offset = V(0, 0, .12)
    d.body.waistAngles = angle(0, 0, -4 * glide)
end
recipes.DancingMetronome = function(d, t, moving)
    local pendulum = wave(t, 1.5)
    d.body.neckAngles = angle(0, 0, 18 * pendulum)
    d.eyes.Left.stalkOffset = V(0, .12 * pendulum, 0)
    d.eyes.Right.stalkOffset = V(0, -.12 * pendulum, 0)
    d.eyes.Left.stalkAngles = angle(0, 0, -10 * pendulum)
    d.eyes.Right.stalkAngles = angle(0, 0, -10 * pendulum)
    d.mouth.scale = V(1.1, .66, 1)
    d.mouth.angles = angle(0, 0, -8 * pendulum)
    d.body.leftFootScale = V(1.14, 1, 1.12)
    d.body.rightFootScale = V(1.14, 1, 1.12)
end
recipes.ColdIron = function(d, t, moving)
    d.body.torsoScale = V(1.28, 1, .72)
    d.body.neckOffset = V(0, -.12, -.06)
    d.body.neckAngles = angle(10, 0, 1.5 * wave(t, .62))
    d.eyes.Left.size = V(1.25, .76, 1)
    d.eyes.Right.size = V(1.25, .76, 1)
    d.eyes.Left.stalkAngles = angle(10, 0, 8)
    d.eyes.Right.stalkAngles = angle(10, 0, -8)
    d.eyes.Left.lidOffset = math.rad(-13)
    d.eyes.Right.lidOffset = math.rad(-13)
    d.mouth.scale = V(1.13, .78, 1)
    d.mouth.teethChatter = .024 * wave(t, .16)
end
recipes.GrumblingPiggyBank = function(d, t, moving)
    local waddle = wave(t, 1.8) * (.2 + .8 * moving)
    d.body.torsoScale = V(1.34, .94, 1.32)
    d.body.waistAngles = angle(0, 0, 8 * waddle)
    d.body.neckOffset = V(0, -.12, .06)
    d.eyes.Left.size = V(.88, .88, .88)
    d.eyes.Right.size = V(.88, .88, .88)
    d.eyes.Left.stalkScale = V(1.1, .7, 1.1)
    d.eyes.Right.stalkScale = V(1.1, .7, 1.1)
    d.mouth.scale = V(.68, 1.12, 1.45)
    d.mouth.offset = V(0, .015, .17)
    d.body.leftFootScale = V(1.25, .82, .9)
    d.body.rightFootScale = V(1.25, .82, .9)
end
recipes.ForgetfulDeskLamp = function(d, t, moving)
    local search = wave(t, 5.5)
    d.body.torsoScale = V(.82, 1.23, .82)
    d.body.neckOffset = V(0, .28, 0)
    d.body.neckAngles = angle(-10 + 5 * moving, 20 * search, 0)
    d.eyes.Left.stalkScale = V(.9, 1.22, .9)
    d.eyes.Right.stalkScale = V(.9, 1.22, .9)
    d.eyes.Left.pupilSize = V(1.25, 1.25, 1)
    d.eyes.Right.pupilSize = V(1.25, 1.25, 1)
    d.eyes.Left.lidOffset = math.rad(8)
    d.eyes.Right.lidOffset = math.rad(8)
    d.mouth.scale = V(.62, 1.25, 1)
end
recipes.NervousSaltShaker = function(d, t, moving)
    local distance = ((t % 4) - 3.12) / .16
    local sneeze = math.exp(-distance * distance)
    d.body.neckOffset = V(0, -.1 - .12 * sneeze, .12 * sneeze)
    d.body.neckAngles = angle(5 + 18 * sneeze, 0, 0)
    d.body.torsoScale = V(1 + .1 * sneeze, 1 - .1 * sneeze, 1)
    d.eyes.Left.size = V(1.1, 1 - .45 * sneeze, 1)
    d.eyes.Right.size = V(1.1, 1 - .45 * sneeze, 1)
    d.eyes.Left.stalkAngles = angle(5 + 12 * sneeze, 0, 5)
    d.eyes.Right.stalkAngles = angle(5 + 12 * sneeze, 0, -5)
    d.mouth.scale = V(.78 + .45 * sneeze, .8 + .68 * sneeze, 1.12)
    d.mouth.offset = V(0, -.06 * sneeze, .05)
end
recipes.CreepingTapeMeasure = function(d, t, moving)
    local measure = breath(t, 6)
    d.eyes.Left.stalkOffset = V(.1 + .28 * measure, 0, 0)
    d.eyes.Right.stalkOffset = V(-.1 - .28 * measure, 0, 0)
    d.eyes.Left.stalkAngles = angle(0, 0, -7 - 9 * measure)
    d.eyes.Right.stalkAngles = angle(0, 0, 7 + 9 * measure)
    d.mouth.scale = V(1.1 + .38 * measure, .62, 1)
    d.body.torsoScale = V(1.03 + .15 * measure, .94, 1)
    d.body.leftFootScale = V(1, .92, 1.36)
    d.body.rightFootScale = V(1, .92, 1.36)
end
recipes.SulkingUmbrella = function(d, t, moving)
    local rainSway = wave(t, 4.8)
    d.body.torsoScale = V(1.32, .86, 1.08)
    d.body.neckOffset = V(0, -.28, 0)
    d.body.neckAngles = angle(9, 0, 5 * rainSway)
    d.eyes.Left.stalkScale = V(1, .76, 1)
    d.eyes.Right.stalkScale = V(1, .76, 1)
    d.eyes.Left.stalkAngles = angle(17, 0, -20)
    d.eyes.Right.stalkAngles = angle(17, 0, 20)
    d.eyes.Left.lidOffset = math.rad(-23)
    d.eyes.Right.lidOffset = math.rad(-23)
    d.mouth.scale = V(.85, .65, 1)
    d.mouth.offset = V(0, -.13, 0)
    d.mouth.angles = angle(0, 0, -3 * rainSway)
end
recipes.SqueakyDuck = function(d, t, moving)
    local bob = wave(t, 1.7) * (.15 + .85 * moving)
    d.mouth.scale = V(1.45, .55, 1.4)
    d.mouth.offset = V(0, -.02, .12)
    d.body.torsoScale = V(1.16, .86, 1.16)
    d.body.neckOffset = V(0, -.12 + .06 * bob, 0)
    d.body.neckAngles = angle(6 * bob, 0, 0)
    d.eyes.Left.stalkScale = V(1.05, .7, 1)
    d.eyes.Right.stalkScale = V(1.05, .7, 1)
    d.eyes.Left.stalkAngles = angle(-5, 0, -8)
    d.eyes.Right.stalkAngles = angle(-5, 0, 8)
    d.body.leftFootScale = V(1.4, .85, 1.32)
    d.body.rightFootScale = V(1.4, .85, 1.32)
end

-- Monster / omen reactions (Monsters build 2026-10-27): short faces published on the same selected channel by
-- MonsterBatch, MonsterAbilities and RecoveryRoundServer, ONLY while no held item owns it (ids start with 'React').
recipes.ReactStartle = function(d, t, moving)
    local shake = wave(t, .09)
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        e.size = V(1.45, 1.45, 1.45); e.pupilSize = V(.5, .5, 1)
        e.stalkScale = V(.9, 1.35, .9); e.stalkAngles = angle(-8 + 3 * shake, 0, sign * (10 + 3 * shake))
        e.lidOffset = math.rad(10)
    end
    d.mouth.scale = V(.75, 1.75, 1.2); d.mouth.offset = V(0, -.05, 0); d.mouth.teethChatter = .025 * wave(t, .07)
    d.body.neckAngles = angle(-10, 0, 0); d.body.torsoScale = V(.94, 1.07, .94)
end
recipes.ReactWince = function(d, t, moving)
    local jolt = wave(t, .12)
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        e.size = V(1.05, .78, 1); e.lidOffset = math.rad(-70); e.stalkAngles = angle(14, 0, -sign * 12)
    end
    d.mouth.scale = V(1.55, .55, 1.05); d.mouth.teethChatter = .02 * jolt
    d.body.neckAngles = angle(12, 0, 3 * jolt); d.body.torsoScale = V(1.06, .93, 1.06)
end
recipes.ReactGrin = function(d, t, moving)
    local bounce = breath(t, .5)
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        e.lidOffset = math.rad(-35); e.stalkScale = V(1, 1.05 + .12 * bounce, 1); e.stalkAngles = angle(0, 0, sign * 8 * bounce)
    end
    d.mouth.scale = V(1.65, 1.15, 1.1); d.mouth.offset = V(0, .03, 0)
    d.body.waistAngles = angle(0, 8 * wave(t, .8), 0); d.body.neckAngles = angle(-4, 0, 6 * wave(t, .8))
end
recipes.ReactDizzy = function(d, t, moving)
    local a = t * TAU / .9
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        local k = sign * a
        e.stalkOffset = V(math.cos(k) * .16, .05 + math.sin(k) * .12, 0); e.stalkAngles = angle(math.sin(k) * 18, 0, math.cos(k) * 22)
        e.pupilSize = V(.65, .65, 1); e.size = V(1.15, 1.15, 1.15)
    end
    d.mouth.scale = V(1.2, .8, 1); d.mouth.angles = angle(0, 0, 14 * wave(t, 1.1))
    d.body.neckAngles = angle(5 * wave(t, 1.3), 0, 12 * wave(t, 1.6)); d.body.waistAngles = angle(0, 0, 6 * wave(t, 1.9))
end
recipes.ReactFloat = function(d, t, moving)
    local drift = wave(t, 1.6)
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        e.size = V(1.25, 1.25, 1.25); e.stalkScale = V(.9, 1.3, .9); e.stalkAngles = angle(-6, 0, sign * (16 + 6 * drift))
    end
    d.mouth.scale = V(.7, 1.45, 1.15); d.body.neckAngles = angle(-8, 0, 4 * drift)
    d.body.leftHandScale = V(1.2, 1.2, 1.2); d.body.rightHandScale = V(1.2, 1.2, 1.2)
end
recipes.ReactSob = function(d, t, moving)
    local sniff = breath(t, .55)
    for _, side in {'Left', 'Right'} do
        local e, sign = d.eyes[side], side == 'Left' and -1 or 1
        e.lidOffset = math.rad(-30); e.stalkAngles = angle(22, 0, -sign * (18 + 4 * sniff)); e.size = V(1.1, .9, 1)
    end
    d.mouth.scale = V(1.1, .7, 1.05); d.mouth.angles = angle(-10, 0, 0); d.mouth.offset = V(0, -.06, 0)
    d.body.neckAngles = angle(16 + 4 * sniff, 0, 0); d.body.torsoScale = V(1.02, .95 + .03 * sniff, 1.02)
end
M.Aliases = {
    RestlessAtomModel = 'OrbitingAtomModel', BobbingBirdbathToy = 'BobbingBirdBath',
    TopsyTurvyChessRook = 'TopsyChessRook', RestlessNutcrackerToy = 'RestlessNutcracker',
    DaydreamingSatelliteDish = 'SillySatelliteDish', FidgetingCalculator = 'FidgetCalculator',
    IndecisiveTravelStool = 'FoldingTravelStool', RestlessOrigamiCrane = 'OrigamiCrane',
    InsideOutUmbrella = 'SulkingUmbrella',
}
M.Recipes = recipes -- Root may append its two separately owned selected recipes.
M.Supported = {}
for id in pairs(recipes) do M.Supported[id] = true end
function M.Evaluate(id, age, speed)
    if type(id) ~= 'string' then return nil end
    id = M.Aliases[id] or id
    local recipe = recipes[id]
    if not recipe then return nil end
    local d = M.Identity()
    recipe(d, math.max(0, finite(age, 0)), math.clamp(finite(speed, 0) / 12, 0, 1))
    return d
end

function M.Read(player,speed)
 local now=workspace:GetServerTimeNow()
 if now>=(player:GetAttribute('DraftSelectedUntil')or 0)then return nil end
 local id=player:GetAttribute('DraftSelectedItem');local age=math.max(0,now-(player:GetAttribute('DraftSelectedStart')or now))
 local d=M.Evaluate(id,age,speed or 0);if not d then return nil end
 local a=math.clamp(age/.35,0,1);a=a*a*(3-2*a)
 local function blend(t)for key,value in t do if typeof(value)=='Vector3'then local scale=key:lower():find('scale')or key=='size'or key=='pupilSize';t[key]=(scale and Vector3.one or Vector3.zero):Lerp(value,a)elseif type(value)=='number'then t[key]=value*a elseif type(value)=='table'then blend(value)end end end
 blend(d);d.id=id;return d
end
function M.Mul(a,b)return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)end
return M
