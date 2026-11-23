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

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/http
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
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

/// A client for the node with the security plugin off.
pub fn client() -> Client {
  client.new(base_url())
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
  use parsed <- result.map(
    uri.parse(secured_base_url())
    |> result.replace_error("OPENSEARCH_SECURED_URL cannot be parsed"),
  )
  let userinfo = uri.percent_encode(user) <> ":" <> uri.percent_encode(password)
  client.new(uri.to_string(uri.Uri(..parsed, userinfo: option.Some(userinfo))))
}

fn delete_index_if_present(
  opensearch: Client,
  index: String,
) -> Result(Nil, String) {
  case document.delete_index(opensearch, index) {
    Ok(_) -> Ok(Nil)
    Error(body) -> accept_missing_index(body)
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
}

/// The `error.type` of an OpenSearch error body.
pub fn error_type(body: String) -> Result(String, Nil) {
  json.parse(body, decode.at(["error", "type"], decode.string))
  |> result.replace_error(Nil)
}

/// The `error.type` and `status` of an OpenSearch error body, for example
/// `Ok(#("index_not_found_exception", 404))`.
pub fn error_type_and_status(body: String) -> Result(#(String, Int), Nil) {
  let decoder = {
    use error_type <- decode.subfield(["error", "type"], decode.string)
    use status <- decode.field("status", decode.int)
    decode.success(#(error_type, status))
  }
  json.parse(body, decoder)
  |> result.replace_error(Nil)
}

/// Stops the test run with a clear message when the cluster does not
/// answer. Call it before the tests start.
pub fn require_cluster() -> Nil {
  case client.send_request(client(), http.Get, "/", "") {
    Ok(_) -> Nil
    Error(message) -> stop_without_cluster(message)
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
