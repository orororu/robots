//// The run's map: what it shows besides the map itself, and its messages.

import gleam/option.{type Option, None}
import robots/run/upgrade

/// What the map tells the player: what the last step did (a battle's pay,
/// a purchase), and the last workshop upgrade, until the next step.
pub type Journal {
  Journal(news: String, upgraded: Option(#(String, upgrade.Change)))
}

pub fn new_journal(news: String) -> Journal {
  Journal(news:, upgraded: None)
}

pub type Msg {
  /// Go to this node.
  Go(node: Int)
  /// After a run: pay it out and go to the hangar.
  ToHangar
}
