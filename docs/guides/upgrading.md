# Upgrading

This guide lists the changes that need a change in your code, for each major version. Each change shows the code before and after.

## Table of Contents

- [From 3.x to 4.0.0](#from-3x-to-400)
  - [client.new returns a Result](#clientnew-returns-a-result)
  - [Errors are an OpenSearchError](#errors-are-an-opensearcherror)
  - [Match on the variant, not on the text](#match-on-the-variant-not-on-the-text)
  - [The base URL is not a field](#the-base-url-is-not-a-field)
  - [New: a client from a base request](#new-a-client-from-a-base-request)

## From 3.x to 4.0.0

Version 4.0.0 changes two things. `client.new` checks the base URL one time and returns `Result(Client, OpenSearchError)`. And every function returns `Result(String, OpenSearchError)` in place of `Result(String, String)`, so your code matches on a variant, not on a text.

### client.new returns a Result

In 3.x, `client.new` returned a `Client` for any text, and each request parsed the URL again. A bad URL showed up only at the first request.

### Before: create a client <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/doc_client_new.gleam#L5-L7"><img align="right" alt="Code at 3.0.0" src="https://img.shields.io/badge/%F0%9F%93%9C_code_at-3.0.0-lightgrey.svg?style=flat-square"></a>

```gleam
pub fn create_local_client() -> Client {
  client.new("http://localhost:9200")
}
```

### After: create a client <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_new.gleam#L5-L7"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
pub fn create_local_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}
```

Create the client one time when your program starts, and stop with a clear message when the URL is wrong. In a function that returns `Result(_, OpenSearchError)`, use `use opensearch <- result.try(client.new(url))`. A test can use `let assert Ok(opensearch) = client.new(url)`.

### Errors are an OpenSearchError

In 3.x, the error was a `String`: a message of the client, or the body of an OpenSearch answer. In 4.0.0, it is an `OpenSearchError`. Where you only show or log the error, use `client.describe_error`:

### Before: show the error <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/doc_document_index.gleam#L14-L17"><img align="right" alt="Code at 3.0.0" src="https://img.shields.io/badge/%F0%9F%93%9C_code_at-3.0.0-lightgrey.svg?style=flat-square"></a>

```gleam
  case document.index(opensearch, index, "123", json.to_string(user)) {
    Ok(_response) -> "Indexed successfully"
    Error(message) -> "Error: " <> message
  }
```

### After: show the error <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_document_index.gleam#L14-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
  case document.index(opensearch, index, "123", json.to_string(user)) {
    Ok(_response) -> "Indexed successfully"
    Error(error) -> "Error: " <> client.describe_error(error)
  }
```

The text of a 3.x error and the text of `describe_error` are different. For example, a refused connection was `Connection failed: Connection refused`, and now it is `OpenSearch is unavailable: Connection failed: Connection refused`. An OpenSearch answer was the body alone, and now it is `OpenSearch rejected the request with status 404: ` and then the body.

### Match on the variant, not on the text

In 3.x, code read the body of every error to find an OpenSearch answer. In 4.0.0, an OpenSearch answer with status 400 or more is `Rejected(status, body)`, so you match on the variant and the status:

### Before: accept a missing document <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_getting_started_user_store.gleam#L64-L79"><img align="right" alt="Code at 3.0.0" src="https://img.shields.io/badge/%F0%9F%93%9C_code_at-3.0.0-lightgrey.svg?style=flat-square"></a>

```gleam
pub fn delete_user(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(Nil, String) {
  document.delete(opensearch, index, id)
  |> result.replace(Nil)
  |> result.try_recover(ignore_not_found)
}

fn ignore_not_found(body: String) -> Result(Nil, String) {
  case json.parse(body, decode.at(["result"], decode.string)) {
    Ok("not_found") -> Ok(Nil)
    _ -> Error(body)
  }
}
```

### After: accept a missing document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_getting_started_user_store.gleam#L63-L80"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
pub fn delete_user(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(Nil, OpenSearchError) {
  case document.delete(opensearch, index, id) {
    Ok(_response) -> Ok(Nil)
    Error(Rejected(status: 404, body:)) -> ignore_not_found(body)
    Error(error) -> Error(error)
  }
}

fn ignore_not_found(body: String) -> Result(Nil, OpenSearchError) {
  case json.parse(body, decode.at(["result"], decode.string)) {
    Ok("not_found") -> Ok(Nil)
    _ -> Error(Rejected(status: 404, body:))
  }
}
```

Each 3.x error text has a variant now:

| The 3.x error | The 4.0.0 error |
|:---|:---|
| The body of an answer with status 400 or more | `Rejected(status:, body:)` |
| `Connection failed: <reason>` | `Unavailable("Connection failed: <reason>")` |
| `Remote closed connection` | `Unavailable("Remote closed connection")` |
| `Timed out after 30000ms` | `TimedOut(timeout_ms: 30000)` |
| `The OpenSearch response body is not valid UTF-8` | `InvalidResponseBody(status:)` |
| `Invalid OpenSearch URL: ...` or `Invalid credentials in the OpenSearch URL: ...` | `InvalidUrl(reason)`, from `client.new` only |

[Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) shows each variant and what to do with it.

### The base URL is not a field

In 3.x, `Client` had the field `base_url`, which held the password. In 4.0.0, `Client` is opaque. The password is only in the `authorization` header of the base request, and `client.base_request` returns that request. Code that read `opensearch.base_url` to log the address reads the scheme, the host and the port of the base request now:

### Before: the address for a log line <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_handling_errors_log.gleam#L10-L16"><img align="right" alt="Code at 3.0.0" src="https://img.shields.io/badge/%F0%9F%93%9C_code_at-3.0.0-lightgrey.svg?style=flat-square"></a>

```gleam
/// The base URL of `opensearch` without its user name and password.
pub fn safe_url(opensearch: Client) -> String {
  case uri.parse(opensearch.base_url) {
    Ok(parsed) -> uri.to_string(Uri(..parsed, userinfo: None))
    Error(Nil) -> "(a base URL that cannot be parsed)"
  }
}
```

### After: the address for a log line <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_log.gleam#L12-L24"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// The scheme, the host and the port of `opensearch`. The base request
/// keeps the password only in its `authorization` header, so this has none.
pub fn address(opensearch: Client) -> String {
  let base = client.base_request(opensearch)
  let port = case http_client.get_port(base) {
    Some(port) -> ":" <> int.to_string(port)
    None -> ""
  }
  http.scheme_to_string(http_client.get_scheme(base))
  <> "://"
  <> http_client.get_host(base)
  <> port
}
```

### New: a client from a base request

`client.from_request` makes a client from a `dream_http_client` request. Every request of the client starts from that base request, with its scheme, host, port, headers, timeouts and recorder. Use it to set a timeout, to trust another certificate authority, or to record the answers of a cluster for your tests:

### Create a client with a timeout and a recorder <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_from_request.gleam#L8-L16"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
pub fn create_recorded_client(recorder: Recorder) -> Client {
  http_client.new()
  |> http_client.scheme(http.Http)
  |> http_client.host("localhost")
  |> http_client.port(9201)
  |> http_client.timeout(5000)
  |> http_client.recorder(recorder)
  |> client.from_request
}
```

No 3.x code needs this change. It is new in 4.0.0.
