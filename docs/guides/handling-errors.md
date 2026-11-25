# Handling errors

Every function in dream_opensearch returns `Result(String, String)`, and the error is a plain string. That string can come from two places: the client, when the request could not be sent or the answer could not be read, or OpenSearch, when it answered with an error status. Your program needs to know which one it is. A missing index calls for a create, a refused connection calls for a retry later, and a bad URL calls for a fix in your configuration. This guide shows every error the client returns, turns the string into a typed error that you can match on, decides which errors are worth a retry, and keeps the password out of your logs.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [Step 1: Know the errors you can get](#step-1-know-the-errors-you-can-get)
- [Step 2: Turn the string into a typed error](#step-2-turn-the-string-into-a-typed-error)
- [Step 3: Decide what is worth a retry](#step-3-decide-what-is-worth-a-retry)
- [Step 4: Log a failure without the password](#step-4-log-a-failure-without-the-password)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- See the exact error string for each way a request can fail.
- Turn any error string into an `OpenSearchError` with five cases: unreachable, interrupted, bad configuration, rejected by OpenSearch, and any other answer.
- Read the status, the error type and the reason out of an OpenSearch error body.
- Decide with one function which errors are worth a retry.
- Write a log line that names the cluster but not the user name and password.
- Test the error handling with the exact strings the client returns.

## Before you start

Add the package, and `gleam_json` to read the error bodies:

```sh
gleam add dream_opensearch gleam_json
```

Every example in this guide is tested. The tests make each error happen for real: a port where nothing listens, a host name that does not resolve, and OpenSearch 2.19.1 in Docker for the answers of OpenSearch, with a second node that has the security plugin on for the 401. [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) shows the Docker service, and `docker compose up -d --wait opensearch` starts it. A cluster cannot be made to close a connection with no answer, or to send a body that is not UTF-8, so for those two a local test server in the tests does it. The 30 second timeout is not tested: the message and the 30000 ms default come from the source of `dream_http_client`.

## Step 1: Know the errors you can get

Here is every kind of error, with the exact string, for a call such as `document.search(opensearch, "books", query_json)`:

| What happened | The error string | Request sent? |
|:---|:---|:---|
| Nothing listens at the address | `Connection failed: Connection refused` | No |
| The host name does not resolve | `Connection failed: DNS resolution failed (NXDOMAIN)` | No |
| The server closed the connection with no answer | `Remote closed connection` | Yes: one time for a POST, two times for the other methods |
| The server sent nothing for 30 seconds | `Timed out after 30000ms` | Yes |
| The base URL has no scheme, as in `localhost:9200` | `Invalid OpenSearch URL: the URL has no host` | No |
| The base URL cannot be parsed, as in `http://[::1` | `Invalid OpenSearch URL: the URL cannot be parsed` | No |
| The password in the URL has bad percent-encoding, as in `p%zz` | `Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding` | No |
| OpenSearch answered with status 400 or more | The response body, unchanged | Yes |
| The response body is not valid UTF-8, with any status | `The OpenSearch response body is not valid UTF-8` | Yes |

The first rows are messages from the client. The OpenSearch row is different: the error is whatever body the server sent. For OpenSearch itself, that is a JSON error object, like this answer to a search on a missing index:

### The answer for a missing index <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_handling_errors_missing_index.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"error":{"root_cause":[{"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"}],"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"},"status":404}
```

But not every answer with an error status is a JSON error object:

- The security plugin answers a request with no credentials, or wrong ones, with status 401 and the plain text body `Unauthorized`. So the error is `Unauthorized`.
- A proxy or a load balancer in front of the cluster can answer with an HTML page, such as a 502 Bad Gateway page.
- An answer with no body gives an empty string. A HEAD request always has no body, so a HEAD that gets a 404 returns `Error("")`. A bulk request over the size limit of the cluster gets a 413 with no body, and returns `Error("")` too.
- A delete of a document that does not exist gets status 404 with a JSON body that has no `error` object: `{"_index":"books","_id":"9","result":"not_found",...}`.

Two more facts you can count on. No error string contains the user name or the password from the base URL. And for the rows marked "No", the client did not send anything, so nothing changed on the cluster.

When the server closes the connection with no answer, the client sends a GET, HEAD, PUT or DELETE request a second time on a new connection, and returns `Remote closed connection` only when that one fails too. For example, `document.index` and `document.delete` go two times. A POST goes one time only, because it may not be safe to repeat: `document.search` and `document.bulk` return `Remote closed connection` after the first try.

## Step 2: Turn the string into a typed error

Matching on strings all over your code is fragile. Do it in one place, and give the rest of your program a type. This is an `opensearch_errors` module:

### Turn an error string into a typed error <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_handling_errors_classify.gleam#L6-L45"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import gleam/dynamic/decode
import gleam/json

pub type OpenSearchError {
  /// The client could not connect: refused, unknown host, TLS failure.
  Unreachable(reason: String)
  /// The connection broke or went quiet after the request went out.
  Interrupted(message: String)
  /// The base URL cannot be used. No request went out.
  BadConfiguration(message: String)
  /// OpenSearch answered with an error object.
  Rejected(status: Int, error_type: String, reason: String)
  /// Any other answer with an error status, as it came.
  OtherAnswer(body: String)
}

pub fn classify(message: String) -> OpenSearchError {
  case message {
    "Connection failed: " <> reason -> Unreachable(reason)
    "Remote closed connection" | "Timed out after " <> _ -> Interrupted(message)
    "Invalid OpenSearch URL: " <> _
    | "Invalid credentials in the OpenSearch URL: " <> _ ->
      BadConfiguration(message)
    _ -> from_body(message)
  }
}

fn from_body(body: String) -> OpenSearchError {
  case json.parse(body, rejected_decoder()) {
    Ok(rejected) -> rejected
    Error(_) -> OtherAnswer(body)
  }
}

fn rejected_decoder() -> decode.Decoder(OpenSearchError) {
  use status <- decode.field("status", decode.int)
  use error_type <- decode.subfield(["error", "type"], decode.string)
  use reason <- decode.subfield(["error", "reason"], decode.string)
  decode.success(Rejected(status:, error_type:, reason:))
}
```

`classify` checks the client's messages first, by their fixed start. Everything else is an answer from the server, and `from_body` tries to read it as an OpenSearch error object. If that works, you get `Rejected` with the status, the error type and the reason. If not, the body comes back whole in `OtherAnswer`.

For the missing index from Step 1, `classify` returns:

### The error that classify returns <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_handling_errors_classified.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Rejected(status: 404, error_type: "index_not_found_exception", reason: "no such index [books]")
```

And for the other strings:

| Error string | `classify` returns |
|:---|:---|
| `Connection failed: Connection refused` | `Unreachable("Connection refused")` |
| `Remote closed connection` | `Interrupted("Remote closed connection")` |
| `Timed out after 30000ms` | `Interrupted("Timed out after 30000ms")` |
| `Invalid OpenSearch URL: the URL has no host` | `BadConfiguration("Invalid OpenSearch URL: the URL has no host")` |
| `Unauthorized` | `OtherAnswer("Unauthorized")` |
| A 502 page from a proxy | `OtherAnswer("<html>...")` |
| `""` | `OtherAnswer("")` |

Now your code matches on the case it cares about. For example, a search screen shows "no results" for `Rejected(error_type: "index_not_found_exception", ..)`, and "search is down, try again" for `Unreachable`.

To use it, map the error of any call: `document.search(opensearch, "books", query_json) |> result.map_error(classify)`.

The error type is the part of the body to match on. The status alone is not enough: status 400 means an index that already exists, a bad index name, a query OpenSearch cannot parse, and more. The `reason` is for people. Log it, but do not match on it, because its wording can change between OpenSearch versions.

## Step 3: Decide what is worth a retry

Some errors pass on their own if you wait: a cluster that is still starting, a node under too much load, a network that dropped a connection. Others fail the same way every time until someone changes the request or the configuration. Add this to the module:

### Decide which errors are worth a retry <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_handling_errors_classify.gleam#L47-L58"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// True for the errors that can go away if you send the same request
/// again a little later.
pub fn worth_a_retry(error: OpenSearchError) -> Bool {
  case error {
    Unreachable(_) | Interrupted(_) -> True
    Rejected(status: 429, ..)
    | Rejected(status: 502, ..)
    | Rejected(status: 503, ..)
    | Rejected(status: 504, ..) -> True
    Rejected(..) | BadConfiguration(_) | OtherAnswer(_) -> False
  }
}
```

| Error | Worth a retry | Why |
|:---|:---|:---|
| `Unreachable` | Yes | The cluster is down, starting, or moving. Nothing was sent |
| `Interrupted` | Yes, if the request is safe to repeat | The request went out, and you do not know what happened to it |
| `Rejected` with status 429 | Yes | The cluster is too busy. Wait before the next try |
| `Rejected` with status 502, 503 or 504 | Yes | A node or a proxy is not ready. For example, `cluster_block_exception` with status 503 while the cluster starts |
| `Rejected` with another status | No | The request is wrong, or the data is: a missing index, a bad query, a mapping conflict |
| `BadConfiguration` | No | The base URL is wrong. Fix the configuration |
| `OtherAnswer` | No | A 401, a proxy page or an empty body. Look at it before you retry |

Retry with a wait between the tries, and with a limit on the number of tries. A cluster under load needs time, and a tight loop of retries makes the load worse.

"Safe to repeat" matters for `Interrupted`. Indexing a document under its ID is safe: a second try stores the same document again. A bulk request with `create` actions, or a reindex, is not: part of it may already be done.

## Step 4: Log a failure without the password

When a request fails, you want to log which cluster it went to. But `opensearch.base_url` holds the user name and password exactly as you gave them to `client.new`. So build the log line from the URL without them:

### Write a log line without the user name and password <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_handling_errors_log.gleam#L6-L20"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import gleam/option.{None}
import gleam/uri.{Uri}

/// The base URL of `opensearch` without its user name and password.
pub fn safe_url(opensearch: Client) -> String {
  case uri.parse(opensearch.base_url) {
    Ok(parsed) -> uri.to_string(Uri(..parsed, userinfo: None))
    Error(Nil) -> "(a base URL that cannot be parsed)"
  }
}

pub fn failure_line(opensearch: Client, message: String) -> String {
  "OpenSearch request to " <> safe_url(opensearch) <> " failed: " <> message
}
```

For a client created with `client.new("https://admin:s3cret@search.example.com:9200")` and a refused connection, `failure_line` returns:

### The line that failure_line returns <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_handling_errors_failure_line.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
OpenSearch request to https://search.example.com:9200 failed: Connection failed: Connection refused
```

The error strings of the package never hold the user name or the password, so you can log the message as it is. The only place they appear is the base URL, so never log it, and never log the client value with `string.inspect`.

## Test your code

Your error handling is the code that runs least in development, so test it on purpose. You can make most of the errors happen for real in a test:

- A real cluster in Docker, started with `docker compose up -d --wait opensearch`, gives real OpenSearch errors: a search on an index that does not exist gives the 404 body of Step 1.

- A client for `http://127.0.0.1:1` gives a refused connection, at once, because nothing listens on port 1.
- A client for `localhost:9200`, with no scheme, gives the "no host" error, and sends nothing.
- An OpenSearch error body is a string, so you can pass one that you copied from your cluster straight to `classify`.

Add `dream_test` as a dev dependency, with the version range that this package tests with:

### The dev dependency on dream_test <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/gleam.toml#L26-L27"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```toml
[dev-dependencies]
dream_test = ">= 3.0.0 and < 4.0.0"
```

Here is a test module for `classify`:

### Test classify with real error strings <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_handling_errors_testing.gleam#L5-L68"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/result
import snippets/guide_handling_errors_classify.{
  BadConfiguration, Rejected, Unreachable, classify,
}

pub fn tests() -> TestSuite {
  describe("classify", [
    it("reads a missing index from its error body", fn() {
      // Arrange
      let body =
        "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}"

      // Act
      let error = classify(body)

      // Assert
      error
      |> should
      |> be_equal(Rejected(
        404,
        "index_not_found_exception",
        "no such index [books]",
      ))
      |> or_fail_with("Expected a 404 rejection")
    }),
    it("calls a refused connection unreachable", fn() {
      // Arrange
      let opensearch = client.new("http://127.0.0.1:1")

      // Act
      let error =
        document.delete(opensearch, "books", "1")
        |> result.map_error(classify)

      // Assert
      error
      |> should
      |> be_equal(Error(Unreachable("Connection refused")))
      |> or_fail_with("Nothing listens on port 1")
    }),
    it("calls a URL with no scheme a bad configuration", fn() {
      // Arrange
      let opensearch = client.new("localhost:9200")

      // Act
      let error =
        document.delete(opensearch, "books", "1")
        |> result.map_error(classify)

      // Assert
      error
      |> should
      |> be_equal(
        Error(BadConfiguration("Invalid OpenSearch URL: the URL has no host")),
      )
      |> or_fail_with("A URL needs http:// or https://")
    }),
  ])
}
```

The last two tests call a real `document` function and map its error with `classify`. That is how your own code uses it, so the tests also catch a change in the strings of a future version of the package.

## Common pitfalls

**Every error treated the same.** *Symptom:* your program retries a bad query forever, or shows "server down" for a missing index. *Fix:* classify the error first, as in [Step 2](#step-2-turn-the-string-into-a-typed-error), and act on the case.

**Matching on the status alone.** *Symptom:* "index already exists" handling also hides a bad index name or a bad mapping. *Fix:* match on `error.type` in the body. Many different errors share status 400.

**Expecting JSON in every error.** *Symptom:* a decode error while you handle another error. *Fix:* a 401 from the security plugin is plain text, a proxy sends HTML, and a HEAD sends no body. Fall back to the raw body, as `OtherAnswer` does.

**A 404 that is not an error.** *Symptom:* a delete of a document that is already gone fails your whole job. *Fix:* a 404 for a document has `"result":"not_found"` and no `error` object. Accept it where it makes sense, as `delete_user` in [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#step-4-delete-a-document) does.

**A bulk request that returns `Ok`.** *Symptom:* no error, but documents are missing. *Fix:* the bulk API answers 200 when some documents fail. Read the items, as [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md) shows.

**The password in a log line.** *Symptom:* credentials in your logs or crash reports. *Fix:* never log `opensearch.base_url` or the client value. Log the URL without credentials, as in [Step 4](#step-4-log-a-failure-without-the-password).

**A request that takes more than 30 seconds.** *Symptom:* `Timed out after 30000ms` from a large reindex or a heavy search, while OpenSearch goes on with the work. *Fix:* the client waits at most 30 seconds for an answer, and dream_opensearch has no setting to change that. Keep requests short: search with a smaller `size`, and split large jobs.

## Where to go next

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): the first requests, and a module that accepts a missing document.
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): accept an index that already exists, and tell a missing index from a cluster you cannot reach.
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): the errors inside a bulk response, and which ones to retry.
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): the errors of a search, and what they mean for your query.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/dream_opensearch/client.html): `send_request` and its list of errors.
