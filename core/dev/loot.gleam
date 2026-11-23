//// Loot report: each level's chart with drop chances and prices.
////
////     cd core && gleam run -m loot

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import robots/construction/attribute.{Resize, Scale}
import robots/construction/part
import robots/content/components
import robots/content/enemies
import robots/rules/rng
import robots/run/loot
import robots/run/map
import robots/run/price

pub fn main() -> Nil {
  attribute_table()
  io.println("CHASSIS PRICES")
  list.each(components.chassis(), fn(ch) {
    io.println(
      "  "
      <> string.pad_end(ch.name, 8, " ")
      <> string.pad_start(int.to_string(price.of_chassis(ch)), 5, " ")
      <> "   carries "
      <> float.to_string(ch.capacity),
    )
  })
  list.each(loot.charts(), fn(ch) {
    let chances = loot.chances(ch)
    let average =
      list.fold(chances, 0.0, fn(t, e) {
        t +. int.to_float(price.of(e.0)) *. e.1 /. 100.0
      })
    io.println(
      "\n== Level "
      <> int.to_string(ch.level)
      <> " · Light "
      <> int.to_string(ch.light_percent)
      <> "% · Overclocked "
      <> int.to_string(ch.overclocked_percent)
      <> "% · boss drops "
      <> string.join(list.map(ch.boss_chassis, fn(x) { x.name }), " or ")
      <> " · average drop "
      <> int.to_string(float.round(average))
      <> " credits (before modifiers)",
    )
    io.println("  part                chance  price")
    chances
    |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
    |> list.each(fn(e) {
      io.println(
        "  "
        <> string.pad_end({ e.0 }.name, 20, " ")
        <> string.pad_start(
          float.to_string(float.to_precision(e.1, 1)) <> "%",
          6,
          " ",
        )
        <> string.pad_start(int.to_string(price.of(e.0)), 7, " "),
      )
    })
    samples(ch.level)
  })
}

/// Each attribute on a Laser card (cost 10, value 10): new numbers, and how
/// much its worth changes.
fn attribute_table() -> Nil {
  let assert [laser, ..] = list.drop(components.laser().cards, 1)
  io.println("CARD ATTRIBUTES (on a Laser card: cost 10, value 10)")
  io.println(
    "  attribute     effect                     cost value   worth  levels 1/2/3",
  )
  list.each(attribute.all(), fn(a) {
    let c = attribute.apply(a, laser)
    let change = attribute.card_worth(c) /. attribute.card_worth(laser) -. 1.0
    let effect = case a.effect {
      Scale(value:, cost:) ->
        pct_change("value", value) <> pct_change(" cost", cost)
      Resize(cost:) -> pct_change("cost", cost) <> ", value on band"
    }
    let weights =
      list.map(loot.charts(), fn(ch) {
        case list.find(ch.attributes, fn(e) { { e.1 }.name == a.name }) {
          Ok(e) -> int.to_string(e.0)
          Error(Nil) -> "-"
        }
      })
    io.println(
      "  "
      <> string.pad_end(a.name, 14, " ")
      <> string.pad_end(string.trim(effect), 27, " ")
      <> string.pad_start(f0(c.cost *. 10.0), 4, " ")
      <> string.pad_start(f0(c.value *. 10.0), 6, " ")
      <> string.pad_start(signed(change), 8, " ")
      <> "  "
      <> string.join(weights, "/"),
    )
  })
  io.println("")
}

fn pct_change(label: String, factor: Float) -> String {
  case factor == 1.0 {
    True -> ""
    False -> " " <> label <> " " <> signed(factor -. 1.0)
  }
}

fn signed(x: Float) -> String {
  let n = float.round(x *. 100.0)
  case n > 0 {
    True -> "+" <> int.to_string(n) <> "%"
    False -> int.to_string(n) <> "%"
  }
}

fn f0(x: Float) -> String {
  int.to_string(float.round(x))
}

/// A few random drops and enemies, to see the names.
fn samples(level: Int) -> Nil {
  let #(drops, _) = loot.rolls(level, 8, rng.new(level * 101))
  io.println(
    "  sample drops: "
    <> string.join(
      list.map(drops, fn(d) {
        part.display_name(d) <> " (" <> int.to_string(price.of(d)) <> ")"
      }),
      ", ",
    ),
  )
  let roster = enemies.level(level)
  let #(_, names) =
    list.map_fold(roster.enemies, rng.new(level * 7), fn(seed, e) {
      let #(spawned, seed) =
        enemies.spawn(e, level, map.condition(level, map.Normal), seed)
      #(seed, e.name <> " → " <> spawned.name)
    })
  io.println("  sample enemies: " <> string.join(names, ", "))
}
