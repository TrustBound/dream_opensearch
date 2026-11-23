# Indexing documents

This guide shows how to add a document to an index and how to delete it. A document is a JSON string, which you can build with `gleam/json`.

## Index a document

`document.index` creates or updates a document in an index. If a document with the same ID already exists, OpenSearch replaces it.

### Indexing Documents <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_indexing_documents.gleam#L5-L21"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

pub fn index_user(opensearch: Client) -> String {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
      #("age", json.int(30)),
    ])

  case document.index(opensearch, "users", "123", json.to_string(user)) {
    Ok(_response) -> "Indexed successfully"
    Error(message) -> "Error: " <> message
  }
}
```

## Delete a document

`document.delete` removes a document from an index by its ID. For example, `document.delete(opensearch, "users", "123")` deletes the document that the example above indexed. When the document does not exist, OpenSearch answers with status 404, and the function returns the response body as an `Error`.

## Functions

- `document.index(client, index, id, json)`: index a document.
- `document.delete(client, index, id)`: delete a document.

Each function returns `Ok` with the OpenSearch response as a JSON string, or `Error` with a message. The [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md) guide lists the errors.

## See also

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials, and read the errors
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
