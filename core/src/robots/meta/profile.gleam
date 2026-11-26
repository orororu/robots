//// What carries over between runs (see docs/META.md): Data, blueprints,
//// the truck and the fabricator, and the robot designs a run starts with.
////
//// - Between runs, Data `research`es found blueprints. Each researched
////   blueprint becomes **one** component in the hangar's garage (the
////   `researched` list), with the blueprint's quality:
////   a second Laser needs a second Laser blueprint, found in a run. A
////   design can only use the copies there are, and so can all the
////   fabricated designs together.
//// - The fabricator builds the first `fabricator` designs into the run's
////   starting robots (`start`), each part as its blueprint has it.
//// - When a run is over, `finish` pays out its Data and adds the
////   blueprints it found.
////
//// Saved as text (`encode`, `decode`), so the client can keep it in the
//// browser.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import robots/construction/builder.{type BuildError}
import robots/construction/part.{type Component}
import robots/content/starters
import robots/meta/blueprint.{type Blueprint, ChassisBlueprint, PartBlueprint}
import robots/run/state.{type Bot, type Run, Bot}

pub type Profile {
  Profile(
    data: Int,
    /// What the fabricator can make: each entry one copy (a blueprint
    /// can be listed several times).
    researched: List(Blueprint),
    /// Found in runs, waiting for research (duplicates too).
    found: List(Blueprint),
    /// How many robots the truck carries in a run.
    truck: Int,
    /// How many designs the fabricator builds for a run.
    fabricator: Int,
    /// The robots a run starts with, in order: the fabricator builds the
    /// first `fabricator` of them.
    designs: List(Design),
    /// The highest level whose boss was beaten (0: none yet).
    best_level: Int,
    runs: Int,
  )
}

/// A robot to fabricate: its chassis by name, and its parts as their
/// blueprints make them (quality included).
pub type Design {
  Design(name: String, chassis: String, parts: List(Component))
}

pub type Error {
  NotFound(Blueprint)
  NotEnoughData(cost: Int, data: Int)
  /// The design uses a blueprint that isn't researched.
  NotResearched(Blueprint)
  /// The designs need `need` copies of a blueprint and there are `have`.
  NotEnoughCopies(blueprint: Blueprint, have: Int, need: Int)
  /// Every copy is needed by a design.
  InUse(Blueprint)
  CantBuild(design: String, errors: List(BuildError))
  NoSuchDesign
}

/// Data for each level whose boss is beaten for the first time.
pub const first_boss_bonus = 25

/// A new player: the Tinker's blueprints and design, a truck for two
/// robots and a fabricator for one.
pub fn new() -> Profile {
  let tinker = Design("Tinker", "Frame", starters.tinker_parts())
  Profile(
    data: 0,
    // One copy of each of the Tinker's parts (two Platings).
    researched: [
      ChassisBlueprint("Frame"),
      ..list.map(tinker.parts, PartBlueprint)
    ],
    found: [],
    truck: state.default_truck,
    fabricator: 1,
    designs: [tinker],
    best_level: 0,
    runs: 0,
  )
}

// RESEARCH --------------------------------------------------------------------

/// Research a found blueprint for its `blueprint.research_cost` in Data:
/// one more copy the fabricator can make.
pub fn research(profile: Profile, b: Blueprint) -> Result(Profile, Error) {
  use <- guard(!list.contains(profile.found, b), NotFound(b))
  let cost = blueprint.research_cost(b)
  use profile <- result.try(pay(profile, cost))
  Ok(
    Profile(
      ..profile,
      researched: list.append(profile.researched, [b]),
      found: remove_one(profile.found, b),
    ),
  )
}

/// How many copies of a blueprint the fabricator can make.
pub fn copies(profile: Profile, b: Blueprint) -> Int {
  list.count(profile.researched, fn(r) { r == b })
}

/// What selling a blueprint pays: a fifth of its research cost, at least 1.
pub fn sell_price(b: Blueprint) -> Int {
  int.max(1, blueprint.research_cost(b) * sell_percent / 100)
}

pub const sell_percent = 20

/// Sell a found blueprint instead of researching it.
pub fn sell_found(profile: Profile, b: Blueprint) -> Result(Profile, Error) {
  use <- guard(!list.contains(profile.found, b), NotFound(b))
  Ok(
    Profile(
      ..profile,
      data: profile.data + sell_price(b),
      found: remove_one(profile.found, b),
    ),
  )
}

/// Sell a component from the garage (a researched blueprint's), unless
/// every one of it is needed by a design. The starting kit's sell too:
/// the saved design keeps a robot that can always be fabricated.
pub fn sell_researched(
  profile: Profile,
  b: Blueprint,
) -> Result(Profile, Error) {
  let have = copies(profile, b)
  let needed =
    list.flat_map(profile.designs, needs) |> list.count(fn(n) { n == b })
  use <- guard(have == 0, NotResearched(b))
  use <- guard(have <= needed, InUse(b))
  Ok(
    Profile(
      ..profile,
      data: profile.data + sell_price(b),
      researched: remove_one(profile.researched, b),
    ),
  )
}

fn pay(profile: Profile, cost: Int) -> Result(Profile, Error) {
  use <- guard(cost > profile.data, NotEnoughData(cost, profile.data))
  Ok(Profile(..profile, data: profile.data - cost))
}

fn remove_one(items: List(a), item: a) -> List(a) {
  case items {
    [] -> []
    [x, ..rest] if x == item -> rest
    [x, ..rest] -> [x, ..remove_one(rest, item)]
  }
}

fn guard(
  failed: Bool,
  error: Error,
  next: fn() -> Result(a, Error),
) -> Result(a, Error) {
  case failed {
    True -> Error(error)
    False -> next()
  }
}

// DESIGNS AND THE FABRICATOR --------------------------------------------------

/// The blueprints a design needs, one per part and one for its chassis.
pub fn needs(design: Design) -> List(Blueprint) {
  [ChassisBlueprint(design.chassis), ..list.map(design.parts, PartBlueprint)]
}

/// Designs built into robots together: there must be a copy of every
/// blueprint for each use, and each build must be legal.
pub fn fabricate_all(
  profile: Profile,
  designs: List(Design),
) -> Result(List(Bot), Error) {
  let needed = list.flat_map(designs, needs)
  use _ <- result.try(
    list.try_each(list.unique(needed), fn(b) {
      let need = list.count(needed, fn(n) { n == b })
      case copies(profile, b) {
        0 -> Error(NotResearched(b))
        have if have < need -> Error(NotEnoughCopies(b, have, need))
        _ -> Ok(Nil)
      }
    }),
  )
  list.try_map(designs, build_design)
}

/// A design built into a robot, if there are copies of its blueprints and
/// the build is legal.
pub fn fabricate(profile: Profile, design: Design) -> Result(Bot, Error) {
  use bots <- result.try(fabricate_all(profile, [design]))
  let assert [bot] = bots
  Ok(bot)
}

fn build_design(design: Design) -> Result(Bot, Error) {
  let chassis_bp = ChassisBlueprint(design.chassis)
  use <- guard(!blueprint.exists(chassis_bp), NotFound(chassis_bp))
  let assert Ok(chassis) = blueprint.chassis(design.chassis)
  use _ <- result.try(
    list.try_each(design.parts, fn(p) {
      case blueprint.exists(PartBlueprint(p)) {
        True -> Ok(Nil)
        False -> Error(NotFound(PartBlueprint(p)))
      }
    }),
  )
  let bot = Bot(name: design.name, chassis:, parts: design.parts)
  case state.build(bot) {
    Ok(_) -> Ok(bot)
    Error(state.CantBuild(errors:, ..)) -> Error(CantBuild(design.name, errors))
    Error(_) -> Error(CantBuild(design.name, []))
  }
}

/// Replace design `index` (or add it, one past the end), if it can be
/// fabricated.
pub fn set_design(
  profile: Profile,
  index: Int,
  design: Design,
) -> Result(Profile, Error) {
  use <- guard(index < 0 || index > list.length(profile.designs), NoSuchDesign)
  use _ <- result.try(fabricate(profile, design))
  let designs = case index == list.length(profile.designs) {
    True -> list.append(profile.designs, [design])
    False ->
      list.index_map(profile.designs, fn(d, i) {
        case i == index {
          True -> design
          False -> d
        }
      })
  }
  Ok(Profile(..profile, designs:))
}

/// A new run with the fabricated robots and the truck.
pub fn start(profile: Profile, seed: Int) -> Result(Run, Error) {
  use robots <- result.try(fabricate_all(
    profile,
    list.take(profile.designs, profile.fabricator),
  ))
  Ok(state.start(seed, robots, profile.truck))
}

// AFTER A RUN -----------------------------------------------------------------

/// What a run pays out.
pub type Earnings {
  Earnings(data: Int, bonus: Int, found: List(Blueprint))
}

/// What `finish` would pay for this run: its Data, a bonus for each
/// level whose boss it beat for the first time, and the blueprints it found.
pub fn earnings(profile: Profile, run: Run) -> Earnings {
  let cleared = run.level - 1
  let bonus = int.max(0, cleared - profile.best_level) * first_boss_bonus
  Earnings(data: state.data(run), bonus:, found: run.found)
}

/// Pay out a finished run.
pub fn finish(profile: Profile, run: Run) -> Profile {
  let e = earnings(profile, run)
  Profile(
    ..profile,
    data: profile.data + e.data + e.bonus,
    found: list.append(profile.found, e.found),
    best_level: int.max(profile.best_level, run.level - 1),
    runs: profile.runs + 1,
  )
}

// SAVING ----------------------------------------------------------------------
// One line per field, "key:value". Lists are separated by "|"; a blueprint
// is `blueprint.to_text` ("c:Frame", "p:Laser+3=Rapid"); a design is
// "Name/Chassis/Part;Part;..." with parts as `blueprint.part_text`. Names
// never contain those characters.

pub fn encode(profile: Profile) -> String {
  let blueprints = fn(bs) { string.join(list.map(bs, blueprint.to_text), "|") }
  [
    "data:" <> int.to_string(profile.data),
    "researched:" <> blueprints(profile.researched),
    "found:" <> blueprints(profile.found),
    "truck:" <> int.to_string(profile.truck),
    "fabricator:" <> int.to_string(profile.fabricator),
    "best_level:" <> int.to_string(profile.best_level),
    "runs:" <> int.to_string(profile.runs),
    "designs:"
      <> string.join(
      list.map(profile.designs, fn(d) {
        d.name
        <> "/"
        <> d.chassis
        <> "/"
        <> string.join(list.map(d.parts, blueprint.part_text), ";")
      }),
      "|",
    ),
  ]
  |> string.join("\n")
}

/// A saved profile. Blueprints of things no longer in the game are
/// dropped, and so are designs that can't be fabricated any more; missing
/// fields keep `new`'s values.
pub fn decode(text: String) -> Result(Profile, Nil) {
  let fields =
    string.split(text, "\n")
    |> list.filter_map(fn(line) { string.split_once(line, ":") })
  use _ <- result.try(list.key_find(fields, "data"))
  let base = new()
  let number = fn(key, default) {
    list.key_find(fields, key)
    |> result.try(int.parse)
    |> result.unwrap(default)
  }
  let blueprints = fn(key, default) {
    case list.key_find(fields, key) {
      Ok("") -> []
      Ok(value) ->
        string.split(value, "|")
        |> list.filter_map(blueprint.from_text)
      Error(Nil) -> default
    }
  }
  let profile =
    Profile(
      data: number("data", 0),
      researched: blueprints("researched", []),
      found: blueprints("found", []),
      truck: number("truck", base.truck),
      fabricator: number("fabricator", base.fabricator),
      designs: [],
      best_level: number("best_level", 0),
      runs: number("runs", 0),
    )
  let designs =
    case list.key_find(fields, "designs") {
      Ok(value) -> string.split(value, "|") |> list.filter_map(decode_design)
      Error(Nil) -> []
    }
    |> list.filter(fn(d) { fabricate(profile, d) |> result.is_ok })
  let designs = case designs {
    [] -> base.designs
    _ -> designs
  }
  Ok(Profile(..profile, designs:))
}

fn decode_design(text: String) -> Result(Design, Nil) {
  case string.split(text, "/") {
    [name, chassis, ""] -> Ok(Design(name, chassis, []))
    [name, chassis, parts] ->
      string.split(parts, ";")
      |> list.try_map(blueprint.part_from_text)
      |> result.map(Design(name, chassis, _))
    _ -> Error(Nil)
  }
}

/// The design the fabricator would build `index`-th, if any.
pub fn design(profile: Profile, index: Int) -> Result(Design, Nil) {
  list.drop(profile.designs, index) |> list.first
}

/// Blueprints found but not researched, with their research cost.
pub fn waiting(profile: Profile) -> List(#(Blueprint, Int)) {
  list.map(profile.found, fn(b) { #(b, blueprint.research_cost(b)) })
}
