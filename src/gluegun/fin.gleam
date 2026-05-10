//// Fin (final) flags for Gun HTTP streaming.
////
//// `Fin` marks the last chunk in a request or response body. `NoFin`
//// indicates more data will follow.

pub type Fin {
  Fin
  NoFin
}
