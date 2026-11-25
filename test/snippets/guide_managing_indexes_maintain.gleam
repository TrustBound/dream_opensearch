//// Guide: Managing indexes, steps 3 to 5
////
//// Calls the index APIs that the `document` module does not cover, with
//// `client.send_request`, and deletes an index.

import dream_opensearch/client.{type Client, type OpenSearchError, Rejected}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result

/// Tells whether the index `index_name` exists.
pub fn index_exists(
  opensearch: Client,
  index_name: String,
) -> Result(Bool, OpenSearchError) {
  case client.send_request(opensearch, http.Get, "/" <> index_name, "") {
    Ok(_) -> Ok(True)
    Error(Rejected(status: 404, ..)) -> Ok(False)
    Error(error) -> Error(error)
  }
}

/// Makes the documents indexed so far visible to search.
pub fn refresh_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, OpenSearchError) {
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
  use body <- result.try(
    client.send_request(
      opensearch,
      http.Get,
      "/" <> index_name <> "/_count",
      "",
    )
    |> result.map_error(client.describe_error),
  )
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
  use response <- result.try(
    client.send_request(opensearch, http.Post, "/_reindex", body)
    |> result.map_error(client.describe_error),
  )
  json.parse(response, decode.at(["created"], decode.int))
  |> result.replace_error("Unexpected reindex response: " <> response)
}

/// Deletes the index `index_name`. An index that is not there is not an
/// error.
pub fn delete_index_if_present(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, OpenSearchError) {
  case document.delete_index(opensearch, index_name) {
    Ok(_) -> Ok(Nil)
    Error(Rejected(status: 404, ..)) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}
