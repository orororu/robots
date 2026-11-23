//// A level's map: a layered graph of events ending in a boss (see
//// docs/RUN.md).
////
//// Nodes sit in rows. The player starts at any node of the first row and
//// each step moves to a node of the next row that the current one links to.
//// Links never cross, every node has a way in and a way on, and every path
//// ends at the boss.
////
//// - Row 0: ordinary enemies, an easy start.
//// - Middle rows: enemies, strong enemies (not before row 2) and repair
////   shops.
//// - The last row before the boss: repair shops.
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

/// Chances for a middle-row node, in percent; the rest are ordinary enemies.
pub const shop_percent = 20

pub const strong_percent = 25

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
  let #(seed, nodes) =
    list.index_map(ids, fn(row_ids, row) { #(row, row_ids) })
    |> list.flat_map(fn(pair) { list.map(pair.1, fn(id) { #(pair.0, id) }) })
    |> list.map_fold(seed, fn(seed, pair) {
      let #(row, id) = pair
      let #(event, seed) = event(row, roster, level, seed)
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

fn event(
  row: Int,
  roster: enemies.Level,
  level: Int,
  seed: Seed,
) -> #(Event, Seed) {
  case row {
    0 -> battle(Normal, roster.enemies, level, seed)
    _ if row == rows -> battle(Boss, [roster.boss], level, seed)
    _ if row == rows - 1 -> #(RepairShop, seed)
    _ -> {
      let #(roll, seed) = rng.int_below(seed, 100)
      case
        roll < shop_percent,
        roll < shop_percent + strong_percent && row >= 2
      {
        True, _ -> #(RepairShop, seed)
        False, True -> battle(Strong, roster.strong, level, seed)
        False, False -> battle(Normal, roster.enemies, level, seed)
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
