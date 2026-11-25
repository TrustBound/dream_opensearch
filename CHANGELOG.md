# Changelog

All notable changes to `dream_opensearch` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - Unreleased

### Added

- `client.from_request(base)` makes a client from a dream_http_client `ClientRequest`. Every request of the client starts from that base request: its scheme, host, port, headers, timeouts, connection pool, certificate authority file and recorder. Each call sets the method, the body and the header `content-type: application/json`. It adds the API path after the path of the base request, and sets the query from the API path. A test can now give the client a recorder, and a program can set a timeout or trust another certificate authority.
- `client.base_request(client)` returns the base request of a client.
- `client.OpenSearchError`, a typed error with the variants `InvalidUrl(reason)`, `Unavailable(reason)`, `TimedOut(timeout_ms)`, `Rejected(status, body)`, `InvalidResponseBody(status)` and `NoRecording(method, url, details)`.
- `client.describe_error(error)` turns an error into one line of text. The text never holds the user name or the password of the base URL.
- The guide "Upgrading", with the code changes from 3.x to 4.0.0.

### Changed

- Every function returns `Result(String, OpenSearchError)`. Before, the error was a `String`: a message of the client, or the body of an OpenSearch answer. Each dream_http_client error maps to one variant, with no match on message text: `ResponseError` is `Rejected`, `TimedOut` is `TimedOut`, `NoRecording` is `NoRecording`, and every other transport error is `Unavailable`. A body that is not UTF-8 is `InvalidResponseBody`.
- `client.new(base_url)` returns `Result(Client, OpenSearchError)`. It checks the URL one time. It returns `Error(InvalidUrl(reason))` for these URLs: a URL that cannot be parsed, a scheme other than `http` or `https`, a URL with no host, a URL with a query or a fragment, and bad percent-encoding in the user name or password. Before, every request parsed the URL again, and a bad URL came back as an error of each request.
- `Client` is opaque, and it holds a base request, not the field `base_url`. The user name and password of the base URL are only in the `authorization` header of the base request.
- The guide "Handling errors" uses the typed error, and shows how to set the timeout.
- CI checks out the whole history, so the snippet check can read the code of the upgrade guide at the tag 3.0.0.

### Upgrading

- Handle the `Result` of `client.new`. In a function that returns `Result(_, OpenSearchError)`, write `use opensearch <- result.try(client.new(url))`.
- Where you show or log an error, use `client.describe_error(error)`. Where you read an OpenSearch answer from an error, match `Rejected(status:, body:)`.
- Where you read `opensearch.base_url`, read the base request with `client.base_request`.
- The guide "Upgrading" shows each change with the code before and after.

## [3.0.0] - 2026-11-25

### Fixed

- A user name and password in the base URL now authenticate. Before, `client.new("https://user:pass@host:9200")` sent no `authorization` header, so a secured OpenSearch answered 401. Now every request sends `authorization: Basic <base64(user:password)>`. The client percent-decodes the user name and password first (`p%40ss` becomes `p@ss`), and a URL with a user name and no password sends an empty password. The user name and password are not sent in the request line or the `host` header. A URL with no user name sends no `authorization` header, as before.
- `send_request` now parses the URL with `gleam/uri`. A query string in the path (`/users/_search?size=5`) is sent as before.
- The `document` functions now percent-encode each index name and document ID in the path: every byte outside `A-Z a-z 0-9 - . _ ~` goes out as `%XX` (UTF-8, upper-case hex). Before, they put the ID in the path as it was, which lost or changed data: `document.index(c, "users", "a#b", body)` sent `PUT /users/_doc/a` and returned `Ok`, `document.delete(c, "users", "a#b")` deleted document `a`, `a/b` and `a?b=1` changed the path, and an ID with a space returned `Error("Invalid OpenSearch URL: the URL cannot be parsed")`. Now each such ID is stored, found and deleted as itself. An index name that OpenSearch does not allow (upper case, `#`, a space) reaches OpenSearch and comes back as its `invalid_index_name_exception` error. `client.send_request` still sends the path that you give it, unchanged.

### Changed

- Moved to its own repository
- `send_request` returns an HTTP error answer (status 4xx or 5xx) as `Error(body)`. Before, in 2.0.0, it returned `Ok(body)`. The body is the answer of OpenSearch, which usually holds the error details. This change was in a 2.1.0 section of this changelog, but 2.1.0 was never published to Hex, so 3.0.0 is the first release with it.
- Needs dream_http_client 6.0.0 or later. A major version, because a project on dream_http_client 5 cannot use it.
- `send_request` returns `Error("The OpenSearch response body is not valid UTF-8")` for a response body that is not UTF-8, with any status. dream_http_client 6.0.0 gives the body as bytes, and this package returns text. Before, such a body came back as a `String` that was not valid text.
- `send_request` returns an error, and sends no request, when the URL cannot be parsed, has no host, or has invalid percent-encoding in the user name or password (for example `"Invalid OpenSearch URL: the URL has no host"`). Before, it tried to connect and returned a connection error. No error message contains the user name or password.
- The tests run against a real OpenSearch 2.19.1 in Docker (`make search-up`), locally and in CI.
- The examples in the doc comments take the index name as a parameter, and their tests run against the real cluster, each in its own index.
- Every code block of the guides is checked: each output block is a file in `test/outputs/` that a test compares with the real output, and each file and command block is a copy of `docker-compose.yml`, `gleam.toml` or a script in `scripts/`.
- The package has five guides in `docs/guides/`: getting started, searching an index, loading documents in bulk, managing indexes, and handling errors. Each one walks through a task from start to finish, with tested code, the failure cases, tests for your own code and common pitfalls. The README is short and links to them, and HexDocs shows the guides.

### Upgrading

- If you percent-encode index names or document IDs before you pass them to a `document` function, stop. The function now encodes them, so an encoded ID is encoded two times: `a%23b` goes out as `a%2523b`, and OpenSearch stores the ID `a%23b`.
- If your code reads an error from an `Ok` body (for example a status 404 or 400 answer), read it from `Error` now.
- No other code change is necessary. A base URL that already holds a user name and password starts to authenticate. Check that those credentials are correct, because a server that ignored them before now reads them.

## [2.0.0]

### Breaking Changes

- Bumped to match dream_http_client 4.x API changes.

## [1.0.2] - 2025-11-21

### Changed
- Added HexDocs documentation badge to README

## [1.0.1] - 2025-11-22

### Fixed
- Fixed logo display on hex.pm by using full GitHub URL
- Added Dream logo to README

## [1.0.0] - 2025-11-21

### Added
- Initial stable release
- `client.new()` - Create OpenSearch client
- `document.index()` - Index documents
- `document.search()` - Search documents
- `document.delete()` - Delete documents
- `document.create_index()` - Create index with mapping
- `document.delete_index()` - Delete index
- `document.bulk()` - Bulk index operations
- Query builder helpers:
  - `query.match_all()` - Match all documents
  - `query.match()` - Full-text search
  - `query.term()` - Exact term match
  - `query.range()` - Range queries

