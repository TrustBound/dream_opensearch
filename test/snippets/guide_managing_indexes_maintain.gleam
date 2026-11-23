//// Guide: Managing indexes, steps 3 to 5
////
//// Calls the index APIs that the `document` module does not cover, with
//// `client.send_request`, and deletes an index.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result

/// Tells whether the index `index_name` exists.
pub fn index_exists(
  opensearch: Client,
  index_name: String,
) -> Result(Bool, String) {
  case client.send_request(opensearch, http.Get, "/" <> index_name, "") {
    Ok(_) -> Ok(True)
    Error(body) -> accept_not_found(body)
  }
}

fn accept_not_found(body: String) -> Result(Bool, String) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("index_not_found_exception") -> Ok(False)
    _ -> Error(body)
  }
}

/// Makes the documents indexed so far visible to search.
pub fn refresh_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  client.send_request(
    opensearch,
    http.Post,
    "/" <> index_name <> "/_refresh",
    "",
  )
  |> result.replace(Nil)
}

/// Counts the documents in the index `index_name`.
pub fn count_documents(
  opensearch: Client,
  index_name: String,
) -> Result(Int, String) {
  use body <- result.try(client.send_request(
    opensearch,
    http.Get,
    "/" <> index_name <> "/_count",
    "",
  ))
  json.parse(body, decode.at(["count"], decode.int))
  |> result.replace_error("Unexpected count response: " <> body)
}

/// Copies every document of `source` into `destination`. Returns how many
/// documents OpenSearch created.
pub fn copy_index(
  opensearch: Client,
  source: String,
  destination: String,
) -> Result(Int, String) {
  let body =
    json.object([
      #("source", json.object([#("index", json.string(source))])),
      #("dest", json.object([#("index", json.string(destination))])),
    ])
    |> json.to_string
  use response <- result.try(client.send_request(
    opensearch,
    http.Post,
    "/_reindex",
    body,
  ))
  json.parse(response, decode.at(["created"], decode.int))
  |> result.replace_error("Unexpected reindex response: " <> response)
}

/// Deletes the index `index_name`. An index that is not there is not an
/// error.
pub fn delete_index_if_present(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  document.delete_index(opensearch, index_name)
  |> result.replace(Nil)
  |> result.try_recover(accept_missing)
}

fn accept_missing(body: String) -> Result(Nil, String) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("index_not_found_exception") -> Ok(Nil)
    _ -> Error(body)
  }
}
