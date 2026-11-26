//// A run in progress as text, so the client can keep it in the browser and
//// a reload (or a new build of the game) continues it.
////
//// Parts and chassis are saved by name with what the run did to them
//// (wear, modifiers, attributes); their cards and stats come from the
//// content when loading, so balance changes apply to saved runs too. A run
//// naming something no longer in the game doesn't load.
////
//// The format is a small tree: `(…)` lists, `"…"` strings, numbers.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robots/construction/attribute.{type Attribute}
import robots/construction/builder.{type Chassis, Chassis}
import robots/construction/part.{type Component, type Modifier, Component}
import robots/content/components
import robots/content/enemies.{type Enemy, Enemy}
import robots/meta/blueprint.{
  type Blueprint, ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/rules/rng
import robots/run/map.{type Map, type Node, type Tier, Map, Node}
import robots/run/shop.{type Shop, Offer, Shop}
import robots/run/state.{type Bot, type Phase, type Run, Bot, Run}

pub fn encode(run: Run) -> String {
  run_data(run) |> write
}

/// A saved run; one in another format doesn't load.
pub fn decode(text: String) -> Result(Run, Nil) {
  read(text) |> result.try(to_run)
}

// THE TREE --------------------------------------------------------------------

type Data {
  L(List(Data))
  S(String)
  I(Int)
  F(Float)
}

fn write(data: Data) -> String {
  case data {
    L(items) -> "(" <> string.join(list.map(items, write), " ") <> ")"
    S(s) ->
      "\""
      <> s |> string.replace("\\", "\\\\") |> string.replace("\"", "\\\"")
      <> "\""
    I(n) -> int.to_string(n)
    F(x) -> "~" <> float.to_string(x)
  }
}

fn read(text: String) -> Result(Data, Nil) {
  case parse(string.to_graphemes(text)) {
    Ok(#(data, rest)) ->
      case skip(rest) {
        [] -> Ok(data)
        _ -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn skip(chars: List(String)) -> List(String) {
  case chars {
    [" ", ..rest] | ["\n", ..rest] -> skip(rest)
    _ -> chars
  }
}

fn parse(chars: List(String)) -> Result(#(Data, List(String)), Nil) {
  case skip(chars) {
    ["(", ..rest] -> parse_list(rest, [])
    ["\"", ..rest] -> parse_string(rest, [])
    ["~", ..rest] -> {
      let #(token, rest) = take_token(rest, [])
      float.parse(token)
      |> result.lazy_or(fn() { int.parse(token) |> result.map(int.to_float) })
      |> result.map(fn(x) { #(F(x), rest) })
    }
    [_, ..] as rest -> {
      let #(token, rest) = take_token(rest, [])
      int.parse(token) |> result.map(fn(n) { #(I(n), rest) })
    }
    [] -> Error(Nil)
  }
}

fn parse_list(
  chars: List(String),
  items: List(Data),
) -> Result(#(Data, List(String)), Nil) {
  case skip(chars) {
    [")", ..rest] -> Ok(#(L(list.reverse(items)), rest))
    [] -> Error(Nil)
    rest -> {
      use #(item, rest) <- result.try(parse(rest))
      parse_list(rest, [item, ..items])
    }
  }
}

fn parse_string(
  chars: List(String),
  acc: List(String),
) -> Result(#(Data, List(String)), Nil) {
  case chars {
    ["\\", c, ..rest] -> parse_string(rest, [c, ..acc])
    ["\"", ..rest] -> Ok(#(S(string.concat(list.reverse(acc))), rest))
    [c, ..rest] -> parse_string(rest, [c, ..acc])
    [] -> Error(Nil)
  }
}

fn take_token(
  chars: List(String),
  acc: List(String),
) -> #(String, List(String)) {
  case chars {
    [c, ..rest] if c != " " && c != ")" && c != "(" && c != "\n" ->
      take_token(rest, [c, ..acc])
    _ -> #(string.concat(list.reverse(acc)), chars)
  }
}

// ENCODING --------------------------------------------------------------------

fn run_data(run: Run) -> Data {
  L([
    I(run.level),
    map_data(run.map),
    option_data(run.at, I),
    L(list.map(run.path, I)),
    phase_data(run.phase),
    L(list.map(run.robots, bot_data)),
    L(list.map(run.parts, component_data)),
    L(list.map(run.chassis, chassis_data)),
    I(run.money),
    shop_data(run.shop),
    I(run.truck),
    I(run.fabricator),
    L(list.map(run.wins, fn(t) { S(map.tier_name(t)) })),
    L(list.map(run.found, blueprint_data)),
    I(rng.to_state(run.seed)),
  ])
}

fn option_data(o: Option(a), f: fn(a) -> Data) -> Data {
  case o {
    Some(x) -> L([f(x)])
    None -> L([])
  }
}

fn map_data(m: Map) -> Data {
  L([I(m.level), L(list.map(m.nodes, node_data))])
}

fn node_data(n: Node) -> Data {
  let event = case n.event {
    map.Battle(tier:, enemy:) ->
      L([S("battle"), S(map.tier_name(tier)), enemy_data(enemy)])
    map.RepairShop -> L([S("shop")])
    map.Workshop -> L([S("workshop")])
  }
  L([I(n.id), I(n.row), event, L(list.map(n.next, I))])
}

fn enemy_data(e: Enemy) -> Data {
  L([
    S(e.name),
    S(e.description),
    chassis_data(e.chassis),
    L(list.map(e.parts, component_data)),
  ])
}

fn phase_data(p: Phase) -> Data {
  case p {
    state.Choosing -> L([S("choosing")])
    state.Fighting(node) -> L([S("fighting"), I(node)])
    state.Repairing(node) -> L([S("repairing"), I(node)])
    state.Upgrading(node) -> L([S("upgrading"), I(node)])
    state.Over -> L([S("over")])
  }
}

fn bot_data(b: Bot) -> Data {
  L([S(b.name), chassis_data(b.chassis), L(list.map(b.parts, component_data))])
}

fn chassis_data(c: Chassis) -> Data {
  L([S(c.name), F(c.wear)])
}

fn component_data(c: Component) -> Data {
  L([
    S(c.name),
    F(c.wear),
    L(list.map(c.modifiers, modifier_data)),
    L(list.map(c.attributes, fn(pair) { L([I(pair.0), S({ pair.1 }.name)]) })),
  ])
}

fn modifier_data(m: Modifier) -> Data {
  case m {
    part.Light(weight:) -> L([S("light"), F(weight)])
    part.Overclocked(value:) -> L([S("overclocked"), F(value)])
  }
}

fn shop_data(s: Shop) -> Data {
  L([
    L(list.map(s.parts, component_data)),
    L(
      list.map(s.robots, fn(o) {
        L([
          S(o.name),
          chassis_data(o.chassis),
          L(list.map(o.parts, component_data)),
        ])
      }),
    ),
  ])
}

fn blueprint_data(b: Blueprint) -> Data {
  case b {
    PartBlueprint(p) -> L([S("part"), component_data(p)])
    ChassisBlueprint(name) -> L([S("chassis"), S(name)])
    FabricatorBlueprint -> L([S("fabricator")])
  }
}

// DECODING --------------------------------------------------------------------

fn to_run(d: Data) -> Result(Run, Nil) {
  case d {
    L([
      I(level),
      m,
      at,
      L(path),
      phase,
      L(robots),
      L(parts),
      L(chassis),
      I(money),
      shop,
      I(truck),
      I(fabricator),
      L(wins),
      L(found),
      I(seed),
    ]) -> {
      use map <- result.try(to_map(m))
      use at <- result.try(to_option(at, to_int))
      use path <- result.try(list.try_map(path, to_int))
      use phase <- result.try(to_phase(phase))
      use robots <- result.try(list.try_map(robots, to_bot))
      use parts <- result.try(list.try_map(parts, to_component))
      use chassis <- result.try(list.try_map(chassis, to_chassis))
      use shop <- result.try(to_shop(shop))
      use wins <- result.try(list.try_map(wins, to_tier))
      use found <- result.try(list.try_map(found, to_blueprint))
      Ok(Run(
        level:,
        map:,
        at:,
        path:,
        phase:,
        robots:,
        parts:,
        chassis:,
        money:,
        shop:,
        truck:,
        fabricator:,
        wins:,
        found:,
        seed: rng.from_state(seed),
      ))
    }
    _ -> Error(Nil)
  }
}

fn to_int(d: Data) -> Result(Int, Nil) {
  case d {
    I(n) -> Ok(n)
    _ -> Error(Nil)
  }
}

fn to_float(d: Data) -> Result(Float, Nil) {
  case d {
    F(x) -> Ok(x)
    I(n) -> Ok(int.to_float(n))
    _ -> Error(Nil)
  }
}

fn to_option(d: Data, f: fn(Data) -> Result(a, Nil)) -> Result(Option(a), Nil) {
  case d {
    L([]) -> Ok(None)
    L([x]) -> f(x) |> result.map(Some)
    _ -> Error(Nil)
  }
}

fn to_map(d: Data) -> Result(Map, Nil) {
  case d {
    L([I(level), L(nodes)]) ->
      list.try_map(nodes, to_node)
      |> result.map(fn(nodes) { Map(level:, nodes:) })
    _ -> Error(Nil)
  }
}

fn to_node(d: Data) -> Result(Node, Nil) {
  case d {
    L([I(id), I(row), event, L(next)]) -> {
      use event <- result.try(case event {
        L([S("battle"), tier, enemy]) -> {
          use tier <- result.try(to_tier(tier))
          use enemy <- result.try(to_enemy(enemy))
          Ok(map.Battle(tier:, enemy:))
        }
        L([S("shop")]) -> Ok(map.RepairShop)
        L([S("workshop")]) -> Ok(map.Workshop)
        _ -> Error(Nil)
      })
      use next <- result.try(list.try_map(next, to_int))
      Ok(Node(id:, row:, event:, next:))
    }
    _ -> Error(Nil)
  }
}

fn to_tier(d: Data) -> Result(Tier, Nil) {
  list.find([map.Normal, map.Strong, map.Boss], fn(t) {
    d == S(map.tier_name(t))
  })
}

fn to_enemy(d: Data) -> Result(Enemy, Nil) {
  case d {
    L([S(name), S(description), chassis, L(parts)]) -> {
      use chassis <- result.try(to_chassis(chassis))
      use parts <- result.try(list.try_map(parts, to_component))
      Ok(Enemy(name:, description:, chassis:, parts:))
    }
    _ -> Error(Nil)
  }
}

fn to_phase(d: Data) -> Result(Phase, Nil) {
  case d {
    L([S("choosing")]) -> Ok(state.Choosing)
    L([S("fighting"), I(node)]) -> Ok(state.Fighting(node))
    L([S("repairing"), I(node)]) -> Ok(state.Repairing(node))
    L([S("upgrading"), I(node)]) -> Ok(state.Upgrading(node))
    L([S("over")]) -> Ok(state.Over)
    _ -> Error(Nil)
  }
}

fn to_bot(d: Data) -> Result(Bot, Nil) {
  case d {
    L([S(name), chassis, L(parts)]) -> {
      use chassis <- result.try(to_chassis(chassis))
      use parts <- result.try(list.try_map(parts, to_component))
      Ok(Bot(name:, chassis:, parts:))
    }
    _ -> Error(Nil)
  }
}

fn to_chassis(d: Data) -> Result(Chassis, Nil) {
  case d {
    L([S(name), wear]) -> {
      use wear <- result.try(to_float(wear))
      use base <- result.try(
        list.find(known_chassis(), fn(c) { c.name == name }),
      )
      Ok(Chassis(..base, wear:))
    }
    _ -> Error(Nil)
  }
}

fn to_component(d: Data) -> Result(Component, Nil) {
  case d {
    L([S(name), wear, L(modifiers), L(attributes)]) -> {
      use wear <- result.try(to_float(wear))
      use modifiers <- result.try(list.try_map(modifiers, to_modifier))
      use attributes <- result.try(list.try_map(attributes, to_attribute))
      use base <- result.try(list.find(known_parts(), fn(p) { p.name == name }))
      Ok(Component(..base, wear:, modifiers:, attributes:))
    }
    _ -> Error(Nil)
  }
}

/// Every part in the game: the content's, and the few only enemies carry
/// (the Compactor's Crusher plate).
fn known_parts() -> List(Component) {
  list.append(components.all(), list.flat_map(roster(), fn(e) { e.parts }))
}

fn known_chassis() -> List(Chassis) {
  list.append(components.chassis(), list.map(roster(), fn(e) { e.chassis }))
}

fn roster() -> List(Enemy) {
  list.flat_map(enemies.levels(), fn(l) {
    list.flatten([l.enemies, l.strong, [l.boss]])
  })
}

fn to_modifier(d: Data) -> Result(Modifier, Nil) {
  case d {
    L([S("light"), x]) -> to_float(x) |> result.map(part.Light)
    L([S("overclocked"), x]) -> to_float(x) |> result.map(part.Overclocked)
    _ -> Error(Nil)
  }
}

fn to_attribute(d: Data) -> Result(#(Int, Attribute), Nil) {
  case d {
    L([I(index), S(name)]) ->
      list.find(attribute.all(), fn(a) { a.name == name })
      |> result.map(fn(a) { #(index, a) })
    _ -> Error(Nil)
  }
}

fn to_shop(d: Data) -> Result(Shop, Nil) {
  case d {
    L([L(parts), L(robots)]) -> {
      use parts <- result.try(list.try_map(parts, to_component))
      use robots <- result.try(
        list.try_map(robots, fn(o) {
          case o {
            L([S(name), chassis, L(parts)]) -> {
              use chassis <- result.try(to_chassis(chassis))
              use parts <- result.try(list.try_map(parts, to_component))
              Ok(Offer(name:, chassis:, parts:))
            }
            _ -> Error(Nil)
          }
        }),
      )
      Ok(Shop(parts:, robots:))
    }
    _ -> Error(Nil)
  }
}

fn to_blueprint(d: Data) -> Result(Blueprint, Nil) {
  case d {
    L([S("part"), p]) -> to_component(p) |> result.map(PartBlueprint)
    L([S("chassis"), S(name)]) -> Ok(ChassisBlueprint(name))
    L([S("fabricator")]) -> Ok(FabricatorBlueprint)
    _ -> Error(Nil)
  }
}
