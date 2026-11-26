//// A level's map: a layered graph of events ending in a boss (see
//// docs/RUN.md).
////
//// Nodes sit in rows. The player starts at any node of the first row and
//// each step moves to a node of the next row that the current one links to.
//// Links never cross, every node has a way in and a way on, and every path
//// ends at the boss.
////
//// Terms: a **level** is one whole map (a run goes level 1, 2, 3...); a
//// node's **row** is how deep it is in its map: row 0 is the start, row
//// `rows` the boss.
////
//// - Row 0: ordinary enemies, an easy start.
//// - Middle rows: enemies and strong enemies (not before row 2).
//// - Repair shops only on the level's `shop_rows`: on each, one or more
////   nodes are shops, but never all of them, so some branches pass by
////   with a battle. Shop rows aren't next to each other, so two shops
////   never follow one another.
//// - One workshop (upgrade a component) on each of the level's
////   `workshop_rows`, never the whole row.
//// - Then the boss, alone in its row.
////
//// Enemies are spawned when the map is made, so the map can show who waits
//// where. Their condition (`enemies.conditions`) is a step per level, plus
//// one for a strong enemy and two for a boss: level 1's ordinary enemies
//// are the most worn down.

import gleam/int
import gleam/list
import robots/content/enemies.{type Enemy}
import robots/rules/rng.{type Seed}

/// Rows before the boss. Twice the first maps' 6, which were short enough
/// for a tutorial level but over too soon for a real one.
pub const rows = 12

pub const min_width = 2

pub const max_width = 4

/// Chance that a battle in a middle row (from row 2) is a strong enemy, in
/// percent.
pub const strong_percent = 25

/// The rows with repair shops on each level: every third row along the
/// way, and one before the boss, so no path goes more than two battles
/// without passing a shop row. Levels past the list use the last entry. Rows
/// must be between 1 and `rows - 1` and not next to each other.
pub fn shop_rows(level: Int) -> List(Int) {
  case level {
    1 -> [2, 5, 8, 11]
    _ -> [3, 6, 9, 11]
  }
}

/// The rows with a workshop on each level: one node each. Not shop rows.
pub fn workshop_rows(level: Int) -> List(Int) {
  case level {
    1 -> [4, 7]
    _ -> [4, 8]
  }
}

pub type Tier {
  Normal
  Strong
  Boss
}

pub type Event {
  Battle(tier: Tier, enemy: Enemy)
  RepairShop
  /// Upgrade one component, once (see `run/upgrade`).
  Workshop
}

pub type Node {
  Node(id: Int, row: Int, event: Event, next: List(Int))
}

pub type Map {
  Map(level: Int, nodes: List(Node))
}

pub fn generate(level: Int, seed: Seed) -> #(Map, Seed) {
  let roster = enemies.level(level)
  // Widths per row: a random start, then mostly the same as the row before
  // (lanes go straight on); otherwise one lane more (a split) or fewer
  // (two rejoin), within `min_width`..`max_width`. The boss row has one
  // node.
  let #(start, seed) = rng.int_below(seed, max_width - min_width + 1)
  let #(_, widths) =
    list.map_fold(upto(rows), #(min_width + start, seed), fn(acc, row) {
      let #(width, seed) = acc
      let #(roll, seed) = rng.int_below(seed, 100)
      let width = case row > 0 && roll < change_percent, roll % 2 {
        False, _ -> width
        True, 0 if width < max_width -> width + 1
        True, _ if width > min_width -> width - 1
        True, _ -> width + 1
      }
      #(#(width, seed), width)
    })
  let seed = rng.next(seed).1
  let widths = list.append(widths, [1])
  // Node ids, row by row.
  let #(_, ids) =
    list.map_fold(widths, 0, fn(next_id, width) {
      #(next_id + width, list.map(upto(width), fn(i) { next_id + i }))
    })
  let #(seed, links) =
    list.map_fold(list.window_by_2(ids), seed, fn(seed, pair) {
      let #(links, seed) = connect(pair.0, pair.1, [], seed)
      let #(links, seed) = cross_over(pair.0, pair.1, links, seed)
      #(seed, links)
    })
  let links = list.flatten(links)
  // On each shop row, 1 to all-but-one of its nodes are shops.
  let #(seed, shops) =
    list.index_map(ids, fn(row_ids, row) { #(row, row_ids) })
    |> list.filter(fn(pair) { list.contains(shop_rows(level), pair.0) })
    |> list.map_fold(seed, fn(seed, pair) {
      let row_ids = pair.1
      let #(extra, seed) = rng.int_below(seed, list.length(row_ids) - 1)
      let #(shuffled, seed) = rng.shuffle(row_ids, seed)
      #(seed, list.take(shuffled, 1 + extra))
    })
  let shops = list.flatten(shops)
  // One workshop on each workshop row.
  let #(seed, workshops) =
    list.index_map(ids, fn(row_ids, row) { #(row, row_ids) })
    |> list.filter(fn(pair) { list.contains(workshop_rows(level), pair.0) })
    |> list.map_fold(seed, fn(seed, pair) {
      let #(i, seed) = rng.int_below(seed, list.length(pair.1))
      #(seed, list.drop(pair.1, i) |> list.take(1))
    })
  let workshops = list.flatten(workshops)
  let #(seed, nodes) =
    list.index_map(ids, fn(row_ids, row) { #(row, row_ids) })
    |> list.flat_map(fn(pair) { list.map(pair.1, fn(id) { #(pair.0, id) }) })
    |> list.map_fold(seed, fn(seed, pair) {
      let #(row, id) = pair
      let #(event, seed) = case
        list.contains(shops, id),
        list.contains(workshops, id)
      {
        True, _ -> #(RepairShop, seed)
        _, True -> #(Workshop, seed)
        _, _ -> battle_at(row, roster, level, seed)
      }
      let next =
        links
        |> list.filter(fn(link) { link.0 == id })
        |> list.map(fn(link) { link.1 })
      #(seed, Node(id:, row:, event:, next:))
    })
  #(Map(level:, nodes:), seed)
}

/// Percent chance that a row has a different number of lanes than the one
/// before: one splits in two, or two rejoin. Otherwise every lane goes
/// straight on, so branches stay apart for a few rows.
pub const change_percent = 50

/// Link two rows without crossings. Every lane merges into the boss. On
/// other rows of the same width each node goes straight on; into a wider
/// row a random node splits, into a narrower one neighbouring nodes rejoin.
fn connect(
  from: List(Int),
  to: List(Int),
  links: List(#(Int, Int)),
  seed: Seed,
) -> #(List(#(Int, Int)), Seed) {
  let widths = #(list.length(from), list.length(to))
  case to {
    [boss] -> #(list.map(from, fn(a) { #(a, boss) }), seed)
    _ if widths.1 >= widths.0 -> {
      // Each node leads to 1 node, plus the splits.
      let #(counts, seed) = spread(widths.0, widths.1 - widths.0, seed)
      let pairs =
        group(to, counts)
        |> list.zip(from, _)
        |> list.flat_map(fn(pair) { list.map(pair.1, fn(b) { #(pair.0, b) }) })
      #(list.append(links, pairs), seed)
    }
    _ -> {
      // Each node is reached from 1 node, plus the ones rejoining.
      let #(counts, seed) = spread(widths.1, widths.0 - widths.1, seed)
      let pairs =
        group(from, counts)
        |> list.zip(to, _)
        |> list.flat_map(fn(pair) { list.map(pair.1, fn(a) { #(a, pair.0) }) })
      #(list.append(links, pairs), seed)
    }
  }
}

/// Percent chance that, between two rows, one lane also links to its
/// neighbour's next node: a split and a rejoin at once, so paths keep
/// weaving instead of running in columns.
pub const cross_percent = 60

/// Maybe add one diagonal link from a random node to the next-row node
/// beside its targets, if it crosses no other link.
fn cross_over(
  from: List(Int),
  to: List(Int),
  links: List(#(Int, Int)),
  seed: Seed,
) -> #(List(#(Int, Int)), Seed) {
  let #(roll, seed) = rng.int_below(seed, 100)
  let #(i, seed) = rng.int_below(seed, list.length(from))
  let #(side, seed) = rng.int_below(seed, 2)
  let assert Ok(a) = list.drop(from, i) |> list.first
  let targets =
    list.filter_map(links, fn(l) {
      case l.0 == a {
        True -> Ok(l.1)
        False -> Error(Nil)
      }
    })
  let candidate = case side {
    0 -> list.fold(targets, a, int.max) + 1
    _ -> list.fold(targets, list.fold(to, 0, int.max), int.min) - 1
  }
  let crosses = fn(l: #(Int, Int)) {
    { l.0 < a && l.1 > candidate } || { l.0 > a && l.1 < candidate }
  }
  case
    roll < cross_percent && list.contains(to, candidate),
    list.contains(links, #(a, candidate)) || list.any(links, crosses)
  {
    True, False -> #(list.append(links, [#(a, candidate)]), seed)
    _, _ -> #(links, seed)
  }
}

/// `n` counts of 1, with `extra` more added at random places.
fn spread(n: Int, extra: Int, seed: Seed) -> #(List(Int), Seed) {
  list.fold(upto(extra), #(list.repeat(1, n), seed), fn(acc, _) {
    let #(counts, seed) = acc
    let #(i, seed) = rng.int_below(seed, n)
    let counts =
      list.index_map(counts, fn(c, j) {
        case i == j {
          True -> c + 1
          False -> c
        }
      })
    #(counts, seed)
  })
}

/// `items` cut into consecutive groups of these sizes.
fn group(items: List(a), sizes: List(Int)) -> List(List(a)) {
  case sizes {
    [] -> []
    [size, ..rest] -> [
      list.take(items, size),
      ..group(list.drop(items, size), rest)
    ]
  }
}

/// The battle on a node that isn't a shop.
fn battle_at(
  row: Int,
  roster: enemies.Level,
  level: Int,
  seed: Seed,
) -> #(Event, Seed) {
  case row {
    0 -> battle(Normal, roster.enemies, level, seed)
    _ if row == rows -> battle(Boss, [roster.boss], level, seed)
    _ -> {
      let #(roll, seed) = rng.int_below(seed, 100)
      case roll < strong_percent && row >= 2 {
        True -> battle(Strong, roster.strong, level, seed)
        False -> battle(Normal, roster.enemies, level, seed)
      }
    }
  }
}

fn battle(
  tier: Tier,
  options: List(Enemy),
  level: Int,
  seed: Seed,
) -> #(Event, Seed) {
  let #(i, seed) = rng.int_below(seed, list.length(options))
  let assert [enemy, ..] = list.drop(options, i)
  let #(enemy, seed) = enemies.spawn(enemy, level, condition(level, tier), seed)
  #(Battle(tier:, enemy:), seed)
}

/// The enemy's condition step (see `enemies.conditions`).
pub fn condition(level: Int, tier: Tier) -> Int {
  level
  - 1
  + case tier {
    Normal -> 0
    Strong -> 1
    Boss -> 2
  }
}

// QUERIES ---------------------------------------------------------------------

pub fn node(map: Map, id: Int) -> Result(Node, Nil) {
  list.find(map.nodes, fn(n) { n.id == id })
}

/// The nodes of one row, left to right.
pub fn row(map: Map, row: Int) -> List(Node) {
  list.filter(map.nodes, fn(n) { n.row == row })
}

/// Where a level starts: any node of the first row.
pub fn start(map: Map) -> List(Node) {
  row(map, 0)
}

/// The nodes a node links to.
pub fn next(map: Map, from: Node) -> List(Node) {
  list.filter_map(from.next, node(map, _))
}

/// Every node that can still be reached from `from` (including them).
pub fn reachable(map: Map, from: List(Node)) -> List(Int) {
  reach(map, list.map(from, fn(n) { n.id }), [])
}

fn reach(map: Map, queue: List(Int), seen: List(Int)) -> List(Int) {
  case queue {
    [] -> list.reverse(seen)
    [id, ..rest] ->
      case list.contains(seen, id) {
        True -> reach(map, rest, seen)
        False -> {
          let next = case node(map, id) {
            Ok(n) -> n.next
            Error(Nil) -> []
          }
          reach(map, list.append(rest, next), [id, ..seen])
        }
      }
  }
}

pub fn tier_name(tier: Tier) -> String {
  case tier {
    Normal -> "enemy"
    Strong -> "strong enemy"
    Boss -> "boss"
  }
}

fn upto(n: Int) -> List(Int) {
  int.range(0, n, [], list.prepend) |> list.reverse
}
