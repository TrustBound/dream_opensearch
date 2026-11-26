//// OpenSearch document operations
////
//// This module provides high-level functions for common OpenSearch operations:
//// indexing documents, searching, deleting, and managing indices.
////
//// ## Quick Start
////
//// ### Create a client and index a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_quick_start.gleam#L3-L21"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
////
//// ```gleam
//// import dream_opensearch/client.{type Client, type OpenSearchError}
//// import dream_opensearch/document
//// import gleam/json
////
//// pub fn create_client() -> Result(Client, OpenSearchError) {
////   client.new("http://localhost:9200")
//// }
////
//// pub fn index_alice(
////   opensearch: Client,
////   index: String,
//// ) -> Result(String, OpenSearchError) {
////   let user =
////     json.object([
////       #("name", json.string("Alice")),
////       #("email", json.string("alice@example.com")),
////     ])
////   document.index(opensearch, index, "123", json.to_string(user))
//// }
//// ```
////
//// ## Index names and document IDs
////
//// Each function puts the index name and the document ID in the URL path as
//// one path segment each, and percent-encodes them: every byte outside
//// `A-Z a-z 0-9 - . _ ~` goes out as `%XX` (UTF-8, upper-case hex). So an
//// ID such as `a#b`, `a/b`, `a?b=1` or `my id` reaches OpenSearch whole.
//// Pass names and IDs as they are, not encoded: an encoded value is encoded
//// again. OpenSearch still checks each index name, and answers a name it
//// does not allow (upper case, `#`, a space) with an
//// `invalid_index_name_exception` error.
////
//// ## JSON Format
////
//// All document operations expect JSON strings. Use `gleam/json` to build
//// JSON objects and convert them to strings with `json.to_string()`.

import dream_opensearch/client.{type Client, type OpenSearchError}
import gleam/bit_array.{from_string}
import gleam/http.{type Method, Delete, Post, Put}
import gleam/int.{to_base16}
import gleam/list.{map}
import gleam/string.{
  concat, from_utf_codepoints, pad_start, to_utf_codepoints,
  utf_codepoint_to_int,
}

/// Index a document in OpenSearch
///
/// Creates or updates a document in the specified index. If a document with
/// the same ID already exists, it will be replaced.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `index_name`: The name of the index (e.g., "users", "products")
/// - `document_id`: The unique document ID
/// - `document_json`: The document as a JSON string
///
/// ## Returns
///
/// - `Ok(String)`: The OpenSearch response as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more (for example `mapper_parsing_exception`),
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `search`: finds the indexed documents.
/// - `bulk`: indexes many documents in one request.
/// - `delete`: deletes the document.
///
/// ## Example
///
/// ### Index a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_index.gleam#L3-L18"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import gleam/json
///
/// pub fn index_alice(opensearch: Client, index: String) -> String {
///   let user =
///     json.object([
///       #("name", json.string("Alice")),
///       #("email", json.string("alice@example.com")),
///     ])
///
///   case document.index(opensearch, index, "123", json.to_string(user)) {
///     Ok(_response) -> "Indexed successfully"
///     Error(error) -> "Error: " <> client.describe_error(error)
///   }
/// }
/// ```
pub fn index(
  client: Client,
  index_name: String,
  document_id: String,
  document_json: String,
) -> Result(String, OpenSearchError) {
  send(client, Put, [index_name, "_doc", document_id], document_json)
}

/// Search documents in an index
///
/// Performs a search query against the specified index. The query should be
/// a valid OpenSearch query JSON string. Use `dream_opensearch/query` helpers
/// to build queries, or construct the JSON manually.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `index_name`: The name of the index to search
/// - `query_json`: The search query as a JSON string
///
/// ## Returns
///
/// - `Ok(String)`: The search results as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more (for example `index_not_found_exception`),
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `dream_opensearch/query`: builds the query JSON.
/// - `index`: adds documents to search.
///
/// ## Example
///
/// ### Search an index <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_search.gleam#L3-L13"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client, type OpenSearchError}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// pub fn search_for_alice(
///   opensearch: Client,
///   index: String,
/// ) -> Result(String, OpenSearchError) {
///   let name_query = query.match("name", "Alice")
///   document.search(opensearch, index, name_query)
/// }
/// ```
pub fn search(
  client: Client,
  index_name: String,
  query_json: String,
) -> Result(String, OpenSearchError) {
  send(client, Post, [index_name, "_search"], query_json)
}

/// Delete a document from an index
///
/// Removes a document from the specified index by its ID.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `index_name`: The name of the index
/// - `document_id`: The ID of the document to delete
///
/// ## Returns
///
/// - `Ok(String)`: The OpenSearch response as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more (for example status 404 when the document does not exist),
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `index`: adds or replaces a document.
/// - `delete_index`: deletes the whole index.
///
/// ## Example
///
/// ### Delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_delete.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
///
/// pub fn delete_user(opensearch: Client, index: String) -> String {
///   case document.delete(opensearch, index, "123") {
///     Ok(_response) -> "Document deleted"
///     Error(error) -> "Error: " <> client.describe_error(error)
///   }
/// }
/// ```
pub fn delete(
  client: Client,
  index_name: String,
  document_id: String,
) -> Result(String, OpenSearchError) {
  send(client, Delete, [index_name, "_doc", document_id], "")
}

/// Create an index with mapping
///
/// Creates a new index with the specified mapping (schema). The mapping
/// defines the fields and their types for documents in the index.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `index_name`: The name of the index to create
/// - `mapping_json`: The index mapping as a JSON string
///
/// ## Returns
///
/// - `Ok(String)`: The OpenSearch response as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more (for example `resource_already_exists_exception`),
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `delete_index`: deletes the index.
/// - `index`: adds documents to the index.
///
/// ## Example
///
/// ### Create an index with a mapping <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_create_index.gleam#L3-L27"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client, type OpenSearchError}
/// import dream_opensearch/document
/// import gleam/json
///
/// pub fn create_users_index(
///   opensearch: Client,
///   index: String,
/// ) -> Result(String, OpenSearchError) {
///   let mapping =
///     json.object([
///       #(
///         "mappings",
///         json.object([
///           #(
///             "properties",
///             json.object([
///               #("name", json.object([#("type", json.string("text"))])),
///               #("email", json.object([#("type", json.string("keyword"))])),
///             ]),
///           ),
///         ]),
///       ),
///     ])
///   document.create_index(opensearch, index, json.to_string(mapping))
/// }
/// ```
pub fn create_index(
  client: Client,
  index_name: String,
  mapping_json: String,
) -> Result(String, OpenSearchError) {
  send(client, Put, [index_name], mapping_json)
}

/// Delete an index
///
/// Permanently deletes an index and all its documents. This operation cannot
/// be undone.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `index_name`: The name of the index to delete
///
/// ## Returns
///
/// - `Ok(String)`: The OpenSearch response as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more (for example `index_not_found_exception`),
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `create_index`: creates an index.
/// - `delete`: deletes one document.
///
/// ## Example
///
/// ### Delete an index <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_delete_index.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
///
/// pub fn delete_old_index(opensearch: Client, index: String) -> String {
///   case document.delete_index(opensearch, index) {
///     Ok(_response) -> "Index deleted"
///     Error(error) -> "Error: " <> client.describe_error(error)
///   }
/// }
/// ```
pub fn delete_index(
  client: Client,
  index_name: String,
) -> Result(String, OpenSearchError) {
  send(client, Delete, [index_name], "")
}

/// Bulk index documents
///
/// Indexes multiple documents in a single request using OpenSearch's bulk API.
/// The body must be in NDJSON (newline-delimited JSON) format, where each line
/// is a JSON object.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `ndjson`: The bulk request body in NDJSON format
///
/// ## Returns
///
/// - `Ok(String)`: The OpenSearch response as JSON string
/// - `Error(OpenSearchError)`: see Errors.
///
/// ## Errors
///
/// The errors of `client.send_request`: `Rejected(status, body)` when
/// OpenSearch answers with status 400 or more,
/// `Unavailable` or `TimedOut` when no answer comes.
///
/// ## See Also
///
/// - `index`: indexes one document.
///
/// ## Example
///
/// ### Index two documents in one request <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_bulk.gleam#L3-L22"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client, type OpenSearchError}
/// import dream_opensearch/document
///
/// pub fn bulk_index_users(
///   opensearch: Client,
///   index: String,
/// ) -> Result(String, OpenSearchError) {
///   // NDJSON format: action and document on alternating lines
///   let ndjson =
///     "{ \"index\": { \"_index\": \""
///     <> index
///     <> "\", \"_id\": \"1\" } }\n"
///     <> "{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n"
///     <> "{ \"index\": { \"_index\": \""
///     <> index
///     <> "\", \"_id\": \"2\" } }\n"
///     <> "{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n"
///
///   document.bulk(opensearch, ndjson)
/// }
/// ```
pub fn bulk(client: Client, ndjson: String) -> Result(String, OpenSearchError) {
  send(client, Post, ["_bulk"], ndjson)
}

/// Sends a request to the path made of `segments`. Every function of this
/// module sends its request here, so every index name and document ID in a
/// path is percent-encoded.
fn send(
  client: Client,
  method: Method,
  segments: List(String),
  body: String,
) -> Result(String, OpenSearchError) {
  let path =
    segments
    |> map(fn(segment) { "/" <> encode_segment(segment) })
    |> concat
  client.send_request(client, method, path, body)
}

/// Percent-encodes one path segment: each byte of the UTF-8 form of
/// `segment` that is not in the RFC 3986 unreserved set
/// (`A-Z a-z 0-9 - . _ ~`) becomes `%` and two upper-case hex digits. So
/// `/`, `#`, `?`, `%` and spaces in a name or an ID stay part of it.
fn encode_segment(segment: String) -> String {
  segment
  |> to_utf_codepoints
  |> map(encode_codepoint)
  |> concat
}

fn encode_codepoint(codepoint: UtfCodepoint) -> String {
  let character = from_utf_codepoints([codepoint])
  case is_unreserved(utf_codepoint_to_int(codepoint)) {
    True -> character
    False -> encode_bytes(from_string(character), "")
  }
}

fn encode_bytes(bytes: BitArray, encoded: String) -> String {
  case bytes {
    <<byte, rest:bytes>> ->
      encode_bytes(
        rest,
        encoded <> "%" <> pad_start(to_base16(byte), to: 2, with: "0"),
      )
    _ -> encoded
  }
}

fn is_unreserved(byte: Int) -> Bool {
  { byte >= 0x41 && byte <= 0x5A }
  || { byte >= 0x61 && byte <= 0x7A }
  || { byte >= 0x30 && byte <= 0x39 }
  || byte == 0x2D
  || byte == 0x2E
  || byte == 0x5F
  || byte == 0x7E
}
