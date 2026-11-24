# Robot builder

Status: **core implemented** (`core/src/robots/construction/part.gleam`, `construction/builder.gleam`,
chassis and parts in `content/components.gleam`, their cards in `content/cards.gleam`). No garage screen yet. Numbers for the
new parts (Cannon, Machine gun, Tank, Scout) are placeholders, not yet balanced.

## Agreed

- **Robots are built before a match.** Nothing is installed during a match.
- A robot is a **chassis** plus **components**.
- **Each component has a weight.** The chassis decides how much weight the robot
  can carry.
- **Each component can add several cards** to the deck (as today).
- **Components can also change robot stats:**
  - **Armor** adds HP.
  - A **battery** sets the maximum energy you can store (the energy cap).
  - **Weapons** (Laser, Chainsaw, …) and **defences** (Shield, Jump engine, …)
    mainly add cards.
- **Chassis have their own HP**, which armor adds to.
- **Slots are mostly generic,** with some restrictions. In particular, the
  chassis limits **how many weapons, and how heavy each one can be.** That
  allows a **tank with one big cannon** and a **small robot with four machine guns**.
- **Duplicates are allowed** (e.g. two Laser arms).
- **A battery is required.** A build without one is invalid.
- **No charge-rate upgrades (for now).** A higher charge rate is a pure win with
  no downside, so every build would take it and it adds no variety. It would
  also break pacing: the 4 s move target and the card efficiency bands assume
  equal energy income. The energy rate stays global.
- **Battery capacity is a real trade-off:** a card costing more than your cap can
  never be played, so builds with big cards need big, heavy batteries, which
  leaves less weight for armor.
- **The builder warns about dead cards**, e.g. Lock on (raises `[attack, range]`)
  on a robot with no ranged attacks.
- The game is **RPG-like**: you collect money and loot, and **finding the best
  parts is part of the fun**. Chassis and components are bought or found
  (shop, loot and money are designed later).

## Proposed model

```gleam
pub type Chassis {
  Chassis(
    name: String,
    hp: Float,               // base HP; armor adds to it
    capacity: Float,         // total weight it can carry
    weapon_mounts: List(Float),  // one entry per weapon, its max weight
  )
}

pub type Kind {
  Weapon
  Defence
  Armor
  Battery
  Utility                    // buffs, targeting, …
}

pub type Component {
  Component(
    name: String,
    kind: Kind,
    weight: Float,
    cards: List(Card),
    hp: Float,               // armor: extra HP (0 for most parts)
    energy_cap: Float,       // battery: storage (0 for most parts)
    modifiers: List(Modifier),  // loot quality, see "Loot modifiers"
  )
}
```

Building is a pure function that either returns a robot or explains what's wrong:

```gleam
pub fn build(chassis: Chassis, parts: List(Component)) -> Result(Robot, List(BuildError))

pub type BuildError {
  Overweight(total: Float, capacity: Float)
  TooManyWeapons(count: Int, mounts: Int)
  WeaponTooHeavy(weapon: String, weight: Float, mount_limit: Float)
  NoWeapon
  NoBattery
}

pub type Warning {
  DeadCard(card: String, reason: String)   // e.g. no matching targets in own deck
  Unaffordable(card: String, cost: Float, cap: Float)  // costs more than the battery holds
}
```

### Example chassis

| Chassis | HP | Capacity | Weapon mounts | Fits |
|---|---|---|---|---|
| Tank | high | high | **1 × heavy** (e.g. ≤ 8) | one big cannon, lots of armor |
| Scout | low | low | **4 × light** (e.g. ≤ 2 each) | four machine guns, a jump engine |
| Frame | medium | medium | 2 × medium | the all-rounder starter |

This fits the efficiency rules: a big cannon's cards are expensive, so they get
the biggest value per energy, while machine guns give many cheap cards.

## Weight

- **Weight is an attribute of the part type**, not a penalty for strength:
  a cannon is heavy, a laser is light. Energy cost is already balanced by the
  card efficiency bands, so heavier parts are not punished twice.
- Weight reflects **how much a part brings**: its total card value, plus HP
  (armor) or energy capacity (battery).
- **Money and quality decide how good a part is for its weight.** A pricier
  "Light Laser Mk2" with the same cards and less weight frees room for armor.
  Finding such parts is part of the loot fun.
- **Armor sets the exchange rate.** Spare weight goes into armor, so armor's HP
  per weight is the price of weight: a part weighing 4 should be worth about
  what 4 weight of armor gives. The build tournament checks this.

## Loot modifiers

Better parts are a **base part plus modifiers**, so each card exists once and
loot changes it by rules:

```gleam
pub type Modifier {
  Light(weight: Float)        // e.g. 0.75 = 25% lighter, same cards
  Overclocked(value: Float)   // e.g. 1.15 = card values +15%, same costs
}
```

- **Light** parts have the same cards and weigh less, freeing weight for armor or
  a bigger battery.
- **Overclocked** parts weigh the same and have stronger cards.
- Modifiers are applied when the robot is built. The card efficiency bands apply
  to **base** parts; modifiers are allowed to beat them, since that's the point
  of loot, but only within set limits.
- Better modifiers mean a higher price (shop and loot are designed later).

## Defaults in use

Chosen to get started; each can change:

- No limits besides weight, capacity and weapon mounts.
- Batteries add no cards. Everything else does (see below).
- **At least one weapon** is required (`NoWeapon`). Chassis attacks (Kick,
  Ram) alone made weaponless builds that caused 75% of tournament stalls.
- **Decks of 16-20 cards.** Every part has 4-5 cards: variants of its base
  card, cheaper and weaker or pricier and stronger, priced by the efficiency
  bands (Laser: Pulse 8/7, Laser 10/10 ×2, Focused beam 13/15, Overcharge
  16/21). A robot needs **at least 16 cards**, chassis, parts and armor
  together, so no one can just repeat their best combo. Without the minimum,
  thin builds still won (Tank + Cannon + armor, 9 cards); with it, winners
  mix weapons with defences and buffs, and stalemates fell from ~10% to ~6%.
  Stronger armor was tried instead and made it worse (thin armored builds
  stayed on top, stalls rose).
- **A smaller deck is legal, but it malfunctions.** The builder fills a deck
  below 16 cards with **Malfunction** cards (`builder.malfunction`): cost 10
  (about an average shot), 2 damage to your own robot, nothing else. They
  take table slots and are only played to clear them. The AI clears them
  as soon as it can while saving up, and never plays one that would destroy
  its own robot. The garage shows "13 cards + 3 Malfunctions".
- No maximum deck size: weight is the limit.

### Every robot's deck is diluted (why carry a second weapon?)

The energy rate is global, so energy alone can't make two weapons fire
faster. Instead, deck composition sets your attack rate: with no discard and
a table that's always full, every card is eventually played or blocks a slot,
so over a match your energy is spent roughly in proportion to your deck.

- **Chassis cards:** each chassis brings fixed cards, its mobility and
  identity. Frame: Sidestep, Kick. Brute: Ram ×2. Tank: Brace. Scout: Jump ×2,
  Dodge ×2 (the best mobility, to make up for low HP). Jump moved here from
  the Servo legs part, which is gone.
- **Armor adds a Block card** per 2 weight: a weak defence, deliberately
  below its efficiency band. Stacking armor fills the deck with weak cards.
- So a one-weapon robot plays mostly non-attack cards, and each extra weapon
  raises its attack share. The tournament confirms it: on Frame, 2-weapon
  builds average 73% vs 51% for 1 weapon; on Brute 59% vs 46%.
- Defence parts compete with armor for weight, so they must beat it per
  weight. The tournament's "armor share" line checks this.
- Starters use **different chassis**: Tinker on Frame, Scrapper on Brute.
- Several modifiers per part. Light = −25% weight, Overclocked = +15% to card
  values, armor HP and battery capacity.
- Weights for now: weapons 1–6 (Fist 1, Laser and Saw arm 3, Cannon 6),
  defences and utilities 1–2, Cell 1 (cap 30), Battery 2 (50), Big battery 4
  (90), Plating 2 (+12.5 HP, 1 Block), Heavy plating 4 (+25 HP, 2 Blocks).
  Chassis HP / capacity: Frame 45/12, Brute 35/12, Tank 45/16, Scout 40/12,
  Mosquito 25/7 (one weapon mount of 2; six dodges: Hover against melee,
  Barrel roll ×2 and Zigzag against range, Dodge ×2 against anything. A
  level monster: weak on purpose, lasers get through).
  (All HP was halved to make battles about 2.5 times shorter.)
  Shown at display scale ×10.
- **Batteries with cards:** some batteries also bring buffs, a little
  heavier than plain ones. Capacitor 1.5 (cap 50) and Big capacitor 3 (90)
  raise energy attacks (Laser, Drone); Servo pack 1.5 (50) and Big servo
  pack 3 (90) raise melee attacks. The build tournament tries them as card
  parts; a build gets a plain battery only if its own can't pay for its
  priciest card.
- **Railgun** (weight 4, fits a Frame's mount): two Pulses and two Rail
  shots, energy attacks that charge on the table, 12 when drawn and growing
  to 30 over 15 s (cost 20, a Cannon shot at full charge). Lowered by a
  Deflector, a Rail shot keeps growing from there. Rated by its full value.
- **Arc welder** (weight 2): Spark, Arc ×2, Weld, tagged melee **and**
  energy, so Servo packs, Hydraulics and Capacitors all raise it, and
  Bucklers and Deflectors both lower it.
- **Needle gun** (weight 1.5, the lightest gun): Needle ×3 (cost 4, hits 3)
  and Volley. Cheap gun cards give Targeting and Ballistic computers more
  targets; a Salvo raises several at once.
- **Ballistic computer:** raises guns only (machine gun, cannon); its
  Salvo raises every gun on the table. The Targeting computer is broader
  (any range attack, missiles too).
- **Defensive buffs:** the Shield booster raises your own defence cards,
  the Gyroscope your movement defences (Sidestep, Dodge, Jump, Smoke).
  The Reactor (raised all attacks) was removed: batteries do that job now.
- **Movement belongs to the chassis:** dodges, jumps and sidesteps are
  chassis cards; a chassis may bring more than 4 cards.
- Chassis may be unequal: better chassis will cost more, and counter cards
  (e.g. Smoke against `range`) can keep strong builds in check. Tank + Cannon
  currently tops the tournament; Scout is weakest (it lacks good light
  weapons).

## Open questions

1. **Limits on other parts:** besides weapon mounts, should anything else be
   limited, e.g. only one jump engine, or one battery?
2. **Parts without cards:** can armor and batteries add zero cards, or should
   every part add at least one (e.g. armor adds "Brace")?
3. **Deck size:** the minimum is 4 (the table size). Is there a maximum? With no
   maximum, a small deck of only the best cards is strong; weight is the
   natural limit.
4. **Starter robots:** Tinker and Scrapper become chassis + parts. Should they
   use the same chassis (differing only in parts) or different chassis?

5. **Modifier details:** can one part have several modifiers (a "Light
   Overclocked Laser")? How big are they (e.g. Light −25% weight, Overclocked
   +15% card values)? Are there more kinds, e.g. "Efficient" (cards cost less
   energy)?

## Tools

- **Garage view** (text mode first): chassis, installed parts, weight used vs
  capacity, mounts used, HP and energy cap, and deck summary: card count,
  average cost (= pace), role mix, dead-card warnings.
- **Build tournament:** every valid build against every other in the
  simulation, to find dominant builds and parts nobody would take.
