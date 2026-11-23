import gleam/int
import gleam/list
import robots/rules/rng
import robots/run/map.{type Map, Battle, Boss, Normal, RepairShop}

fn maps() -> List(Map) {
  list.flat_map([1, 2, 3, 4], fn(level) {
    list.map(int.range(1, 26, [], list.prepend), fn(seed) {
      map.generate(level, rng.new(seed)).0
    })
  })
}

fn links(m: Map) -> List(#(map.Node, map.Node)) {
  list.flat_map(m.nodes, fn(n) { list.map(map.next(m, n), fn(to) { #(n, to) }) })
}

pub fn rows_have_the_right_widths_test() {
  list.each(maps(), fn(m) {
    list.each(int.range(0, map.rows, [], list.prepend), fn(r) {
      let width = list.length(map.row(m, r))
      assert width >= map.min_width && width <= map.max_width
    })
    assert list.length(map.row(m, map.rows)) == 1
    // Ids number the nodes row by row, left to right.
    assert list.map(m.nodes, fn(n) { n.id })
      == int.range(0, list.length(m.nodes), [], list.prepend) |> list.reverse
  })
}

pub fn every_node_has_a_way_in_and_on_test() {
  list.each(maps(), fn(m) {
    let targets = list.map(links(m), fn(link) { { link.1 }.id })
    list.each(m.nodes, fn(n) {
      case n.row {
        0 -> Nil
        _ -> {
          assert list.contains(targets, n.id)
        }
      }
      case n.row == map.rows {
        True -> {
          assert n.next == []
        }
        False -> {
          assert n.next != []
        }
      }
    })
  })
}

pub fn links_go_to_the_next_row_without_crossing_test() {
  list.each(maps(), fn(m) {
    let pairs = links(m)
    list.each(pairs, fn(link) {
      assert { link.1 }.row == { link.0 }.row + 1
    })
    // Two links between the same rows cross when their ends are in
    // opposite orders (ids grow left to right within a row).
    list.each(pairs, fn(a) {
      list.each(pairs, fn(b) {
        assert !{ { a.0 }.id < { b.0 }.id && { a.1 }.id > { b.1 }.id }
      })
    })
  })
}

pub fn events_follow_the_row_rules_test() {
  list.each(maps(), fn(m) {
    list.each(m.nodes, fn(n) {
      case n.row, n.event {
        0, Battle(tier: Normal, ..) -> Nil
        0, _ -> panic as "row 0 must be ordinary enemies"
        1, Battle(tier: map.Strong, ..) -> panic as "no strong enemy in row 1"
        r, RepairShop if r == map.rows - 1 -> Nil
        r, _ if r == map.rows - 1 -> panic as "repair shops before the boss"
        r, Battle(tier: Boss, ..) if r == map.rows -> Nil
        r, _ if r == map.rows -> panic as "the boss row is a boss"
        _, Battle(tier: Boss, ..) -> panic as "a boss before the last row"
        _, _ -> Nil
      }
    })
  })
}

pub fn all_three_event_kinds_appear_in_the_middle_test() {
  let middle =
    list.flat_map(maps(), fn(m) {
      list.filter(m.nodes, fn(n) { n.row >= 2 && n.row < map.rows - 1 })
    })
  let kind = fn(n: map.Node) {
    case n.event {
      Battle(tier:, ..) -> map.tier_name(tier)
      RepairShop -> "shop"
    }
  }
  let kinds = list.unique(list.map(middle, kind))
  assert list.contains(kinds, "enemy")
  assert list.contains(kinds, "strong enemy")
  assert list.contains(kinds, "shop")
}

pub fn maps_are_reproducible_test() {
  assert map.generate(2, rng.new(7)).0 == map.generate(2, rng.new(7)).0
  assert map.generate(2, rng.new(7)).0 != map.generate(2, rng.new(8)).0
}
