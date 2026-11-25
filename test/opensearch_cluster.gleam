//// The real OpenSearch that the tests run against.
////
//// `make search-up` starts it from `docker-compose.yml`. The base URLs come
//// from the environment, with the ports of that file as the defaults:
////
//// - `OPENSEARCH_URL` (default `http://localhost:9201`): the node with the
////   security plugin off, for almost every test.
//// - `OPENSEARCH_SECURED_URL` (default `http://localhost:9202`): the node
////   with the security plugin on, for the tests of HTTP Basic
////   authentication. Its admin password is `secured_admin_password`.
////
//// Each test gets its own index name from `index_name`, and `with_index`
//// deletes that index after the test. So the tests can run in any order and
//// at the same time.

import dream_http_client/client as http_client
import dream_http_client/recorder
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri

/// The admin password of the secured node in `docker-compose.yml`. It is a
/// made-up value for tests, with the characters `:`, `@` and `/`, which a
/// URL must percent-encode.
pub const secured_admin_password = "Test:P@ss/w0rd!"

@external(erlang, "opensearch_cluster_ffi", "environment_value")
fn environment_value(name: String, default: String) -> String

@external(erlang, "opensearch_cluster_ffi", "unique_suffix")
fn unique_suffix() -> String

@external(erlang, "opensearch_cluster_ffi", "halt")
fn halt(status: Int) -> Nil

/// The base URL of the node with the security plugin off.
pub fn base_url() -> String {
  environment_value("OPENSEARCH_URL", "http://localhost:9201")
}

/// The base URL of the node with the security plugin on, with no user name
/// and no password in it.
pub fn secured_base_url() -> String {
  environment_value("OPENSEARCH_SECURED_URL", "http://localhost:9202")
}

/// The mode of the recorder of the recorded tests: `Record` when the
/// environment variable `RECORD_OPENSEARCH` is `true`, which sends the
/// requests to the node at `http://localhost:9201` and writes the
/// recordings again, and `Playback` otherwise, which needs no cluster.
pub fn recorder_mode() -> recorder.Mode {
  case environment_value("RECORD_OPENSEARCH", "false") {
    "true" -> recorder.Record
    _ -> recorder.Playback
  }
}

/// A client from a base request for `http://localhost:9201` with a
/// recorder in `mode` on the recordings in `directory`. Returns the
/// recorder too, so the test can stop it.
pub fn recorded_client(
  directory: String,
  mode: recorder.Mode,
) -> Result(#(Client, recorder.Recorder), String) {
  use started <- result.map(
    recorder.new()
    |> recorder.directory(directory)
    |> recorder.mode(mode)
    |> recorder.start,
  )
  let opensearch =
    http_client.new()
    |> http_client.scheme(http.Http)
    |> http_client.host("localhost")
    |> http_client.port(9201)
    |> http_client.recorder(started)
    |> client.from_request
  #(opensearch, started)
}

/// A client for the node with the security plugin off.
pub fn client() -> Client {
  let assert Ok(opensearch) = client.new(base_url())
    as "OPENSEARCH_URL is not a URL that client.new can use"
  opensearch
}

/// A client for `url`. Stops the test with a message when `client.new`
/// cannot use the URL.
pub fn client_for(url: String) -> Client {
  let assert Ok(opensearch) = client.new(url)
    as "client.new cannot use the base URL of the test"
  opensearch
}

/// The base URL that the base request of `opensearch` stands for: the
/// scheme, the host, the port when it is set, and the path prefix. It has
/// no user name and no password.
pub fn base_url_of(opensearch: Client) -> String {
  let base = client.base_request(opensearch)
  let port = case http_client.get_port(base) {
    option.Some(port) -> ":" <> int.to_string(port)
    option.None -> ""
  }
  http.scheme_to_string(http_client.get_scheme(base))
  <> "://"
  <> http_client.get_host(base)
  <> port
  <> http_client.get_path(base)
}

/// A new index name that starts with `prefix`, for example
/// `books_1763891234567890_12`. No other call returns the same name.
pub fn index_name(prefix: String) -> String {
  prefix <> "_" <> unique_suffix()
}

/// Runs `test_body` with a client and a new index name that starts with
/// `prefix`, then deletes that index. Returns the result of `test_body`, or
/// the error of the delete when the index could not be deleted. An index
/// that `test_body` never created is not an error.
pub fn with_index(
  prefix: String,
  test_body: fn(Client, String) -> Result(value, String),
) -> Result(value, String) {
  let opensearch = client()
  use index <- with_index_on(opensearch, prefix)
  test_body(opensearch, index)
}

/// Like `with_index`, on the cluster of `opensearch`, which also deletes
/// the index.
pub fn with_index_on(
  opensearch: Client,
  prefix: String,
  test_body: fn(String) -> Result(value, String),
) -> Result(value, String) {
  let index = index_name(prefix)
  let outcome = test_body(index)
  use Nil <- result.try(delete_index_if_present(opensearch, index))
  outcome
}

/// Like `with_index`, with two index names.
pub fn with_two_indexes(
  prefix: String,
  test_body: fn(Client, String, String) -> Result(value, String),
) -> Result(value, String) {
  use opensearch, first <- with_index(prefix)
  use second <- with_index_on(opensearch, prefix)
  test_body(opensearch, first, second)
}

/// A client for the secured node, as `admin` with the right password.
pub fn secured_admin_client() -> Result(Client, String) {
  secured_client("admin", secured_admin_password)
}

/// A client for the secured node with this user name and password, put in
/// the base URL percent-encoded.
pub fn secured_client(
  user: String,
  password: String,
) -> Result(Client, String) {
  use parsed <- result.try(
    uri.parse(secured_base_url())
    |> result.replace_error("OPENSEARCH_SECURED_URL cannot be parsed"),
  )
  let userinfo = uri.percent_encode(user) <> ":" <> uri.percent_encode(password)
  client.new(uri.to_string(uri.Uri(..parsed, userinfo: option.Some(userinfo))))
  |> result.map_error(client.describe_error)
}

fn delete_index_if_present(
  opensearch: Client,
  index: String,
) -> Result(Nil, String) {
  case document.delete_index(opensearch, index) {
    Ok(_) -> Ok(Nil)
    Error(client.Rejected(body:, ..)) -> accept_missing_index(body)
    Error(error) -> Error(client.describe_error(error))
  }
}

fn accept_missing_index(body: String) -> Result(Nil, String) {
  case error_type(body) {
    Ok("index_not_found_exception") -> Ok(Nil)
    _ -> Error(body)
  }
}

/// Makes the documents indexed so far in `index` visible to search.
pub fn refresh(opensearch: Client, index: String) -> Result(Nil, String) {
  client.send_request(opensearch, http.Post, "/" <> index <> "/_refresh", "")
  |> result.replace(Nil)
  |> result.map_error(client.describe_error)
}

/// The `error.type` of an OpenSearch error body.
pub fn error_type(body: String) -> Result(String, Nil) {
  json.parse(body, decode.at(["error", "type"], decode.string))
  |> result.replace_error(Nil)
}

/// The `error.type` of the body and the status of a `Rejected` error, for
/// example `Ok(#("index_not_found_exception", 404))`. `Error(Nil)` for any
/// other error, or a body with no `error.type`.
pub fn error_type_and_status(
  error: client.OpenSearchError,
) -> Result(#(String, Int), Nil) {
  case error {
    client.Rejected(status:, body:) ->
      error_type(body) |> result.map(fn(error_type) { #(error_type, status) })
    _ -> Error(Nil)
  }
}

/// The body in the text that `client.describe_error` makes of a `Rejected`
/// error, or the whole text for any other error.
pub fn described_body(text: String) -> String {
  case text {
    "OpenSearch rejected the request with status " <> rest ->
      string.split_once(rest, ": ")
      |> result.map(fn(parts) { parts.1 })
      |> result.unwrap(text)
    _ -> text
  }
}

/// Like `error_type_and_status`, for the text that `client.describe_error`
/// makes of a `Rejected` error.
pub fn described_type_and_status(text: String) -> Result(#(String, Int), Nil) {
  case text {
    "OpenSearch rejected the request with status " <> rest -> {
      use #(status, body) <- result.try(string.split_once(rest, ": "))
      use status <- result.try(int.parse(status))
      error_type_and_status(client.Rejected(status:, body:))
    }
    _ -> Error(Nil)
  }
}

/// The error of `outcome` as the text of `client.describe_error`, for the
/// tests that collect errors of more than one kind as text.
pub fn as_text(
  outcome: Result(value, client.OpenSearchError),
) -> Result(value, String) {
  result.map_error(outcome, client.describe_error)
}

/// The error of `outcome` as the body of a `Rejected` error, and any other
/// error as the text of `client.describe_error`.
pub fn rejected_body(
  outcome: Result(value, client.OpenSearchError),
) -> Result(value, String) {
  result.map_error(outcome, fn(error) {
    case error {
      client.Rejected(body:, ..) -> body
      _ -> client.describe_error(error)
    }
  })
}

/// Stops the test run with a clear message when the cluster does not
/// answer. Call it before the tests start.
pub fn require_cluster() -> Nil {
  case client.send_request(client(), http.Get, "/", "") {
    Ok(_) -> Nil
    Error(error) -> stop_without_cluster(client.describe_error(error))
  }
}

fn stop_without_cluster(message: String) -> Nil {
  list.each(
    [
      "",
      "The tests need OpenSearch at "
        <> base_url()
        <> ", and it did not answer:",
      "  " <> message,
      "Start it with `make search-up` (Docker), or set OPENSEARCH_URL and",
      "OPENSEARCH_SECURED_URL to a running cluster. Stop it with `make search-down`.",
      "",
    ],
    io.println_error,
  )
  halt(1)
}
