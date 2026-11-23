# dream_opensearch 3.0.0 Release Notes

**Release Date:** not released yet (draft)

This release makes a user name and password in the base URL authenticate, and moves `dream_opensearch` to `dream_http_client` 6.0.0. Before, `client.new("https://user:pass@host:9200")` sent no `authorization` header, so a secured OpenSearch answered 401.

It is a major version because a project on `dream_http_client` 5 cannot use it. Your code needs no change. Read "Upgrading" before you upgrade. The package also moved to its own repository.

## Key Highlights

- **Credentials in the base URL work**: every request sends `authorization: Basic <base64(user:password)>`
- **Needs `dream_http_client` 6.0.0**: the client that shares HTTP/2 connections and gives the response body as bytes
- **A bad URL is an error before any request**: no host, a URL that cannot be parsed, or bad percent-encoding
- **Its own repository**: `dream_opensearch` now lives at [TrustBound/dream_opensearch](https://github.com/TrustBound/dream_opensearch), with its own version and its own releases

## What's New

### Needs `dream_http_client` 6.0.0

`dream_opensearch` now uses `dream_http_client` 6.0.0 or later. A project that also lists `dream_http_client` must allow version 6.

### A Response Body That Is Not UTF-8

`send_request` returns `Error("The OpenSearch response body is not valid UTF-8")` for a response body that is not UTF-8, with any status. `dream_http_client` 6.0.0 gives the body as bytes, and this package returns text. Before, such a body came back as a `String` that was not valid text. OpenSearch answers with JSON, which is UTF-8.

### A Bad URL Is an Error Before Any Request

`send_request` returns an error, and sends no request, when the URL cannot be parsed, has no host, or has invalid percent-encoding in the user name or password. An example is `"Invalid OpenSearch URL: the URL has no host"`. Before, it tried to connect and returned a connection error. No error message contains the user name or password.

### Its Own Repository

`dream_opensearch` moved out of the Dream repository. It has its own version, its own changelog and its own release workflow. The package name on Hex and the module names are the same as before.

### Guides

The package has five guides in [`docs/guides/`](https://github.com/TrustBound/dream_opensearch/tree/main/docs/guides): getting started, searching an index, loading documents in bulk, managing indexes, and handling errors. Each one walks through a task from start to finish, with tested code, the failure cases, tests for your own code and common pitfalls. The README is short and links to them, and HexDocs shows the guides.

## Bug Fixes

### A User Name and Password in the Base URL Authenticate

Before, `client.new("https://user:pass@host:9200")` sent no `authorization` header. Now every request sends `authorization: Basic <base64(user:password)>`.

- The client percent-decodes the user name and password first: `p%40ss` becomes `p@ss`
- A URL with a user name and no password sends an empty password
- The user name and password are not sent in the request line or in the `host` header
- A URL with no user name sends no `authorization` header, as before

#### Create a client with and without credentials <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/doc_client_new.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}

pub fn create_local_client() -> Client {
  client.new("http://localhost:9200")
}

pub fn create_client_with_credentials() -> Client {
  client.new("https://user:pass@search.example.com:9200")
}
```

### Index Names and Document IDs Are Percent-Encoded

Before, the `document` functions put the index name and the document ID in the URL path as they were. Some IDs lost or changed data:

- `document.index(c, "users", "a#b", body)` sent `PUT /users/_doc/a` and returned `Ok`
- `document.delete(c, "users", "a#b")` deleted document `a`
- `a/b` went out as `/users/_doc/a/b`, and `a?b=1` as `/users/_doc/a?b=1`
- `my id` returned `Error("Invalid OpenSearch URL: the URL cannot be parsed")`

Now every `document` function percent-encodes each index name and document ID as one path segment. Every byte outside `A-Z a-z 0-9 - . _ ~` goes out as `%XX` (UTF-8, upper-case hex), so `a#b` goes out as `a%23b`. Against OpenSearch 2.19.1, a document with the ID `a#b`, `a/b`, `a?b=1`, `my id` or `café ☕` is stored, found by a search for exactly that `_id`, and deleted, and the document `a` stays. An index name that OpenSearch does not allow (upper case, `#`, a space) reaches OpenSearch and comes back as its `invalid_index_name_exception` error. `client.send_request` still sends the path that you give it, unchanged.

### The URL Is Parsed With `gleam/uri`

`send_request` now parses the URL with `gleam/uri`. A query string in the path (`/users/_search?size=5`) is sent as before.

## Testing

- 247 tests run, 0 failed, 100.0% line coverage, in about 7 seconds (Apple M1 Max, OTP 29, Gleam 1.19.2, OpenSearch 2.19.1 in Docker on the same machine)
- The tests run against a real OpenSearch 2.19.1 in Docker (`docker-compose.yml`, `make search-up`), locally and in CI

## Upgrading

Update your dependencies:

```toml
[dependencies]
dream_opensearch = ">= 3.0.0 and < 4.0.0"
```

Then run:

```bash
gleam deps update dream_opensearch
```

### Migration Guide

Most code needs no change. Three things can change what your app does.

#### 1. Your base URL already holds a user name and password

That URL starts to authenticate. Make sure that those credentials are correct, because a server that ignored them before now reads them.

#### 2. Your project lists `dream_http_client` itself

Allow version 6 in your own `gleam.toml`, and read the `dream_http_client` 6.0.0 release notes. Its response body is now bytes.

#### 3. You percent-encode index names or document IDs yourself

Stop, and pass them as they are. The `document` functions now encode them, so an encoded ID is encoded two times: `uri.percent_encode("a#b")` gives `a%23b`, which goes out as `a%2523b`, and OpenSearch stores the ID `a%23b`.

## Documentation

- [dream_opensearch](https://hexdocs.pm/dream_opensearch) - v3.0.0
- [dream_http_client](https://hexdocs.pm/dream_http_client) - v6.0.0
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md)
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md)
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md)
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md)
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md)
- [Changelog](https://github.com/TrustBound/dream_opensearch/blob/main/CHANGELOG.md)

## Community

- [Discussions](https://github.com/TrustBound/dream/discussions)
- [Report Issues](https://github.com/TrustBound/dream_opensearch/issues)
- [Contributing Guide](https://github.com/TrustBound/dream_opensearch/blob/main/CONTRIBUTING.md)
