# Project Pocket Circuit Online
## Full Game Design + Technical Specification

**Document status:** Pre-production specification  
**Engine:** Godot 4.7+  
**Primary language:** GDScript for gameplay/client, with backend services implemented independently as needed  
**Genre:** Online arcade racing / persistent multiplayer / light RPG / vehicle progression  
**Working title:** **Pocket Circuit Online**  
**Core inspiration:** the readable miniature chaos and same-screen pressure of *Micro Machines 2: Turbo Tournament*, combined with the race-to-earn-to-upgrade economy and vehicle-part progression associated with classic *Road Rash* games.

> **Important:** This is an original game design inspired by the *structure and feel* of classic arcade racers. It should not reuse copyrighted names, tracks, art, characters, music, UI, vehicle designs, or other protected content from *Micro Machines*, *Road Rash*, or any other game.

---

# 1. Executive Summary

**Pocket Circuit Online** is a fast, top-down 3D arcade racing game where tiny vehicles race through oversized everyday environments: kitchen counters, workshops, offices, supermarkets, rooftops, gardens, arcades, warehouses, toy stores, garages, construction sites, and other spaces that become enormous obstacle courses at miniature scale.

The moment-to-moment game should feel immediate and chaotic:

- accelerate;
- brake;
- drift;
- bump rivals;
- dodge giant environmental hazards;
- take shortcuts;
- use limited active vehicle abilities;
- survive mistakes;
- fight for screen position;
- finish a race in a few minutes;
- immediately want another one.

The long-term game is an online persistent progression game.

Players own vehicles, install parts, tune setups, earn currency, build collections, specialize cars, increase reputation with racing factions, join crews, compete in seasons, chase leaderboard times, and unlock new locations.

The word **MMO** does **not** mean that 500 physical cars race in the same physics simulation.

Instead:

- accounts exist in one persistent online world;
- garages, inventory, currencies, progression, crews, leaderboards, seasons, markets, events, and social systems persist;
- social hubs can contain many players;
- races run as smaller dedicated server instances;
- world events connect the entire population through shared objectives and rankings.

This architecture gives the game MMO persistence without sacrificing the precision required by arcade racing.

---

# 2. High-Level Vision

## 2.1 One-Sentence Pitch

> A persistent online miniature arcade racing world where every three-minute race feeds an RPG-like garage progression system.

## 2.2 Player Fantasy

The player should feel like:

1. a reckless miniature racing driver;
2. a garage owner building increasingly ridiculous machines;
3. a collector hunting rare parts and vehicles;
4. a tuner creating specialized race builds;
5. a competitor climbing divisions and leaderboards;
6. a member of a larger online racing community.

## 2.3 Design Pillars

### Pillar 1 — Easy to Drive, Hard to Master

A new player must understand movement within seconds.

Mastery comes from:

- racing lines;
- braking;
- drifting;
- boost timing;
- shortcut knowledge;
- surface knowledge;
- collision management;
- opponent prediction;
- vehicle tuning.

The game should never become a realistic simulator.

### Pillar 2 — Miniature Scale Creates the Spectacle

The environment is the star.

A coffee cup is a wall.

A puddle is a lake.

A ruler is a bridge.

A spinning desk fan is a moving hazard.

A sink is a canyon.

A keyboard is rough terrain.

A pet crossing the track can be a temporary world event.

Tracks should feel like races built through a gigantic human world rather than purpose-built racing circuits.

### Pillar 3 — Every Race Advances Something

Even a loss should usually produce meaningful progress.

A race can advance:

- credits;
- account XP;
- vehicle mastery;
- part mastery;
- faction reputation;
- seasonal objectives;
- crew objectives;
- achievements;
- leaderboard placement;
- crafting materials.

Losing must hurt competitive ranking more than it hurts general progression.

### Pillar 4 — Vehicles Are Builds, Not Just Skins

Cars should behave differently.

Parts should create noticeable handling changes.

Examples:

- light high-revving sprint build;
- heavy collision-resistant bruiser;
- grip-focused technical build;
- loose drift build;
- acceleration-focused elimination build;
- high top-speed time-trial build;
- wet-surface specialization;
- off-road shortcut specialization.

### Pillar 5 — Competitive Integrity

Progression must create ownership and specialization without making ranked racing meaningless.

The solution is a combination of:

- performance classes;
- gear-score brackets;
- normalized ranked playlists;
- build-limited competitive events;
- open-power casual events;
- matchmaking rating.

### Pillar 6 — Short Races, Long Career

Typical races should last approximately **2–5 minutes**.

The meta-game should last hundreds of hours.

---

# 3. Design Goals

## 3.1 Primary Goals

1. Recreate the immediacy of classic top-down arcade racing in a modern online game.
2. Make vehicle control enjoyable before progression systems are added.
3. Create an addictive race → rewards → garage → upgrade → race loop.
4. Support long-term online progression without mandatory grinding.
5. Make different vehicles and builds genuinely distinct.
6. Support solo, party, crew, competitive, and time-trial players.
7. Build the architecture around server-authoritative multiplayer from the beginning.
8. Make content production modular enough that new tracks, events, parts, and vehicles can be added continuously.

## 3.2 Non-Goals

The initial game is **not**:

- a realistic motorsport simulator;
- an open-world driving simulator;
- a 100-player battle royale;
- a physics sandbox;
- a player-driven cryptocurrency economy;
- a full player-to-player auction-house economy at launch;
- a vehicular combat game where weapons dominate racing;
- pay-to-win.

---

# 4. Target Platforms

## 4.1 Initial

Primary:

- Windows
- Linux

Strong secondary target:

- Steam Deck

## 4.2 Later

Potential:

- macOS
- consoles

Web should **not** drive the core networking architecture because the real-time race mode benefits from native UDP-based networking.

## 4.3 Input

Required:

- keyboard;
- Xbox-compatible controller;
- PlayStation-style controller.

Optional later:

- mobile/touch;
- steering wheel support as novelty/accessibility rather than simulation.

---

# 5. Core Gameplay Loop

```text
LOGIN
  ↓
SOCIAL HUB / GARAGE
  ↓
CHOOSE VEHICLE + BUILD
  ↓
SELECT EVENT / QUEUE
  ↓
MATCHMAKING
  ↓
2–5 MINUTE RACE
  ↓
RESULTS
  ↓
XP + CREDITS + REPUTATION + PART DROPS
  ↓
UPGRADE / TUNE / SALVAGE / CRAFT
  ↓
UNLOCK NEW CONTENT
  ↓
QUEUE AGAIN
```

Long-form loop:

```text
Races
→ Better knowledge
→ Better parts
→ More vehicles
→ More builds
→ Higher divisions
→ Harder events
→ More valuable rewards
→ Seasonal goals
→ Crew competition
→ Prestige
```

---

# 6. Session Structure

## 6.1 5-Minute Session

Player:

- logs in;
- claims pending rewards;
- presses Quick Race;
- completes one race;
- receives rewards;
- exits.

The game must feel worthwhile even at this duration.

## 6.2 20-Minute Session

Player:

- completes 4–6 races;
- finishes daily objectives;
- levels a vehicle;
- upgrades one or two parts;
- compares leaderboard times.

## 6.3 60-Minute Session

Player:

- joins friends;
- races several playlists;
- modifies builds;
- attempts a ranked promotion;
- participates in a world event;
- contributes to crew progression.

## 6.4 Multi-Month Session

Player:

- accumulates a garage;
- perfects multiple class builds;
- reaches seasonal ranks;
- joins competitive events;
- completes collections;
- chases rare cosmetics and prestige rewards.

---

# 7. Racing Camera

## 7.1 Default View

The game uses a **top-down / high three-quarter perspective** in fully 3D environments.

The camera should:

- remain readable at speed;
- show enough track ahead for reaction;
- subtly rotate with track direction;
- zoom based on speed;
- compensate for elevation;
- prevent giant environment geometry from blocking the car.

## 7.2 Camera Modes

### Follow Camera

Standard online mode.

Camera follows the local player.

### Dynamic Group Camera

Optional local multiplayer or special elimination modes.

Camera frames multiple racers.

A player leaving the safe screen region can be eliminated or concede a point.

### Spectator Camera

Supports:

- follow racer;
- leader focus;
- free track camera;
- automatic broadcast director.

## 7.3 Camera Collision

Environment objects between camera and racer should:

1. become transparent;
2. fade to an outline;
3. hide temporarily;
4. never make the player blind.

---

# 8. Vehicle Controls

Default digital controls:

```text
Accelerate
Brake / Reverse
Steer Left
Steer Right
Handbrake / Drift
Boost / Active Ability
Reset
Look Back / Rear Indicator
```

Controller:

```text
RT = accelerate
LT = brake/reverse
Left Stick = steer
A / Cross = handbrake/drift
B / Circle = active ability
Y / Triangle = reset
Right Stick / bumper = camera/context
```

The exact mapping must be remappable.

---

# 9. Driving Model

## 9.1 Philosophy

Physics should create believable momentum without demanding simulation skills.

The game should feel like a physical toy car that has been intentionally tuned for an arcade game.

## 9.2 Core Variables

Each vehicle exposes:

```text
mass
engine_power
max_speed
acceleration
reverse_speed
steering_rate
steering_response
grip
lateral_grip
drift_factor
brake_force
handbrake_force
suspension_stability
collision_resistance
air_control
boost_power
boost_capacity
boost_recharge
durability
```

## 9.3 Steering

At low speed:

- aggressive steering;
- tight turning radius.

At high speed:

- reduced direct steering;
- more lateral slip;
- increased importance of braking and drift.

This prevents twitchy high-speed movement.

## 9.4 Drift

Drifting should be deliberate but accessible.

Possible trigger:

```text
high steering input
+
handbrake
+
minimum speed
```

During drift:

- lateral grip decreases;
- rotation responsiveness increases;
- speed decreases gradually;
- successful controlled drift can charge a small boost meter.

Drift should not be optimal on every corner.

## 9.5 Collision

Vehicle-to-vehicle collision must feel physical but not ruin races constantly.

Rules:

- speed difference matters;
- mass matters;
- impact angle matters;
- side contacts create smaller disturbances;
- hard rear impacts can push;
- head-on collisions are severe;
- low-speed contact should be forgiving.

Server resolves authoritative collision outcomes.

## 9.6 Recovery

If the player:

- falls from the track;
- becomes stuck;
- flips;
- lands in an invalid zone;

the game triggers recovery.

Recovery cost may include:

- 1–3 seconds;
- temporary ghost state;
- loss of boost.

It should **not** remove the player from the race for a single mistake.

---

# 10. Surfaces

Tracks contain meaningful surfaces.

Examples:

| Surface | Grip | Speed | Special |
|---|---:|---:|---|
| Polished wood | Medium | High | Long slides |
| Carpet | High | Low | Strong acceleration penalty |
| Tile | Medium | High | Predictable |
| Wet tile | Low | Medium | Sliding |
| Paper | Medium | Medium | Lightweight movable pieces |
| Metal | Medium | High | Strong sound feedback |
| Dirt | Medium-low | Medium | Off-road tires matter |
| Oil | Very low | Medium | Temporary hazard |
| Ice | Very low | High | Advanced control |
| Sticky spill | High | Very low | Trap surface |

Parts can alter how a build handles surfaces.

---

# 11. Track Philosophy

Tracks should be remembered by **objects and moments**, not merely by curve geometry.

A good track contains:

- one iconic opening;
- one early conflict point;
- one memorable hazard;
- one shortcut decision;
- one technical section;
- one speed section;
- one dramatic finish.

Example:

```text
Kitchen Counter Sprint

Start beside toaster
→ weave between cereal pieces
→ jump across open drawer
→ sharp turn around coffee mug
→ optional shortcut across wet sponge
→ pass under dripping faucet
→ spoon bridge
→ finish beside cutting board
```

---

# 12. World Themes

Launch-quality world themes could include:

## 12.1 Kitchen

Objects:

- plates;
- cups;
- cereal;
- cutlery;
- sink;
- sponge;
- water;
- toaster;
- fruit;
- stovetop.

## 12.2 Workshop

Objects:

- tools;
- screws;
- sawdust;
- cables;
- oil;
- drills;
- clamps;
- rulers.

## 12.3 Office

Objects:

- keyboards;
- papers;
- pens;
- phones;
- coffee;
- desk organizers;
- printers.

## 12.4 Backyard

Objects:

- grass;
- soil;
- stones;
- hose;
- patio;
- barbecue;
- flower pots.

## 12.5 Supermarket

Objects:

- shelves;
- cans;
- bottles;
- checkout conveyor;
- spilled products;
- shopping carts.

## 12.6 Arcade

Objects:

- arcade cabinets;
- cables;
- coins;
- carpet;
- neon lighting;
- prize machines.

## 12.7 Toy Store

Objects:

- blocks;
- rails;
- toy boxes;
- model towns;
- ramps.

## 12.8 Rooftop

Objects:

- vents;
- gravel;
- rain puddles;
- cables;
- air-conditioning units;
- dangerous edges.

---

# 13. Environmental Hazards

Hazards should create decisions rather than random unavoidable punishment.

Examples:

- rolling marble;
- fan gust;
- dripping water;
- moving office chair wheel;
- closing drawer;
- toaster pop;
- falling dominoes;
- cat paw crossing the course;
- vacuum airflow;
- swinging cable;
- moving conveyor;
- automatic door;
- sprinkler;
- falling tools;
- bouncing tennis ball.

Hazards require deterministic server timing or server authority.

Players should receive audiovisual telegraphs before dangerous activation.

---

# 14. Shortcuts

Every major track should ideally include at least one shortcut.

Shortcut categories:

### Skill Shortcut

Faster but mechanically difficult.

### Build Shortcut

Requires enough:

- grip;
- acceleration;
- suspension;
- off-road performance.

### Risk Shortcut

Dangerous but available to everyone.

### Dynamic Shortcut

Only becomes available during certain hazard states.

A shortcut must never require a rare paid or loot-exclusive part.

---

# 15. Race Modes

## 15.1 Circuit Race

Classic laps.

Typical:

- 6–12 racers;
- 2–4 laps;
- 3–5 minutes.

## 15.2 Sprint

Point A → B.

Supports more environmental storytelling and giant set pieces.

## 15.3 Screen King

Strongly inspired by classic same-screen distance battles.

Rules:

- players race continuously;
- if one racer establishes enough screen/distance advantage, that racer scores a point;
- field resets;
- first to target score wins.

Online variant uses track-distance thresholds rather than trusting a literal client viewport.

Possible settings:

```text
1v1
2v2
Free-for-all 4
First to 5
First to 7
```

This should become a signature mode.

## 15.4 Elimination

At intervals:

- last place eliminated;
- remaining racers continue;
- final racer wins.

## 15.5 Knockout Laps

At each lap:

- bottom racers eliminated.

## 15.6 Time Trial

Solo.

Features:

- global ghost;
- personal best ghost;
- friend ghost;
- crew ghost;
- class leaderboard;
- build leaderboard.

## 15.7 Daily Track

Everyone receives:

- same track;
- same weather;
- same vehicle class;
- optionally normalized vehicle.

Excellent for fair leaderboards.

## 15.8 Crew Battle

Crew points are earned through:

- placements;
- lap times;
- participation;
- weekly objectives.

Avoid requiring every crew member online simultaneously.

## 15.9 Chaos Event

Casual rotating modes:

- giant hazards;
- reverse track;
- low grip;
- infinite boost;
- random vehicle;
- bumper-heavy physics;
- obstacle survival.

Rewards are useful but not ranked-critical.

---

# 16. Match Sizes

Recommended initial limits:

| Mode | Players |
|---|---:|
| 1v1 Screen King | 2 |
| Small race | 4 |
| Standard race | 8 |
| Large race | 12 |
| Chaos | 12–16 |
| Social hub | 30–100+ depending on implementation |

Do **not** begin development by optimizing for huge race populations.

Eight excellent synchronized cars are more valuable than sixty bad ones.

---

# 17. Vehicle Classes

Performance classes:

```text
D
C
B
A
S
X / Prototype
```

Class is determined by a combination of:

- vehicle base rating;
- installed parts;
- tuning;
- performance cap.

A car can move between some classes through upgrades.

Example:

```text
Rustbug
Base: D
Maximum tuned: B
```

while:

```text
V12 Needle
Base: A
Maximum tuned: S
```

This allows beloved early vehicles to remain useful without making every chassis identical.

---

# 18. Vehicle Archetypes

## Lightweight

Strengths:

- acceleration;
- steering;
- recovery.

Weaknesses:

- collisions;
- stability.

## Muscle / Heavy

Strengths:

- mass;
- durability;
- pushing;
- straight-line speed.

Weaknesses:

- turning;
- recovery.

## Grip

Strengths:

- technical tracks;
- braking;
- consistency.

Weaknesses:

- less drift bonus;
- moderate top speed.

## Drift

Strengths:

- rotation;
- boost generation;
- long corners.

Weaknesses:

- difficult precision.

## Off-Road

Strengths:

- carpet;
- dirt;
- rough shortcuts.

Weaknesses:

- polished high-speed surfaces.

## Prototype

Extreme strengths and weaknesses intended for advanced builds.

---

# 19. Garage

The garage is the emotional center of progression.

The player can:

- inspect vehicle;
- rotate/preview;
- install parts;
- compare stats;
- tune setup;
- repair;
- repaint;
- apply decals;
- equip cosmetics;
- save builds;
- test drive;
- view mastery;
- view historical race statistics.

## 19.1 Saved Loadouts

Each vehicle supports multiple loadouts.

Example:

```text
TECHNICAL
WET
SPRINT
ELIMINATION
FUN
```

Changing a loadout outside a race is free.

---

# 20. Part System

This is the primary long-term RPG-like system.

The core system should echo the satisfaction of upgrading distinct vehicle systems rather than simply increasing one global number.

## 20.1 Main Part Slots

Recommended slots:

1. Engine
2. Transmission
3. Tires
4. Suspension
5. Chassis
6. Brakes
7. Boost System
8. Differential / Handling Module
9. Utility Module

The strongest connection to classic Road Rash-style progression comes from emphasizing:

- engine performance;
- chassis durability;
- tires;
- suspension.

## 20.2 Engine

Affects:

- acceleration;
- top speed;
- heat/boost interactions.

Possible identities:

- torque engine;
- high-RPM engine;
- efficient engine;
- sprint engine.

## 20.3 Transmission

Affects:

- acceleration curve;
- top speed;
- response after crashes;
- speed recovery.

## 20.4 Tires

Affects:

- grip;
- lateral grip;
- surface modifiers;
- braking.

Variants:

```text
slick
all-surface
wet
off-road
drift
```

## 20.5 Suspension

Affects:

- stability;
- landing recovery;
- rough surface speed;
- curb interaction;
- bump resistance.

## 20.6 Chassis

Affects:

- mass;
- durability;
- collision response.

Examples:

- lightweight frame;
- reinforced frame;
- balanced chassis.

## 20.7 Brakes

Affects:

- brake distance;
- turn-in;
- drift initiation.

## 20.8 Boost System

Affects:

- capacity;
- burst power;
- recharge;
- drift conversion.

## 20.9 Differential / Handling Module

Affects:

- rotation;
- drift lock;
- corner exit;
- traction.

## 20.10 Utility

Provides unusual modifiers rather than raw power.

Examples:

- faster reset;
- reduced hazard slow;
- stronger drafting;
- increased drift charge;
- better recovery acceleration.

---

# 21. Part Quality

Suggested rarity tiers:

```text
Standard
Tuned
Performance
Elite
Prototype
Legendary
```

Rarity should mostly increase:

- build flexibility;
- specialization;
- affix quality;
- cosmetic prestige.

Avoid enormous raw-stat gaps.

A great Standard part with the correct specialization should sometimes be preferable to an irrelevant Legendary part.

---

# 22. Part Itemization

Example item:

```yaml
id: engine_hummingbird_v3
slot: engine
rarity: performance
class_requirement: C
level: 18

base:
  acceleration: +7.0%
  max_speed: +2.0%

affixes:
  - exit_acceleration: +4.0%
  - boost_heat_reduction: +6.0%

trait:
  name: Quick Recovery
  effect: +10% acceleration for 1.2s after landing
```

---

# 23. Part Affixes

Examples:

## Offensive Racing Affixes

- acceleration after collision;
- slipstream power;
- boost output;
- top speed above 90% throttle.

## Technical Affixes

- braking stability;
- drift steering;
- grip after drift;
- landing stability.

## Recovery Affixes

- reset delay reduction;
- acceleration after reset;
- hazard resistance.

## Surface Affixes

- wet grip;
- carpet speed;
- dirt acceleration.

Affixes should be understandable.

Avoid Diablo-style walls of tiny percentages.

---

# 24. Part Upgrade System

Parts gain **Mastery XP** while equipped.

Mastery unlocks small choices.

Example:

```text
Engine Level 1
  base stats

Level 2
  +minor acceleration

Level 3
  choose:
    A: stronger launch
    B: higher top speed

Level 4
  cosmetic engine effect

Level 5
  trait enhancement
```

This makes using a part meaningful rather than constantly discarding it.

---

# 25. Part Tuning

Tuning should create tradeoffs.

Example tire tuning:

```text
GRIP <------ BALANCED ------> DRIFT
```

Example gearbox:

```text
ACCELERATION <-------------> TOP SPEED
```

Example suspension:

```text
SOFT <---------------------> STIFF
```

The player can change tuning freely outside ranked lock-in.

---

# 26. Part Sets

Use sparingly.

Example:

**Workshop Rat Set**

2-piece:

- +rough-surface speed.

3-piece:

- landing recovery boost.

4-piece:

- shortcut surfaces reduce less speed.

Set bonuses must not become mandatory best-in-slot.

---

# 27. Vehicle Damage and Repair Economy

Borrow the emotional concept of damage and repair costs without creating a punishment spiral.

During a race, vehicles can accumulate temporary damage.

Damage can affect:

- visual body state;
- small handling penalty in specific modes;
- durability bar in hardcore events.

After standard races:

- routine repair is free or nearly free.

For special high-stakes events:

- damage can create a meaningful credit repair bill.

Never allow:

```text
player loses
→ cannot afford repair
→ cannot play
```

The economy should create tension, not lockout.

---

# 28. Vehicle Acquisition

Vehicles can come from:

- starter choices;
- dealership;
- reputation unlocks;
- seasonal reward tracks;
- challenge chains;
- crafting/restoration;
- prestige events.

Avoid random loot boxes for gameplay vehicles.

---

# 29. Vehicle Mastery

Each chassis has mastery.

Mastery rewards:

- decals;
- paint;
- title;
- profile badge;
- tuning preset slot;
- small side-grade unlock;
- unique cosmetic;
- vehicle-specific challenge.

Mastery should mostly express commitment, not mandatory power.

---

# 30. Player Progression

There are several parallel progression tracks.

## 30.1 Account Level

Represents general experience.

Unlocks:

- systems;
- locations;
- event types;
- garage features.

## 30.2 Driver License / Career Tier

Example:

```text
Rookie
Street
Club
Regional
National
Elite
Master
Legend
```

Unlock conditions combine:

- level;
- event completion;
- performance challenges.

## 30.3 Vehicle Mastery

Per chassis.

## 30.4 Part Mastery

Per owned item or part family.

## 30.5 Faction Reputation

Per racing organization.

## 30.6 Seasonal Rank

Competitive and temporary.

## 30.7 Crew Reputation

Shared group progression.

---

# 31. Driver Skill Tree

Driver skills should be mostly horizontal.

Example categories:

## Racer

- extra drafting feedback;
- improved start timing indicator;
- ghost comparison features.

## Mechanic

- lower crafting costs;
- extra salvage yield;
- more tuning presets.

## Explorer

- extra world-event rewards;
- shortcut discovery challenges.

## Collector

- garage slots;
- cosmetic display features.

Do **not** put large universal speed bonuses into permanent character skill trees.

---

# 32. Factions

Example original factions:

## Countertop Racing Club

Technical races.

Rewards:

- grip parts;
- clean liveries.

## Junkyard Union

Collision-heavy and rough terrain.

Rewards:

- chassis;
- suspension;
- industrial cosmetics.

## Midnight Circuit

Time trials and precision.

Rewards:

- lightweight parts;
- neon cosmetics.

## Backyard Outlaws

Off-road and risky shortcuts.

Rewards:

- tires;
- boost modules;
- dirt cosmetics.

## Prototype Lab

End-game experimental events.

Rewards:

- unusual side-grade parts.

---

# 33. MMO / Persistent World Structure

## 33.1 Account World

Persistent:

- identity;
- garage;
- inventory;
- currency;
- progression;
- friends;
- crew;
- mail;
- objectives;
- season state;
- rankings.

## 33.2 Social Hubs

Players enter themed hub instances.

Example:

**The Garage District**

Contains:

- dealership;
- mechanic;
- tuning bench;
- event terminal;
- crew terminal;
- showcase zone;
- test track;
- player vehicles on display.

Players can:

- walk as stylized avatars;
- drive slowly in designated spaces;
- emote;
- inspect vehicles;
- invite to party;
- enter events together.

For MVP, this can be a menu-driven shared garage before becoming a physical hub.

## 33.3 Race Instances

Each race is a separate dedicated server process or assigned match instance.

The persistent backend does not run race physics.

## 33.4 World Events

The population contributes toward global objectives.

Examples:

```text
Complete 2,000,000 laps this weekend
Beat the Workshop World Boss Time
Collect 5,000,000 loose screws
Crew Championship Week
```

Rewards can unlock globally when thresholds are reached.

---

# 34. Matchmaking

Inputs:

```text
region
latency
playlist
party size
MMR
vehicle class
power rating
player experience
queue duration
```

Priority:

1. good latency;
2. correct playlist/class;
3. fair skill;
4. low queue time.

Search range expands gradually.

---

# 35. Competitive Fairness

Progression games create a power problem.

This design solves it with multiple race categories.

## 35.1 Open Build

Bring anything within class limits.

Parts matter fully.

Best for:

- casual;
- progression;
- experimentation.

## 35.2 Homologated

Part stats are capped to a class rating.

Build identity remains but extreme power is normalized.

## 35.3 Spec Race

Everyone uses the same vehicle and setup.

Pure skill.

## 35.4 Draft Event

Players choose from temporary provided builds.

## 35.5 Ranked

Primary ranked mode should use:

- homologation;
- strict class caps;
- no consumable power advantages.

---

# 36. Ranked System

Example divisions:

```text
Bronze
Silver
Gold
Platinum
Diamond
Master
Champion
```

Rank is based on MMR, not account XP.

Seasonal soft reset.

Rewards:

- cosmetics;
- titles;
- banners;
- garage trophies;
- profile effects.

Avoid exclusive gameplay power for top-ranked players.

---

# 37. Race Rewards

Base formula:

```text
reward =
  participation_base
  + placement_bonus
  + clean_racing_bonus
  + difficulty_bonus
  + event_modifier
  + objective_bonus
```

Do not base rewards only on winning.

Example:

```text
8-player race

8th:
  100 credits

4th:
  145 credits

1st:
  210 credits
```

A weaker player still progresses.

---

# 38. Economy

## 38.1 Currencies

### Credits

Primary soft currency.

Earned from racing.

Used for:

- vehicles;
- common parts;
- upgrading;
- tuning services;
- limited repair;
- crafting.

### Scrap

Earned by salvaging parts.

Used for crafting.

### Reputation Tokens

Faction-specific progression.

### Premium Currency

Optional monetization.

Use only for:

- cosmetics;
- convenience that does not increase race performance;
- season cosmetic pass.

---

# 39. Economy Sinks

Necessary sinks:

- vehicle purchases;
- part upgrades;
- crafting;
- cosmetic purchases;
- garage expansion;
- high-level rerolls;
- high-stakes event entry;
- optional repairs in hardcore modes.

Avoid inflation by monitoring:

```text
credits created per day
credits destroyed per day
median balance
balance by account age
```

---

# 40. Salvage and Crafting

Unwanted parts can be salvaged.

Output:

```text
Scrap
+
Part-family material
+
small chance of special component
```

Crafting should allow targeting.

Bad:

```text
Spend everything
→ receive completely random part
```

Better:

```text
Choose:
Engine
Class B
Grip family

Randomize:
exact model
secondary affix
quality roll
```

---

# 41. Trading

Recommendation for launch:

**No unrestricted player-to-player trading of performance parts.**

Reasons:

- reduces real-money trading pressure;
- reduces bot farming;
- prevents economy exploitation;
- simplifies anti-fraud;
- makes balancing easier.

Possible later:

- cosmetic market;
- crew gifting with limits;
- bound/unbound item categories.

---

# 42. Daily / Weekly Systems

Keep them optional.

Examples:

```text
Daily:
Complete 3 races
Drift 600 meters
Finish one Workshop event

Weekly:
Complete 20 races
Win 3 different modes
Set 5 personal bests
Contribute 5,000 crew points
```

Players should not feel punished for missing a day.

---

# 43. Quest / Contract System

Contracts provide RPG flavor without pretending the player is doing a giant narrative campaign.

Examples:

> A mechanic wants tire telemetry from wet surfaces.

Objective:

- finish three wet races with any C-class car.

Reward:

- tire blueprint.

Another:

> The Junkyard Union wants proof the reinforced chassis can survive impacts.

Objective:

- complete a collision event with 50% durability remaining.

---

# 44. Seasons

Typical season:

8–12 weeks.

Season includes:

- theme;
- new track;
- 1–3 vehicles;
- parts;
- ranked reset;
- faction story;
- global event;
- cosmetics;
- challenges.

Avoid deleting old gameplay content unnecessarily.

---

# 45. Crews / Guilds

Crew features:

- name;
- tag;
- emblem;
- roster;
- ranks;
- crew chat;
- weekly objectives;
- crew leaderboard;
- shared cosmetic unlocks.

Later:

- crew garage;
- club tournaments;
- asynchronous territory competition.

Do not make crews mandatory for core progression.

---

# 46. Social Features

Launch priorities:

- friend list;
- party;
- recent players;
- invites;
- crew;
- text chat;
- quick-chat;
- emotes;
- mute/block/report.

Voice chat can be added later or delegated to platform/social solutions.

---

# 47. Ghost System

Ghost data is extremely valuable.

A ghost stores compact race inputs or transform samples.

Uses:

- personal best;
- global record;
- friend challenge;
- tutorial demonstration;
- anti-cheat review;
- track validation.

Leaderboards should store:

```text
player
vehicle
build hash
time
track version
physics version
ghost id
timestamp
```

Track/physics versioning prevents invalid historical comparisons.

---

# 48. Active Abilities

Abilities should enhance racing rather than become combat weapons.

Possible examples:

## Boost

Simple speed burst.

## Grip Pulse

Temporary traction increase.

## Stabilizer

Reduces spin after contact.

## Jump Assist

Improves air correction.

## Recovery Burst

Accelerates after reset.

Competitive ranked modes can:

- restrict abilities;
- normalize them;
- disable certain modules.

---

# 49. Power-Ups

Recommendation:

Use power-ups only in dedicated casual playlists.

Examples:

- boost;
- temporary shield;
- oil slick;
- magnet;
- giant bumper;
- short slow field.

Ranked core racing should not depend on random pickup luck.

---

# 50. New Player Experience

## First 10 Minutes

### Step 1

Choose one of three starter vehicles:

- Grip
- Balanced
- Drift

### Step 2

30-second driving tutorial.

Teach:

```text
accelerate
steer
brake
drift
reset
```

### Step 3

Short solo race.

### Step 4

Reward first upgrade.

Example:

```text
Standard Tires
→ Tuned Street Tires
```

Player immediately sees:

- +grip;
- -slight drift.

### Step 5

First online race.

Bots can fill missing slots.

### Step 6

Return to garage.

Unlock:

- tuning;
- Quick Race;
- faction introduction.

---

# 51. First Hour Example

```text
00:00 Create driver
00:02 Choose starter
00:03 Driving tutorial
00:06 Solo race
00:10 First upgrade
00:12 First online race
00:17 Garage explanation
00:20 Second track
00:25 Unlock time trial
00:30 Obtain first rare-ish part
00:35 Tune vehicle
00:40 Online event
00:45 Unlock second vehicle purchase option
00:50 Faction contract
00:55 Personal-best challenge
01:00 Player has a clear next goal
```

---

# 52. UI Architecture

Major screens:

```text
Login
Character/Profile
World/Home
Garage
Vehicle Selection
Parts
Tuning
Dealership
Crafting
Contracts
Faction
Crew
Friends
Party
Event Browser
Matchmaking
Race HUD
Results
Leaderboard
Season
Settings
```

---

# 53. Race HUD

Must remain minimal.

Required:

- position;
- lap / round;
- checkpoint;
- mini progress strip;
- speed;
- boost;
- ability;
- race timer;
- nearby opponent indicators.

Optional:

- durability;
- split time;
- drift meter.

Do not cover the miniature environment with MMO UI clutter.

---

# 54. Results Screen

Sequence:

1. finishing position;
2. time;
3. rating movement;
4. XP;
5. credits;
6. reputation;
7. part/mastery progress;
8. drops;
9. objectives;
10. rematch / next race.

The player should see progress bars move.

---

# 55. Art Direction

## 55.1 Style

Recommended:

- stylized 3D;
- readable materials;
- saturated but controlled palette;
- exaggerated object scale;
- slightly toy-like vehicles;
- clear silhouettes.

Avoid photorealism.

Why:

- cheaper content;
- better readability;
- stronger identity;
- easier cross-platform performance.

## 55.2 Scale Contrast

Human objects should feel enormous.

Use details such as:

- crumbs;
- scratches;
- droplets;
- fibers;
- dust;
- tiny screws.

These communicate vehicle scale.

## 55.3 Vehicles

Vehicles should look original and fictional.

Design language:

- chunky proportions;
- readable roofs;
- exaggerated wheels;
- strong color blocking.

Top-down readability matters more than realistic side profiles.

---

# 56. Cosmetic System

Cosmetics:

- paint;
- material finish;
- decals;
- wheel style;
- antenna;
- roof decoration;
- boost trail;
- drift particles;
- horn;
- victory animation;
- driver avatar;
- profile banner;
- garage decoration.

Cosmetics must not obscure hitboxes badly.

---

# 57. Audio

Audio priorities:

1. engine clarity;
2. tire feedback;
3. collision impact;
4. boost;
5. surface changes;
6. hazard telegraph;
7. UI reward feedback.

Each vehicle family can have a unique engine identity.

Music:

- energetic;
- compact loops;
- dynamic final-lap layer;
- lower intensity in garage/hub.

---

# 58. Accessibility

Required:

- remappable controls;
- controller support;
- colorblind-friendly UI;
- high contrast race indicators;
- adjustable screen shake;
- adjustable camera rotation;
- reduced flashes;
- subtitle support;
- separate volume controls;
- steering assist;
- auto-accelerate option;
- hold/toggle options where relevant.

---

# 59. Godot Technical Baseline

Target stable baseline at project start:

**Godot 4.7**

Do not bind game data directly to brittle scene paths.

Use a layered architecture.

```text
Presentation
↓
Gameplay
↓
Network
↓
Domain / Shared Rules
↓
Persistence / Backend API
```

---

# 60. Suggested Repository Structure

```text
/
├── project.godot
├── addons/
├── assets/
│   ├── audio/
│   ├── models/
│   ├── materials/
│   ├── textures/
│   └── ui/
│
├── data/
│   ├── vehicles/
│   ├── parts/
│   ├── tracks/
│   ├── factions/
│   ├── progression/
│   └── localization/
│
├── scenes/
│   ├── boot/
│   ├── menu/
│   ├── garage/
│   ├── hub/
│   ├── race/
│   ├── vehicles/
│   ├── tracks/
│   └── ui/
│
├── scripts/
│   ├── autoload/
│   ├── gameplay/
│   ├── vehicle/
│   ├── race/
│   ├── network/
│   ├── progression/
│   ├── inventory/
│   ├── ui/
│   └── utilities/
│
├── server/
│   ├── race/
│   └── config/
│
└── tests/
```

---

# 61. Godot Autoloads

Potential global services:

```text
App
Session
Auth
Api
GameData
Inventory
Garage
Party
Matchmaking
Audio
Settings
Telemetry
```

Do not put all gameplay into autoload singletons.

---

# 62. Vehicle Scene Structure

Example:

```text
Vehicle
├── VisualRoot
│   ├── BodyMesh
│   ├── WheelMeshes
│   └── Cosmetics
│
├── PhysicsBody
├── CollisionShape
├── SurfaceDetector
├── GroundRaycasts
├── NetworkSync
├── Audio
├── PartEffects
└── VFX
```

Possible script composition:

```text
VehicleController
VehiclePhysics
VehicleStats
VehicleDamage
VehicleBoost
VehicleAbility
VehicleNetwork
VehiclePresentation
```

Avoid one 4,000-line `car.gd`.

---

# 63. Vehicle Data

Base vehicles should be data-driven.

Example:

```yaml
id: rustbug
display_name: Rustbug
class: D

base_stats:
  mass: 0.8
  acceleration: 62
  max_speed: 54
  steering: 74
  grip: 70
  durability: 52
  boost: 50

slots:
  engine: 1
  transmission: 1
  tires: 1
  suspension: 1
  chassis: 1
  brakes: 1
  boost: 1
  differential: 1
  utility: 1
```

Data can be represented with Godot Resources during development and exported/validated into backend-compatible data.

---

# 64. Stat Calculation

Recommended pipeline:

```text
base vehicle stats
→ class scaling
→ installed part additive modifiers
→ installed part multiplicative modifiers
→ tuning
→ temporary event modifiers
→ server validation
→ final runtime stats
```

Never trust final client-calculated stats.

The server receives:

```text
vehicle_id
part_instance_ids
tuning_config
```

and builds authoritative stats itself.

---

# 65. Track Scene Structure

```text
Track
├── Environment
├── RaceSpline
├── Checkpoints
├── SpawnPoints
├── RecoveryPoints
├── Hazards
├── Shortcuts
├── SurfaceVolumes
├── Cameras
├── SpectatorPoints
└── NavigationMetadata
```

---

# 66. Checkpoint Validation

A race result is valid only if the player follows legal checkpoint sequence.

Server tracks:

```text
lap
next_checkpoint
checkpoint_time
track_progress
```

Shortcuts must still pass logical checkpoint gates.

---

# 67. Track Progress Metric

For placement, calculate distance along a reference race spline.

Example:

```text
race_progress =
  lap * spline_length
  + current_spline_distance
```

Placement sorts by:

1. finished;
2. lap;
3. checkpoint;
4. spline progress.

Do not calculate placement by raw Euclidean distance to finish.

---

# 68. Networking Model

## 68.1 Core Rule

**Server authoritative.**

The client does not decide:

- real position;
- velocity;
- checkpoint completion;
- collision result;
- item usage validity;
- race finish;
- reward;
- inventory;
- currency.

Client sends **inputs/intents**.

Server simulates and validates.

## 68.2 Race Transport

Recommended initial native transport:

**ENet / UDP through Godot multiplayer APIs.**

## 68.3 Backend Transport

Use HTTPS for:

- auth;
- inventory;
- garage;
- progression;
- event data;
- store.

Use WebSocket optionally for:

- presence;
- chat;
- party updates;
- matchmaking status;
- notifications.

Do not use WebSocket as the primary native high-speed race transport.

---

# 69. Tick Rates

Starting target:

```text
Client render: 60+ FPS
Client physics: 60 Hz
Server simulation: 30–60 Hz
Input send: 30–60 Hz
Snapshots: 15–30 Hz
```

Prototype both:

- 30 Hz server;
- 60 Hz server.

Choose based on measured race feel and hosting cost.

---

# 70. Client Prediction

Local vehicle should respond immediately.

Flow:

```text
client reads input
→ client predicts movement immediately
→ input packet sent with sequence number
→ server simulates authoritative state
→ server sends snapshot + acknowledged input
→ client compares
→ client reconciles difference
```

Corrections should be:

- invisible when small;
- smoothly blended when moderate;
- snapped only when severe.

---

# 71. Remote Vehicle Interpolation

Remote cars are rendered slightly behind real server time using snapshot interpolation.

This provides smooth movement despite jitter.

Do not directly render remote transform packets as they arrive.

---

# 72. Collision Networking

This is one of the hardest systems.

Recommended:

- server resolves final collision;
- clients predict minor contact;
- correction is softened;
- extreme collision outcomes are server-enforced.

Prioritize fairness over perfect visual agreement.

---

# 73. Lag Compensation

For racing, avoid shooter-style heavy rollback unless needed.

Primary tools:

- input prediction;
- reconciliation;
- interpolation;
- bounded collision forgiveness.

High latency should not allow impossible collision exploits.

---

# 74. Network Message Channels

Conceptual channels:

```text
0 Gameplay inputs           unreliable ordered
1 State snapshots           unreliable ordered
2 Race events               reliable
3 Match lifecycle           reliable
4 Chat/social               reliable
5 Telemetry/debug           separate/low priority
```

Examples of reliable race events:

- race start;
- finish;
- elimination;
- ability activation accepted;
- checkpoint penalty;
- disconnect status.

---

# 75. Dedicated Race Server

Run Godot in headless/dedicated mode.

Race server responsibilities:

- load track;
- validate match token;
- spawn vehicles;
- calculate authoritative stats;
- simulate race;
- validate checkpoints;
- detect finish;
- record race telemetry;
- submit signed result to backend.

Race server should not directly modify arbitrary database rows.

It sends a result payload to trusted backend services.

---

# 76. Backend Architecture

Logical services:

```text
API Gateway
├── Authentication
├── Account/Profile
├── Inventory
├── Garage
├── Progression
├── Economy
├── Matchmaking
├── Party/Presence
├── Crew
├── Leaderboards
├── Live Ops
└── Telemetry
```

MVP can begin as a modular monolith.

Do **not** start with twelve microservices merely because the game is called an MMO.

Recommended evolution:

```text
Phase 1:
Single backend application + PostgreSQL + Redis

Phase 2:
Extract matchmaking / presence / leaderboard where needed

Phase 3:
Scale services independently
```

---

# 77. Persistence

Recommended primary database:

**PostgreSQL**

Good fit for:

- accounts;
- inventories;
- transactions;
- vehicles;
- part instances;
- crews;
- progression.

Recommended cache/ephemeral state:

**Redis**

Potential uses:

- sessions;
- matchmaking queues;
- presence;
- rate limits;
- temporary leaderboard caches.

---

# 78. Inventory Data Model

Simplified entities:

```text
Account
Profile
CurrencyBalance
VehicleDefinition
OwnedVehicle
PartDefinition
PartInstance
VehicleLoadout
FactionProgress
SeasonProgress
ObjectiveProgress
Crew
CrewMember
RaceResult
LeaderboardEntry
Transaction
```

---

# 79. Owned Vehicle

Example logical schema:

```text
owned_vehicle
--------------
id
account_id
vehicle_definition_id
acquired_at
mastery_xp
mastery_level
odometer
paint_config
cosmetic_config
active_loadout_id
```

---

# 80. Part Instance

```text
part_instance
-------------
id
account_id
part_definition_id
rarity
level
mastery_xp
rolled_affixes
bound_state
acquired_at
```

---

# 81. Transaction Ledger

Every important economy mutation should be traceable.

```text
transaction
-----------
id
account_id
type
currency
amount
reason
reference_id
created_at
```

Examples:

```text
RACE_REWARD
VEHICLE_PURCHASE
PART_UPGRADE
SALVAGE
ADMIN_GRANT
SEASON_REWARD
```

This is essential for:

- debugging;
- exploit response;
- customer support.

---

# 82. Matchmaking Flow

```text
Client
→ Backend: queue request
→ Matchmaker groups players
→ Allocator starts/assigns race server
→ Race server registers readiness
→ Backend issues short-lived match token
→ Client receives server address + token
→ Client connects
→ Race server validates token
→ Match starts
```

---

# 83. Match Tokens

Token contains or references:

```text
account_id
match_id
allowed vehicle/loadout
expiry
nonce
signature
```

A player cannot connect to arbitrary race servers pretending to own items.

---

# 84. Race Result Flow

```text
Race server
→ submits authoritative result
→ result service validates match identity
→ progression service calculates rewards
→ inventory/economy transaction committed
→ client receives final reward payload
```

The client never submits:

```text
"I won, give me 5000 credits."
```

---

# 85. Disconnect Handling

If player disconnects:

### Before race

- short reconnect window;
- otherwise remove.

### During race

- vehicle can become ghost/AI;
- allow reconnect for 30–90 seconds depending on mode.

### Ranked

Repeated intentional disconnects:

- loss;
- cooldown;
- escalating penalties.

Do not punish obvious server outages as player misconduct.

---

# 86. Server Regions

Start with only regions justified by player population.

Possible:

```text
North America East
North America West
South America
Europe
Asia-Pacific
```

Matchmaking prefers measured ping, not only selected region.

---

# 87. Anti-Cheat

Server authority solves only part of cheating.

Detect:

- impossible input rate;
- impossible acceleration;
- invalid loadout;
- speed beyond authoritative stats;
- checkpoint teleport;
- packet spam;
- modified cooldowns;
- inventory tampering;
- suspicious repeated leaderboard patterns.

For time trials:

- store ghost;
- build hash;
- track version;
- physics version;
- server verification for top records.

---

# 88. Security

Rules:

- all client data untrusted;
- validate RPC payloads;
- authenticate sessions;
- rate limit backend;
- parameterize DB queries;
- rotate secrets;
- never ship server secrets in client;
- log privileged operations;
- isolate race server permissions.

---

# 89. Version Compatibility

Client handshake contains:

```text
game_version
network_protocol_version
physics_version
content_manifest_version
```

Backend can reject incompatible clients.

Race result also stores these versions.

---

# 90. Content Manifest

Server and client need matching gameplay definitions.

Build a signed/versioned gameplay manifest containing:

- vehicles;
- parts;
- stat curves;
- tracks;
- event rules.

Cosmetic-only assets can be versioned separately where practical.

---

# 91. Track Authoring Tools

Build Godot editor tools for designers.

Needed helpers:

- checkpoint placer;
- race spline editor;
- spawn grid generator;
- recovery point visualizer;
- surface painter;
- hazard timeline preview;
- shortcut validator;
- AI racing line;
- camera obstruction preview.

Track creation must not require engineering for every change.

---

# 92. Automated Track Validation

Tool checks:

- all checkpoints reachable;
- checkpoint indexes valid;
- respawn points exist;
- no spawn overlaps;
- finish path valid;
- race spline continuous;
- hazards have IDs;
- track bounds configured;
- server can load scene headlessly.

---

# 93. AI Racers

Bots are important for:

- onboarding;
- empty queues;
- offline testing;
- training;
- server load tests.

AI layers:

```text
Racing line target
+
Speed plan
+
Local obstacle avoidance
+
Opponent awareness
+
Personality
```

Personality variables:

```text
aggression
risk
shortcut_preference
drift_skill
collision_avoidance
consistency
mistake_rate
```

Bots must use approximately legal player physics.

---

# 94. Bot Difficulty

Difficulty changes:

- racing-line accuracy;
- reaction timing;
- mistake rate;
- risk decisions;
- boost timing.

Avoid hidden 30% speed cheats.

Small rubber-banding may be acceptable in casual single-player but should be obvious in design and disabled in serious modes.

---

# 95. Dynamic Events

Track variants can change without entirely new maps.

Parameters:

```text
weather
hazard schedule
surface state
shortcut state
time of day
moving object state
route gates
```

Example:

**Kitchen — Breakfast**

- dry;
- toast hazard;
- cereal obstacles.

**Kitchen — Cleanup**

- wet surfaces;
- sponge shortcut;
- running water hazard.

---

# 96. Procedural Elements

Avoid fully random competitive tracks at launch.

Use controlled procedural variation:

- obstacle positions from legal sets;
- hazard schedules;
- alternate gates;
- pickups in chaos mode.

Ranked maps should remain learnable.

---

# 97. Live Operations

Backend-configured values should include:

- active playlists;
- event schedule;
- reward multiplier;
- available contracts;
- season settings;
- featured track;
- shop cosmetics.

Do not require client release for every event rotation.

---

# 98. Analytics

Track at minimum:

## Acquisition / Onboarding

- tutorial started;
- tutorial completed;
- first race;
- first online race;
- first upgrade.

## Racing

- race starts;
- race completion;
- DNF;
- track;
- vehicle;
- class;
- placement;
- lap times;
- resets;
- collisions.

## Economy

- credits earned;
- credits spent;
- parts acquired;
- parts salvaged;
- upgrades purchased.

## Retention

- D1;
- D7;
- D30.

## Matchmaking

- queue time;
- ping;
- skill spread;
- bot fill rate;
- disconnects.

---

# 99. Balance Metrics

Monitor per vehicle:

```text
pick rate
win rate
podium rate
average lap time
track-specific performance
MMR-specific performance
part combinations
```

A vehicle can be balanced overall but broken on one surface or track.

---

# 100. Performance Targets

Initial PC targets:

```text
60 FPS minimum on target hardware
120 FPS supported where possible
8-player race baseline
12-player stretch
16-player chaos stretch
```

Dedicated server target:

- stable fixed simulation;
- no rendering;
- predictable CPU cost;
- metrics exported.

Optimization priorities:

1. vehicle physics;
2. environment collision;
3. network serialization;
4. hazard logic;
5. particles;
6. draw calls.

---

# 101. Physics Performance

Use simplified collision geometry.

Do not use detailed render meshes as track collision.

Separate:

```text
visual mesh
collision mesh
race bounds
surface volumes
```

Dynamic props should be limited.

Not every fork, screw, crumb, and paper clip needs full rigid-body simulation.

---

# 102. Determinism

Do not require perfect cross-platform deterministic physics for the first architecture.

Use authoritative server state.

Determinism is useful for:

- repeatable hazards;
- replays;
- testing.

But game correctness should not depend on client and server physics producing bit-identical results.

---

# 103. Replays

Phase 1:

- time-trial ghost.

Phase 2:

- input replay.

Phase 3:

- full match replay for:
  - spectating;
  - tournament review;
  - anti-cheat;
  - content creation.

---

# 104. Testing Strategy

## Unit Tests

- stat calculations;
- reward formulas;
- progression;
- class rating;
- inventory operations.

## Integration Tests

- login;
- queue;
- server allocation;
- match result;
- reward transaction.

## Simulation Tests

Run bots headlessly.

Examples:

```text
1000 races
8 bots each
all tracks
all classes
```

Detect:

- crashes;
- impossible checkpoint state;
- physics explosions;
- server memory leaks.

---

# 105. Network Simulation Testing

Test with:

```text
20 ms
50 ms
100 ms
150 ms
250 ms latency

0%
1%
3%
5%
10% packet loss

jitter
reordering
temporary disconnect
```

Do not wait until beta to test poor networking.

---

# 106. Failure Recovery

The backend must tolerate:

- race server crash;
- client crash;
- duplicate result submission;
- DB retry;
- duplicate purchase click;
- matchmaking timeout.

Economy operations need idempotency keys.

---

# 107. Monetization

Recommended:

**Buy-to-play or free-to-play with cosmetic monetization.**

Safe monetization:

- vehicle skins;
- decals;
- driver cosmetics;
- garage cosmetics;
- emotes;
- season cosmetic track.

Avoid selling:

- stat points;
- exclusive best-in-slot parts;
- direct ranked advantage;
- extra boost charges in ranked.

---

# 108. Battle / Season Pass

If used:

Free track:

- credits;
- crafting material;
- cosmetics.

Premium track:

- cosmetics;
- profile items;
- garage decorations;
- currency rebate.

Gameplay vehicles should remain reasonably earnable without premium purchase.

---

# 109. IP / Originality Requirements

Because the concept takes inspiration from known games:

Do not copy:

- Micro Machines track layouts;
- Micro Machines branding;
- Micro Machines UI;
- Micro Machines named vehicles;
- Road Rash characters;
- Road Rash bikes;
- Road Rash dialogue;
- exact Road Rash shop presentation;
- music;
- logos;
- sound effects.

Use the **design lessons**:

- miniature readable racing;
- distance/elimination competition;
- leagues/time trials;
- money earned through races;
- progressively better vehicles;
- distinct upgrade categories;
- damage/repair tension.

Create original implementation and content.

---

# 110. MVP Definition

The first playable online MVP should be much smaller than the full vision.

## MVP Features

### Racing

- 1 vehicle physics model;
- 3 vehicle chassis;
- 2 tracks;
- 1 environment theme;
- 4–8 players;
- circuit mode;
- Screen King 1v1;
- time trial;
- basic bots.

### Networking

- dedicated authoritative server;
- ENet;
- prediction;
- interpolation;
- reconciliation;
- matchmaking prototype.

### Progression

- account;
- credits;
- 4 core part slots:
  - engine;
  - tires;
  - suspension;
  - chassis;
- vehicle purchase;
- race rewards.

### Backend

- login;
- profile;
- garage;
- inventory;
- matchmaking;
- results.

### UI

- home;
- garage;
- queue;
- race HUD;
- results.

---

# 111. Vertical Slice

The vertical slice should prove the actual game fantasy.

Required:

- polished Kitchen environment;
- 4–6 polished tracks/variants;
- 6 vehicles;
- 8–9 part slots;
- complete garage UX;
- progression from class D → C/B;
- social party;
- public matchmaking;
- one faction;
- one mini-season;
- leaderboard;
- daily time trial;
- cosmetics.

Success question:

> Is racing fun enough that players willingly repeat tracks because driving and progression both feel good?

---

# 112. Alpha

Target:

- 3 environments;
- 15+ race layouts;
- 12+ vehicles;
- several hundred part variants through data combinations;
- crews;
- ranked;
- season framework;
- live event config;
- telemetry;
- reporting;
- moderation tools.

---

# 113. Beta

Focus:

- balance;
- onboarding;
- retention;
- matchmaking;
- server scale;
- economy health;
- anti-cheat;
- content cadence;
- crash rate.

Avoid adding major foundational systems during late beta.

---

# 114. Production Roadmap

## Phase 0 — Handling Prototype

Goal:

**Prove driving is fun.**

Build:

- one car;
- graybox kitchen;
- acceleration;
- steering;
- drift;
- collision;
- camera;
- reset;
- checkpoints.

No MMO.

No inventory.

No cosmetics.

No crafting.

## Phase 1 — Local Race

Build:

- four vehicles;
- bots;
- lap logic;
- Screen King;
- results;
- three tracks.

## Phase 2 — Network Race

Build:

- dedicated server;
- prediction;
- interpolation;
- reconciliation;
- 4 players;
- then 8.

## Phase 3 — Persistent Garage

Build:

- accounts;
- vehicles;
- parts;
- credits;
- rewards;
- database.

## Phase 4 — Matchmaking

Build:

- queue;
- server allocation;
- party;
- reconnect.

## Phase 5 — Progression

Build:

- XP;
- mastery;
- factions;
- crafting;
- vehicle classes.

## Phase 6 — Social MMO Layer

Build:

- crews;
- hub;
- events;
- seasons;
- leaderboards.

## Phase 7 — Scale / Polish

Build:

- anti-cheat;
- moderation;
- telemetry;
- content pipeline;
- live ops;
- additional regions.

---

# 115. Highest-Risk Technical Problems

## Risk 1 — Arcade Physics Feels Bad

This kills the game regardless of progression quality.

Mitigation:

- prototype physics first;
- constant controller playtesting;
- do not build MMO systems until driving works.

## Risk 2 — Online Vehicle Collision Feels Unfair

Mitigation:

- server authority;
- prediction;
- generous side contact;
- network simulation testing;
- reduce collision severity in high-latency conditions if necessary.

## Risk 3 — RPG Progression Becomes Pay-to-Win / Grind-to-Win

Mitigation:

- classes;
- homologation;
- spec modes;
- horizontal part design.

## Risk 4 — Too Much MMO Scope

Mitigation:

- persistent services first;
- physical hub later;
- instanced races;
- modular monolith backend.

## Risk 5 — Part System Has Fake Choices

Mitigation:

Every slot needs clear tradeoffs.

Ask:

> Can two strong players rationally choose different builds for the same track?

If no, redesign.

## Risk 6 — Content Is Too Expensive

Mitigation:

- reusable environment kits;
- route variants;
- hazard variants;
- modular track tools.

---

# 116. Core Balancing Rule

The progression formula should follow:

```text
SKILL > BUILD POWER
```

but:

```text
BUILD CHOICE matters.
```

A skilled player in a mediocre legal build should beat a weak player in an optimized build most of the time.

The build should affect:

- strategy;
- preferred lines;
- risk tolerance;
- surface choices;
- recovery.

Not merely determine the winner.

---

# 117. Example Build Comparison

## Build A — Kitchen Grip

```text
Vehicle: Midge GT
Engine: balanced
Tires: sticky slick
Suspension: stiff
Chassis: lightweight
Differential: grip
Boost: small quick-charge
```

Best:

- tight corners;
- dry tile.

Weak:

- collisions;
- wet sections.

## Build B — Sink Shortcut

```text
Vehicle: Rustbug
Engine: torque
Tires: all-surface
Suspension: soft
Chassis: reinforced
Differential: stable
Boost: long duration
```

Best:

- sponge shortcut;
- wet area;
- bumps.

Weak:

- clean high-speed line.

Both can be viable.

---

# 118. Example Reward Drop

After a race:

```text
2nd Place

+ 185 Credits
+ 120 Account XP
+ 80 Midnight Circuit Reputation
+ 54 Vehicle Mastery
+ 31 Engine Mastery

Drop:
Tuned Gecko Suspension
Class C
+5% landing stability
+3% rough-surface speed

Objective:
Wet Feet 2/3
```

The player sees multiple progress vectors.

---

# 119. Example Screen King Rules

1v1:

```text
Target Score: 5
```

Both racers begin at a reset/start zone.

Server continuously calculates track progress difference.

If:

```text
progress_leader - progress_trailer > threshold
```

for:

```text
confirmation_time = 0.35s
```

leader gains one point.

Then:

- brief slow-motion;
- score UI;
- reposition/reset;
- next round begins.

Threshold can vary by track section to account for camera geometry.

Alternative:

Use designer-authored **duel zones** that define fair separation thresholds.

---

# 120. Example Ranked Homologation

Player owns:

```text
S-class vehicle rating 782
```

Playlist:

```text
A-Class Ranked
Maximum rating 700
```

System scales/caps the build to 700 using deterministic homologation rules.

UI shows:

```text
OPEN POWER: 782
RANKED POWER: 700
```

The player can inspect exactly what was adjusted.

---

# 121. Example Backend API Surface

Illustrative only:

```text
POST /auth/session
GET  /profile
GET  /garage
POST /garage/loadout
GET  /events
POST /matchmaking/queue
DELETE /matchmaking/queue
GET  /matchmaking/status
POST /craft
POST /parts/upgrade
POST /parts/salvage
GET  /leaderboards/{track}
GET  /season
GET  /crew
```

Race servers use privileged internal endpoints.

---

# 122. Example Client Match State Machine

```text
IDLE
↓
QUEUEING
↓
MATCH_FOUND
↓
CONNECTING
↓
AUTHENTICATING
↓
LOADING
↓
READY
↓
COUNTDOWN
↓
RACING
↓
FINISHED
↓
RESULTS
↓
RETURN
```

Every state requires timeout/error handling.

---

# 123. Example Race Server State Machine

```text
BOOTING
↓
REGISTERED
↓
WAITING_FOR_PLAYERS
↓
LOADING
↓
COUNTDOWN
↓
RUNNING
↓
FINISHING
↓
SUBMITTING_RESULTS
↓
SHUTDOWN
```

---

# 124. Definition of Done — Vehicle Handling Prototype

A handling prototype is successful when:

- controller feels responsive;
- keyboard is viable;
- player can understand steering immediately;
- drifting is learnable;
- collisions are fun;
- reset is reliable;
- track elevation works;
- camera rarely hides hazards;
- testers voluntarily replay laps without progression rewards.

That last point matters most.

---

# 125. Definition of Done — Online Prototype

Successful when:

- 8 clients can finish repeated races;
- 100–150 ms ping remains playable;
- moderate packet loss does not destroy movement;
- no client can declare its own finish;
- server validates loadout;
- reconnect works;
- remote cars appear smooth;
- collision correction is acceptable.

---

# 126. Definition of Done — Progression Prototype

Successful when:

- player receives rewards from authoritative race result;
- buys a vehicle;
- obtains a part;
- equips a part;
- server recalculates stats;
- part meaningfully changes handling;
- inventory survives relog;
- duplicate transactions do not duplicate rewards.

---

# 127. Recommended Initial Team Priorities

If this is a small team or solo-heavy project:

1. vehicle feel;
2. camera;
3. track readability;
4. local race rules;
5. networking;
6. authoritative dedicated server;
7. persistence;
8. basic progression;
9. matchmaking;
10. more content;
11. crews/seasons/hub.

Do not reverse this order.

A beautiful MMO garage attached to mediocre racing is a dead project.

---

# 128. Suggested First Engineering Milestone

Create a project called:

```text
pocket-circuit-prototype
```

Build only:

```text
1 graybox Kitchen track
1 vehicle
1 camera
1 lap
1 stopwatch
1 reset system
1 drift system
```

Debug overlay:

```text
speed
velocity
grip
slip angle
surface
current checkpoint
lap
physics FPS
```

Then tune until driving is fun.

---

# 129. Suggested Second Milestone

Add:

```text
4 local vehicles
Screen King mode
basic collision
AI
```

Play locally.

Do **not** add inventory yet.

---

# 130. Suggested Third Milestone

Convert the same race to:

```text
dedicated authoritative server
2 players
4 players
8 players
```

Only after multiplayer movement works should persistent progression become a priority.

---

# 131. Long-Term Expansion Ideas

Not launch requirements.

## Alternative Vehicle Families

Potential:

- micro boats;
- hover vehicles;
- snow vehicles;
- tiny helicopters in special modes.

Do not mix radically different physics into standard competitive playlists until the core car game is mature.

## Player-Created Tracks

High-risk/high-value later feature.

Could support:

- approved modular track editor;
- curated community playlists;
- creator leaderboards.

Requires strong validation and moderation.

## Tournament Mode

Bracket:

```text
16
→ 8
→ 4
→ 2
→ champion
```

## Spectator / Esports

- director camera;
- overlays;
- replay;
- tournament server;
- observer slots.

---

# 132. Product Identity

The strongest identity should be:

> **Tiny racing, huge world, endless garage.**

The game should not be sold as:

> “Micro Machines but online.”

That may explain the prototype internally, but the finished game needs its own identity.

Possible original hooks:

- persistent garage RPG;
- build-dependent environmental shortcuts;
- globally shared miniature world;
- seasonal faction racing;
- Screen King as signature competitive mode.

---

# 133. Final Product Test

Before adding a major system, ask:

### Racing Test

Does it make driving more fun?

### Progression Test

Does it create a meaningful goal?

### Choice Test

Does it create a real decision?

### MMO Test

Does persistence/social play improve the experience?

### Fairness Test

Can a skilled new player still compete?

### Scope Test

Could this be implemented without delaying the core game for months?

If the answer is no, cut or postpone it.

---

# 134. Core Feature Priority Matrix

## Must Have

- arcade driving;
- top-down miniature tracks;
- multiplayer;
- authoritative servers;
- circuit racing;
- Screen King;
- garage;
- vehicles;
- parts;
- tuning;
- progression;
- matchmaking;
- leaderboards.

## Should Have

- factions;
- crews;
- seasons;
- daily time trial;
- crafting;
- multiple surfaces;
- dynamic hazards.

## Could Have

- physical social hub;
- trading;
- tournaments;
- advanced spectator mode;
- community tracks;
- alternate vehicle types.

## Explicitly Not Early

- giant seamless open world;
- hundreds of physical players per race;
- blockchain;
- unrestricted item market;
- realistic vehicle simulation;
- massive narrative campaign.

---

# 135. Final Recommended Scope

The best version of this concept is **not actually a giant MMO racing simulation**.

It is:

```text
Excellent 3-minute arcade races
+
persistent online accounts
+
deep garage progression
+
meaningful vehicle builds
+
social competition
+
seasonal content
```

That is large enough.

The core technology and game design should always protect the thing that makes the concept worth building:

> **You press accelerate, the tiny car moves, the camera follows it across an absurdly oversized environment, three other players slam into you around a coffee cup, you recover, take a risky shortcut across a sponge, steal the lead, win by half a second, receive a new suspension part, install it, feel the difference, and immediately queue again.**

If that loop works, the MMO layer has something worth sustaining.
