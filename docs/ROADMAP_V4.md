# Solar Horizon: status and roadmap (v4)

**Base:** `main` @ `9247ce3` plus this zip / `solar_horizon_s2_cumulative.patch`. **172 / 172 tests pass, 0 script errors.**
Everything visual below was checked in **software-rendered** screenshots (Mesa lavapipe, 1-2 fps). Nothing has been seen on a real GPU or on the S26+ yet. Please send a spawn screenshot from your machine; it settles most open questions.

## 1. What this zip contains (on top of Slice 1)

| Area | Change | Verified by |
|---|---|---|
| Ground **missing / "wedges"** | **Root cause found:** terrain patches had no culling bounds, so Godot culled each one by its tiny flat grid box at its centre; the ground beneath and beside you vanished along straight frustum-plane edges. Patches now get bounds covering their displaced geometry | Render before/after (ground now exists under the ship, with its shadow); test |
| Terrain **skirts** | Were 3.5 km deep (40% of the tallest mountain), drawn as giant walls. Now 8 m to ~80 m | Render with skirts off / short; test guards the formula |
| Terrain **normals** | The shader never set a normal and mixed view-space and local vectors, so lighting and slope colouring were wrong. Now smooth normals from the GPU heights (facet normals on the analytic path), all lighting maths in world space | Render with normals shown as colour; sphere-normal control render lit the ground |
| Terrain **speckle** | Noise sampled at raw 600 km coordinates quantised into per-pixel static. Now uses a patch-local origin reduced in double precision | Render before/after |
| Height texture sampling | Exact 4-texel fetch (texel i = patch uv i/32); avoids stair-stepping on GPUs without linear R32F filtering | Render (no regression); not the cause of the stripes (below) |
| **Relief** | Earth max height 8.8 km -> 3.5 km, one source of truth (`BodyFrames`), guarded by a test. The old value made every region within 200 km of the spawn 5.8-8.8 km high | CPU height sampling along lines |
| **Sky** | Daytime atmosphere sky (gradient, haze, sunset tint, Mie glow, stars fade in daylight), fog, sky-lit ambient, lower glow/exposure/sun energy on the ground; outside-view atmosphere/cloud shells hide below 15 km (removes the green band); ocean sphere hidden near the ground | Renders |
| **HUD** | Apoapsis/periapsis show "--" until actually orbital | Render |
| **Tutorial** | New ground-start steps (lift off 15 km -> pulse drive -> land **on the Moon**); landing on Earth no longer completes the lunar step; key names come from the InputMap | 3 tests |
| **Touch controls** | Real multitouch flight buttons: Boost, Pulse, Lift, Down, Throttle +/-, Gear (TouchScreenButton bound to real actions), shown only in flight | Test |
| **Audio** | `AudioManager` was never created, so the game was silent. MainWorld now creates it (group `audio_manager`); the ship finds it by group. (Cannot hear it here) | Test; clean exit |
| **Tooling** | `tools/visual/capture_shots.gd` + `docs/VISUAL_TESTING.md`: screenshots without a GPU | Ran end to end |

## 2. Honest state of the look

- **Ground now exists** and is lit, but in my captures it reads as **dark navy with horizontal pale-green stripes**. The stripes are a shading/geometry artefact I could not pin down (I ruled out shadows, skirts, texel alignment and the normal source). It may be partly a software-driver effect. **This is the first thing to check on your GPU.**
- Ground colour/biomes still need art direction (grass/rock/snow palette, detail texture); distance fog tuning; plume intensity from side angles.
- **Not done:** speed-sensation VFX (dust/streaks), steering on touch (stick or gyro), thermal plugin, S26+ measurements.

## 3. Roadmap

Each sprint ends with a recorded 5-minute play session, an automated test, and a screenshot set reviewed by you.

| Sprint | Goal | Work | Exit criteria |
|---|---|---|---|
| **S2c** (next, ~1 wk) | The ground reads as ground | Find the stripe artefact on a real GPU (use your screenshot; add a debug view: normals / height / patch id); palette + detail texture + distance haze; shadow tuning; LOD seam shading | Spawn, 80 m and 3 km captures look like terrain; luminance/colour asserts in the capture tool |
| **S2d** (~1 wk) | It feels fast | Speed dust and streaks, boost FOV kick/vignette, pulse-drive tunnel, plume from the side, gear animation, engine audio levels | Captures at boost and pulse show motion cues; audio check on a device |
| **S2e** (~1 wk) | Playable on the S26+ | Touch steering (stick + gyro), HUD scale for 6.7" 3120x1440, first device run (frame ms, GPU ms, RSS, temperature at 5/10/20 min), thermal plugin, terrain depth budget (mobile LOD 8 = ~120 m vertex spacing) | Device baseline in `docs/baseline/`; 60 FPS decision made from data |
| **S3** (~2 wk) | Land on the Moon | Moon terrain + collision verified, low-gravity landing assist, EVA suit time ~10 min, atomic crafting + exported recipes, Moon lit-side look | Moon landing + EVA playthrough test |
| **S4** (~3 wk) | Warp to another star | Galaxy map, `SystemLoader` (swap `BodyRegistry`/`GravityService` to a generated system), star-class fix (all stars are class M today), per-body terrain parameters, arrival sequence | Seeded jump test; same seed gives the same system on desktop and phone |
| **S5** (~3 wk) | Reasons to play | Scanner/discovery/upload, upgrades that raise speed tiers and pulse range, outpost, simple trade | 30-minute session without dead ends |
| **S6** (~2 wk) | Release candidate | Android export in CI, soak test (2 h), crash reporting, store capture from in-engine footage | Signed build, device checklist green |

## 4. Process rules that now apply
1. Every bug fix ships with a test that fails without it (mutation-check it).
2. Every visual change ships with before/after captures (`tools/visual`).
3. No module merges unless something launches it.
4. CI runs the headless suite (~4 min) and, when available, the capture job.

## 5. Decisions needed from you
1. Day/night: fixed sun now. Add a slow cosmetic cycle near the ground, or keep fixed?
2. Mobile terrain depth vs frame budget (decide after the first S26+ run).
3. Steering on touch: virtual stick, gyro, or both?
4. Keep combat and the "Horizon Signal" story cut until after S5?
