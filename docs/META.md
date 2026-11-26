# Meta progression: between runs

Currencies: **scrap** is a run's money (loot, repairs, parts); **Data** is
earned at a run's end and spent between runs.

Status: **first slice built** (`core/src/robots/meta/`, the client's
hangar). Most runs end in defeat, so every run should still leave the player
a little stronger or with more options for the next one.

## Agreed

- **The carrier truck** carries the robots of a run: **2 at first**, later
  upgraded to 3 and maybe 4. It carries any number of parts and spare
  chassis. With a full truck, assembling or buying a robot fails
  (`state.TruckFull`); the chassis waits as a spare.
- **Blueprints:** a run **finds** them; between runs, **Data
  pays to research** them. **Each researched blueprint makes one part or
  chassis**: a second Laser needs a second Laser blueprint, so a better
  start has to be discovered in runs. Duplicates drop, and each is one
  more copy. A design, and all the fabricated designs together, use only
  the copies there are (`profile.NotEnoughCopies`).
- **Blueprints have a quality.** A part blueprint is a particular part:
  its Light or Overclocked modifiers and its card attributes. A Rapid
  Laser and a Precise Laser are different blueprints, each with its own
  copies, listed side by side in the hangar, and the fabricator makes the
  part exactly as its blueprint has it. Chassis blueprints are plain.
  (A blueprint copier was tried and removed: another copy has to be
  found.)
- **The fabricator** builds a run's starting robots from researched
  blueprints. At first it builds **one robot**; upgrades raise that to 2,
  then maybe 3.
- Meta progression changes what a run starts with and what's possible, never
  card rules or enemy numbers (enemies stay symmetric).

## Data

Paid when a run is over (`state.data`, `profile.finish`):

| Source | Data |
|---|---|
| Battle won | 1 (strong enemy 3, boss 10) |
| Each level reached past the first | 5 |
| Scrap left | 1 per 20 |
| A level's boss beaten for the first time | +25, once per level |

The autopilot earns about **24 Data per run** and finds 0.7 blueprints.

## Blueprints

- **Drops** (`blueprint.roll`): a **boss always** drops one, a **strong
  enemy 15%** of the time. It's one of the level's parts (its loot chart),
  with the quality a shop's parts have (`loot.roll_shop`: the next
  level's odds for modifiers and attributes, a little better), or one of
  its chassis (what its bosses and strong enemies drop). It can be one the
  player already has: another copy.
- **Research cost** (`blueprint.research_cost`): half a part's price in
  scrap (its quality included), rounded to 5, at least 10: plain parts
  cost **10-35** (Point defence,
  Needle gun, Cell 10; Laser, Cannon, Drone bay 30; Big capacitor 35).
  Chassis at a fifth of their price: **55-70**. So about one part per run,
  a chassis every three.
- **Selling** (`profile.sell_found`, `sell_researched`): a blueprint sells
  for a fifth of its research cost, at least 1 Data (a Laser 6). Found
  ones instead of researching them; components in the fabricator unless a
  design needs every one of them. The starting kit's parts are ordinary
  components and sell too; the saved design can't lose its parts, so
  there's always a robot to fabricate.
- **To start:** one copy of each of the Tinker's blueprints (Frame, Laser,
  Buckler, Big capacitor, two Platings) and the Tinker design.

## The profile (`robots/meta/profile`)

- `Profile`: Data, researched and found blueprints, truck and fabricator
  sizes, designs, the best level cleared, runs played.
- `research`, `copies`, `sell_found`, `sell_researched`, `fabricate` and
  `fabricate_all` (designs into robots, if there's a copy of every
  blueprint for each use and each build is legal), `set_design`, `start`
  (a run with the fabricated robots and the truck), `earnings` and
  `finish`.
- Saved as text (`encode`, `decode`); a part blueprint is its name and
  quality ("p:Laser+light+0=Rapid", `blueprint.to_text`). The client keeps
  it in the browser's `localStorage`. Things no longer in the game are
  dropped on loading.

## The client

- **The start menu** opens the game: Continue (the run saved in the
  browser, if any) or New run (abandoning a saved run pays it out like a
  lost one), then the hangar.
- **The hangar** opens before every run, with three tabs at the top. The
  first, **Hangar**, open by default, shows the truck, the fabricator and
  the design (whether it can be fabricated), with Start a run. The others:
  - **Research lab** (with the count of found blueprints): blueprints
    found in runs, to research or sell;
  - **Garage**, laid out like a run's garage: the design as a robot
    (chassis, installed parts by kind), and below it the FABRICATOR's
    spare components, one row per copy (no stacking), grouped by kind,
    plus spare chassis. Installing a component takes it off the list.
    Select as in a run: install, remove, swap (an installed part and a
    component), build the design on another chassis, or sell a spare.
  Select, then act: Research, Sell, Add to the design (while a copy is
  free), Remove, Build the design on a chassis. Start a run.
- **The run's end** shows the Data earned and blueprints found; "To the
  hangar" pays it out.
- The battle report notes a blueprint drop; the header shows the truck
  ("1 of 2 robots in the truck").

## Next

- Upgrades for Data: the truck (3rd robot, then 4th), the fabricator
  (2nd robot, then 3rd), each with a second design in the hangar.
- An autopilot campaign: runs that earn, research and upgrade, to tune how
  fast progress comes.
- Maybe: blueprints for sale in shops; a starting kit (scrap or a spare).

## Open questions

1. Should a run's earnings be kept if the page is closed on the end screen?
   Now they're paid out by "To the hangar".
2. Should runs ever be won outright (after level 3), and pay a big bonus?
