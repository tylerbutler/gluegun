import argv
import gleam/io
import webprobe/cli
import webprobe/runner

// Halts the CLI's Erlang runtime, flushing outstanding output before exiting.
// This function never returns.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

pub fn main() -> Nil {
  case cli.parse(argv.load().arguments) {
    Ok(cli.Help) -> io.print(cli.help_text())
    Ok(cli.Probe(config)) -> {
      case runner.run(config) {
        Ok(output) -> io.print(output)
        Error(message) -> {
          io.println_error(message)
          halt(1)
        }
      }
    }

    Error(message) -> {
      io.println_error(message)
      halt(1)
    }
  }
}
