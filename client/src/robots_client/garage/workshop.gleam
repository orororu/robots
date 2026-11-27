//// The workshop: upgrade one component for free, in the garage.

import lustre/element.{type Element}
import lustre/element/html
import robots_client/common/ui.{button_class, text}
import robots_client/garage/model.{type Msg, Leave}
import robots_client/garage/view.{type GarageView, view_garage}

pub fn view_workshop(g: GarageView) -> Element(Msg) {
  html.div([], [
    text(
      "",
      "WORKSHOP · select a component below, then upgrade it: one card gets a "
        <> "good attribute, or a good one goes up a tier. Free, once.",
    ),
    button_class(">>> Leave without upgrading", "banner", Leave),
    view_garage(g),
  ])
}
