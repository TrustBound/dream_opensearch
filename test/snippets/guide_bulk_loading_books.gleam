//// Guide: Loading documents in bulk, steps 1 to 5
////
//// Loads books into an index with the bulk API, finds the books
//// that failed, loads in batches and retries the rejected ones.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Book {
  Book(id: String, title: String, author: String, year: Int)
}

pub type FailedItem {
  FailedItem(id: String, status: Int, error_type: String, reason: String)
}

/// Builds the bulk body: an action line and a document line for each book,
/// each line ended by a newline.
pub fn bulk_body(index: String, books: List(Book)) -> String {
  books
  |> list.flat_map(book_lines(index, _))
  |> list.map(fn(line) { json.to_string(line) <> "\n" })
  |> string.concat
}

fn book_lines(index: String, book: Book) -> List(json.Json) {
  let action =
    json.object([
      #(
        "index",
        json.object([
          #("_index", json.string(index)),
          #("_id", json.string(book.id)),
        ]),
      ),
    ])
  let source =
    json.object([
      #("title", json.string(book.title)),
      #("author", json.string(book.author)),
      #("year", json.int(book.year)),
    ])
  [action, source]
}

/// Loads `books` in one bulk request. Returns the books that failed.
pub fn load_books(
  opensearch: Client,
  index: String,
  books: List(Book),
) -> Result(List(FailedItem), String) {
  use body <- result.try(
    document.bulk(opensearch, bulk_body(index, books))
    |> result.map_error(client.describe_error),
  )
  failed_items(body)
}

/// Reads the failed items out of the body of a bulk response.
pub fn failed_items(body: String) -> Result(List(FailedItem), String) {
  json.parse(body, decode.at(["items"], decode.list(item_decoder())))
  |> result.map(option.values)
  |> result.replace_error("Unexpected bulk response: " <> body)
}

// Each item has one key: the action of its line in the request
fn item_decoder() -> decode.Decoder(Option(FailedItem)) {
  decode.one_of(decode.at(["index"], outcome_decoder()), [
    decode.at(["create"], outcome_decoder()),
    decode.at(["update"], outcome_decoder()),
    decode.at(["delete"], outcome_decoder()),
  ])
}

fn outcome_decoder() -> decode.Decoder(Option(FailedItem)) {
  use id <- decode.field("_id", decode.string)
  use status <- decode.field("status", decode.int)
  use error <- decode.optional_field(
    "error",
    None,
    decode.map(error_decoder(), Some),
  )
  decode.success(
    option.map(error, fn(error) {
      let #(error_type, reason) = error
      FailedItem(id:, status:, error_type:, reason:)
    }),
  )
}

fn error_decoder() -> decode.Decoder(#(String, String)) {
  use error_type <- decode.field("type", decode.string)
  use reason <- decode.field("reason", decode.string)
  decode.success(#(error_type, reason))
}

/// Loads `books` with one bulk request for each `batch_size` books. Stops at
/// the first request that fails as a whole.
pub fn load_in_batches(
  opensearch: Client,
  index: String,
  books: List(Book),
  batch_size: Int,
) -> Result(List(FailedItem), String) {
  books
  |> list.sized_chunk(batch_size)
  |> list.try_fold([], fn(failed, batch) {
    use batch_failed <- result.map(load_books(opensearch, index, batch))
    list.append(failed, batch_failed)
  })
}

/// Loads once more the books that OpenSearch rejected with status 429
/// (too many requests). Returns the books that still failed.
pub fn retry_rejected(
  opensearch: Client,
  index: String,
  books: List(Book),
  failed: List(FailedItem),
) -> Result(List(FailedItem), String) {
  let #(rejected, permanent) =
    list.partition(failed, fn(item) { item.status == 429 })
  let rejected_ids = list.map(rejected, fn(item) { item.id })
  case list.filter(books, fn(book) { list.contains(rejected_ids, book.id) }) {
    [] -> Ok(permanent)
    retry -> {
      use still_failed <- result.map(load_books(opensearch, index, retry))
      list.append(permanent, still_failed)
    }
  }
}
