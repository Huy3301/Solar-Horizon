# Solar Horizon — Overhaul v3: make it a game you want to play

**Repo:** `github.com/Huy3301/Solar-Horizon` `main` @ `0a26acf` (what is on GitHub; your local copy may be ahead, see §2)
**Patch:** `solar_horizon_slice1.patch` (16 files, +1,010 / −167). Applies cleanly to `0a26acf`; for a newer local copy use `git apply --3way`.
**Verified on:** Godot 4.7.2 headless. **163 / 163 tests pass, 0 script errors, ~4 minutes.** Nothing in this document has been *seen* on screen (no GPU here); §4 lists exactly what that means.

---

## 0. Straight answer

You were right to be disappointed, and part of it is on my side.

- My v1 and v2 documents were **bug registers**. They found real defects, but I never played the game the way you do: launch, look, fly. The three things you reported (starts in space, camera far away, ship slow) were all visible in my own measurements and I had filed them as low-priority notes (SH-25, SH-15) instead of leading with them.
- Worse, **the test suite could not have caught any of it.** I found that `tests/run_tests.gd` never awaited asynchronous tests, so any test that waited for physics passed without running its assertions, and a script error in a test also counted as a PASS. "154 passing" included **zero** real flight tests. That is now fixed (§3).
- The roadmap tracked *systems* (crafting, factions, tutorials). The thing that makes No Man's Sky feel good is one loop, done well: **stand on a planet, lift off, leave the atmosphere, go somewhere fast, land.** That loop is now playable in the build and covered by tests. Everything else should wait behind it.

---

## 1. What you saw, and why (all measured)

| You saw | Real cause | Evidence | Status in patch |
|---|---|---|---|
| **Starts in space** | `main.tscn` spawned the ship in a 200 km orbit; the tutorial then skipped its first two steps because the conditions were already true | spawn alt 200,000 m, v 2,182 m/s | **Fixed**: parked on the ground near Adelaide (`MainWorld.start_mode = SURFACE`; `ORBIT` still available) |
| **Camera really far** | Chase camera lerped its *position* in world space. The lag is `v·dt·(1−a)/a`: **286 m behind a 19 m ship at orbital speed**. A second, smaller lag (one physics tick, v/60) remained even with local smoothing | measured 286 m at tick 30 | **Fixed**: position rigidly attached, only orientation smoothed, updated per rendered frame from the interpolated ship transform. Test asserts < 60 m at 0 / 0.5 / 2 / 35 km/s; reverting the fix makes it fail (102 m, 1,436 m) |
| **Ship very slow** | (a) Godot's project default linear damp (0.1/s) silently braked the ship: 2,182 → 1,325 m/s in 5 s. (b) Forward-only thrust, ~0.4 rad/s² pitch, no hover assist: it flew like a rocket, not a ship. (c) `boost` and `pulse_drive` input actions were never defined, so the speed tiers could not be used. (d) Nothing in empty space to show speed | v2 SH-15, SH-23 | (a)(b)(c) **Fixed** (below). (d) **Not fixed**: needs speed-dust/star-streak VFX, see S2 |
| *(you did not report, but found)* | Takeoff counted *upward* speed as "touchdown speed" and crashed any lift-off faster than 10 m/s; the tutorial respawn teleported to a hard-coded point | traced to `abs(vspeed)` in `evaluate_landing`; respawn at (0,50,0) | **Fixed** |

---

## 2. What the patch gives you

### 2.1 Controls (new or changed)

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle up / down | `↑` / `↓` | RT / LT (unchanged) |
| **Boost** | `Shift` | L3 |
| **Pulse drive** (toggle, needs ≥ 60 km clear of any body) | `Tab` | R3 |
| **Lift / descend** (VTOL) | `Space` / `Ctrl` | A / — |
| Pitch / roll / yaw | `W`,`S` / `A`,`D` / `Q`,`E` | sticks |
| Camera | `V` | — |

**Touch (S26+): not done.** There are no on-screen Boost / Pulse buttons yet. Until they exist the phone build cannot use the new speed tiers.

### 2.2 How it flies now (default `ARCADE` mode, NMS-style)

- **Point the nose, set throttle.** Ship accelerates toward `forward × throttle × speed limit`, with a short response time. Release throttle and the ship **brakes to a hover** (grav-lift), it does not fall out of the sky.
- **Takeoff:** any throttle on the ground lifts the ship straight up at 28 m/s first, forward speed fades in as it clears 14 m. Measured: clears 15 m about 0.85 s after throttle.
- **Landing assist:** sink rate is capped as the ground approaches.
- **Direct rate control** (1.3 / 0.9 / 1.7 rad/s pitch / yaw / roll, ~0.12 s response) and **auto-level in atmosphere**. Old pitch accel was ~0.4 rad/s².
- **Speed tiers** (all exported on the ship for tuning): atmosphere cruise 220 / boost 700 m/s; space cruise 1,200 / boost 3,500 m/s; pulse drive up to 35 km/s, **auto-braking for bodies ahead** (not the one you are leaving) and disengaging at 55 km altitude; proximity cut-out at 20 km.
- **Crash is no longer permanent:** emergency recovery after 4 s.
- **Newtonian / Assisted modes remain** for sim players (`flight_model` export). They need real orbital insertion and are **not** the default. There is no in-game toggle yet.

### 2.3 Measured, scripted flight (headless, real Jolt, real `main.tscn`)

| Leg | Result |
|---|---|
| Ground start | Rests on terrain, AGL ≈ 1 m, speed ≈ 0, stays put for 10+ s while Earth moves 30 km/s |
| Takeoff | Clears 15 m in ≈ 0.85 s, no crash |
| Ground → 70 km (pitch 40°, boost) | ≈ 58 s |
| Pulse drive to the Moon | ≈ 108 s for ~3,500–3,900 km, peak 35 km/s, gravity hands over to the Moon mid-flight, arrives ~55 km above the surface at < 3 km/s, no crash |

(These are numbers from my probe; the committed test asserts safe bounds: lift-off < 4 s, 70 km < 90 s, Moon leg 20–150 s, peak > 20 km/s, arrival 20–120 km altitude and < 3 km/s.)

### 2.4 Under the hood (all required for the above)

1. **Co-moving physics frame** (`MainWorld._track_frame`): the local frame follows the dominant body, with a patched-conic velocity hand-over on SOI change (10-tick hysteresis). Without it, Earth flies away at 30 km/s and a "parked" ship falls into space (v2 SH-16).
2. **Planets do not spin under the player.** Earth is tilted by its real obliquity, and the spin phase is chosen so the sun is ~42° up in the east at spawn. (A spinning surface would slide under a parked ship at ~760 m/s.) Consequence: **no day/night cycle yet**; it needs a decision (§6).
3. **Terrain patches are drawn where they belong.** They were 642 km off (v2 SH-17) because the offset was applied twice. Now placed camera-relative in double precision, instances are top-level.
4. **Collision ring**: up to 9 collision patches around the ship (was 1, ~244 m wide, never re-positioned), positioned every tick, backface collision on.
5. **LOD and collision use height above the terrain, not above sea level.** Standing on a 2 km plateau the old code treated you as "2 km from every patch": no fine terrain, no collider. (This was found by the new tests failing.)
6. **CPU terrain = GLSL terrain.** The CPU hash function was different from the GLSL one, so collision and AGL used a completely unrelated height field from what the GPU draws (mean difference 0.33 = uncorrelated). Hash now identical (checked 500 samples, max diff 0.0); the Earth height formula was also replaced with the GLSL one (water mask removed, see §4).
7. **Spawn picker:** searches 120 (scaled) km around Adelaide for flat, low ground; ship is frozen until the collider under it exists.
8. **Ship input gating** (`input_enabled`): keys pressed on foot no longer fly the parked ship (it reached 18.9 km/s in my test).
9. **Hidden damping removed** (`DAMP_MODE_REPLACE`, project default damp 0), Jolt speed cap raised to 100 km/s, continuous collision on.
10. **Crash respawn** goes back to the real ground spawn.

### 2.5 Test harness repairs (these matter as much as the features)

- Runner now `await`s each test; async tests are real.
- `require_completion()` / `complete()`: a script error that aborts a test mid-way is reported as FAIL, not PASS.
- One-frame wait so autoloads exist; scene `_ready` timing handled.
- `SH_TEST_FILE=… SH_TEST_METHOD=…` filters (the full suite takes ~4 min because it flies 3+ minutes of simulated game).
- **Mutation checks done:** re-breaking the takeoff crash, the camera, and the patch placement each makes its test fail (and did *not* fail under the old runner).
- Also fixed the `RefCounted.free()` script error that would have made your CI red.

### 2.6 Applying it

```bash
git apply --check solar_horizon_slice1.patch && git apply solar_horizon_slice1.patch
# newer local copy:  git apply --3way solar_horizon_slice1.patch
# fast checks:       SH_TEST_FILE=test_slice1 SH_TEST_METHOD=takeoff godot --headless --path . --script res://tests/run_tests.gd
```

---

## 3. New bugs found while doing this (SH-31 …)

| ID | Sev | Finding | Status |
|---|---|---|---|
| SH-31 | S1 | CPU terrain hash ≠ GLSL hash → collision/AGL unrelated to drawn terrain | Fixed (CPU side). **GPU side unverified** |
| SH-32 | S1 | Landing evaluator used `abs(vspeed)`: every fast lift-off was a "crash" | Fixed |
| SH-33 | S1 | Test runner did not await coroutines, ignored script errors, ran before autoloads existed | Fixed |
| SH-34 | S1 | LOD/collision distance measured to a sea-level sphere (broken on any high ground) | Fixed |
| SH-35 | S2 | `GameBootstrap.respawn_player` teleported to local (0, 50, 0) with identity basis | Fixed |
| SH-36 | S2 | Single collision patch, never repositioned | Fixed (ring) |
| SH-37 | S2 | Earth's near-surface terrain is ridged noise: **no oceans, coasts, or Adelaide**; the far sphere shows real continents. Descending will show a pop | Open (needs DEM / water-mask pipeline, Phase D) |
| SH-38 | S2 | Tutorial still expects the old flow: orbit check wants 7.2 km/s or Pe > 75 km, which the arcade ship (hover, no orbit) never meets; prompt names wrong keys | Open: rewrite for ground start (S2) |
| SH-39 | S2 | Mobile quality tier caps terrain depth at 8: **122 m vertex spacing** at the ground, so it will look faceted | Open: needs on-device test and a depth/budget decision |
| SH-40 | S3 | `AudioManager` is not an autoload → game is silent; `get_sun_direction` never defined | Open (from v2 SH-24) |
| SH-41 | S3 | All stars are class M (`class` and `has_star` share one hash) | Open (v2 SH-27) |
| SH-42 | S3 | Crafting: output silently truncated into a full inventory; recipes will not load in exported builds (`.remap`) | Open (v2 SH-20/21) |
| SH-43 | S3 | Moon EVA kills the player in 45 s | Open (v2 SH-19) |

---

## 4. What I could not verify (please check these first)

I have **no GPU and no device**. These are the things that decide whether it *feels* good, and I have not seen any of them:

1. **Open the game and look at the ground at spawn.** Is terrain drawn under the ship, and does it line up with where the ship rests? My assertions prove the collider and the CPU height field agree to 0.02 m. They do **not** prove the GPU compute shader draws the same height field. If you see the ship hovering or sunk, that is SH-31 on the GPU side.
2. Patch placement in the *shader* (patches are positioned by their world transform, vertices are expressed relative to the patch centre; I believe this matches the shader but did not run it).
3. Transition from ground terrain to the far Earth sphere while climbing (SH-37 pop).
4. Whether camera distance and the 25–35% pull-back *look* right (numbers are right).
5. Boost, pulse and plume VFX; audio (silent until SH-40).
6. Everything on the S26+: frame time, thermals, touch controls, terrain faceting (SH-39).
7. Landing on the Moon (its terrain/collision path is the same code but untested).

---

## 5. The experience we are building (spec)

**The 5-minute loop, to be demonstrated every sprint:**

`stand on pad (0:00) → throttle, lift off (0:05) → climb through atmosphere, horizon curves, sky darkens (0:20) → boost out of atmosphere (1:00) → pulse to the Moon, speed streaks (1:10 – 3:00) → arrive, drop out, descend (3:30) → land on the Moon (4:30) → step out (5:00)`

**Feel targets (tunable, measured by tests):** lift-off < 1 s; atmosphere exit < 90 s with boost; Moon in ≈ 2 min; camera within 1.5× the ship's length at any speed; no phase of flight where the player waits more than ~10 s with nothing to decide.

**What No Man's Sky does that we copy:** arcade handling with assist always on; speed tiers per environment; pulse drive that auto-brakes at planets; boost on a single key; a visible speed sensation; seamless ground-to-space. **What we keep from this project's identity:** real distances/gravity data, orbital mechanics as an opt-in Sim mode, real-Sol first.

**"Warping" (not in this patch):** two levels.
- **Pulse drive (done):** inside a system.
- **Hyperjump (S4):** galaxy map from `StarCatalog`, charge, tunnel effect, arrival at a *generated* system. Needs a `SystemLoader` that swaps `BodyRegistry` contents and `GravityService` bodies for a `StarSystemGenerator` result and re-bases the origin. Prerequisites: star-class fix (SH-41), per-body terrain parameters so a generated planet can use the same terrain pipeline.

---

## 6. Roadmap v3 — playable at the end of every sprint

Rule for every sprint: **a recorded 5-minute play session and an automated test for it.** No new systems until the previous demo is fun.

| Sprint | Goal (demo) | Contents | Exit test |
|---|---|---|---|
| **S1 — done in this patch** | Ground → space → Moon, headless-proven | Everything in §2 | `test_slice1_flight` (9 tests) |
| **S2 — Feel & looks (≈ 1–2 wk)** | You enjoy flying it, on desktop | Visual check of §4 items 1–4; speed sensation (star dust, streaks, FOV kick, plume); gear retract on takeoff; engine audio (wire `AudioManager`, SH-40); **tutorial rewrite** for the ground start (SH-38); Sim-mode toggle; **touch Boost/Pulse buttons**; day/night decision | Scripted play-through; screenshots reviewed by you |
| **S3 — Land on the Moon (≈ 2 wk)** | Moon landing → EVA → mine → return | Moon terrain/collision verified; suit time ≈ 10 min (SH-43); atomic crafting + exported recipes (SH-42); scanner basics | Moon landing test; EVA test |
| **S4 — Warp to another star (≈ 3 wk)** | Jump to a generated system and land | Galaxy map, `SystemLoader`, star classes (SH-41), per-body terrain params, arrival sequence | Seeded jump test; same seed = same system on desktop and phone |
| **S5 — Reasons to play (≈ 3 wk)** | A 30-minute session with goals | Discovery/upload, upgrades that raise speed tiers and pulse range, outpost, simple trade | 30-min playtest, no dead ends |
| **S6 — S26+ pass (≈ 2 wk, start earlier for the build)** | Holds 60 FPS for 20 min on the phone | Android export in CI, thermal plugin, terrain depth budget (SH-39), draw-call / overdraw budget, real-device frame-time CSV | Device baseline in `docs/baseline/` |

**Process changes** so this does not repeat: (1) CI runs the headless flight tests on every push; (2) no module may be merged unless something launches it (the v2 orphan list: rover, flora, biome, stamper, audio, LUT atmosphere); (3) every bug fix ships with a test that fails without the fix (mutation-check it); (4) you review a screenshot/clip at the end of each sprint, not a document.

---

## 7. Decisions I need from you

| # | Decision | My recommendation |
|---|---|---|
| 1 | Default flight model: NMS-style arcade (now) vs orbital sim | Arcade default, Sim mode as an advanced toggle |
| 2 | Day/night: planets do not spin now | Rotate the sun/sky cosmetically near a planet only, or run a slow rotation with a "parked = locked to surface" rule |
| 3 | Real Adelaide vs procedural terrain near Earth | Procedural until a DEM pipeline exists; keep the Adelaide *name and heading*, not the geography |
| 4 | Scale (planet radius 1:10, distances 1:100): atmosphere exit ~1 min, Moon ~2 min feel good; interstellar needs hyperjump anyway | Keep |
| 5 | Mobile terrain depth vs frame budget (SH-39) | Decide after S2 device capture |
| 6 | Combat / "Horizon Signal" story | Still cut |
