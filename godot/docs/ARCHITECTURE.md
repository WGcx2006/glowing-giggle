# Battlefield 2035 - Godot 4 Architecture

This is the native Godot 4 port of the existing Three.js prototype. It must be
self-contained: all geometry, textures, and audio are generated at runtime with
GDScript. No external asset downloads are allowed.

## Project layout

```text
godot/
  project.godot
  scenes/
    main.tscn
    player.tscn
    environment.tscn
    enemies.tscn
    capture_zones.tscn
    fx.tscn
    hud.tscn
  scripts/
    core/events.gd
    game/game_mode.gd
    gameplay/player.gd
    gameplay/weapons.gd
    gameplay/projectiles.gd
    gameplay/capture_zones.gd
    ai/enemy.gd
    ai/enemy_system.gd
    render/environment.gd
    render/terrain.gd
    render/sky.gd
    render/postfx.gd
    fx/effects.gd
    fx/tracers.gd
    audio/audio_manager.gd
    ui/hud.gd
    main.gd
  tools/
    visual_capture.gd
  docs/
    ARCHITECTURE.md
```

## Module ownership

Each subagent owns a disjoint file set. The authoritative ownership matrix and
multi-agent operating rules live in `docs/全流程执行提示词.md` and
`.agents/roles/`; when they conflict with this table, those files win.

| Module | Owned paths | Responsibility |
| --- | --- | --- |
| Render | `scripts/render/*`, `scenes/environment.tscn` | Terrain, sky, water, props, lighting, fog, post-processing, quality tiers |
| Gameplay | `scripts/gameplay/player.gd`, `scripts/gameplay/weapons.gd`, `scripts/gameplay/projectiles.gd`, `scenes/player.tscn` | First-person controller, weapon feel, bullets/rockets/grenades, recoil, view bob |
| AI/Game | `scripts/ai/*`, `scripts/gameplay/capture_zones.gd`, `scripts/game/game_mode.gd`, `scenes/enemies.tscn`, `scenes/capture_zones.tscn` | Enemy AI, team spawning, capture points, win/loss, match flow |
| FX/Audio | `scripts/fx/*`, `scripts/audio/*`, `scripts/ui/hud.gd`, `scenes/fx.tscn`, `scenes/hud.tscn` | Particles, tracers, casings, explosions, procedural audio, HUD/menu, blind-test capture helper |

## Contracts

### Render

```gdscript
extends Node3D

func setup() -> void
func update(delta: float, camera: Camera3D, time_of_day: float) -> void
func terrain_height_at(pos: Vector3) -> float
func get_spawn_points() -> Array[Vector3]
func get_nav_points() -> Array[Vector3]
func get_cover_points() -> Array[Vector3]
func set_quality(quality: String) -> void  # low / medium / high / ultra
```

The environment must expose `get_quality()`, `get_sun()`, `get_world_environment()`
when needed by integration.

### Gameplay

```gdscript
# player.gd
extends CharacterBody3D

func spawn(pos: Vector3, yaw: float) -> void
func take_damage(amount: float, attacker: Node) -> void
func get_camera() -> Camera3D
func get_state() -> Dictionary
func set_input_enabled(value: bool) -> void
func switch_weapon(index: int) -> void

signal health_changed(current: int, maximum: int)
signal player_died()
signal player_respawned()
signal weapon_fired(origin: Vector3, direction: Vector3, weapon_type: String)
signal ammo_changed(current: int, reserve: int, weapon_name: String)
signal weapon_switched(name: String)
signal footstep(volume: float)
signal muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String)
```

`weapons.gd` and `projectiles.gd` are children of the player or the main scene
and expose `fire(origin, dir, type)`, `switch_weapon(index)`, `reload()`,
`update(delta)`.

### AI and game mode

```gdscript
# enemy_system.gd
extends Node3D

func setup(player: CharacterBody3D, spawn_points: Array[Vector3], nav_points: Array[Vector3], cover_points: Array[Vector3]) -> void
func spawn_teams() -> void
func update(delta: float) -> void
func get_alive_counts() -> Dictionary
func damage_enemy(enemy: Node, amount: float, point: Vector3) -> void

signal enemy_killed(team: String, name: String)
```

```gdscript
# capture_zones.gd
extends Node3D

func setup(zone_data: Array[Dictionary]) -> void
func update(delta: float) -> void
func get_control_state() -> Dictionary

signal capture_progress(zone_id: String, team: String, progress: float)
signal zone_captured(zone_id: String, team: String)
```

```gdscript
# game_mode.gd
extends Node3D

func setup(player, enemy_system, capture_zones) -> void
func update(delta: float) -> void
func restart() -> void

signal objective_changed(text: String)
signal game_over(winner: String)
```

### FX, audio, HUD

```gdscript
# effects.gd
extends Node3D

func set_camera(camera: Camera3D) -> void
func muzzle_flash(pos: Vector3, dir: Vector3, weapon_type: String) -> void
func impact(pos: Vector3, normal: Vector3) -> void
func explosion(pos: Vector3, radius: float) -> void
func tracer(from: Vector3, to: Vector3, color: Color) -> void
func casing(pos: Vector3, dir: Vector3) -> void
func update(delta: float) -> void
```

```gdscript
# audio_manager.gd
extends Node3D

func set_camera(camera: Camera3D) -> void
func play_shot(weapon_type: String, distance: float) -> void
func play_impact(volume: float) -> void
func play_explosion(distance: float) -> void
func play_footstep(volume: float) -> void
func play_hit() -> void
```

```gdscript
# hud.gd
extends CanvasLayer

func update_state(state: Dictionary) -> void
func show_message(text: String, color: Color = Color.WHITE) -> void
func show_game_over(winner: String) -> void
func set_quality_menu(value: String) -> void
```

## Quality gates

- Player movement must be responsive: acceleration, sprint FOV, camera lean,
  landing recovery, no jitter.
- Weapons must have recoil curves, spread, tracers, shell casings, muzzle flash,
  reload timing, and distinct feel across three weapons.
- Enemies must patrol, seek cover, suppress, flank, and aim with latency.
- Capture mode: 4 points, contested state, progress, objective UI, victory.
- Rendering: dynamic sky, volumetric fog, SSAO, glow, ACES tonemapping, shadow
  cascades, procedural terrain, water, instanced vegetation, smoke, explosions.
- Performance: stable 60 FPS on medium desktop hardware; instancing for repeated
  objects; no allocation in `_physics_process` hot paths where avoidable.
- Every script must parse with `godot --headless --path godot --check-only`
  or equivalent, and the main scene must run without script errors.

## Blind test

`tools/visual_capture.gd` writes PNG screenshots from fixed cinematic camera
positions. The Three.js version already emits screenshots into
`public/screenshots/`; Godot output is written to `godot/screenshots/` and then
copied into the public manifest for A/B comparison.
