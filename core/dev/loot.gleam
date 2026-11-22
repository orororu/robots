//// Loot report: each level's chart with drop chances and prices.
////
////     cd core && gleam run -m loot

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import robots/content/catalog
import robots/run/loot
import robots/run/price

pub fn main() -> Nil {
  io.println("CHASSIS PRICES")
  list.each(catalog.chassis(), fn(ch) {
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
  })
}
