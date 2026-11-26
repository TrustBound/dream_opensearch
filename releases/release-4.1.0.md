# dream_opensearch 4.1.0 Release Notes

**Release Date:** 2026-11-26

This release adds `client.to_error`. It maps an `OpenSearchError` to `dream_errors.Error`, the error type that the Dream packages share. An app that uses several Dream packages can then handle their errors with one type.

It is a minor version: it only adds a function and a dependency.

## Key Highlights

- **`client.to_error`**: maps each `OpenSearchError` to `dream_errors.Error`, and keeps the `OpenSearchError` as the cause
- **New dependency**: `dream_errors`, a small package with the shared error type and no other dependency than `gleam_stdlib`

## What's New

### `client.to_error`

`client.to_error(error)` gives a `dream_errors.Error(OpenSearchError)`:

- `InvalidUrl` gives `Invalid`
- `Unavailable` gives `Unavailable`
- `TimedOut` gives `Timeout`
- `Rejected` with status 404 gives `NotFound`, and with status 409 gives `Conflict`
- Every other error gives `Failed`

The message is the text of `describe_error`, for developers and logs. `NotFound` has no cause, so its message holds the status and the body of the answer.

#### Read a document with the shared error <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_to_error.gleam#L5-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
  type Client, type OpenSearchError, send_request, to_error,
}
import gleam/http.{Get}
import gleam/result.{map_error}

pub fn get_document(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(String, Error(OpenSearchError)) {
  send_request(opensearch, Get, "/" <> index <> "/_doc/" <> id, "")
  |> map_error(to_error)
}
```

## Testing

- 281 tests, 0 failed, 100% line coverage (137/137 lines of `src/`), in 18.4 seconds over one run, with the coverage report on. Apple M1 Max, 10 cores, 64 GB, macOS 26.5.1, OTP 29, Gleam 1.19.2, OpenSearch 2.19.1 in Docker on the same machine.

## Upgrading

Allow version 4.1 in your `gleam.toml` (`dream_opensearch = ">= 4.1.0 and < 5.0.0"`), then run `gleam deps update dream_opensearch`.

### Migration Guide

No code changes. Every function of 4.0.0 works as before.

## Documentation

- [dream_opensearch](https://hexdocs.pm/dream_opensearch) - v4.1.0
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md#the-shared-error-type)
- [Changelog](https://github.com/TrustBound/dream_opensearch/blob/main/CHANGELOG.md)

## Community

- [Discussions](https://github.com/TrustBound/dream/discussions)
- [Report Issues](https://github.com/TrustBound/dream_opensearch/issues)
- [Contributing Guide](https://github.com/TrustBound/dream_opensearch/blob/main/CONTRIBUTING.md)
