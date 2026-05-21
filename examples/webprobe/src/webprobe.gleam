import argv
import gleam/io
import webprobe/cli
import webprobe/runner

pub fn main() -> Nil {
  case cli.parse(argv.load().arguments) {
    Ok(config) -> {
      case runner.run(config) {
        Ok(output) -> io.print(output)
        Error(message) -> io.println_error(message)
      }
    }

    Error(message) -> io.println_error(message)
  }
}
