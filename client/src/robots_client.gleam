//// Text-mode browser client. This is the "imperative shell": it reads the
//// clock and the keyboard, feeds messages into the pure core, and renders.
//// Swapping this text view for sprites later doesn't touch the game rules.
////
//// The core works in relative amounts (1.0 = base). Every number shown here
//// goes through `robots/rules/scale`, so the whole game can be rescaled in one place.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import robots/ai/brain
import robots/rules/amount
import robots/rules/card.{type Card}
import robots/content/catalog
import robots/rules/energy
import robots/rules/game.{type Combatant, type Game, P1, P2}
import robots/construction/part
import robots/rules/scale.{type Scale}
import robots/rules/table.{type Slot}
import robots_client/browser

const frame_ms = 50

const flash_ms = 1500

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    game: Game,
    brain: brain.Brain,
    scale: Scale,
    now: Int,
    flash: String,
    flash_until: Int,
  )
}

fn new_match(now: Int) -> Model {
  let state =
    game.new(
      game.default_config(),
      p1: catalog.tinker(),
      p2: catalog.scrapper(),
      seed: browser.random_seed(),
      now:,
    )
  Model(
    game: state,
    brain: brain.new(P2, reaction: brain.human, seed: browser.random_seed()),
    scale: scale.default(),
    now:,
    flash: "",
    flash_until: 0,
  )
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let subscriptions =
    effect.from(fn(dispatch) {
      browser.every(frame_ms, fn() { dispatch(Frame(browser.now())) })
      browser.on_keydown(fn(key) { dispatch(KeyDown(key)) })
    })
  #(new_match(browser.now()), subscriptions)
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  Play(slot: Int)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let model = case msg {
    Frame(now) -> advance(model, now)
    Play(slot) -> play(model, slot)
    KeyDown("r") | KeyDown("R") -> new_match(browser.now())
    KeyDown(key) ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
  }
  #(model, effect.none())
}

/// Let time pass and give the AI a chance to act.
fn advance(model: Model, now: Int) -> Model {
  let #(brain, state) = brain.act(model.brain, model.game, now)
  Model(..model, game: state, brain:, now:)
}

fn play(model: Model, slot: Int) -> Model {
  // Use a fresh timestamp: the last frame may be up to 50ms old.
  let model = advance(model, browser.now())
  case game.update(model.game, game.PlayCard(P1, slot, model.now)) {
    Ok(state) -> Model(..model, game: state, flash: "")
    Error(rejection) ->
      Model(
        ..model,
        flash: describe_rejection(model.scale, rejection),
        flash_until: model.now + flash_ms,
      )
  }
}

fn describe_rejection(s: Scale, rejection: game.Rejection) -> String {
  case rejection {
    game.GameOver -> "The match is over. Press R to play again."
    game.NoSuchCard -> "No card in that slot."
    game.NotEnoughEnergy(cost:, available:) ->
      "Not enough energy: need "
      <> int.to_string(scale.cost(s, cost))
      <> ", have "
      <> int.to_string(scale.energy(s, available))
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  // Show current values: drones grow between plays.
  let state = game.settle(model.game, model.now)
  let s = model.scale
  let available = energy.at(state.p1.energy, model.now)
  html.div([attribute.class("screen")], [
    html.style([], css),
    html.pre([], [
      element.text("ROBOTS · text mode          [1-4] play card   [R] restart"),
    ]),
    html.pre([attribute.class("foe")], [
      element.text(
        status_panel("ENEMY", state.p2, s, model.now)
        <> "\n"
        <> {
          state.p2.table
          |> list.map(fn(slot) { "      " <> slot_text(s, slot) })
          |> string.join("\n")
        },
      ),
    ]),
    html.pre([attribute.class("dim")], [element.text(string.repeat("─", 64))]),
    html.pre([attribute.class("ally")], [
      element.text(status_panel("YOU", state.p1, s, model.now)),
    ]),
    html.div(
      [attribute.class("table")],
      list.index_map(state.p1.table, fn(slot, index) {
        table_card(s, slot, index, available)
      }),
    ),
    html.pre([attribute.class("banner")], [element.text(banner(model))]),
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
      <> string.join(parts, ", "),
  ]
  |> string.join("\n")
}

fn table_card(
  s: Scale,
  slot: Slot,
  index: Int,
  available: Float,
) -> Element(Msg) {
  let affordable = amount.at_least(available, slot.card.cost)
  html.button(
    [
      attribute.class(case affordable {
        True -> "card"
        False -> "card dim"
      }),
      event.on_click(Play(index)),
    ],
    [
      element.text(
        "[" <> int.to_string(index + 1) <> "] " <> slot_text(s, slot),
      ),
    ],
  )
}

/// "Laser          3 (10)  cost 10  [attack,range,beam]"
fn slot_text(s: Scale, slot: Slot) -> String {
  let card = slot.card
  let shown = scale.value(s, slot.value)
  let printed = scale.value(s, card.value)
  let value = case shown == printed {
    True -> int.to_string(shown)
    False -> int.to_string(shown) <> " (" <> int.to_string(printed) <> ")"
  }
  string.pad_end(card.name, 14, " ")
  <> string.pad_end(value, 9, " ")
  <> "cost "
  <> string.pad_end(int.to_string(scale.cost(s, card.cost)), 4, " ")
  <> card.tags_text(card.tags)
  <> case card.has_trait(card, card.Once) {
    True -> " once"
    False -> ""
  }
  <> case card.growth(card) {
    Ok(#(_, cap)) -> " grows to " <> int.to_string(scale.value(s, cap))
    Error(Nil) -> ""
  }
  <> "  → "
  <> target_text(card)
}

/// "foe hp", "foe one [attack,melee]", "self all [attack]", ...
fn target_text(c: Card) -> String {
  case c.target {
    card.OpponentHp -> "foe hp"
    card.Opponent(scope) -> "foe " <> scope_text(scope)
    card.Self(scope) -> "self " <> scope_text(scope)
    card.Both(scope) -> "both " <> scope_text(scope)
    card.Burn(_) -> "burn a foe card at 0"
    card.NoEffect -> "nothing"
    card.Launch(drone) -> "launch " <> drone.name
  }
}

fn scope_text(scope: card.Scope) -> String {
  case scope {
    card.One(tags) -> "one " <> card.tags_text(tags)
    card.All(tags) -> "all " <> card.tags_text(tags)
  }
}

fn describe_event(state: Game, s: Scale, event: game.Event) -> String {
  let name = fn(side) { game.combatant_of(state, side).robot.name }
  case event {
    game.Started -> "Fight!"
    game.Destroyed(side) -> name(side) <> " is destroyed!"
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
        card.Both(_), n -> ": -" <> shown <> " on " <> cards(n) <> ", both sides"
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

fn banner(model: Model) -> String {
  case model.game.status {
    game.Won(P1) -> ">>> VICTORY! Press R to play again."
    game.Won(P2) -> ">>> DEFEAT. Press R to try again."
    game.Running ->
      case model.now < model.flash_until {
        True -> "! " <> model.flash
        False -> ""
      }
  }
}

fn bar(value: Float, max: Float, width: Int) -> String {
  let filled =
    float.truncate(value /. max *. int.to_float(width))
    |> int.clamp(0, width)
  "[" <> string.repeat("#", filled) <> string.repeat(".", width - filled) <> "]"
}

const css =
  "
body { margin: 0; background: #101214; color: #c8d0c8; }
.screen { font-family: ui-monospace, 'JetBrains Mono', Menlo, Consolas, monospace;
  font-size: 15px; max-width: 52rem; margin: 0 auto; padding: 1.5rem 1rem; }
pre { margin: 0 0 0.75rem; white-space: pre-wrap; font: inherit; }
.foe { color: #e08a7a; }
.ally { color: #8fd18f; }
.dim { opacity: 0.45; }
.banner { color: #f0d060; min-height: 1.3em; }
.table { display: flex; flex-direction: column; gap: 2px; margin-bottom: 0.75rem; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; white-space: pre; }
.card:hover { background: #1f2a1f; }
"
