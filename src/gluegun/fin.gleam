//// Fin (final) flags for Gun HTTP streaming.
////
//// `Fin` marks the last chunk in a request or response body. `NoFin`
//// indicates more data will follow.

/// Fin (final) flag for a Gun HTTP body chunk.
pub type Fin {
  /// This chunk is the last one in the body. Gun will not deliver more data.
  Fin
  /// More data will follow. Continue to send or receive chunks.
  NoFin
}
