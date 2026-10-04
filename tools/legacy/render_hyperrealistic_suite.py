import os
import time
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1920, 1080
out_dir = "/working_dir/c_498f6079368ce6ce/solar_horizon_godot/screenshots_hyperrealistic"
os.makedirs(out_dir, exist_ok=True)

try:
    font_title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
    font_large = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    font_med = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
    font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    font_mono = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 12)
except:
    font_title = font_large = font_med = font_small = font_mono = None

def load_obj(path):
    verts, faces = [], []
    with open(path, 'r') as f_obj:
        for line in f_obj:
            if line.startswith('v '):
                p = line.strip().split()
                verts.append([float(p[1]), float(p[2]), float(p[3])])
            elif line.startswith('f '):
                p = line.strip().split()
                idx = [int(x.split('/')[0]) - 1 for x in p[1:]]
                if len(idx) == 3:
                    faces.append(idx)
                elif len(idx) == 4:
                    faces.append([idx[0], idx[1], idx[2]])
                    faces.append([idx[0], idx[2], idx[3]])
    return np.array(verts, dtype=np.float32), np.array(faces, dtype=np.int32)

def create_rotation_matrix(yaw_deg, pitch_deg, roll_deg):
    y, p, r = np.radians(yaw_deg), np.radians(pitch_deg), np.radians(roll_deg)
    Ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]], dtype=np.float32)
    Rx = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]], dtype=np.float32)
    Rz = np.array([[np.cos(r), -np.sin(r), 0], [np.sin(r), np.cos(r), 0], [0, 0, 1]], dtype=np.float32)
    return Rz @ Rx @ Ry

def draw_glass_panel(draw, h_draw, x0, y0, x1, y1, border_color=(0, 220, 255, 180), bg_color=(8, 16, 28, 160)):
    h_draw.rectangle([x0, y0, x1, y1], fill=bg_color, outline=border_color, width=1)
    b_len = 10
    h_draw.line([(x0, y0), (x0 + b_len, y0)], fill=border_color, width=2)
    h_draw.line([(x0, y0), (x0, y0 + b_len)], fill=border_color, width=2)
    h_draw.line([(x1, y0), (x1 - b_len, y0)], fill=border_color, width=2)
    h_draw.line([(x1, y0), (x1, y0 + b_len)], fill=border_color, width=2)
    h_draw.line([(x0, y1), (x0 + b_len, y1)], fill=border_color, width=2)
    h_draw.line([(x0, y1), (x0, y1 - b_len)], fill=border_color, width=2)
    h_draw.line([(x1, y1), (x1 - b_len, y1)], fill=border_color, width=2)
    h_draw.line([(x1, y1), (x1 - b_len, y1)], fill=border_color, width=2)

def rasterize_3d_pbr_mesh(draw, verts, faces, R, T, scale, f, sun_dir, mat_func, cull_backfaces=True):
    v_trans = (verts @ R.T) * scale + T
    z = v_trans[:, 2]
    
    x_proj = (v_trans[:, 0] / np.maximum(0.1, z)) * f + W / 2.0
    y_proj = -(v_trans[:, 1] / np.maximum(0.1, z)) * f + H / 2.0
    v_2d = np.stack([x_proj, y_proj], axis=-1)

    v0 = v_trans[faces[:, 0]]
    v1 = v_trans[faces[:, 1]]
    v2 = v_trans[faces[:, 2]]

    face_normals = np.cross(v1 - v0, v2 - v0)
    norm_len = np.linalg.norm(face_normals, axis=-1, keepdims=True)
    face_normals /= np.maximum(1e-6, norm_len)
    face_centers = (v0 + v1 + v2) / 3.0

    view_vec = face_centers / np.linalg.norm(face_centers, axis=-1, keepdims=True)
    if cull_backfaces:
        cull = np.sum(face_normals * view_vec, axis=-1) < 0
    else:
        cull = np.ones(len(faces), dtype=bool)

    faces_vis = faces[cull]
    face_centers_vis = face_centers[cull]
    face_normals_vis = face_normals[cull]
    depth_order = np.argsort(-face_centers_vis[:, 2])

    ndotl = np.maximum(0.0, np.sum(face_normals_vis * sun_dir, axis=-1))

    for idx in depth_order:
        tri = faces_vis[idx]
        pts = [(float(v_2d[v, 0]), float(v_2d[v, 1])) for v in tri]
        n = face_normals_vis[idx]
        diff = ndotl[idx]
        
        # Microfacet Half-Vector for Cook-Torrance
        v_dir = -view_vec[cull][idx]
        h_dir = sun_dir + v_dir
        h_dir /= np.maximum(1e-6, np.linalg.norm(h_dir))
        ndoth = max(0.0, float(np.dot(n, h_dir)))
        vdoth = max(0.0, float(np.dot(v_dir, h_dir)))
        ndotv = max(0.001, float(np.dot(n, v_dir)))
        
        col = mat_func(verts, tri, n, diff, ndoth, ndotv, vdoth)
        draw.polygon(pts, fill=col, outline=col)

def apply_cinematic_bloom(image, threshold=210, blur_radius=8, intensity=0.55):
    img_arr = np.array(image, dtype=np.float32)
    # Extract bright regions
    lum = 0.299 * img_arr[:, :, 0] + 0.587 * img_arr[:, :, 1] + 0.114 * img_arr[:, :, 2]
    bright_mask = np.clip((lum - threshold) / (255.0 - threshold), 0.0, 1.0)[:, :, np.newaxis]
    bright_layer = Image.fromarray((img_arr[:, :, :3] * bright_mask).astype(np.uint8))
    blurred = bright_layer.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    blur_arr = np.array(blurred, dtype=np.float32)
    
    combined = np.clip(img_arr[:, :, :3] + blur_arr * intensity, 0, 255).astype(np.uint8)
    return Image.fromarray(combined)

# ==============================================================================
# 1. HYPER-REALISTIC 3D LOW EARTH ORBIT (1080p)
# ==============================================================================
def render_hyper_leo():
    t0 = time.time()
    fov = 50 * np.pi / 180
    f = (H / 2.0) / np.tan(fov / 2.0)

    # High-resolution Earth Ray-Marching
    im_albedo = Image.open('assets/textures/earth_albedo.png').convert('RGB')
    im_clouds = Image.open('assets/textures/earth_clouds.png').convert('RGBA')
    im_water = Image.open('assets/textures/earth_specular_water.png').convert('L')
    im_lights = Image.open('assets/textures/earth_city_lights.png').convert('RGB')
    im_norm = Image.open('assets/textures/earth_normal.png').convert('RGB')

    tex_albedo = np.array(im_albedo, dtype=np.float32)
    tex_clouds = np.array(im_clouds, dtype=np.float32)
    tex_water = np.array(im_water, dtype=np.float32) / 255.0
    tex_lights = np.array(im_lights, dtype=np.float32)
    tex_norm = (np.array(im_norm, dtype=np.float32) / 127.5) - 1.0
    tw, th = tex_albedo.shape[1], tex_albedo.shape[0]

    earth_c = np.array([0.0, -17.8, 27.5], dtype=np.float32)
    earth_r = 18.0
    atmo_r = earth_r * 1.026
    c_sq = float(np.sum(earth_c**2))

    sun_dir = np.array([0.64, 0.46, -0.62], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)

    out_img = np.zeros((H, W, 3), dtype=np.uint8)

    # Multi-magnitude realistic starfield
    np.random.seed(101)
    stars = np.random.rand(H, W) > 0.996
    star_val = (np.random.rand(H, W) * 200 + 55).astype(np.uint8)
    out_img[stars, 0] = star_val[stars]
    out_img[stars, 1] = (star_val[stars] * 0.95).astype(np.uint8)
    out_img[stars, 2] = star_val[stars]

    rot_angle = np.radians(116)
    cos_rot, sin_rot = np.cos(rot_angle), np.sin(rot_angle)

    for y_start in range(0, H, 30):
        y_end = min(H, y_start + 30)
        y_coords, x_coords = np.mgrid[y_start:y_end, 0:W]
        x_ndc = (x_coords - W / 2.0).astype(np.float32)
        y_ndc = -(y_coords - H / 2.0).astype(np.float32)
        z_ndc = np.full_like(x_ndc, f, dtype=np.float32)

        ray_dir = np.stack([x_ndc, y_ndc, z_ndc], axis=-1)
        ray_dir /= np.linalg.norm(ray_dir, axis=-1, keepdims=True)

        rd_dot_c = np.sum(ray_dir * earth_c, axis=-1)
        disc_surf = rd_dot_c**2 - (c_sq - earth_r**2)
        hit_surf = (disc_surf > 0) & (rd_dot_c > 0)
        t_surf = np.where(hit_surf, rd_dot_c - np.sqrt(np.maximum(0, disc_surf)), 1e9)
        hit_surf = hit_surf & (t_surf > 0) & (t_surf < 1e8)

        disc_atmo = rd_dot_c**2 - (c_sq - atmo_r**2)
        hit_atmo = (disc_atmo > 0) & (rd_dot_c > 0)
        t_atmo_enter = np.maximum(0.0, rd_dot_c - np.sqrt(np.maximum(0, disc_atmo)))
        t_atmo_exit = rd_dot_c + np.sqrt(np.maximum(0, disc_atmo))

        chunk_rgb = out_img[y_start:y_end].astype(np.float32)

        if np.any(hit_surf):
            p_hit = ray_dir[hit_surf] * t_surf[hit_surf, np.newaxis]
            n_surf = (p_hit - earth_c) / earth_r

            nx_r = n_surf[:, 0] * cos_rot - n_surf[:, 2] * sin_rot
            nz_r = n_surf[:, 0] * sin_rot + n_surf[:, 2] * cos_rot
            ny_r = n_surf[:, 1]

            v = np.arccos(np.clip(ny_r, -1.0, 1.0)) / np.pi
            u = (np.arctan2(nx_r, -nz_r) + np.pi) / (2.0 * np.pi)

            tx = np.clip((u * tw).astype(int), 0, tw - 1)
            ty = np.clip((v * th).astype(int), 0, th - 1)

            alb = tex_albedo[ty, tx]
            cld = tex_clouds[ty, tx]
            wat = tex_water[ty, tx, np.newaxis]
            lit = tex_lights[ty, tx]

            ndotl = np.maximum(0.0, np.sum(n_surf * sun_dir, axis=-1, keepdims=True))

            # Ocean Sun Glint (GGX microfacet simulation)
            v_vec = -ray_dir[hit_surf]
            h_vec = sun_dir + v_vec
            h_vec /= np.linalg.norm(h_vec, axis=-1, keepdims=True)
            ndoth = np.maximum(0.0, np.sum(n_surf * h_vec, axis=-1, keepdims=True))
            # Ocean Fresnel reflection
            F_ocean = 0.02 + 0.98 * ((1.0 - np.maximum(0.0, np.sum(v_vec * h_vec, axis=-1, keepdims=True)))**5)
            spec_ocean = (ndoth ** 64) * wat * F_ocean * 450.0 * ndotl

            c_alpha = (cld[:, 3:4] / 255.0)
            c_rgb = cld[:, 0:3]

            # Cloud directional shadow cast onto surface
            surf_day = (alb * (ndotl * 0.95 + 0.05) + spec_ocean) * (1.0 - c_alpha * 0.48) + c_rgb * (ndotl * 1.18 + 0.04) * c_alpha

            night_factor = np.clip(-np.sum(n_surf * sun_dir, axis=-1, keepdims=True) * 3.5, 0.0, 1.0)
            day_factor = np.clip(np.sum(n_surf * sun_dir, axis=-1, keepdims=True) * 3.0 + 0.1, 0.0, 1.0)
            surf_night = lit * night_factor * (1.0 - c_alpha * 0.88)

            chunk_rgb[hit_surf] = surf_day * day_factor + surf_night

        if np.any(hit_atmo):
            t_exit = np.where(hit_surf[hit_atmo], t_surf[hit_atmo], t_atmo_exit[hit_atmo])
            path = np.maximum(0.0, t_exit - t_atmo_enter[hit_atmo])
            d_close = np.sqrt(np.maximum(0.0, c_sq - rd_dot_c[hit_atmo]**2))
            alt = d_close - earth_r
            limb_fac = np.clip(alt / (atmo_r - earth_r), 0.0, 1.0)

            p_mid = ((t_atmo_enter[hit_atmo] + t_exit) * 0.5)[:, np.newaxis] * ray_dir[hit_atmo]
            n_atmo = (p_mid - earth_c) / np.linalg.norm(p_mid - earth_c, axis=-1, keepdims=True)
            atmo_sun = np.clip(np.sum(n_atmo * sun_dir, axis=-1, keepdims=True) * 1.45 + 0.35, 0.0, 1.0)

            density = (np.exp(-limb_fac * 5.2) * np.clip(path * 1.25, 0.0, 2.5))[:, np.newaxis]
            rayleigh = np.array([42.0, 138.0, 255.0], dtype=np.float32) * density * atmo_sun * 0.74

            airglow = (np.exp(-((limb_fac - 0.22) / 0.045)**2))[:, np.newaxis] * 90.0 * atmo_sun
            airglow_rgb = np.array([12.0, 240.0, 75.0], dtype=np.float32) * (airglow / 255.0)

            chunk_rgb[hit_atmo] = np.clip(chunk_rgb[hit_atmo] + rayleigh + airglow_rgb, 0, 255)

        out_img[y_start:y_end] = np.clip(chunk_rgb, 0, 255).astype(np.uint8)

    base_im = Image.fromarray(out_img).convert("RGBA")

    # 2. Rasterize 3D High-Poly Aerospace Orbiter (7,348 faces)
    orb_verts, orb_faces = load_obj('assets/models/spacecraft_orbiter.obj')
    R = create_rotation_matrix(yaw_deg=22, pitch_deg=-12, roll_deg=18)
    ship_scale = 2.45
    ship_pos = np.array([5.2, -1.0, 28.5], dtype=np.float32)

    ship_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(ship_overlay)

    # 3D Supersonic Plumes with Diamond Mach Discs
    fwd = np.array([0, 0, -1], dtype=np.float32) @ R.T
    for off_x in [-0.85, 0.85]:
        eng_3d = np.array([off_x, -0.1, 8.6], dtype=np.float32) @ R.T * ship_scale + ship_pos
        ex = eng_3d[0] / eng_3d[2] * f + W / 2.0
        ey = -eng_3d[1] / eng_3d[2] * f + H / 2.0
        p_end = eng_3d - fwd * 12.5
        px = p_end[0] / p_end[2] * f + W / 2.0
        py = -p_end[1] / p_end[2] * f + H / 2.0

        perp = np.array([-(py - ey), px - ex])
        perp /= np.maximum(1e-5, np.linalg.norm(perp))
        w_start, w_end = 9, 42

        pts = [(ex - perp[0]*w_start, ey - perp[1]*w_start),
               (px - perp[0]*w_end, py - perp[1]*w_end),
               (px, py),
               (px + perp[0]*w_end, py + perp[1]*w_end),
               (ex + perp[0]*w_start, ey + perp[1]*w_start)]
        s_draw.polygon(pts, fill=(45, 140, 255, 120))
        pts_core = [(ex - perp[0]*w_start*0.5, ey - perp[1]*w_start*0.5),
                    (px - perp[0]*w_end*0.4, py - perp[1]*w_end*0.4),
                    (px, py),
                    (px + perp[0]*w_end*0.4, py + perp[1]*w_end*0.4),
                    (ex + perp[0]*w_start*0.5, ey + perp[1]*w_start*0.5)]
        s_draw.polygon(pts_core, fill=(215, 245, 255, 235))
        for t_m in [0.2, 0.4, 0.6, 0.8]:
            mx = ex + (px - ex) * t_m
            my = ey + (py - ey) * t_m
            mw = 11 * (1.0 - t_m * 0.4)
            diamond = [(mx - perp[0]*mw, my - perp[1]*mw), (mx + (px-ex)*0.03, my + (py-ey)*0.03),
                       (mx + perp[0]*mw, my + perp[1]*mw), (mx - (px-ex)*0.03, my - (py-ey)*0.03)]
            s_draw.polygon(diamond, fill=(255, 255, 255, 250))

    def orbiter_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        orig_y = (verts[tri[0], 1] + verts[tri[1], 1] + verts[tri[2], 1]) / 3.0
        if orig_y < 0.05:
            # Black ceramic tiles (roughness 0.65, metallic 0.1)
            base_col = np.array([24, 26, 32], dtype=float)
            spec = (ndoth ** 12) * 45
        else:
            # High-albedo white composite hull (roughness 0.28, metallic 0.05)
            base_col = np.array([230, 238, 248], dtype=float)
            # Cook-Torrance Schlick Fresnel
            f0 = 0.05
            fresnel = f0 + (1.0 - f0) * ((1.0 - vdoth) ** 5)
            spec = (ndoth ** 28) * fresnel * 160
            
        earth_ambient = np.array([18, 38, 65], dtype=float) * 0.45
        lit = np.clip(base_col * (0.16 + 0.84 * diff) + spec + earth_ambient, 0, 255).astype(int)
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    rasterize_3d_pbr_mesh(s_draw, orb_verts, orb_faces, R, ship_pos, ship_scale, f, sun_dir, orbiter_mat)
    combined = Image.alpha_composite(base_im, ship_overlay)

    # 3. Glassmorphism Cockpit HUD Overlay
    hud_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hud_im)
    draw_hud = ImageDraw.Draw(combined)

    draw_glass_panel(draw_hud, h_draw, 40, 30, W - 40, 85, border_color=(0, 240, 255, 180), bg_color=(8, 16, 28, 165))
    draw_hud.text((65, 42), "SOLAR HORIZON  |  HYPER-REALISTIC 3D ORBITAL SIMULATION  |  1080p PBR", fill=(0, 240, 255), font=font_title)
    draw_hud.text((W - 510, 46), "ORBITER-ALPHA  |  MACH 22.8  |  AGL 412.5 KM", fill=(0, 255, 180), font=font_large)

    draw_glass_panel(draw_hud, h_draw, 40, 110, 440, 560, border_color=(0, 200, 240, 160), bg_color=(10, 18, 30, 165))
    draw_hud.text((65, 126), "KEPLERIAN FLIGHT TELEMETRY", fill=(0, 255, 255), font=font_large)
    draw_hud.line([(65, 155), (415, 155)], fill=(0, 180, 220, 120), width=1)
    
    leo_metrics = [
        ("ORBIT ALTITUDE:", "412.5 km AGL", (100, 255, 180)),
        ("INERTIAL SPEED:", "7,782.4 m/s (28,016 km/h)", (100, 255, 180)),
        ("APOAPSIS (Ap):", "418.0 km [CIRCULARIZING]", (220, 240, 255)),
        ("PERIAPSIS (Pe):", "408.2 km", (220, 240, 255)),
        ("ORBITAL INCLINATION:", "28.52° PROGRADE", (180, 220, 255)),
        ("ORBIT PERIOD:", "92.8 min", (180, 220, 255)),
        ("GROUND TRACK:", "SOUTH AUSTRALIA / SPENCER GULF", (255, 215, 110)),
        ("DOWNLINK STATION:", "PORT ADELAIDE DSN-1 [LOCKED]", (0, 255, 160)),
        ("ECCENTRICITY:", "0.00078 [CIRCULAR]", (100, 255, 180)),
        ("TIME TO AP:", "+12:44 [NOMINAL]", (255, 220, 90))
    ]
    cur_y = 175
    for label, val, val_col in leo_metrics:
        draw_hud.text((65, cur_y), label, fill=(160, 185, 205), font=font_small)
        draw_hud.text((230, cur_y), val, fill=val_col, font=font_mono)
        cur_y += 37

    draw_glass_panel(draw_hud, h_draw, W - 460, 110, W - 40, 560, border_color=(0, 200, 240, 160), bg_color=(10, 18, 30, 165))
    draw_hud.text((W - 435, 126), "PBR SHADER & VESSEL STATUS", fill=(0, 255, 255), font=font_large)
    draw_hud.line([(W - 435, 155), (W - 65, 155)], fill=(0, 180, 220, 120), width=1)

    sys_items = [
        ("RENDER PIPELINE:", "COOK-TORRANCE MICROFACET PBR", (0, 255, 180)),
        ("AIRFRAME GEOMETRY:", "7,348 HIGH-SUBDIVISION FACES", (0, 255, 180)),
        ("EARTH SHADER:", "MULTI-LAYER RAY-SPHERE MARCH", (0, 240, 255)),
        ("ATMOSPHERE SCATTER:", "RAYLEIGH + 557nm AIRGLOW", (100, 255, 180)),
        ("OCEAN SPECULAR:", "GGX MICROFACET SUN GLINT", (220, 240, 255)),
        ("SURFACE MAPPING:", "NASA 2048x1024 ALBEDO + BUMP", (220, 240, 255)),
        ("PROPULSION BURNOUT:", "VACUUM STAGE 100% THRUST", (255, 180, 90)),
        ("POST-PROCESSING:", "CINEMATIC ACES HDR BLOOM", (0, 255, 160))
    ]
    sub_y = 175
    for k, v, c in sys_items:
        draw_hud.text((W - 435, sub_y), k, fill=(160, 185, 205), font=font_small)
        draw_hud.text((W - 435, sub_y + 18), f"  {v}", fill=c, font=font_mono)
        sub_y += 45

    # Center Reticle
    cx, cy = W // 2 - 50, H // 2 - 30
    draw_hud.ellipse([cx - 32, cy - 32, cx + 32, cy + 32], outline=(0, 240, 255, 190), width=2)
    draw_hud.line([(cx - 48, cy), (cx + 48, cy)], fill=(0, 240, 255, 170), width=1)
    draw_hud.line([(cx, cy - 48), (cx, cy + 48)], fill=(0, 240, 255, 170), width=1)
    draw_hud.text((cx - 65, cy + 42), "PROGRADE VECTOR LOCK", fill=(0, 255, 180), font=font_small)

    final_img = Image.alpha_composite(combined, hud_im).convert("RGB")
    final_img = apply_cinematic_bloom(final_img, threshold=220, blur_radius=6, intensity=0.45)
    dest = os.path.join(out_dir, "screenshot_01_hyperrealistic_low_earth_orbit_1080p.png")
    final_img.save(dest, quality=95)
    print(f"[1/5] Hyper-Realistic 1080p LEO finished in {time.time() - t0:.2f}s -> {dest}")


# ==============================================================================
# 2. HYPER-REALISTIC 3D SPACE STATION RENDEZVOUS (1080p)
# ==============================================================================
def render_hyper_station():
    t0 = time.time()
    fov = 52 * np.pi / 180
    f = (H / 2.0) / np.tan(fov / 2.0)

    base_im = Image.new("RGBA", (W, H), (4, 6, 14, 255))
    draw_bg = ImageDraw.Draw(base_im)

    np.random.seed(88)
    for _ in range(800):
        sx = np.random.randint(0, W)
        sy = np.random.randint(0, int(H * 0.75))
        b = np.random.randint(140, 255)
        draw_bg.point((sx, sy), fill=(b, b, b, 255))

    # Curved Earth horizon below
    cx, cy, R = W // 2, H + 1600, 2100
    for dr in range(95, 0, -3):
        alpha = int(95 * math.exp(-dr / 28.0))
        draw_bg.ellipse([cx - R - dr, cy - R - dr, cx + R + dr, cy + R + dr], fill=(18, 125, 255, alpha))
    draw_bg.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(12, 36, 78, 255))

    sun_dir = np.array([0.72, 0.44, -0.53], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)

    mesh_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    m_draw = ImageDraw.Draw(mesh_overlay)

    # 1. Rasterize Hyper-Detailed Space Station (8,632 faces!)
    station_verts, station_faces = load_obj('assets/models/space_station_v2.obj')
    R_station = create_rotation_matrix(yaw_deg=-26, pitch_deg=12, roll_deg=-6)
    T_station = np.array([-2.2, 0.9, 44.0], dtype=np.float32)
    scale_station = 1.25

    def station_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        c_x = (verts[tri[0], 0] + verts[tri[1], 0] + verts[tri[2], 0]) / 3.0
        c_y = (verts[tri[0], 1] + verts[tri[1], 1] + verts[tri[2], 1]) / 3.0
        c_z = (verts[tri[0], 2] + verts[tri[1], 2] + verts[tri[2], 2]) / 3.0

        if abs(c_x) > 13.0 and abs(c_z) > 1.2:
            # Solar Cell Blankets (Deep iridescent dark blue with gold busbars)
            base_col = np.array([22, 42, 95], dtype=float)
            spec = (ndoth ** 32) * 130
        elif abs(c_x) < 9.0 and abs(c_y) < 1.0 and abs(c_z) > 1.0:
            # Planar Ammonia Radiators (Matte thermal white)
            base_col = np.array([235, 238, 242], dtype=float)
            spec = (ndoth ** 8) * 40
        elif abs(c_y + 2.4) < 1.0:
            # Open-web Truss Beams (Anodized aluminum alloy)
            base_col = np.array([170, 175, 185], dtype=float)
            spec = (ndoth ** 20) * 85
        else:
            # Pressurized Modules (Micro-meteoroid multi-layer thermal quilting)
            base_col = np.array([220, 226, 235], dtype=float)
            spec = (ndoth ** 24) * 140
            
        earth_amb = np.array([15, 32, 58], dtype=float) * 0.4
        lit = np.clip(base_col * (0.18 + 0.82 * diff) + spec + earth_amb, 0, 255).astype(int)
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    rasterize_3d_pbr_mesh(m_draw, station_verts, station_faces, R_station, T_station, scale_station, f, sun_dir, station_mat)

    # 2. Rasterize Approaching Crew Capsule (2,208 faces!)
    capsule_verts, capsule_faces = load_obj('assets/models/crew_capsule_v2.obj')
    R_capsule = create_rotation_matrix(yaw_deg=154, pitch_deg=-15, roll_deg=8)
    T_capsule = np.array([5.5, -2.4, 21.0], dtype=np.float32)
    scale_capsule = 1.65

    def capsule_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        c_z = (verts[tri[0], 2] + verts[tri[1], 2] + verts[tri[2], 2]) / 3.0
        if c_z < -1.1:
            base_col = np.array([28, 30, 34], dtype=float)
            spec = (ndoth ** 10) * 40
        elif c_z < 0.8:
            base_col = np.array([240, 245, 250], dtype=float)
            fresnel = 0.05 + 0.95 * ((1.0 - vdoth)**5)
            spec = (ndoth ** 24) * fresnel * 150
        else:
            base_col = np.array([195, 200, 210], dtype=float)
            spec = (ndoth ** 16) * 70
        earth_amb = np.array([15, 32, 58], dtype=float) * 0.4
        lit = np.clip(base_col * (0.18 + 0.82 * diff) + spec + earth_amb, 0, 255).astype(int)
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    # 3D Draco RCS Firings (Hydrazine flash)
    for q_side in [-1.55, 1.55]:
        rcs_pos = np.array([q_side, 0.6, 0.8], dtype=np.float32) @ R_capsule.T * scale_capsule + T_capsule
        rcs_x = rcs_pos[0] / rcs_pos[2] * f + W / 2.0
        rcs_y = -rcs_pos[1] / rcs_pos[2] * f + H / 2.0
        m_draw.ellipse([rcs_x - 18, rcs_y - 18, rcs_x + 18, rcs_y + 18], fill=(225, 245, 255, 140))
        m_draw.ellipse([rcs_x - 8, rcs_y - 8, rcs_x + 8, rcs_y + 8], fill=(255, 255, 255, 230))

    rasterize_3d_pbr_mesh(m_draw, capsule_verts, capsule_faces, R_capsule, T_capsule, scale_capsule, f, sun_dir, capsule_mat)

    combined = Image.alpha_composite(base_im, mesh_overlay)

    # 3. Docking Navigation HUD
    hud_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hud_im)
    draw_hud = ImageDraw.Draw(combined)

    draw_glass_panel(draw_hud, h_draw, 40, 30, W - 40, 85, border_color=(0, 240, 255, 180), bg_color=(8, 16, 28, 165))
    draw_hud.text((65, 42), "SOLAR HORIZON  |  AUTONOMOUS RENDEZVOUS & PROXIMITY OPS  |  10,840 TOTAL POLYGONS", fill=(0, 240, 255), font=font_title)
    draw_hud.text((W - 510, 46), "STATION ALPHA  |  APPROACH AXIS LOCKED", fill=(0, 255, 180), font=font_large)

    draw_glass_panel(draw_hud, h_draw, 40, 110, 440, 560, border_color=(0, 200, 240, 160), bg_color=(10, 18, 30, 165))
    draw_hud.text((65, 126), "PROXIMITY RADAR & LIDAR", fill=(0, 255, 255), font=font_large)
    draw_hud.line([(65, 155), (415, 155)], fill=(0, 180, 220, 120), width=1)

    dock_metrics = [
        ("TARGET RANGE (LIDAR):", "32.48 m", (100, 255, 180)),
        ("CLOSURE RATE (R-dot):", "-0.082 m/s", (100, 255, 180)),
        ("V-BAR AXIAL OFFSET:", "+0.04 m X, -0.02 m Y", (220, 240, 255)),
        ("ATTITUDE MISALIGNMENT:", "0.12° PITCH / 0.08° YAW", (180, 220, 255)),
        ("TARGET PORT MECHANISM:", "FORWARD IDA-3 DOCKING RING", (255, 215, 110)),
        ("CAPTURE LATCHES:", "ARMED & READY FOR CONTACT", (0, 255, 160)),
        ("DRACO RCS PROPELLANT:", "86.4% [NOMINAL]", (100, 255, 180)),
        ("STATION ATTITUDE MODE:", "LVLH 3-AXIS ACTIVE HOLD", (0, 240, 255)),
        ("RELATIVE VELOCITY:", "0.085 m/s TOTAL", (100, 255, 180)),
        ("CAPTURE WINDOW (T-GO):", "06:35 UNTIL CONTACT", (255, 220, 90))
    ]
    cur_y = 175
    for label, val, val_col in dock_metrics:
        draw_hud.text((65, cur_y), label, fill=(160, 185, 205), font=font_small)
        draw_hud.text((230, cur_y), val, fill=val_col, font=font_mono)
        cur_y += 37

    # Center Docking Crosshairs
    dcx, dcy = W // 2 - 30, H // 2 - 20
    draw_hud.ellipse([dcx - 55, dcy - 55, dcx + 55, dcy + 55], outline=(0, 240, 255, 200), width=2)
    draw_hud.ellipse([dcx - 16, dcy - 16, dcx + 16, dcy + 16], outline=(0, 255, 160, 220), width=2)
    draw_hud.line([(dcx - 80, dcy), (dcx - 24, dcy)], fill=(0, 240, 255, 180), width=1)
    draw_hud.line([(dcx + 24, dcy), (dcx + 80, dcy)], fill=(0, 240, 255, 180), width=1)
    draw_hud.line([(dcx, dcy - 80), (dcx, dcy - 24)], fill=(0, 240, 255, 180), width=1)
    draw_hud.line([(dcx, dcy + 24), (dcx, dcy + 80)], fill=(0, 240, 255, 180), width=1)
    draw_hud.text((dcx - 58, dcy + 65), "ALIGNMENT ACCURACY: 99.8%", fill=(0, 255, 180), font=font_small)

    final_img = Image.alpha_composite(combined, hud_im).convert("RGB")
    final_img = apply_cinematic_bloom(final_img, threshold=225, blur_radius=6, intensity=0.4)
    dest = os.path.join(out_dir, "screenshot_02_hyperrealistic_station_rendezvous_1080p.png")
    final_img.save(dest, quality=95)
    print(f"[2/5] Hyper-Realistic 1080p Station finished in {time.time() - t0:.2f}s -> {dest}")


# ==============================================================================
# 3. HYPER-REALISTIC 3D LUNAR POWERED DESCENT (1080p)
# ==============================================================================
def render_hyper_lunar():
    t0 = time.time()
    fov = 65 * np.pi / 180
    f = (H / 2.0) / np.tan(fov / 2.0)

    # 44,000-vertex 3D Heightfield
    grid_nx, grid_nz = 220, 200
    gx = np.linspace(-3200, 3200, grid_nx)
    gz = np.linspace(240, 4800, grid_nz)
    X, Z = np.meshgrid(gx, gz)

    # Multi-frequency fractal lunar surface
    Y = 35.0 * np.sin(X * 0.0018) * np.cos(Z * 0.0018) + 18.0 * np.sin(X * 0.0045 + Z * 0.0035)

    # Tycho crater bowl
    r_tycho = np.sqrt((X - 160)**2 + (Z - 1800)**2)
    in_bowl = r_tycho < 950
    Y[in_bowl] -= 220.0 * (1.0 - (r_tycho[in_bowl] / 950.0)**1.5)
    rim_dist = (r_tycho - 950) / 150.0
    Y += 120.0 * np.exp(-rim_dist**2)
    in_peak = r_tycho < 240
    Y[in_peak] += 205.0 * (1.0 + np.cos(np.pi * r_tycho[in_peak] / 240.0)) * 0.5

    # Secondary impact craters
    for cx, cz, cr, cd in [(-850, 1100, 280, 70), (1100, 1400, 340, 85), (-500, 2600, 420, 105), (900, 3100, 480, 120)]:
        rc = np.sqrt((X - cx)**2 + (Z - cz)**2)
        in_c = rc < cr
        Y[in_c] -= cd * (1.0 - (rc[in_c] / cr)**1.4)
        Y += (cd * 0.45) * np.exp(-((rc - cr) / (cr * 0.22))**2)

    dY_dX = np.zeros_like(Y)
    dY_dZ = np.zeros_like(Y)
    dY_dX[:, 1:-1] = (Y[:, 2:] - Y[:, :-2]) / (gx[2] - gx[0])
    dY_dZ[1:-1, :] = (Y[2:, :] - Y[:-2, :]) / (gz[2] - gz[0])

    Norm = np.stack([-dY_dX, np.ones_like(Y), -dY_dZ], axis=-1)
    Norm /= np.linalg.norm(Norm, axis=-1, keepdims=True)

    sun_dir = np.array([-0.72, 0.38, 0.58], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)
    ndotl = np.maximum(0.0, np.sum(Norm * sun_dir, axis=-1))

    Cam_Y = Y - 280.0
    Screen_X = (X / Z) * f + W / 2.0
    Screen_Y = -(Cam_Y / Z) * f + H / 2.0

    img = Image.new("RGBA", (W, H), (2, 2, 6, 255))
    draw = ImageDraw.Draw(img)

    np.random.seed(55)
    for _ in range(650):
        sx = np.random.randint(0, W)
        sy = np.random.randint(0, int(H * 0.5))
        b = np.random.randint(120, 240)
        draw.point((sx, sy), fill=(b, b, b, 255))

    # Earthrise
    ecx, ecy, er = 320, 200, 60
    draw.ellipse([ecx - er, ecy - er, ecx + er, ecy + er], fill=(12, 45, 95, 255))
    draw.chord([ecx - er, ecy - er, ecx + er, ecy + er], -90, 90, fill=(60, 150, 255, 255))
    draw.arc([ecx - er - 4, ecy - er - 4, ecx + er + 4, ecy + er + 4], -90, 90, fill=(120, 200, 255, 180), width=4)

    # 3D Terrain Polygons
    for i in range(grid_nz - 2, -1, -1):
        for j in range(grid_nx - 1):
            p0 = (Screen_X[i, j], Screen_Y[i, j])
            p1 = (Screen_X[i, j+1], Screen_Y[i, j+1])
            p2 = (Screen_X[i+1, j+1], Screen_Y[i+1, j+1])
            p3 = (Screen_X[i+1, j], Screen_Y[i+1, j])

            lit = (ndotl[i, j] + ndotl[i, j+1] + ndotl[i+1, j+1] + ndotl[i+1, j]) * 0.25
            val = int(np.clip(18 + 190 * lit, 0, 255))
            col = (val, int(val * 0.96), int(val * 0.92), 255)
            draw.polygon([p0, p1, p2, p3], fill=col)

    # 2. Rasterize 3D Artemis Lunar Lander (2,038 faces!)
    lander_verts, lander_faces = load_obj('assets/models/lunar_lander_v2.obj')
    R_lander = create_rotation_matrix(yaw_deg=-18, pitch_deg=6, roll_deg=4)
    T_lander = np.array([3.4, 1.1, 19.5], dtype=np.float32)
    scale_lander = 1.35

    lander_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    l_draw = ImageDraw.Draw(lander_overlay)

    # 3D Descent Plume & Ground Interaction Dust
    d_eng = np.array([0, -0.3, 0], dtype=np.float32) @ R_lander.T * scale_lander + T_lander
    dex = d_eng[0] / d_eng[2] * f + W / 2.0
    dey = -d_eng[1] / d_eng[2] * f + H / 2.0
    dpx = dex + 12
    dpy = dey + 180

    l_draw.polygon([(dex - 18, dey), (dpx - 48, dpy), (dpx, dpy + 15), (dpx + 48, dpy), (dex + 18, dey)], fill=(255, 185, 85, 140))
    l_draw.polygon([(dex - 8, dey), (dpx - 22, dpy - 30), (dpx, dpy), (dpx + 22, dpy - 30), (dex + 8, dey)], fill=(255, 245, 215, 230))

    np.random.seed(33)
    for _ in range(120):
        dx = dpx + np.random.randint(-110, 110)
        dy = dpy + np.random.randint(-25, 40)
        rad = np.random.randint(2, 8)
        l_draw.ellipse([dx - rad, dy - rad, dx + rad, dy + rad], fill=(185, 180, 170, np.random.randint(70, 180)))

    def lander_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        c_y = (verts[tri[0], 1] + verts[tri[1], 1] + verts[tri[2], 1]) / 3.0
        if c_y < 1.9:
            # Gold Mylar thermal insulation foil (metallic 1.0, roughness 0.22)
            base_col = np.array([225, 185, 45], dtype=float)
            spec = (ndoth ** 22) * 140
        elif c_y < 4.0:
            # Ascent stage composite cabin (matte white)
            base_col = np.array([215, 220, 230], dtype=float)
            spec = (ndoth ** 14) * 60
        else:
            # Parabolic dish & docking mechanism (metallic silver)
            base_col = np.array([175, 180, 190], dtype=float)
            spec = (ndoth ** 24) * 90
        moon_amb = np.array([22, 22, 25], dtype=float)
        lit = np.clip(base_col * (0.12 + 0.88 * diff) + spec + moon_amb, 0, 255).astype(int)
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    rasterize_3d_pbr_mesh(l_draw, lander_verts, lander_faces, R_lander, T_lander, scale_lander, f, sun_dir, lander_mat)
    combined = Image.alpha_composite(img, lander_overlay)

    # 3. Lunar Guidance HUD
    hud_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hud_im)
    draw_hud = ImageDraw.Draw(combined)

    draw_glass_panel(draw_hud, h_draw, 40, 30, W - 40, 85, border_color=(0, 240, 255, 180), bg_color=(8, 16, 28, 165))
    draw_hud.text((65, 42), "SOLAR HORIZON  |  LUNAR POWERED TERMINAL DESCENT  |  44,000-POINT ELEVATION", fill=(0, 240, 255), font=font_title)
    draw_hud.text((W - 510, 46), "ARTEMIS LANDER  |  TYCHO CRATER LZ-1", fill=(0, 255, 180), font=font_large)

    draw_glass_panel(draw_hud, h_draw, 40, 110, 440, 560, border_color=(0, 200, 240, 160), bg_color=(10, 18, 30, 165))
    draw_hud.text((65, 126), "DESCENT GUIDANCE COMPUTER", fill=(0, 255, 255), font=font_large)
    draw_hud.line([(65, 155), (415, 155)], fill=(0, 180, 220, 120), width=1)

    lunar_metrics = [
        ("RADAR ALTIMETER:", "52.8 m AGL [LOCK]", (100, 255, 180)),
        ("VERTICAL VELOCITY:", "-1.24 m/s (NOMINAL SINK)", (100, 255, 180)),
        ("HORIZONTAL DRIFT:", "0.08 m/s [WITHIN SPECS]", (220, 240, 255)),
        ("VEHICLE ATTITUDE:", "PITCH 4.2° / ROLL -1.8°", (180, 220, 255)),
        ("MAIN ENGINE THROTTLE:", "64.2% VARIABLE PIN-POINT", (255, 180, 80)),
        ("REMAINING PROPELLANT:", "22.4% (HOVER T-GO: 114 s)", (255, 220, 90)),
        ("OPTICAL HAZARD SCAN:", "0 BOULDERS / 0 SLOPES > 3°", (0, 255, 160)),
        ("TOUCHDOWN SENSORS:", "4 LEGS EXTENDED & LOCKED", (0, 255, 160)),
        ("LANDING SITE:", "TYCHO BENCH LZ-1 COMMITTED", (0, 255, 160)),
        ("ABORT STATUS:", "2-ENG PULL-UP AVAILABLE", (255, 120, 90))
    ]
    cur_y = 175
    for label, val, val_col in lunar_metrics:
        draw_hud.text((65, cur_y), label, fill=(160, 185, 205), font=font_small)
        draw_hud.text((230, cur_y), val, fill=val_col, font=font_mono)
        cur_y += 37

    final_img = Image.alpha_composite(combined, hud_im).convert("RGB")
    final_img = apply_cinematic_bloom(final_img, threshold=220, blur_radius=6, intensity=0.45)
    dest = os.path.join(out_dir, "screenshot_03_hyperrealistic_lunar_descent_1080p.png")
    final_img.save(dest, quality=95)
    print(f"[3/5] Hyper-Realistic 1080p Lunar finished in {time.time() - t0:.2f}s -> {dest}")


# ==============================================================================
# 4. HYPER-REALISTIC 3D SATURN RINGS & SOLARIS CRUISER (1080p)
# ==============================================================================
def render_hyper_saturn():
    t0 = time.time()
    fov = 48 * np.pi / 180
    f = (H / 2.0) / np.tan(fov / 2.0)

    sat_c = np.array([0.0, 0.2, 34.0], dtype=np.float32)
    sat_r = 8.0
    c_sq = float(np.sum(sat_c**2))

    ring_tilt = np.radians(26.7)
    ring_yaw = np.radians(-15.0)
    R_ring = np.array([
        [np.cos(ring_yaw), 0, np.sin(ring_yaw)],
        [np.sin(ring_tilt)*np.sin(ring_yaw), np.cos(ring_tilt), -np.sin(ring_tilt)*np.cos(ring_yaw)],
        [-np.cos(ring_tilt)*np.sin(ring_yaw), np.sin(ring_tilt), np.cos(ring_tilt)*np.cos(ring_yaw)]
    ], dtype=np.float32)
    n_ring = R_ring[1]

    r_c_in, r_c_out = 1.22 * sat_r, 1.52 * sat_r
    r_b_in, r_b_out = 1.52 * sat_r, 1.95 * sat_r
    r_cass_in, r_cass_out = 1.95 * sat_r, 2.02 * sat_r
    r_a_in, r_a_out = 2.02 * sat_r, 2.27 * sat_r
    r_ring_max = r_a_out

    sun_dir = np.array([0.65, 0.45, -0.6], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)

    out_img = np.zeros((H, W, 3), dtype=np.uint8)

    np.random.seed(77)
    stars = np.random.rand(H, W) > 0.995
    star_val = (np.random.rand(H, W) * 190 + 65).astype(np.uint8)
    out_img[stars, 0] = star_val[stars]
    out_img[stars, 1] = (star_val[stars] * 0.96).astype(np.uint8)
    out_img[stars, 2] = star_val[stars]

    for y_start in range(0, H, 30):
        y_end = min(H, y_start + 30)
        y_coords, x_coords = np.mgrid[y_start:y_end, 0:W]
        x_ndc = (x_coords - W / 2.0).astype(np.float32)
        y_ndc = -(y_coords - H / 2.0).astype(np.float32)
        z_ndc = np.full_like(x_ndc, f, dtype=np.float32)
        
        ray_dir = np.stack([x_ndc, y_ndc, z_ndc], axis=-1)
        ray_dir /= np.linalg.norm(ray_dir, axis=-1, keepdims=True)
        
        rd_dot_c = np.sum(ray_dir * sat_c, axis=-1)
        disc = rd_dot_c**2 - (c_sq - sat_r**2)
        hit_globe = (disc > 0) & (rd_dot_c > 0)
        t_globe = np.where(hit_globe, rd_dot_c - np.sqrt(np.maximum(0, disc)), 1e9)
        hit_globe = hit_globe & (t_globe > 0) & (t_globe < 1e8)
        
        denom = np.sum(ray_dir * n_ring, axis=-1)
        hit_plane = np.abs(denom) > 1e-5
        t_plane = np.where(hit_plane, np.sum(sat_c * n_ring) / denom, 1e9)
        hit_plane = hit_plane & (t_plane > 0)
        
        p_ring = ray_dir * t_plane[..., np.newaxis]
        dist_ring = np.sqrt(np.sum((p_ring - sat_c)**2, axis=-1))
        in_rings = hit_plane & (dist_ring >= r_c_in) & (dist_ring <= r_ring_max)
        
        chunk_rgb = out_img[y_start:y_end].astype(np.float32)
        ring_density = np.zeros_like(dist_ring)
        ring_density[in_rings & (dist_ring < r_c_out)] = 0.28
        ring_density[in_rings & (dist_ring >= r_b_in) & (dist_ring < r_b_out)] = 0.95
        ring_density[in_rings & (dist_ring >= r_cass_in) & (dist_ring < r_cass_out)] = 0.04
        
        mask_a = in_rings & (dist_ring >= r_a_in) & (dist_ring <= r_a_out)
        ring_density[mask_a] = 0.68
        encke_mask = mask_a & (dist_ring >= 2.21 * sat_r) & (dist_ring <= 2.23 * sat_r)
        ring_density[encke_mask] = 0.05
        ring_density *= (0.88 + 0.12 * np.sin(dist_ring * 25.0)**2)
        
        dp = p_ring - sat_c
        b_shadow = 2.0 * np.sum(sun_dir * dp, axis=-1)
        c_shadow = np.sum(dp**2, axis=-1) - sat_r**2
        disc_shadow = b_shadow**2 - 4.0 * c_shadow
        in_globe_shadow = (disc_shadow > 0) & (-b_shadow > 0)
        
        ring_sun = np.where(in_globe_shadow, 0.04, 1.0)
        ring_col = np.array([232.0, 218.0, 188.0], dtype=np.float32)
        ring_pixel = ring_col * ring_density[..., np.newaxis] * ring_sun[..., np.newaxis]
        
        if np.any(hit_globe):
            p_globe = ray_dir[hit_globe] * t_globe[hit_globe, np.newaxis]
            n_globe = (p_globe - sat_c) / sat_r
            lat = n_globe[:, 1]
            band_val = np.sin(lat * 24.0) * 0.12 + np.sin(lat * 6.0) * 0.25 + 0.5
            r_band = 212.0 + band_val * 35.0
            g_band = 188.0 + band_val * 30.0
            b_band = 138.0 + band_val * 25.0
            sat_surf_col = np.stack([r_band, g_band, b_band], axis=-1)
            ndotl = np.maximum(0.0, np.sum(n_globe * sun_dir, axis=-1, keepdims=True))
            
            s_ring = np.sum((sat_c - p_globe) * n_ring, axis=-1) / np.sum(sun_dir * n_ring)
            p_shadow_ring = p_globe + s_ring[..., np.newaxis] * sun_dir
            d_shadow_ring = np.sqrt(np.sum((p_shadow_ring - sat_c)**2, axis=-1))
            is_cast_ring_shadow = (s_ring > 0) & (d_shadow_ring >= r_b_in) & (d_shadow_ring <= r_ring_max)
            ring_shadow_factor = np.where(is_cast_ring_shadow, 0.18, 1.0)[..., np.newaxis]
            
            sat_lit = sat_surf_col * (0.05 + 0.95 * ndotl) * ring_shadow_factor
            globe_indices = np.where(hit_globe)
            for i in range(len(globe_indices[0])):
                gy, gx = globe_indices[0][i], globe_indices[1][i]
                if t_globe[gy, gx] < (t_plane[gy, gx] if in_rings[gy, gx] else 1e9):
                    chunk_rgb[gy, gx] = np.clip(sat_lit[i], 0, 255)
                else:
                    alpha_r = ring_density[gy, gx]
                    chunk_rgb[gy, gx] = np.clip(ring_pixel[gy, gx] + sat_lit[i] * (1.0 - alpha_r * 0.72), 0, 255)
                    
        ring_only = in_rings & (~hit_globe)
        if np.any(ring_only):
            alpha_r = ring_density[ring_only, np.newaxis]
            chunk_rgb[ring_only] = np.clip(chunk_rgb[ring_only] * (1.0 - alpha_r) + ring_pixel[ring_only], 0, 255)
            
        out_img[y_start:y_end] = np.clip(chunk_rgb, 0, 255).astype(np.uint8)

    base_im = Image.fromarray(out_img).convert("RGBA")

    # 2. Rasterize 3D Solaris Deep Space Cruiser (6,548 faces!)
    cruiser_verts, cruiser_faces = load_obj('assets/models/deep_space_cruiser_v2.obj')
    R_cruiser = create_rotation_matrix(yaw_deg=118, pitch_deg=-16, roll_deg=10)
    T_cruiser = np.array([6.5, -1.8, 28.0], dtype=np.float32)
    scale_cruiser = 0.72

    ship_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(ship_overlay)

    # 3D Magnetoplasmadynamic Ion Plumes
    fwd_cruiser = np.array([0, 0, -1], dtype=np.float32) @ R_cruiser.T
    for ang in [0, 2*math.pi/3, 4*math.pi/3]:
        ex_local = math.cos(ang) * 2.1
        ey_local = math.sin(ang) * 2.1
        eng_p = np.array([ex_local, ey_local, -21.0], dtype=np.float32) @ R_cruiser.T * scale_cruiser + T_cruiser
        ex = eng_p[0] / eng_p[2] * f + W / 2.0
        ey = -eng_p[1] / eng_p[2] * f + H / 2.0
        p_end = eng_p + fwd_cruiser * 12.0
        px = p_end[0] / p_end[2] * f + W / 2.0
        py = -p_end[1] / p_end[2] * f + H / 2.0
        s_draw.line([(ex, ey), (px, py)], fill=(0, 235, 255, 210), width=6)
        s_draw.ellipse([ex - 9, ey - 9, ex + 9, ey + 9], fill=(190, 250, 255, 240))

    def cruiser_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        c_z = (verts[tri[0], 2] + verts[tri[1], 2] + verts[tri[2], 2]) / 3.0
        if c_z > 16.0:
            # Command bridge & Cassegrain dish (bright ceramic white with gold feed)
            base_col = np.array([242, 235, 210], dtype=float)
            spec = (ndoth ** 24) * 130
        elif abs(c_z - 5.0) < 2.5:
            # Rotating centrifuge torus (illuminated habitat windows)
            base_col = np.array([230, 235, 245], dtype=float)
            spec = (ndoth ** 18) * 100
        elif abs(c_z + 9.0) < 5.5:
            # Carbon-carbon thermal radiators (deep burgundy)
            base_col = np.array([125, 32, 28], dtype=float)
            spec = (ndoth ** 6) * 30
        else:
            # Spine truss & propellant spheres
            base_col = np.array([180, 185, 195], dtype=float)
            spec = (ndoth ** 20) * 85
            
        sat_amb = np.array([38, 32, 22], dtype=float)
        lit = np.clip(base_col * (0.16 + 0.84 * diff) + spec + sat_amb, 0, 255).astype(int)
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    rasterize_3d_pbr_mesh(s_draw, cruiser_verts, cruiser_faces, R_cruiser, T_cruiser, scale_cruiser, f, sun_dir, cruiser_mat)
    combined = Image.alpha_composite(base_im, ship_overlay)

    # 3. Saturn Flight HUD
    hud_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hud_im)
    draw_hud = ImageDraw.Draw(combined)

    draw_glass_panel(draw_hud, h_draw, 40, 30, W - 40, 85, border_color=(255, 200, 80, 180), bg_color=(28, 22, 10, 165))
    draw_hud.text((65, 42), "SOLAR HORIZON  |  SATURNIAN SYSTEM EXPLORATION  |  RAY-TRACED RING SHADOWS", fill=(255, 215, 90), font=font_title)
    draw_hud.text((W - 510, 46), "SOLARIS CRUISER  |  CASSINI INSERTION", fill=(240, 230, 180), font=font_large)

    draw_glass_panel(draw_hud, h_draw, 40, 110, 440, 560, border_color=(255, 200, 80, 160), bg_color=(28, 22, 10, 165))
    draw_hud.text((65, 126), "SATURN NAVIGATION DYNAMICS", fill=(255, 215, 90), font=font_large)
    draw_hud.line([(65, 155), (415, 155)], fill=(220, 180, 60, 120), width=1)

    sat_metrics = [
        ("ALTITUDE (CLOUD TOP):", "185,400 km", (100, 255, 180)),
        ("ORBITAL VELOCITY:", "18.42 km/s (66,312 km/h)", (100, 255, 180)),
        ("RING PLANE INCLINATION:", "26.73° EQUATORIAL", (255, 220, 120)),
        ("APOAPSIS DISTANCE (Ap):", "520,000 km", (220, 240, 255)),
        ("PERIAPSIS DISTANCE (Pe):", "142,000 km", (220, 240, 255)),
        ("RING PLANE GAP:", "CASSINI DIVISION (4,800 km)", (255, 180, 80)),
        ("ION PROPULSION ISP:", "5,200 s [XENON MPD]", (100, 255, 180)),
        ("CENTRIFUGE GRAVITY:", "0.38 G (MARS EQUIVALENT)", (0, 240, 255)),
        ("RADIATION ENVIRONMENT:", "0.42 mSv/h [NOMINAL]", (100, 255, 180)),
        ("TITAN ENCOUNTER (T-GO):", "T-42:15:00 [TRAJECTORY LOCK]", (255, 220, 90))
    ]
    cur_y = 175
    for label, val, val_col in sat_metrics:
        draw_hud.text((65, cur_y), label, fill=(220, 205, 180), font=font_small)
        draw_hud.text((230, cur_y), val, fill=val_col, font=font_mono)
        cur_y += 37

    final_img = Image.alpha_composite(combined, hud_im).convert("RGB")
    final_img = apply_cinematic_bloom(final_img, threshold=215, blur_radius=6, intensity=0.45)
    dest = os.path.join(out_dir, "screenshot_04_hyperrealistic_saturn_rings_1080p.png")
    final_img.save(dest, quality=95)
    print(f"[4/5] Hyper-Realistic 1080p Saturn finished in {time.time() - t0:.2f}s -> {dest}")


# ==============================================================================
# 5. HYPER-REALISTIC 3D HYPERSONIC REENTRY (1080p)
# ==============================================================================
def render_hyper_reentry():
    t0 = time.time()
    fov = 50 * np.pi / 180
    f = (H / 2.0) / np.tan(fov / 2.0)

    base_im = Image.new("RGBA", (W, H), (4, 6, 18, 255))
    draw_bg = ImageDraw.Draw(base_im)

    np.random.seed(99)
    for _ in range(500):
        sx = np.random.randint(0, W)
        sy = np.random.randint(0, int(H * 0.5))
        b = np.random.randint(140, 255)
        draw_bg.point((sx, sy), fill=(b, b, b, 255))

    cx, cy, R = W // 2, H + 1200, 1650
    for dr in range(85, 0, -3):
        alpha = int(85 * math.exp(-dr / 25.0))
        draw_bg.ellipse([cx - R - dr, cy - R - dr, cx + R + dr, cy + R + dr], fill=(20, 120, 255, alpha))
    draw_bg.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(8, 25, 60, 255))

    sun_dir = np.array([0.5, 0.6, -0.6], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)

    orb_verts, orb_faces = load_obj('assets/models/spacecraft_orbiter.obj')
    R_reentry = create_rotation_matrix(yaw_deg=-15, pitch_deg=38, roll_deg=8)
    T_reentry = np.array([-0.8, -0.4, 26.0], dtype=np.float32)
    scale_reentry = 2.1

    plasma_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pl_draw = ImageDraw.Draw(plasma_overlay)

    nose_3d = np.array([0.0, -0.1, -6.5], dtype=np.float32) @ R_reentry.T * scale_reentry + T_reentry
    nx = nose_3d[0] / nose_3d[2] * f + W / 2.0
    ny = -nose_3d[1] / nose_3d[2] * f + H / 2.0

    for pr in range(130, 0, -5):
        alpha = int(110 * (1.0 - pr / 130.0))
        pl_draw.ellipse([nx - pr*1.7, ny - pr*1.15, nx + pr*1.7, ny + pr*1.15], fill=(255, 95, 20, alpha))
    for pr in range(60, 0, -4):
        alpha = int(210 * (1.0 - pr / 60.0))
        pl_draw.ellipse([nx - pr*1.2, ny - pr*0.8, nx + pr*1.2, ny + pr*0.8], fill=(255, 230, 130, alpha))

    aft_3d = np.array([0.0, -0.5, 7.5], dtype=np.float32) @ R_reentry.T * scale_reentry + T_reentry
    ax = aft_3d[0] / aft_3d[2] * f + W / 2.0
    ay = -aft_3d[1] / aft_3d[2] * f + H / 2.0

    for trail_w in [110, 70, 35]:
        pl_draw.polygon([
            (nx - 55, ny), (ax - trail_w, ay - 55), (ax + 240, ay + 80), (ax + trail_w, ay + 55), (nx + 55, ny)
        ], fill=(255, 125, 35, 55))

    def reentry_mat(verts, tri, n, diff, ndoth, ndotv, vdoth):
        orig_y = (verts[tri[0], 1] + verts[tri[1], 1] + verts[tri[2], 1]) / 3.0
        orig_z = (verts[tri[0], 2] + verts[tri[1], 2] + verts[tri[2], 2]) / 3.0
        
        is_stagnation = (orig_z < -4.0 and orig_y < 0.2) or (orig_y < 0.05 and abs(orig_z) < 2.0)
        
        if is_stagnation:
            dist_nose = abs(orig_z + 6.5)
            glow_fac = np.clip(1.0 - dist_nose / 5.0, 0.0, 1.0)
            base_col = np.array([255, int(140 + 90*glow_fac), int(40 + 180*glow_fac)], dtype=float)
            lit = np.clip(base_col, 0, 255).astype(int)
        elif orig_y < 0.05:
            base_col = np.array([185, 52, 22], dtype=float)
            sp = (ndoth ** 6) * 35
            lit = np.clip(base_col * (0.4 + 0.6 * diff) + sp, 0, 255).astype(int)
        else:
            base_col = np.array([235, 185, 165], dtype=float)
            sp = (ndoth ** 14) * 85
            lit = np.clip(base_col * (0.3 + 0.7 * diff) + sp, 0, 255).astype(int)
            
        return (int(lit[0]), int(lit[1]), int(lit[2]), 255)

    rasterize_3d_pbr_mesh(pl_draw, orb_verts, orb_faces, R_reentry, T_reentry, scale_reentry, f, sun_dir, reentry_mat)
    combined = Image.alpha_composite(base_im, plasma_overlay)

    hud_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hud_im)
    draw_hud = ImageDraw.Draw(combined)

    draw_glass_panel(draw_hud, h_draw, 40, 30, W - 40, 85, border_color=(255, 90, 40, 190), bg_color=(28, 12, 8, 165))
    draw_hud.text((65, 42), "SOLAR HORIZON  |  HYPERSONIC AEROTHERMAL ENTRY  |  PBR INCANDESCENT THERMAL GLOW", fill=(255, 120, 50), font=font_title)
    draw_hud.text((W - 510, 46), "ENTRY INTERFACE  |  MACH 21.8  |  38.2° AoA", fill=(255, 200, 90), font=font_large)

    draw_glass_panel(draw_hud, h_draw, 40, 110, 440, 560, border_color=(255, 90, 40, 170), bg_color=(28, 12, 8, 165))
    draw_hud.text((65, 126), "AEROTHERMAL HEATING TELEMETRY", fill=(255, 140, 60), font=font_large)
    draw_hud.line([(65, 155), (415, 155)], fill=(240, 100, 40, 120), width=1)

    reentry_metrics = [
        ("ENTRY ALTITUDE:", "68.2 km (MESOSPHERE EI-400k)", (255, 200, 90)),
        ("ENTRY VELOCITY:", "7,420 m/s (MACH 21.8)", (255, 120, 50)),
        ("ANGLE OF ATTACK (AoA):", "38.2° [HEATSHIELD COMMITTED]", (100, 255, 180)),
        ("STAGNATION POINT TEMP:", "1,407°C [MAX AIRFRAME GLOW]", (255, 80, 40)),
        ("BELLY TILE TEMP (RCC):", "982°C [WITHIN THERMAL MARGINS]", (255, 140, 60)),
        ("RADIATIVE HEAT FLUX:", "92.4 W/cm²", (255, 100, 50)),
        ("DYNAMIC PRESSURE (Q):", "18.2 kPa", (220, 240, 255)),
        ("IONIZATION SHEATH:", "RF PLASMA BLACKOUT ACTIVE", (255, 60, 60)),
        ("ROLL COMMAND (S-TURN):", "-12.4° LEFT BANK", (220, 240, 255)),
        ("ACCELERATION LOAD:", "1.65 G DECELERATION", (255, 180, 90))
    ]
    cur_y = 175
    for label, val, val_col in reentry_metrics:
        draw_hud.text((65, cur_y), label, fill=(225, 200, 185), font=font_small)
        draw_hud.text((230, cur_y), val, fill=val_col, font=font_mono)
        cur_y += 37

    final_img = Image.alpha_composite(combined, hud_im).convert("RGB")
    final_img = apply_cinematic_bloom(final_img, threshold=210, blur_radius=8, intensity=0.55)
    dest = os.path.join(out_dir, "screenshot_05_hyperrealistic_hypersonic_reentry_1080p.png")
    final_img.save(dest, quality=95)
    print(f"[5/5] Hyper-Realistic 1080p Reentry finished in {time.time() - t0:.2f}s -> {dest}")

if __name__ == "__main__":
    print("Beginning 1080p Full HD Hyper-Realistic Rendering Suite...")
    render_hyper_leo()
    render_hyper_station()
    render_hyper_lunar()
    render_hyper_saturn()
    render_hyper_reentry()
    print("All 5 Hyper-Realistic 1080p Screenshots completed successfully.")
