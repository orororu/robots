# Runs: the roguelike layer

Status: **design draft.** Implemented so far: wear
(`core/src/robots/construction/wear.gleam`), battles between teams
(`game.teams`), part and chassis prices, loot charts and battle drops
(`core/src/robots/run/`), card attributes
(`construction/attribute.gleam`), the enemy roster (`content/enemies.gleam`),
map generation (`run/map.gleam`) and run state (`run/state.gleam`). Not
yet: any UI for runs, buying, upgrades. Agreed points are under "Agreed";
undecided ones under "Open questions".

## Agreed

### The run

- A **run** is a journey through a **graph of nodes**. The player picks a path;
  each node is an **event**.
- Event types to start with:
  - **Enemy**: a battle.
  - **Strong enemy**: a harder battle with better rewards.
  - **Repair shop**: pay to repair.
  - More event types later.
- **Every graph ends with a boss battle.**
- **Battles are the duels we have now**: the real-time card game.
- **After a battle** the player gets **money** and **a few good parts**
  from the level's loot chart: 1 from an enemy, 2 from a strong enemy or a
  boss. Bosses also drop a **chassis**.

### Robots

- The player **starts a run with one robot**.
- During a run they can **pick up new chassis** and build more robots from
  looted components.
- **Before a battle** the player sees **the enemy's description** and decides
  the **order** in which their robots go into the battle.
  - Descriptions are **consistent**: an enemy type always has the same name
    and build, e.g. a "Rusty brawler" is always the same fist-and-parry
    scout. Players learn what each name means and pick robots to counter it.
- **Parts can be replaced after every battle,** once the loot is in.
- **When a robot is destroyed, the next one goes into the battle.** When none
  are left, **the run is over**.
  - **The other side keeps everything:** its HP, energy and table.
  - **The incoming robot starts fresh:** a new deck, table and starting
    energy.
- **A destroyed robot is lost for the run,** with all its parts.

### Loot and prices

- **Each level has a loot chart:** the parts that can drop there and how
  likely each is (`run/loot.gleam`). Later levels drop stronger parts:
  - Level 1: small, simple parts (Fist, Saw arm, Machine gun, light
    defences, small batteries, Plating).
  - Level 2: specialists (Laser more often, Flamethrower, Missile rack,
    Smoke, Point defence, Heavy plating, Big battery, the new batteries
    with buffs and the defensive buffs).
  - Level 3: heavy weapons (Cannon, Drone bay) and more heavy armor.
  - Levels past the last chart use the last one.
- **Plating drops often on every level,** since looted armor is the only
  healing between nodes.
- **Loot is worth picking up:** never worse than a new part, so it's
  interesting at the level it drops on.
- **Modifiers get likelier by level:** Light and Overclocked, each 10% on
  level 1, 20% on level 2, 30% on level 3. A drop can have both. They apply
  to the whole part (its weight, all its values).
- **Card attributes:** each card of a drop can carry **one attribute**
  (`construction/attribute.gleam`). On loot, only neutral trade-offs and
  gains: the chance per card rises by level (30%, 40%, 50%), and so does
  the share of the best ones. Bad attributes come only on worn-down enemies
  and broken plates.
  - The card's name gets the attribute: "Rapid Burst".
  - **The part's name shows its two most impactful attributes,** after any
    Light/Overclocked modifier: "Broken rapid machine gun".
  - **Impact** is how much the attribute changes the card's worth (the same
    measure prices use), so a Broken big card outranks a Worn small one.
  - Value attributes skip cards whose value does nothing (drone launches,
    Ignite, Fire); cost attributes apply to any card with a cost.

Card attributes. Shown on a Laser card (cost 10, value 10); "worth" is the
change in what the card is worth, which also changes the part's price. The
last column is the attribute's loot weight on levels 1/2/3 (– means it
never drops as loot).

| Attribute | Effect | Laser card cost/value | Worth | Weights 1/2/3 |
|---|---|---|---|---|
| Broken | value −80% | 10 / 2 | −80% | –/–/– |
| Damaged | value −40% | 10 / 6 | −40% | –/–/– |
| Wasteful | cost +50% | 15 / 10 | −20% | –/–/– |
| Crude | value −20%, cost +10% | 11 / 8 | −24% | –/–/– |
| Weak | value −20% | 10 / 8 | −20% | –/–/– |
| Sluggish | cost +20% | 12 / 10 | −9% | 3/2/– |
| Worn | value −10% | 10 / 9 | −10% | 4/2/– |
| Quick | cost −20%, value rescaled to stay on the band | 8 / 7 | −20% | 6/5/4 |
| Precise | cost +20%, value rescaled to stay on the band | 12 / 13 | +20% | 6/6/6 |
| Tuned | value +10% | 10 / 11 | +10% | 10/8/5 |
| Efficient | cost −10% | 9 / 10 | +5% | 8/7/5 |
| Strong | value +20% | 10 / 12 | +20% | 5/8/9 |
| Rapid | cost −20% | 8 / 10 | +11% | 3/6/8 |
| Overcharged | value +50%, cost +25% | 13 / 15 | +33% | 1/3/5 |
| Masterwork | value +40% | 10 / 14 | +40% | –/1/3 |

**Words depend on the part.** "Precise" fits a gun, not a plate. On armor,
attributes speak of condition and toughness: Damaged is **Dented**, Weak
**Thin**, Worn **Scratched**, Tuned **Hardened**, Strong **Thick** (Broken,
Crude and Masterwork keep their names); the others never go on armor. An
Overclocked plate is **Reinforced**, an Overclocked battery
**High-capacity**. More armor materials may come later.

**Light and Overclocked stay part-wide modifiers,** separate from card
attributes: a Light or Overclocked part is effectively a different weapon
(lighter, or stronger across the board), while card attributes set its tier
(Broken, Worn... up to Masterwork). More weapons will come later, built
from new combinations of cards; attributes give each of them tiers.

Quick and Precise are trade-offs rather than pure gains or losses: bigger
cards are more efficient per energy but wait longer to be affordable.
`gleam run -m loot` prints this table, the loot charts, and sample drops and
enemies for each level.
- **Every part has a price** in credits (`run/price.gleam`), from what it
  does, what its cards cost and its weight:
  - **Cards:** each counts its energy cost, scaled by how efficient it is
    against its role's goal. Cards outside the efficiency band (counters,
    launches, Smoke, Burn) count their cost.
  - **Armor:** 2 per HP left, so worn plates are cheaper (doubled when all
    HP was halved, so prices stayed the same).
  - **Batteries:** 0.5 per point of energy cap.
  - **Weight:** each unit below 3 adds 10%, each above takes 10% off.
  - **Modifiers:** Light and Overclocked raise the price.
  - Base prices run from 13 (Point defence) to 57 (Laser).
- **Chassis are expensive** (`price.of_chassis`), about 300-360 credits,
  several parts' worth:
  - **Capacity:** 15 credits per unit of weight it can carry (about what a
    part costs per unit of its weight).
  - **HP:** 20 credits per HP left (less wear).
  - **Rare cards:** chassis cards (Sidestep, Jump, Ram...) come from no part,
    so they count 3 times a part's card of the same worth.
- `gleam run -m loot` prints chassis prices and each chart with chances and
  prices.

### Enemies

- **Enemy builds climb the build tournament's ranking**, level by level:
  - Level 1: builds scoring about 20-30% there (the starters score about 60%).
  - Level 2: about 40-50%.
  - Level 3: about 60%.
  - Each level's **strong enemies** are a step above its normal ones (level
    1's strong enemies are level 2's normal ones), and the **boss** another
    step: Foreman (~50%), Warhead (~70%), Siege tank (the top Cannon tank).
- **Early enemies are worn down** (`enemies.conditions`), so a fight costs
  little HP; HP doesn't come back between nodes. When an enemy is met
  (`spawn`), every card gets an attribute for its **condition step**: the
  level minus 1, plus 1 for a strong enemy and 2 for a boss.

  | Step | Card attributes (weights) | Who |
  |---|---|---|
  | 0 | Broken 8, Damaged 2 | level 1 enemies |
  | 1 | Broken 6, Damaged 3, Weak 1 | level 1 strong, level 2 enemies |
  | 2 | Damaged 5, Weak 3, Broken 2 | level 1 boss, level 2 strong, level 3 enemies |
  | 3 | Damaged 2, Weak 4, Worn 4 | level 2 boss, level 3 strong |
  | 4+ | the level's loot chart (30-40% per card, any attribute) | level 3 boss |

  HP the Tinker loses per level 1 fight: 7-22% against enemies, about 35%
  against strong ones, 33% against the boss (it was 25-72% for enemies with
  loot rolls; both measured before all HP was halved).
- **All HP is halved** (chassis and armor, for everyone: enemies are built
  from the same parts as the player). Battles are about 2.5 times shorter
  (Tinker vs Scrapper: 48 s instead of about 2 minutes), but each fight
  takes a bigger share of a robot's HP: card values stayed. Easier fights
  will come from weaker enemy robots, not from enemy-only numbers.
- **Enemy names come from their parts.** When an enemy is met (`spawn`), its
  parts get card attributes by its condition (above). Its name is its two
  most impactful attributes plus the crew name of its main weapon (the most
  valuable one): "Broken machine gunner", "Strong rapid rocketeer".
  - Crew names: Laser → lancer, Saw arm → grinder, Fist → brawler, Cannon →
    cannoneer, Machine gun → machine gunner, Missile rack → rocketeer, Drone
    bay → drone master, Flamethrower → firebug.
  - The roster's own names (Rusty brawler...) only appear in reports; the
    description still tells the player the build style.
- `gleam run -m enemies` plays the starters against every enemy. Matchups
  stay rock-paper-scissors: Scrapper crushes Twin beam but loses to Warhead,
  Tinker the other way round.

| Level | Enemies | Strong | Boss |
|---|---|---|---|
| 1 | Rusty brawler, Scrap gunner, Rust bucket, Grinder | Rocket turtle, Firebug | Foreman |
| 2 | Rocket turtle, Firebug, Beam knight, Smoke ripper | Iron grinder, Twin beam | Warhead |
| 3 | Iron grinder, Twin beam, Gunship, Flare | Bulwark, Hornet | Siege tank |

### Shop and upgrades

- **Money buys parts and upgrades.**
- **An upgrade adds a higher-efficiency card to a part** (proposal, not yet
  built): e.g. a "Tuned laser" card, a copy of one of the part's cards with
  more value for the same cost, above the efficiency band. The part keeps its
  weight, so upgrades are the way to grow stronger within a chassis' capacity.
- **Good chassis are special:** a boss drops one (level 1: Brute or Scout,
  level 2: Scout or Tank, level 3: Tank), and shops sell them, expensively.

### Levels and prizes

- **Beating the boss** gives bigger prizes, e.g. **blueprints**: start future
  runs with different components and chassis, or with more than one robot.
- Then the player moves to the **next level**: a new graph with the same
  rules, **harder enemies and bigger prizes**.

### HP between nodes: damage stays on the parts

Only the **chassis** and **armor** give HP. Weapons, defences, utilities and
batteries have none, so swapping them never touches HP.

- **Each armor plate and each chassis keeps its own damage** (wear) for the
  whole run. A part's remaining HP is its full HP minus its wear.
- **In battle nothing changes:** the robot has one HP pool, starting at the
  sum of its parts' remaining HP.
- **After the battle, the damage is assigned to the parts, armor first:**
  - Plates absorb damage one at a time, **the most worn plate first** (the
    largest share of its HP gone). This leaves fewer half-broken plates.
  - A plate whose HP runs out **breaks but stays installed**: no HP left,
    and **every card on it gets the Broken attribute** (value −80%), e.g.
    "Broken plating" with a "Broken Block". It keeps its weight, so it's
    dead weight until replaced, and the deck keeps its size (a robot never
    drops below the minimum deck from losing armor). Broken plates take no
    more damage: it goes to the next plate, then the chassis.
  - Block cards keep their full value until the battle ends, since damage
    is only assigned to parts afterwards.
  - Example: three plates of 2 HP and 5 damage. Two plates break and the
    third is at 50%.
  - Only damage beyond all the armor reaches the **chassis**.
- **Swapping parts can't heal.** A worn plate keeps its wear when removed or
  moved to another robot. A worn chassis keeps its damage in any build.
  Looted parts come in their own condition, possibly worn.
- **No HP is restored between nodes** (for now). The only way to heal on the
  road is **looted armor**: a fresh plate replaces a worn or broken one.
  Repair shops repair for money.

Why on the parts and not on the robot: if the robot only remembered its
damage, installing fresh armor would heal it and removing a damaged plate
would leave its damage behind. If it remembered an HP percentage, a brand-new
plate on a battered robot would also count as battered.

### The map (`run/map.gleam`)

- **Terms:** a **level** is one whole map; a run goes level 1, 2, 3... A
  node's **row** is how deep it is in its level's map: row 0 is the start,
  row 6 the boss.
- Each level's map is **6 rows of 2-4 nodes, then the boss** alone in a
  last row. The player starts at any node of row 0 and moves one row at a
  time along links. **Links never cross;** every node has a way in and a
  way on, so every path ends at the boss.
- **Row 0** is ordinary enemies. Other rows are enemies and **strong
  enemies** (25%, not before row 2).
- **Repair shops** stand only on the level's **shop rows** (`shop_rows`):
  level 1 rows 2 and 5, levels 2 and 3 rows 3 and 5. On a shop row, one or
  more nodes are shops but never all of them, so some branches pass by
  with a battle. Shop rows are never next to each other, so two shops
  never follow one another. Row 5 often offers the choice: repair before
  the boss, or one more fight.
- Enemies are spawned when the map is made, so the map can show who waits
  where (name and description).
- The client draws the map: E enemy, S strong enemy, R repair shop, B boss;
  your path in green, where you can go in yellow, nodes out of reach
  faded.

### Run state (`run/state.gleam`)

- A run holds the level, its map, the current node, the player's robots
  (each a chassis and its parts, with their wear), spare parts and chassis,
  and money.
- **Battle order names every robot.** A robot sits out only by being taken
  apart in the garage.
- **After a battle,** each robot's damage goes on its parts (`wear.assign`),
  destroyed robots are removed with their parts, and a win pays money, 1-3
  parts, and a chassis for a boss. **Beating the boss** generates the next
  level's map. A loss ends the run.
- **Money per win (placeholders):** 20 for an enemy, 40 for a strong enemy,
  100 for a boss. Runs start with no money.
- **Drops per win:** 1 part for an enemy, 2 for a strong enemy or a boss.
- **Repair shops** restore a robot fully (chassis and plates, including
  broken ones) at 20 credits per HP, what HP is worth on a new plate. A
  broken plate comes back with plain cards (any attribute it had before
  breaking is gone).
- **The garage** (install, uninstall, swap, assemble a new robot from a
  spare chassis) works at any time except after the run is over; every
  change must leave a legal build.

### Autopilot (`gleam run -m run`)

Plays whole runs with the starter alone: random paths, AI battles, repairs
when affordable, broken plates swapped for looted ones; no buying, no new
robots. With worn-down early enemies and all HP halved (40 runs): **33%
reach level 2**, none get further; 5.7 battles per run. Weaker enemy
robots are to come. Level 2 enemies (Firebug, Beam
knight, Rocket turtle) end most runs: the starter alone isn't meant to get
far, and players will have second robots and bought parts. (Before enemies
were worn down: 5% reached level 2.)

## Open questions

1. **Money per battle:** placeholders are 20/40/100 (see Run state).
2. **Upgrades:** how much better is an upgrade card (e.g. +20% value)? Which
   card gets copied? How many upgrades per part, and at what price?
3. **Selling:** can parts be sold, and for what share of their price?
4. **Enemy loot and wear:** do enemies arrive damaged on later nodes? Does
   their loot come from their own parts (with the attributes in their name)?
5. **More enemy robots:** the roster comes from duel builds (the
   tournament). Runs need more, and more varied, robots with distinct
   strategies, made for the roguelike rather than for duels.
6. **Prices and strength:** prices come from a formula, not from how parts
   do in the tournament. The Cannon is the strongest weapon but priced like
   a Laser.

## Implementation sketch

In `core/` (pure, like the rest):

- **Wear (done):** `wear` on parts and on the chassis; remaining HP is full HP
  minus wear (`part.remaining_hp`, `builder.chassis_hp`). The builder gives a
  robot max HP as if new, and starting HP from what its parts have left.
  `wear.assign(chassis, parts, damage)` puts a battle's damage on the parts
  (most worn plate first, breaking plates, the rest on the chassis) and
  returns the worn chassis and parts. `wear.break` makes a broken plate.
- **Map and run state (done):** `map.generate(level, seed)`; `state.new`,
  `choices`/`go`, `battle`, `team`, `outcome`/`finish`, `repair`/`leave`,
  `install`/`uninstall`/`swap`/`assemble`. `simulation.teams` plays a team
  battle between AIs.
- **Battles between teams (done):** `game.teams(config, p1:, p2:, ...)` takes
  each side's robots in order; `game.new` is a one-robot team. Each side keeps
  a `reserve`. When its robot is destroyed, the next enters fresh (events
  `Destroyed`, then `Entered`); with no reserve left, the side loses.
