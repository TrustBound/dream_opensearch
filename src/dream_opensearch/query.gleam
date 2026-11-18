//// OpenSearch query builder helpers
////
//// This module provides helper functions to build common OpenSearch query
//// types. These functions return JSON strings that can be passed to
//// `document.search()`.
////
//// ## Quick Start
////
//// ### Search with query builders <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_quick_start.gleam#L3-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
////
//// ```gleam
//// import dream_opensearch/client.{type Client}
//// import dream_opensearch/document
//// import dream_opensearch/query
////
//// // Full-text search
//// pub fn search_by_name(opensearch: Client) -> Result(String, String) {
////   let name_query = query.match("name", "Alice")
////   document.search(opensearch, "users", name_query)
//// }
////
//// // Exact term match
//// pub fn search_by_status(opensearch: Client) -> Result(String, String) {
////   let status_query = query.term("status", "active")
////   document.search(opensearch, "users", status_query)
//// }
//// ```
////
//// ## Custom Queries
////
//// For complex queries, build the JSON manually using `gleam/json`:
////
//// ### Build a custom query <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_custom.gleam#L3-L27"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
////
//// ```gleam
//// import gleam/json
////
//// pub fn build_bool_query() -> String {
////   json.object([
////     #(
////       "query",
////       json.object([
////         #(
////           "bool",
////           json.object([
////             #(
////               "must",
////               json.preprocessed_array([
////                 json.object([
////                   #("match", json.object([#("name", json.string("Alice"))])),
////                 ]),
////               ]),
////             ),
////           ]),
////         ),
////       ]),
////     ),
////   ])
////   |> json.to_string()
//// }
//// ```

import gleam/json

/// Build a match_all query
///
/// Creates a query that matches all documents in the index. Useful for
/// retrieving all documents or as a base for filtering.
///
/// ## Returns
///
/// A JSON query string that matches all documents.
///
/// ## See Also
///
/// - `document.search`: sends the query.
/// - `term`: matches one exact value.
///
/// ## Example
///
/// ### Search all documents <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_match_all.gleam#L3-L10"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// pub fn search_all_users(opensearch: Client) -> Result(String, String) {
///   let all_query = query.match_all()
///   document.search(opensearch, "users", all_query)
/// }
/// ```
pub fn match_all() -> String {
  json.object([#("query", json.object([#("match_all", json.object([]))]))])
  |> json.to_string()
}

/// Build a simple term query
///
/// Creates a query that matches documents where the specified field exactly
/// matches the given value. This is useful for exact matches on keyword fields.
///
/// ## Parameters
///
/// - `field`: The field name to match against
/// - `value`: The exact value to match
///
/// ## Returns
///
/// A JSON query string for the term query.
///
/// ## See Also
///
/// - `match`: full-text search.
/// - `range`: matches a range of values.
/// - `document.search`: sends the query.
///
/// ## Example
///
/// ### Search for an exact value <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_term.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// // Find all users with status "active"
/// pub fn search_active_users(opensearch: Client) -> Result(String, String) {
///   let status_query = query.term("status", "active")
///   document.search(opensearch, "users", status_query)
/// }
/// ```
pub fn term(field: String, value: String) -> String {
  json.object([
    #(
      "query",
      json.object([
        #("term", json.object([#(field, json.string(value))])),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Build a range query
///
/// Creates a query that matches documents where the specified field falls
/// within the given range (greater than or equal to `gte`, less than or
/// equal to `lte`).
///
/// ## Parameters
///
/// - `field`: The field name to filter on
/// - `gte`: The minimum value (greater than or equal)
/// - `lte`: The maximum value (less than or equal)
///
/// ## Returns
///
/// A JSON query string for the range query.
///
/// ## See Also
///
/// - `term`: matches one exact value.
/// - `document.search`: sends the query.
///
/// ## Example
///
/// ### Search a range <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_range.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// // Find products with price between 10 and 100
/// pub fn search_products_by_price(opensearch: Client) -> Result(String, String) {
///   let price_query = query.range("price", "10", "100")
///   document.search(opensearch, "products", price_query)
/// }
/// ```
pub fn range(field: String, gte: String, lte: String) -> String {
  json.object([
    #(
      "query",
      json.object([
        #(
          "range",
          json.object([
            #(
              field,
              json.object([
                #("gte", json.string(gte)),
                #("lte", json.string(lte)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Build a match query (full-text search)
///
/// Creates a full-text search query that matches documents where the specified
/// field contains the given text. This performs text analysis and is suitable
/// for searching text fields.
///
/// ## Parameters
///
/// - `field`: The field name to search in
/// - `text`: The text to search for
///
/// ## Returns
///
/// A JSON query string for the match query.
///
/// ## See Also
///
/// - `term`: matches one exact value, with no text analysis.
/// - `document.search`: sends the query.
///
/// ## Example
///
/// ### Search the text of a field <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_query_match.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// // Search for users with "Alice" in the name field
/// pub fn search_users_named_alice(opensearch: Client) -> Result(String, String) {
///   let name_query = query.match("name", "Alice")
///   document.search(opensearch, "users", name_query)
/// }
/// ```
pub fn match(field: String, text: String) -> String {
  json.object([
    #(
      "query",
      json.object([
        #("match", json.object([#(field, json.string(text))])),
      ]),
    ),
  ])
  |> json.to_string()
}
