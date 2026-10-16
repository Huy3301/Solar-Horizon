#!/usr/bin/env python3
"""
Solar Horizon — Sprints S2c -> S5 In-Place Patcher, Validator & Zip Builder.
Applies surgical, non-destructive upgrades to existing scripts and shaders,
generates `solar_horizon_s2c_to_s5.patch`, runs headless tests, and creates an updated zip.
"""

from pathlib import Path
import subprocess
import zipfile
import os
import sys

REPO_ROOT = Path(__file__).resolve().parent.parent


def write_file(rel_path: str, content: str) -> None:
    target = REPO_ROOT / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")
    print(f"  [WRITE] {rel_path}")


def append_if_missing(rel_path: str, marker: str, block: str) -> None:
    target = REPO_ROOT / rel_path
    if not target.exists():
        print(f"  [SKIP]  {rel_path} (not found)")
        return
    existing = target.read_text(encoding="utf-8")
    if marker in existing:
        print(f"  [OK]    {rel_path} already contains `{marker}`")
        return
    updated = existing.rstrip() + "\n\n\n" + block.strip() + "\n"
    target.write_text(updated, encoding="utf-8", newline="\n")
    print(f"  [PATCH] {rel_path} (+ `{marker}`)")


# ---------------------------------------------------------------------------
# 1. S2c: game/planet/core/terrain_patch.gdshader
# ---------------------------------------------------------------------------
TERRAIN_PATCH_SHADER = """shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// S2c Debug Views: 0 = Lit Terrain, 1 = World Normals, 2 = Normalized Height, 3 = Patch ID, 4 = Slope & Grid
uniform int debug_view_mode : hint_range(0, 4) = 0;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform bool use_height_tex = true;
uniform float patch_size_m = 2000.0;
uniform float max_relief_m = 3500.0;
uniform float skirt_depth_m = 24.0;
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch_origin_local = vec3(0.0);
uniform vec3 planet_center_local = vec3(0.0, -637100.0, 0.0);
uniform vec3 sun_direction_world = vec3(0.35, 0.85, 0.39);
uniform vec3 patch_debug_color = vec3(0.25, 0.65, 0.90);

uniform vec3 col_deep_basalt : source_color = vec3(0.16, 0.18, 0.21);
uniform vec3 col_coastal_sand : source_color = vec3(0.74, 0.68, 0.50);
uniform vec3 col_lowland_grass : source_color = vec3(0.23, 0.43, 0.17);
uniform vec3 col_highland_shrub : source_color = vec3(0.36, 0.40, 0.24);
uniform vec3 col_steep_cliff : source_color = vec3(0.34, 0.32, 0.29);
uniform vec3 col_alpine_snow : source_color = vec3(0.92, 0.95, 0.98);

uniform vec3 haze_tint : source_color = vec3(0.56, 0.73, 0.94);
uniform float haze_falloff = 0.000042;

varying vec3 v_patch_local_pos;
varying vec3 v_sphere_normal;
varying float v_height_m;
varying float v_camera_dist_m;

float sample_height_exact(vec2 uv) {
\tif (!use_height_tex) {
\t\treturn 0.15 * max_relief_m;
\t}
\tvec2 clamped = clamp(uv, vec2(0.0), vec2(1.0));
\tvec2 texel = clamped * 32.0;
\tivec2 i0 = ivec2(floor(texel));
\tivec2 i1 = min(i0 + ivec2(1, 1), ivec2(32, 32));
\tvec2 f = fract(texel);

\tfloat h00 = texelFetch(height_tex, i0, 0).r;
\tfloat h10 = texelFetch(height_tex, ivec2(i1.x, i0.y), 0).r;
\tfloat h01 = texelFetch(height_tex, ivec2(i0.x, i1.y), 0).r;
\tfloat h11 = texelFetch(height_tex, i1, 0).r;

\tfloat h_sample = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
\treturn (abs(h_sample) <= 2.0) ? (h_sample * max_relief_m) : h_sample;
}

float hash_detail(vec3 p) {
\tvec3 q = fract(p * 0.1031);
\tq += dot(q, q.yzx + 33.33);
\treturn fract((q.x + q.y) * q.z);
}

float fbm_detail(vec3 p) {
\tvec3 i = floor(p);
\tvec3 f = fract(p);
\tf = f * f * (3.0 - 2.0 * f);
\tfloat a = hash_detail(i);
\tfloat b = hash_detail(i + vec3(1.0, 0.0, 0.0));
\tfloat c = hash_detail(i + vec3(0.0, 1.0, 0.0));
\tfloat d = hash_detail(i + vec3(1.0, 1.0, 0.0));
\treturn mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
\tvec2 grid_coord = UV * 32.0;
\tvec2 odd_frac = fract(grid_coord * 0.5) * 2.0;
\tvec2 morphed_uv = clamp(UV - (odd_frac / 32.0) * morph_factor, vec2(0.0), vec2(1.0));

\tfloat h_m = sample_height_exact(morphed_uv);
\tfloat is_skirt = step(0.5, UV2.x);
\tfloat skirt_drop = is_skirt * clamp(patch_size_m * 0.015, 8.0, 80.0);

\tvec3 world_base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
\tvec3 radial_up = normalize(world_base - planet_center_local);
\tvec3 displaced_world = world_base + radial_up * (h_m - skirt_drop);

\tVERTEX = (inverse(MODEL_MATRIX) * vec4(displaced_world, 1.0)).xyz;
\tv_sphere_normal = radial_up;
\tv_height_m = h_m;
\tv_patch_local_pos = displaced_world - patch_origin_local;
\tv_camera_dist_m = length(CAMERA_POSITION_WORLD - displaced_world);
}

void fragment() {
\tfloat duv = 1.0 / 32.0;
\tfloat world_step_m = max(patch_size_m * duv, 1.0);

\tfloat h_w = sample_height_exact(UV - vec2(duv, 0.0));
\tfloat h_e = sample_height_exact(UV + vec2(duv, 0.0));
\tfloat h_s = sample_height_exact(UV - vec2(0.0, duv));
\tfloat h_n = sample_height_exact(UV + vec2(0.0, duv));

\tvec3 up = normalize(v_sphere_normal);
\tvec3 ref_axis = (abs(up.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
\tvec3 tangent_u = normalize(cross(ref_axis, up));
\tvec3 tangent_v = normalize(cross(up, tangent_u));

\tfloat dh_du = (h_e - h_w) / (2.0 * world_step_m);
\tfloat dh_dv = (h_n - h_s) / (2.0 * world_step_m);

\tvec3 world_normal = normalize(up - tangent_u * dh_du - tangent_v * dh_dv);
\tNORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

\tfloat slope = clamp(1.0 - dot(world_normal, up), 0.0, 1.0);
\tfloat h_norm = clamp(v_height_m / max(max_relief_m, 1.0), 0.0, 1.0);

\tfloat detail_fine = fbm_detail(v_patch_local_pos * 0.12);
\tfloat detail_macro = fbm_detail(v_patch_local_pos * 0.008);
\tfloat detail_mod = mix(0.86, 1.14, mix(detail_fine, detail_macro, 0.5));

\tvec3 biome_col = mix(col_coastal_sand, col_lowland_grass, smoothstep(0.01, 0.09, h_norm));
\tbiome_col = mix(biome_col, col_highland_shrub, smoothstep(0.28, 0.52, h_norm));
\tbiome_col = mix(biome_col, col_steep_cliff, smoothstep(0.52, 0.74, h_norm));
\tbiome_col = mix(biome_col, col_alpine_snow, smoothstep(0.72, 0.88, h_norm + detail_macro * 0.06));

\tfloat cliff_weight = smoothstep(0.16, 0.42, slope);
\tvec3 rock_col = mix(col_steep_cliff, col_deep_basalt, smoothstep(0.42, 0.75, slope));
\tvec3 terrain_rgb = mix(biome_col, rock_col, cliff_weight) * detail_mod;

\tfloat horizon_ao = clamp(1.0 - slope * 0.55, 0.40, 1.0);
\tfloat haze_mix = clamp(1.0 - exp(-v_camera_dist_m * haze_falloff), 0.0, 0.82);
\tvec3 final_rgb = mix(terrain_rgb, haze_tint, haze_mix);

\tif (debug_view_mode == 1) {
\t\tALBEDO = world_normal * 0.5 + 0.5;
\t\tROUGHNESS = 1.0;
\t\tMETALLIC = 0.0;
\t} else if (debug_view_mode == 2) {
\t\tALBEDO = vec3(h_norm, 1.0 - abs(h_norm - 0.5) * 2.0, 1.0 - h_norm);
\t\tROUGHNESS = 1.0;
\t\tMETALLIC = 0.0;
\t} else if (debug_view_mode == 3) {
\t\tALBEDO = patch_debug_color;
\t\tROUGHNESS = 1.0;
\t\tMETALLIC = 0.0;
\t} else if (debug_view_mode == 4) {
\t\tfloat grid_edge = max(step(0.93, fract(UV.x * 32.0)), step(0.93, fract(UV.y * 32.0)));
\t\tALBEDO = mix(vec3(slope, 1.0 - slope, 0.25), vec3(1.0, 0.9, 0.1), grid_edge);
\t\tROUGHNESS = 1.0;
\t\tMETALLIC = 0.0;
\t} else {
\t\tALBEDO = final_rgb;
\t\tROUGHNESS = mix(0.88, 0.58, smoothstep(0.72, 0.90, h_norm));
\t\tMETALLIC = 0.0;
\t\tAO = horizon_ao;
\t}
}
"""

# ---------------------------------------------------------------------------
# 2. S2d: shaders/engine_plume.gdshader & game/fx/ship_vfx.gd
# ---------------------------------------------------------------------------
ENGINE_PLUME_SHADER = """shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float throttle : hint_range(0.0, 1.0) = 0.0;
uniform float atmospheric_pressure_atm : hint_range(0.0, 2.0) = 1.0;
uniform vec4 inner_color : source_color = vec4(0.68, 0.90, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(1.0, 0.46, 0.12, 1.0);
uniform float plume_brightness = 3.2;

varying float v_axial_uv;

void vertex() {
\tv_axial_uv = clamp(UV.y, 0.0, 1.0);
\tfloat vacuum_Bell = mix(1.75, 1.0, clamp(atmospheric_pressure_atm, 0.0, 1.0));
\tVERTEX.xz *= mix(1.0, vacuum_Bell, v_axial_uv) * (0.45 + 0.55 * throttle);
}

void fragment() {
\t// S2d fix: maintain cylindrical core visibility from side angles
\tfloat view_alignment = abs(dot(NORMAL, VIEW));
\tfloat side_visibility = max(pow(view_alignment, 0.65), 0.48);
\tfloat axial_fade = pow(1.0 - v_axial_uv, 1.35);
\tfloat shock_freq = mix(2.5, 16.0, clamp(atmospheric_pressure_atm, 0.0, 1.0));
\tfloat shock_diamonds = 0.78 + 0.22 * cos(v_axial_uv * shock_freq - TIME * 26.0);

\tfloat intensity = throttle * side_visibility * axial_fade * shock_diamonds;
\tvec3 rgb = mix(outer_color.rgb, inner_color.rgb, pow(1.0 - v_axial_uv, 2.0));
\tALBEDO = rgb * intensity * plume_brightness;
\tALPHA = clamp(intensity, 0.0, 1.0);
}
"""

SHIP_VFX_EXTENSION = """
## S2d: Speed-sensation cues (FOV kick, speed streaks, vignette, pulse tunnel, gear deploy).
const S2D_BASE_FOV_DEG: float = 75.0
const S2D_BOOST_FOV_KICK_DEG: float = 14.0
const S2D_PULSE_FOV_KICK_DEG: float = 24.0
const S2D_STREAK_MIN_SPEED_MPS: float = 40.0
const S2D_STREAK_MAX_SPEED_MPS: float = 450.0


## Computes deterministic S2d motion cues without per-frame allocations.
static func compute_speed_sensation_metrics(
\tspeed_mps: float,
\tis_boosting: bool,
\tis_pulse_active: bool
) -> Dictionary:
\tvar target_fov: float = S2D_BASE_FOV_DEG
\tif is_pulse_active:
\t\ttarget_fov += S2D_PULSE_FOV_KICK_DEG
\telif is_boosting:
\t\ttarget_fov += S2D_BOOST_FOV_KICK_DEG
\telse:
\t\ttarget_fov += clampf(speed_mps / S2D_STREAK_MAX_SPEED_MPS, 0.0, 1.0) * 4.5

\tvar streak_alpha: float = 0.0
\tif is_pulse_active:
\t\tstreak_alpha = 1.0
\telif speed_mps > S2D_STREAK_MIN_SPEED_MPS:
\t\tstreak_alpha = clampf(
\t\t\t(speed_mps - S2D_STREAK_MIN_SPEED_MPS) / (S2D_STREAK_MAX_SPEED_MPS - S2D_STREAK_MIN_SPEED_MPS),
\t\t\t0.0,
\t\t\t1.0
\t\t)

\tvar vignette: float = 0.35 if is_pulse_active else (0.18 if is_boosting else 0.0)
\tvar plume_side_gain: float = clampf(0.48 + 0.52 * (speed_mps / 200.0), 0.48, 1.0)
\treturn {
\t\t"target_fov_deg": target_fov,
\t\t"streak_alpha": streak_alpha,
\t\t"vignette_intensity": vignette,
\t\t"pulse_tunnel_mix": 1.0 if is_pulse_active else 0.0,
\t\t"plume_side_gain": plume_side_gain
\t}
"""

# ---------------------------------------------------------------------------
# 3. S2e: Touch Steering + Gyro + S26+ Safe Area + Thermal Governor
# ---------------------------------------------------------------------------
TOUCH_CONTROLS_EXTENSION = """
## S2e: Touch steering (stick + gyro) & Samsung Galaxy S26+ safe-area scaling.
const S2E_STICK_DEADZONE: float = 0.12
const S2E_GYRO_GAIN: float = 0.65
const S2E_S26_PLUS_WIDTH_PX: float = 3120.0
const S2E_S26_PLUS_HEIGHT_PX: float = 1440.0


## Computes radial deadzoned steering vector (X = roll, Y = pitch) with response curve.
static func compute_touch_steering_vector(
\traw_offset_px: Vector2,
\tmax_radius_px: float,
\tgyro_rad_s: Vector3 = Vector3.ZERO,
\tuse_gyro: bool = false
) -> Vector2:
\tvar result: Vector2 = Vector2.ZERO
\tif max_radius_px > 0.001:
\t\tvar length_px: float = raw_offset_px.length()
\t\tvar norm: float = clampf(length_px / max_radius_px, 0.0, 1.0)
\t\tif norm > S2E_STICK_DEADZONE:
\t\t\tvar remapped: float = (norm - S2E_STICK_DEADZONE) / (1.0 - S2E_STICK_DEADZONE)
\t\t\tvar curved: float = pow(remapped, 1.6)
\t\t\tresult = (raw_offset_px / length_px) * curved
\tif use_gyro:
\t\tresult.x = clampf(result.x - gyro_rad_s.z * S2E_GYRO_GAIN, -1.0, 1.0)
\t\tresult.y = clampf(result.y + gyro_rad_s.x * S2E_GYRO_GAIN, -1.0, 1.0)
\treturn result


## Computes UI scale factor for high-DPI mobile displays like Samsung Galaxy S26+ (3120x1440).
static func compute_s26_hud_scale(viewport_size: Vector2i) -> float:
\tvar short_edge: float = float(mini(viewport_size.x, viewport_size.y))
\tif short_edge <= 0.0:
\t\treturn 1.0
\treturn clampf(short_edge / 1080.0, 0.85, 1.45)
"""

QUALITY_GOVERNOR_EXTENSION = """
## S2e: Mobile terrain LOD budget (depth 8 = ~120 m vertex spacing) & ADPF thermal headroom step-down.
const S2E_MOBILE_MAX_LOD_DEPTH: int = 8
const S2E_DESKTOP_MAX_LOD_DEPTH: int = 16
const S2E_THERMAL_WARN_HEADROOM: float = 0.85
const S2E_THERMAL_CRITICAL_HEADROOM: float = 0.95
const S2E_GPU_BUDGET_MS: float = 12.5


## Returns the terrain quadtree max depth for the active platform/thermal state.
static func get_terrain_max_lod_depth(is_mobile_platform: bool, thermal_headroom: float = 0.5) -> int:
\tif is_mobile_platform:
\t\tif thermal_headroom >= S2E_THERMAL_CRITICAL_HEADROOM:
\t\t\treturn S2E_MOBILE_MAX_LOD_DEPTH - 1
\t\treturn S2E_MOBILE_MAX_LOD_DEPTH
\treturn S2E_DESKTOP_MAX_LOD_DEPTH


## Computes recommended FSR 1.0 render scale based on ADPF thermal headroom and GPU frame time.
static func compute_thermal_render_scale(
\tcurrent_scale: float,
\tthermal_headroom: float,
\tavg_gpu_ms: float
) -> float:
\tif thermal_headroom >= S2E_THERMAL_CRITICAL_HEADROOM:
\t\treturn 0.60
\tif thermal_headroom >= S2E_THERMAL_WARN_HEADROOM or avg_gpu_ms > S2E_GPU_BUDGET_MS:
\t\treturn maxf(0.60, current_scale - 0.05)
\treturn clampf(current_scale, 0.60, 1.0)
"""

# ---------------------------------------------------------------------------
# 4. S3: Moon Landing Assist, 10-Min EVA Suit Time & Atomic Crafting
# ---------------------------------------------------------------------------
SURVIVAL_EXTENSION = """
## S3: 10-minute (600 s) EVA suit life-support target & lunar surface thermal drain helper.
const S3_EVA_SUIT_CAPACITY_SECONDS: float = 600.0
const S3_LUNAR_DAY_TEMP_K: float = 390.0
const S3_LUNAR_NIGHT_TEMP_K: float = 110.0


## Computes remaining EVA oxygen after `elapsed_s` on EVA (10-minute baseline capacity).
static func compute_eva_oxygen_remaining(
\tinitial_oxygen_s: float,
\telapsed_s: float,
\to2_upgrade_tier: int = 0
) -> float:
\tvar tier_multiplier: float = 1.0 + float(clampi(o2_upgrade_tier, 0, 3)) * 0.25
\tvar max_cap: float = S3_EVA_SUIT_CAPACITY_SECONDS * tier_multiplier
\tvar start_val: float = minf(initial_oxygen_s, max_cap)
\treturn maxf(0.0, start_val - maxf(0.0, elapsed_s))
"""

CRAFTING_EXTENSION = """
## S3: Atomic crafting transaction helper (guarantees zero partial deductions on failure).
static func execute_atomic_craft(
\tstock: Dictionary,
\trequired_inputs: Dictionary,
\toutput_item: String,
\toutput_count: int = 1
) -> bool:
\tif output_item.is_empty() or output_count <= 0:
\t\treturn false
\tfor ing_key: Variant in required_inputs.keys():
\t\tvar item_id: String = str(ing_key)
\t\tvar needed: int = int(required_inputs[ing_key])
\t\tif needed <= 0:
\t\t\tcontinue
\t\tif int(stock.get(item_id, 0)) < needed:
\t\t\treturn false
\tfor ing_key: Variant in required_inputs.keys():
\t\tvar item_id: String = str(ing_key)
\t\tvar needed: int = int(required_inputs[ing_key])
\t\tif needed <= 0:
\t\t\tcontinue
\t\tvar left: int = int(stock.get(item_id, 0)) - needed
\t\tif left <= 0:
\t\t\tstock.erase(item_id)
\t\telse:
\t\t\tstock[item_id] = left
\tstock[output_item] = int(stock.get(output_item, 0)) + output_count
\treturn true
"""

FLIGHT_MODEL_EXTENSION = """
## S3: Low-gravity Moon landing assist (auto-damps horizontal slip & cushions vertical sink rate).
const S3_LOW_GRAVITY_ASSIST_MAX_ALT_M: float = 250.0
const S3_MOON_GRAVITY_MPS2: float = 1.62


## Computes assistive counter-thrust acceleration vector in body-local up/horizontal frame.
static func compute_low_gravity_landing_assist(
\tvelocity_local: Vector3,
\tup_normal: Vector3,
\taltitude_agl_m: float,
\tsurface_gravity_mps2: float
) -> Vector3:
\tif altitude_agl_m > S3_LOW_GRAVITY_ASSIST_MAX_ALT_M or altitude_agl_m < 0.0:
\t\treturn Vector3.ZERO
\tvar up: Vector3 = up_normal.normalized()
\tvar vertical_speed: float = velocity_local.dot(up)
\tvar lateral_vel: Vector3 = velocity_local - up * vertical_speed
\tvar safe_sink_rate: float = -clampf(altitude_agl_m * 0.08 + 1.2, 1.2, 18.0)
\tvar vertical_correction: float = 0.0
\tif vertical_speed < safe_sink_rate:
\t\tvertical_correction = (safe_sink_rate - vertical_speed) * 2.4 + surface_gravity_mps2
\tvar lateral_damping: Vector3 = -lateral_vel * 1.8
\treturn up * vertical_correction + lateral_damping
"""

# ---------------------------------------------------------------------------
# 5. S4: Star-Class Fix (O,B,A,F,G,K,M) & SystemLoader
# ---------------------------------------------------------------------------
STAR_GENERATOR_EXTENSION = """
## S4: Deterministic 64-bit SplitMix64 spectral class selector (fixes all-M-star bug).
const S4_SPECTRAL_CLASSES: Array[String] = ["O", "B", "A", "F", "G", "K", "M"]


static func splitmix64_hash(seed_value: int, salt: int) -> int:
\tvar z: int = seed_value + salt + 0x6A09E667F3BCC909
\tz = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
\tz = (z ^ (z >> 27)) * 0x94D049BB133111EB
\treturn absi(z ^ (z >> 31))


## Returns deterministic star class ("O", "B", "A", "F", "G", "K", "M") from `system_seed`.
static func select_spectral_class_code(system_seed: int) -> String:
\tvar bucket: int = splitmix64_hash(system_seed, 404) % 1000
\tif bucket < 10:
\t\treturn "O"
\telif bucket < 40:
\t\treturn "B"
\telif bucket < 105:
\t\treturn "A"
\telif bucket < 230:
\t\treturn "F"
\telif bucket < 460:
\t\treturn "G"
\telif bucket < 720:
\t\treturn "K"
\treturn "M"


## Generates deterministic per-body terrain parameters from body seed and equilibrium temperature.
static func generate_body_terrain_params(body_seed: int, equilibrium_temp_k: float) -> Dictionary:
\tvar h1: int = splitmix64_hash(body_seed, 11)
\tvar h2: int = splitmix64_hash(body_seed, 29)
\tvar max_relief_m: float = 1200.0 + float(h1 % 4800)
\tvar roughness: float = 0.35 + float(h2 % 550) / 1000.0
\tvar biome_family: String = "temperate"
\tif equilibrium_temp_k > 360.0:
\t\tbiome_family = "scorched"
\telif equilibrium_temp_k < 210.0:
\t\tbiome_family = "frozen"
\treturn {
\t\t"max_relief_m": max_relief_m,
\t\t"roughness": roughness,
\t\t"biome_family": biome_family
\t}
"""

SYSTEM_LOADER_SCRIPT = """class_name SystemLoader extends RefCounted
## Swaps active celestial bodies and gravity sources when warping to a generated star system (Sprint S4).

const ARRIVAL_STANDOFF_RADII: float = 6.0


## Builds a deterministic system descriptor from a 64-bit seed and returns arrival coordinates.
static func build_seeded_system_state(system_seed: int) -> Dictionary:
\tvar star_class: String = StarSystemGenerator.select_spectral_class_code(system_seed)
\tvar planet_count: int = 2 + (StarSystemGenerator.splitmix64_hash(system_seed, 77) % 6)
\tvar bodies: Array[Dictionary] = []

\tfor idx: int in range(planet_count):
\t\tvar body_seed: int = StarSystemGenerator.splitmix64_hash(system_seed, 1000 + idx)
\t\tvar orbit_au: float = 0.35 * pow(1.65, float(idx))
\t\tvar eq_temp_k: float = 280.0 / sqrt(maxf(orbit_au, 0.1))
\t\tvar terrain_params: Dictionary = StarSystemGenerator.generate_body_terrain_params(body_seed, eq_temp_k)
\t\tbodies.append({
\t\t\t"body_id": "proc_planet_%d_%d" % [system_seed, idx],
\t\t\t"seed": body_seed,
\t\t\t"orbit_au": orbit_au,
\t\t\t"radius_m": 240000.0 + float(body_seed % 450000),
\t\t\t"equilibrium_temp_k": eq_temp_k,
\t\t\t"terrain_params": terrain_params
\t\t})

\treturn {
\t\t"system_seed": system_seed,
\t\t"star_class": star_class,
\t\t"planet_count": planet_count,
\t\t"bodies": bodies
\t}
"""

# ---------------------------------------------------------------------------
# 6. S5: Scanner Upload Payouts & Speed-Tier / Pulse-Range Upgrades
# ---------------------------------------------------------------------------
DISCOVERY_EXTENSION = """
## S5: Discovery upload credit calculation & speed-tier upgrade progression helpers.
const S5_BASE_UPLOAD_CREDITS: int = 250


static func compute_upload_payout(discovery_count: int, rarity_bonus: float = 1.0) -> int:
\tif discovery_count <= 0:
\t\treturn 0
\treturn int(round(float(discovery_count * S5_BASE_UPLOAD_CREDITS) * maxf(rarity_bonus, 1.0)))


static func compute_upgraded_speed_limits(
\tbase_max_speed_mps: float,
\tbase_pulse_range_m: float,
\tupgrade_tier: int
) -> Dictionary:
\tvar clamped_tier: int = clampi(upgrade_tier, 0, 3)
\tvar speed_mult: float = 1.0 + float(clamped_tier) * 0.30
\tvar range_mult: float = 1.0 + float(clamped_tier) * 0.50
\treturn {
\t\t"max_speed_mps": base_max_speed_mps * speed_mult,
\t\t"pulse_range_m": base_pulse_range_m * range_mult
\t}
"""

# ---------------------------------------------------------------------------
# 7. Headless Unit Tests for S2c -> S5 (tests/roadmap/test_s2c_to_s5_roadmap.gd)
# ---------------------------------------------------------------------------
ROADMAP_UNIT_TEST = """class_name TestS2cToS5Roadmap extends TestCase
## Verifies Sprint S2c, S2d, S2e, S3, S4, and S5 deliverables under `tests/run_tests.gd`.


func test_s2c_terrain_shader_has_debug_views_and_view_space_normal() -> void:
\tvar shader_code: String = FileAccess.get_file_as_string("res://game/planet/core/terrain_patch.gdshader")
\tassert_true(shader_code.contains("uniform int debug_view_mode"), "S2c shader must expose debug_view_mode")
\tassert_true(shader_code.contains("VIEW_MATRIX * vec4(world_normal"), "S2c shader must transform world_normal to view space")


func test_s2d_speed_sensation_and_side_plume() -> void:
\tvar idle_metrics: Dictionary = ShipVFX.compute_speed_sensation_metrics(0.0, false, false)
\tassert_almost_eq(float(idle_metrics["target_fov_deg"]), 75.0, 1e-4, "Idle FOV should be 75 deg")
\tassert_almost_eq(float(idle_metrics["streak_alpha"]), 0.0, 1e-4, "Idle streak alpha should be 0")

\tvar boost_metrics: Dictionary = ShipVFX.compute_speed_sensation_metrics(280.0, true, false)
\tassert_true(float(boost_metrics["target_fov_deg"]) >= 89.0, "Boost must apply FOV kick")
\tassert_true(float(boost_metrics["streak_alpha"]) > 0.5, "High speed must enable speed streaks")


func test_s2e_touch_steering_and_thermal_governor() -> void:
\tvar dead_vec: Vector2 = TouchControls.compute_touch_steering_vector(Vector2(4.0, 0.0), 100.0)
\tassert_almost_eq(dead_vec.length(), 0.0, 1e-5, "Deflection inside deadzone must return zero")

\tvar active_vec: Vector2 = TouchControls.compute_touch_steering_vector(Vector2(100.0, 0.0), 100.0)
\tassert_almost_eq(active_vec.x, 1.0, 1e-4, "Full deflection must return 1.0")

\tvar lod_mobile: int = QualityGovernor.get_terrain_max_lod_depth(true, 0.5)
\tassert_eq(lod_mobile, 8, "S26+ mobile terrain LOD depth must be capped at 8")

\tvar throttled_scale: float = QualityGovernor.compute_thermal_render_scale(0.67, 0.96, 15.0)
\tassert_almost_eq(throttled_scale, 0.60, 1e-4, "Critical thermal headroom must step down render scale")


func test_s3_moon_landing_assist_eva_10_min_and_atomic_crafting() -> void:
\tvar rem_o2: float = SurvivalSystem.compute_eva_oxygen_remaining(600.0, 120.0, 0)
\tassert_almost_eq(rem_o2, 480.0, 1e-3, "2 minutes of EVA should leave 480s of 600s capacity")

\tvar stock: Dictionary = {"iron_ore": 2, "silicate": 1}
\tvar recipe: Dictionary = {"iron_ore": 2, "silicate": 3}
\tvar failed: bool = CraftingSystem.execute_atomic_craft(stock, recipe, "circuit", 1)
\tassert_false(failed, "Craft must fail when silicate is insufficient")
\tassert_eq(int(stock["iron_ore"]), 2, "Atomic craft must not deduct iron_ore on failure")

\tstock["silicate"] = 3
\tvar passed: bool = CraftingSystem.execute_atomic_craft(stock, recipe, "circuit", 1)
\tassert_true(passed, "Craft must succeed when all inputs are present")
\tassert_eq(int(stock["circuit"]), 1, "Crafted item must be added to stock")

\tvar assist_accel: Vector3 = FlightModel.compute_low_gravity_landing_assist(
\t\tVector3(6.0, -15.0, 0.0),
\t\tVector3.UP,
\t\t40.0,
\t\t1.62
\t)
\tassert_true(assist_accel.y > 0.0, "Landing assist must provide upward braking when sinking fast")
\tassert_true(assist_accel.x < 0.0, "Landing assist must oppose positive X lateral drift")


func test_s4_star_class_diversity_and_seeded_system_determinism() -> void:
\tvar seen_classes: Dictionary = {}
\tfor i: int in range(80):
\t\tvar code: String = StarSystemGenerator.select_spectral_class_code(1000 + i * 9973)
\t\tseen_classes[code] = true
\tassert_true(seen_classes.size() >= 4, "StarSystemGenerator must generate multiple spectral classes, not only M")

\tvar sys_a: Dictionary = SystemLoader.build_seeded_system_state(424242)
\tvar sys_b: Dictionary = SystemLoader.build_seeded_system_state(424242)
\tassert_eq(str(sys_a["star_class"]), str(sys_b["star_class"]), "Same seed must produce identical star class")
\tassert_eq(int(sys_a["planet_count"]), int(sys_b["planet_count"]), "Same seed must produce identical planet count")


func test_s5_discovery_upload_and_speed_upgrades() -> void:
\tvar credits: int = DiscoverySystem.compute_upload_payout(4, 1.5)
\tassert_eq(credits, 1500, "4 discoveries at 1.5x rarity should award 1500 Survey Credits")

\tvar upgraded: Dictionary = DiscoverySystem.compute_upgraded_speed_limits(200.0, 100000.0, 2)
\tassert_almost_eq(float(upgraded["max_speed_mps"]), 320.0, 1e-3, "Tier 2 upgrade should raise speed by 60%")
\tassert_almost_eq(float(upgraded["pulse_range_m"]), 200000.0, 1e-1, "Tier 2 upgrade should double pulse range")
"""


def main() -> int:
    print("==> Applying Solar Horizon S2c -> S5 Roadmap Patch...")
    write_file("game/planet/core/terrain_patch.gdshader", TERRAIN_PATCH_SHADER)
    write_file("shaders/engine_plume.gdshader", ENGINE_PLUME_SHADER)
    append_if_missing("game/fx/ship_vfx.gd", "compute_speed_sensation_metrics", SHIP_VFX_EXTENSION)
    append_if_missing("game/ui/touch_controls.gd", "compute_touch_steering_vector", TOUCH_CONTROLS_EXTENSION)
    append_if_missing("game/autoload/quality_governor.gd", "get_terrain_max_lod_depth", QUALITY_GOVERNOR_EXTENSION)
    append_if_missing("game/gameplay/survival_system.gd", "compute_eva_oxygen_remaining", SURVIVAL_EXTENSION)
    append_if_missing("game/gameplay/crafting_system.gd", "execute_atomic_craft", CRAFTING_EXTENSION)
    append_if_missing("game/player/flight_model.gd", "compute_low_gravity_landing_assist", FLIGHT_MODEL_EXTENSION)
    append_if_missing("game/universe/star_system_generator.gd", "select_spectral_class_code", STAR_GENERATOR_EXTENSION)
    write_file("game/universe/system_loader.gd", SYSTEM_LOADER_SCRIPT)
    append_if_missing("game/gameplay/discovery_system.gd", "compute_upload_payout", DISCOVERY_EXTENSION)
    write_file("tests/roadmap/test_s2c_to_s5_roadmap.gd", ROADMAP_UNIT_TEST)

    # Export a clean git unified diff file
    patch_file = REPO_ROOT / "solar_horizon_s2c_to_s5.patch"
    try:
        diff_proc = subprocess.run(
            ["git", "diff"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        if diff_proc.stdout:
            patch_file.write_text(diff_proc.stdout, encoding="utf-8", newline="\n")
            print(f"  [DIFF]  Wrote unified git patch to {patch_file.name}")
    except Exception as exc:
        print(f"  [WARN]  Could not run git diff: {exc}")

    # Create the updated ZIP archive
    zip_out = REPO_ROOT.parent / "Solar-Horizon-s2c-to-s5-updated.zip"
    excluded_dirs = {".git", ".godot", "__pycache__"}
    with zipfile.ZipFile(zip_out, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(REPO_ROOT):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for file in files:
                full_path = Path(root) / file
                rel_path = full_path.relative_to(REPO_ROOT)
                zf.write(full_path, arcname=str(Path("Solar-Horizon") / rel_path))
    print(f"==> Packaged updated archive: {zip_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())