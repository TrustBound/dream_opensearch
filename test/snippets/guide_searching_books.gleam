//// Guide: Searching an index, steps 1 to 3
////
//// Searches an index of books with the query builders and reads the hits
//// into Gleam values.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

pub type Book {
  Book(id: String, title: String, author: String, year: Int, in_stock: Bool)
}

pub type SearchResult {
  /// `total` counts every match, `books` holds one page of them.
  SearchResult(total: Int, books: List(Book))
}

/// Sends `query_json` to `index` and reads the hits.
pub fn search_books(
  opensearch: Client,
  index: String,
  query_json: String,
) -> Result(SearchResult, String) {
  use body <- result.try(
    document.search(opensearch, index, query_json)
    |> result.map_error(client.describe_error),
  )
  search_result_from_response(body)
}

/// Reads the total and the books out of the body of a search response.
pub fn search_result_from_response(
  body: String,
) -> Result(SearchResult, String) {
  json.parse(body, search_result_decoder())
  |> result.replace_error("Unexpected search response: " <> body)
}

fn search_result_decoder() -> decode.Decoder(SearchResult) {
  use total <- decode.subfield(["hits", "total", "value"], decode.int)
  use books <- decode.subfield(["hits", "hits"], decode.list(book_hit()))
  decode.success(SearchResult(total:, books:))
}

fn book_hit() -> decode.Decoder(Book) {
  use id <- decode.field("_id", decode.string)
  use title <- decode.subfield(["_source", "title"], decode.string)
  use author <- decode.subfield(["_source", "author"], decode.string)
  use year <- decode.subfield(["_source", "year"], decode.int)
  use in_stock <- decode.subfield(["_source", "in_stock"], decode.bool)
  decode.success(Book(id:, title:, author:, year:, in_stock:))
}

/// Full-text search in the titles.
pub fn books_about(
  opensearch: Client,
  index: String,
  words: String,
) -> Result(SearchResult, String) {
  search_books(opensearch, index, query.match("title", words))
}

/// The books of one author, spelled exactly as stored.
pub fn books_by(
  opensearch: Client,
  index: String,
  author: String,
) -> Result(SearchResult, String) {
  search_books(opensearch, index, query.term("author", author))
}

/// The books published from `first_year` to `last_year`, both included.
pub fn books_published_between(
  opensearch: Client,
  index: String,
  first_year: Int,
  last_year: Int,
) -> Result(SearchResult, String) {
  let years =
    query.range("year", int.to_string(first_year), int.to_string(last_year))
  search_books(opensearch, index, years)
}
