# Robots

A real-time card game: build robots, install components (each adds cards to your
deck), and play cards from a 4-card table visible to both sides, using energy
that accumulates over time. Rules: [docs/RULES.md](docs/RULES.md).

## Layout

```
core/     pure game logic (Gleam, runs on JavaScript and BEAM): no IO, no clock
  src/robots/
    game.gleam      update(game, msg) -> Result(Game, Rejection)
    table.gleam     the 4 visible table slots and automatic targeting
    card.gleam      cards, tags, target + scope; relative costs and values
    scale.gleam     display scale: relative amounts -> shown numbers
    energy.gleam    energy computed from timestamps, never ticked
    robot.gleam     robots, components, install, damage
    catalog.gleam   starter components and robots (balance here)
    ai.gleam        pure AI opponent
    rng.gleam       seeded RNG, identical on both targets
client/   Lustre browser app: text-mode view, clock, keyboard
```

## Commands

```sh
cd core   && gleam test                         # tests on BEAM
cd core   && gleam test --target javascript     # same tests on JS
cd client && gleam run -m lustre/dev start      # dev server with live reload
cd client && gleam run -m lustre/dev build      # production bundle in client/dist
```

Controls: `1`–`4` (or click) to play a card, `R` to restart.
