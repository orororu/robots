//// The battle screen: both robots, your table of cards, and the log.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/part
import robots/rules/amount
import robots/rules/card
import robots/rules/energy
import robots/rules/game.{type Combatant, type Game}
import robots/rules/scale.{type Scale}
import robots_client/card_view

pub fn view(
  state: Game,
  s: Scale,
  now: Int,
  banner: Element(msg),
  on_play: fn(Int) -> msg,
) -> Element(msg) {
  // Show current values: drones grow between plays.
  let state = game.settle(state, now)
  let available = energy.at(state.p1.energy, now)
  html.div([], [
    html.pre([attribute.class("foe")], [
      element.text(status_panel("ENEMY", state.p2, s, now)),
    ]),
    card_view.row(
      list.map(state.p2.table, fn(slot) {
        card_view.view(
          s,
          slot.card,
          current: slot.value,
          key: None,
          dim: False,
          on_click: None,
        )
      }),
    ),
    html.pre([attribute.class("dim")], [element.text(string.repeat("─", 64))]),
    html.pre([attribute.class("ally")], [
      element.text(status_panel("YOU", state.p1, s, now)),
    ]),
    card_view.row(
      list.index_map(state.p1.table, fn(slot, index) {
        card_view.view(
          s,
          slot.card,
          current: slot.value,
          key: Some(int.to_string(index + 1)),
          dim: !amount.at_least(available, slot.card.cost),
          on_click: Some(on_play(index)),
        )
      }),
    ),
    banner,
    html.pre([attribute.class("dim")], [
      element.text(
        "LOG\n"
        <> state.log
        |> list.map(fn(event) { "  " <> describe_event(state, s, event) })
        |> string.join("\n"),
      ),
    ]),
  ])
}

fn status_panel(label: String, c: Combatant, s: Scale, now: Int) -> String {
  let bot = c.robot
  let current = energy.at(c.energy, now)
  let parts =
    bot.components
    |> list.filter(fn(p) { p.kind != part.Body })
    |> list.map(part.display_name)
  let reserve = case c.reserve {
    [] -> ""
    waiting ->
      "\n  next: " <> string.join(list.map(waiting, fn(r) { r.name }), ", ")
  }
  [
    string.pad_end(label, 7, " ") <> bot.name <> " (" <> bot.chassis <> ")",
    "  HP      "
      <> bar(bot.hp, bot.max_hp, 20)
      <> " "
      <> int.to_string(scale.value(s, bot.hp))
      <> "/"
      <> int.to_string(scale.value(s, bot.max_hp)),
    "  energy  "
      <> bar(current, c.energy.cap, 20)
      <> " "
      <> int.to_string(scale.energy(s, current))
      <> "/"
      <> int.to_string(scale.cost(s, c.energy.cap)),
    "  deck "
      <> int.to_string(list.length(c.deck))
      <> " · discard "
      <> int.to_string(list.length(c.discard))
      <> " · parts: "
      <> string.join(parts, ", ")
      <> reserve,
  ]
  |> string.join("\n")
}

fn describe_event(state: Game, s: Scale, event: game.Event) -> String {
  let name = fn(side) { game.combatant_of(state, side).robot.name }
  case event {
    game.Started -> "Fight!"
    game.Destroyed(side) -> name(side) <> " is destroyed!"
    game.Entered(side: _, robot:) -> robot.name <> " enters the battle!"
    game.DroneHit(side:, drone:, damage:, destroyed:) ->
      "  → hits "
      <> name(side)
      <> "'s "
      <> drone.name
      <> " for "
      <> int.to_string(scale.value(s, damage))
      <> case destroyed {
        True -> ": destroyed!"
        False -> ""
      }
    game.Burned(side:, card: c) ->
      "  → " <> name(side) <> "'s " <> c.name <> " burns up!"
    game.DroneDestroyed(side:, drone:) ->
      "  → " <> name(side) <> "'s " <> drone.name <> " is destroyed!"
    game.Played(side:, card: c, targets:, effect:, ..) -> {
      // The amount actually changed, so wasted extra value isn't shown.
      let shown = int.to_string(scale.value(s, effect))
      name(side)
      <> " plays "
      <> c.name
      <> case c.target, targets {
        card.OpponentHp, _ -> " for " <> shown <> " damage"
        card.Launch(drone), _ -> ": launches a " <> drone.name
        card.NoEffect, _ -> ": does nothing"
        card.Burn(_), 0 -> ": nothing to burn"
        card.Burn(_), _ -> ": sets a card on fire"
        _, 0 -> ": no target"
        card.Opponent(_), n -> ": -" <> shown <> " on " <> cards(n)
        card.Self(_), n -> ": +" <> shown <> " on " <> cards(n)
        card.Both(_), n ->
          ": -" <> shown <> " on " <> cards(n) <> ", both sides"
      }
    }
  }
}

fn cards(n: Int) -> String {
  case n {
    1 -> "1 card"
    _ -> int.to_string(n) <> " cards"
  }
}

pub fn bar(value: Float, max: Float, width: Int) -> String {
  let filled = case max >. 0.0 {
    True ->
      float.truncate(value /. max *. int.to_float(width))
      |> int.clamp(0, width)
    False -> 0
  }
  "[" <> string.repeat("#", filled) <> string.repeat(".", width - filled) <> "]"
}
