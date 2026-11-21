//// Text-mode browser client. This is the "imperative shell": it reads the
//// clock and the keyboard, feeds messages into the pure core, and renders.
//// Swapping this text view for sprites later doesn't touch the game rules.

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
import robots/ai
import robots/card.{type Card}
import robots/catalog
import robots/energy
import robots/game.{type Combatant, type Game, P1, P2}
import robots_client/browser

const frame_ms = 50

const ai_think_ms = 1400

const flash_ms = 1500

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(game: Game, brain: ai.Brain, now: Int, flash: String, flash_until: Int)
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
    brain: ai.new(P2, think_ms: ai_think_ms, now:),
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
  Play(index: Int)
  Restart
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let model = case msg {
    Frame(now) -> advance(model, now)
    Play(index) -> play(model, index)
    Restart -> new_match(browser.now())
    KeyDown("r") | KeyDown("R") -> new_match(browser.now())
    KeyDown(key) ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
  }
  #(model, effect.none())
}

/// Let time pass for the core and give the AI a chance to act.
fn advance(model: Model, now: Int) -> Model {
  let state = case game.update(model.game, game.Tick(now)) {
    Ok(state) -> state
    Error(_) -> model.game
  }
  let #(brain, state) = ai.act(model.brain, state, now)
  Model(..model, game: state, brain:, now:)
}

fn play(model: Model, index: Int) -> Model {
  // Use a fresh timestamp: the last frame may be up to 50ms old.
  let model = advance(model, browser.now())
  case game.update(model.game, game.PlayCard(P1, index, model.now)) {
    Ok(state) -> Model(..model, game: state, flash: "")
    Error(rejection) ->
      Model(
        ..model,
        flash: describe_rejection(rejection),
        flash_until: model.now + flash_ms,
      )
  }
}

fn describe_rejection(rejection: game.Rejection) -> String {
  case rejection {
    game.GameOver -> "The match is over. Press R to play again."
    game.NoSuchCard -> "No card in that slot."
    game.NotEnoughEnergy(cost:, available:) ->
      "Not enough energy: need "
      <> int.to_string(cost)
      <> ", have "
      <> one_decimal(available)
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let state = model.game
  let me = state.p1
  let available = energy.at(me.energy, model.now)
  html.div([attribute.class("screen")], [
    html.style([], css),
    html.pre([], [
      element.text("ROBOTS · text mode         [1-5] play card   [R] restart"),
    ]),
    html.pre([attribute.class("foe")], [
      element.text(combatant_panel("ENEMY", state.p2, model.now, True)),
    ]),
    html.pre([attribute.class("dim")], [element.text(string.repeat("─", 60))]),
    html.pre([attribute.class("ally")], [
      element.text(combatant_panel("YOU", me, model.now, False)),
    ]),
    html.div(
      [attribute.class("hand")],
      list.index_map(me.hand, fn(card, index) {
        hand_card(card, index, available)
      }),
    ),
    html.pre([attribute.class("banner")], [element.text(banner(model))]),
    html.pre([attribute.class("dim")], [
      element.text(
        "LOG\n"
        <> state.log |> list.map(fn(line) { "  " <> line }) |> string.join("\n"),
      ),
    ]),
  ])
}

fn combatant_panel(
  label: String,
  c: Combatant,
  now: Int,
  is_enemy: Bool,
) -> String {
  let bot = c.robot
  let current = energy.at(c.energy, now)
  let draw_in = int.max(0, c.next_draw_at - now)
  let parts = bot.components |> list.map(fn(part) { part.name })
  let hand_line = case is_enemy {
    True -> "hand " <> int.to_string(list.length(c.hand)) <> " · "
    False -> ""
  }
  [
    string.pad_end(label, 7, " ") <> bot.name,
    "  HP      "
      <> bar(int.to_float(bot.hp), int.to_float(bot.max_hp), 20)
      <> " "
      <> int.to_string(bot.hp)
      <> "/"
      <> int.to_string(bot.max_hp)
      <> case bot.shield {
      0 -> ""
      s -> "   shield " <> int.to_string(s)
    },
    "  energy  "
      <> bar(current, c.energy.cap, 20)
      <> " "
      <> one_decimal(current)
      <> "/"
      <> int.to_string(float.round(c.energy.cap)),
    "  "
      <> hand_line
      <> "deck "
      <> int.to_string(list.length(c.deck))
      <> " · discard "
      <> int.to_string(list.length(c.discard))
      <> " · next draw "
      <> one_decimal(int.to_float(draw_in) /. 1000.0)
      <> "s",
    "  parts   " <> string.join(parts, ", "),
  ]
  |> string.join("\n")
}

fn hand_card(card: Card, index: Int, available: Float) -> Element(Msg) {
  let affordable = int.to_float(card.cost) <=. available
  let label =
    "["
    <> int.to_string(index + 1)
    <> "] "
    <> string.pad_end(card.name, 9, " ")
    <> " ("
    <> int.to_string(card.cost)
    <> ")  "
    <> card.describe(card)
  html.button(
    [
      attribute.class(case affordable {
        True -> "card"
        False -> "card dim"
      }),
      event.on_click(Play(index)),
    ],
    [element.text(label)],
  )
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
    float.round(value /. max *. int.to_float(width))
    |> int.clamp(0, width)
  "[" <> string.repeat("#", filled) <> string.repeat(".", width - filled) <> "]"
}

fn one_decimal(x: Float) -> String {
  let tenths = float.truncate(x *. 10.0)
  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10)
}

const css =
  "
body { margin: 0; background: #101214; color: #c8d0c8; }
.screen { font-family: ui-monospace, 'JetBrains Mono', Menlo, Consolas, monospace;
  font-size: 15px; max-width: 46rem; margin: 0 auto; padding: 1.5rem 1rem; }
pre { margin: 0 0 0.75rem; white-space: pre-wrap; font: inherit; }
.foe { color: #e08a7a; }
.ally { color: #8fd18f; }
.dim { opacity: 0.45; }
.banner { color: #f0d060; min-height: 1.3em; }
.hand { display: flex; flex-direction: column; gap: 2px; margin-bottom: 0.75rem; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; }
.card:hover { background: #1f2a1f; }
"
