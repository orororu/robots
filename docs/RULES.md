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
- The main tags decide what a card does when played:

| Main tag | When played |
|---|---|
| `attack` | Damages the **opponent's HP** by the card's current value. |
| `defence` | Lowers the **value of cards on the opponent's table** by the defence's value. |
| `buff` | Raises the **value of cards on your own table**. |

Other tags (`range`, `beam`, `energy`, `melee`, …) decide which cards a defence
or buff affects (see "Targeting").

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

- Each defence and buff lists the **tags its targets must have**
  (e.g. Parry: `attack` + `melee`; Energy shield: any `attack`).
- **Extra value is wasted.** Energy shield 12 against Laser 10 leaves the Laser
  at 0, and the extra 2 does nothing.
- **Defence lowers attack cards only.**
- **Buffs raise one random matching card** on your own table. No maximum value.
- **All tags are visible** for now.
- The old robot **Shield, Repair and Charge effects are removed**. Robot HP stays.
- A deck with fewer than 4 cards leaves table slots empty.

## Open questions

1. **Hidden tags:** which tags are hidden, and can they be revealed (e.g. a
   scanner card)?
2. **Multi-target buffs:** should they exist, with a lower value like Jump?
3. **Minimum deck size** when building a robot, so the table can always be filled.

## Effect on the current code

The current `core` has a hidden hand, a draw timer, and plays every card
instantly with a list of effects. Expected changes:

- `card.Card` gets `value: Int` and `tags: List(Tag)`. What it does follows
  from its main tag rather than from a stored list of effects.
- `game.Combatant`: `hand` becomes `table`, with 4 slots visible to both sides.
- **The draw timer goes away:** `next_draw_at`, `draw_interval_ms` and the
  draws in `Tick` are removed. Playing a card refills its slot immediately.
- `PlayCard(side, slot, at)` stays target-free: targeting is automatic, a pure
  function `(card, opponent table, seed) -> #(opponent table, seed)`, easy to
  unit-test. The random pick uses the game's existing seeded RNG.
- No discard message is needed.
- The AI gets more interesting: it can see the player's table and decide
  whether to defend or attack.
