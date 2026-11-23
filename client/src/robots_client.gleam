//// Text-mode browser client. This is the "imperative shell": it reads the
//// clock and the keyboard, feeds messages into the pure core, and renders.
//// Swapping this text view for sprites later doesn't touch the game rules.
////
//// A run (`robots/run/state`) drives the screens: the map with the garage,
//// the enemy and battle order before a battle, the battle, the repair shop,
//// and the end of the run.
////
//// The core works in relative amounts (1.0 = base). Every number shown here
//// goes through `robots/rules/scale`, so the whole game can be rescaled in one place.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import robots/ai/brain
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/construction/wear
import robots/content/enemies
import robots/rules/game.{type Game, P1, P2}
import robots/rules/scale.{type Scale}
import robots/run/map
import robots/run/price
import robots/run/state.{type Bot, type Run}
import robots_client/battle_view
import robots_client/browser

const frame_ms = 50

const flash_ms = 2500

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    run: Run,
    /// The battle being fought, if any.
    battle: Option(Battle),
    /// Battle order for the next battle: indexes into `run.robots`.
    order: List(Int),
    /// What's selected in the garage.
    pick: Pick,
    /// What the last battle paid, shown on the map.
    news: String,
    scale: Scale,
    now: Int,
    flash: String,
    flash_until: Int,
  )
}

type Battle {
  Battle(game: Game, brain: brain.Brain, order: List(Int))
}

type Pick {
  NoPick
  /// A robot: clicking a spare part installs it there.
  PickedRobot(robot: Int)
  /// An installed part: clicking a spare swaps it in; or remove it.
  PickedPart(robot: Int, part: Int)
  /// A spare chassis and the spare parts chosen for a new robot.
  Draft(chassis: Int, parts: List(Int))
}

fn new_run(now: Int) -> Model {
  let run = state.new(browser.random_seed())
  Model(
    run:,
    battle: None,
    order: default_order(run),
    pick: NoPick,
    news: "A new run. Pick where to go.",
    scale: scale.default(),
    now:,
    flash: "",
    flash_until: 0,
  )
}

fn default_order(run: Run) -> List(Int) {
  int.range(0, list.length(run.robots), [], list.prepend) |> list.reverse
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let subscriptions =
    effect.from(fn(dispatch) {
      browser.every(frame_ms, fn() { dispatch(Frame(browser.now())) })
      browser.on_keydown(fn(key) { dispatch(KeyDown(key)) })
    })
  #(new_run(browser.now()), subscriptions)
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  NewRun
  // Map
  Go(node: Int)
  // Before a battle
  First(robot: Int)
  Fight
  // Battle
  Play(slot: Int)
  Continue
  // Repair shop
  Repair(robot: Int)
  Leave
  // Garage
  ClickRobot(robot: Int)
  ClickInstalled(robot: Int, part: Int)
  ClickSpare(part: Int)
  ClickChassis(chassis: Int)
  Remove
  Assemble
  Cancel
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let model = case msg {
    Frame(now) -> advance(model, now)
    KeyDown(key) -> key_down(model, key)
    NewRun -> new_run(browser.now())
    Go(node) -> attempt(model, state.go(model.run, node), "")
    First(robot) ->
      Model(..model, order: [
        robot,
        ..list.filter(model.order, fn(i) { i != robot })
      ])
    Fight -> fight(model)
    Play(slot) -> play(model, slot)
    Continue -> continue(model)
    Repair(robot) -> attempt(model, state.repair(model.run, robot), "")
    Leave -> attempt(model, state.leave(model.run), "")
    ClickRobot(robot) -> Model(..model, pick: PickedRobot(robot))
    ClickInstalled(robot, p) -> Model(..model, pick: PickedPart(robot, p))
    ClickSpare(spare) -> click_spare(model, spare)
    ClickChassis(chassis) -> Model(..model, pick: Draft(chassis, []))
    Remove ->
      case model.pick {
        PickedPart(robot, p) ->
          attempt(model, state.uninstall(model.run, robot, p), "")
        _ -> model
      }
    Assemble ->
      case model.pick {
        Draft(chassis, parts) -> {
          let name =
            "Robot " <> int.to_string(list.length(model.run.robots) + 1)
          attempt(model, state.assemble(model.run, name, chassis, parts), "")
        }
        _ -> model
      }
    Cancel -> Model(..model, pick: NoPick)
  }
  #(model, effect.none())
}

fn key_down(model: Model, key: String) -> Model {
  case model.battle, key {
    Some(_), "Enter" -> continue(model)
    Some(_), _ ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
    None, "Escape" -> Model(..model, pick: NoPick)
    None, _ -> model
  }
}

/// Apply a run step; on success clear the garage selection and reset the
/// battle order (robots may have come or gone).
fn attempt(
  model: Model,
  result: Result(Run, state.Error),
  news: String,
) -> Model {
  case result {
    Ok(run) ->
      Model(
        ..model,
        run:,
        pick: NoPick,
        order: default_order(run),
        news: case news {
          "" -> model.news
          _ -> news
        },
      )
    Error(error) -> flash(model, describe_error(error))
  }
}

fn flash(model: Model, text: String) -> Model {
  Model(..model, flash: text, flash_until: model.now + flash_ms)
}

fn click_spare(model: Model, spare: Int) -> Model {
  case model.pick {
    PickedRobot(robot) ->
      attempt(model, state.install(model.run, robot, spare), "")
    PickedPart(robot, p) ->
      attempt(model, state.swap(model.run, robot, p, spare), "")
    Draft(chassis, parts) ->
      Model(
        ..model,
        pick: Draft(chassis, case list.contains(parts, spare) {
          True -> list.filter(parts, fn(i) { i != spare })
          False -> list.append(parts, [spare])
        }),
      )
    NoPick -> flash(model, "Pick a robot or one of its parts first.")
  }
}

fn fight(model: Model) -> Model {
  case state.battle(model.run), state.team(model.run, model.order) {
    Ok(#(_, enemy)), Ok(team) -> {
      let now = browser.now()
      let game =
        game.teams(
          game.default_config(),
          p1: team,
          p2: [enemies.robot(enemy)],
          seed: browser.random_seed(),
          now:,
        )
      let brain =
        brain.new(P2, reaction: brain.human, seed: browser.random_seed())
      Model(..model, battle: Some(Battle(game:, brain:, order: model.order)))
    }
    Error(error), _ | _, Error(error) -> flash(model, describe_error(error))
  }
}

/// Let time pass and give the AI a chance to act.
fn advance(model: Model, now: Int) -> Model {
  case model.battle {
    Some(b) -> {
      let #(brain, game) = brain.act(b.brain, b.game, now)
      Model(..model, battle: Some(Battle(..b, game:, brain:)), now:)
    }
    None -> Model(..model, now:)
  }
}

fn play(model: Model, slot: Int) -> Model {
  // Use a fresh timestamp: the last frame may be up to 50ms old.
  let model = advance(model, browser.now())
  case model.battle {
    Some(b) ->
      case game.update(b.game, game.PlayCard(P1, slot, model.now)) {
        Ok(game) -> Model(..model, battle: Some(Battle(..b, game:)), flash: "")
        Error(rejection) ->
          flash(model, describe_rejection(model.scale, rejection))
      }
    None -> model
  }
}

/// After a finished battle: report it to the run.
fn continue(model: Model) -> Model {
  case model.battle {
    Some(b) if b.game.status != game.Running -> {
      let outcome = state.outcome(b.game, list.length(b.order))
      case state.finish(model.run, b.order, outcome) {
        Ok(#(run, reward)) ->
          Model(
            ..model,
            run:,
            battle: None,
            pick: NoPick,
            order: default_order(run),
            news: describe_reward(model.run, run, reward),
          )
        Error(error) -> flash(model, describe_error(error))
      }
    }
    _ -> model
  }
}

// WORDING ---------------------------------------------------------------------

fn describe_rejection(s: Scale, rejection: game.Rejection) -> String {
  case rejection {
    game.GameOver -> "The battle is over. Press Enter to continue."
    game.NoSuchCard -> "No card in that slot."
    game.NotEnoughEnergy(cost:, available:) ->
      "Not enough energy: need "
      <> int.to_string(scale.cost(s, cost))
      <> ", have "
      <> int.to_string(scale.energy(s, available))
  }
}

fn describe_error(error: state.Error) -> String {
  case error {
    state.WrongPhase -> "Not now."
    state.NotReachable(_) -> "You can't get there from here."
    state.BadOrder -> "Every robot must be in the battle order once."
    state.NoSuchRobot -> "No such robot."
    state.NoSuchPart -> "No such part."
    state.NoSuchChassis -> "No such chassis."
    state.CantBuild(robot:, errors:) ->
      robot
      <> ": "
      <> string.join(list.map(errors, builder.describe_error), "; ")
    state.NotEnoughMoney(price:, money:) ->
      "Costs "
      <> int.to_string(price)
      <> " credits; you have "
      <> int.to_string(money)
  }
}

fn describe_reward(before: Run, after: Run, reward: state.Reward) -> String {
  let lost =
    list.filter(before.robots, fn(b) {
      !list.any(after.robots, fn(a) { a.name == b.name })
    })
    |> list.map(fn(b) { b.name <> " was destroyed. " })
    |> string.concat
  case after.phase {
    state.Over -> lost
    _ ->
      lost
      <> "Victory! +"
      <> int.to_string(reward.money)
      <> " credits. Loot: "
      <> string.join(list.map(reward.parts, part.display_name), ", ")
      <> case reward.chassis {
        Some(c) -> ", and a " <> c.name <> " chassis!"
        None -> "."
      }
      <> case after.level > before.level {
        True -> " On to level " <> int.to_string(after.level) <> "!"
        False -> ""
      }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("screen")], [
    html.style([], css),
    html.pre([], [element.text(header(model))]),
    case model.battle, model.run.phase {
      Some(b), _ -> view_battle(model, b)
      None, state.Over -> view_over(model)
      None, state.Fighting(_) -> view_prebattle(model)
      None, state.Repairing(_) -> view_shop(model)
      None, state.Choosing -> view_map(model)
    },
    html.pre([attribute.class("banner")], [
      element.text(case model.now < model.flash_until {
        True -> "! " <> model.flash
        False -> ""
      }),
    ]),
  ])
}

fn header(model: Model) -> String {
  "ROBOTS · level "
  <> int.to_string(model.run.level)
  <> " · "
  <> int.to_string(model.run.money)
  <> " credits · "
  <> int.to_string(list.length(model.run.robots))
  <> case model.run.robots {
    [_] -> " robot"
    _ -> " robots"
  }
}

fn button(label: String, msg: Msg) -> Element(Msg) {
  html.button([attribute.class("card"), event.on_click(msg)], [
    element.text(label),
  ])
}

fn button_class(label: String, class: String, msg: Msg) -> Element(Msg) {
  html.button([attribute.class("card " <> class), event.on_click(msg)], [
    element.text(label),
  ])
}

fn text(class: String, content: String) -> Element(Msg) {
  html.pre([attribute.class(class)], [element.text(content)])
}

// Battle

fn view_battle(model: Model, b: Battle) -> Element(Msg) {
  let banner = case b.game.status {
    game.Won(P1) ->
      button_class(">>> VICTORY! Continue [Enter]", "banner", Continue)
    game.Won(P2) ->
      button_class(">>> DEFEAT. Continue [Enter]", "banner", Continue)
    game.Running -> text("dim", "[1-9] play a card")
  }
  battle_view.view(b.game, model.scale, model.now, banner, Play)
}

// Map

fn view_map(model: Model) -> Element(Msg) {
  let run = model.run
  let choices = list.map(state.choices(run), fn(n) { n.id })
  let rows =
    int.range(0, map.rows + 1, [], list.prepend)
    |> list.reverse
    |> list.map(fn(r) {
      html.div(
        [attribute.class("row")],
        list.map(map.row(run.map, r), fn(node) {
          let label = node_label(node)
          case list.contains(choices, node.id), run.at == Some(node.id) {
            True, _ -> button_class("→ " <> label, "choice", Go(node.id))
            _, True -> text("here", "● " <> label)
            _, _ -> text("dim node", "  " <> label)
          }
        }),
      )
    })
  html.div([], [
    text("news", model.news),
    text("", "MAP · level " <> int.to_string(run.level) <> " (top to bottom)"),
    html.div([attribute.class("map")], rows),
    view_garage(model),
  ])
}

fn node_label(node: map.Node) -> String {
  case node.event {
    map.RepairShop -> "Repair shop"
    map.Battle(tier: map.Normal, enemy:) -> enemy.name
    map.Battle(tier: map.Strong, enemy:) -> "STRONG " <> enemy.name
    map.Battle(tier: map.Boss, enemy:) -> "BOSS " <> enemy.name
  }
}

// Before a battle

fn view_prebattle(model: Model) -> Element(Msg) {
  case state.battle(model.run) {
    Error(_) -> text("", "")
    Ok(#(tier, enemy)) -> {
      let foe = enemies.robot(enemy)
      html.div([], [
        text(
          "foe",
          string.uppercase(map.tier_name(tier))
            <> ": "
            <> enemy.name
            <> " ("
            <> enemy.chassis.name
            <> ", "
            <> int.to_string(scale.value(model.scale, foe.hp))
            <> " HP)\n  "
            <> enemy.description,
        ),
        text("", "BATTLE ORDER (click a robot to send it in first)"),
        html.div(
          [attribute.class("table")],
          list.index_map(model.order, fn(i, n) {
            let assert [bot, ..] = list.drop(model.run.robots, i)
            button(
              int.to_string(n + 1) <> ". " <> bot_line(model.scale, bot),
              First(i),
            )
          }),
        ),
        button_class(">>> FIGHT!", "banner", Fight),
        view_garage(model),
      ])
    }
  }
}

// Repair shop

fn view_shop(model: Model) -> Element(Msg) {
  html.div([], [
    text(
      "",
      "REPAIR SHOP · full repairs, "
        <> int.to_string(price.repair(1.0))
        <> " credits per HP",
    ),
    html.div(
      [attribute.class("table")],
      list.index_map(model.run.robots, fn(bot, i) {
        case state.repair_price(bot) {
          0 -> text("dim", "  " <> bot_line(model.scale, bot) <> " · as new")
          cost ->
            button(
              "Repair "
                <> bot_line(model.scale, bot)
                <> " · "
                <> int.to_string(cost)
                <> " credits",
              Repair(i),
            )
        }
      }),
    ),
    button_class(">>> Leave", "banner", Leave),
    view_garage(model),
  ])
}

// End of the run

fn view_over(model: Model) -> Element(Msg) {
  html.div([], [
    text("news", model.news),
    text(
      "foe",
      "THE RUN IS OVER. You reached level "
        <> int.to_string(model.run.level)
        <> ".",
    ),
    button_class(">>> New run", "banner", NewRun),
  ])
}

// Garage

fn view_garage(model: Model) -> Element(Msg) {
  let run = model.run
  let robots =
    list.index_map(run.robots, fn(bot, r) {
      let picked_robot = model.pick == PickedRobot(r)
      html.div([attribute.class("robot")], [
        button_class(
          bot_line(model.scale, bot)
            <> " · weight "
            <> num(part.total_weight(bot.parts))
            <> "/"
            <> num(bot.chassis.capacity),
          case picked_robot {
            True -> "ally picked"
            False -> "ally"
          },
          ClickRobot(r),
        ),
        ..list.index_map(bot.parts, fn(p, i) {
          button_class(
            "    " <> part_line(p),
            case model.pick == PickedPart(r, i) {
              True -> "picked"
              False -> ""
            },
            ClickInstalled(r, i),
          )
        })
      ])
    })
  let drafted = case model.pick {
    Draft(_, parts) -> parts
    _ -> []
  }
  let spares =
    list.index_map(run.parts, fn(p, i) {
      button_class(
        "  " <> part_line(p),
        case list.contains(drafted, i) {
          True -> "picked"
          False -> ""
        },
        ClickSpare(i),
      )
    })
  let chassis =
    list.index_map(run.chassis, fn(c, i) {
      button_class(
        "  "
          <> c.name
          <> " chassis · "
          <> int.to_string(scale.value(model.scale, builder.chassis_hp(c)))
          <> " HP · carries "
          <> num(c.capacity)
          <> " · "
          <> int.to_string(list.length(c.weapon_mounts))
          <> " weapon mounts",
        case model.pick {
          Draft(chosen, _) if chosen == i -> "picked"
          _ -> ""
        },
        ClickChassis(i),
      )
    })
  html.div([attribute.class("garage")], [
    text("", "GARAGE · " <> hint(model.pick)),
    html.div([attribute.class("table")], robots),
    text("", "SPARE PARTS"),
    html.div([attribute.class("table")], case spares {
      [] -> [text("dim", "  none")]
      _ -> spares
    }),
    case chassis {
      [] -> text("", "")
      _ ->
        html.div([attribute.class("table")], [
          text("", "SPARE CHASSIS"),
          ..chassis
        ])
    },
    html.div([attribute.class("actions")], case model.pick {
      PickedPart(..) -> [
        button("[Remove part]", Remove),
        button("[Cancel]", Cancel),
      ]
      PickedRobot(_) -> [button("[Cancel]", Cancel)]
      Draft(..) -> [
        button("[Assemble robot]", Assemble),
        button("[Cancel]", Cancel),
      ]
      NoPick -> []
    }),
  ])
}

fn hint(pick: Pick) -> String {
  case pick {
    NoPick ->
      "click a robot to install spares on it, a part to swap or remove it, a chassis to build a robot"
    PickedRobot(_) -> "click a spare part to install it"
    PickedPart(..) -> "click a spare part to swap it in, or remove this one"
    Draft(..) -> "click spare parts for the new robot, then assemble"
  }
}

/// "Tinker (Frame) HP [######....] 9/12"
fn bot_line(s: Scale, bot: Bot) -> String {
  case state.build(bot) {
    Ok(r) ->
      bot.name
      <> " ("
      <> bot.chassis.name
      <> ") HP "
      <> battle_view.bar(r.hp, r.max_hp, 10)
      <> " "
      <> int.to_string(scale.value(s, r.hp))
      <> "/"
      <> int.to_string(scale.value(s, r.max_hp))
    Error(_) -> bot.name <> " (" <> bot.chassis.name <> ") can't fight as built"
  }
}

/// "Broken plating · armor · weight 2 · HP 0/2.5 · 25 cr"
fn part_line(p: Component) -> String {
  part.display_name(p)
  <> " · "
  <> part.kind_name(p.kind)
  <> " · weight "
  <> num(part.weight(p))
  <> case p.kind {
    part.Armor ->
      " · HP "
      <> num(part.remaining_hp(p))
      <> "/"
      <> num(part.hp(p))
      <> case wear.is_broken(p) {
        True -> " BROKEN"
        False -> ""
      }
    part.Battery -> " · stores " <> num(part.energy_cap(p))
    _ -> " · " <> int.to_string(list.length(p.cards)) <> " cards"
  }
  <> " · "
  <> int.to_string(price.of(p))
  <> " cr"
}

fn num(x: Float) -> String {
  let rounded = float.to_precision(x, 1)
  case rounded == float.floor(rounded) {
    True -> int.to_string(float.truncate(rounded))
    False -> float.to_string(rounded)
  }
}

const css =
  "
body { margin: 0; background: #101214; color: #c8d0c8; }
.screen { font-family: ui-monospace, 'JetBrains Mono', Menlo, Consolas, monospace;
  font-size: 15px; max-width: 60rem; margin: 0 auto; padding: 1.5rem 1rem; }
pre { margin: 0 0 0.75rem; white-space: pre-wrap; font: inherit; }
.foe { color: #e08a7a; }
.ally { color: #8fd18f; }
.dim { opacity: 0.45; }
.banner { color: #f0d060; min-height: 1.3em; }
.news { color: #f0d060; }
.here { color: #8fd18f; margin: 0; }
.table { display: flex; flex-direction: column; gap: 2px; margin-bottom: 0.75rem; }
.map { margin-bottom: 1rem; }
.row { display: flex; flex-wrap: wrap; gap: 0 1.5rem; margin-bottom: 0.25rem; }
.row pre { margin: 0; }
.choice { color: #f0d060; }
.robot { display: flex; flex-direction: column; gap: 1px; margin-bottom: 0.5rem; }
.actions { display: flex; gap: 1rem; margin-bottom: 0.75rem; }
.garage { border-top: 1px solid #2a302a; padding-top: 0.75rem; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; white-space: pre-wrap; }
.card:hover { background: #1f2a1f; }
.picked { background: #2a3a2a; }
"
