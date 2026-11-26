//// Blueprints (see docs/META.md): what the fabricator can make. A part
//// blueprint is a particular part, quality included: a Rapid Laser and a
//// Precise Laser are different blueprints. A chassis blueprint is a chassis
//// by name. A run can find blueprints (`roll`); between runs, Data
//// researches them (`robots/meta/profile`), and from then on the fabricator
//// builds starting robots with that part, exactly as the blueprint has it.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robots/construction/attribute
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component, Component}
import robots/content/components
import robots/rules/rng.{type Seed}
import robots/run/loot
import robots/run/map.{type Tier}
import robots/run/price

pub type Blueprint {
  /// A part as the fabricator makes it: new (no wear), with the modifiers
  /// and attributes the blueprint was found with.
  PartBlueprint(part: Component)
  ChassisBlueprint(name: String)
}

pub fn name(blueprint: Blueprint) -> String {
  case blueprint {
    PartBlueprint(p) -> p.name
    ChassisBlueprint(name) -> name
  }
}

/// The blueprint of a part as it is (worn plates come out new).
pub fn of_part(p: Component) -> Blueprint {
  PartBlueprint(Component(..p, wear: 0.0))
}

/// The plain part with this name, as in `components.all`.
pub fn part(name: String) -> Result(Component, Nil) {
  list.find(components.all(), fn(p) { p.name == name })
}

pub fn chassis(name: String) -> Result(Chassis, Nil) {
  list.find(components.chassis(), fn(c) { c.name == name })
}

/// Whether the blueprint names a part or chassis that exists.
pub fn exists(blueprint: Blueprint) -> Bool {
  case blueprint {
    PartBlueprint(p) -> part(p.name) != Error(Nil)
    ChassisBlueprint(name) -> chassis(name) != Error(Nil)
  }
}

/// What researching it costs in Data: a share of the thing's price,
/// rounded to 5, at least `min_research`. Better parts cost more.
pub fn research_cost(blueprint: Blueprint) -> Int {
  let #(scrap, share) = case blueprint {
    PartBlueprint(p) -> #(price.of(p), research_share)
    ChassisBlueprint(name) ->
      case chassis(name) {
        Ok(c) -> #(price.of_chassis(c), chassis_research_share)
        Error(Nil) -> #(0, chassis_research_share)
      }
  }
  let rounded = float.round(int.to_float(scrap) *. share /. 5.0) * 5
  int.max(min_research, rounded)
}

/// Data per point of price (in scrap), for research: plain parts cost
/// 10-35 (a run pays about 24), chassis 55-70.
pub const research_share = 0.5

/// Chassis are priced high in scrap (HP, capacity, cards): a smaller share.
pub const chassis_research_share = 0.2

pub const min_research = 10

/// Chance a strong enemy drops a blueprint, in percent. A boss always does.
pub const strong_percent = 15

/// A blueprint drop for beating an enemy of `tier` on `level`: one of the
/// level's parts (its loot chart), with the quality a shop's parts have
/// (`loot.roll_shop`), or one of its chassis (what its bosses and strong
/// enemies drop). Every drop is one more copy: a second Laser needs a
/// second Laser blueprint.
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
  let parts =
    list.length(list.unique(list.map(chart.entries, fn(e) { { e.1 }.name })))
  let chassis =
    list.append(chart.boss_chassis, chart.strong_chassis)
    |> list.map(fn(c) { c.name })
    |> list.unique
  case drops {
    False -> #(None, seed)
    True -> {
      let #(i, seed) = rng.int_below(seed, parts + list.length(chassis))
      case list.drop(chassis, i - parts) {
        [name, ..] if i >= parts -> #(Some(ChassisBlueprint(name)), seed)
        _ -> {
          let #(p, seed) = loot.roll_shop(level, seed)
          #(Some(of_part(p)), seed)
        }
      }
    }
  }
}

/// How a blueprint is listed: "Rapid laser (weapon)", "Scout (chassis)".
pub fn describe(blueprint: Blueprint) -> String {
  case blueprint {
    PartBlueprint(p) ->
      part.display_name(p) <> " (" <> part.kind_name(p.kind) <> ")"
    ChassisBlueprint(name) -> name <> " (chassis)"
  }
}

// AS TEXT ---------------------------------------------------------------------
// "c:Frame", or "p:Laser" with "+light", "+overclocked" and "+3=Rapid" (card
// 3's attribute) for its quality. Names never contain ":", "+" or "=".

pub fn to_text(blueprint: Blueprint) -> String {
  case blueprint {
    ChassisBlueprint(name) -> "c:" <> name
    PartBlueprint(p) -> "p:" <> part_text(p)
  }
}

pub fn from_text(text: String) -> Result(Blueprint, Nil) {
  case string.split_once(text, ":") {
    Ok(#("p", rest)) -> part_from_text(rest) |> result.map(PartBlueprint)
    Ok(#("c", name)) ->
      case chassis(name) {
        Ok(_) -> Ok(ChassisBlueprint(name))
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// A part with its quality as text, e.g. "Laser+light+3=Rapid".
pub fn part_text(p: Component) -> String {
  let modifiers =
    list.map(p.modifiers, fn(m) {
      case m {
        part.Light(_) -> "+light"
        part.Overclocked(_) -> "+overclocked"
      }
    })
  let attributes =
    list.map(p.attributes, fn(pair) {
      "+" <> int.to_string(pair.0) <> "=" <> { pair.1 }.name
    })
  string.concat([p.name, ..list.append(modifiers, attributes)])
}

/// A part from `part_text`, if it and its attributes are still in the game.
pub fn part_from_text(text: String) -> Result(Component, Nil) {
  let assert [name, ..quality] = string.split(text, "+")
  use base <- result.try(part(name))
  list.try_fold(quality, base, fn(p, q) {
    case q, string.split_once(q, "=") {
      "light", _ -> Ok(part.with(p, part.light()))
      "overclocked", _ -> Ok(part.with(p, part.overclocked()))
      _, Ok(#(index, attribute_name)) -> {
        use index <- result.try(int.parse(index))
        use a <- result.try(
          list.find(attribute.all(), fn(a) { a.name == attribute_name }),
        )
        Ok(Component(..p, attributes: list.append(p.attributes, [#(index, a)])))
      }
      _, _ -> Error(Nil)
    }
  })
}
