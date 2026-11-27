//// How things read: errors, rewards, and one-line descriptions of robots,
//// parts, weight and weapon mounts.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/construction/wear
import robots/meta/blueprint
import robots/meta/profile
import robots/rules/game
import robots/rules/scale.{type Scale}
import robots/run/price
import robots/run/shop
import robots/run/state.{type Bot, type Run}
import robots_client/components/battle_view

pub fn describe_profile_error(e: profile.Error) -> String {
  case e {
    profile.FabricatorFull ->
      "The fabricator builds "
      <> int.to_string(blueprint.max_fabricator)
      <> " robots already: sell this one."
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

pub fn describe_rejection(s: Scale, rejection: game.Rejection) -> String {
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

pub fn describe_error(error: state.Error) -> String {
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

pub fn describe_reward(
  before: Run,
  after: Run,
  reward: state.Reward,
) -> String {
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

/// "18 cards", or "13 cards (small deck)".
pub fn offer_deck(o: shop.Offer) -> String {
  deck_text(builder.deck_size(o.chassis, o.parts))
}

/// "18 cards", or with a warning below `builder.minimum_deck`.
pub fn deck_text(cards: Int) -> String {
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

/// "Tinker (Frame) HP [######....] 9/12"
pub fn bot_line(s: Scale, bot: Bot) -> String {
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
pub fn by_kind(parts: List(Component)) -> List(#(Int, Component)) {
  parts
  |> list.index_map(fn(p, i) { #(i, p) })
  |> list.sort(fn(a, b) {
    case int.compare(kind_rank({ a.1 }.kind), kind_rank({ b.1 }.kind)) {
      order.Eq -> int.compare(a.0, b.0)
      other -> other
    }
  })
}

pub fn kind_rank(kind: part.Kind) -> Int {
  case kind {
    part.Body -> 0
    part.Weapon -> 1
    part.Defence -> 2
    part.Utility -> 3
    part.Battery -> 4
    part.Armor -> 5
  }
}

pub fn kind_plural(kind: part.Kind) -> String {
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
pub fn own_chassis_line(s: Scale, bot: Bot) -> String {
  bot.chassis.name
  <> " chassis · HP "
  <> int.to_string(scale.value(s, builder.chassis_hp(bot.chassis)))
  <> "/"
  <> int.to_string(scale.value(s, bot.chassis.hp))
}

/// "Weight 11 of max 12 · 1 free · 18 cards" (with a warning for a deck
/// below the minimum).
pub fn weight_line(bot: Bot) -> String {
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
pub fn mounts_line(bot: Bot) -> String {
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

/// "Broken plating · armor · weight 2 · HP 0/25 · 25 scrap"
pub fn part_line(s: Scale, p: Component) -> String {
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

pub fn num(x: Float) -> String {
  let rounded = float.to_precision(x, 1)
  case rounded == float.floor(rounded) {
    True -> int.to_string(float.truncate(rounded))
    False -> float.to_string(rounded)
  }
}
