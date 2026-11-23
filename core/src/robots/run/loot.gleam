//// Loot charts: which parts can drop on each level, and how likely each is
//// (see docs/RUN.md). Weights are relative: a part with weight 10 drops twice
//// as often as one with weight 5. Plating stays common on every level: there
//// is no repair between nodes, so looted armor is how a robot heals.
////
//// Loot is worth picking up: never worse than a new part. Each card of a
//// drop may get one attribute (`attribute.gleam`), only neutral trade-offs
//// (Quick, Precise) and gains, likelier and better on later levels. (Bad
//// attributes are for worn-down enemies and broken plates.)
////
//// How many parts a battle drops is up to the run (`run/state`). Bosses
//// also drop a chassis: good chassis are special loot (or bought,
//// expensively).

import gleam/int
import gleam/list
import robots/construction/attribute.{type Attribute} as a
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/content/components as c
import robots/rules/rng.{type Seed}

pub type Chart {
  Chart(
    level: Int,
    entries: List(#(Int, Component)),
    /// Percent chance that a drop is Light (lighter) and, separately, that
    /// it is Overclocked (stronger). A drop can be both.
    light_percent: Int,
    overclocked_percent: Int,
    /// Chassis the level's boss can drop, one picked at random.
    boss_chassis: List(Chassis),
    /// Percent chance that each card of a drop gets an attribute.
    attribute_percent: Int,
    /// Which attribute, when it does (relative weights).
    attributes: List(#(Int, Attribute)),
  )
}

pub fn charts() -> List(Chart) {
  [
    // The scrapyard: small, simple parts.
    Chart(
      level: 1,
      entries: [
        #(12, c.plating()),
        #(10, c.fist()),
        #(8, c.saw_arm()),
        #(8, c.machine_gun()),
        #(6, c.laser()),
        #(8, c.buckler()),
        #(8, c.deflector()),
        #(6, c.kinetic_shield()),
        #(5, c.targeting_computer()),
        #(5, c.hydraulics()),
        #(8, c.cell()),
        #(6, c.battery()),
        #(4, c.capacitor()),
        #(4, c.servo_pack()),
        #(4, c.shield_booster()),
        #(3, c.gyroscope()),
      ],
      light_percent: 10,
      overclocked_percent: 10,
      boss_chassis: [c.brute(), c.scout()],
      attribute_percent: 30,
      attributes: [
        #(4, a.worn()),
        #(3, a.sluggish()),
        #(6, a.quick()),
        #(6, a.precise()),
        #(10, a.tuned()),
        #(8, a.efficient()),
        #(5, a.strong()),
        #(3, a.rapid()),
        #(1, a.overcharged()),
      ],
    ),
    // Specialists appear: fire, missiles, counters.
    Chart(
      level: 2,
      entries: [
        #(10, c.plating()),
        #(5, c.heavy_plating()),
        #(4, c.fist()),
        #(6, c.saw_arm()),
        #(5, c.machine_gun()),
        #(8, c.laser()),
        #(6, c.flamethrower()),
        #(5, c.missile_rack()),
        #(5, c.buckler()),
        #(5, c.deflector()),
        #(6, c.kinetic_shield()),
        #(4, c.smoke_launcher()),
        #(4, c.point_defence()),
        #(4, c.targeting_computer()),
        #(4, c.hydraulics()),
        #(4, c.shield_booster()),
        #(4, c.gyroscope()),
        #(6, c.battery()),
        #(4, c.big_battery()),
        #(4, c.capacitor()),
        #(3, c.big_capacitor()),
        #(4, c.servo_pack()),
        #(3, c.big_servo_pack()),
      ],
      light_percent: 20,
      overclocked_percent: 20,
      boss_chassis: [c.scout(), c.tank()],
      attribute_percent: 40,
      attributes: [
        #(2, a.worn()),
        #(2, a.sluggish()),
        #(5, a.quick()),
        #(6, a.precise()),
        #(8, a.tuned()),
        #(7, a.efficient()),
        #(8, a.strong()),
        #(6, a.rapid()),
        #(3, a.overcharged()),
        #(1, a.masterwork()),
      ],
    ),
    // Heavy weapons: cannons and drones.
    Chart(
      level: 3,
      entries: [
        #(5, c.plating()),
        #(10, c.heavy_plating()),
        #(4, c.saw_arm()),
        #(6, c.laser()),
        #(5, c.flamethrower()),
        #(6, c.missile_rack()),
        #(5, c.cannon()),
        #(5, c.drone_bay()),
        #(3, c.buckler()),
        #(3, c.deflector()),
        #(5, c.kinetic_shield()),
        #(5, c.smoke_launcher()),
        #(5, c.point_defence()),
        #(4, c.shield_booster()),
        #(3, c.gyroscope()),
        #(3, c.battery()),
        #(6, c.big_battery()),
        #(4, c.big_capacitor()),
        #(4, c.big_servo_pack()),
      ],
      light_percent: 30,
      overclocked_percent: 30,
      boss_chassis: [c.tank()],
      attribute_percent: 50,
      attributes: [
        #(4, a.quick()),
        #(6, a.precise()),
        #(5, a.tuned()),
        #(5, a.efficient()),
        #(9, a.strong()),
        #(8, a.rapid()),
        #(5, a.overcharged()),
        #(3, a.masterwork()),
      ],
    ),
  ]
}

/// The chart for a level. Levels past the last chart use the last one.
pub fn chart(level: Int) -> Chart {
  let all = charts()
  let assert Ok(last) = list.last(all)
  case list.find(all, fn(ch) { ch.level == level }) {
    Ok(ch) -> ch
    Error(Nil) if level < 1 -> {
      let assert [first, ..] = all
      first
    }
    Error(Nil) -> last
  }
}

/// One random drop from the level's chart, with its modifiers.
pub fn roll(level: Int, seed: Seed) -> #(Component, Seed) {
  let ch = chart(level)
  let total = int.sum(list.map(ch.entries, fn(e) { e.0 }))
  let #(pick, seed) = rng.int_below(seed, total)
  let component = pick_entry(ch.entries, pick)
  let #(light, seed) = rng.int_below(seed, 100)
  let #(overclocked, seed) = rng.int_below(seed, 100)
  let component = case light < ch.light_percent {
    True -> part.with(component, part.light())
    False -> component
  }
  let component = case overclocked < ch.overclocked_percent {
    True -> part.with(component, part.overclocked())
    False -> component
  }
  roll_attributes(ch, component, seed)
}

/// Each card may get one attribute, picked among those that affect it.
pub fn roll_attributes(
  ch: Chart,
  component: Component,
  seed: Seed,
) -> #(Component, Seed) {
  roll_card_attributes(component, ch.attribute_percent, ch.attributes, seed)
}

/// Give each card of `component`, with `percent` chance, an attribute from
/// the weighted `attributes` (only ones that affect that card).
pub fn roll_card_attributes(
  component: Component,
  percent: Int,
  attributes: List(#(Int, a.Attribute)),
  seed: Seed,
) -> #(Component, Seed) {
  component.cards
  |> list.index_map(fn(card, i) { #(i, card) })
  |> list.fold(#(component, seed), fn(acc, pair) {
    let #(component, seed) = acc
    let #(i, _) = pair
    let #(chance, seed) = rng.int_below(seed, 100)
    let options =
      list.filter(attributes, fn(e) { part.can_attach(component, i, e.1) })
    case chance < percent, options {
      True, [_, ..] -> {
        let total = int.sum(list.map(options, fn(e) { e.0 }))
        let #(pick, seed) = rng.int_below(seed, total)
        #(part.attach(component, i, pick_entry(options, pick)), seed)
      }
      _, _ -> #(component, seed)
    }
  })
}

/// `count` drops.
pub fn rolls(level: Int, count: Int, seed: Seed) -> #(List(Component), Seed) {
  let #(seed, drops) =
    list.map_fold(list.repeat(Nil, count), seed, fn(seed, _) {
      let #(drop, seed) = roll(level, seed)
      #(seed, drop)
    })
  #(drops, seed)
}

/// The boss's chassis drop.
pub fn boss_chassis(level: Int, seed: Seed) -> #(Chassis, Seed) {
  let options = chart(level).boss_chassis
  let #(i, seed) = rng.int_below(seed, list.length(options))
  let assert [pick, ..] = list.drop(options, i)
  #(pick, seed)
}

fn pick_entry(entries: List(#(Int, x)), pick: Int) -> x {
  case entries {
    [#(weight, component), ..rest] ->
      case pick < weight || rest == [] {
        True -> component
        False -> pick_entry(rest, pick - weight)
      }
    [] -> panic as "a loot chart can't be empty"
  }
}

/// Chance of each entry, in percent (0-100).
pub fn chances(ch: Chart) -> List(#(Component, Float)) {
  let total = int.to_float(int.sum(list.map(ch.entries, fn(e) { e.0 })))
  list.map(ch.entries, fn(e) { #(e.1, int.to_float(e.0) *. 100.0 /. total) })
}
