# Seeing the game without a GPU

Headless Godot cannot render, so it cannot tell you what the game looks like. Software Vulkan (Mesa
"lavapipe") plus a virtual display can, on any Linux box or CI runner:

```bash
sudo apt-get install -y xvfb mesa-vulkan-drivers libvulkan1
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
xvfb-run -a -s "-screen 0 960x540x24" godot --rendering-driver vulkan --resolution 960x540 \
    --path . res://tools/visual/capture_shots.tscn
```

PNGs land in Godot's `user://shots/`. It runs at roughly 1-2 frames per second, so use it for *what things
look like* (geometry, sky, UI, VFX), never for performance numbers. Physics-driven waits still work, they are
just slow. The GPU compute terrain path has not been checked on a real GPU; the Compatibility renderer
(`--rendering-driver opengl3`) exercises the non-compute fallback.

Findings from the first captures are in `docs/NEXT_INCREMENT.md`.
