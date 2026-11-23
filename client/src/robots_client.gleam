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
import lustre/element/svg
import lustre/event
import robots/ai/brain
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/construction/wear
import robots/content/enemies
import robots/rules/game.{type Game, P1, P2}
import robots/rules/scale.{type Scale}
import robots/run/map
import robots/run/price
import robots/run/state.{type Bot, type Run}
import robots_client/battle_view
import robots_client/browser
import robots_client/card_view

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
    /// How the last battle went, shown until the player continues.
    report: Option(Report),
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
  Battle(
    game: Game,
    brain: brain.Brain,
    order: List(Int),
    /// The player's robots as they entered, in order.
    team: List(Robot),
    enemy: String,
    started: Int,
  )
}

type Report {
  Report(
    won: Bool,
    enemy: String,
    enemy_hp: Float,
    enemy_max_hp: Float,
    /// Each robot that fought: name, HP before, HP after, max HP.
    robots: List(#(String, Float, Float, Float)),
    seconds: Int,
    reward: state.Reward,
    /// The run's level before and after (a boss moves it on).
    level_before: Int,
    level_after: Int,
  )
}

/// What's selected in the garage; the selected parts' cards are shown.
type Pick {
  /// An installed part (robot, part) and/or a spare part. With one, it can
  /// be removed or installed; with both, swapped.
  Picked(installed: Option(#(Int, Int)), spare: Option(Int))
  /// A spare chassis and the spare parts chosen for a new robot; `last` is
  /// the spare clicked last, whose cards are shown.
  Draft(chassis: Int, parts: List(Int), last: Option(Int))
}

const no_pick = Picked(None, None)

fn new_run(now: Int) -> Model {
  let run = state.new(browser.random_seed())
  Model(
    run:,
    battle: None,
    report: None,
    order: default_order(run),
    pick: no_pick,
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
  ClickInstalled(robot: Int, part: Int)
  ClickSpare(part: Int)
  ClickChassis(chassis: Int)
  Install(robot: Int)
  Swap
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
    ClickInstalled(robot, p) -> {
      let spare = case model.pick {
        Picked(_, spare) -> spare
        Draft(..) -> None
      }
      let installed = case model.pick {
        Picked(Some(picked), _) if picked == #(robot, p) -> None
        _ -> Some(#(robot, p))
      }
      Model(..model, pick: Picked(installed, spare))
    }
    ClickSpare(spare) -> click_spare(model, spare)
    ClickChassis(chassis) -> Model(..model, pick: Draft(chassis, [], None))
    Install(robot) ->
      case model.pick {
        Picked(_, Some(spare)) ->
          attempt(model, state.install(model.run, robot, spare), "")
        _ -> model
      }
    Swap ->
      case model.pick {
        Picked(Some(#(robot, p)), Some(spare)) ->
          attempt(model, state.swap(model.run, robot, p, spare), "")
        _ -> model
      }
    Remove ->
      case model.pick {
        Picked(Some(#(robot, p)), _) ->
          attempt(model, state.uninstall(model.run, robot, p), "")
        _ -> model
      }
    Assemble ->
      case model.pick {
        Draft(chassis, parts, _) -> {
          let name =
            "Robot " <> int.to_string(list.length(model.run.robots) + 1)
          attempt(model, state.assemble(model.run, name, chassis, parts), "")
        }
        _ -> model
      }
    Cancel -> Model(..model, pick: no_pick)
  }
  #(model, effect.none())
}

fn key_down(model: Model, key: String) -> Model {
  case model.battle, key {
    _, "Enter" if model.report != None -> continue(model)
    Some(_), _ ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
    None, "Escape" -> Model(..model, pick: no_pick)
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
        pick: no_pick,
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
    Draft(chassis, parts, _) ->
      Model(
        ..model,
        pick: Draft(
          chassis,
          case list.contains(parts, spare) {
            True -> list.filter(parts, fn(i) { i != spare })
            False -> list.append(parts, [spare])
          },
          Some(spare),
        ),
      )
    Picked(installed, Some(picked)) if picked == spare ->
      Model(..model, pick: Picked(installed, None))
    Picked(installed, _) -> Model(..model, pick: Picked(installed, Some(spare)))
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
      Model(
        ..model,
        battle: Some(Battle(
          game:,
          brain:,
          order: model.order,
          team:,
          enemy: enemy.name,
          started: now,
        )),
      )
    }
    Error(error), _ | _, Error(error) -> flash(model, describe_error(error))
  }
}

/// Let time pass and give the AI a chance to act.
fn advance(model: Model, now: Int) -> Model {
  case model.battle {
    Some(b) -> {
      let #(brain, game) = brain.act(b.brain, b.game, now)
      end_if_over(
        Model(..model, battle: Some(Battle(..b, game:, brain:)), now:),
      )
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
        Ok(game) ->
          end_if_over(
            Model(..model, battle: Some(Battle(..b, game:)), flash: ""),
          )
        Error(rejection) ->
          flash(model, describe_rejection(model.scale, rejection))
      }
    None -> model
  }
}

/// Once the battle is over, report it to the run (damage, losses, loot)
/// and show the battle report. The battle stops: no more ticking.
fn end_if_over(model: Model) -> Model {
  case model.battle {
    Some(b) if b.game.status != game.Running -> {
      let outcome = state.outcome(b.game, list.length(b.order))
      case state.finish(model.run, b.order, outcome) {
        Ok(#(run, reward)) -> {
          let report =
            Report(
              won: outcome.won,
              enemy: b.enemy,
              enemy_hp: b.game.p2.robot.hp,
              enemy_max_hp: b.game.p2.robot.max_hp,
              robots: list.map(list.zip(b.team, outcome.hp_left), fn(pair) {
                let #(r, after) = pair
                #(r.name, r.hp, after, r.max_hp)
              }),
              seconds: { model.now - b.started } / 1000,
              reward:,
              level_before: model.run.level,
              level_after: run.level,
            )
          Model(
            ..model,
            run:,
            battle: None,
            report: Some(report),
            flash: "",
            flash_until: 0,
            pick: no_pick,
            order: default_order(run),
            news: describe_reward(model.run, run, reward),
          )
        }
        Error(error) -> flash(model, describe_error(error))
      }
    }
    _ -> model
  }
}

/// Leave the battle report.
fn continue(model: Model) -> Model {
  Model(..model, report: None)
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
      _, _ if model.report != None -> view_report(model)
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
  let banner = text("dim", "[1-9] play a card")
  battle_view.view(b.game, model.scale, model.now, banner, Play)
}

// Battle report

fn view_report(model: Model) -> Element(Msg) {
  let assert Some(r) = model.report
  let s = model.scale
  let hp = fn(x) { int.to_string(scale.value(s, x)) }
  let robots =
    list.map(r.robots, fn(entry) {
      let #(name, before, after, max) = entry
      "  "
      <> string.pad_end(name, 12, " ")
      <> battle_view.bar(after, max, 20)
      <> " "
      <> hp(before)
      <> " → "
      <> case after >. 0.0 {
        True -> hp(after) <> "/" <> hp(max)
        False -> "DESTROYED (lost with its parts)"
      }
    })
  let loot =
    list.map(r.reward.parts, fn(p) { "  + " <> part_line(p) })
    |> list.append(case r.reward.chassis {
      Some(c) -> ["  + " <> c.name <> " chassis"]
      None -> []
    })
  html.div([], [
    text(
      case r.won {
        True -> "banner big"
        False -> "foe big"
      },
      case r.won {
        True -> "VICTORY"
        False -> "DEFEAT"
      }
        <> " against "
        <> r.enemy
        <> " · "
        <> int.to_string(r.seconds)
        <> " s",
    ),
    text(
      "ally",
      "YOUR ROBOTS (HP before → after)\n" <> string.join(robots, "\n"),
    ),
    text(
      "foe",
      "ENEMY  "
        <> battle_view.bar(r.enemy_hp, r.enemy_max_hp, 20)
        <> " "
        <> hp(r.enemy_hp)
        <> "/"
        <> hp(r.enemy_max_hp),
    ),
    case r.won {
      True ->
        text(
          "",
          "REWARD: +"
            <> int.to_string(r.reward.money)
            <> " credits\n"
            <> string.join(loot, "\n")
            <> case r.level_after > r.level_before {
            True ->
              "\n\nThe boss is beaten! On to level "
              <> int.to_string(r.level_after)
              <> "."
            False -> ""
          },
        )
      False -> text("foe", "Every robot is gone. The run is over.")
    },
    button_class(">>> Continue [Enter]", "banner", Continue),
  ])
}

// Map

fn view_map(model: Model) -> Element(Msg) {
  let run = model.run
  let choices = state.choices(run)
  html.div([], [
    text("news", model.news),
    text(
      "",
      "MAP · level "
        <> int.to_string(run.level)
        <> " · start at the top, the boss waits at the bottom",
    ),
    map_svg(run, choices),
    text(
      "dim",
      "E enemy · S strong enemy · R repair shop · B boss · green: your path · yellow: where you can go · faded: out of reach",
    ),
    text("", "WHERE NEXT"),
    html.div(
      [attribute.class("table")],
      list.map(choices, fn(n) {
        button_class(
          "→ " <> node_label(n) <> node_detail(n),
          "choice",
          Go(n.id),
        )
      }),
    ),
    view_garage(model),
  ])
}

const map_width = 760

const row_height = 84

const map_top = 30

fn node_xy(m: map.Map, node: map.Node) -> #(Int, Int) {
  let row = map.row(m, node.row)
  let index =
    list.index_fold(row, 0, fn(found, n, i) {
      case n.id == node.id {
        True -> i
        False -> found
      }
    })
  let x = { index + 1 } * map_width / { list.length(row) + 1 }
  #(x, map_top + node.row * row_height)
}

fn map_svg(run: Run, choices: List(map.Node)) -> Element(Msg) {
  let m = run.map
  let choice_ids = list.map(choices, fn(n) { n.id })
  // What can still be reached from here.
  let reachable = case run.at {
    None -> map.reachable(m, map.start(m))
    Some(id) ->
      case map.node(m, id) {
        Ok(here) -> map.reachable(m, [here])
        Error(Nil) -> []
      }
  }
  let steps = list.window_by_2(run.path)
  let links =
    list.flat_map(m.nodes, fn(from) {
      list.filter_map(from.next, fn(to_id) {
        case map.node(m, to_id) {
          Ok(to) -> Ok(link(m, run, from, to, steps, choice_ids, reachable))
          Error(Nil) -> Error(Nil)
        }
      })
    })
  let nodes =
    list.map(m.nodes, fn(n) { map_node(m, run, n, choice_ids, reachable) })
  svg.svg(
    [
      attribute.attribute(
        "viewBox",
        "0 0 "
          <> int.to_string(map_width)
          <> " "
          <> int.to_string(map_top * 2 + map.rows * row_height + 20),
      ),
      attribute.class("map"),
    ],
    list.append(links, nodes),
  )
}

fn link(
  m: map.Map,
  run: Run,
  from: map.Node,
  to: map.Node,
  steps: List(#(Int, Int)),
  choice_ids: List(Int),
  reachable: List(Int),
) -> Element(Msg) {
  let #(x1, y1) = node_xy(m, from)
  let #(x2, y2) = node_xy(m, to)
  let #(color, width) = case
    list.contains(steps, #(from.id, to.id)),
    run.at == Some(from.id) && list.contains(choice_ids, to.id),
    list.contains(reachable, from.id) && list.contains(reachable, to.id)
  {
    True, _, _ -> #("#8fd18f", "3")
    _, True, _ -> #("#f0d060", "3")
    _, _, True -> #("#6a766a", "1.5")
    _, _, False -> #("#2a302a", "1")
  }
  svg.line([
    attribute.attribute("x1", int.to_string(x1)),
    attribute.attribute("y1", int.to_string(y1)),
    attribute.attribute("x2", int.to_string(x2)),
    attribute.attribute("y2", int.to_string(y2)),
    attribute.attribute("stroke", color),
    attribute.attribute("stroke-width", width),
  ])
}

fn map_node(
  m: map.Map,
  run: Run,
  node: map.Node,
  choice_ids: List(Int),
  reachable: List(Int),
) -> Element(Msg) {
  let #(x, y) = node_xy(m, node)
  let #(letter, fill, stroke) = case node.event {
    map.RepairShop -> #("R", "#1f3340", "#7ab0d0")
    map.Battle(tier: map.Normal, ..) -> #("E", "#33241f", "#e08a7a")
    map.Battle(tier: map.Strong, ..) -> #("S", "#4a1c1c", "#ff6a5a")
    map.Battle(tier: map.Boss, ..) -> #("B", "#3a2048", "#c890f0")
  }
  let here = run.at == Some(node.id)
  let visited = list.contains(run.path, node.id)
  let choice = list.contains(choice_ids, node.id)
  let #(stroke, stroke_width) = case here, choice {
    True, _ -> #("#8fd18f", "4")
    _, True -> #("#f0d060", "3")
    _, _ -> #(stroke, "1.5")
  }
  let opacity = case here || visited || list.contains(reachable, node.id) {
    True -> "1"
    False -> "0.25"
  }
  let fill = case visited && !here {
    True -> "#22331f"
    False -> fill
  }
  let lines = label_lines(node_label(node))
  let events = case choice {
    True -> [event.on_click(Go(node.id)), attribute.class("clickable")]
    False -> []
  }
  svg.g([attribute.attribute("opacity", opacity), ..events], [
    svg.title([], [element.text(node_label(node) <> node_detail(node))]),
    svg.circle([
      attribute.attribute("cx", int.to_string(x)),
      attribute.attribute("cy", int.to_string(y)),
      attribute.attribute("r", "15"),
      attribute.attribute("fill", fill),
      attribute.attribute("stroke", stroke),
      attribute.attribute("stroke-width", stroke_width),
    ]),
    svg_text(x, y + 5, "14", "#e8ece8", letter),
    ..list.index_map(lines, fn(line, i) {
      svg_text(x, y + 30 + i * 12, "11", "#b8c0b8", line)
    })
  ])
}

fn svg_text(
  x: Int,
  y: Int,
  size: String,
  color: String,
  content: String,
) -> Element(Msg) {
  svg.text(
    [
      attribute.attribute("x", int.to_string(x)),
      attribute.attribute("y", int.to_string(y)),
      attribute.attribute("font-size", size),
      attribute.attribute("fill", color),
      attribute.attribute("text-anchor", "middle"),
    ],
    content,
  )
}

/// A node's name in at most two short lines.
fn label_lines(label: String) -> List(String) {
  case string.length(label) <= 20 {
    True -> [label]
    False -> {
      let words = string.split(label, " ")
      let half = list.length(words) / 2
      [
        string.join(list.take(words, half), " "),
        string.join(list.drop(words, half), " "),
      ]
    }
  }
}

/// " · A small, quick scrapper..." for battles.
fn node_detail(node: map.Node) -> String {
  case node.event {
    map.Battle(enemy:, ..) -> " · " <> enemy.description
    map.RepairShop -> " · repair your robots for credits"
  }
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
  let #(installed, spare, drafted, chassis_pick) = case model.pick {
    Picked(installed, spare) -> #(installed, spare, [], None)
    Draft(chassis, parts, _) -> #(None, None, parts, Some(chassis))
  }
  let picked = fn(yes) {
    case yes {
      True -> "picked"
      False -> ""
    }
  }
  let robots =
    list.index_map(run.robots, fn(bot, r) {
      html.div([attribute.class("robot")], [
        text(
          "ally",
          bot_line(model.scale, bot)
            <> " · weight "
            <> num(part.total_weight(bot.parts))
            <> "/"
            <> num(bot.chassis.capacity),
        ),
        ..list.index_map(bot.parts, fn(p, i) {
          button_class(
            "    " <> part_line(p),
            picked(installed == Some(#(r, i))),
            ClickInstalled(r, i),
          )
        })
      ])
    })
  let spares =
    list.index_map(run.parts, fn(p, i) {
      button_class(
        "  " <> part_line(p),
        picked(spare == Some(i) || list.contains(drafted, i)),
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
        picked(chassis_pick == Some(i)),
        ClickChassis(i),
      )
    })
  let actions = case model.pick {
    Picked(Some(_), Some(_)) -> [
      button("[Swap them]", Swap),
      button("[Cancel]", Cancel),
    ]
    Picked(Some(_), None) -> [
      button("[Remove part]", Remove),
      button("[Cancel]", Cancel),
    ]
    Picked(None, Some(_)) ->
      list.append(
        list.index_map(run.robots, fn(bot, r) {
          button("[Install on " <> bot.name <> "]", Install(r))
        }),
        [button("[Cancel]", Cancel)],
      )
    Picked(None, None) -> []
    Draft(..) -> [
      button("[Assemble robot]", Assemble),
      button("[Cancel]", Cancel),
    ]
  }
  html.div([attribute.class("garage")], [
    html.div([], [
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
      html.div([attribute.class("actions")], actions),
    ]),
    view_selected(model),
  ])
}

/// The cards of what's selected: an installed part, a spare, both (what
/// goes out and what comes in), or a chassis being built on.
fn view_selected(model: Model) -> Element(Msg) {
  let run = model.run
  let installed_part = fn(r, i) {
    case list.drop(run.robots, r) {
      [bot, ..] -> list.drop(bot.parts, i) |> list.first |> option.from_result
      [] -> None
    }
  }
  let spare_part = fn(i) {
    list.drop(run.parts, i) |> list.first |> option.from_result
  }
  let sections = case model.pick {
    Picked(installed, spare) -> {
      let out =
        option.then(installed, fn(pair) { installed_part(pair.0, pair.1) })
      let incoming = option.then(spare, spare_part)
      case out, incoming {
        Some(o), Some(n) -> [
          preview_section(model, "OUT", o),
          preview_section(model, "IN", n),
        ]
        Some(o), None -> [preview_section(model, "", o)]
        None, Some(n) -> [preview_section(model, "", n)]
        None, None -> [
          text("dim", "Select a part, spare or chassis to see its cards."),
        ]
      }
    }
    Draft(chassis, _, last) -> {
      let body =
        list.drop(run.chassis, chassis)
        |> list.first
        |> option.from_result
        |> option.map(builder.body)
      list.flatten([
        case body {
          Some(b) -> [preview_section(model, "CHASSIS", b)]
          None -> []
        },
        case option.then(last, spare_part) {
          Some(p) -> [preview_section(model, "PART", p)]
          None -> []
        },
      ])
    }
  }
  html.div([attribute.class("preview")], sections)
}

fn preview_section(model: Model, label: String, p: Component) -> Element(Msg) {
  let title = case label {
    "" -> ""
    _ -> label <> ": "
  }
  let cards = part.cards(p)
  html.div([], [
    text(
      "",
      title
        <> part.display_name(p)
        <> " · "
        <> case cards {
        [] -> "no cards"
        [_] -> "1 card"
        _ -> int.to_string(list.length(cards)) <> " cards"
      },
    ),
    card_view.row(
      list.map(cards, fn(c) {
        card_view.view(
          model.scale,
          c,
          current: c.value,
          key: None,
          dim: False,
          on_click: None,
        )
      }),
    ),
  ])
}

fn hint(pick: Pick) -> String {
  case pick {
    Picked(None, None) ->
      "select a part or spare to see its cards; a chassis to build a robot"
    Picked(Some(_), None) -> "remove it, or select a spare to swap it for"
    Picked(None, Some(_)) -> "install it, or select an installed part to swap"
    Picked(Some(_), Some(_)) -> "swap them, or change either selection"
    Draft(..) -> "select spare parts for the new robot, then assemble"
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
  font-size: 15px; max-width: 76rem; margin: 0 auto; padding: 1.5rem 1rem; }
pre { margin: 0 0 0.75rem; white-space: pre-wrap; font: inherit; }
.foe { color: #e08a7a; }
.ally { color: #8fd18f; }
.dim { opacity: 0.45; }
.banner { color: #f0d060; min-height: 1.3em; }
.big { font-size: 1.4em; font-weight: bold; }
.news { color: #f0d060; }
.here { color: #8fd18f; margin: 0; }
.table { display: flex; flex-direction: column; gap: 2px; margin-bottom: 0.75rem; }
.map { width: 100%; max-width: 760px; display: block; margin-bottom: 0.5rem; }
.clickable { cursor: pointer; }
.row { display: flex; flex-wrap: wrap; gap: 0 1.5rem; margin-bottom: 0.25rem; }
.row pre { margin: 0; }
.choice { color: #f0d060; }
.robot { display: flex; flex-direction: column; gap: 1px; margin-bottom: 0.5rem; }
.actions { display: flex; gap: 1rem; margin-bottom: 0.75rem; }
.garage { border-top: 1px solid #2a302a; padding-top: 0.75rem;
  display: grid; grid-template-columns: minmax(0, 1fr) 21rem; gap: 1.5rem; }
.preview { position: sticky; top: 1rem; align-self: start; }
@media (max-width: 900px) { .garage { grid-template-columns: 1fr; } }
.cards { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 0.75rem; }
.cardbox { width: 9.5rem; min-height: 7.5rem; border: 2px solid; border-radius: 7px;
  padding: 5px 7px; font-size: 12px; display: flex; flex-direction: column; gap: 3px;
  box-sizing: border-box; }
.cardbox.clickable:hover { filter: brightness(1.35); }
.cardhead { display: flex; justify-content: space-between; font-size: 10px; letter-spacing: 0.05em; opacity: 0.85; }
.cardcost { font-weight: bold; color: #f0d060; }
.cardname { font-weight: bold; font-size: 13px; }
.cardvalue { font-size: 20px; font-weight: bold; }
.cardtarget { font-size: 11px; }
.cardtags { font-size: 10px; opacity: 0.7; white-space: pre-wrap; margin-top: auto; }
.cardbox.attack { border-color: #e06a5a; background: #2a1614; color: #f2c2ba; }
.cardbox.defence { border-color: #5a9ae0; background: #141e2a; color: #bcd4f2; }
.cardbox.buff { border-color: #6ad06a; background: #142a16; color: #c2f0c2; }
.cardbox.special { border-color: #9a9a9a; background: #1e1e1e; color: #d0d0d0; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; white-space: pre-wrap; }
.card:hover { background: #1f2a1f; }
.picked { background: #2a3a2a; }
"
