import gleam/list
import gleam/option.{None, Some}
import robots/ai/brain
import robots/balance/simulation
import robots/construction/part
import robots/construction/wear
import robots/content/components
import robots/content/enemies
import robots/content/starters
import robots/rules/game
import robots/run/map
import robots/run/state.{type Run, Outcome, Run}

/// A run standing at its first battle.
fn at_first_battle() -> Run {
  let run = state.new(1)
  let assert [first, ..] = state.choices(run)
  let assert Ok(run) = state.go(run, first.id)
  run
}

/// A run standing at a node with the given event, reached by setting the
/// position directly.
fn at(run: Run, event: fn(map.Event) -> Bool) -> Run {
  let assert Ok(node) = list.find(run.map.nodes, fn(n) { event(n.event) })
  let phase = case node.event {
    map.RepairShop -> state.Repairing(node.id)
    map.Battle(..) -> state.Fighting(node.id)
  }
  Run(..run, at: Some(node.id), phase:)
}

fn tinker_hp() -> Float {
  starters.tinker().hp
}

pub fn a_run_starts_with_the_tinker_on_the_first_row_test() {
  let run = state.new(1)
  assert run.level == 1
  assert run.phase == state.Choosing
  assert list.map(run.robots, fn(b) { b.name }) == ["Tinker"]
  assert state.choices(run) == map.start(run.map)
}

pub fn moves_follow_the_links_test() {
  let run = state.new(1)
  // A boss node isn't reachable from the start.
  let assert Ok(boss) = list.last(run.map.nodes)
  assert state.go(run, boss.id) == Error(state.NotReachable(boss.id))
  let run = at_first_battle()
  let assert Ok(#(map.Normal, _)) = state.battle(run)
  // At a battle, the next step waits for the battle.
  assert state.choices(run) == []
  assert state.go(run, 0) == Error(state.WrongPhase)
}

pub fn a_battle_order_names_every_robot_once_test() {
  let run = at_first_battle()
  assert state.team(run, []) == Error(state.BadOrder)
  assert state.team(run, [0, 0]) == Error(state.BadOrder)
  assert state.team(run, [1]) == Error(state.BadOrder)
  let assert Ok([tinker]) = state.team(run, [0])
  assert tinker.name == "Tinker"
}

pub fn a_win_wears_the_robot_and_pays_out_test() {
  let run = at_first_battle()
  let assert Some(node_id) = run.at
  let assert Ok(#(after, reward)) =
    state.finish(run, [0], Outcome(won: True, hp_left: [tinker_hp() -. 4.0]))
  assert after.phase == state.Choosing
  assert reward.money == state.money_normal
  assert after.money == state.money_normal
  assert reward.chassis == None
  assert list.length(reward.parts) == state.drops_normal
  assert after.parts == reward.parts
  // The plating (2.875 HP) broke and the Frame took the rest.
  let assert [tinker] = after.robots
  assert list.any(tinker.parts, wear.is_broken)
  assert tinker.chassis.wear >. 1.0
  // The next choices follow from the battle's node.
  let assert Ok(node) = map.node(after.map, node_id)
  assert state.choices(after) == map.next(after.map, node)
}

pub fn a_loss_ends_the_run_test() {
  let run = at_first_battle()
  let assert Ok(#(after, reward)) =
    state.finish(run, [0], Outcome(won: False, hp_left: [0.0]))
  assert after.phase == state.Over
  assert after.robots == []
  assert reward.money == 0
  assert state.choices(after) == []
}

pub fn destroyed_robots_are_lost_but_the_team_can_still_win_test() {
  let run = with_scrapper(at_first_battle())
  // The Scrapper fights first and is destroyed; the Tinker wins.
  let assert Ok(#(after, _)) =
    state.finish(run, [1, 0], Outcome(won: True, hp_left: [0.0, tinker_hp()]))
  assert list.map(after.robots, fn(b) { b.name }) == ["Tinker"]
  assert after.phase == state.Choosing
}

pub fn beating_the_boss_opens_the_next_level_test() {
  let run =
    at(state.new(3), fn(e) {
      case e {
        map.Battle(tier: map.Boss, ..) -> True
        _ -> False
      }
    })
  let assert Ok(#(after, reward)) =
    state.finish(run, [0], Outcome(won: True, hp_left: [tinker_hp()]))
  assert reward.money == state.money_boss
  let assert Some(chassis) = reward.chassis
  assert after.chassis == [chassis]
  assert after.level == 2
  assert after.map.level == 2
  assert after.at == None
  assert state.choices(after) == map.start(after.map)
}

pub fn the_repair_shop_restores_wear_for_money_test() {
  let run = at(state.new(1), fn(e) { e == map.RepairShop })
  let assert [tinker] = run.robots
  let #(chassis, parts) = wear.assign(tinker.chassis, tinker.parts, 2.0)
  let worn = state.Bot(..tinker, chassis:, parts:)
  let run = Run(..run, robots: [worn])
  // 2 HP of wear at 20 credits per HP.
  assert state.repair_price(worn) == 40
  assert state.repair(run, 0) == Error(state.NotEnoughMoney(40, 0))
  let assert Ok(repaired) = state.repair(Run(..run, money: 50), 0)
  assert repaired.money == 10
  let assert [fixed] = repaired.robots
  assert fixed == tinker
  // Repairs only happen at a shop.
  assert state.repair(Run(..run, phase: state.Choosing, money: 50), 0)
    == Error(state.WrongPhase)
  let assert Ok(left) = state.leave(repaired)
  assert left.phase == state.Choosing
}

pub fn the_repair_shop_can_fix_one_part_at_a_time_test() {
  let run = at(state.new(1), fn(e) { e == map.RepairShop })
  let assert [tinker] = run.robots
  // 3 HP: both Platings (1.25 each) break, 0.5 reaches the Frame.
  let #(chassis, parts) = wear.assign(tinker.chassis, tinker.parts, 3.0)
  let run =
    Run(..run, money: 30, robots: [state.Bot(..tinker, chassis:, parts:)])
  assert state.repair_one_price(run, state.RepairChassis(0)) == Ok(10)
  assert state.repair_one_price(run, state.RepairPart(0, 3)) == Ok(25)
  // The Laser doesn't wear.
  assert state.repair_one_price(run, state.RepairPart(0, 0)) == Ok(0)
  let assert Ok(run) = state.repair_one(run, state.RepairPart(0, 3))
  assert run.money == 5
  let assert [bot] = run.robots
  let assert [_, _, _, fixed, still_broken] = bot.parts
  assert !wear.is_broken(fixed)
  assert wear.is_broken(still_broken)
  assert bot.chassis.wear == 0.5
  assert state.repair_one(run, state.RepairChassis(0))
    == Error(state.NotEnoughMoney(10, 5))
  // A broken plate taken off can be repaired among the spares.
  let run = Run(..run, money: 100, parts: [still_broken])
  let assert Ok(run) = state.repair_one(run, state.RepairSpare(0))
  let assert [spare] = run.parts
  assert !wear.is_broken(spare)
  assert run.money == 75
  assert state.repair_one(run, state.RepairSpare(5)) == Error(state.NoSuchPart)
}

pub fn garage_changes_must_leave_a_legal_build_test() {
  let run =
    Run(..state.new(1), parts: [
      components.cannon(),
      part.with(components.plating(), part.overclocked()),
      components.laser(),
    ])
  // A Cannon is too heavy for the Tinker.
  let assert Error(state.CantBuild("Tinker", _)) = state.install(run, 0, 0)
  // Its only weapon can't just be taken off...
  let assert Error(state.CantBuild("Tinker", _)) = state.uninstall(run, 0, 0)
  // ...but it can be swapped for another.
  let assert Ok(swapped) = state.swap(run, 0, 0, 2)
  let assert [tinker] = swapped.robots
  assert list.length(tinker.parts) == 5
  assert list.length(swapped.parts) == 3
  assert state.swap(run, 0, 9, 1) == Error(state.NoSuchPart)
  // A broken plate is swapped for a fresh one; it goes to the spares, still
  // broken.
  let assert [tinker] = run.robots
  // 2 damage: the first Plating breaks, the second is worn.
  let #(chassis, parts) = wear.assign(tinker.chassis, tinker.parts, 2.0)
  let run = Run(..run, robots: [state.Bot(..tinker, chassis:, parts:)])
  let assert Ok(fixed) = state.swap(run, 0, 3, 1)
  let assert [tinker] = fixed.robots
  assert !list.any(tinker.parts, wear.is_broken)
  assert list.any(fixed.parts, wear.is_broken)
}

pub fn a_spare_chassis_becomes_a_new_robot_test() {
  let run = with_scrapper(state.new(1))
  assert list.map(run.robots, fn(b) { b.name }) == ["Tinker", "Scrapper"]
  assert run.chassis == []
  assert run.parts == []
  let assert Ok([first, second]) = state.team(run, [1, 0])
  assert first.name == "Scrapper"
  assert second.name == "Tinker"
}

pub fn outcome_reads_the_finished_game_test() {
  let tinker = starters.tinker()
  let foe = enemies.robot(enemies.rusty_brawler())
  let final =
    simulation.teams(
      game.default_config(),
      [tinker, tinker],
      [foe],
      3,
      brain.human,
    )
  let outcome = state.outcome(final, 2)
  assert list.length(outcome.hp_left) == 2
  case final.status {
    game.Won(game.P1) -> {
      assert outcome.won
      assert list.any(outcome.hp_left, fn(hp) { hp >. 0.0 })
    }
    _ -> {
      assert !outcome.won
      assert outcome.hp_left == [0.0, 0.0]
    }
  }
}

/// Give the run a second robot: the Scrapper, assembled from spares.
fn with_scrapper(run: Run) -> Run {
  let run =
    Run(..run, chassis: [components.brute()], parts: [
      components.saw_arm(),
      components.fist(),
      components.hydraulics(),
      components.deflector(),
      components.battery(),
      components.plating(),
      components.plating(),
    ])
  let assert Ok(run) = state.assemble(run, "Scrapper", 0, [0, 1, 2, 3, 4, 5, 6])
  run
}
