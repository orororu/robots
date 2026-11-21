import gleam/list
import robots/catalog
import robots/efficiency
import robots/robot

/// Every catalog card must fit its role's efficiency band. Defence, buffs and
/// repair are rated above attacks, so builds aren't all glass cannons.
pub fn every_catalog_card_is_within_its_band_test() {
  let outliers =
    catalog.components()
    |> list.flat_map(fn(component) { component.cards })
    |> list.filter(fn(card) { !efficiency.within_band(card) })
    |> list.map(fn(card) { card.name })
  assert outliers == []
}

pub fn starter_robots_only_use_catalog_components_test() {
  let names = list.map(catalog.components(), fn(c) { c.name })
  let used =
    list.flat_map([catalog.tinker(), catalog.scrapper()], fn(bot: robot.Robot) {
      list.map(bot.components, fn(c) { c.name })
    })
  assert list.all(used, list.contains(names, _))
}

pub fn non_damage_roles_are_rated_above_damage_test() {
  let damage = efficiency.target(efficiency.Damage)
  assert efficiency.target(efficiency.Weaken) >. damage
  assert efficiency.target(efficiency.Strengthen) >. damage
  assert efficiency.target(efficiency.Repair) >. damage
}
