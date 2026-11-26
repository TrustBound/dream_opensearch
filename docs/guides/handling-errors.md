# Handling errors

Every function in dream_opensearch returns `Result(String, OpenSearchError)`. The error is a type with one variant for each way a request can fail: the base URL cannot be used, the request got no answer, the answer did not come in time, OpenSearch rejected the request, or the answer is not text. Your program needs to know which one it is. A missing index calls for a create, a refused connection calls for a retry later, and a bad URL calls for a fix in your configuration. This guide shows every error the client returns, reads the details out of an OpenSearch error, decides which errors are worth a retry, keeps the password out of your logs, and sets the timeout.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [Step 1: Know the errors you can get](#step-1-know-the-errors-you-can-get)
- [Step 2: Read the details of an OpenSearch error](#step-2-read-the-details-of-an-opensearch-error)
- [Step 3: Decide what is worth a retry](#step-3-decide-what-is-worth-a-retry)
- [Step 4: Log a failure without the password](#step-4-log-a-failure-without-the-password)
- [Step 5: Set the timeout](#step-5-set-the-timeout)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- See the exact `OpenSearchError` value for each way a request can fail.
- Read the error type and the reason out of the body of a `Rejected` error.
- Decide with one function which errors are worth a retry.
- Write a log line that names the cluster but not the user name and password.
- Make a client with a timeout of its own.
- Test the error handling with real errors of the client.

## Before you start

Add the package, and `gleam_json` to read the error bodies:

```sh
gleam add dream_opensearch gleam_json
```

Every example in this guide is tested. The tests make each error happen for real: a port where nothing listens, a host name that does not resolve, and OpenSearch 2.19.1 in Docker for the answers of OpenSearch, with a second node that has the security plugin on for the 401. [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) shows the Docker service, and `docker compose up -d --wait opensearch` starts it. A cluster cannot be made to close a connection with no answer, to hold a request with no answer, or to send a body that is not UTF-8. For those three, a local test server in the tests does it.

## Step 1: Know the errors you can get

Here is every kind of error, with the exact value, for a call such as `document.search(opensearch, "books", query_json)`:

| What happened | The error | Request sent? |
|:---|:---|:---|
| Nothing listens at the address | `Unavailable("Connection failed: Connection refused")` | No |
| The host name does not resolve | `Unavailable("Connection failed: DNS resolution failed (NXDOMAIN)")` | No |
| The server closed the connection with no answer | `Unavailable("Remote closed connection")` | Yes: one time for a POST, two times for the other methods |
| The server sent no answer within the timeout | `TimedOut(timeout_ms: 30000)`, with the timeout of the client | Yes |
| OpenSearch answered with status 400 or more | `Rejected(status: 404, body: "...")`, with the body unchanged | Yes |
| The response body is not valid UTF-8, with any status | `InvalidResponseBody(status: 200)` | Yes |

`client.new` checks the base URL one time, before any request. When it cannot use the URL, it returns `Error(InvalidUrl(reason))`, and you get no client:

| The base URL | The error of `client.new` |
|:---|:---|
| `localhost:9200`, with no scheme | `InvalidUrl("the URL scheme must be http or https")` |
| `http://[::1`, which cannot be parsed | `InvalidUrl("the URL cannot be parsed")` |
| `http://admin:p%zz@localhost:9200`, with bad percent-encoding | `InvalidUrl("the user name or password has invalid percent-encoding")` |
| `http://localhost:9200?pretty=true`, with a query | `InvalidUrl("the URL has a query or a fragment")` |

The body of a `Rejected` error is whatever the server sent. For OpenSearch itself, that is a JSON error object, like this body of the 404 answer to a search on a missing index:

### The answer for a missing index <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/outputs/guide_handling_errors_missing_index.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"error":{"root_cause":[{"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"}],"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"},"status":404}
```

But not every body of a `Rejected` error is a JSON error object:

- The security plugin answers a request with no credentials, or wrong ones, with status 401 and the plain text body `Unauthorized`. So the error is `Rejected(status: 401, body: "Unauthorized")`.
- A proxy or a load balancer in front of the cluster can answer with an HTML page, such as a 502 Bad Gateway page.
- An answer with no body gives an empty body. A HEAD request always has no body, so a HEAD that gets a 404 returns `Rejected(status: 404, body: "")`. A bulk request over the size limit of the cluster gets a 413 with no body.
- A delete of a document that does not exist gets status 404 with a JSON body that has no `error` object: `{"_index":"books","_id":"9","result":"not_found",...}`.

Two more facts you can count on. No error contains the user name or the password from the base URL. And for the rows marked "No", the client did not send anything, so nothing changed on the cluster.

When the server closes the connection with no answer, the client sends a GET, HEAD, PUT or DELETE request a second time on a new connection. It returns `Unavailable("Remote closed connection")` only when that one fails too. For example, `document.index` and `document.delete` go two times. A POST goes one time only, because it may not be safe to repeat: `document.search` and `document.bulk` return the error after the first try.

### The shared error type

`client.to_error(error)` maps an `OpenSearchError` to `dream_errors.Error(OpenSearchError)`, the error type that the Dream packages share. An app that also uses other Dream packages can then handle all their errors with one type. The message is the text of `client.describe_error`, for developers and logs.

| `OpenSearchError` | `dream_errors.Error` |
|:---|:---|
| `InvalidUrl(reason)` | `Invalid` |
| `Unavailable(reason)` | `Unavailable` |
| `TimedOut(timeout_ms)` | `Timeout` |
| `Rejected(status: 404, body)` | `NotFound` |
| `Rejected(status: 409, body)` | `Conflict` |
| `Rejected` with another status, `InvalidResponseBody(status)`, `NoRecording(..)` | `Failed` |

Each one keeps the `OpenSearchError` as the cause, except `NotFound`, which has no cause. Its message holds the status and the body of the answer.

## Step 2: Read the details of an OpenSearch error

The status of a `Rejected` error tells you a little. The error type in its body tells you what went wrong. This is the start of an `opensearch_errors` module:

### Read the type and the reason of an OpenSearch error <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_classify.gleam#L6-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{
  type OpenSearchError, InvalidResponseBody, InvalidUrl, NoRecording, Rejected,
  TimedOut, Unavailable,
}
import gleam/dynamic/decode
import gleam/json
import gleam/result

/// The `error` object of an OpenSearch answer.
pub type ErrorDetails {
  ErrorDetails(error_type: String, reason: String)
}

/// The type and the reason of a `Rejected` error, when its body is an
/// OpenSearch error object. `Error(Nil)` for any other error or body.
pub fn error_details(error: OpenSearchError) -> Result(ErrorDetails, Nil) {
  case error {
    Rejected(body:, ..) ->
      json.parse(body, details_decoder())
      |> result.replace_error(Nil)
    _ -> Error(Nil)
  }
}

fn details_decoder() -> decode.Decoder(ErrorDetails) {
  use error_type <- decode.subfield(["error", "type"], decode.string)
  use reason <- decode.subfield(["error", "reason"], decode.string)
  decode.success(ErrorDetails(error_type:, reason:))
}
```

`error_details` reads the body of a `Rejected` error as an OpenSearch error object. If that works, you get the error type and the reason. For any other error, or a body that is not an error object, you get `Error(Nil)`, and the error itself still holds everything there is to know.

For the missing index from Step 1, `error_details` returns:

### The value that error_details returns <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/outputs/guide_handling_errors_classified.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok(ErrorDetails(error_type: "index_not_found_exception", reason: "no such index [books]"))
```

For a 401 with the body `Unauthorized`, a 502 page from a proxy, or an empty body, it returns `Error(Nil)`.

Now your code matches on the case it cares about. For example, a search screen shows "no results" for the error type `index_not_found_exception`, and "search is down, try again" for `Unavailable`.

The error type is the part of the body to match on. The status alone is not enough: status 400 means an index that already exists, a bad index name, a query OpenSearch cannot parse, and more. The `reason` is for people. Log it, but do not match on it, because its wording can change between OpenSearch versions.

## Step 3: Decide what is worth a retry

Some errors pass on their own if you wait: a cluster that is still starting, a node under too much load, a network that dropped a connection. Others fail the same way every time until someone changes the request or the configuration. Add this to the module:

### Decide which errors are worth a retry <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_classify.gleam#L36-L48"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// True for the errors that can go away if you send the same request
/// again a little later.
pub fn worth_a_retry(error: OpenSearchError) -> Bool {
  case error {
    Unavailable(_) | TimedOut(_) -> True
    Rejected(status: 429, ..)
    | Rejected(status: 502, ..)
    | Rejected(status: 503, ..)
    | Rejected(status: 504, ..) -> True
    Rejected(..) | InvalidUrl(_) | InvalidResponseBody(_) | NoRecording(..) ->
      False
  }
}
```

The function names every variant, with no catch-all. So if a future version of the package adds a variant, your code does not compile until you decide about it.

| Error | Worth a retry | Why |
|:---|:---|:---|
| `Unavailable` | Yes | The cluster is down, starting, or moving, or the connection broke |
| `TimedOut` | Yes, if the request is safe to repeat | The request went out, and you do not know what happened to it |
| `Rejected` with status 429 | Yes | The cluster is too busy. Wait before the next try |
| `Rejected` with status 502, 503 or 504 | Yes | A node or a proxy is not ready. For example, `cluster_block_exception` with status 503 while the cluster starts |
| `Rejected` with another status | No | The request is wrong, or the data is: a missing index, a bad query, a mapping conflict, or a 401 |
| `InvalidUrl` | No | The base URL is wrong. Fix the configuration |
| `InvalidResponseBody` | No | The server sent bytes that are not text. Look at the server |
| `NoRecording` | No | A test recorder has no recording for the request. Record it |

Retry with a wait between the tries, and with a limit on the number of tries. A cluster under load needs time, and a tight loop of retries makes the load worse.

"Safe to repeat" matters for `TimedOut` and for a closed connection. Indexing a document under its ID is safe: a second try stores the same document again. A bulk request with `create` actions, or a reindex, is not: part of it may already be done.

## Step 4: Log a failure without the password

When a request fails, you want to log which cluster it went to, and what went wrong. `client.describe_error` turns any error into one line of text, and that text never holds the user name or the password. The client keeps the password only in the `authorization` header of its base request, so build the address from the scheme, the host and the port:

### Write a log line without the user name and password <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_log.gleam#L6-L31"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_http_client/client as http_client
import dream_opensearch/client.{type Client, type OpenSearchError}
import gleam/http
import gleam/int
import gleam/option.{None, Some}

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

pub fn failure_line(opensearch: Client, error: OpenSearchError) -> String {
  "OpenSearch request to "
  <> address(opensearch)
  <> " failed: "
  <> client.describe_error(error)
}
```

For a client created with `client.new("https://admin:s3cret@search.example.com:9200")` and a refused connection, `failure_line` returns:

### The line that failure_line returns <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/outputs/guide_handling_errors_failure_line.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
OpenSearch request to https://search.example.com:9200 failed: OpenSearch is unavailable: Connection failed: Connection refused
```

The text of a `Rejected` error holds the body of the answer. Log it, because it holds the reason. Never log the headers of the base request, and never log the client value with `string.inspect`, because the `authorization` header holds the password in Base64.

## Step 5: Set the timeout

The client waits 30 seconds for an answer, the default of `dream_http_client`. To wait longer or less, build the client from a `dream_http_client` request with `client.from_request`, and set the timeout on that request:

### Make a client with a timeout of its own <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_timeout.gleam#L5-L18"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_http_client/client as http_client
import dream_opensearch/client.{type Client}
import gleam/http

/// A client for the cluster at `host` and `port` that waits at most
/// `timeout_ms` for each answer.
pub fn client_with_timeout(host: String, port: Int, timeout_ms: Int) -> Client {
  http_client.new()
  |> http_client.scheme(http.Http)
  |> http_client.host(host)
  |> http_client.port(port)
  |> http_client.timeout(timeout_ms)
  |> client.from_request
}
```

Every request of that client starts from the base request, so every request has that timeout. When no answer comes in time, the error is `TimedOut(timeout_ms:)` with the value you set. The same base request can also carry other headers, a connection pool, a certificate authority file, or a recorder for tests.

## Test your code

Your error handling is the code that runs least in development, so test it on purpose. You can make most of the errors happen for real in a test:

- A real cluster in Docker, started with `docker compose up -d --wait opensearch`, gives real OpenSearch errors: a search on an index that does not exist gives the 404 of Step 1.
- A client for `http://127.0.0.1:1` gives a refused connection, at once, because nothing listens on port 1.
- `client.new("localhost:9200")`, with no scheme, gives an `InvalidUrl` error, and sends nothing.
- A `Rejected` error is a value, so you can build one with a body that you copied from your cluster, and pass it straight to `error_details`.

Add `dream_test` as a dev dependency, with the version range that this package tests with:

### The dev dependency on dream_test <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/gleam.toml#L28-L29"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```toml
[dev-dependencies]
dream_test = ">= 3.0.0 and < 4.0.0"
```

Here is a test module for the error handling:

### Test the error handling with real errors <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/guide_handling_errors_testing.gleam#L5-L79"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{InvalidUrl, Rejected, Unavailable}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/result
import snippets/guide_handling_errors_classify.{
  ErrorDetails, error_details, worth_a_retry,
}

pub fn tests() -> TestSuite {
  describe("error handling", [
    it("reads a missing index from its error body", fn() {
      // Arrange
      let error =
        Rejected(
          status: 404,
          body: "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}",
        )

      // Act
      let details = error_details(error)

      // Assert
      details
      |> should
      |> be_equal(
        Ok(ErrorDetails("index_not_found_exception", "no such index [books]")),
      )
      |> or_fail_with("Expected a missing index")
    }),
    it("retries a refused connection", fn() {
      // Arrange
      // Nothing listens on port 1
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let retry =
        document.delete(opensearch, "books", "1")
        |> result.map_error(worth_a_retry)

      // Assert
      retry
      |> should
      |> be_equal(Error(True))
      |> or_fail_with("A refused connection is worth a retry")
    }),
    it("does not retry a URL with no scheme", fn() {
      // Act
      let created = client.new("localhost:9200")

      // Assert
      created
      |> result.map_error(fn(error) { #(error, worth_a_retry(error)) })
      |> should
      |> be_equal(
        Error(#(InvalidUrl("the URL scheme must be http or https"), False)),
      )
      |> or_fail_with("A URL needs http:// or https://")
    }),
    it("gives the reason of an unavailable cluster", fn() {
      // Arrange
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let deleted = document.delete(opensearch, "books", "1")

      // Assert
      deleted
      |> should
      |> be_equal(Error(Unavailable("Connection failed: Connection refused")))
      |> or_fail_with("Nothing listens on port 1")
    }),
  ])
}
```

Three of the tests use the real client: a real `document` function against a closed port, and a real `client.new` with a bad URL. That is how your own code gets these errors, so the tests also catch a change in a future version of the package.

## Common pitfalls

**Every error treated the same.** *Symptom:* your program retries a bad query forever, or shows "server down" for a missing index. *Fix:* match on the variant, as in [Step 3](#step-3-decide-what-is-worth-a-retry), and read the error type of a `Rejected` error, as in [Step 2](#step-2-read-the-details-of-an-opensearch-error).

**Matching on the status alone.** *Symptom:* "index already exists" handling also hides a bad index name or a bad mapping. *Fix:* match on `error.type` in the body. Many different errors share status 400.

**Expecting JSON in every body.** *Symptom:* a decode error while you handle another error. *Fix:* a 401 from the security plugin is plain text, a proxy sends HTML, and a HEAD sends no body. Keep the `Rejected` error when `error_details` returns `Error(Nil)`.

**A 404 that is not an error.** *Symptom:* a delete of a document that is already gone fails your whole job. *Fix:* a 404 for a document has `"result":"not_found"` and no `error` object. Accept it where it makes sense, as `delete_user` in [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#step-4-delete-a-document) does.

**A bulk request that returns `Ok`.** *Symptom:* no error, but documents are missing. *Fix:* the bulk API answers 200 when some documents fail. Read the items, as [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md) shows.

**The password in a log line.** *Symptom:* credentials in your logs or crash reports. *Fix:* log `client.describe_error(error)` and the address, as in [Step 4](#step-4-log-a-failure-without-the-password). Never log the client value or the headers of its base request.

**A request that takes more than the timeout.** *Symptom:* `TimedOut(timeout_ms: 30000)` from a large reindex or a heavy search, while OpenSearch goes on with the work. *Fix:* keep requests short: search with a smaller `size`, and split large jobs. When a request must take longer, make a client with a longer timeout, as in [Step 5](#step-5-set-the-timeout).

## Where to go next

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): the first requests, and a module that accepts a missing document.
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): accept an index that already exists, and tell a missing index from a cluster you cannot reach.
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): the errors inside a bulk response, and which ones to retry.
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): the errors of a search, and what they mean for your query.
- [Upgrading](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/upgrading.md): the changes from 3.x to 4.0.0.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/dream_opensearch/client.html): `OpenSearchError`, `describe_error` and `from_request`.
