import gleam/float
import gleam/int
import gleam/list
import robots/ai/brain
import robots/construction/part
import robots/construction/robot
import robots/content/catalog
import robots/rules/card.{
  type Card, All, Attack, Beam, Buff, Card, Defence, Energy, Melee, One,
  Opponent, OpponentHp, Range, Self,
}
import robots/rules/energy
import robots/rules/game.{
  type Game, Combatant, Config, Game, GameOver, NoSuchCard, NotEnoughEnergy, P1,
  P2, PlayCard, Played, Won,
}
import robots/rules/scale
import robots/rules/table.{type Slot, Slot, slot}

// CARDS -----------------------------------------------------------------------

fn laser() -> Card {
  Card(
    "Laser",
    [Attack, Range, Beam],
    cost: 1.0,
    value: 1.0,
    target: OpponentHp,
    traits: [],
  )
}

fn punch() -> Card {
  Card(
    "Punch",
    [Attack, Melee],
    cost: 0.5,
    value: 0.5,
    target: OpponentHp,
    traits: [],
  )
}

fn energy_shield(value: Float) -> Card {
  Card(
    "Energy shield",
    [Defence, Energy],
    0.8,
    value,
    Opponent(One([Attack])),
    traits: [],
  )
}

fn parry() -> Card {
  Card(
    "Parry",
    [Defence, Melee],
    0.6,
    0.8,
    Opponent(One([Attack, Melee])),
    traits: [],
  )
}

fn jump() -> Card {
  Card("Jump", [Defence], 0.8, 0.3, Opponent(All([Attack, Melee])), traits: [])
}

fn lock_on() -> Card {
  Card(
    "Lock on",
    [Buff, Range],
    0.5,
    0.4,
    Self(One([Attack, Range])),
    traits: [],
  )
}

// SETUP -----------------------------------------------------------------------

fn config(starting_energy: Float) -> game.Config {
  Config(table_size: 4, starting_energy:, energy_rate: 0.5, defence_floor: 0.0)
}

fn bot(name: String, cards: List(Card)) -> robot.Robot {
  robot.new(name, chassis: "Test", max_hp: 5.0, energy_cap: 5.0, components: [
    part.new("Part", part.Weapon, 1.0, cards),
  ])
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
  let g = Game(..g, p1: Combatant(..g.p1, table: [Slot(laser(), 0.3, 0)]))
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert g.p1.table == [Slot(laser(), 1.0, 0)]
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
  let g = Game(..g, p1: Combatant(..g.p1, table: [Slot(laser(), 0.0, 0)]))
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

pub fn defence_cannot_go_below_the_floor_test() {
  // With a 25% floor, a Laser 10 hit by a 12 shield keeps 2.5 (shown 2).
  let g = arena([energy_shield(1.2)], [laser()])
  let g = Game(..g, config: Config(..g.config, defence_floor: 0.25))
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert list.map(g.p2.table, fn(s) { s.value }) == [0.25]
  // A second shield has nothing left to take.
  let g = arena([energy_shield(0.7)], [laser()])
  let g = Game(..g, config: Config(..g.config, defence_floor: 0.25))
  let floored =
    Game(..g, p2: Combatant(..g.p2, table: [table.Slot(laser(), 0.25, 0)]))
  let assert Ok(after) = game.update(floored, PlayCard(P1, 0, 0))
  assert list.map(after.p2.table, fn(s) { s.value }) == [0.25]
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
      p2: Combatant(..g.p2, table: [
        Slot(laser(), 0.0, 0),
        Slot(laser(), 1.0, 0),
      ]),
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

pub fn buff_all_raises_every_matching_own_card_test() {
  let overclock =
    Card("Overclock", [Buff], 0.9, 0.2, Self(All([Attack])), traits: [])
  let g = arena([overclock, punch(), laser()], [laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert values(g.p1) == [2, 7, 12]
}

// ONCE PER MATCH --------------------------------------------------------------

pub fn once_cards_leave_the_game_test() {
  let missile = Card(..laser(), name: "Missile", traits: [card.Once])
  let everywhere = fn(c: game.Combatant) {
    list.flatten([list.map(c.table, fn(s) { s.card }), c.deck, c.discard])
    |> list.map(fn(card) { card.name })
  }
  let g = arena([missile, laser()], [laser()])
  // The Missile is gone for good: not on the table, in the deck or discard.
  let assert Ok(after_missile) = game.update(g, PlayCard(P1, 0, 0))
  assert everywhere(after_missile.p1) == ["Laser"]
  // An ordinary card is recycled as usual (discarded, then reshuffled in).
  let assert Ok(after_laser) = game.update(after_missile, PlayCard(P1, 0, 0))
  assert everywhere(after_laser.p1) == ["Laser"]
}

// DRONES ----------------------------------------------------------------------

fn with_tables(g: Game, p1: List(Slot), p2: List(Slot)) -> Game {
  Game(..g, p1: Combatant(..g.p1, table: p1), p2: Combatant(..g.p2, table: p2))
}

fn drone_at(value: Float) -> Slot {
  Slot(catalog.drone(), value, 0)
}

pub fn launch_puts_a_drone_in_the_same_slot_test() {
  let assert [launch, ..] = catalog.drone_bay().cards
  let g = arena([laser(), launch], [laser()])
  let assert Ok(g) = game.update(g, PlayCard(P1, 1, 0))
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Laser", "Drone"]
  // Launching is once per match.
  assert g.p1.discard == []
}

pub fn drones_grow_up_to_their_cap_test() {
  let slot = table.placed(catalog.drone(), 0)
  assert table.value_at(slot, 0) == 1.5
  assert table.value_at(slot, 10_000) == 2.5
  assert table.value_at(slot, 100_000) == 3.0
}

pub fn attacks_hit_a_drone_instead_of_the_robot_test() {
  let g = arena([], [laser()]) |> with_tables([drone_at(2.0)], [slot(laser())])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert g.p1.robot.hp == 5.0
  assert list.map(g.p1.table, fn(s) { s.value }) == [1.0]
}

pub fn leftover_damage_is_lost_when_a_drone_is_destroyed_test() {
  let g = arena([], [laser()]) |> with_tables([drone_at(0.4)], [slot(laser())])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert g.p1.robot.hp == 5.0
  // Destroyed: gone from the table (and the game).
  assert g.p1.table == []
  assert g.p1.discard == []
}

pub fn drone_strikes_for_its_grown_value_test() {
  let g = arena([], [laser()]) |> with_tables([drone_at(0.5)], [slot(laser())])
  // 10 s later it has grown from 0.5 to 1.5.
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 10_000))
  assert g.p2.robot.hp == 3.5
  assert g.p1.discard == []
}

pub fn shields_do_not_affect_drones_test() {
  let shield = energy_shield(0.7)
  let g = arena([], [shield]) |> with_tables([drone_at(2.0)], [slot(shield)])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert list.map(g.p1.table, fn(s) { s.value }) == [2.0]
}

pub fn shoot_down_destroys_a_full_drone_test() {
  let assert [shoot_down, ..] = catalog.point_defence().cards
  let g =
    arena([], [shoot_down])
    |> with_tables([drone_at(3.0), slot(laser())], [slot(shoot_down)])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Laser"]
}

pub fn ai_lets_a_drone_grow_before_striking_test() {
  let shield = energy_shield(0.7)
  let g =
    arena([], [shield])
    |> with_tables([drone_at(0.5), slot(laser())], [slot(shield)])
  // Young drone, nothing threatens it: fire the Laser, let the drone grow.
  assert brain.choose(g, P1, 0) == Ok(1)
  // Fully grown (3.0 after 25 s): strike with it.
  assert brain.choose(g, P1, 30_000) == Ok(0)
}

pub fn ai_waits_for_a_full_drone_even_under_threat_test() {
  // The opponent's Laser (1.0) could destroy this drone (0.9), but the AI
  // still waits for it to max out.
  let g =
    arena([], [laser()])
    |> with_tables([drone_at(0.9), slot(energy_shield(0.7))], [slot(laser())])
  assert brain.choose(g, P1, 0) != Ok(0)
  // ...unless the strike would win the match.
  let low =
    Game(..g, p2: Combatant(..g.p2, robot: robot.Robot(..g.p2.robot, hp: 0.5)))
  assert brain.choose(low, P1, 0) == Ok(0)
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
  let nuke = Card("Nuke", [Attack], 0.0, 9.0, OpponentHp, traits: [])
  let assert Ok(g) = game.update(arena([nuke], [laser()]), PlayCard(P1, 0, 0))
  assert g.status == Won(P1)
  assert g.p2.robot.hp == 0.0
  assert game.update(g, PlayCard(P2, 0, 0)) == Error(GameOver)
}

// AI --------------------------------------------------------------------------

pub fn ai_waits_until_it_has_thought_test() {
  let g = arena([laser()], [laser()])
  let #(_, after) = brain.act(brain.new(P2, think_ms: 1000, now: 0), g, 500)
  assert after == g
}

pub fn ai_plays_after_thinking_test() {
  let g = arena([laser()], [laser()])
  let #(brain, g) = brain.act(brain.new(P2, think_ms: 1000, now: 0), g, 1000)
  assert g.p1.robot.hp == 4.0
  assert brain.next_action_at == 2000
}

pub fn ai_defends_against_a_big_attack_test() {
  // Shield 9 for cost 7 removes 9 of the Laser: 1.29 per energy, better than
  // a Punch's 1.0.
  let shield =
    Card("Shield", [Defence], 0.7, 0.9, Opponent(One([Attack])), traits: [])
  let g = arena([laser()], [punch(), shield])
  assert brain.choose(g, P2, 0) == Ok(1)
}

pub fn ai_saves_energy_for_a_more_efficient_card_test() {
  // Tap (1.0 per cost) is affordable; Big shot (1.5 per cost) isn't yet.
  let big = Card("Big shot", [Attack], 2.0, 3.0, OpponentHp, traits: [])
  let weak = Card("Tap", [Attack], 0.5, 0.5, OpponentHp, traits: [])
  let g = arena([laser()], [weak, big])
  let low =
    Game(..g, p2: Combatant(..g.p2, energy: energy.new(1.0, 0.5, 5.0, 0)))
  assert brain.choose(low, P2, 0) == Error(Nil)
  // Once it can pay, it plays the better card.
  assert brain.choose(low, P2, 2000) == Ok(1)
}

pub fn ai_spends_instead_of_wasting_energy_at_the_cap_test() {
  // The best card costs more than ever affordable right now, but energy is
  // full: spend on the best affordable card rather than waste income.
  let big = Card("Big shot", [Attack], 5.0, 9.0, OpponentHp, traits: [])
  let weak = Card("Tap", [Attack], 0.5, 0.5, OpponentHp, traits: [])
  let g = arena([laser()], [weak, big])
  let nearly =
    Game(..g, p2: Combatant(..g.p2, energy: energy.new(4.6, 0.5, 5.0, 0)))
  assert brain.choose(nearly, P2, 0) == Ok(0)
}

pub fn ai_goes_for_the_kill_test() {
  let g = arena([laser()], [energy_shield(0.7), punch()])
  let g =
    Game(..g, p1: Combatant(..g.p1, robot: robot.Robot(..g.p1.robot, hp: 0.5)))
  assert brain.choose(g, P2, 0) == Ok(1)
}

pub fn ai_clears_a_dead_slot_only_when_energy_is_nearly_full_test() {
  let g = arena([laser()], [parry()])
  // Parry has no target: not worth playing with half-full energy...
  let half =
    Game(..g, p2: Combatant(..g.p2, energy: energy.new(2.5, 0.5, 5.0, 0)))
  assert brain.choose(half, P2, 0) == Error(Nil)
  // ...but with full energy, clearing the slot beats wasting the energy.
  assert brain.choose(g, P2, 0) == Ok(0)
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

pub fn an_unlaunched_drone_does_not_soak_attacks_test() {
  let assert [launch, ..] = catalog.drone_bay().cards
  let g =
    arena([], [laser()])
    |> with_tables([slot(launch)], [slot(laser())])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  // The Laser hits the robot; the Launch card is still on the table.
  assert g.p1.robot.hp == 4.0
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Launch drone"]
}

pub fn smoke_lowers_range_attacks_on_both_tables_test() {
  let assert [smoke, ..] = catalog.smoke_launcher().cards
  let assert [jab, ..] = catalog.fist().cards
  let g =
    arena([smoke, laser(), jab], [laser()])
    |> with_tables([slot(smoke), slot(laser()), slot(jab)], [slot(laser())])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  // Both Lasers (1.0) drop to 0; the melee Jab is untouched. (Slot 0
  // is refilled from the deck.)
  let values = fn(t: List(Slot)) {
    list.map(t, fn(s) {
      #(s.card.name, int.to_float(float.round(s.value *. 100.0)) /. 100.0)
    })
  }
  assert list.drop(values(g.p1.table), 1) == [#("Laser", 0.0), #("Jab", 0.38)]
  assert values(g.p2.table) == [#("Laser", 0.0)]
}

pub fn smoke_does_not_block_beams_test() {
  let assert [smoke, ..] = catalog.smoke_launcher().cards
  let assert [_, laser_card, ..] = catalog.laser().cards
  let assert [burst, ..] = catalog.machine_gun().cards
  let g =
    arena([], [smoke])
    |> with_tables([slot(laser_card), slot(burst)], [slot(smoke)])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  // The Laser is a beam: untouched. The Burst is a range attack: lowered.
  let assert [laser_slot, burst_slot] = g.p1.table
  assert laser_slot.value == laser_card.value
  assert burst_slot.value == 0.0
}

pub fn a_machine_gun_sweep_destroys_a_fresh_drone_test() {
  let assert Ok(sweep) =
    list.find(catalog.machine_gun().cards, fn(c) { c.name == "Sweep" })
  let g =
    arena([], [sweep])
    |> with_tables([drone_at(1.5), slot(laser())], [slot(sweep)])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Laser"]
}

fn ignite() -> Card {
  let assert Ok(c) =
    list.find(catalog.flamethrower().cards, fn(c) { c.name == "Ignite" })
  c
}

fn names_everywhere(c: game.Combatant) -> List(String) {
  list.flatten([
    list.map(c.table, fn(s) { s.card.name }),
    list.map(c.deck, fn(c) { c.name }),
    list.map(c.discard, fn(c) { c.name }),
  ])
}

pub fn ignite_burns_a_zeroed_card_test() {
  let g =
    arena([], [ignite()])
    |> with_tables([Slot(punch(), 0.0, 0), slot(laser())], [slot(ignite())])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  // The zeroed Punch is gone for the match; Fire takes its slot, and costs
  // at least as much to clear as the Punch did.
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Fire", "Laser"]
  assert !list.contains(names_everywhere(g.p1), "Punch")
  let assert [fire, ..] = g.p1.table
  assert fire.card.cost >=. punch().cost
}

pub fn ignite_needs_a_zeroed_card_test() {
  let g =
    arena([], [ignite()])
    |> with_tables([slot(punch()), slot(laser())], [slot(ignite())])
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert list.map(g.p1.table, fn(s) { s.card.name }) == ["Punch", "Laser"]
}

pub fn fire_leaves_the_match_when_played_test() {
  let g =
    arena([], [laser()])
    |> with_tables([slot(catalog.fire()), slot(laser())], [slot(laser())])
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert !list.contains(names_everywhere(g.p1), "Fire")
}
