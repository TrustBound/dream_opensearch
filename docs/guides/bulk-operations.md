# Bulk operations

This guide shows how to index many documents in one request with the OpenSearch bulk API. The request body is NDJSON (newline-delimited JSON), where each line is a JSON object.

## Index many documents in one request

In the NDJSON body, an action line and a document line alternate. The action line names the index and the document ID. The next line is the document.

### Bulk Operations <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_bulk_operations.gleam#L5-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn bulk_index_users(opensearch: Client) -> Result(String, String) {
  // NDJSON format: action and document on alternating lines
  let ndjson =
    "{ \"index\": { \"_index\": \"users\", \"_id\": \"1\" } }\n"
    <> "{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n"
    <> "{ \"index\": { \"_index\": \"users\", \"_id\": \"2\" } }\n"
    <> "{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n"

  document.bulk(opensearch, ndjson)
}
```

## Functions

- `document.bulk(client, ndjson)`: bulk index documents. It returns `Ok` with the OpenSearch response as a JSON string, or `Error` with a message.

## See also

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials, and read the errors
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
