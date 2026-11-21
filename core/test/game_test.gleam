import gleam/list
import robots/ai
import robots/card.{
  type Card, All, Attack, Beam, Buff, Card, Defence, Energy, Melee, NoReach, One,
  Range,
}
import robots/catalog
import robots/energy
import robots/game.{
  type Game, Combatant, Config, Game, GameOver, NoSuchCard, NotEnoughEnergy, P1,
  P2, PlayCard, Played, Won,
}
import robots/robot.{Component}
import robots/scale
import robots/table.{Slot}

// CARDS -----------------------------------------------------------------------

fn laser() -> Card {
  Card("Laser", [Attack, Range, Beam], cost: 1.0, value: 1.0, reach: NoReach)
}

fn punch() -> Card {
  Card("Punch", [Attack, Melee], cost: 0.5, value: 0.5, reach: NoReach)
}

fn energy_shield(value: Float) -> Card {
  Card("Energy shield", [Defence, Energy], 0.8, value, One([Attack]))
}

fn parry() -> Card {
  Card("Parry", [Defence, Melee], 0.6, 0.8, One([Attack, Melee]))
}

fn jump() -> Card {
  Card("Jump", [Defence], 0.8, 0.3, All([Attack, Melee]))
}

fn lock_on() -> Card {
  Card("Lock on", [Buff, Range], 0.5, 0.4, One([Attack, Range]))
}

// SETUP -----------------------------------------------------------------------

fn config(starting_energy: Float) -> game.Config {
  Config(table_size: 4, starting_energy:, energy_rate: 0.5, energy_cap: 5.0)
}

fn bot(name: String, cards: List(Card)) -> robot.Robot {
  let assert Ok(bot) =
    robot.new(name, max_hp: 5.0, slots: 1)
    |> robot.install(Component("Part", cards))
  bot
}

/// A game where both tables, decks and discard piles are exactly as given,
/// independent of shuffling.
fn arena(p1_table: List(Card), p2_table: List(Card)) -> Game {
  let g =
    game.new(
      config(5.0),
      p1: bot("Alpha", [laser()]),
      p2: bot("Beta", [laser()]),
      seed: 1,
      now: 0,
    )
  let set = fn(c: game.Combatant, cards: List(Card)) {
    Combatant(..c, table: list.map(cards, table.slot), deck: [], discard: [])
  }
  Game(..g, p1: set(g.p1, p1_table), p2: set(g.p2, p2_table))
}

fn values(c: game.Combatant) -> List(Int) {
  list.map(c.table, fn(s) { scale.value(scale.default(), s.value) })
}

// TABLE -----------------------------------------------------------------------

pub fn tables_start_full_test() {
  let g =
    game.new(
      game.default_config(),
      p1: catalog.tinker(),
      p2: catalog.scrapper(),
      seed: 99,
      now: 0,
    )
  assert list.length(g.p1.table) == 4
  assert list.length(g.p2.table) == 4
  assert list.length(g.p1.deck) == list.length(robot.deck(catalog.tinker())) - 4
}

pub fn small_deck_leaves_slots_empty_test() {
  let g =
    game.new(
      config(5.0),
      p1: bot("Tiny", [laser(), laser()]),
      p2: bot("Beta", [laser()]),
      seed: 1,
      now: 0,
    )
  assert list.length(g.p1.table) == 2
}

pub fn same_seed_same_game_test() {
  let new = fn() {
    game.new(
      game.default_config(),
      p1: catalog.tinker(),
      p2: catalog.scrapper(),
      seed: 5,
      now: 0,
    )
  }
  assert new() == new()
}

pub fn played_slot_is_refilled_in_place_test() {
  let g = arena([punch(), laser(), punch()], [laser()])
  let g = Game(..g, p1: Combatant(..g.p1, deck: [jump()]))
  let assert Ok(g) = game.update(g, PlayCard(P1, 1, 0))
  assert list.map(g.p1.table, fn(s) { s.card.name })
    == ["Punch", "Jump", "Punch"]
  assert g.p1.discard == [laser()]
}

pub fn empty_deck_reshuffles_discard_and_resets_value_test() {
  // A lowered Laser is played, goes to the discard pile, and comes straight
  // back (it's the only card) at its printed value.
  let g = arena([laser()], [laser()])
  let g = Game(..g, p1: Combatant(..g.p1, table: [Slot(laser(), 0.3)]))
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert g.p1.table == [Slot(laser(), 1.0)]
  assert g.p1.discard == []
}

// ATTACK ----------------------------------------------------------------------

pub fn attack_damages_hp_by_current_value_test() {
  let assert Ok(g) =
    game.update(arena([laser()], [punch()]), PlayCard(P1, 0, 0))
  assert g.p2.robot.hp == 4.0
}

pub fn zero_value_attack_still_costs_energy_test() {
  let g = arena([laser()], [punch()])
  let g = Game(..g, p1: Combatant(..g.p1, table: [Slot(laser(), 0.0)]))
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert g.p2.robot.hp == 5.0
  assert energy.at(g.p1.energy, 0) == 4.0
}

// DEFENCE ---------------------------------------------------------------------

pub fn energy_shield_example_from_the_rules_test() {
  // Opponent has Laser 10; I play Energy shield 7; their Laser drops to 3.
  let g = arena([energy_shield(0.7)], [laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [3]
  // If they play it now, it deals only 3.
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert scale.value(scale.default(), g.p1.robot.hp) == 47
}

pub fn extra_defence_value_is_wasted_test() {
  let g = arena([energy_shield(1.2)], [laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [0]
}

pub fn single_target_defence_only_hits_matching_cards_test() {
  let g = arena([parry()], [laser(), punch(), laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [10, 0, 10]
}

pub fn single_target_defence_skips_cards_already_at_zero_test() {
  let g = arena([energy_shield(0.7)], [laser(), laser()])
  let g =
    Game(
      ..g,
      p2: Combatant(..g.p2, table: [Slot(laser(), 0.0), Slot(laser(), 1.0)]),
    )
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [0, 3]
}

pub fn single_target_defence_picks_at_random_test() {
  // Over many seeds, both matching Lasers get picked at some point.
  let picks =
    list.map([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn(seed) {
      let g = arena([energy_shield(0.7)], [laser(), laser()])
      let g = Game(..g, seed: rng_seed(seed))
      let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
      values(g.p2)
    })
  assert list.contains(picks, [3, 10])
  assert list.contains(picks, [10, 3])
}

pub fn jump_hits_every_melee_attack_test() {
  let g = arena([jump()], [punch(), laser(), punch()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [2, 10, 2]
}

pub fn defence_without_target_does_nothing_but_is_played_test() {
  let g = arena([parry()], [laser(), laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p2) == [10, 10]
  assert energy.at(g.p1.energy, 0) == 4.4
  let assert [Played(side: P1, targets: 0, ..), ..] = g.log
}

// BUFF ------------------------------------------------------------------------

pub fn buff_raises_own_matching_card_test() {
  let g = arena([lock_on(), punch(), laser()], [laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  // Lock on's slot was refilled from an empty deck by reshuffling Lock on.
  assert values(g.p1) == [4, 5, 14]
}

// ENERGY AND ERRORS -----------------------------------------------------------

pub fn not_enough_energy_is_rejected_test() {
  let g = arena([laser()], [laser()])
  let g = Game(..g, p1: Combatant(..g.p1, energy: energy.new(0.5, 0.5, 5.0, 0)))
  assert game.update(g, PlayCard(P1, 0, 0))
    == Error(NotEnoughEnergy(cost: 1.0, available: 0.5))
  // One second later, 0.5 more energy has arrived.
  let assert Ok(_) = game.update(g, PlayCard(P1, 0, 1000))
}

pub fn invalid_slot_is_rejected_test() {
  let g = arena([laser()], [laser()])
  assert game.update(g, PlayCard(P1, 4, 0)) == Error(NoSuchCard)
  assert game.update(g, PlayCard(P1, -1, 0)) == Error(NoSuchCard)
}

pub fn destroying_the_robot_wins_test() {
  let nuke = Card("Nuke", [Attack], 0.0, 9.0, NoReach)
  let assert Ok(g) = game.update(arena([nuke], [laser()]), PlayCard(P1, 0, 0))
  assert g.status == Won(P1)
  assert g.p2.robot.hp == 0.0
  assert game.update(g, PlayCard(P2, 0, 0)) == Error(GameOver)
}

// AI --------------------------------------------------------------------------

pub fn ai_waits_until_it_has_thought_test() {
  let g = arena([laser()], [laser()])
  let #(_, after) = ai.act(ai.new(P2, think_ms: 1000, now: 0), g, 500)
  assert after == g
}

pub fn ai_plays_after_thinking_test() {
  let g = arena([laser()], [laser()])
  let #(brain, g) = ai.act(ai.new(P2, think_ms: 1000, now: 0), g, 1000)
  assert g.p1.robot.hp == 4.0
  assert brain.next_action_at == 2000
}

pub fn ai_defends_against_a_big_attack_test() {
  // Weakening a 10-value Laser beats dealing 5 with a Punch.
  let g = arena([laser()], [punch(), energy_shield(0.7)])
  assert ai.choose(g, P2, 0) == Ok(1)
}

pub fn ai_goes_for_the_kill_test() {
  let g = arena([laser()], [energy_shield(0.7), punch()])
  let g =
    Game(..g, p1: Combatant(..g.p1, robot: robot.Robot(..g.p1.robot, hp: 0.5)))
  assert ai.choose(g, P2, 0) == Ok(1)
}

pub fn ai_clears_a_dead_slot_only_when_energy_is_nearly_full_test() {
  let g = arena([laser()], [parry()])
  // Parry has no target: not worth playing with half-full energy...
  let half =
    Game(..g, p2: Combatant(..g.p2, energy: energy.new(2.5, 0.5, 5.0, 0)))
  assert ai.choose(half, P2, 0) == Error(Nil)
  // ...but with full energy, clearing the slot beats wasting the energy.
  assert ai.choose(g, P2, 0) == Ok(0)
}

fn rng_seed(n: Int) {
  game.new(
    config(5.0),
    p1: bot("A", [laser()]),
    p2: bot("B", [laser()]),
    seed: n,
    now: 0,
  ).seed
}
