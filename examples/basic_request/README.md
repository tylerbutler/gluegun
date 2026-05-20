# basic_request

A minimal source-level example showing how to open a connection, make a GET request, read the full response body as text, and close the connection.

## Usage

This example is documentation-only. It is not a separate Gleam package and is not built by the root `just` tasks. To adapt it for your own project:

1. Create a Gleam project targeting Erlang.
2. Run `gleam add gluegun`.
3. Copy `src/basic_request.gleam` into your project and adjust the host, port, and path.

## Notes

- `client.get` collects the full response body in memory. Use `gluegun/request` and `gluegun/message` for streaming or advanced flows.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path.
- Gun is Erlang-only, so this example requires the Erlang target.

## Running

If you want to run it as a standalone project, initialise a Gleam project,
copy the source file, and add the dependencies to `gleam.toml`:

```toml
[dependencies]
gleam_stdlib = ">= 0.48.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_otp    = ">= 1.0.0 and < 2.0.0"
gun          = ">= 2.1.0 and < 3.0.0"
gluegun      = { path = "../.." }
```

Then:

```sh
gleam run
```

> **Note:** The example targets `example.com:80` and requests `/`. Adjust the
> host, port, and path for your own service before running it in production.
