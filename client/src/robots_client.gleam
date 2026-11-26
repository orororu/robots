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
import robots/run/save
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
    /// Between runs: the hangar, where Data is spent and the starting
    /// robot designed. `run` is the last run (or a placeholder) meanwhile.
    hangar: Option(Hangar),
    /// The start menu: continue the saved run, or a new one.
    menu: Bool,
    /// The run saved in the browser, while the menu can continue it.
    saved: Option(Run),
    run: Run,
    /// The battle being fought, if any.
    battle: Option(Battle),
    /// How the last battle went, shown until the player continues.
    report: Option(Report),
    /// Battle order for the next battle: indexes into `run.robots`.
    order: List(Int),
    /// What's selected in the garage.
    pick: Pick,
    /// The open tab of the garage (the shop's counter first, at a shop).
    tab: Tab,
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
  /// `designs`: the robots the fabricator builds, as edited (saved on
  /// starting a run).
  Hangar(designs: List(profile.Design), pick: HangarPick, screen: HangarScreen)
}

/// The hangar's screens: an overview, the research lab, the garage.
type HangarScreen {
  Overview
  Lab
  /// A design's room, like a run's robot tab.
  Room(Int)
  /// Make a new design from a spare chassis and components.
  NewRoom
}

type HangarPick {
  NoHangarPick
  /// A found blueprint, to research or sell.
  PickFound(Blueprint)
  /// In the garage, as in a run's: a part of the design and/or one of the
  /// fabricator's spare components (by index in `spare_parts`).
  PickGarage(installed: Option(Int), spare: Option(Int))
  /// One of the fabricator's spare chassis (in `spare_chassis`).
  PickSpareChassis(Int)
  /// The design's own chassis, to see its cards.
  PickDesignChassis
  /// In the new robot room: a spare chassis and the spare components
  /// chosen (indexes into `spare_chassis` and `spare_parts`).
  PickDraft(chassis: Int, parts: List(Int))
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
  /// A spare chassis, to rebuild the open tab's robot on.
  SpareChassis(index: Int)
}

/// The tabs over the garage: the shop's counter (at a repair shop), a
/// room per robot, and one to assemble a new robot.
type Tab {
  ShopTab
  RobotTab(robot: Int)
  NewRobotTab
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
    menu: False,
    saved: None,
    run:,
    battle: None,
    report: None,
    order: default_order(run),
    pick: no_pick,
    tab: ShopTab,
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
    Model(
      ..new_model(
        state.new(browser.random_seed()),
        profile,
        None,
        browser.now(),
      ),
      menu: True,
      saved: save.decode(browser.load_run()) |> option.from_result,
    )
  #(model, subscriptions)
}

fn hangar_for(p: Profile) -> Hangar {
  Hangar(
    designs: list.take(p.designs, p.fabricator),
    pick: NoHangarPick,
    screen: Overview,
  )
}

/// The open room's design index (the first design outside a room).
fn room_index(h: Hangar) -> Int {
  case h.screen {
    Room(i) -> i
    _ -> 0
  }
}

fn room(h: Hangar) -> profile.Design {
  at(h.designs, room_index(h))
  |> option.unwrap(profile.Design("Robot", "Frame", []))
}

/// Change the open room's design; clears the selection.
fn set_room(h: Hangar, d: profile.Design) -> Hangar {
  let i = room_index(h)
  Hangar(
    ..h,
    designs: list.index_map(h.designs, fn(x, j) {
      case i == j {
        True -> d
        False -> x
      }
    }),
    pick: NoHangarPick,
  )
}

/// Save the profile and go to the hangar.
fn open_hangar(model: Model, p: Profile) -> Model {
  browser.save_profile(profile.encode(p))
  // The run is over and paid out: nothing to continue.
  browser.save_run("")
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
  SellBlueprint
  // The start screen
  ContinueRun
  NewGame
  ToMenu
  HangarGo(screen: HangarScreen)
  HangarInstalled(index: Int)
  HangarSpare(index: Int)
  HangarSpareChassis(index: Int)
  HangarOwnChassis
  AddPart
  RemovePart
  SwapPart
  UseChassis
  AssembleDesign
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
  GoTab(Tab)
  /// Rebuild the open tab's robot on the selected spare chassis.
  Rebuild
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
                hangar: Some(Hangar(..h, pick: NoHangarPick)),
                news: "Researched "
                  <> blueprint.describe(b)
                  <> ": it's in the fabricator.",
              )
            }
            Error(e) -> flash(model, describe_profile_error(e))
          }
        _ -> model
      }
    HangarInstalled(i) ->
      update_hangar(model, fn(h) {
        let pick = case h.pick {
          PickGarage(installed, spare) ->
            PickGarage(toggle(installed, i), spare)
          _ -> PickGarage(Some(i), None)
        }
        Hangar(..h, pick: tidy(pick))
      })
    HangarSpare(i) ->
      update_hangar(model, fn(h) {
        let pick = case h.pick {
          PickDraft(c, parts) ->
            PickDraft(c, case list.contains(parts, i) {
              True -> list.filter(parts, fn(x) { x != i })
              False -> list.append(parts, [i])
            })
          PickGarage(installed, spare) ->
            PickGarage(installed, toggle(spare, i))
          _ -> PickGarage(None, Some(i))
        }
        Hangar(..h, pick: tidy(pick))
      })
    HangarSpareChassis(i) ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.screen, h.pick {
          NewRoom, PickDraft(c, _) if c == i -> NoHangarPick
          NewRoom, _ -> PickDraft(i, [])
          _, PickSpareChassis(c) if c == i -> NoHangarPick
          _, _ -> PickSpareChassis(i)
        })
      })
    HangarOwnChassis ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.pick == PickDesignChassis {
          True -> NoHangarPick
          False -> PickDesignChassis
        })
      })
    AddPart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(None, Some(j)) ->
            case at(spare_parts(model.profile, h.designs), j) {
              Some(p) ->
                set_room(
                  h,
                  profile.Design(..d, parts: list.append(d.parts, [p])),
                )
              None -> h
            }
          _ -> h
        }
      })
    RemovePart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(Some(i), None) ->
            set_room(
              h,
              profile.Design(
                ..d,
                parts: list.append(
                  list.take(d.parts, i),
                  list.drop(d.parts, i + 1),
                ),
              ),
            )
          _ -> h
        }
      })
    SwapPart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(Some(i), Some(j)) ->
            case at(spare_parts(model.profile, h.designs), j) {
              Some(p) ->
                set_room(
                  h,
                  profile.Design(
                    ..d,
                    parts: list.flatten([
                      list.take(d.parts, i),
                      [p],
                      list.drop(d.parts, i + 1),
                    ]),
                  ),
                )
              None -> h
            }
          _ -> h
        }
      })
    // Rebuild the design on a spare chassis: the parts that fit stay, the
    // rest go back to the fabricator's spares.
    UseChassis ->
      case model.hangar {
        Some(Hangar(pick: PickSpareChassis(i), ..) as h) ->
          case
            option.then(
              at(spare_chassis(model.profile, h.designs), i),
              fn(name) { option.from_result(blueprint.chassis(name)) },
            )
          {
            Some(c) -> {
              let d = room(h)
              let #(kept, dropped) = builder.fit(c, d.parts)
              use <- bool.lazy_guard(
                result.is_error(builder.build(d.name, c, kept)),
                fn() {
                  case builder.build(d.name, c, kept) {
                    Error(errors) ->
                      flash(
                        model,
                        string.join(
                          list.map(errors, builder.describe_error),
                          "; ",
                        ),
                      )
                    Ok(_) -> model
                  }
                },
              )
              let message =
                "Rebuilt "
                <> d.name
                <> " on the "
                <> c.name
                <> "."
                <> case dropped {
                  [] -> ""
                  _ ->
                    " Back to the spares: "
                    <> string.join(list.map(dropped, part.display_name), ", ")
                    <> "."
                }
              flash(
                Model(
                  ..model,
                  hangar: Some(set_room(
                    h,
                    profile.Design(..d, chassis: c.name, parts: kept),
                  )),
                ),
                message,
              )
            }
            None -> model
          }
        _ -> model
      }
    AssembleDesign ->
      case model.hangar {
        Some(Hangar(pick: PickDraft(c, parts), ..) as h) -> {
          let spares = spare_parts(model.profile, h.designs)
          case at(spare_chassis(model.profile, h.designs), c) {
            Some(chassis) -> {
              let d =
                profile.Design(
                  name: "Robot " <> int.to_string(list.length(h.designs) + 1),
                  chassis:,
                  parts: list.filter_map(parts, fn(j) {
                    at(spares, j) |> option.to_result(Nil)
                  }),
                )
              case profile.fabricate(model.profile, d) {
                Ok(_) ->
                  Model(
                    ..model,
                    hangar: Some(Hangar(
                      designs: list.append(h.designs, [d]),
                      pick: NoHangarPick,
                      screen: Room(list.length(h.designs)),
                    )),
                  )
                Error(e) -> flash(model, describe_profile_error(e))
              }
            }
            None -> model
          }
        }
        _ -> model
      }
    SellBlueprint ->
      case model.hangar {
        Some(Hangar(pick: PickFound(b), ..) as h) ->
          sell_blueprint(model, h, profile.sell_found(model.profile, b), b)
        Some(Hangar(pick: PickGarage(None, Some(j)), ..) as h) ->
          case at(spare_parts(model.profile, h.designs), j) {
            Some(c) -> {
              let b = PartBlueprint(c)
              sell_blueprint(
                model,
                h,
                profile.sell_researched(model.profile, b),
                b,
              )
            }
            None -> model
          }
        Some(Hangar(pick: PickSpareChassis(i), ..) as h) ->
          case at(spare_chassis(model.profile, h.designs), i) {
            Some(name) -> {
              let b = ChassisBlueprint(name)
              sell_blueprint(
                model,
                h,
                profile.sell_researched(model.profile, b),
                b,
              )
            }
            None -> model
          }
        _ -> model
      }
    StartRun -> start_run(model)
    ContinueRun ->
      case model.saved {
        Some(run) ->
          Model(
            ..new_model(run, model.profile, None, model.now),
            news: "Run continued.",
          )
        None -> model
      }
    // A saved run is abandoned: paid out like a lost one.
    NewGame ->
      case model.saved {
        Some(run) ->
          open_hangar(
            Model(..model, menu: False, saved: None),
            profile.finish(model.profile, run),
          )
        None ->
          Model(..model, menu: False, hangar: Some(hangar_for(model.profile)))
      }
    ToMenu -> Model(..model, menu: True)
    HangarGo(screen) ->
      update_hangar(model, fn(h) { Hangar(..h, screen:, pick: NoHangarPick) })
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
    Leave -> attempt(Model(..model, tab: ShopTab), state.leave(model.run), "")
    GoTab(tab) -> Model(..model, tab:, pick: no_pick)
    Rebuild ->
      case model.pick, current_tab(model) {
        SpareChassis(c), RobotTab(r) ->
          case state.rebuild(model.run, r, c) {
            Ok(#(run, dropped)) -> {
              let message =
                case dropped {
                  [] -> "Rebuilt: every part fits."
                  _ ->
                    "Rebuilt. To the spares: "
                    <> string.join(list.map(dropped, part.display_name), ", ")
                    <> "."
                }
                <> " The old chassis is a spare."
              flash(attempt(model, Ok(run), message), message)
            }
            Error(e) -> attempt(model, Error(e), "")
          }
        _, _ -> model
      }
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
        Draft(..) | OwnChassis(_) | ForSale(..) | SpareChassis(_) -> None
      }
      let installed = case model.pick {
        Picked(Some(picked), _) if picked == #(robot, p) -> None
        _ -> Some(#(robot, p))
      }
      Model(..model, pick: Picked(installed, spare))
    }
    ClickSpare(spare) -> click_spare(model, spare)
    ClickChassis(chassis) ->
      Model(..model, pick: case current_tab(model), model.pick {
        NewRobotTab, Draft(c, _, _) if c == chassis -> no_pick
        NewRobotTab, _ -> Draft(chassis, [], None)
        _, SpareChassis(c) if c == chassis -> no_pick
        _, _ -> SpareChassis(chassis)
      })
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
          let after =
            attempt(model, state.assemble(model.run, name, chassis, parts), "")
          // Open the new robot's room.
          case list.length(after.run.robots) > list.length(model.run.robots) {
            True ->
              Model(..after, tab: RobotTab(list.length(after.run.robots) - 1))
            False -> after
          }
        }
        _ -> model
      }
    Cancel -> Model(..model, pick: no_pick)
  }
  #(model, effect.none())
}

fn toggle(selected: Option(Int), i: Int) -> Option(Int) {
  case selected == Some(i) {
    True -> None
    False -> Some(i)
  }
}

fn tidy(pick: HangarPick) -> HangarPick {
  case pick {
    PickGarage(None, None) -> NoHangarPick
    _ -> pick
  }
}

fn at(items: List(a), i: Int) -> Option(a) {
  list.drop(items, i) |> list.first |> option.from_result
}

/// The fabricator's components the design doesn't use: one entry per
/// copy, in research order (each installed part takes one copy away).
fn spare_parts(p: Profile, designs: List(profile.Design)) -> List(Component) {
  let made =
    list.filter_map(p.researched, fn(b) {
      case b {
        PartBlueprint(c) -> Ok(c)
        ChassisBlueprint(_) -> Error(Nil)
      }
    })
  list.fold(list.flat_map(designs, fn(d) { d.parts }), made, remove_first)
}

/// The fabricator's chassis the design isn't built on.
fn spare_chassis(p: Profile, designs: List(profile.Design)) -> List(String) {
  let made =
    list.filter_map(p.researched, fn(b) {
      case b {
        ChassisBlueprint(name) -> Ok(name)
        PartBlueprint(_) -> Error(Nil)
      }
    })
  list.fold(list.map(designs, fn(d) { d.chassis }), made, remove_first)
}

fn remove_first(items: List(a), item: a) -> List(a) {
  case items {
    [] -> []
    [x, ..rest] if x == item -> rest
    [x, ..rest] -> [x, ..remove_first(rest, item)]
  }
}

/// Sell a blueprint and save; keep it selected while copies are left.
fn sell_blueprint(
  model: Model,
  h: Hangar,
  result: Result(Profile, profile.Error),
  b: Blueprint,
) -> Model {
  case result {
    Ok(p) -> {
      browser.save_profile(profile.encode(p))
      // Indexes into the spares shift after a sale: clear the selection.
      let left = case h.pick {
        PickFound(_) -> list.contains(p.found, b)
        _ -> False
      }
      Model(
        ..model,
        profile: p,
        hangar: Some(
          Hangar(..h, pick: case left {
            True -> h.pick
            False -> NoHangarPick
          }),
        ),
        news: "Sold " <> blueprint.describe(b) <> ".",
      )
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
        use p <- result.try(
          list.index_fold(h.designs, Ok(model.profile), fn(acc, d, i) {
            result.try(acc, profile.set_design(_, i, d))
          }),
        )
        use run <- result.map(profile.start(p, browser.random_seed()))
        #(p, run)
      }
      case started {
        Ok(#(p, run)) -> {
          browser.save_profile(profile.encode(p))
          keep(run)
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
    profile.InUse(b) ->
      "Every "
      <> blueprint.describe(b)
      <> " in the fabricator is in the design."
    profile.NotEnoughCopies(blueprint: b, have:, need:) ->
      "Needs "
      <> int.to_string(need)
      <> " "
      <> blueprint.describe(b)
      <> "; the fabricator has "
      <> int.to_string(have)
      <> ". Find another blueprint in a run."
    profile.NotEnoughData(cost:, data:) ->
      "Costs "
      <> int.to_string(cost)
      <> " Data; you have "
      <> int.to_string(data)
      <> "."
    profile.NotResearched(b) ->
      blueprint.describe(b)
      <> " isn't in the fabricator: research its blueprint in the research lab."
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
    Ok(run) -> {
      keep(run)
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
    }
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
    OwnChassis(_) | ForSale(..) | SpareChassis(_) ->
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
          keep(run)
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

/// Save the run, so a reload continues it.
fn keep(run: Run) -> Nil {
  browser.save_run(save.encode(run))
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
      <> " scrap; you have "
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
      <> " scrap. Loot: "
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
      _, _ if model.menu -> view_menu(model)
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
  use <- bool.lazy_guard(model.menu, fn() {
    "ROBOTS · "
    <> int.to_string(model.profile.data)
    <> " Data · "
    <> int.to_string(model.profile.runs)
    <> case model.profile.runs {
      1 -> " run played"
      _ -> " runs played"
    }
  })
  use <- bool.lazy_guard(model.hangar != None, fn() {
    "ROBOTS · HANGAR · "
    <> int.to_string(model.profile.data)
    <> " Data · "
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
  <> " scrap · "
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
            <> " scrap\n"
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
    map.RepairShop -> " · repair your robots for scrap"
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
  case current_tab(model) {
    ShopTab -> html.div([], [garage_tabs(model), view_counter(model)])
    _ ->
      html.div([], [
        view_garage(model),
        button_class(">>> Leave", "banner", Leave),
      ])
  }
}

/// The shop's counter: repair the robots, buy, sell spare parts. The
/// garage (installing, swapping, assembling) is its own screen.
fn view_counter(model: Model) -> Element(Msg) {
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
              <> " scrap",
            Repair(r),
          )
      }
    })
  let selling = case model.pick {
    Picked(None, Some(i)) -> Some(i)
    _ -> None
  }
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
            "    "
              <> part_line(s, p)
              <> " · sells for "
              <> int.to_string(price.sell(p)),
            case selling == Some(i) {
              True -> "picked"
              False -> ""
            },
            ClickSpare(i),
          )
        })
      ]
    })
  let sell_actions = case selling {
    Some(i) ->
      case list.drop(run.parts, i) {
        [p, ..] -> [
          html.div([attribute.class("actions")], [
            button(
              "[Sell · +" <> int.to_string(price.sell(p)) <> " scrap]",
              SellPicked,
            ),
            button("[Cancel]", Cancel),
          ]),
        ]
        [] -> []
      }
    None -> []
  }
  html.div([], [
    text(
      "",
      "REPAIR SHOP · "
        <> int.to_string(price.repair(1.0) / scale.value(s, 1.0))
        <> " scrap per HP · repair one part or chassis in the Garage tab",
    ),
    html.div([attribute.class("table")], robots),
    html.div([attribute.class("garage")], [
      html.div([], [
        view_stock(model),
        text("", "SELL · your spare parts; select one to see its cards"),
        html.div([attribute.class("table")], case spares {
          [] -> [text("dim", "  none")]
          _ -> spares
        }),
        ..sell_actions
      ]),
      view_selected(model),
    ]),
    button_class(">>> Leave", "banner", Leave),
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
          <> " scrap",
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
        button("[Buy · " <> int.to_string(cost) <> " scrap]", Buy),
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
      <> "): the robot can malfunction"
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

// The start menu

fn view_menu(model: Model) -> Element(Msg) {
  let continue = case model.saved {
    Some(run) -> {
      let robots = run.robots |> list.map(fn(b) { b.name }) |> string.join(", ")
      let where = case run.phase {
        state.Over -> "over, not paid out yet"
        state.Fighting(_) -> "before a battle"
        state.Repairing(_) -> "at a repair shop"
        state.Upgrading(_) -> "at a workshop"
        state.Choosing -> "on the map"
      }
      [
        button_class(">>> Continue", "banner", ContinueRun),
        text(
          "dim",
          "    level "
            <> int.to_string(run.level)
            <> ", "
            <> where
            <> " · "
            <> case robots {
            "" -> "no robots left"
            _ -> robots
          }
            <> " · "
            <> int.to_string(run.money)
            <> " scrap · "
            <> int.to_string(list.length(run.wins))
            <> " battles won",
        ),
      ]
    }
    None -> [text("dim", "    Continue: no run in progress")]
  }
  let new = case model.saved {
    Some(run) -> {
      let e = profile.earnings(model.profile, run)
      button(
        ">>> New run · abandons the current one (it pays "
          <> int.to_string(e.data + e.bonus)
          <> " Data, as if lost)",
        NewGame,
      )
    }
    None -> button_class(">>> New run", "banner", NewGame)
  }
  html.div([], [text("", "MENU"), ..list.append(continue, [new])])
}

// Hangar (between runs)

fn view_hangar(model: Model) -> Element(Msg) {
  let assert Some(h) = model.hangar
  html.div([], [
    hangar_tabs(model, h),
    case h.screen {
      Overview -> view_hangar_overview(model, h)
      Lab -> view_lab(model, h)
      Room(_) -> design_room(model, h)
      NewRoom -> new_design_room(model, h)
    },
  ])
}

fn picked(yes: Bool) -> String {
  case yes {
    True -> "picked"
    False -> ""
  }
}

/// Whether the design can be fabricated, or why not.
fn design_status(model: Model, d: profile.Design) -> Element(Msg) {
  case profile.fabricate(model.profile, d) {
    Ok(_) -> text("ally", "✓ ready to fabricate")
    Error(e) -> text("foe", "✗ " <> describe_profile_error(e))
  }
}

fn design_lines(d: profile.Design) -> List(Element(Msg)) {
  case design_bot(d) {
    Some(b) -> [
      text("", "    " <> weight_line(b)),
      text("", "    " <> mounts_line(b)),
    ]
    None -> []
  }
}

/// A row of tabs at the top of a screen: (label, active, message).
fn tabs(items: List(#(String, Bool, Msg))) -> Element(Msg) {
  html.div(
    [attribute.class("tabs")],
    list.map(items, fn(item) {
      let #(label, active, msg) = item
      button_class(
        label,
        case active {
          True -> "tab active"
          False -> "tab"
        },
        msg,
      )
    }),
  )
}

fn hangar_tabs(model: Model, h: Hangar) -> Element(Msg) {
  let found = list.length(model.profile.found)
  tabs([
    #("Hangar", h.screen == Overview, HangarGo(Overview)),
    #(
      "Research lab"
        <> case found {
        0 -> ""
        n -> " (" <> int.to_string(n) <> ")"
      },
      h.screen == Lab,
      HangarGo(Lab),
    ),
    ..list.append(
      list.index_map(h.designs, fn(d, i) {
        #(d.name, h.screen == Room(i), HangarGo(Room(i)))
      }),
      [#("+ New robot", h.screen == NewRoom, HangarGo(NewRoom))],
    )
  ])
}

fn with_cancel(actions: List(Element(Msg))) -> List(Element(Msg)) {
  case actions {
    [] -> []
    _ -> list.append(actions, [button("[Cancel]", HangarSelect(NoHangarPick))])
  }
}

fn view_hangar_overview(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
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
        <> " for each run from its components",
    ),
    button_class(">>> Start a run", "banner", StartRun),
    text("", "ROBOTS · change each in its tab"),
    html.div(
      [attribute.class("table")],
      list.flat_map(h.designs, fn(d) {
        [
          text(
            "ally",
            "  "
              <> d.name
              <> " ("
              <> d.chassis
              <> "): "
              <> string.join(list.map(d.parts, part.display_name), ", "),
          ),
          ..list.append(design_lines(d), [design_status(model, d)])
        ]
      }),
    ),
    button("[Menu]", ToMenu),
  ])
}

fn view_lab(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
  let found =
    list.map(p.found, fn(b) {
      button_class(
        "  "
          <> blueprint.describe(b)
          <> " · research "
          <> int.to_string(blueprint.research_cost(b))
          <> " Data",
        picked(h.pick == PickFound(b)),
        HangarSelect(PickFound(b)),
      )
    })
  let #(actions, preview) = case h.pick {
    PickFound(b) -> #(
      [
        button(
          "[Research · "
            <> int.to_string(blueprint.research_cost(b))
            <> " Data]",
          Research,
        ),
        sell_button(b),
      ],
      case blueprint_component(b) {
        Some(c) -> preview_section(model, "", c)
        None -> text("", "")
      },
    )
    _ -> #([], text("dim", "Select a blueprint to see its cards."))
  }
  html.div([], [
    html.div([attribute.class("garage")], [
      html.div([], [
        text(
          "",
          "RESEARCH LAB · blueprints found in runs: research one to get its component in the fabricator",
        ),
        html.div([attribute.class("table")], case found {
          [] -> [
            text(
              "dim",
              "  none yet: strong enemies sometimes drop one, bosses always",
            ),
          ]
          _ -> found
        }),
        html.div([attribute.class("actions")], with_cancel(actions)),
      ]),
      html.div([attribute.class("preview")], [preview]),
    ]),
  ])
}

/// The garage between runs: the design as a robot, as in a run's garage,
/// and the fabricator's spare components below it, one per copy, grouped
/// by kind. Installing one takes it off the list.
/// The fabricator's spare components, grouped by kind; `chosen` selected.
fn fabricator_spare_rows(
  model: Model,
  h: Hangar,
  chosen: List(Int),
) -> List(Element(Msg)) {
  let rows =
    by_kind(spare_parts(model.profile, h.designs))
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, c) = pair
          button_class(
            "    " <> part_line(model.scale, c),
            picked(list.contains(chosen, i)),
            HangarSpare(i),
          )
        })
      ]
    })
  case rows {
    [] -> [text("dim", "  none: research blueprints in the research lab")]
    _ -> rows
  }
}

fn fabricator_chassis_rows(
  model: Model,
  h: Hangar,
  chosen: Option(Int),
) -> List(Element(Msg)) {
  list.index_map(spare_chassis(model.profile, h.designs), fn(name, i) {
    case blueprint.chassis(name) {
      Ok(c) ->
        button_class(
          "  "
            <> c.name
            <> " chassis · "
            <> int.to_string(scale.value(model.scale, c.hp))
            <> " HP · max weight "
            <> num(c.capacity)
            <> " · weapon mounts up to "
            <> string.join(list.map(c.weapon_mounts, num), ", "),
          picked(chosen == Some(i)),
          HangarSpareChassis(i),
        )
      Error(Nil) -> text("dim", "  " <> name)
    }
  })
}

fn spare_chassis_at(
  model: Model,
  h: Hangar,
  i: Int,
) -> Option(builder.Chassis) {
  option.then(at(spare_chassis(model.profile, h.designs), i), fn(name) {
    option.from_result(blueprint.chassis(name))
  })
}

/// A design's room, like a robot's tab in a run: the robot, the
/// fabricator's spare components and chassis. Install, remove, swap,
/// rebuild on another chassis, or sell a spare.
fn design_room(model: Model, h: Hangar) -> Element(Msg) {
  let s = model.scale
  let d = room(h)
  let spares = spare_parts(model.profile, h.designs)
  let #(installed, spare) = case h.pick {
    PickGarage(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot = case design_bot(d) {
    Some(bot) ->
      html.div([attribute.class("robot")], [
        text("ally", bot_line(s, bot)),
        ..list.flatten([
          design_lines(d),
          [
            button_class(
              "    " <> own_chassis_line(s, bot),
              picked(h.pick == PickDesignChassis),
              HangarOwnChassis,
            ),
          ],
          by_kind(bot.parts)
            |> list.map(fn(pair) {
              let #(i, c) = pair
              button_class(
                "    " <> part_line(s, c),
                picked(installed == Some(i)),
                HangarInstalled(i),
              )
            }),
          [design_status(model, d)],
        ])
      ])
    None -> text("foe", "  " <> d.name <> ": unknown chassis")
  }
  let chosen_chassis = case h.pick {
    PickSpareChassis(i) -> Some(i)
    _ -> None
  }
  let chassis_rows = fabricator_chassis_rows(model, h, chosen_chassis)
  let actions = case h.pick {
    PickGarage(Some(_), Some(_)) -> [button("[Swap them]", SwapPart)]
    PickGarage(Some(_), None) -> [button("[Remove part]", RemovePart)]
    PickGarage(None, Some(j)) ->
      list.flatten([
        [button("[Install on " <> d.name <> "]", AddPart)],
        case at(spares, j) {
          Some(c) -> [sell_button(PartBlueprint(c))]
          None -> []
        },
      ])
    PickSpareChassis(i) ->
      list.flatten([
        [button("[Rebuild " <> d.name <> " on it]", UseChassis)],
        case at(spare_chassis(model.profile, h.designs), i) {
          Some(name) -> [sell_button(ChassisBlueprint(name))]
          None -> []
        },
      ])
    _ -> []
  }
  // What a rebuild would do.
  let check = case h.pick {
    PickSpareChassis(i) ->
      case spare_chassis_at(model, h, i) {
        Some(c) -> {
          let #(kept, dropped) = builder.fit(c, d.parts)
          case builder.build(d.name, c, kept) {
            Ok(_) -> [
              text("ally", case dropped {
                [] -> "✓ every part fits"
                _ ->
                  "✓ it works · back to the spares: "
                  <> string.join(list.map(dropped, part.display_name), ", ")
              }),
            ]
            Error(errors) -> [
              text(
                "foe",
                "✗ "
                  <> string.join(list.map(errors, builder.describe_error), "; "),
              ),
            ]
          }
        }
        None -> []
      }
    _ -> []
  }
  let previews = case h.pick {
    PickGarage(installed, spare) ->
      case
        option.then(installed, at(d.parts, _)),
        option.then(spare, at(spares, _))
      {
        Some(o), Some(n) -> [
          preview_section(model, "OUT", o),
          preview_section(model, "IN", n),
        ]
        Some(o), None -> [preview_section(model, "", o)]
        None, Some(n) -> [preview_section(model, "", n)]
        None, None -> []
      }
    PickSpareChassis(i) ->
      case spare_chassis_at(model, h, i) {
        Some(c) -> [preview_section(model, "CHASSIS", builder.body(c))]
        None -> []
      }
    PickDesignChassis ->
      case blueprint.chassis(d.chassis) {
        Ok(c) -> [preview_section(model, "", builder.body(c))]
        Error(Nil) -> []
      }
    _ -> []
  }
  let previews = case previews {
    [] -> [text("dim", "Select a part, component or chassis to see its cards.")]
    _ -> previews
  }
  let hint = case h.pick {
    PickGarage(Some(_), None) ->
      "remove it, or select a component to swap it for"
    PickGarage(None, Some(_)) ->
      "install it, or select an installed part to swap"
    PickGarage(Some(_), Some(_)) -> "swap them, or change either selection"
    PickSpareChassis(_) ->
      "rebuild the robot on it: the parts that fit move over"
    PickDesignChassis -> "the chassis' own cards"
    _ ->
      "select a part or component to see its cards; a spare chassis to rebuild on"
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", d.name <> " · " <> hint),
      html.div([attribute.class("table")], [robot]),
      text(
        "",
        "FABRICATOR · spare components it can make, one per researched blueprint",
      ),
      html.div(
        [attribute.class("table")],
        fabricator_spare_rows(model, h, option.values([spare])),
      ),
      case chassis_rows {
        [] -> text("", "")
        _ ->
          html.div([attribute.class("table")], [
            text("", "SPARE CHASSIS · rebuild " <> d.name <> " on one"),
            ..chassis_rows
          ])
      },
      html.div([attribute.class("actions")], with_cancel(actions)),
      ..check
    ]),
    html.div([attribute.class("preview")], previews),
  ])
}

/// A new design from a spare chassis and spare components, while the
/// fabricator has room for another robot.
fn new_design_room(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
  let spares = spare_parts(p, h.designs)
  let #(chassis, drafted) = case h.pick {
    PickDraft(c, parts) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room_left = list.length(h.designs) < p.fabricator
  let chassis_rows = fabricator_chassis_rows(model, h, chassis)
  let #(actions, check) = case h.pick, room_left {
    PickDraft(c, parts), True -> {
      let attempt =
        option.map(spare_chassis_at(model, h, c), fn(frame) {
          builder.build(
            "New",
            frame,
            list.filter_map(parts, fn(j) {
              at(spares, j) |> option.to_result(Nil)
            }),
          )
        })
      #([button("[Assemble robot]", AssembleDesign)], case attempt {
        Some(Ok(_)) -> [text("ally", "✓ it can be built")]
        Some(Error(errors)) -> [
          text(
            "foe",
            "✗ " <> string.join(list.map(errors, builder.describe_error), "; "),
          ),
        ]
        None -> []
      })
    }
    _, _ -> #([], [])
  }
  let previews = case h.pick {
    PickDraft(c, parts) ->
      list.flatten([
        case spare_chassis_at(model, h, c) {
          Some(frame) -> [
            preview_section(model, "CHASSIS", builder.body(frame)),
          ]
          None -> []
        },
        case list.last(parts) {
          Ok(j) ->
            case at(spares, j) {
              Some(part) -> [preview_section(model, "PART", part)]
              None -> []
            }
          Error(Nil) -> []
        },
      ])
    _ -> [text("dim", "Select a spare chassis to build on.")]
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text(
        "",
        "NEW ROBOT · "
          <> case room_left, chassis_rows, chassis {
          False, _, _ ->
            "the fabricator builds "
            <> int.to_string(p.fabricator)
            <> case p.fabricator {
              1 -> " robot"
              _ -> " robots"
            }
            <> " a run: an upgrade will let it build more"
          True, [], _ -> "no spare chassis: research a chassis blueprint"
          True, _, None -> "select a spare chassis to build on"
          True, _, Some(_) -> "select components for it, then assemble"
        },
      ),
      html.div([attribute.class("table")], [
        text("", "SPARE CHASSIS"),
        ..case chassis_rows {
          [] -> [text("dim", "  none")]
          _ -> chassis_rows
        }
      ]),
      text("", "FABRICATOR · spare components"),
      html.div(
        [attribute.class("table")],
        fabricator_spare_rows(model, h, drafted),
      ),
      html.div([attribute.class("actions")], with_cancel(actions)),
      ..check
    ]),
    html.div([attribute.class("preview")], previews),
  ])
}

fn sell_button(b: Blueprint) -> Element(Msg) {
  button(
    "[Sell · +" <> int.to_string(profile.sell_price(b)) <> " Data]",
    SellBlueprint,
  )
}

/// The design as a robot, to show its weight and mounts (if its chassis
/// and parts exist; research and legality aside).
fn design_bot(d: profile.Design) -> Option(Bot) {
  case blueprint.chassis(d.chassis) {
    Ok(chassis) -> Some(state.Bot(name: d.name, chassis:, parts: d.parts))
    Error(Nil) -> None
  }
}

/// What a blueprint makes, as a component (a chassis as its body).
fn blueprint_component(b: Blueprint) -> Option(Component) {
  case b {
    PartBlueprint(p) -> Some(p)
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
        "DATA · +"
        <> int.to_string(e.data)
        <> " (battles won, levels reached and scrap left)",
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

fn at_shop(model: Model) -> Bool {
  case model.run.phase {
    state.Repairing(_) -> True
    _ -> False
  }
}

/// The open tab, made valid: the shop's counter only at a shop, a robot
/// that's still there (else the first, or New robot when there's none).
fn current_tab(model: Model) -> Tab {
  let robots = list.length(model.run.robots)
  let first = case robots {
    0 -> NewRobotTab
    _ -> RobotTab(0)
  }
  case model.tab {
    ShopTab ->
      case at_shop(model) {
        True -> ShopTab
        False -> first
      }
    RobotTab(r) if r >= 0 && r < robots -> model.tab
    RobotTab(_) -> first
    NewRobotTab -> NewRobotTab
  }
}

/// Shop (at a shop) | a tab per robot | + New robot.
fn garage_tabs(model: Model) -> Element(Msg) {
  let open = current_tab(model)
  tabs(
    list.flatten([
      case at_shop(model) {
        True -> [#("Shop", open == ShopTab, GoTab(ShopTab))]
        False -> []
      },
      list.index_map(model.run.robots, fn(bot, r) {
        #(bot.name, open == RobotTab(r), GoTab(RobotTab(r)))
      }),
      [#("+ New robot", open == NewRobotTab, GoTab(NewRobotTab))],
    ]),
  )
}

/// The garage: a tab per robot, where it's modified or rebuilt on another
/// chassis, and one to assemble a new robot from a spare chassis. The
/// spare parts are shared.
fn view_garage(model: Model) -> Element(Msg) {
  html.div([], [
    garage_tabs(model),
    case current_tab(model) {
      RobotTab(r) -> robot_room(model, r)
      NewRobotTab | ShopTab -> new_robot_room(model)
    },
  ])
}

/// Spare parts grouped by kind, a heading per kind; `chosen` are shown
/// as selected.
fn spare_rows(model: Model, chosen: List(Int)) -> List(Element(Msg)) {
  let rows =
    by_kind(model.run.parts)
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, p) = pair
          button_class(
            "    " <> part_line(model.scale, p),
            picked(list.contains(chosen, i)),
            ClickSpare(i),
          )
        })
      ]
    })
  case rows {
    [] -> [text("dim", "  none")]
    _ -> rows
  }
}

fn chassis_rows(model: Model, chosen: Option(Int)) -> List(Element(Msg)) {
  list.index_map(model.run.chassis, fn(c, i) {
    button_class(
      "  "
        <> c.name
        <> " chassis · "
        <> int.to_string(scale.value(model.scale, builder.chassis_hp(c)))
        <> " HP · max weight "
        <> num(c.capacity)
        <> " · weapon mounts up to "
        <> string.join(
        list.map(builder.mounts(c, []), fn(m) { num(m.0) }),
        ", ",
      ),
      picked(chosen == Some(i)),
      ClickChassis(i),
    )
  })
}

/// Repair (at a shop) and upgrade (at a workshop) for what's selected.
fn service_actions(model: Model) -> List(Element(Msg)) {
  let run = model.run
  let repair = case at_shop(model), repair_target(model.pick) {
    True, Some(target) ->
      case state.repair_one_price(run, target) {
        Ok(cost) if cost > 0 -> [
          button("[Repair · " <> int.to_string(cost) <> " scrap]", RepairPicked),
        ]
        _ -> []
      }
    _, _ -> []
  }
  let upgrade = case run.phase, upgrade_target(model.pick) {
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
  list.append(upgrade, repair)
}

fn with_cancel_run(
  actions: List(Element(Msg)),
  pick: Pick,
) -> List(Element(Msg)) {
  case pick {
    Picked(None, None) -> []
    _ -> list.append(actions, [button("[Cancel]", Cancel)])
  }
}

/// One robot's room: the robot, the shared spare parts, and spare chassis
/// to rebuild it on.
fn robot_room(model: Model, r: Int) -> Element(Msg) {
  let run = model.run
  let assert [bot, ..] = list.drop(run.robots, r)
  let #(installed, spare) = case model.pick {
    Picked(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot =
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
  let chosen_chassis = case model.pick {
    SpareChassis(c) -> Some(c)
    _ -> None
  }
  let actions = case model.pick {
    Picked(Some(#(pr, _)), Some(_)) if pr == r -> [button("[Swap them]", Swap)]
    Picked(Some(#(pr, _)), None) if pr == r -> [button("[Remove part]", Remove)]
    Picked(None, Some(_)) -> [
      button("[Install on " <> bot.name <> "]", Install(r)),
    ]
    SpareChassis(_) -> [button("[Rebuild " <> bot.name <> " on it]", Rebuild)]
    _ -> []
  }
  let actions =
    list.append(service_actions(model), actions)
    |> with_cancel_run(model.pick)
  let chassis = chassis_rows(model, chosen_chassis)
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", bot.name <> " · " <> hint(model.pick)),
      html.div([attribute.class("table")], [robot]),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(model, option.values([spare])),
      ),
      case chassis {
        [] -> text("", "")
        _ ->
          html.div([attribute.class("table")], [
            text("", "SPARE CHASSIS · rebuild " <> bot.name <> " on one"),
            ..chassis
          ])
      },
      html.div([attribute.class("actions")], actions),
      ..fit_lines(model)
    ]),
    view_selected(model),
  ])
}

/// Assemble a new robot: a spare chassis and spare parts.
fn new_robot_room(model: Model) -> Element(Msg) {
  let run = model.run
  let #(chassis, drafted) = case model.pick {
    Draft(c, parts, _) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room = list.length(run.robots) < run.truck
  let actions = case model.pick {
    Draft(..) -> [button("[Assemble robot]", Assemble)]
    _ -> []
  }
  let actions =
    list.append(service_actions(model), actions)
    |> with_cancel_run(model.pick)
  html.div([attribute.class("garage")], [
    html.div([], [
      text(
        "",
        "NEW ROBOT · "
          <> case room, run.chassis {
          False, _ ->
            "the truck is full ("
            <> int.to_string(run.truck)
            <> " robots): a spare chassis waits"
          True, [] -> "no spare chassis: win or buy one"
          True, _ ->
            case chassis {
              None -> "select a spare chassis to build on"
              Some(_) -> "select spare parts for it, then assemble"
            }
        },
      ),
      html.div([attribute.class("table")], [
        text("", "SPARE CHASSIS"),
        ..case run.chassis {
          [] -> [text("dim", "  none")]
          _ -> chassis_rows(model, chassis)
        }
      ]),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(model, case model.pick {
          Draft(..) -> drafted
          Picked(_, spare) -> option.values([spare])
          _ -> []
        }),
      ),
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
    SpareChassis(c) ->
      case list.drop(run.chassis, c) {
        [frame, ..] -> [preview_section(model, "CHASSIS", builder.body(frame))]
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
      "select a part or spare to see its cards; a spare chassis to rebuild on"
    Picked(Some(_), None) -> "remove it, or select a spare to swap it for"
    Picked(None, Some(_)) -> "install it, or select an installed part to swap"
    Picked(Some(_), Some(_)) -> "swap them, or change either selection"
    Draft(..) -> "select spare parts for the new robot, then assemble"
    OwnChassis(_) -> "the chassis' own cards; it can be repaired at a shop"
    ForSale(..) -> "on sale: buy it above, or select something else"
    SpareChassis(_) -> "rebuild the robot on it: the parts that fit move over"
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
    "[up to "
    <> num(m.0)
    <> "] "
    <> case m.1 {
      Some(w) ->
        part.display_name(w) <> " (weight " <> num(part.weight(w)) <> ")"
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
      case current_tab(model) {
        RobotTab(r) ->
          case list.drop(run.robots, r) {
            [bot, ..] -> [
              line("fits on " <> bot.name, state.install(run, r, spare)),
            ]
            [] -> []
          }
        _ -> []
      }
    SpareChassis(c) ->
      case current_tab(model) {
        RobotTab(r) ->
          case state.rebuild(run, r, c) {
            Ok(#(_, [])) -> [text("ally", "✓ every part fits")]
            Ok(#(_, dropped)) -> [
              text(
                "ally",
                "✓ it works · to the spares: "
                  <> string.join(list.map(dropped, part.display_name), ", "),
              ),
            ]
            Error(e) -> [text("foe", "✗ " <> describe_error(e))]
          }
        _ -> []
      }
    Draft(chassis, parts, _) -> [
      line("it can be built", state.assemble(run, "New", chassis, parts)),
    ]
    Picked(Some(#(r, i)), Some(spare)) -> [
      line("the swap works", state.swap(run, r, i, spare)),
    ]
    Picked(Some(#(r, i)), None) -> [
      line("it can be removed", state.uninstall(run, r, i)),
    ]
    _ -> []
  }
}

/// "Broken plating · armor · weight 2 · HP 0/25 · 25 scrap"
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
  <> " scrap"
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
.tabs { display: flex; gap: 0.25rem; margin-bottom: 0.75rem;
  border-bottom: 1px solid #2a302a; }
.tab { padding: 0.3rem 1rem; border: 1px solid #2a302a; border-bottom: none;
  border-radius: 6px 6px 0 0; opacity: 0.6; }
.tab.active { opacity: 1; background: #2a3a2a; color: #f0d060; }
"
