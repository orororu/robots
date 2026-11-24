# Levels: themes, robots and bosses

Status: **ideas**, except the Dump (level 1), which is built
(`core/src/robots/content/enemies.gleam`). Each level of a run has a theme:
its robots look and fight alike, and its boss has a weapon of its own. Themes
follow the loot charts (`run/loot.gleam`), which already drop simple parts on
level 1, specialists on level 2 and heavy weapons on level 3, so what a level
drops fits what fights there.

Levels are 12 rows long, then the boss (`run/map.gleam`). The first maps had
6 rows, short enough for a **tutorial level** later.

## 1. Dump (built)

Junk and broken robots: rusty melee and rattling guns. Level 1 enemies
arrive worn down (mostly Broken cards, see RUN.md "Enemies"), which suits a
dump: everything here is falling apart.

| Robot | Build | |
|---|---|---|
| Rusty brawler, Scrap gunner, Rust bucket, Grinder | as before | already scrap-themed |
| Junk fly, Bottle fly | Mosquitoes (level monsters) | were Gnat and Horsefly |
| **strong** Hubcap knight | two boosted bucklers, saw and fist | was Shieldwall |
| **strong** Incinerator | flamethrower, fist, buckler, deflector | new: burns parried cards |
| **strong** Foreman | saw arm, kinetic shield, deflector | was the boss |
| **BOSS Compactor** | Tank: Crusher plate, kinetic shield, deflector | new |

**The Compactor's Crusher plate** (weight 5, boss only: it never drops):
2 **Compress** and 2 **Shove**.

- **Compress** `[attack, melee, kinetic]`, cost 20, grows while it waits
  on the table from 5 to 50 over about 40 s (the drones' `Grows` trait). It
  is an ordinary melee attack, so Bucklers, Kinetic shields, Brace and Jump
  all lower it, but **it keeps growing back**: the fight is a timer you
  keep resetting with defence energy. Left alone, one blow takes most of a
  starter's HP.
- The AI waits for it to grow fully (as with drones), so the threat is
  visible on the table the whole time.
- Measured (`gleam run -m enemies`): at full strength the Tinker beats it
  13% of the time and the Scrapper 10%; as met in a run (worn down) the
  Tinker wins 88% and loses about half its HP (the Foreman cost 41%).

Engine changes it needed: a card drawn from the deck now starts growing
when it's drawn (before, only launched drones grew, and a drawn growing card
would have counted from the start of the match). Attributes scale a growing
card's growth with its value (a Broken Compress grows to 10, not 50). The AI
never throws a growing card away as clutter.

## 2. Toxic waste (idea)

Fire, smoke and corrosion. Loot: flamethrowers, smoke launchers, missiles.

- **Sludge crawler:** flamethrower and buckler.
- **Fume belcher:** fights under smoke with a saw (Smoke ripper, renamed).
- **Barrel lobber:** missiles as toxic barrels (Rocket turtle, renamed).
- **Mutant mosquito:** a level monster (Wasp, renamed).
- **BOSS Acid hydra**, with an **Acid sprayer**: its sprays corrode your
  *defence* cards (`defence(..., One([Defence]))`). No new rule needed:
  targeting is by tags. Check: Acid removes defence rather than preventing
  damage, so it likely sits outside the efficiency band like Smoke and is
  tuned with `counter_check`. Acid plus Ignite would burn zeroed shields.

## 3. Reactor (idea)

Energy weapons. Loot: lasers, capacitors, deflectors, drones.

- Beam knight and Twin beam as now.
- **Arc welder:** laser and capacitors.
- **Coolant carrier:** drone bay and deflectors.
- **Spark moth:** a Mosquito with a laser (level monster).
- **BOSS Meltdown core**, with **Critical mass**: its energy income rises
  during the match, so it must be killed fast. Needs a **new rule**: energy
  rate changing over time (energy is computed from timestamps, so a rate
  that depends on match time fits).

## 4. Arsenal (idea)

Heavy military. Loot: cannons, missile racks, drone bays, heavy plating.

- Bastion, Bulwark, Gunship and Hornet as now.
- **BOSS Siege tank** as now, or a **Carrier** with two drone bays.

## More theme ideas

- **Mine:** drills (saws), rams, and a Once dynamite charge.
- **Foundry:** molten fire and heavy plating.
- **Docks:** cranes, and anchors that hit very hard.

## Open questions

1. **Order:** Dump, Toxic waste, Reactor, Arsenal follows the loot charts.
   Should later runs shuffle the middle levels?
2. **Boss weapons as loot:** should a beaten boss sometimes drop its unique
   weapon (the Crusher plate), or should those stay boss-only?
3. **Themed loot:** should each level's loot chart lean further toward its
   theme (more armor in the Dump, more fire in Toxic waste)?
4. **Level 2 and 3 rosters** still mix themes (Firebug and Rocket turtle are
   on level 2, Twin beam on level 3) until those levels get their themes.
