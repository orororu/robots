# Robots

A real-time card game: build robots, install components (each adds cards to your
deck), and play cards from a 4-card table visible to both sides, using energy
that accumulates over time. Rules: [docs/RULES.md](docs/RULES.md).
Robot builder: [docs/BUILDER.md](docs/BUILDER.md). Roguelike runs (draft):
[docs/RUN.md](docs/RUN.md).

## Layout

```
core/     pure game logic (Gleam, runs on JavaScript and BEAM): no IO, no clock
  src/robots/
    rules/        the match rules
      game.gleam      update(game, msg) -> Result(Game, Rejection)
      table.gleam     the 4 visible table slots and automatic targeting
      card.gleam      cards, tags, targets, traits; relative costs and values
      energy.gleam    energy computed from timestamps, never ticked
      amount.gleam    float comparisons with a tolerance
      scale.gleam     display scale: relative amounts -> shown numbers
      rng.gleam       seeded RNG, identical on both targets
    construction/ assembling robots
      part.gleam      components: kind, weight, cards, armor/battery, loot modifiers
      robot.gleam     built robots: HP, energy cap, deck, damage
      builder.gleam   chassis + parts -> robot, with errors and warnings
      build_search.gleam  generate legal builds (tournament, later AI and garage)
      wear.gleam      damage kept on armor plates and chassis between battles
      attribute.gleam card attributes from loot (Broken, Rapid, Precise...)
    content/
      cards.gleam     every card, one function each (balance here)
      components.gleam  every part and chassis, built from those cards
      starters.gleam  the starter robots
      enemies.gleam   the named enemy roster for each level of a run
    ai/
      brain.gleam     pure AI opponent: efficiency-based, saves energy, reacts
                      to changes after a human-like 0.5-0.8 s delay
    run/          the roguelike layer (docs/RUN.md)
      price.gleam     what parts and chassis are worth in credits
      loot.gleam      loot charts per level, battle drops, boss chassis
      map.gleam       a level's map: layered graph of battles and repair shops
      state.gleam     a run in progress: map, robots, spares, money, rewards
    balance/      balancing tools used by tests and dev reports
      simulation.gleam  AI-vs-AI matches
      efficiency.gleam  card roles and value-per-cost bands
  dev/            reports: balance, tournament, counter_check, loot, enemies, run
client/   Lustre browser app: text-mode run (map, garage, shop) and battles
```

## Commands

```sh
cd core   && gleam test                         # tests on BEAM
cd core   && gleam test --target javascript     # same tests on JS
cd core   && gleam run -m balance               # AI-vs-AI balance report
cd core   && gleam run -m tournament            # every legal build vs each other (~2.5 min)
cd core   && gleam run -m loot                  # loot charts with chances and prices
cd core   && gleam run -m enemies               # starters vs every enemy in the roster
cd core   && gleam run -m run                   # sample maps, then whole runs on autopilot
cd core   && gleam run -m counter_check         # do counter parts beat their targets? (~2 min)
cd client && gleam run -m lustre/dev start      # dev server with live reload
cd client && gleam run -m lustre/dev build      # production bundle in client/dist
```

`tournament` and `counter_check` run in parallel but leave 2 cores free;
set `ROBOTS_WORKERS=4` (for example) to use fewer.

Controls: `1`–`4` (or click) to play a card, `R` to restart.
