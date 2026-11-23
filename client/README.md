# robots_client

Text-mode browser client for Robots, built with Lustre.

```sh
gleam run -m lustre/dev start   # dev server
gleam run -m lustre/dev build   # bundle in dist/
```

A run (`robots/run/state` in core) drives the screens:

- **Map:** pick the next node (yellow arrows). The garage is below.
- **Before a battle:** the enemy's name and description; click a robot to
  send it in first. FIGHT starts the battle.
- **Battle:** keys 1-9 play cards; Enter continues once it's over.
- **Repair shop:** repair robots for credits, then leave.
- **Garage:** select a part (installed or spare) to see its cards. Then
  Remove an installed one, Install a spare on a robot, or select one of
  each and Swap them (the panel shows what goes out and what comes in).
  Select a spare chassis, then spare parts, then Assemble to build a new
  robot.
- **Cards** are boxes colored by role: red attacks, blue defences, green
  buffs, grey specials (`src/robots_client/card_view.gleam`).
- **Run over:** start a new run.

`src/robots_client/battle_view.gleam` draws the battle screen.
