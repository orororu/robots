import gleam/list
import gleam/option.{Some}
import gleam/string
import robots/construction/attribute
import robots/construction/builder
import robots/construction/part
import robots/content/components
import robots/meta/blueprint.{PartBlueprint}
import robots/rules/rng
import robots/run/map
import robots/run/save
import robots/run/shop
import robots/run/state.{Run}

pub fn a_new_run_survives_saving_test() {
  list.each([1, 2, 3, 4, 5], fn(seed) {
    let run = state.new(seed)
    assert save.decode(save.encode(run)) == Ok(run)
  })
}

pub fn every_level_map_survives_saving_test() {
  // Every enemy on every level: their worn parts and chassis come back.
  list.each([1, 2, 3], fn(level) {
    list.each([1, 2, 3], fn(seed) {
      let #(m, _) = map.generate(level, rng.new(seed))
      let run = Run(..state.new(seed), level:, map: m)
      assert save.decode(save.encode(run)) == Ok(run)
    })
  })
}

pub fn wear_modifiers_attributes_and_the_rest_survive_saving_test() {
  let laser =
    components.laser()
    |> part.with(part.light())
    |> part.with(part.overclocked())
  let laser = part.Component(..laser, attributes: [#(1, attribute.strong())])
  let plate = part.Component(..components.plating(), wear: 1.25)
  let #(stock, _) = shop.stock(2, 300, rng.new(3))
  let run =
    Run(
      ..state.new(9),
      at: Some(3),
      path: [1, 3],
      phase: state.Repairing(3),
      parts: [laser, plate],
      chassis: [builder_frame_worn()],
      money: 123,
      shop: stock,
      truck: 3,
      wins: [map.Boss, map.Normal],
      found: [PartBlueprint("Railgun")],
    )
  let assert Ok(back) = save.decode(save.encode(run))
  assert back == run
  // The seed carries on exactly: the same next shuffle.
  assert rng.next(back.seed) == rng.next(run.seed)
}

fn builder_frame_worn() {
  builder.Chassis(..components.frame(), wear: 0.5)
}

pub fn a_broken_save_does_not_load_test() {
  assert save.decode("") == Error(Nil)
  assert save.decode("(1 (garbage") == Error(Nil)
  // Something no longer in the game.
  let text = save.encode(state.new(1))
  let gone = text |> string.replace("\"Laser\"", "\"Gone gun\"")
  assert save.decode(gone) == Error(Nil)
}
