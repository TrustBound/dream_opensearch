<div align="center">
  <img src="https://raw.githubusercontent.com/TrustBound/dream/main/ricky_and_lucy.png" alt="Ricky Moony and Lucy, a moon shaped mascot for Dream with the star shaped mascot for Gleam, each with cute cartoon eyes and a smile" width="200">

<b>Simple OpenSearch client for Gleam</b>

</div>

<br />

<div align="center">
  <a href="https://hex.pm/packages/dream_opensearch"><img src="https://img.shields.io/hexpm/v/dream_opensearch" alt="Hex Package"></a>
  <a href="https://github.com/TrustBound/dream_opensearch/releases"><img src="https://img.shields.io/github/v/release/TrustBound/dream_opensearch?label=Release" alt="Latest Release"></a>
  <a href="https://hexdocs.pm/dream_opensearch"><img src="https://img.shields.io/badge/hex-docs-lightgreen.svg" alt="HexDocs"></a>
  <a href="https://github.com/TrustBound/dream_opensearch/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/TrustBound/dream_opensearch/badges/coverage.json" alt="Coverage"></a>
  <a href="https://github.com/TrustBound/dream_opensearch/blob/main/LICENSE.md"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://gleam.run"><img src="https://img.shields.io/badge/gleam-%E2%9C%A8-ffaff3" alt="Gleam"></a>
</div>

<br />

# dream_opensearch

A standalone HTTP client for OpenSearch (or Elasticsearch) clusters. It indexes, searches and deletes documents, and manages indices. It is built with the same quality standards as [Dream](https://github.com/TrustBound/dream), but it is completely independent. Use it in any Gleam project.

## Features

- ✅ Document indexing and deletion
- ✅ Full-text search
- ✅ Index management
- ✅ Bulk operations
- ✅ Query builder helpers
- ✅ Zero dependencies on Dream or other frameworks

## Installation

```bash
gleam add dream_opensearch
```

## Quick Start

### Index, search and delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_quick_start.gleam#L5-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a> <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/docs/guides/getting-started.md#index-search-and-delete-a-document-"><img align="right" alt="Guide" src="https://img.shields.io/badge/%F0%9F%93%96_read-guide-blue.svg?style=flat-square"></a>

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

## Guides

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Client setup](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/client-setup.md): create a client, send credentials in the base URL, and read the errors
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request

## API Reference

The full API reference is on [HexDocs](https://hexdocs.pm/dream_opensearch). Each guide lists the functions it uses.

## Design Principles

dream_opensearch follows Dream's [design principles](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/reference/design-principles.md) and [contributing guide](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/contributing/contributing.md).

## About Dream

This module was originally built for the [Dream](https://github.com/TrustBound/dream) web toolkit, but it's completely standalone and can be used in any Gleam project. It follows Dream's design principles and will be maintained as part of the Dream ecosystem.

## License

MIT — see [LICENSE.md](https://github.com/TrustBound/dream_opensearch/blob/main/LICENSE.md)

---

<div align="center">
  <sub>Built in Gleam, on the BEAM, by the <a href="https://github.com/trustbound/dream">Dream Team</a> ❤️</sub>
</div>
