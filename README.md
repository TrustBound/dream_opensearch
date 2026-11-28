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

## What is Dream OpenSearch?

Dream OpenSearch is an HTTP client for OpenSearch, and for Elasticsearch clusters with the same document and search APIs. It indexes, searches and deletes documents, loads them in bulk and manages indexes, with a function for each job. Every failure comes back as a typed error, so you match on `Rejected`, `Unavailable` or `TimedOut` and decide what to retry. It has no dependency on the rest of Dream.

## Features

### Documents

Save, search for and delete documents with one function each. [Read more](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md).

| Feature                 | What you get                                                                  |
| ----------------------- | ----------------------------------------------------------------------------- |
| 📝 **Index and delete** | `document.index` and `document.delete` take the index, the id and a JSON body |
| 🔎 **Full-text search** | `document.search` runs a query and returns the response body for you to read  |
| 🧱 **Query builders**   | `match`, `term`, `range` and `match_all` build the query body                 |

### Searching

Queries, pages and sorting, and reading the hits into your own types. [Read more](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md).

| Feature                      | What you get                                                              |
| ---------------------------- | ------------------------------------------------------------------------- |
| 🧭 **Match, term and range** | The right query for text, exact values and ranges                         |
| 🧩 **Bool queries**          | Combine conditions, page and sort with a body you build with `gleam/json` |

### Indexes and bulk loading

Create indexes with a mapping and load many documents in one request. [Read more](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md).

| Feature                 | What you get                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| 🗂️ **Index management** | Create an index with settings and a mapping, and delete it                                    |
| 📦 **Bulk loading**     | `document.bulk` loads many documents in one request, and the guide finds the ones that failed |

### Typed errors

Every failure is a value you match on. [Read more](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md).

| Feature                          | What you get                                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 🚦 **Typed errors**              | `Rejected`, `Unavailable`, `TimedOut`, `InvalidUrl` and more                                             |
| 🔐 **Logs without the password** | The user name and password of the URL stay out of what you log                                           |
| ⏱️ **Your own client settings**   | Build the client from a `dream_http_client` request for a timeout, a recorder or a certificate authority |

## A Quick Example

### Index, search and delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/readme_quick_start.gleam#L5-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a> <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/docs/guides/getting-started.md#index-search-and-delete-a-document-"><img align="right" alt="Guide: Getting started" title="Guide: Getting started" src="https://img.shields.io/badge/%F0%9F%93%96_read-guide-blue.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import dream_opensearch/query
import gleam/json

// Create client
pub fn create_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

// Index a document
pub fn index_alice(opensearch: Client) -> Result(String, OpenSearchError) {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
    ])
  document.index(opensearch, "users", "123", json.to_string(user))
}

// Search documents
pub fn search_for_alice(opensearch: Client) -> Result(String, OpenSearchError) {
  let search_query = query.match("name", "Alice")
  document.search(opensearch, "users", search_query)
}

// Delete document
pub fn delete_alice(opensearch: Client) -> Result(String, OpenSearchError) {
  document.delete(opensearch, "users", "123")
}
```

**Run this:** `index_alice(opensearch)` → `Ok(body)`, the response of the cluster; `search_for_alice(opensearch)` then finds the document, and `delete_alice(opensearch)` removes it.

## Installation

```sh
gleam add dream_opensearch gleam_json
```

## Guides

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): connect to a local or a secured cluster, then save, search for and delete documents from a Gleam module, with tests
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): match, term, range and bool queries, pages and sorting, and reading the hits into your own types
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): load many documents in one request, find the ones that failed, load in batches and retry
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): create an index with settings and a mapping, check, refresh, count, copy and delete indexes
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md): every error the client returns, the details of an OpenSearch error, what to retry, logs without the password, and the timeout
- [Upgrading](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/upgrading.md): the code changes from 3.x to 4.0.0, before and after
- [API reference](https://hexdocs.pm/dream_opensearch): every module and function on HexDocs

## Requirements

- Gleam 1.19.2 or newer on Erlang/OTP 28 (the versions CI uses). Dream OpenSearch runs on Erlang.
- An OpenSearch cluster. The tests run against OpenSearch 2.19.1.

## About Dream

[Dream](https://github.com/TrustBound/dream) is a collection of Gleam packages for building production web applications. Each package implements its standards completely, shares the same naming and style as the others, and is fully tested. TrustBound builds Dream for its own production systems and shares it in the hope that it helps yours.

Dream OpenSearch works on its own. You don't need the rest of Dream to use it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE.md](https://github.com/TrustBound/dream_opensearch/blob/main/LICENSE.md)
