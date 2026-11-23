//// The output files of the guides, under `test/outputs/`.
////
//// Each `text` block of a guide is a copy of one output file, and a test
//// compares that file with the real output of the code. A value or a
//// printed line is compared as it is. A response body of OpenSearch is
//// compared with `stable_json`, which leaves out the fields that change
//// from run to run, and which the guide names next to the block.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

@external(erlang, "guide_output_ffi", "read_file")
fn read_file(path: String) -> Result(String, Nil)

@external(erlang, "guide_output_ffi", "without_keys")
fn without_keys(term: Dynamic, keys: List(String)) -> Dynamic

/// The text of `test/outputs/<name>.txt`, with its final line break. When
/// the file cannot be read, a message that names the file, so the test
/// fails with that message.
pub fn file(name: String) -> String {
  let path = "test/outputs/" <> name <> ".txt"
  case read_file(path) {
    Ok(text) -> text
    Error(Nil) -> "The output file " <> path <> " cannot be read"
  }
}

/// `text` as the lines of an output file: with a final line break.
pub fn lines(text: String) -> String {
  text <> "\n"
}

/// `value` printed with `string.inspect`, as one line of an output file.
pub fn inspected(value: anything) -> String {
  lines(string.inspect(value))
}

/// A method, a path and an optional body, as the guides show a request:
/// the request line, then the body on the next line when there is one.
pub fn request(method: String, target: String, body: String) -> String {
  case body {
    "" -> lines(method <> " " <> target)
    _ -> lines(method <> " " <> target <> "\n" <> body)
  }
}

/// The JSON of `body` with the keys `varying` left out at every depth, for
/// a comparison of the fields that do not change from run to run.
pub fn stable_json(
  body: String,
  varying: List(String),
) -> Result(Dynamic, String) {
  json.parse(body, decode.dynamic)
  |> result.map(without_keys(_, varying))
  |> result.replace_error("Not JSON: " <> body)
}

/// Like `stable_json`, for a body from an index of a test: every
/// `test_index` in the body is `shown_index` first, the index name that the
/// guide shows.
pub fn stable_body(
  body: String,
  test_index: String,
  shown_index: String,
  varying: List(String),
) -> Result(Dynamic, String) {
  stable_json(string.replace(body, test_index, shown_index), varying)
}

/// The stable fields of the output file `name`, as `stable_json` reads them.
pub fn stable_file(
  name: String,
  varying: List(String),
) -> Result(Dynamic, String) {
  stable_json(file(name), varying)
}
