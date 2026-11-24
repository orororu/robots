import gleam/list
import gleam/option.{None, Some}
import robots/construction/attribute as a
import robots/construction/part.{type Component}
import robots/content/components
import robots/rules/rng
import robots/run/upgrade

fn upgraded(p: Component, seed: Int) -> Component {
  let assert Ok(#(p, _, _)) = upgrade.apply(p, rng.new(seed))
  p
}

/// Every card's attribute name ("" for none), card by card.
fn attributes(p: Component) -> List(String) {
  list.index_map(p.cards, fn(_, i) {
    case list.key_find(p.attributes, i) {
      Ok(attr) -> attr.name
      Error(Nil) -> ""
    }
  })
}

pub fn an_upgrade_gives_one_card_a_good_attribute_test() {
  let laser = components.laser()
  list.each([1, 2, 3, 4, 5], fn(seed) {
    let assert Ok(#(p, change, _)) = upgrade.apply(laser, rng.new(seed))
    assert list.length(p.attributes) == 1
    let assert [#(i, attr)] = p.attributes
    let assert [c, ..] = list.drop(laser.cards, i)
    assert a.is_good(attr, c)
    assert change.card == i
    assert change.before == c
    assert change.after.name == attr.name <> " " <> c.name
    assert change.attribute == attr.name
    assert change.replaced == None
  })
}

pub fn an_upgrade_replaces_a_bad_attribute_test() {
  let laser = components.laser()
  let worn =
    list.index_fold(laser.cards, laser, fn(p, _, i) {
      part.attach(p, i, a.damaged())
    })
  let assert Ok(#(p, change, _)) = upgrade.apply(worn, rng.new(1))
  assert change.replaced == Some("Damaged")
  let damaged = list.count(attributes(p), fn(n) { n == "Damaged" })
  assert damaged == list.length(laser.cards) - 1
}

pub fn when_every_card_is_good_an_attribute_goes_up_a_tier_test() {
  let laser = components.laser()
  let tuned =
    list.index_fold(laser.cards, laser, fn(p, _, i) {
      part.attach(p, i, a.tuned())
    })
  let p = upgraded(tuned, 1)
  assert list.count(attributes(p), fn(n) { n == "Strong" }) == 1
  assert list.count(attributes(p), fn(n) { n == "Tuned" })
    == list.length(laser.cards) - 1
}

pub fn a_component_at_its_best_cant_be_upgraded_test() {
  let laser = components.laser()
  let best =
    list.index_fold(laser.cards, laser, fn(p, _, i) {
      part.attach(p, i, a.masterwork())
    })
  assert !upgrade.can_upgrade(best)
  assert upgrade.can_upgrade(laser)
}

pub fn upgrades_keep_going_until_the_top_test() {
  // Upgrading over and over ends with every card at a top attribute.
  let laser = components.laser()
  let #(p, _) =
    list.fold(list.repeat(Nil, 40), #(laser, rng.new(9)), fn(acc, _) {
      let #(p, seed) = acc
      case upgrade.apply(p, seed) {
        Ok(#(p, _, seed)) -> #(p, seed)
        Error(Nil) -> acc
      }
    })
  assert !upgrade.can_upgrade(p)
  assert list.all(attributes(p), fn(n) { n == "Masterwork" || n == "Rapid" })
}
