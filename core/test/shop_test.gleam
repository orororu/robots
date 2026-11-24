import gleam/int
import gleam/list
import gleam/option.{Some}
import robots/construction/builder
import robots/construction/part
import robots/content/enemies
import robots/rules/rng
import robots/run/loot
import robots/run/map
import robots/run/price
import robots/run/shop.{Offer}
import robots/run/state.{Run}

fn average_price(
  roll: fn(Int, rng.Seed) -> #(part.Component, rng.Seed),
) -> Int {
  let #(_, prices) =
    list.map_fold(list.repeat(Nil, 300), rng.new(7), fn(seed, _) {
      let #(p, seed) = roll(1, seed)
      #(seed, price.of(p))
    })
  int.sum(prices) / 300
}

pub fn shop_parts_are_the_levels_parts_but_better_test() {
  assert average_price(loot.roll_shop) > average_price(loot.roll)
  let names = list.map(loot.chart(1).entries, fn(e) { { e.1 }.name })
  let #(stock, _) = shop.stock(1, 0, rng.new(3))
  assert list.length(stock.parts) == shop.part_count
  assert list.all(stock.parts, fn(p) { list.contains(names, p.name) })
}

pub fn the_chassis_on_sale_fits_the_level_test() {
  let roster = enemies.level(1)
  let themed =
    list.map(list.append(roster.enemies, roster.strong), fn(e) { e.chassis })
  let #(stock, _) = shop.stock(1, 0, rng.new(3))
  let assert [chassis] = stock.chassis
  assert list.contains(themed, chassis)
  assert shop.chassis_price(chassis) < price.of_chassis(chassis)
}

pub fn robots_are_stripped_to_what_the_player_could_pay_test() {
  let fly = enemies.junk_fly()
  let offer = Offer(fly.name, fly.chassis, fly.parts)
  // Rich: the whole robot.
  assert shop.fit(offer, 10_000) == Ok(offer)
  // Poorer: armor goes first, and it fits the budget.
  let full = shop.robot_price(offer)
  let assert Ok(cheaper) = shop.fit(offer, full - 1)
  assert shop.robot_price(cheaper) <= full - 1
  assert list.length(cheaper.parts) < list.length(offer.parts)
  // Armor is the first to go.
  let armor = fn(o: shop.Offer) {
    list.count(o.parts, fn(p) { p.kind == part.Armor })
  }
  assert armor(cheaper) < armor(offer)
  // It always keeps a weapon and a battery, so it can fight.
  let assert Ok(bare) = shop.fit(offer, minimum_price(offer))
  assert list.any(bare.parts, fn(p) { p.kind == part.Weapon })
  assert list.any(bare.parts, fn(p) { p.kind == part.Battery })
  let assert Ok(_) = builder.build(bare.name, bare.chassis, bare.parts)
  // Too poor even for that: no robot.
  assert shop.fit(offer, minimum_price(offer) - 1) == Error(Nil)
}

/// The price of the robot stripped as far as it goes.
fn minimum_price(offer: shop.Offer) -> Int {
  let keep =
    list.filter(offer.parts, fn(p) {
      p.kind == part.Weapon || p.kind == part.Battery
    })
  shop.robot_price(Offer(..offer, parts: keep))
}

pub fn buying_takes_money_and_stock_test() {
  let run = state.new(1)
  let assert Ok(node) =
    list.find(run.map.nodes, fn(n) { n.event == map.RepairShop })
  let #(stock, _) = shop.stock(1, 1000, rng.new(1))
  let run =
    Run(
      ..run,
      at: Some(node.id),
      phase: state.Repairing(node.id),
      shop: stock,
      money: 1000,
    )
  let assert [first, ..] = stock.parts
  let assert Ok(after) = state.buy_part(run, 0)
  assert after.money == 1000 - shop.part_price(first)
  assert after.parts == [first]
  assert list.length(after.shop.parts) == shop.part_count - 1
  let assert [chassis] = stock.chassis
  let assert Ok(after) = state.buy_chassis(after, 0)
  assert after.chassis == [chassis]
  assert after.shop.chassis == []
  case stock.robots {
    [offer] -> {
      let assert Ok(after) = state.buy_robot(after, 0)
      assert list.map(after.robots, fn(b) { b.name }) == ["Tinker", offer.name]
    }
    _ -> Nil
  }
  // Not enough money.
  assert state.buy_part(Run(..run, money: 0), 0)
    == Error(state.NotEnoughMoney(shop.part_price(first), 0))
  // Leaving clears the stock.
  let assert Ok(left) = state.leave(run)
  assert left.shop == shop.empty
}

pub fn robots_on_sale_fit_the_budget_test() {
  list.each([150, 250, 400], fn(budget) {
    list.each([1, 2, 3, 4, 5], fn(seed) {
      let #(stock, _) = shop.stock(1, budget, rng.new(seed))
      assert list.all(stock.robots, fn(o) { shop.robot_price(o) <= budget })
    })
  })
}
