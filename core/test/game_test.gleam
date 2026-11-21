import gleam/list
import robots/ai
import robots/card.{Card, Damage, Repair, Shield}
import robots/catalog
import robots/game.{
  type Game, Config, GameOver, NoSuchCard, NotEnoughEnergy, P1, P2, PlayCard,
  Tick, Won,
}
import robots/robot.{Component}

// Robots whose decks contain a single kind of card, so tests don't depend on
// shuffle order.
fn mono_robot(name: String, card: card.Card, copies: Int) -> robot.Robot {
  let assert Ok(bot) =
    robot.new(name, max_hp: 20, slots: 1)
    |> robot.install(Component("Test part", list.repeat(card, copies)))
  bot
}

fn zap() {
  Card("Zap", 2, [Damage(3)])
}

fn config() {
  Config(
    starting_hand: 3,
    hand_limit: 5,
    draw_interval_ms: 1000,
    starting_energy: 3.0,
    energy_rate: 1.0,
    energy_cap: 10.0,
  )
}

fn duel(p1_card: card.Card, p2_card: card.Card) -> Game {
  game.new(
    config(),
    p1: mono_robot("Alpha", p1_card, 8),
    p2: mono_robot("Beta", p2_card, 8),
    seed: 1,
    now: 0,
  )
}

pub fn deals_starting_hands_test() {
  let g =
    game.new(
      game.default_config(),
      p1: catalog.tinker(),
      p2: catalog.scrapper(),
      seed: 99,
      now: 0,
    )
  assert list.length(g.p1.hand) == 3
  assert list.length(g.p2.hand) == 3
  assert list.length(g.p1.deck) == list.length(robot.deck(catalog.tinker())) - 3
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

pub fn playing_a_card_damages_the_opponent_test() {
  let assert Ok(g) = game.update(duel(zap(), zap()), PlayCard(P1, 0, 0))
  assert g.p2.robot.hp == 17
  assert list.length(g.p1.hand) == 2
  assert g.p1.discard == [zap()]
}

pub fn not_enough_energy_is_rejected_test() {
  let blast = Card("Blast", 5, [Damage(8)])
  assert game.update(duel(blast, zap()), PlayCard(P1, 0, 1000))
    == Error(NotEnoughEnergy(cost: 5, available: 4.0))
}

pub fn energy_arrives_in_real_time_test() {
  let blast = Card("Blast", 5, [Damage(8)])
  let assert Ok(g) = game.update(duel(blast, zap()), PlayCard(P1, 0, 2000))
  assert g.p2.robot.hp == 12
}

pub fn invalid_hand_index_is_rejected_test() {
  assert game.update(duel(zap(), zap()), PlayCard(P1, 7, 0))
    == Error(NoSuchCard)
  assert game.update(duel(zap(), zap()), PlayCard(P1, -1, 0))
    == Error(NoSuchCard)
}

pub fn shield_absorbs_damage_first_test() {
  let brace = Card("Brace", 1, [Shield(2)])
  let g = duel(zap(), brace)
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  assert g.p2.robot.shield == 0
  assert g.p2.robot.hp == 19
}

pub fn repair_never_exceeds_max_hp_test() {
  let patch = Card("Patch", 1, [Repair(10)])
  let assert Ok(g) = game.update(duel(zap(), patch), PlayCard(P1, 0, 0))
  let assert Ok(g) = game.update(g, PlayCard(P2, 0, 0))
  assert g.p2.robot.hp == 20
}

pub fn draws_on_the_timer_test() {
  let g = duel(zap(), zap())
  let assert Ok(g) = game.update(g, Tick(999))
  assert list.length(g.p1.hand) == 3
  let assert Ok(g) = game.update(g, Tick(1000))
  assert list.length(g.p1.hand) == 4
  assert g.p1.next_draw_at == 2000
}

pub fn hand_limit_is_respected_after_a_long_pause_test() {
  let assert Ok(g) = game.update(duel(zap(), zap()), Tick(60_000))
  assert list.length(g.p1.hand) == 5
  assert g.p1.next_draw_at == 61_000
}

pub fn empty_deck_reshuffles_discard_test() {
  // 4 cards total: 3 in hand, 1 in deck.
  let assert Ok(bot) =
    robot.new("Tiny", max_hp: 20, slots: 1)
    |> robot.install(Component("Part", list.repeat(zap(), 4)))
  let g = game.new(config(), p1: bot, p2: bot, seed: 1, now: 0)
  let assert Ok(g) = game.update(g, PlayCard(P1, 0, 0))
  let assert Ok(g) = game.update(g, Tick(1000))
  // The last deck card was drawn; the deck is empty, one card in discard.
  assert g.p1.deck == []
  let assert Ok(g) = game.update(g, Tick(2000))
  assert list.length(g.p1.hand) == 4
  assert g.p1.discard == []
}

pub fn destroying_the_robot_wins_test() {
  let nuke = Card("Nuke", 0, [Damage(99)])
  let assert Ok(g) = game.update(duel(nuke, zap()), PlayCard(P1, 0, 0))
  assert g.status == Won(P1)
  assert g.p2.robot.hp == 0
  assert game.update(g, PlayCard(P2, 0, 0)) == Error(GameOver)
  assert game.update(g, Tick(5000)) == Ok(g)
}

pub fn ai_waits_until_it_has_thought_test() {
  let g = duel(zap(), zap())
  let brain = ai.new(P2, think_ms: 1000, now: 0)
  let #(_, after) = ai.act(brain, g, 500)
  assert after == g
}

pub fn ai_plays_an_affordable_card_test() {
  let g = duel(zap(), zap())
  let brain = ai.new(P2, think_ms: 1000, now: 0)
  let #(brain, g) = ai.act(brain, g, 1000)
  assert g.p1.robot.hp == 17
  assert brain.next_action_at == 2000
}

pub fn ai_prefers_repair_when_hurt_test() {
  let g =
    game.new(
      config(),
      p1: mono_robot("Alpha", zap(), 8),
      p2: catalog.tinker(),
      seed: 1,
      now: 0,
    )
  let hurt = robot.Robot(..g.p2.robot, hp: 10)
  let hand = [zap(), Card("Patch", 3, [Repair(5)])]
  let g = game.Game(..g, p2: game.Combatant(..g.p2, robot: hurt, hand:))
  assert ai.choose(g, P2, 0) == Ok(1)
}
