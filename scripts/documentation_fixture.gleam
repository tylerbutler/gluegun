//// Test-only bridge copied into the extracted documentation package.
//// Only endpoint creation and terminal cleanup are instrumented; requests,
//// readiness, result ordering, and ownership stay in the actual examples.

import gluegun/connection.{type ConnectOptions, type Connection}
import gluegun/error.{type GluegunError}

@external(erlang, "documentation_examples_test", "open")
pub fn open(
  options: ConnectOptions,
  host host: String,
  port port: Int,
) -> Result(Connection, GluegunError)

@external(erlang, "documentation_examples_test", "terminate")
pub fn terminate(connection: Connection) -> Result(Nil, GluegunError)

@external(erlang, "documentation_examples_test", "main")
pub fn main() -> Nil
