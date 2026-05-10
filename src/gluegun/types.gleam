import gluegun/request

pub type Method =
  request.Method

pub type Header =
  request.Header

pub fn method_to_string(method: Method) -> String {
  request.method_to_string(method)
}

pub fn normalize_headers(headers: List(Header)) -> List(Header) {
  request.normalize_headers(headers)
}
