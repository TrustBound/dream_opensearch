# Index management

This guide shows how to create an index with a mapping and how to delete an index. The mapping defines the fields and their types for the documents in the index.

## Create and delete an index

`document.create_index` creates a new index with the mapping that you give it. It returns an `Error` when the index already exists (`resource_already_exists_exception`). `document.delete_index` deletes the whole index.

### Index Management <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_index_management.gleam#L5-L32"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

// Create index with mapping
pub fn create_users_index(opensearch: Client) -> Result(String, String) {
  let mapping =
    json.object([
      #(
        "mappings",
        json.object([
          #(
            "properties",
            json.object([
              #("name", json.object([#("type", json.string("text"))])),
              #("email", json.object([#("type", json.string("keyword"))])),
            ]),
          ),
        ]),
      ),
    ])
  document.create_index(opensearch, "users", json.to_string(mapping))
}

// Delete index
pub fn delete_old_index(opensearch: Client) -> Result(String, String) {
  document.delete_index(opensearch, "old_index")
}
```

## Functions

- `document.create_index(client, index, mapping_json)`: create an index.
- `document.delete_index(client, index)`: delete an index.

## See also

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials, and read the errors
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
