# dream_opensearch 4.0.0 Release Notes

**Release Date:** 2026-11-25

This release lets a client start from a `dream_http_client` request, and gives every function a typed error. Before, a test could not give the client a recorder, and every error was text, so an app had to match on the start of a message to tell "the service is down" from "OpenSearch said 400".

It is a major version because the error type and `client.new` change. Read the guide [Upgrading](https://hexdocs.pm/dream_opensearch/4.0.0/guides/upgrading.html) before you upgrade.

## Key Highlights

- **A client from a base request**: `client.from_request(base)` uses the scheme, host, port, headers, timeouts and recorder of a `dream_http_client` request, so tests can record and play back OpenSearch traffic
- **Typed errors**: `Unavailable`, `TimedOut`, `Rejected(status, body)`, `InvalidUrl`, `InvalidResponseBody` and `NoRecording`, with `client.describe_error` for one line of text
- **A bad URL fails at once**: `client.new(url)` returns a `Result`
- **No credentials in errors**: `InvalidUrl` holds a fixed reason, never the URL

## What's New

### A Client From a Base Request

`client.from_request(base)` makes a client from a `ClientRequest`. Each call starts from that request and sets the method, the body, the content type, the path and the query. A test gives the client a request with a recorder, records one time against a real cluster, and then plays back with no cluster. A program can set a timeout or trust another certificate authority in the same way. `client.base_request(client)` returns the base request.

### Typed Errors

Every function returns `Result(String, OpenSearchError)`. Each `dream_http_client` error maps to one variant, with no match on message text. An answer with status 400 or more is `Rejected(status, body)`. A timeout is `TimedOut(timeout_ms)`. A refused or closed connection is `Unavailable(reason)`. A playback request with no recording is `NoRecording`, so a test setup miss does not look like an outage.

### `client.new` Checks the URL One Time

`client.new(base_url)` returns `Result(Client, OpenSearchError)`. It refuses a URL that cannot be parsed, a scheme other than `http` or `https`, a URL with no host, a URL with a query or a fragment, and bad percent-encoding in the user name or password. Version 3.x accepted some of these URLs and failed on each request instead.

## Testing

- 272 tests run, 0 failed, 100.0% line coverage, in about 15 seconds (Apple M1 Max, OTP 29, Gleam 1.19.2, OpenSearch 2.19.1 in Docker on the same machine)
- The tests run against a real OpenSearch 2.19.1 in Docker, locally and in CI. A round trip through `client.from_request` with a recorder is recorded one time and played back
- Each error variant has a test: a closed port, a held request with a short timeout, real 400, 401 and 404 answers, a body that is not UTF-8, and a playback request with no recording

## Upgrading

Allow version 4 in your `gleam.toml` (`dream_opensearch = ">= 4.0.0 and < 5.0.0"`), then run `gleam deps update dream_opensearch`.

### Migration Guide

The guide [Upgrading](https://hexdocs.pm/dream_opensearch/4.0.0/guides/upgrading.html) shows each change with the 3.x code next to the 4.0.0 code:

1. Handle the `Result` of `client.new`.
2. Use `client.describe_error` where you show or log an error.
3. Match `Rejected(status:, body:)` where you read an OpenSearch answer from an error.
4. Read `client.base_request` where you read `base_url`.

## Documentation

- [HexDocs](https://hexdocs.pm/dream_opensearch/4.0.0/)
- [Changelog](https://github.com/TrustBound/dream_opensearch/blob/4.0.0/CHANGELOG.md)

## Community

- [Discussions](https://github.com/TrustBound/dream/discussions)
- [Report Issues](https://github.com/TrustBound/dream_opensearch/issues)
- [Contributing Guide](https://github.com/TrustBound/dream_opensearch/blob/main/CONTRIBUTING.md)
