# 战地风云 2035 — 架构契约

这是一个基于 Three.js 的中型 FPS。所有模块通过 `src/core/Events.js` 的事件总线或明确构造函数注入协作，避免循环依赖。

## 目录

- `src/main.js` 入口：创建渲染器、场景、相机、`Game`。
- `src/core/Game.js` 总编排：实例化所有系统、注册事件、驱动 update 循环。
- `src/core/Events.js` EventBus 单例。
- `src/core/Noise.js` 随机噪声工具。
- `src/core/Textures.js` 程序化 PBR 贴图工厂。
- `src/core/Physics.js` 轻量碰撞/射线物理世界。
- `src/render/Sky.js` 天空、太阳、云、大气。
- `src/render/Terrain.js` 地形高度场、道路、水面。
- `src/render/Environment.js` 建筑、掩体、车辆、植被、灯光、贴花。
- `src/render/Weather.js` 雨、尘、雾、动态天气。
- `src/render/PostFX.js` 后处理链：SSAO/Bloom/ColorGrade/Vignette/FXAA。
- `src/gameplay/Player.js` 第一人称控制器、生命、移动、相机反馈。
- `src/gameplay/Weapons.js` 武器定义、视模型、开火、换弹、机瞄。
- `src/gameplay/Projectiles.js` 子弹、火箭、手雷。
- `src/gameplay/Enemies.js` AI 士兵、无人机、波次。
- `src/effects/Particles.js` 粒子池。
- `src/effects/Explosions.js` 爆炸、烟雾、冲击。
- `src/audio/AudioManager.js` WebAudio 程序化音效。
- `src/ui/HUD.js` DOM HUD 与菜单。
- `src/config/Quality.js` 画质档位。

## 系统构造签名（实现时必须匹配）

```js
new SkySystem(scene, quality)
new TerrainSystem(scene, quality)
new EnvironmentSystem(scene, physics, terrain, quality)
new WeatherSystem(scene, camera, quality)
new PostFX(renderer, scene, camera, quality)
new PlayerController(camera, scene, physics, events, terrain, quality)
new WeaponSystem(scene, camera, player, physics, events, quality)
new ProjectileSystem(scene, physics, events, particles, explosions, quality)
new EnemySystem(scene, physics, player, events, environment, terrain, quality)
new ParticleSystem(scene, quality)
new ExplosionSystem(scene, physics, events, particles, quality)
new AudioManager()
new HUD(events)
```

## 关键方法

- `SkySystem.update(time, dt)`、`setWeather(type)`
- `TerrainSystem.heightAt(x, z)`、`update(dt)`
- `EnvironmentSystem.update(dt, time, camera)`、`getSpawnPoints()`、`getNavPoints()`
- `WeatherSystem.update(dt)`、`setWeather(type)`
- `PostFX.render(dt)`、`resize(w, h)`
- `PlayerController.update(dt, input)`、`getPosition()`、`getCamera()`、`getHealth()`、`damage(amount, dir)`
- `WeaponSystem.update(dt, input)`、`switchWeapon(i)`、`getState()`
- `ProjectileSystem.update(dt)`
- `EnemySystem.update(dt)`、`spawnWave(n)`、`getAliveCount()`
- `ParticleSystem.update(dt)`、`burst(options)`、`muzzleFlash(pos, dir)`、`smoke(pos, color)`、`sparks(pos)`、`dust(pos)`
- `ExplosionSystem.explode(pos, radius, power, type)`、`update(dt)`
- `AudioManager.init()`、`playShot(type, distance)`、`playExplosion(distance)`、`playFootstep()`、`playReload()`、`playHit()`
- `HUD.update(state)`、`showMenu()`、`hideMenu()`、`showDeath()`、`hideDeath()`、`addKillFeed(text)`、`damageFlash()`、`setObjective(text)`

## 事件契约

```js
events.emit('player:health', { health, maxHealth });
events.emit('player:damage', { amount, direction });
events.emit('player:death', {});
events.emit('player:respawn', {});
events.emit('weapon:fire', { origin, direction, damage, tracerColor, weaponType });
events.emit('weapon:muzzle', { position, direction, weaponType });
events.emit('enemy:fire', { origin, direction, damage, tracerColor });
events.emit('weapon:ammo', { current, reserve });
events.emit('weapon:switch', { name });
events.emit('weapon:reload', {});
events.emit('explosion:detonated', { position, radius, power, type });
events.emit('damage:target', { target, amount, point, source });
events.emit('enemy:kill', { name });
events.emit('killfeed', { text });
events.emit('objective', { text });
events.emit('game:wave', { wave });
```

`weapon:fire` 由 `WeaponSystem` 发出，`Game` 把它转给 `ProjectileSystem.fireHitScan`。
`enemy:fire` 由 `EnemySystem` 发出，`Game` 同样转给 `ProjectileSystem.fireHitScan`，并播放敌方枪声与枪口闪光。
`explosion:detonated` 由 `ProjectileSystem` 发出，`Game` 转给 `ExplosionSystem.explode`，`PlayerController` 与 `EnemySystem` 各自监听做范围伤害。
`damage:target` 由命中判定发出，`EnemySystem` 监听并结算。

## 命中判定

`PlayerController` 和每个敌人都会在 `PhysicsWorld` 注册一个 `sphere`，`userData.entity` 指向自身。
`ProjectileSystem.fireHitScan` 命中后发出 `damage:target { target, amount, point, source }`。
玩家与敌人监听该事件，只响应自己的 `entity`。

## 品质要求

- 主场景必须包含：动态天空、体积感云层、PBR 地面、可交互掩体、车辆残骸、植被、战火烟尘、爆炸与弹道曳光、程序化音效、完整 HUD。
- 后处理链必须包含 SSAO、Bloom、色调映射、暗角、色彩校正；高画质下启用阴影级联。
- 必须使用 InstancedMesh 处理植被/弹壳/碎石等大量实例。
- 所有贴图由 `Textures.js` 程序化生成，禁止外部加载。
