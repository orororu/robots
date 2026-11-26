//// Blueprints (see docs/META.md): what the fabricator can make. One for each
//// part and chassis, by name. A run can find blueprints (`roll`); between
//// runs, Data researches them (`robots/meta/profile`), and from then on
//// the fabricator builds starting robots with that part or chassis, plain
//// (no attributes or modifiers), as many as the design needs.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/content/components
import robots/rules/rng.{type Seed}
import robots/run/loot
import robots/run/map.{type Tier}
import robots/run/price

pub type Blueprint {
  PartBlueprint(name: String)
  ChassisBlueprint(name: String)
}

pub fn name(blueprint: Blueprint) -> String {
  blueprint.name
}

/// The part a blueprint makes: plain, as in `components.all`.
pub fn part(name: String) -> Result(Component, Nil) {
  list.find(components.all(), fn(p) { p.name == name })
}

pub fn chassis(name: String) -> Result(Chassis, Nil) {
  list.find(components.chassis(), fn(c) { c.name == name })
}

/// Whether the blueprint names a part or chassis that exists.
pub fn exists(blueprint: Blueprint) -> Bool {
  case blueprint {
    PartBlueprint(name) -> part(name) != Error(Nil)
    ChassisBlueprint(name) -> chassis(name) != Error(Nil)
  }
}

/// What researching it costs in Data: a share of the thing's price,
/// rounded to 5, at least `min_research`.
pub fn research_cost(blueprint: Blueprint) -> Int {
  let #(scrap, share) = case blueprint {
    PartBlueprint(name) ->
      case part(name) {
        Ok(p) -> #(price.of(p), research_share)
        Error(Nil) -> #(0, research_share)
      }
    ChassisBlueprint(name) ->
      case chassis(name) {
        Ok(c) -> #(price.of_chassis(c), chassis_research_share)
        Error(Nil) -> #(0, chassis_research_share)
      }
  }
  let rounded = float.round(int.to_float(scrap) *. share /. 5.0) * 5
  int.max(min_research, rounded)
}

/// Data per point of price (in scrap), for research: parts cost 10-35 (a run pays
/// about 24), chassis 55-70.
pub const research_share = 0.5

/// Chassis are priced high in scrap (HP, capacity, cards): a smaller share.
pub const chassis_research_share = 0.2

pub const min_research = 10

/// Chance a strong enemy drops a blueprint, in percent. A boss always does.
pub const strong_percent = 15

/// A blueprint drop for beating an enemy of `tier` on `level`: one of the
/// level's parts (its loot chart) or chassis (what its bosses and strong
/// enemies drop). It can be one the player has: each blueprint is one more
/// copy the fabricator can make.
pub fn roll(level: Int, tier: Tier, seed: Seed) -> #(Option(Blueprint), Seed) {
  let #(drops, seed) = case tier {
    map.Boss -> #(True, seed)
    map.Strong -> {
      let #(roll, seed) = rng.int_below(seed, 100)
      #(roll < strong_percent, seed)
    }
    map.Normal -> #(False, seed)
  }
  let chart = loot.chart(level)
  let options =
    list.flatten([
      list.map(chart.entries, fn(e) { PartBlueprint({ e.1 }.name) }),
      list.map(list.append(chart.boss_chassis, chart.strong_chassis), fn(c) {
        ChassisBlueprint(c.name)
      }),
    ])
    |> list.unique
  case drops, options {
    True, [_, ..] -> {
      let #(i, seed) = rng.int_below(seed, list.length(options))
      #(list.drop(options, i) |> list.first |> option.from_result, seed)
    }
    _, _ -> #(None, seed)
  }
}

/// How a blueprint is listed: "Railgun (weapon)", "Scout (chassis)".
pub fn describe(blueprint: Blueprint) -> String {
  case blueprint {
    PartBlueprint(name) ->
      case part(name) {
        Ok(p) -> name <> " (" <> part.kind_name(p.kind) <> ")"
        Error(Nil) -> name
      }
    ChassisBlueprint(name) -> name <> " (chassis)"
  }
}
