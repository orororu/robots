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

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
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
import robots/meta/blueprint.{type Blueprint, ChassisBlueprint, PartBlueprint}
import robots/meta/profile.{type Profile}
import robots/rules/card
import robots/rules/game.{type Game, P1, P2}
import robots/rules/scale.{type Scale}
import robots/run/map
import robots/run/price
import robots/run/shop
import robots/run/state.{type Bot, type Run}
import robots/run/upgrade
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
    /// What carries over between runs; saved in the browser.
    profile: Profile,
    /// Between runs: the hangar, where Salvage is spent and the starting
    /// robot designed. `run` is the last run (or a placeholder) meanwhile.
    hangar: Option(Hangar),
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
    /// The last workshop upgrade (part name, change), shown on the map
    /// until the next step.
    upgraded: Option(#(String, upgrade.Change)),
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

/// The hangar: the design being edited (the fabricator's first robot) and
/// what's selected.
type Hangar {
  Hangar(design: profile.Design, pick: HangarPick)
}

type HangarPick {
  NoHangarPick
  /// A found blueprint, to research.
  PickFound(Blueprint)
  /// A researched blueprint, to add to the design (a part) or build it on
  /// (a chassis).
  PickBlueprint(Blueprint)
  /// Part `index` of the design, to remove.
  PickInstalled(index: Int)
}

/// What's selected in the garage; the selected parts' cards are shown.
type Pick {
  /// An installed part (robot, part) and/or a spare part. With one, it can
  /// be removed or installed; with both, swapped.
  Picked(installed: Option(#(Int, Int)), spare: Option(Int))
  /// A spare chassis and the spare parts chosen for a new robot; `last` is
  /// the spare clicked last, whose cards are shown.
  Draft(chassis: Int, parts: List(Int), last: Option(Int))
  /// The chassis of robot `robot` (to see its cards, or repair it).
  OwnChassis(robot: Int)
  /// Something a shop sells.
  ForSale(item: Stock, index: Int)
}

/// The kinds of things a shop sells.
type Stock {
  StockPart
  StockRobot
}

const no_pick = Picked(None, None)

/// A model for `run`, in the hangar if `hangar` is given.
fn new_model(
  run: Run,
  profile: Profile,
  hangar: Option(Hangar),
  now: Int,
) -> Model {
  Model(
    profile:,
    hangar:,
    run:,
    battle: None,
    report: None,
    order: default_order(run),
    pick: no_pick,
    news: "A new run. Pick where to go.",
    upgraded: None,
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
  let profile =
    profile.decode(browser.load_profile()) |> result.unwrap(profile.new())
  let model =
    new_model(
      state.new(browser.random_seed()),
      profile,
      Some(hangar_for(profile)),
      browser.now(),
    )
  #(model, subscriptions)
}

fn hangar_for(p: Profile) -> Hangar {
  let design = case profile.design(p, 0) {
    Ok(d) -> d
    Error(Nil) -> profile.Design("Robot", "Frame", [])
  }
  Hangar(design:, pick: NoHangarPick)
}

/// Save the profile and go to the hangar.
fn open_hangar(model: Model, p: Profile) -> Model {
  browser.save_profile(profile.encode(p))
  Model(
    ..model,
    profile: p,
    hangar: Some(hangar_for(p)),
    battle: None,
    report: None,
  )
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  // Hangar
  HangarSelect(pick: HangarPick)
  Research
  AddPart
  RemovePart
  UseChassis
  CopyBlueprint
  ResearchCopier
  StartRun
  /// After a run: pay it out and go to the hangar.
  ToHangar
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
  RepairPicked
  SellPicked
  Leave
  // Workshop
  UpgradePicked
  // Garage
  ClickInstalled(robot: Int, part: Int)
  ClickSpare(part: Int)
  ClickChassis(chassis: Int)
  ClickOwnChassis(robot: Int)
  ClickForSale(item: Stock, index: Int)
  Buy
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
    HangarSelect(pick) ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.pick == pick {
          True -> NoHangarPick
          False -> pick
        })
      })
    Research ->
      case model.hangar {
        Some(Hangar(pick: PickFound(b), ..) as h) ->
          case profile.research(model.profile, b) {
            Ok(p) -> {
              browser.save_profile(profile.encode(p))
              Model(
                ..model,
                profile: p,
                hangar: Some(Hangar(..h, pick: PickBlueprint(b))),
              )
            }
            Error(e) -> flash(model, describe_profile_error(e))
          }
        _ -> model
      }
    AddPart ->
      update_hangar(model, fn(h) {
        case h.pick {
          PickBlueprint(PartBlueprint(name)) ->
            Hangar(
              ..h,
              design: profile.Design(
                ..h.design,
                parts: list.append(h.design.parts, [name]),
              ),
            )
          _ -> h
        }
      })
    RemovePart ->
      update_hangar(model, fn(h) {
        case h.pick {
          PickInstalled(i) ->
            Hangar(
              design: profile.Design(
                ..h.design,
                parts: list.append(
                  list.take(h.design.parts, i),
                  list.drop(h.design.parts, i + 1),
                ),
              ),
              pick: NoHangarPick,
            )
          _ -> h
        }
      })
    UseChassis ->
      update_hangar(model, fn(h) {
        case h.pick {
          PickBlueprint(ChassisBlueprint(name)) ->
            Hangar(
              design: profile.Design(..h.design, chassis: name),
              pick: NoHangarPick,
            )
          _ -> h
        }
      })
    CopyBlueprint ->
      case model.hangar {
        Some(Hangar(pick: PickBlueprint(b), ..)) ->
          change_profile(model, profile.copy(model.profile, b))
        _ -> model
      }
    ResearchCopier ->
      change_profile(model, profile.research_copier(model.profile))
    StartRun -> start_run(model)
    ToHangar -> open_hangar(model, profile.finish(model.profile, model.run))
    Go(node) ->
      attempt(Model(..model, upgraded: None), state.go(model.run, node), "")
    First(robot) ->
      Model(..model, order: [
        robot,
        ..list.filter(model.order, fn(i) { i != robot })
      ])
    Fight -> fight(model)
    Play(slot) -> play(model, slot)
    Continue -> continue(model)
    Repair(robot) -> attempt(model, state.repair(model.run, robot), "")
    RepairPicked ->
      case repair_target(model.pick) {
        Some(target) -> attempt(model, state.repair_one(model.run, target), "")
        None -> model
      }
    SellPicked ->
      case model.pick {
        Picked(None, Some(spare)) ->
          attempt(model, state.sell(model.run, spare), "")
        _ -> model
      }
    Leave -> attempt(model, state.leave(model.run), "")
    UpgradePicked ->
      case upgrade_target(model.pick) {
        Some(target) ->
          case
            state.target_part(model.run, target),
            state.upgrade(model.run, target)
          {
            Ok(p), Ok(#(run, change)) ->
              attempt(
                Model(..model, upgraded: Some(#(part.display_name(p), change))),
                Ok(run),
                "Upgraded "
                  <> part.display_name(p)
                  <> ": "
                  <> change.before.name
                  <> " → "
                  <> change.after.name
                  <> ".",
              )
            _, Error(error) -> attempt(model, Error(error), "")
            Error(error), _ -> attempt(model, Error(error), "")
          }
        None -> model
      }
    ClickInstalled(robot, p) -> {
      let spare = case model.pick {
        Picked(_, spare) -> spare
        Draft(..) | OwnChassis(_) | ForSale(..) -> None
      }
      let installed = case model.pick {
        Picked(Some(picked), _) if picked == #(robot, p) -> None
        _ -> Some(#(robot, p))
      }
      Model(..model, pick: Picked(installed, spare))
    }
    ClickSpare(spare) -> click_spare(model, spare)
    ClickChassis(chassis) -> Model(..model, pick: Draft(chassis, [], None))
    ClickForSale(item, i) ->
      Model(..model, pick: case model.pick {
        ForSale(it, j) if it == item && j == i -> no_pick
        _ -> ForSale(item, i)
      })
    Buy ->
      case model.pick {
        ForSale(StockPart, i) ->
          attempt(model, state.buy_part(model.run, i), "")
        ForSale(StockRobot, i) ->
          attempt(model, state.buy_robot(model.run, i), "")
        _ -> model
      }
    ClickOwnChassis(robot) ->
      Model(..model, pick: case model.pick {
        OwnChassis(r) if r == robot -> no_pick
        _ -> OwnChassis(robot)
      })
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

/// Apply a change to the profile and save it, or flash why it failed.
fn change_profile(
  model: Model,
  result: Result(Profile, profile.Error),
) -> Model {
  case result {
    Ok(p) -> {
      browser.save_profile(profile.encode(p))
      Model(..model, profile: p)
    }
    Error(e) -> flash(model, describe_profile_error(e))
  }
}

fn update_hangar(model: Model, f: fn(Hangar) -> Hangar) -> Model {
  case model.hangar {
    Some(h) -> Model(..model, hangar: Some(f(h)))
    None -> model
  }
}

/// Save the design and start a run with the fabricated robots.
fn start_run(model: Model) -> Model {
  case model.hangar {
    None -> model
    Some(h) -> {
      let started = {
        use p <- result.try(profile.set_design(model.profile, 0, h.design))
        use run <- result.map(profile.start(p, browser.random_seed()))
        #(p, run)
      }
      case started {
        Ok(#(p, run)) -> {
          browser.save_profile(profile.encode(p))
          new_model(run, p, None, model.now)
        }
        Error(e) -> flash(model, describe_profile_error(e))
      }
    }
  }
}

fn describe_profile_error(e: profile.Error) -> String {
  case e {
    profile.NotFound(b) -> blueprint.describe(b) <> ": no blueprint."
    profile.NotEnoughCopies(blueprint: b, have:, need:) ->
      "Needs "
      <> int.to_string(need)
      <> " "
      <> blueprint.describe(b)
      <> " blueprints; you have "
      <> int.to_string(have)
      <> ". Each blueprint makes one."
    profile.NoCopier -> "Research the blueprint copier first."
    profile.CopierResearched -> "The blueprint copier is researched already."
    profile.NotEnoughSalvage(cost:, salvage:) ->
      "Costs "
      <> int.to_string(cost)
      <> " Salvage; you have "
      <> int.to_string(salvage)
      <> "."
    profile.NotResearched(b) ->
      blueprint.describe(b) <> " isn't researched yet."
    profile.CantBuild(design:, errors:) ->
      design
      <> ": "
      <> string.join(list.map(errors, builder.describe_error), "; ")
    profile.NoSuchDesign -> "No such design."
  }
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
    OwnChassis(_) | ForSale(..) ->
      Model(..model, pick: Picked(None, Some(spare)))
  }
}

/// What a repair would fix for this selection: one chassis or one part.
/// The one component selected, to upgrade at a workshop.
fn upgrade_target(pick: Pick) -> Option(state.Target) {
  case pick {
    Picked(Some(#(robot, p)), None) -> Some(state.Installed(robot, p))
    Picked(None, Some(spare)) -> Some(state.Spare(spare))
    _ -> None
  }
}

fn repair_target(pick: Pick) -> Option(state.Repair) {
  case pick {
    OwnChassis(robot) -> Some(state.RepairChassis(robot))
    Picked(Some(#(robot, p)), None) -> Some(state.RepairPart(robot, p))
    Picked(None, Some(spare)) -> Some(state.RepairSpare(spare))
    _ -> None
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
    state.CantUpgrade -> "Every card of it is at its best already."
    state.TruckFull(robots:) ->
      "The truck carries "
      <> int.to_string(robots)
      <> " robots and is full. Keep the chassis as a spare."
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
      <> case reward.blueprint {
        Some(b) -> " Found a blueprint: " <> blueprint.describe(b) <> "!"
        None -> ""
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
      _, _ if model.hangar != None -> view_hangar(model)
      _, _ if model.report != None -> view_report(model)
      Some(b), _ -> view_battle(model, b)
      None, state.Over -> view_over(model)
      None, state.Fighting(_) -> view_prebattle(model)
      None, state.Repairing(_) -> view_shop(model)
      None, state.Upgrading(_) -> view_workshop(model)
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
  use <- bool.lazy_guard(model.hangar != None, fn() {
    "ROBOTS · HANGAR · "
    <> int.to_string(model.profile.salvage)
    <> " Salvage · "
    <> int.to_string(model.profile.runs)
    <> case model.profile.runs {
      1 -> " run"
      _ -> " runs"
    }
  })
  "ROBOTS · level "
  <> int.to_string(model.run.level)
  <> " · "
  <> int.to_string(model.run.money)
  <> " credits · "
  <> int.to_string(list.length(model.run.robots))
  <> " of "
  <> int.to_string(model.run.truck)
  <> " robots in the truck"
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
    list.map(r.reward.parts, fn(p) { "  + " <> part_line(s, p) })
    |> list.append(case r.reward.chassis {
      Some(c) -> ["  + " <> c.name <> " chassis"]
      None -> []
    })
    |> list.append(case r.reward.blueprint {
      Some(b) -> [
        "  + Blueprint: "
        <> blueprint.describe(b)
        <> " (research it in the hangar after the run)",
      ]
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
    view_upgrade(model),
    text(
      "",
      "MAP · level "
        <> int.to_string(run.level)
        <> " · start at the top, the boss waits at the bottom",
    ),
    map_svg(run, choices),
    text(
      "dim",
      "E enemy · S strong enemy · R repair shop · U workshop · B boss · green: your path · yellow: where you can go · faded: out of reach",
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
    text("", "YOUR ROBOTS · change parts in the garage before a fight"),
    html.div(
      [attribute.class("table")],
      list.map(run.robots, fn(bot) {
        text("ally", "  " <> bot_line(model.scale, bot))
      }),
    ),
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
    map.Workshop -> #("U", "#2a3a1f", "#a8d07a")
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
    map.Workshop -> " · upgrade one component, free"
  }
}

fn node_label(node: map.Node) -> String {
  case node.event {
    map.RepairShop -> "Repair shop"
    map.Workshop -> "Workshop"
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

// Workshop

fn view_workshop(model: Model) -> Element(Msg) {
  html.div([], [
    text(
      "",
      "WORKSHOP · select a component below, then upgrade it: one card gets a "
        <> "good attribute, or a good one goes up a tier. Free, once.",
    ),
    button_class(">>> Leave without upgrading", "banner", Leave),
    view_garage(model),
  ])
}

// Repair shop

fn view_shop(model: Model) -> Element(Msg) {
  let run = model.run
  let s = model.scale
  let robots =
    list.index_map(run.robots, fn(bot, r) {
      case state.repair_price(bot) {
        0 -> text("dim", "  " <> bot_line(s, bot) <> " · as new")
        cost ->
          button(
            "  Repair all of "
              <> bot_line(s, bot)
              <> " · "
              <> int.to_string(cost)
              <> " credits",
            Repair(r),
          )
      }
    })
  html.div([], [
    text(
      "",
      "REPAIR SHOP · "
        <> int.to_string(price.repair(1.0) / scale.value(s, 1.0))
        <> " credits per HP · select a part or chassis below to repair or sell it",
    ),
    html.div([attribute.class("table")], robots),
    view_stock(model),
    button_class(">>> Leave", "banner", Leave),
    view_garage(model),
  ])
}

/// What the shop sells, by kind; select one to see its cards, then buy it.
fn view_stock(model: Model) -> Element(Msg) {
  let run = model.run
  let s = model.scale
  let item = fn(label, stock, i) {
    button_class(
      "    " <> label,
      case model.pick == ForSale(stock, i) {
        True -> "picked"
        False -> ""
      },
      ClickForSale(stock, i),
    )
  }
  let group = fn(title, items) {
    case items {
      [] -> []
      _ -> [text("dim", "  " <> title), ..items]
    }
  }
  let parts =
    by_kind(run.shop.parts)
    |> list.map(fn(pair) {
      let #(i, p) = pair
      item(part_line(s, p), StockPart, i)
    })
  let robots =
    list.index_map(run.shop.robots, fn(o, i) {
      item(
        "Used "
          <> o.name
          <> " ("
          <> o.chassis.name
          <> ") · "
          <> string.join(list.map(o.parts, part.display_name), ", ")
          <> " · "
          <> int.to_string(shop.robot_price(o))
          <> " cr",
        StockRobot,
        i,
      )
    })
  let price_of = case model.pick {
    ForSale(StockPart, i) ->
      list.drop(run.shop.parts, i) |> list.first |> result.map(shop.part_price)
    ForSale(StockRobot, i) ->
      list.drop(run.shop.robots, i)
      |> list.first
      |> result.map(shop.robot_price)
    _ -> Error(Nil)
  }
  let actions = case price_of {
    Ok(cost) -> [
      html.div([attribute.class("actions")], [
        button("[Buy · " <> int.to_string(cost) <> " credits]", Buy),
        button("[Cancel]", Cancel),
      ]),
    ]
    Error(Nil) -> []
  }
  let rows =
    list.flatten([
      group("PARTS (new)", parts),
      group("ROBOTS (used)", robots),
    ])
  html.div([], [
    text("", "FOR SALE · select something to see its cards"),
    html.div([attribute.class("table")], case rows {
      [] -> [text("dim", "  sold out")]
      _ -> rows
    }),
    ..actions
  ])
}

/// "18 cards", or "13 cards (small deck)".
fn offer_deck(o: shop.Offer) -> String {
  deck_text(builder.deck_size(o.chassis, o.parts))
}

/// "18 cards", or with a warning below `builder.minimum_deck`.
fn deck_text(cards: Int) -> String {
  int.to_string(cards)
  <> " cards"
  <> case cards < builder.minimum_deck {
    True ->
      " · ⚠ small deck (under "
      <> int.to_string(builder.minimum_deck)
      <> "): the same few cards keep coming round"
    False -> ""
  }
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
    view_earnings(model),
    button_class(">>> To the hangar", "banner", ToHangar),
  ])
}

// Hangar (between runs)

fn view_hangar(model: Model) -> Element(Msg) {
  let assert Some(h) = model.hangar
  let p = model.profile
  let s = model.scale
  let picked = fn(yes) {
    case yes {
      True -> "picked"
      False -> ""
    }
  }
  // Found blueprints, to research.
  let found =
    list.map(p.found, fn(b) {
      button_class(
        "  "
          <> blueprint.describe(b)
          <> " · research "
          <> int.to_string(blueprint.research_cost(b))
          <> " Salvage",
        picked(h.pick == PickFound(b)),
        HangarSelect(PickFound(b)),
      )
    })
  // The design: its chassis and parts.
  let bot = design_bot(h.design)
  let installed =
    list.index_map(h.design.parts, fn(name, i) {
      let label = case blueprint.part(name) {
        Ok(c) -> part_line(s, c)
        Error(Nil) -> name
      }
      #(i, label)
    })
    |> list.map(fn(pair) {
      button_class(
        "    " <> pair.1,
        picked(h.pick == PickInstalled(pair.0)),
        HangarSelect(PickInstalled(pair.0)),
      )
    })
  let design_lines = case bot {
    Some(b) -> [
      text("", "    " <> weight_line(b)),
      text("", "    " <> mounts_line(b)),
    ]
    None -> []
  }
  let status = case profile.fabricate(p, h.design) {
    Ok(_) -> text("ally", "✓ ready to fabricate")
    Error(e) -> text("foe", "✗ " <> describe_profile_error(e))
  }
  // Researched blueprints: chassis to build on, parts to add.
  // Copies of a blueprint, and how many the design uses.
  let count = fn(b) {
    let have = profile.copies(p, b)
    let used = list.count(profile.needs(h.design), fn(n) { n == b })
    " · ×"
    <> int.to_string(have)
    <> case used {
      0 -> ""
      _ -> ", " <> int.to_string(used) <> " in the design"
    }
  }
  let unique = list.unique(p.researched)
  let researched_chassis =
    list.filter_map(unique, fn(b) {
      case b {
        ChassisBlueprint(name) ->
          case blueprint.chassis(name) {
            Ok(c) ->
              Ok(button_class(
                "    "
                  <> c.name
                  <> " · "
                  <> int.to_string(scale.value(s, c.hp))
                  <> " HP · max weight "
                  <> num(c.capacity)
                  <> " · weapon mounts "
                  <> string.join(list.map(c.weapon_mounts, num), ", ")
                  <> count(b),
                picked(h.pick == PickBlueprint(b)),
                HangarSelect(PickBlueprint(b)),
              ))
            Error(Nil) -> Error(Nil)
          }
        PartBlueprint(_) -> Error(Nil)
      }
    })
  let researched_parts =
    unique
    |> list.filter_map(fn(b) {
      case b {
        PartBlueprint(name) -> blueprint.part(name)
        ChassisBlueprint(_) -> Error(Nil)
      }
    })
    |> by_kind
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "    " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let b = PartBlueprint({ pair.1 }.name)
          button_class(
            "      " <> part_line(s, pair.1) <> count(b),
            picked(h.pick == PickBlueprint(b)),
            HangarSelect(PickBlueprint(b)),
          )
        })
      ]
    })
  let actions = case h.pick {
    NoHangarPick -> []
    PickFound(b) -> [
      button(
        "[Research · "
          <> int.to_string(blueprint.research_cost(b))
          <> " Salvage]",
        Research,
      ),
    ]
    PickBlueprint(PartBlueprint(_) as b) -> {
      let spare =
        profile.copies(p, b)
        > list.count(profile.needs(h.design), fn(n) { n == b })
      let copy = case p.copier {
        True -> [
          button(
            "[Copy it · " <> int.to_string(profile.copy_cost(b)) <> " Salvage]",
            CopyBlueprint,
          ),
        ]
        False -> []
      }
      case spare {
        True -> [button("[Add to the design]", AddPart), ..copy]
        False -> [
          text(
            "dim",
            "  every copy is in the design: each blueprint makes one part. Find another"
              <> case p.copier {
              True -> ", or copy it."
              False -> ", or research the blueprint copier."
            },
          ),
          ..copy
        ]
      }
    }
    PickBlueprint(ChassisBlueprint(name)) ->
      case name == h.design.chassis {
        True -> [text("dim", "  the design is built on it")]
        False -> [button("[Build the design on it]", UseChassis)]
      }
    PickInstalled(_) -> [button("[Remove from the design]", RemovePart)]
  }
  let actions = case h.pick {
    NoHangarPick -> []
    _ -> list.append(actions, [button("[Cancel]", HangarSelect(NoHangarPick))])
  }
  // The selected thing's cards.
  let selected = case h.pick {
    PickFound(b) | PickBlueprint(b) -> blueprint_component(b)
    PickInstalled(i) ->
      list.drop(h.design.parts, i)
      |> list.first
      |> result.try(blueprint.part)
      |> option.from_result
    NoHangarPick -> None
  }
  let preview = case selected {
    Some(c) -> preview_section(model, "", c)
    None ->
      text(
        "dim",
        "Select a blueprint or a part of the design to see its cards.",
      )
  }
  html.div([], [
    text(
      "",
      "HANGAR · the truck carries "
        <> int.to_string(p.truck)
        <> " robots · the fabricator builds "
        <> int.to_string(p.fabricator)
        <> case p.fabricator {
        1 -> " robot"
        _ -> " robots"
      }
        <> " for each run, one part per blueprint (plain parts, no attributes)",
    ),
    button_class(">>> Start a run", "banner", StartRun),
    html.div([attribute.class("garage")], [
      html.div([], [
        text("", "FOUND BLUEPRINTS · research them with Salvage"),
        html.div([attribute.class("table")], case found {
          [] -> [
            text(
              "dim",
              "  none yet: strong enemies sometimes drop one, bosses always",
            ),
          ]
          _ -> found
        }),
        text("", "DESIGN · what the fabricator builds"),
        html.div([attribute.class("table")], [
          text("ally", "  " <> h.design.name <> " (" <> h.design.chassis <> ")"),
          ..list.flatten([
            design_lines,
            case installed {
              [] -> [text("dim", "    no parts")]
              _ -> installed
            },
            [status],
          ])
        ]),
        text("", "FABRICATOR"),
        html.div([attribute.class("table")], [
          case p.copier {
            True ->
              text(
                "dim",
                "  Blueprint copier: select a researched blueprint to copy it, at twice its research cost",
              )
            False ->
              button(
                "  Research the blueprint copier · "
                  <> int.to_string(profile.copier_cost)
                  <> " Salvage: copy researched blueprints for twice their research cost",
                ResearchCopier,
              )
          },
        ]),
        text(
          "",
          "RESEARCHED BLUEPRINTS · each makes one part or chassis (×copies)",
        ),
        html.div([attribute.class("table")], [
          text("dim", "    CHASSIS"),
          ..list.append(researched_chassis, researched_parts)
        ]),
        html.div([attribute.class("actions")], actions),
      ]),
      html.div([attribute.class("preview")], [preview]),
    ]),
  ])
}

/// The design as a robot, to show its weight and mounts (if its chassis
/// and parts exist; research and legality aside).
fn design_bot(d: profile.Design) -> Option(Bot) {
  case blueprint.chassis(d.chassis), list.try_map(d.parts, blueprint.part) {
    Ok(chassis), Ok(parts) -> Some(state.Bot(name: d.name, chassis:, parts:))
    _, _ -> None
  }
}

/// What a blueprint makes, as a component (a chassis as its body).
fn blueprint_component(b: Blueprint) -> Option(Component) {
  case b {
    PartBlueprint(name) -> blueprint.part(name) |> option.from_result
    ChassisBlueprint(name) ->
      blueprint.chassis(name) |> result.map(builder.body) |> option.from_result
  }
}

/// What the run that just ended pays out.
fn view_earnings(model: Model) -> Element(Msg) {
  let e = profile.earnings(model.profile, model.run)
  let lines =
    list.flatten([
      [
        "SALVAGE · +"
        <> int.to_string(e.salvage)
        <> " (battles won, levels reached and credits left)",
      ],
      case e.bonus {
        0 -> []
        b -> [
          "  +" <> int.to_string(b) <> " for beating a boss for the first time",
        ]
      },
      case e.found {
        [] -> []
        found -> [
          "BLUEPRINTS FOUND · "
          <> string.join(list.map(found, blueprint.describe), ", ")
          <> " · research them in the hangar",
        ]
      },
    ])
  text("ally", string.join(lines, "\n"))
}

// Garage

fn view_garage(model: Model) -> Element(Msg) {
  let run = model.run
  let #(installed, spare, drafted, chassis_pick) = case model.pick {
    Picked(installed, spare) -> #(installed, spare, [], None)
    Draft(chassis, parts, _) -> #(None, None, parts, Some(chassis))
    OwnChassis(_) | ForSale(..) -> #(None, None, [], None)
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
        text("ally", bot_line(model.scale, bot)),
        text("", "    " <> weight_line(bot)),
        text("", "    " <> mounts_line(bot)),
        button_class(
          "    " <> own_chassis_line(model.scale, bot),
          picked(model.pick == OwnChassis(r)),
          ClickOwnChassis(r),
        ),
        ..by_kind(bot.parts)
        |> list.map(fn(pair) {
          let #(i, p) = pair
          button_class(
            "    " <> part_line(model.scale, p),
            picked(installed == Some(#(r, i))),
            ClickInstalled(r, i),
          )
        })
      ])
    })
  // Spares grouped by kind, a heading per kind.
  let spares =
    by_kind(run.parts)
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, p) = pair
          button_class(
            "    " <> part_line(model.scale, p),
            picked(spare == Some(i) || list.contains(drafted, i)),
            ClickSpare(i),
          )
        })
      ]
    })
  let chassis =
    list.index_map(run.chassis, fn(c, i) {
      button_class(
        "  "
          <> c.name
          <> " chassis · "
          <> int.to_string(scale.value(model.scale, builder.chassis_hp(c)))
          <> " HP · max weight "
          <> num(c.capacity)
          <> " · weapon mounts "
          <> string.join(
          list.map(builder.mounts(c, []), fn(m) { num(m.0) }),
          ", ",
        ),
        picked(chassis_pick == Some(i)),
        ClickChassis(i),
      )
    })
  let at_shop = case run.phase {
    state.Repairing(_) -> True
    _ -> False
  }
  // At a repair shop: repair what's selected, if it's worn.
  let repair = case at_shop, repair_target(model.pick) {
    True, Some(target) ->
      case state.repair_one_price(run, target) {
        Ok(cost) if cost > 0 -> [
          button(
            "[Repair · " <> int.to_string(cost) <> " credits]",
            RepairPicked,
          ),
        ]
        _ -> []
      }
    _, _ -> []
  }
  // At a workshop: upgrade what's selected.
  let actions_upgrade = case run.phase, upgrade_target(model.pick) {
    state.Upgrading(_), Some(target) ->
      case state.target_part(run, target) {
        Ok(p) ->
          case upgrade.can_upgrade(p) {
            True -> [button("[Upgrade]", UpgradePicked)]
            False -> [text("dim", "  every card is at its best")]
          }
        Error(_) -> []
      }
    _, _ -> []
  }
  let actions = case model.pick {
    Picked(Some(_), Some(_)) -> [button("[Swap them]", Swap)]
    Picked(Some(_), None) -> [button("[Remove part]", Remove), ..repair]
    Picked(None, Some(spare)) ->
      list.flatten([
        list.index_map(run.robots, fn(bot, r) {
          button("[Install on " <> bot.name <> "]", Install(r))
        }),
        repair,
        case at_shop, list.drop(run.parts, spare) {
          True, [p, ..] -> [
            button(
              "[Sell · +" <> int.to_string(price.sell(p)) <> " credits]",
              SellPicked,
            ),
          ]
          _, _ -> []
        },
      ])
    Picked(None, None) -> []
    Draft(..) -> [button("[Assemble robot]", Assemble)]
    OwnChassis(_) -> repair
    // Bought from the shop's own list (see view_shop).
    ForSale(..) -> []
  }
  let actions = case model.pick {
    Picked(None, None) -> []
    _ -> list.flatten([actions_upgrade, actions, [button("[Cancel]", Cancel)]])
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
      ..fit_lines(model)
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
    ForSale(StockPart, i) ->
      case list.drop(run.shop.parts, i) {
        [p, ..] -> [preview_section(model, "FOR SALE", p)]
        [] -> []
      }
    ForSale(StockRobot, i) ->
      case list.drop(run.shop.robots, i) {
        [o, ..] -> [
          text("", "FOR SALE: " <> o.name <> " · " <> offer_deck(o)),
          preview_section(model, "CHASSIS", builder.body(o.chassis)),
          ..list.map(o.parts, preview_section(model, "PART", _))
        ]
        [] -> []
      }
    OwnChassis(r) ->
      case list.drop(run.robots, r) {
        [bot, ..] -> [preview_section(model, "", builder.body(bot.chassis))]
        [] -> []
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
      list.index_map(list.zip(cards, part.plain_cards(p)), fn(pair, i) {
        let #(c, plain) = pair
        let shown = plain_card(model, c)
        // An attribute: what it is and what it does to the plain card.
        case part.attribute_at(p, i) {
          Ok(#(word, good)) ->
            card_view.noted(
              shown,
              word <> ": " <> card_view.change_text(model.scale, plain, c),
              good,
            )
          Error(Nil) -> shown
        }
      }),
    ),
  ])
}

fn plain_card(model: Model, c: card.Card) -> Element(Msg) {
  card_view.view(
    model.scale,
    c,
    current: c.value,
    key: None,
    dim: False,
    on_click: None,
    charge: None,
  )
}

/// The last upgrade: the card before and after, with what changed.
fn view_upgrade(model: Model) -> Element(Msg) {
  case model.upgraded {
    None -> text("", "")
    Some(#(name, change)) ->
      html.div([], [
        text(
          "",
          "UPGRADED "
            <> name
            <> ": "
            <> change.attribute
            <> " added to "
            <> change.plain.name
            <> case change.replaced {
            Some(old) -> " (replacing " <> old <> ")"
            None -> ""
          },
        ),
        card_view.row([
          card_view.noted(plain_card(model, change.before), "before", False),
          card_view.noted(
            plain_card(model, change.after),
            "after: "
              <> card_view.change_text(model.scale, change.before, change.after),
            True,
          ),
        ]),
      ])
  }
}

fn hint(pick: Pick) -> String {
  case pick {
    Picked(None, None) ->
      "select a part or spare to see its cards; a chassis to build a robot"
    Picked(Some(_), None) -> "remove it, or select a spare to swap it for"
    Picked(None, Some(_)) -> "install it, or select an installed part to swap"
    Picked(Some(_), Some(_)) -> "swap them, or change either selection"
    Draft(..) -> "select spare parts for the new robot, then assemble"
    OwnChassis(_) -> "the chassis' own cards; it can be repaired at a shop"
    ForSale(..) -> "on sale: buy it above, or select something else"
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

/// Parts with their index, ordered by kind (weapons, defences, utilities,
/// batteries, armor), keeping their order within a kind.
fn by_kind(parts: List(Component)) -> List(#(Int, Component)) {
  parts
  |> list.index_map(fn(p, i) { #(i, p) })
  |> list.sort(fn(a, b) {
    case int.compare(kind_rank({ a.1 }.kind), kind_rank({ b.1 }.kind)) {
      order.Eq -> int.compare(a.0, b.0)
      other -> other
    }
  })
}

fn kind_rank(kind: part.Kind) -> Int {
  case kind {
    part.Body -> 0
    part.Weapon -> 1
    part.Defence -> 2
    part.Utility -> 3
    part.Battery -> 4
    part.Armor -> 5
  }
}

fn kind_plural(kind: part.Kind) -> String {
  case kind {
    part.Body -> "chassis"
    part.Weapon -> "weapons"
    part.Defence -> "defences"
    part.Utility -> "utilities"
    part.Battery -> "batteries"
    part.Armor -> "armor"
  }
}

/// "Frame chassis · HP 28/45"
fn own_chassis_line(s: Scale, bot: Bot) -> String {
  bot.chassis.name
  <> " chassis · HP "
  <> int.to_string(scale.value(s, builder.chassis_hp(bot.chassis)))
  <> "/"
  <> int.to_string(scale.value(s, bot.chassis.hp))
}

/// "Weight 11 of max 12 · 1 free · 18 cards" (with a warning for a deck
/// below the minimum).
fn weight_line(bot: Bot) -> String {
  let used = part.total_weight(bot.parts)
  "Weight "
  <> num(used)
  <> " of max "
  <> num(bot.chassis.capacity)
  <> " · "
  <> num(float.max(0.0, bot.chassis.capacity -. used))
  <> " free · "
  <> deck_text(builder.deck_size(bot.chassis, bot.parts))
}

/// "Weapon mounts: [4] Laser (3) · [4] empty": a weapon fits a mount at
/// least as big as its weight.
fn mounts_line(bot: Bot) -> String {
  "Weapon mounts: "
  <> builder.mounts(bot.chassis, bot.parts)
  |> list.map(fn(m) {
    "["
    <> num(m.0)
    <> "] "
    <> case m.1 {
      Some(w) -> part.display_name(w) <> " (" <> num(part.weight(w)) <> ")"
      None -> "empty"
    }
  })
  |> string.join(" · ")
}

/// What the selected change would do to each robot it could apply to:
/// "✓ fits on Tinker" or "✗ Tinker: Too heavy: 14, max weight 12".
fn fit_lines(model: Model) -> List(Element(Msg)) {
  let run = model.run
  let line = fn(name, result) {
    case result {
      Ok(_) -> text("ally", "✓ " <> name)
      Error(e) -> text("foe", "✗ " <> describe_error(e))
    }
  }
  case model.pick {
    Picked(None, Some(spare)) ->
      list.index_map(run.robots, fn(bot, r) {
        line("fits on " <> bot.name, state.install(run, r, spare))
      })
    Picked(Some(#(r, i)), Some(spare)) -> [
      line("the swap works", state.swap(run, r, i, spare)),
    ]
    Picked(Some(#(r, i)), None) -> [
      line("it can be removed", state.uninstall(run, r, i)),
    ]
    _ -> []
  }
}

/// "Broken plating · armor · weight 2 · HP 0/25 · 25 cr"
fn part_line(s: Scale, p: Component) -> String {
  part.display_name(p)
  <> " · "
  <> part.kind_name(p.kind)
  <> " · weight "
  <> num(part.weight(p))
  <> case p.kind {
    part.Armor ->
      " · HP "
      <> int.to_string(scale.value(s, part.remaining_hp(p)))
      <> "/"
      <> int.to_string(scale.value(s, part.hp(p)))
      <> case wear.is_broken(p) {
        True -> " BROKEN"
        False -> ""
      }
    part.Battery ->
      " · stores " <> int.to_string(scale.energy(s, part.energy_cap(p)))
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
.cardbox { width: 9.5rem; border: 2px solid; border-radius: 7px;
  padding: 5px 7px; font-size: 12px; display: flex; flex-direction: column; gap: 3px;
  box-sizing: border-box; }
.noted { display: flex; flex-direction: column; gap: 2px; width: 9.5rem; }
.cardnote { font-size: 11px; padding: 0 2px; line-height: 1.25; height: 2.5em; overflow: hidden;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.aims { display: flex; align-items: center; gap: 6px; height: 1.1rem; padding: 0 2px; font-size: 10px; opacity: 0.85; }
.aimdots { display: flex; gap: 4px; }
.aimbot { width: 12px; height: 9px; border-radius: 2px; background: #4a4a4a; margin-right: 3px; }
.aimbot.enemy { background: #e06a5a; }
.aimbot.own { background: #6ad06a; }
.aimdot { width: 8px; height: 8px; border-radius: 50%; background: #4a4a4a; }
.aimdot.enemy { background: #e06a5a; }
.aimdot.own { background: #6ad06a; }
.aimdot.both { background: linear-gradient(90deg, #e06a5a 50%, #6ad06a 50%); }
.aimdot.random { background: transparent; box-sizing: border-box; border: 2px solid #e06a5a; }
.aimdot.own.random { border-color: #6ad06a; }
.aimdot.both.random { border-color: #e06a5a #6ad06a #6ad06a #e06a5a; }
.aimlabel { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: #c0c0c0; }
.cardnote.good { color: #8fd18f; }
.cardnote.bad { color: #e08a7a; }
.cardbox.clickable:hover { filter: brightness(1.35); }
.cardhead { display: flex; justify-content: space-between; font-size: 10px; letter-spacing: 0.05em; opacity: 0.85;
  height: 1.3em; white-space: nowrap; overflow: hidden; }
.cardcost { font-weight: bold; color: #f0d060; }
/* Every line has a fixed height (two-line ones clamped), so cards don't
   change size with their text. */
.clamp2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.cardname { font-weight: bold; font-size: 13px; line-height: 1.2; height: 2.4em; }
.cardvalue { font-size: 20px; font-weight: bold; line-height: 1.2; height: 1.2em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cardtarget { font-size: 11px; line-height: 1.25; height: 2.5em; }
.cardtags { font-size: 10px; opacity: 0.7; white-space: pre-wrap; line-height: 1.25; height: 2.5em; overflow: hidden;
  display: flex; flex-direction: column; justify-content: flex-end; }
.cardbox.attack { border-color: #e06a5a; background: #2a1614; color: #f2c2ba; }
.cardbox.defence { border-color: #5a9ae0; background: #141e2a; color: #bcd4f2; }
.cardbox.buff { border-color: #6ad06a; background: #142a16; color: #c2f0c2; }
.charge { position: relative; height: 0.9rem; margin-top: 0.3rem; border: 1px solid currentColor; border-radius: 3px; overflow: hidden; }
.chargefill { height: 100%; background: rgba(240, 208, 96, 0.35); }
.chargefill.ready { background: rgba(240, 208, 96, 0.8); }
.chargelabel { position: absolute; inset: 0; text-align: center; font-size: 10px; line-height: 0.9rem; color: #fff; }
.cardbox.special { border-color: #9a9a9a; background: #1e1e1e; color: #d0d0d0; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; white-space: pre-wrap; }
.card:hover { background: #1f2a1f; }
.picked { background: #2a3a2a; }
"
