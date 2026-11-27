//// Components in tables: grouped by kind, a heading row per kind
//// (WEAPONS, BATTERIES...) and a row per component; a robot's table starts
//// with its chassis.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre/element.{type Element}
import robots/construction/builder
import robots/construction/part.{type Component, Weapon}
import robots/rules/scale.{type Scale}
import robots/run/price
import robots/run/state.{type Bot}
import robots_client/common/ui.{table, table_group, table_note, table_row}
import robots_client/common/wording.{kind_groups, kind_plural, num, part_stat}

/// Parts in a table grouped by kind: Part, Weight, Stats, and a price
/// column (`price_header`, `price`). `select(index)` says whether a row is
/// selected and what clicking it sends.
pub fn part_table(
  s: Scale,
  parts: List(Component),
  price_header: String,
  price: fn(Component) -> Int,
  select: fn(Int) -> #(Bool, msg),
) -> Element(msg) {
  table(
    headers(price_header),
    part_rows(s, parts, price, select, fn(_) { True }),
  )
}

/// A robot in a table: its chassis first (the weight carried over what it
/// can carry, its HP), then
/// its weapon mounts (each with its weapon, or empty), then its other parts
/// grouped by kind, each with what it's worth. `chassis` and
/// `select(index)` say whether a row is selected and what clicking it sends.
pub fn robot_table(
  s: Scale,
  bot: Bot,
  chassis: #(Bool, msg),
  select: fn(Int) -> #(Bool, msg),
) -> Element(msg) {
  let headers = headers("Value")
  let #(selected, msg) = chassis
  let frame = bot.chassis
  table(headers, [
    table_group("CHASSIS", list.length(headers)),
    table_row(
      [
        frame.name,
        num(part.total_weight(bot.parts)) <> "/" <> num(frame.capacity),
        "HP "
          <> int.to_string(scale.value(s, builder.chassis_hp(frame)))
          <> "/"
          <> int.to_string(scale.value(s, frame.hp)),
        scrap(price.of_chassis(frame)),
      ],
      selected,
      msg,
    ),
    ..list.append(
      weapon_rows(s, bot, select),
      part_rows(s, bot.parts, price.of, select, fn(kind) { kind != Weapon }),
    )
  ])
}

/// A row per weapon mount, biggest first: the weapon on it, its weight over
/// the mount's ("1.5/2", "3/2 too heavy"), or an empty mount ("-/2").
/// Weapons beyond the mounts follow, with no mount.
fn weapon_rows(
  s: Scale,
  bot: Bot,
  select: fn(Int) -> #(Bool, msg),
) -> List(Element(msg)) {
  let weapons =
    list.index_map(bot.parts, fn(p, i) { #(i, p) })
    |> list.filter(fn(pair) { { pair.1 }.kind == Weapon })
  let row = fn(i, p, fit) {
    let #(selected, msg) = select(i)
    table_row(
      [part.display_name(p), fit, part_stat(s, p), scrap(price.of(p))],
      selected,
      msg,
    )
  }
  let #(left, mounted) =
    list.map_fold(builder.mounts(bot.chassis, bot.parts), weapons, fn(pool, m) {
      let #(limit, held) = m
      let found = case held {
        Some(w) -> take(pool, w)
        None -> Error(Nil)
      }
      case found {
        Ok(#(#(i, w), rest)) -> {
          let weight = part.weight(w)
          let fit =
            num(weight)
            <> "/"
            <> num(limit)
            <> case weight >. limit {
              True -> " too heavy"
              False -> ""
            }
          #(rest, row(i, w, fit))
        }
        Error(Nil) -> #(
          pool,
          table_note(["empty mount", "-/" <> num(limit), "", ""]),
        )
      }
    })
  let unmounted =
    list.map(left, fn(pair) {
      row(pair.0, pair.1, num(part.weight(pair.1)) <> " · no mount")
    })
  case mounted, unmounted {
    [], [] -> []
    _, _ -> [
      table_group(string.uppercase(kind_plural(Weapon)), 4),
      ..list.append(mounted, unmounted)
    ]
  }
}

/// Take the first `item` out of `pool`, with its index.
fn take(
  pool: List(#(Int, Component)),
  item: Component,
) -> Result(#(#(Int, Component), List(#(Int, Component))), Nil) {
  case pool {
    [] -> Error(Nil)
    [#(_, p) as first, ..rest] if p == item -> Ok(#(first, rest))
    [first, ..rest] -> {
      use #(found, others) <- result.map(take(rest, item))
      #(found, [first, ..others])
    }
  }
}

fn headers(price_header: String) -> List(String) {
  ["Part", "Weight", "Stats", price_header]
}

/// A group row per kind (those `show` keeps), then a row per part.
fn part_rows(
  s: Scale,
  parts: List(Component),
  price: fn(Component) -> Int,
  select: fn(Int) -> #(Bool, msg),
  show: fn(part.Kind) -> Bool,
) -> List(Element(msg)) {
  kind_groups(parts)
  |> list.filter(fn(group) { show(group.0) })
  |> list.flat_map(fn(group) {
    let #(kind, items) = group
    [
      table_group(string.uppercase(kind_plural(kind)), 4),
      ..list.map(items, fn(pair) {
        let #(i, p) = pair
        let #(selected, msg) = select(i)
        table_row(
          [
            part.display_name(p),
            num(part.weight(p)),
            part_stat(s, p),
            scrap(price(p)),
          ],
          selected,
          msg,
        )
      })
    ]
  })
}

fn scrap(amount: Int) -> String {
  int.to_string(amount) <> " scrap"
}

/// Spare parts to pick from in a garage: what each is worth.
pub fn spare_table(
  s: Scale,
  parts: List(Component),
  chosen: List(Int),
  click: fn(Int) -> msg,
) -> Element(msg) {
  part_table(s, parts, "Value", price.of, fn(i) {
    #(list.contains(chosen, i), click(i))
  })
}
