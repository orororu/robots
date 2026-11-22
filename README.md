# Robots

A real-time card game: build robots, install components (each adds cards to your
deck), and play cards from a 4-card table visible to both sides, using energy
that accumulates over time. Rules: [docs/RULES.md](docs/RULES.md).

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
    content/
      catalog.gleam   all chassis, parts and starter robots (balance here)
    ai/
      brain.gleam     pure AI opponent (efficiency-based, saves energy)
    balance/      balancing tools used by tests and dev reports
      simulation.gleam  AI-vs-AI matches
      efficiency.gleam  card roles and value-per-cost bands
  dev/            reports: balance, tournament, counter_check
client/   Lustre browser app: text-mode view, clock, keyboard
```

## Commands

```sh
cd core   && gleam test                         # tests on BEAM
cd core   && gleam test --target javascript     # same tests on JS
cd core   && gleam run -m balance               # AI-vs-AI balance report
cd core   && gleam run -m tournament            # every legal build vs each other (~35 s)
cd core   && gleam run -m counter_check         # do counter parts beat their targets? (~2 min)
cd client && gleam run -m lustre/dev start      # dev server with live reload
cd client && gleam run -m lustre/dev build      # production bundle in client/dist
```

Controls: `1`–`4` (or click) to play a card, `R` to restart.
