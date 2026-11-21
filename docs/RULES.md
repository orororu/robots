# Game rules: table, tags and values

Status: **draft**. Agreed ideas are in "Rules". Undecided points are in "Open questions".

## Rules

### The table

- Each side has a **table with 4 slots**.
- **There is no hidden hand.** The table replaces it completely:
  deck → table → play → discard pile.
- **The table is always full.** As soon as a card leaves the table, a new card is
  drawn from the deck into the free slot. When the deck is empty, the discard
  pile is shuffled to form a new deck.
- There is no draw timer. **Energy is the only limit** on how fast you play.
- The table is **visible to both sides**. You can always see which cards your
  opponent is able to play next.
- You **play cards from your table**. Playing a card costs energy (as today).
- **Every played card resolves once and goes to the discard pile.** Nothing
  stays in play after it resolves.

### Card values

- Every card has a **value**, a number that says how strong it is (e.g. Laser 10).
- **While a card waits on the table, its value can change:** opponent defence
  lowers it, and your own buffs raise it. A value never goes below 0.
- When a card is played, its **current** value is used.
- A card's value **resets to its printed value** when it goes to the discard pile.
- Every card also has an **energy cost**. Costlier cards have higher values.

### Relative costs and values

- Costs and values are written as **multiples of a base amount**: cost `1.2`
  means 1.2 × the base cost, and value `0.7` means 0.7 × the base value.
- The game shows them through a **display scale**. With scale 10, cost `1.2`
  shows as **12**; with scale 1000 it shows as **1200**. Changing the scale only
  changes the numbers players see, never the balance.
- Energy uses the **cost** scale (energy pays for costs), and robot HP uses the
  **value** scale (attack values subtract from HP).
- The Laser example below uses scale 10: Laser `1.0` shows as 10, and Energy
  shield `0.7` as 7.

### Tags

- Every card has **one or more tags** describing what it is,
  e.g. Laser = `[attack, range, beam]`, Energy shield = `[defence, energy]`.
- Tags are **not necessarily visible** to players. Some may be hidden, to be
  decided later.
- Tags only **describe** cards. They don't decide what a card does; its
  **target** does (below). Tags matter because targets select cards by tag.

### Target and scope

Every card has a **target**. It either damages the opponent's HP, or affects
table cards: on the `opponent` side it **lowers** them by the card's current
value, and on the `self` side it **raises** them by it. A table **scope** says
which cards:

  - `one(tags)`: one random table card that has all these tags.
  - `all(tags)`: every table card that has all these tags. Should have a lower value.

| Target | Effect | Example |
|---|---|---|
| `opponent(hp)` | damage the opponent | Laser, Punch |
| `opponent(one(tags))` | lower one opponent card | Parry `one[attack,melee]`, Energy shield `one[attack]` |
| `opponent(all(tags))` | lower all matching opponent cards | Jump `all[attack,melee]` |
| `self(one(tags))` | raise one of your cards | Lock on `one[attack,range]` |
| `self(all(tags))` | raise all your matching cards | Overclock `all[attack]` |

The `attack`, `defence` and `buff` tags are just names for common kinds of
cards. A card tagged `defence` usually targets `opponent(one(...))`, but the
target is what counts.

### Defence is played before the attack

- Defence can't react to an attack that has already been played; by then the
  damage is done.
- Instead, you **watch the opponent's table** and weaken their attack cards
  **before** they play them. This is the core real-time tension: do I spend energy
  now to weaken their Laser, or save it for my own attack?

### No discarding

- There is **no discard action**. You can't throw cards away to dig through
  your deck for a better one.
- To clear a slot you must **play the card**, paying its full energy cost, even
  if its value is 0 and it does nothing. This makes clearing a slot expensive
  on purpose.
- So lowering an enemy card to 0 hurts twice: its attack is gone, and the
  opponent must waste energy to get rid of it.

### Targeting

- Targets are chosen **automatically**. The player never picks one.
- Which cards a defence affects depends on its **type and tags** compared with
  the cards on the opponent's table.
- When a card affects only one card and several match, the target is picked
  **at random**. The seeded RNG in the game state makes the pick reproducible
  for tests and replays.
- A card with **no matching target can still be played**. It simply does nothing
  (e.g. Parry when the opponent has no `melee` cards). Its energy is spent and
  it goes to the discard pile as usual.

Every defence has a value. **Defences that affect several cards have a lower
value** than single-target ones:

| Defence | Targets on the opponent's table | Value (example) |
|---|---|---|
| **Parry** | **One** random `melee` attack card | high, e.g. 8 |
| **Jump** | **All** `melee` attack cards | low, e.g. 3 |
| **Energy shield** | One random attack card | e.g. 7 |

### Example

> The opponent's table shows **Laser** `[attack, range, beam]`, value **10**.
> Before they can play it, I play **Energy shield** `[defence, energy]`, value **7**.
> The Laser on their table drops to **3** (10 − 7), and my Energy shield goes to my
> discard pile, freeing a slot that is immediately refilled from my deck.
> If they play the Laser now, it deals only 3 damage.

### Defaults for now

These are placeholders so the game can be built and played. Each can change
after playtesting:

- **Extra value is wasted.** Energy shield 12 against Laser 10 leaves the Laser
  at 0, and the extra 2 does nothing.
- **Defensive stalls (known, not fixed yet):** two decks that are mostly
  defence wear each other's attacks to 0, and ~10% of build-tournament matches
  hit the 15-minute limit. Revisit once there are more card types and rules.
  Options: AI opponents avoid too-defensive builds (players may still use
  them), or a **defence floor** (`Config.defence_floor`, 0 = off): defence
  can't lower a card below a share of its printed value. A 25% floor cut
  stalls to ~2% and kept the starters at 49%.
- **Defence lowers attack cards only.**
- **Buffs raise one random matching card** on your own table. No maximum value.
- **All tags are visible** for now.
- The old robot **Shield, Repair and Charge effects are removed**. Robot HP stays.
- **No healing during a match.** Robots are repaired only between matches.
  Repair cards made matches stall: they out-healed cheap attacks, and 22% of
  build-tournament matches hit the 15-minute limit (3% without them).
- A deck with fewer than 4 cards leaves table slots empty.

## Balance principles

- **Pace:** about **one move every 4 seconds** per player. Humans can't play
  several moves per second, so energy income, not reaction speed, limits play.
  Rule of thumb: energy rate × 4 s ≈ average card cost.
- **Match length:** about **2 minutes** (~30 moves per player).
- **Bigger cards are more efficient**, in every role. Big cards are riskier:
  they wait longer on the table, attract defence, and cost more to clear once
  zeroed. Without a reward nobody would play them.
- **Defence and buffs beat attacks of the same cost**, by a margin that
  **grows with cost**. Cheap ones get no margin, so fast small defences can't
  stall the round. Big ones always outclass attacks of the same cost, so no
  attack is ever big enough to beat defence, and builds aren't glass cannons.
- Target value per cost (`robots/efficiency.gleam`):
  `1.0 + 0.5 × (cost − 1) + bonus × max(0, cost − 0.5)`, with bonus 0 for
  damage, 0.6 for weaken (defence) and 0.4 for strengthen (buffs). Cards hitting
  `all(...)` are rated as if they hit 2 cards. A test checks every catalog card
  against its goal (±0.1).

  | Cost (shown) | 5 | 6 | 8 | 10 | 16 |
  |---|---|---|---|---|---|
  | Damage | 0.75 | 0.80 | 0.90 | 1.00 | 1.30 |
  | Weaken | 0.75 | 0.86 | 1.08 | 1.30 | 1.96 |
  | Strengthen | 0.75 | 0.84 | 1.02 | 1.20 | 1.74 |

- **Robots should play differently.** Variety of builds, robots assembled from
  components that each add several cards, is the main attraction (to be designed).
- **Measure with the balance report:** `cd core && gleam run -m balance` plays
  AI-vs-AI matches (both seatings) and shows win rates, match length, seconds
  per move, and what each card actually achieves per cost.
- Small numbers matter: changing one robot's HP from 100 to 110 moved its win
  rate from 31% to 62%. Change one thing at a time and rerun the report.

## Open questions

1. **Hidden tags:** which tags are hidden, and can they be revealed (e.g. a
   scanner card)?
2. **Multi-target buffs:** should they exist, with a lower value like Jump?
3. **Minimum deck size:** 4 cards for now. Chassis cards keep decks above it,
   so small decks are no longer an exploit (see docs/BUILDER.md).
4. **Counter cards** against strong builds, e.g. Smoke lowering every `range`
   attack, so expensive chassis like Tank + Cannon can be answered.

## Implementation

These rules are implemented in `core/`:

- `card.gleam`: tags, `Target` (side) and `Scope` (hp / one / all), relative `cost` and `value`.
- `table.gleam`: table slots with current values, and automatic `one`/`all` targeting (`affect`).
- `game.gleam`: playing a card, resolving it, discarding it, and refilling the slot.
- `scale.gleam`: the display scale (default ×10 for costs and values).
- `catalog.gleam`: all components and the starter robots.
- `efficiency.gleam`: card roles and their value-per-cost bands.
- `simulation.gleam` and `core/dev/balance.gleam`: AI-vs-AI matches and the balance report.

`core/test/simulation_test.gleam` fails on stalemates and prints a warning when
match length, pace or win rate drift from the targets.
