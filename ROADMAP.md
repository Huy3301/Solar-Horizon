# Solar Horizon: Continuous Development Roadmap & Polish Matrix

A comprehensive engineering roadmap for evolving **Solar Horizon** into a complete, realistic, cross-platform solar system spaceflight simulator.

---

## Phase I: Celestial Bodies & Astronomical Scale

- [ ] **1.1 Global Solar System Hierarchy**
  - Implement barycentric coordinate tree (Solar System Barycenter -> Sun -> Planets -> Moons).
  - Position all 8 major planets + Moon + Galilean Moons + Titan at real J2000 epoch coordinates using Keplerian mean anomaly propagation.
- [ ] **1.2 NASA Planetary Elevation (DEM) Pipeline**
  - **Earth:** Integrate SRTM (Shuttle Radar Topography Mission) and GEBCO 15-arc-second bathymetry/elevation tiles.
  - **Moon:** Integrate NASA LRO LOLA (Lunar Orbiter Laser Altimeter) 64-pixels-per-degree DEM.
  - **Mars:** Integrate NASA MRO MOLA (Mars Orbiter Laser Altimeter) 128-pixels-per-degree elevation maps (Olympus Mons, Valles Marineris).
  - **Mercury & Venus:** Integrate MESSENGER and Magellan radar topographic maps.
- [ ] **1.3 Seamless Cube-Sphere Quadtree LOD Engine**
  - Implement distance-based recursive quadtree splitting (LOD levels 0 through 18) down to 1-meter surface resolution.
  - Add vertex morphing (geomorphing) between adjacent LOD levels to eliminate geometry popping during atmospheric descent.
  - Generate skirt geometry along chunk borders to eliminate visual seams between differing LOD resolutions.
- [ ] **1.4 Saturn Ring System & Volumetric Shadows**
  - Implement double-sided alpha-masked ring plane with anisotropic light scattering (A, B, C rings and Cassini Division).
  - Implement planetary ring shadow projection onto Saturn's cloud tops and globe shadow onto the rings.

---

## Phase II: Visuals & "Theoretical Physics Meets Practice" Style

- [ ] **2.1 Conic Section & Trajectory Suite**
  - Real-time Keplerian orbit lines with glowing neon blueprint aesthetic (Cyan = Closed Orbit, Orange = Atmospheric Aerobraking, Crimson = Collision Trajectory, Gold = Hyperbolic Escape).
  - Interactive maneuver nodes: click and drag Prograde/Retrograde, Normal/Anti-Normal, and Radial-In/Radial-Out gizmos to preview resulting transfer orbit before burning engines.
  - Lagrange Points visualization: Render stable and unstable equilibrium contours (L1, L2, L3, L4, L5) in Earth-Moon and Sun-Earth systems.
  - Gravitational Hill Sphere and Sphere of Influence (SOI) boundary wireframe cages.
  - Roche Limit dashed warning rings around gas giants and terrestrial planets.
- [ ] **2.2 Atmospheric Scattering & Lighting**
  - Bruneton-style precomputed atmospheric scattering shader for Earth and Mars (Rayleigh air molecular scattering + Mie aerosol haze).
  - Dynamic twilight terminator line and atmospheric limb glow visible from orbit.
  - Cloud shadow projection onto planetary terrain using multi-layered dynamic flow maps.
- [ ] **2.3 Re-entry Plasma & Thermal Effects**
  - Compressional atmospheric heating shader: ship leading edges, nose cone, and wing tips glow cherry-red to white-hot at velocities > Mach 4.5.
  - Plasma envelope particle trail with ionization wake and aerodynamic shockwave cones.
  - Camera vibration and sonic boom pressure wave distortion when breaking the sound barrier (Mach 1.0).
- [ ] **2.4 Graphics Scalability (Mobile vs. Desktop Ultra)**
  - **Desktop (Forward+):** Volumetric fog, screen-space reflections (SSR), multi-sample anti-aliasing (MSAA 4x), soft shadow cascades.
  - **Mobile (Compatibility / Vulkan Mobile):** Half-resolution planetary atmosphere, baked normal maps, ASTC texture compression, dynamic resolution scaling targeting locked 60 FPS.

---

## Phase III: Physics & Aerodynamics Enhancements

- [ ] **3.1 High-Altitude Aero-Thermal Flight**
  - Dynamic center-of-pressure (CP) shifting backward from 25% chord at subsonic speeds to 45% chord at supersonic/hypersonic speeds.
  - Hypersonic lift-to-drag ratio degradation (L/D ~ 1.5 - 2.5 at Mach 10+).
  - High-angle-of-attack S-turn energy management autopilot for orbital de-orbit and landing approach into Adelaide Base.
- [ ] **3.2 Precision Orbital Physics & Perturbations**
  - J2 zonal harmonic gravitational perturbation for Earth (oblateness causes orbital nodal regression).
  - Patched-conics transition handler with automatic state vector transformation across planetary SOI boundaries.
  - Solar radiation pressure calculation on ultra-light deep-space vessels.
- [ ] **3.3 Re-entry Heat Shield & G-Force Limits**
  - Thermal shield ablative wear: excessive heating angle burns through TPS (Thermal Protection System) tiles.
  - Crew G-force limits: sustained accelerations > 9 G trigger redout/blackout tunnel vision effects.

---

## Phase IV: Multi-Vessel Fleet

- [ ] **4.1 SSTO Aero-Spaceplane ("Valkyrie-Class Exploration Cruiser")**
  - Dual-mode propulsion: Air-breathing turbo-ramjets (Mach 0 to 5.5 in atmosphere) transitioning to closed-cycle vacuum rocket engines.
  - Retractable hypersonic control canards, split-rudder airbrakes, and cargo bay for deploying orbital satellites.
  - Full interior cockpit with clickable Multi-Function Displays (MFDs).
- [ ] **4.2 Heavy Space Rocket ("Astraeus Orbital Launch Vehicle")**
  - Multi-stage vertical launch rocket: Stage 1 booster (9 methane/LOX gimballed engines) + Stage 2 vacuum upper stage.
  - Automated booster return: boostback burn, atmospheric entry burn, aerodynamic grid fin steering, and vertical touchdown burn (suicide burn) back at Adelaide Spaceport launchpad.
- [ ] **4.3 Lunar / Martian Exploration Lander ("Artemis Modular Lander")**
  - Deep-throttling hypergolic rocket engines.
  - Terrain-relative navigation (TRN) camera with hazard detection (boulders and slope avoidance).
  - Deployable surface rover and crew airlock.
- [ ] **4.4 Deep-Space Nuclear-Thermal / Ion Cruiser ("Solaris Interplanetary")**
  - Low-thrust, high-Isp (Specific Impulse > 5000 s) continuous burn propulsion for interplanetary cruise between Earth, Mars, and Jupiter.
  - Rotating centrifugal artificial gravity habitat ring.

---

## Phase V: Navigation, Tactical Maps & Solar System Tools

- [ ] **5.1 Hohmann Transfer Window Calculator**
  - In-game delta-v porkchop plot generator to find optimal departure windows from Earth to Mars, Venus, or the outer planets.
  - Automatic time-to-node countdown timer and burn duration calculation based on vessel engine thrust-to-weight ratio.
- [ ] **5.2 Ground Tracking Stations & Communications Network**
  - Real ground station network: Adelaide Spaceport (Australia), Goldstone (USA), Madrid (Spain), and Canberra Deep Space Communication Complex (CDSCC).
  - Line-of-sight signal occlusion by planetary bodies (requiring orbital relay satellites).
- [ ] **5.3 Adelaide Base Expansion**
  - Add RAAF Edinburgh hangars, cryogenic fuel storage tanks, launch gantry towers, radar tracking domes, and Port Adelaide maritime landmarks.
  - Precision Instrument Landing System (ILS) and runway approach lighting towers for night/fog landings.

---

## Phase VI: Audio Engineering & Immersion

- [ ] **6.1 Realistic Acoustic Modeling**
  - Hull-conduction sound simulation: inside the cockpit in vacuum, engine sound is filtered to low-frequency hull rumble; external atmospheric roar fades as air density reaches zero.
  - Dynamic airflow sound: wind rush volume and pitch scale with dynamic pressure (q) and Mach angle.
- [ ] **6.2 Flight Deck & Telemetry Audio**
  - GPWS (Ground Proximity Warning System) callouts: "Altitude", "Sink Rate", "Pull Up", "500", "100", "50", "20", "Touchdown".
  - Atmospheric entry warning alarms, staging clunks, and thruster pulse clicks.
