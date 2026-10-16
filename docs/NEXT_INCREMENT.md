# Solar Horizon — Next increment (S2): the first five minutes must look and feel right

**Base:** `main` @ `9247ce3` (your push of the Slice 1 zip). **Evidence:** this time I rendered the game (software Vulkan, see `docs/VISUAL_TESTING.md`) as well as running it headless. Screenshots are in `screens/`.
**Honest limits:** software rendering runs at 1-2 fps, so I can judge *what things look like*, not speed, smoothness, thermals, or whether the GPU compute terrain path matches. Please send me one screenshot of your own spawn view (see §6): it is the fastest way to find out whether your GPU shows the same thing.

---

## S2a status (executed)

| Item | Result | Evidence |
|---|---|---|
| Daytime sky from inside the atmosphere (V2) | **Done.** Blue gradient sky, horizon haze, sunset tint, stars fade in daylight, fog, sky-lit ambient; the outside-view atmosphere/cloud shells hide below 15 km (that also removes the green band) | `screens/s2a_spawn_final.png` |
| Terrain "walls" and blue wedges | **Root cause found and fixed.** They were the terrain *skirts*: 3.5 km deep (40% of the tallest mountain). Now sized to cover LOD cracks only (8 m up to ~80 m). The ocean sphere was also drawn over the ground and is hidden near it. My earlier winding theory was wrong and is not in the code | renders with skirts off / short skirts; test guards the formula |
| HUD readouts on the ground (V5) | **Done.** Apoapsis/Periapsis show "--" until you are actually orbital | `s2a_spawn_final.png` |
| Tutorial for the ground start | **Done.** New steps: lift off (15 km) -> pulse drive -> land **on the Moon** (landing on Earth no longer completes the lunar step); all key names come from the InputMap | 3 new tests |
| Engine plume (V4) | **Checked, not changed.** It is a proper shader plume; the "two big spheres" were the cones seen end-on from behind. Needs a side-angle capture before touching intensity | code read |
| Ground texture (V3) | **Still open.** The ground now reads as pale speckled snow; colour/lighting need work (WP-A2) | `s2a_spawn_final.png` |

Tests: 168 / 168, 0 script errors. Everything rendered via software Vulkan; real-GPU confirmation still needed.

---

## 1. What the renders show

| # | Finding | Evidence | Status |
|---|---|---|---|
| V1 | **Blue wedges and hard diagonal edges over the ground.** Cause: the whole-planet ocean sphere draws over the terrain (it is meant for viewing from space). Hiding it removes them; the terrain beneath is continuous | `before_01`, `after_03`; also isolated by hiding terrain / clouds / atmosphere / ocean one at a time | **Fixed** (`planet_runtime.gd`: ocean hidden below the far-LOD transition) + test (fails if reverted) |
| V2 | **No daytime sky.** Standing on the ground in full sun the sky is black stars with a green band at the horizon. The atmosphere shells are built for the outside view; nothing paints sky from inside the atmosphere. The Hillaire LUT atmosphere and cloud shaders in the repo are not used by any material | `after_03` | **Open, biggest visual gap** |
| V3 | **Ground texture is black/white speckle.** It reads as static noise, not rock or soil: no colour, no light/shade, no slope variation. Likely the albedo array / triplanar scale or missing textures; needs a look | `after_03` | Open |
| V4 | **Engine plume is two big translucent white spheres** (takeoff) | `before_02` | Open |
| V5 | **HUD:** mission banner overlaps the telemetry; prompt still says "Throttle Up [Shift]" (it is the Up arrow; Shift is boost); on the ground it shows Apoapsis -0.0 km / Periapsis -637 km, which means nothing in hover flight | all HUD shots | Open |
| V6 | **Space and orbit look good**: atmosphere limb glow, sun glare, nebula and stars. Keep and protect this | `orbit_04` | OK |
| V7 | **Moon renders as a black disc** from 90 km on the Earth-facing side. This may simply be the unlit side at that time; not proven either way | `moon_05` | Needs a lit-side check |
| V8 | **Engine errors on the Vulkan path:** 98 x "Texture (binding 1) is not a valid texture" + "Parameter us is null", and leaked RIDs at exit. The GPU height generator creates a texture and uniform set per patch and never frees them, and results are not checked for validity. May be partly a software-driver artefact; the leak is real regardless | `/tmp` log, code reading of `gpu_height_generator.gd` | Open |
| V9 | A hard-edged lighter region at one side of the ground (patch/LOD seam shading) | `after_03` | Open |

**A correction on my side.** I first believed the ground itself was invisible because every terrain triangle looked back-face-culled (my numeric check said so) and I changed the winding. Rendering the old and new versions side by side showed **no difference**, so the check was wrong; I reverted that change and it is not in the patch. The wedges were the ocean all along. This is exactly why I now render instead of reasoning.

---

## 2. Goal of the increment

> Someone launches the game and, within 60 seconds, thinks "that is a planet, and flying it feels good", on desktop and on an S26+.

Everything below serves that. No new gameplay systems until this holds.

---

## 3. Work packages (in priority order)

Sizes: S = 1-2 days, M = 3-5 days, L = 1-2 weeks, solo with AI assistance.

### WP-A: The ground and the sky (the first thing anyone sees) - M/L
1. **Daytime sky from inside the atmosphere** (V2): a sky shader driven by sun direction and altitude: blue gradient, sun disc, horizon haze, stars fading in as altitude rises, fully dark by ~100 km. Start with the cheap analytic version; promote the Hillaire LUT shader behind the quality tier only if it fits the S26+ budget.
2. **Terrain surface** (V3, V9): find out why the albedo is noise (assets, array indices, triplanar scale, mip bias); colour by altitude/slope/latitude; sun-lit shading; fix LOD seam shading. Add distance haze so far terrain fades into the sky.
3. **Remove the green band** (shell shader seen from inside) by switching the shell off or making it inside-aware.
- **Acceptance:** captured frames at spawn, 80 m, 3 km and 30 km show a lit blue sky, a coloured lit ground, and no hard seams. A CI check on the capture: sky region mean luminance and blue-dominance above a threshold, ground region not near-black/near-white with bounded variance; before/after images attached to the PR.

### WP-B: Ship feel you can see - M
1. Engine plume: replace the sphere meshes with a flame cone / additive sprite stack scaled by `arcade_thrust_fraction` (V4).
2. **Speed sensation:** space dust, speed streaks, FOV kick and slight vignette on boost, pulse-drive tunnel effect (the biggest "it feels fast" lever in empty space).
3. Gear retracts on takeoff; engine audio via the missing `AudioManager` autoload (the game is currently silent).
4. **HUD cleanup (V5):** non-overlapping layout; in atmosphere show AGL, vertical speed, ground speed, throttle, boost/pulse state; show orbit data only above the atmosphere; every key prompt generated from `InputMap` so it cannot drift.
- **Acceptance:** capture shows plume, streaks at boost, clean HUD; a test asserts every prompt string names a key that exists in `InputMap` for that action.

### WP-C: Controls on the S26+ - M
Touch flight HUD: throttle slider, **Boost** and **Pulse** buttons, lift/descend, aim stick or gyro; gamepad mapping check; in-game Sim/Arcade toggle. Today the touch scene only has on-foot buttons (jump, jetpack, interact, scan, visor), so the phone build cannot use boost or pulse at all.
- **Acceptance:** scripted touch-event test drives takeoff -> boost -> pulse on the touch scene; on-device checklist (§5).

### WP-D: Tutorial for the ground start - S/M
Rewrite the steps for: lift off, climb, leave atmosphere, pulse to the Moon, descend. Thresholds from `GameScale`, key text from `InputMap`, skippable. Today the orbit step demands 7.2 km/s or Pe > 75 km, which the arcade ship never meets, so the tutorial would stall after step 1.
- **Acceptance:** a headless playthrough completes every step; no step completes at spawn.

### WP-E: Land on the Moon - M/L (start once A-C land)
Moon collision/terrain verified (same code path, untested), landing assist tuned for low gravity, EVA suit time ~10 min (was 45 s), atomic crafting. Check the lit-side look (V7).

### WP-F: GPU hygiene and the first device run - M
Free/validate every RD texture, uniform set and shader; fail loudly if a resource is invalid (V8). First S26+ capture: frame time, GPU time, RSS, temperature at 5/10/20 min, terrain depth and faceting at the ground (mobile caps LOD depth at 8 = ~122 m vertex spacing, which will look faceted).

### WP-G: Keep it honest - S
CI job that runs the visual capture under software Vulkan and uploads the PNGs; "no module without a launcher" rule (rover, flora, biome, stamper, LUT atmosphere are still orphans); docs updated each sprint.

---

## 4. Suggested split

| Slice | Contents | Demo |
|---|---|---|
| **S2a (this week)** | WP-A1 + A3 (sky), WP-B1 + B4 (plume, HUD), WP-D (tutorial) | Spawn shows a blue sky and a lit ground; takeoff reads clearly |
| **S2b** | WP-A2 (terrain look), WP-B2/B3 (speed sensation, audio), WP-C (touch) | Fast, loud, playable on the phone |
| **S2c** | WP-F (device run, GPU hygiene), WP-G | Measured S26+ baseline; CI posts screenshots |
| **S3** | WP-E (Moon), then the interstellar warp work from `docs/OVERHAUL_V3.md` | Land on the Moon, then jump to another star |

---

## 5. How we will verify (three layers)

1. **Headless logic tests** (exist, 164): physics, frame, flight, input actions, camera, respawn, ocean visibility.
2. **Visual captures** (new, `tools/visual/capture_shots.gd`): PNGs of spawn, takeoff, climb, space, Moon, with luminance/colour assertions where objective, and human review where not.
3. **Device run** (manual, S26+): checklist: spawn view matches the capture; takeoff < 1 s; no hitching while climbing; boost/pulse buttons work; frame time and temperature logged; terrain at ground level acceptable.

## 6. What I need from you

1. **A screenshot of the spawn on your PC** (and one mid-climb if you can). It tells me whether the GPU terrain path looks like my captures, which I cannot see from here.
2. Whether the **green band** and the **speckle ground** look the same on your machine.
3. Day/night: keep the planet fixed with a fixed sun (now), or add a slow cosmetic cycle near the ground?
4. Do you want the S26+ touch HUD built before or after the sky/ground look? (I recommend after, because the look decides whether it is worth playing.)
