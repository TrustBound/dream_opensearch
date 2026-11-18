//// OpenSearch document operations
////
//// This module provides high-level functions for common OpenSearch operations:
//// indexing documents, searching, deleting, and managing indices.
////
//// ## Quick Start
////
//// ### Create a client and index a document <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_quick_start.gleam#L3-L18"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
////
//// ```gleam
//// import dream_opensearch/client.{type Client}
//// import dream_opensearch/document
//// import gleam/json
////
//// pub fn create_client() -> Client {
////   client.new("http://localhost:9200")
//// }
////
//// pub fn index_alice(opensearch: Client) -> Result(String, String) {
////   let user =
////     json.object([
////       #("name", json.string("Alice")),
////       #("email", json.string("alice@example.com")),
////     ])
////   document.index(opensearch, "users", "123", json.to_string(user))
//// }
//// ```
////
//// ## JSON Format
////
//// All document operations expect JSON strings. Use `gleam/json` to build
//// JSON objects and convert them to strings with `json.to_string()`.

import dream_opensearch/client.{type Client}
import gleam/http

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
/// - `Error(String)`: An error message if the operation failed
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more (for example `mapper_parsing_exception`), or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `search`: finds the indexed documents.
/// - `bulk`: indexes many documents in one request.
/// - `delete`: deletes the document.
///
/// ## Example
///
/// ### Index a document <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_index.gleam#L3-L18"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import gleam/json
///
/// pub fn index_alice(opensearch: Client) -> String {
///   let user =
///     json.object([
///       #("name", json.string("Alice")),
///       #("email", json.string("alice@example.com")),
///     ])
///
///   case document.index(opensearch, "users", "123", json.to_string(user)) {
///     Ok(_response) -> "Indexed successfully"
///     Error(message) -> "Error: " <> message
///   }
/// }
/// ```
pub fn index(
  client: Client,
  index_name: String,
  document_id: String,
  document_json: String,
) -> Result(String, String) {
  let path = "/" <> index_name <> "/_doc/" <> document_id
  client.send_request(client, http.Put, path, document_json)
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
/// - `Error(String)`: An error message if the search failed
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more (for example `index_not_found_exception`), or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `dream_opensearch/query`: builds the query JSON.
/// - `index`: adds documents to search.
///
/// ## Example
///
/// ### Search an index <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_search.gleam#L3-L10"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import dream_opensearch/query
///
/// pub fn search_for_alice(opensearch: Client) -> Result(String, String) {
///   let name_query = query.match("name", "Alice")
///   document.search(opensearch, "users", name_query)
/// }
/// ```
pub fn search(
  client: Client,
  index_name: String,
  query_json: String,
) -> Result(String, String) {
  let path = "/" <> index_name <> "/_search"
  client.send_request(client, http.Post, path, query_json)
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
/// - `Error(String)`: An error message if the deletion failed
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more (for example status 404 when the document does not exist), or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `index`: adds or replaces a document.
/// - `delete_index`: deletes the whole index.
///
/// ## Example
///
/// ### Delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_delete.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
///
/// pub fn delete_user(opensearch: Client) -> String {
///   case document.delete(opensearch, "users", "123") {
///     Ok(_response) -> "Document deleted"
///     Error(message) -> "Error: " <> message
///   }
/// }
/// ```
pub fn delete(
  client: Client,
  index_name: String,
  document_id: String,
) -> Result(String, String) {
  let path = "/" <> index_name <> "/_doc/" <> document_id
  client.send_request(client, http.Delete, path, "")
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
/// - `Error(String)`: An error message if creation failed (e.g., index already exists)
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more (for example `resource_already_exists_exception`), or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `delete_index`: deletes the index.
/// - `index`: adds documents to the index.
///
/// ## Example
///
/// ### Create an index with a mapping <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_create_index.gleam#L3-L24"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
/// import gleam/json
///
/// pub fn create_users_index(opensearch: Client) -> Result(String, String) {
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
///   document.create_index(opensearch, "users", json.to_string(mapping))
/// }
/// ```
pub fn create_index(
  client: Client,
  index_name: String,
  mapping_json: String,
) -> Result(String, String) {
  let path = "/" <> index_name
  client.send_request(client, http.Put, path, mapping_json)
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
/// - `Error(String)`: An error message if deletion failed (e.g., index doesn't exist)
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more (for example `index_not_found_exception`), or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `create_index`: creates an index.
/// - `delete`: deletes one document.
///
/// ## Example
///
/// ### Delete an index <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_delete_index.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
///
/// pub fn delete_old_index(opensearch: Client) -> String {
///   case document.delete_index(opensearch, "old_index") {
///     Ok(_response) -> "Index deleted"
///     Error(message) -> "Error: " <> message
///   }
/// }
/// ```
pub fn delete_index(
  client: Client,
  index_name: String,
) -> Result(String, String) {
  let path = "/" <> index_name
  client.send_request(client, http.Delete, path, "")
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
/// - `Error(String)`: An error message if the bulk operation failed
///
/// ## Errors
///
/// The errors of `client.send_request`: the response body when OpenSearch
/// answers with status 400 or more, or a message when the connection
/// fails or the base URL cannot be used.
///
/// ## See Also
///
/// - `index`: indexes one document.
///
/// ## Example
///
/// ### Index two documents in one request <a href="https://github.com/TrustBound/dream_opensearch/blob/2.0.0/test/snippets/doc_document_bulk.gleam#L3-L15"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import dream_opensearch/document
///
/// pub fn bulk_index_users(opensearch: Client) -> Result(String, String) {
///   // NDJSON format: action and document on alternating lines
///   let ndjson =
///     "{ \"index\": { \"_index\": \"users\", \"_id\": \"1\" } }\n"
///     <> "{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n"
///     <> "{ \"index\": { \"_index\": \"users\", \"_id\": \"2\" } }\n"
///     <> "{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n"
///
///   document.bulk(opensearch, ndjson)
/// }
/// ```
pub fn bulk(client: Client, ndjson: String) -> Result(String, String) {
  let path = "/_bulk"
  client.send_request(client, http.Post, path, ndjson)
}
