//// Guide: Managing indexes, steps 1 and 2
////
//// Creates an index for books with settings and a strict mapping, and
//// creates it only when it is missing.

import dream_opensearch/client.{type Client, type OpenSearchError, Rejected}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/json
import gleam/result

/// The settings and the mapping of an index for books.
pub fn books_index_body() -> String {
  json.object([
    #(
      "settings",
      json.object([
        #("number_of_shards", json.int(1)),
        #("number_of_replicas", json.int(1)),
      ]),
    ),
    #(
      "mappings",
      json.object([
        // Refuse documents with fields that the mapping does not name
        #("dynamic", json.string("strict")),
        #(
          "properties",
          json.object([
            #("title", field_type("text")),
            #("author", field_type("keyword")),
            #("year", field_type("integer")),
            #("in_stock", field_type("boolean")),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn field_type(name: String) -> json.Json {
  json.object([#("type", json.string(name))])
}

/// Creates the index `index_name` for books.
pub fn create_books_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, OpenSearchError) {
  document.create_index(opensearch, index_name, books_index_body())
  |> result.replace(Nil)
}

/// Creates the index `index_name` for books, unless it already exists.
pub fn ensure_books_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, OpenSearchError) {
  create_books_index(opensearch, index_name)
  |> result.try_recover(accept_existing)
}

fn accept_existing(error: OpenSearchError) -> Result(Nil, OpenSearchError) {
  case error {
    Rejected(status: 400, body:) -> accept_existing_body(error, body)
    _ -> Error(error)
  }
}

fn accept_existing_body(
  error: OpenSearchError,
  body: String,
) -> Result(Nil, OpenSearchError) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("resource_already_exists_exception") -> Ok(Nil)
    _ -> Error(error)
  }
}
