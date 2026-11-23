# Getting started

This guide shows how to add dream_opensearch to a Gleam project. It then creates a client and indexes, searches and deletes one document.

## Install

Add the package as a dependency:

```bash
gleam add dream_opensearch
```

dream_opensearch has no dependency on Dream or other frameworks. You can use it in any Gleam project. It works with OpenSearch and with Elasticsearch clusters.

## A first document

The example creates a client for a local cluster. It then indexes a user document, searches for it with a match query, and deletes it. Each document operation returns `Ok` with the OpenSearch response as a JSON string, or `Error` with a message.

### Index, search and delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_quick_start.gleam#L5-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import gleam/json

// Create client
pub fn create_client() -> Client {
  client.new("http://localhost:9200")
}

// Index a document
pub fn index_alice(opensearch: Client) -> Result(String, String) {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
    ])
  document.index(opensearch, "users", "123", json.to_string(user))
}

// Search documents
pub fn search_for_alice(opensearch: Client) -> Result(String, String) {
  let search_query = query.match("name", "Alice")
  document.search(opensearch, "users", search_query)
}

// Delete document
pub fn delete_alice(opensearch: Client) -> Result(String, String) {
  document.delete(opensearch, "users", "123")
}
```

All document operations expect JSON strings. Use `gleam/json` to build JSON objects and convert them to strings with `json.to_string()`.

## See also

- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials, and read the errors
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
