import gleam/list
import robots/card
import robots/catalog
import robots/efficiency
import robots/part
import robots/robot

/// Every catalog card must fit its role's efficiency band. Defence and buffs
/// are rated above attacks, so builds aren't all glass cannons.
pub fn every_catalog_card_is_within_its_band_test() {
  let part_cards =
    catalog.components()
    |> list.filter(fn(component) { component.kind != part.Armor })
    |> list.flat_map(fn(component) { component.cards })
  let chassis_cards = list.flat_map(catalog.chassis(), fn(ch) { ch.cards })
  let outliers =
    list.append(part_cards, chassis_cards)
    |> list.filter(fn(card) { !efficiency.within_band(card) })
    |> list.map(fn(card) { card.name })
  assert outliers == []
}

pub fn once_cards_are_rated_above_their_role_test() {
  let missile = catalog.missile_rack().cards |> list.first
  let assert Ok(missile) = missile
  assert card.has_trait(missile, card.Once)
  assert efficiency.goal(missile)
    == efficiency.goal_for(efficiency.Damage, missile.cost)
    *. efficiency.once_bonus
}

/// Armor's Block is weak on purpose, so stacking armor dilutes the deck.
pub fn armor_cards_are_below_the_band_test() {
  let block = catalog.block()
  assert efficiency.rating(block) <. efficiency.goal(block)
  assert !efficiency.within_band(block)
}

pub fn starter_robots_only_use_catalog_components_test() {
  let names = list.map(catalog.components(), fn(c) { c.name })
  let used =
    list.flat_map([catalog.tinker(), catalog.scrapper()], fn(bot: robot.Robot) {
      bot.components
      |> list.filter(fn(c) { c.kind != part.Body })
      |> list.map(fn(c) { c.name })
    })
  assert list.all(used, list.contains(names, _))
}

const costs = [0.5, 0.6, 0.8, 1.0, 1.5, 2.0]

const roles = [
  efficiency.Damage,
  efficiency.Weaken,
  efficiency.Strengthen,
]

pub fn bigger_cards_are_more_efficient_in_every_role_test() {
  list.each(roles, fn(role) {
    list.window_by_2(costs)
    |> list.each(fn(pair) {
      assert efficiency.goal_for(role, pair.1)
        >. efficiency.goal_for(role, pair.0)
    })
  })
}

pub fn defence_and_buffs_beat_attacks_of_the_same_cost_test() {
  list.each(list.drop(costs, 1), fn(cost) {
    let attack = efficiency.goal_for(efficiency.Damage, cost)
    assert efficiency.goal_for(efficiency.Weaken, cost) >. attack
    assert efficiency.goal_for(efficiency.Strengthen, cost) >. attack
  })
}

pub fn the_margin_over_attacks_grows_with_cost_test() {
  let margin = fn(cost) {
    efficiency.goal_for(efficiency.Weaken, cost)
    -. efficiency.goal_for(efficiency.Damage, cost)
  }
  assert margin(1.5) >. margin(1.0)
  assert margin(1.0) >. margin(0.6)
}

pub fn cheap_defence_does_not_outperform_attacks_test() {
  // So fast, small defences can't stall the round.
  let cheap = efficiency.bonus_pivot_cost
  assert efficiency.goal_for(efficiency.Weaken, cheap)
    == efficiency.goal_for(efficiency.Damage, cheap)
}
