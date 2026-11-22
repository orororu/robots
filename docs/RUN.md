# Runs: the roguelike layer

Status: **design draft.** Only wear is implemented
(`core/src/robots/construction/wear.gleam`). Agreed points are under "Agreed";
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
- **After a battle** the player gets **money** and **random components** (loot).

### Robots

- The player **starts a run with one robot**.
- During a run they can **pick up new chassis** and build more robots from
  looted components.
- **Before a battle** the player gets **some information about the enemy**
  and decides the **order** in which their robots go into the battle.
- **When a robot is destroyed, the next one goes into the battle.** When none
  are left, **the run is over**.

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
- **HP is only partially restored between nodes.** Full repair costs money at
  a repair shop.

Why on the parts and not on the robot: if the robot only remembered its
damage, installing fresh armor would heal it and removing a damaged plate
would leave its damage behind. If it remembered an HP percentage, a brand-new
plate on a battered robot would also count as battered.

## Open questions

1. **Destroyed robots:** does a destroyed robot come back after the battle (as
   a wreck: chassis at 0, armor gone) that can be repaired at a shop, or is it
   lost for the run? Do its weapons and other parts survive?
2. **Robot change in battle:** when the next robot comes in, does the enemy
   keep its HP, energy and table? Does the new robot start with a fresh table
   and starting energy?
3. **Partial restore between nodes:** how much? A fixed amount, a share of
   max HP, armor only (chassis only at shops)?
4. **When can parts be swapped:** anywhere between nodes, or only at certain
   nodes (a workshop)?
5. **Enemy information before a battle:** chassis only, full build, or
   partial (e.g. weapons visible, defences hidden)? Could a scanner part
   reveal more?
6. **Money and loot:** what money buys (repairs, parts, chassis), loot
   quality by level, and how modifiers (Light, Overclocked) and wear show up
   on loot.

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
- **Battle with several robots**: the player's robots in the chosen order; on
  destruction, the next robot enters.
