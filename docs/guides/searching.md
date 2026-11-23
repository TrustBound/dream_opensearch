# Searching

This guide shows how to search an index. Use the query builders in `dream_opensearch/query` for common queries, or build the query JSON yourself for complex queries.

## Search with the query builders

`document.search` sends a query to an index. Each query builder returns a JSON query string that you give to `document.search`:

### Search with each query builder <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_searching.gleam#L5-L31"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

// Full-text search
pub fn search_by_name(opensearch: Client) -> Result(String, String) {
  let name_query = query.match("name", "Alice")
  document.search(opensearch, "users", name_query)
}

// Exact term match
pub fn search_by_status(opensearch: Client) -> Result(String, String) {
  let status_query = query.term("status", "active")
  document.search(opensearch, "users", status_query)
}

// Range query
pub fn search_by_age(opensearch: Client) -> Result(String, String) {
  let age_query = query.range("age", "18", "65")
  document.search(opensearch, "users", age_query)
}

// Match all
pub fn search_all(opensearch: Client) -> Result(String, String) {
  let all_query = query.match_all()
  document.search(opensearch, "users", all_query)
}
```

`query.match` does text analysis and is for text fields. `query.term` matches one exact value, with no text analysis. `query.range` matches values that are greater than or equal to `gte` and less than or equal to `lte`.

## Custom queries

For complex queries, build JSON manually:

### Search with a bool query <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_custom_queries.gleam#L5-L43"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

pub fn search_active_users_named_alice(
  opensearch: Client,
) -> Result(String, String) {
  let bool_query =
    json.object([
      #(
        "query",
        json.object([
          #(
            "bool",
            json.object([
              #(
                "must",
                json.preprocessed_array([
                  json.object([
                    #("match", json.object([#("name", json.string("Alice"))])),
                  ]),
                ]),
              ),
              #(
                "filter",
                json.preprocessed_array([
                  json.object([
                    #("term", json.object([#("status", json.string("active"))])),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ])

  document.search(opensearch, "users", json.to_string(bool_query))
}
```

## Functions

- `document.search(client, index, query_json)`: search documents. It returns `Ok` with the search results as a JSON string, or `Error` with a message.
- `query.match_all()`: match all documents.
- `query.match(field, text)`: full-text search.
- `query.term(field, value)`: exact term match.
- `query.range(field, gte, lte)`: range query.

## See also

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials, and read the errors
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
