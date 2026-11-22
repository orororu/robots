# Runs: the roguelike layer

Status: **design draft.** Implemented so far: wear
(`core/src/robots/construction/wear.gleam`), battles between teams
(`game.teams`), part and chassis prices, loot charts and battle drops
(`core/src/robots/run/`), the enemy roster (`content/enemies.gleam`). Agreed points are under "Agreed";
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
- **After a battle** the player gets **money** and **1 to 3 random parts**
  from the level's loot chart. Bosses also drop a **chassis**.

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
    Smoke, Point defence, Reactor, Heavy plating, Big battery).
  - Level 3: heavy weapons (Cannon, Drone bay) and more heavy armor.
  - Levels past the last chart use the last one.
- **Plating drops often on every level,** since looted armor is the only
  healing between nodes.
- **Modifiers get likelier by level:** Light and Overclocked, each 5% on
  level 1, 10% on level 2, 20% on level 3. A drop can have both.
- **Every part has a price** in credits (`run/price.gleam`), from what it
  does, what its cards cost and its weight:
  - **Cards:** each counts its energy cost, scaled by how efficient it is
    against its role's goal. Cards outside the efficiency band (counters,
    launches, Smoke, Burn) count their cost.
  - **Armor:** 1 per HP left, so worn plates are cheaper.
  - **Batteries:** 0.5 per point of energy cap.
  - **Weight:** each unit below 3 adds 10%, each above takes 10% off.
  - **Modifiers:** Light and Overclocked raise the price.
  - Base prices run from 13 (Point defence) to 57 (Laser).
- **Chassis are expensive** (`price.of_chassis`), about 300-360 credits,
  several parts' worth:
  - **Capacity:** 15 credits per unit of weight it can carry (about what a
    part costs per unit of its weight).
  - **HP:** 10 credits per HP left (less wear).
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
  - A plate whose HP runs out is **destroyed** and removed from the robot.
  - **A destroyed plate's cards (Block) stay in the deck until the battle
    ends,** since damage is only assigned to parts afterwards.
  - Example: three plates of 2 HP and 5 damage. Two plates are destroyed and
    the third is at 50%.
  - Only damage beyond all the armor reaches the **chassis**.
- **Swapping parts can't heal.** A worn plate keeps its wear when removed or
  moved to another robot. A worn chassis keeps its damage in any build.
  Looted parts come in their own condition, possibly worn.
- **No HP is restored between nodes** (for now). The only way to heal on the
  road is **looted armor**: a fresh plate replaces a worn or destroyed one.
  Repair shops repair for money.

Why on the parts and not on the robot: if the robot only remembered its
damage, installing fresh armor would heal it and removing a damaged plate
would leave its damage behind. If it remembered an HP percentage, a brand-new
plate on a battered robot would also count as battered.

## Open questions

1. **Money per battle:** how much for an enemy, a strong enemy and a boss?
   Do strong enemies and bosses drop more parts than 1-3?
2. **Upgrades:** how much better is an upgrade card (e.g. +20% value)? Which
   card gets copied? How many upgrades per part, and at what price?
3. **Selling:** can parts be sold, and for what share of their price?
4. **Enemy loot and wear:** do enemies arrive damaged on later nodes? Does
   their loot come from their own parts?
5. **Prices and strength:** prices come from a formula, not from how parts
   do in the tournament. The Cannon is the strongest weapon but priced like
   a Laser.

## Implementation sketch

In `core/` (pure, like the rest):

- **Wear (done):** `wear` on parts and on the chassis; remaining HP is full HP
  minus wear (`part.remaining_hp`, `builder.chassis_hp`). The builder gives a
  robot max HP as if new, and starting HP from what its parts have left.
  `wear.assign(chassis, parts, damage)` puts a battle's damage on the parts
  (most worn plate first, destroying plates, the rest on the chassis) and
  returns the worn chassis and surviving parts.
- **Run state**: the graph, the current node, the player's robots (chassis,
  parts, wear), unused parts, money, the level.
- **Battles between teams (done):** `game.teams(config, p1:, p2:, ...)` takes
  each side's robots in order; `game.new` is a one-robot team. Each side keeps
  a `reserve`. When its robot is destroyed, the next enters fresh (events
  `Destroyed`, then `Entered`); with no reserve left, the side loses.
