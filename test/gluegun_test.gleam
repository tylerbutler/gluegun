import gleeunit
import gleeunit/should
import gluegun

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn name_test() {
  gluegun.name()
  |> should.equal("gluegun")
}
