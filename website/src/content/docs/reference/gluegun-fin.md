---
title: gluegun/fin
description: Fin (final) flags for Gun HTTP streaming.
---

# `gluegun/fin`

Fin (final) flags for Gun HTTP streaming.

 `Fin` marks the last chunk in a request or response body. `NoFin`
 indicates more data will follow.

## Types

### `Fin`

Fin (final) flag for a Gun HTTP body chunk.

```gleam
pub type Fin {
  Fin
  NoFin
}
```

**Constructors**

#### `Fin`

This chunk is the last one in the body. Gun will not deliver more data.

#### `NoFin`

More data will follow. Continue to send or receive chunks.
