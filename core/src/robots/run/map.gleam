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

/// Rows before the boss.
pub const rows = 6

pub const min_width = 2

pub const max_width = 4

/// Chance that a battle in a middle row (from row 2) is a strong enemy, in
/// percent.
pub const strong_percent = 25

/// The rows with repair shops on each level: one along the way, one before
/// the boss. Levels past the list use the last entry. Rows must be between
/// 1 and `rows - 1` and not next to each other.
pub fn shop_rows(level: Int) -> List(Int) {
  case level {
    1 -> [2, 5]
    2 -> [3, 5]
    _ -> [3, 5]
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
}

pub type Node {
  Node(id: Int, row: Int, event: Event, next: List(Int))
}

pub type Map {
  Map(level: Int, nodes: List(Node))
}

pub fn generate(level: Int, seed: Seed) -> #(Map, Seed) {
  let roster = enemies.level(level)
  // Widths per row; the boss row has one node.
  let #(seed, widths) =
    list.map_fold(upto(rows), seed, fn(seed, _) {
      let #(extra, seed) = rng.int_below(seed, max_width - min_width + 1)
      #(seed, min_width + extra)
    })
  let widths = list.append(widths, [1])
  // Node ids, row by row.
  let #(_, ids) =
    list.map_fold(widths, 0, fn(next_id, width) {
      #(next_id + width, list.map(upto(width), fn(i) { next_id + i }))
    })
  let #(seed, links) =
    list.map_fold(list.window_by_2(ids), seed, fn(seed, pair) {
      let #(links, seed) = connect(pair.0, pair.1, [], seed)
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
  let #(seed, nodes) =
    list.index_map(ids, fn(row_ids, row) { #(row, row_ids) })
    |> list.flat_map(fn(pair) { list.map(pair.1, fn(id) { #(pair.0, id) }) })
    |> list.map_fold(seed, fn(seed, pair) {
      let #(row, id) = pair
      let #(event, seed) = case list.contains(shops, id) {
        True -> #(RepairShop, seed)
        False -> battle_at(row, roster, level, seed)
      }
      let next =
        links
        |> list.filter(fn(link) { link.0 == id })
        |> list.map(fn(link) { link.1 })
      #(seed, Node(id:, row:, event:, next:))
    })
  #(Map(level:, nodes:), seed)
}

/// Link two rows without crossings: walk both from the left, linking the
/// current pair, then step one row or both.
fn connect(
  from: List(Int),
  to: List(Int),
  links: List(#(Int, Int)),
  seed: Seed,
) -> #(List(#(Int, Int)), Seed) {
  case from, to {
    [a], [b] -> #(list.reverse([#(a, b), ..links]), seed)
    [a], [b, ..rest] -> connect([a], rest, [#(a, b), ..links], seed)
    [a, ..rest], [b] -> connect(rest, [b], [#(a, b), ..links], seed)
    [a, ..from_rest], [b, ..to_rest] -> {
      let links = [#(a, b), ..links]
      let #(step, seed) = rng.int_below(seed, 3)
      case step {
        0 -> connect(from_rest, to, links, seed)
        1 -> connect(from, to_rest, links, seed)
        _ -> connect(from_rest, to_rest, links, seed)
      }
    }
    _, _ -> #(list.reverse(links), seed)
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
