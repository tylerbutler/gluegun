# gluegun

[![Package Version](https://img.shields.io/hexpm/v/gluegun)](https://hex.pm/packages/gluegun)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gluegun/)

A Gleam wrapper for the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client supporting HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Because Gun is Erlang-only, gluegun targets the Erlang runtime.

## Installation

```sh
gleam add gluegun
```

## Usage

```gleam
import gluegun

pub fn main() {
  gluegun.name()
  // -> "gluegun"
}
```

## Development

```sh
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format code
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks
```

## License

MIT
