# Getting started

You have an OpenSearch cluster and a Gleam program. You want the program to store records in the cluster and find them again by their text. This guide takes you from an empty project to a small module that saves, finds and deletes users, connects to a secured cluster, and has tests.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [The short version](#the-short-version)
- [Step 1: Create a client](#step-1-create-a-client)
- [Step 2: Save a document](#step-2-save-a-document)
- [Step 3: Search and read the hits](#step-3-search-and-read-the-hits)
- [Step 4: Delete a document](#step-4-delete-a-document)
- [Step 5: Put it in your program](#step-5-put-it-in-your-program)
- [Which function to use](#which-function-to-use)
- [When something goes wrong](#when-something-goes-wrong)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- Create a client for a local cluster, and one for a secured cluster with a user name and password.
- Save a Gleam `User` value as a document.
- Search by name and get `User` values back, not JSON text.
- Delete a user, and accept a user that is not there.
- Save a user and find it in the same program run.
- Run a real OpenSearch in Docker for your tests, and test the JSON reading with no cluster at all.

## Before you start

Add the package, and `gleam_json` to build and read JSON:

```sh
gleam add dream_opensearch gleam_json
```

dream_opensearch has no dependency on Dream or on any other framework, so you can use it in any Gleam project. It works with OpenSearch, and with Elasticsearch clusters that have the same document and search APIs.

You also need a cluster. The examples use a cluster on `http://localhost:9200`, the default port of OpenSearch, with the security plugin turned off, which is the usual setup for development. [Step 1](#step-1-create-a-client) shows how to connect to a secured cluster instead.

The quickest cluster for development is OpenSearch in Docker. This is the service that the tests of dream_opensearch run against, from the `docker-compose.yml` of the package:

### The OpenSearch service of the tests <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/docker-compose.yml#L16-L33"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```yaml
services:
  opensearch:
    image: opensearchproject/opensearch:2.19.1
    environment:
      discovery.type: single-node
      DISABLE_SECURITY_PLUGIN: "true"
      DISABLE_INSTALL_DEMO_CONFIG: "true"
      OPENSEARCH_JAVA_OPTS: "-Xms512m -Xmx512m"
      # A small request size limit, so the tests can show the 413 answer
      # to a bulk request that is too large.
      http.max_content_length: 1mb
    ports:
      - "9201:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=1s' > /dev/null"]
      interval: 3s
      timeout: 5s
      retries: 60
```

Put it in a `docker-compose.yml` file and start it. `--wait` returns when the health check passes, which took about 15 seconds on our machine:

### Start the cluster <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/scripts/search-up.sh#L9"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```sh
docker compose up -d --wait opensearch
```

This file maps the cluster to port 9201, so use `http://localhost:9201` as the base URL with it, or change the port mapping to `"9200:9200"`. Leave out `http.max_content_length` for your own work: the default limit is 100 MB. `docker compose down` stops the cluster and removes its data.

Every example in this guide is tested against OpenSearch 2.19.1, in this Docker service. The responses you see here are bodies that the cluster really sent. Fields such as `took`, `_score`, `_seq_no` and `_version` change from run to run, so your numbers can differ.

## The short version

Here is the smallest useful program. It creates a client, then indexes, searches for and deletes one user:

### Index, search and delete a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/readme_quick_start.gleam#L5-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

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

Every document function takes a JSON string and returns `Result(String, OpenSearchError)`. `Ok` holds the response body that OpenSearch sent, as a JSON string. `Error` holds an `OpenSearchError`: for example `Rejected(status, body)` for an error answer of OpenSearch, or `Unavailable(reason)` when the request got no answer. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) shows each one. The package sends and receives JSON text. It does not turn it into Gleam values for you, and the steps below show how to do that.

## Step 1: Create a client

A `Client` holds the base request of your cluster: the scheme, the host, the port and the headers that each request starts from. `client.new` reads the base URL one time and returns `Error(InvalidUrl(reason))` when it cannot use it. It does not connect. So you can create the client once when your program starts, and pass it to each function that needs it.

### Create a client for a local and a secured cluster <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_connect.gleam#L5-L29"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client, type OpenSearchError, InvalidUrl}
import gleam/option.{Some}
import gleam/result
import gleam/uri.{Uri}

/// A client for a cluster on your own machine, with no security plugin.
pub fn local_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

/// A client for a secured cluster. Every request sends the user name and
/// password as HTTP Basic authentication.
pub fn secured_client(
  url: String,
  user: String,
  password: String,
) -> Result(Client, OpenSearchError) {
  use parsed <- result.try(
    uri.parse(url)
    |> result.replace_error(InvalidUrl(reason: "the URL cannot be parsed")),
  )
  // Percent-encode both parts, so that `@`, `:` and `/` cannot break the URL
  let userinfo = uri.percent_encode(user) <> ":" <> uri.percent_encode(password)
  client.new(uri.to_string(Uri(..parsed, userinfo: Some(userinfo))))
}
```

A secured cluster wants a user name and password on each request. The client takes them from the base URL. When the URL has a user name, every request sends an `authorization: Basic ...` header, and the user name and password are not sent anywhere else: not in the request line, and not in the `host` header.

A password often holds characters that have a meaning in a URL, such as `@`, `:` or `/`. `secured_client` percent-encodes the user name and the password, and the client decodes them again before it builds the header. For example, each request from `secured_client("https://search.example.com:9200", "admin", "p@ss:w/rd")` sends this header, which is `admin:p@ss:w/rd` in Base64:

### The authorization header <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_authorization.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
authorization: Basic YWRtaW46cEBzczp3L3Jk
```

A few more facts about the base URL:

- Give the scheme and the port, as in `http://localhost:9200` or `https://search.example.com:9200`. With `https`, the client uses TLS. A scheme other than `http` or `https`, a URL with no host, and a URL with a query or a fragment give `Error(InvalidUrl(reason))`.
- `client.new` removes one trailing slash, so `http://localhost:9200/` works too.
- A URL with a user name and no password sends an empty password. A URL with no user name sends no `authorization` header.
- A base URL can have a path, such as `https://proxy.example.com/opensearch`, when a proxy serves the cluster under a prefix. The client puts the API path after it.

In a real program, read the URL, the user name and the password from your configuration or from environment variables, and call `secured_client` with them. Keep the password out of your source code.

## Step 2: Save a document

OpenSearch stores documents, and each document is a JSON object with an ID. Your program has typed values. So the first thing to write is the step from one to the other. This is the start of a `user_store` module:

### Save a user as a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_user_store.gleam#L5-L34"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client, type OpenSearchError, Rejected}
import dream_opensearch/document
import dream_opensearch/query
import gleam/dynamic/decode
import gleam/http
import gleam/io
import gleam/json
import gleam/result
import gleam/string

pub type User {
  User(id: String, name: String, email: String)
}

/// Stores `user` under its ID in `index`. Saving the same ID again
/// replaces the user.
pub fn save_user(
  opensearch: Client,
  index: String,
  user: User,
) -> Result(Nil, OpenSearchError) {
  let body =
    json.object([
      #("name", json.string(user.name)),
      #("email", json.string(user.email)),
    ])
    |> json.to_string
  document.index(opensearch, index, user.id, body)
  |> result.replace(Nil)
}
```

The import list holds what all the steps of this guide need, so you can add the next steps to the same module.

Every function of the module takes the client and the name of the index, so your program and your tests can use different indexes. `save_user(opensearch, "users", User(id: "123", name: "Alice", email: "alice@example.com"))` sends this request:

### The request of save_user <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_save_request.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
PUT /users/_doc/123
{"name":"Alice","email":"alice@example.com"}
```

The ID goes in the path, and it is not part of the document body. `document.index` percent-encodes the index name and the ID, so an ID such as `a/b` or `a#b` stays one ID. OpenSearch answers with status 201 and this body:

### The answer to a new document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_save_response.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"_index":"users","_id":"123","_version":1,"result":"created","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":0,"_primary_term":1}
```

`save_user` does not need any of it, so it returns `Ok(Nil)`. When you save the same ID again, OpenSearch replaces the whole document and answers with status 200, `result` is `"updated"`, and `_version` goes up by one.

With its default settings, OpenSearch creates the `users` index on the first write and guesses a type for each field. For a JSON string it guesses `text`, with a `keyword` sub-field named `name.keyword`. That is fine to start with. When the types matter, for example for exact matches on `email`, create the index yourself with a mapping, as [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md) shows.

## Step 3: Search and read the hits

To find users, send a query with `document.search`, then read the users out of the response. Add this to the same module:

### Find users by name <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_user_store.gleam#L36-L60"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Finds the users whose name matches `name`, best match first.
pub fn find_users_by_name(
  opensearch: Client,
  index: String,
  name: String,
) -> Result(List(User), String) {
  use body <- result.try(
    document.search(opensearch, index, query.match("name", name))
    |> result.map_error(client.describe_error),
  )
  users_from_response(body)
}

/// Reads the users out of the body of a search response.
pub fn users_from_response(body: String) -> Result(List(User), String) {
  json.parse(body, decode.at(["hits", "hits"], decode.list(user_hit())))
  |> result.replace_error("Unexpected search response: " <> body)
}

fn user_hit() -> decode.Decoder(User) {
  use id <- decode.field("_id", decode.string)
  use name <- decode.subfield(["_source", "name"], decode.string)
  use email <- decode.subfield(["_source", "email"], decode.string)
  decode.success(User(id:, name:, email:))
}
```

`query.match("name", "alice")` builds a full-text query. `find_users_by_name(opensearch, "users", "alice")` sends it to the search endpoint of the index:

### The request of find_users_by_name <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_search_request.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
POST /users/_search
{"query":{"match":{"name":"alice"}}}
```

A match query analyzes the text first, so `alice` finds `Alice`. OpenSearch answers with the matching documents under `hits.hits`, best match first:

### The answer to the search <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_search_response.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"took":1,"timed_out":false,"_shards":{"total":1,"successful":1,"skipped":0,"failed":0},"hits":{"total":{"value":1,"relation":"eq"},"max_score":0.18232156,"hits":[{"_index":"users","_id":"123","_score":0.18232156,"_source":{"name":"Alice","email":"alice@example.com"}}]}}
```

`took` and the scores change from run to run. The decoder reads only `_id` and `_source`.

Each hit has the document ID in `_id` and the document you saved in `_source`. `user_hit` reads both and builds a `User`, so the function returns:

### The users that find_users_by_name returns <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_found_users.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok([User(id: "123", name: "Alice", email: "alice@example.com")])
```

`find_users_by_name` returns `Result(List(User), String)`, because two kinds of failure end there: a search that fails, and a body that the decoder cannot read. `client.describe_error` turns the `OpenSearchError` of the search into text, so both kinds are a `String`.

`users_from_response` is public on purpose. It holds all the JSON reading, and it needs no cluster, so you can test it with a saved response body. [Test your code](#test-your-code) does that. When a body does not have the shape the decoder expects, the function says so and keeps the body for your logs, for example `Error("Unexpected search response: {}")`.

There is more to search than one match query: exact values, ranges, several conditions at once, pages and sorting. [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md) covers all of it.

## Step 4: Delete a document

`document.delete` deletes one document by its ID. Often you want a delete that does not fail when the document is already gone, for example when a user deletes their account twice. Add this to the module:

### Delete a user <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_user_store.gleam#L62-L80"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Deletes the user with `id`. A user that is not there is not an error.
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

`delete_user(opensearch, "users", "123")` sends `DELETE /users/_doc/123`. When the document is there, OpenSearch answers with status 200, and the function returns `Ok(Nil)`.

When the document is not there, OpenSearch answers with status 404. The client returns every response with status 400 or more as `Error(Rejected(status, body))`, so `document.delete` returns `Error(Rejected(status: 404, body:))` with this body:

### The answer to a delete of a missing document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_delete_not_found.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"_index":"users","_id":"123","_version":4,"result":"not_found","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":3,"_primary_term":1}
```

This body is from a delete of Alice after she was saved two times and deleted one time, so `_version` and `_seq_no` count those writes. A delete in a new, empty index gets `_version` 1.

`delete_user` matches the `Rejected` error with status 404, and `ignore_not_found` reads `result` from its body. It turns `"not_found"` into `Ok(Nil)`. Every other error stays an error. That matters, because a missing index also answers with status 404, but with an `index_not_found_exception` body and no `result` field. A delete does not create a missing index. A delete from an index that does not exist is a real problem, and `delete_user` returns that error.

## Step 5: Put it in your program

Now use the module from a program. This part also shows one thing that surprises almost everyone: a document you just saved is not in search results yet.

### Save a user and find it right away <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_user_store.gleam#L82-L111"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Makes the documents indexed so far in `index` visible to search.
pub fn refresh(
  opensearch: Client,
  index: String,
) -> Result(Nil, OpenSearchError) {
  client.send_request(opensearch, http.Post, "/" <> index <> "/_refresh", "")
  |> result.replace(Nil)
}

pub fn main() -> Nil {
  client.new("http://localhost:9200")
  |> result.map_error(client.describe_error)
  |> result.try(save_and_find(_, "users"))
  |> string.inspect
  |> io.println
}

/// Saves Alice, makes her visible to search, and finds her by name.
pub fn save_and_find(
  opensearch: Client,
  index: String,
) -> Result(List(User), String) {
  let alice = User(id: "123", name: "Alice", email: "alice@example.com")
  let saved = {
    use Nil <- result.try(save_user(opensearch, index, alice))
    refresh(opensearch, index)
  }
  use Nil <- result.try(result.map_error(saved, client.describe_error))
  find_users_by_name(opensearch, index, "alice")
}
```

OpenSearch makes new documents visible to search at each refresh of the index, and by default an index refreshes about once a second. A search in the same moment as the save misses the new document: in the tests of this guide, `find_users_by_name` right after `save_user` returns `Ok([])`. `refresh` asks for a refresh now. The package has no function for that API, so it uses `client.send_request`, which sends any method, path and body to the cluster, with your base URL and credentials and the header `content-type: application/json`. The `document` functions use it for every request. `client.send_request` sends the path as it is, with no encoding, so use it with index names made of lower-case letters, digits, `-` and `_`.

`save_and_find(opensearch, "users")` sends three requests, in this order:

### The requests of save_and_find <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_save_and_find_requests.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
PUT /users/_doc/123
POST /users/_refresh
POST /users/_search
```

`save_and_find` returns `Ok([User(id: "123", name: "Alice", email: "alice@example.com")])`. Run the program with `gleam run`, and `main` prints that value with `string.inspect`, which leaves out the field names:

### What main prints <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_getting_started_main_output.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok([User("123", "Alice", "alice@example.com")])
```

`main` creates the client once and passes it down. Every function in the module takes the client and the index name as parameters, and nothing reads a global or a hidden setting. That is what makes the module easy to point at another cluster, or at an index of its own in a test.

A refresh costs work on the cluster. Use it in scripts and tests, where you search right after a write. In a production service, let the cluster refresh on its own schedule.

## Which function to use

| Your situation | Use | Why |
|:---|:---|:---|
| Store one document under an ID you choose | `document.index` | Creates the document, or replaces the whole document with that ID |
| Store hundreds or thousands of documents | `document.bulk` | One request for many documents. See [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md) |
| Find documents | `document.search` with a builder from `dream_opensearch/query`, or with your own query JSON | See [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md) |
| Remove one document | `document.delete` | Deletes by ID. A missing document is a 404 |
| Create an index with a mapping, or delete an index | `document.create_index`, `document.delete_index` | See [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md) |
| Any other OpenSearch API: refresh, count, get one document by ID | `client.send_request` | Sends any method, path and body, with your base URL and credentials |

To get one document by its ID, for example, call `client.send_request(opensearch, http.Get, "/users/_doc/123", "")`. The document is under `_source` in the body.

## When something goes wrong

Each `document` function returns `Error(OpenSearchError)`, and the variant tells you what happened. These are the ones you meet first:

| What happened | What you get |
|:---|:---|
| Nothing listens at the address | `Error(Unavailable("Connection failed: Connection refused"))` |
| The base URL has no `http://` or `https://`, as in `localhost:9200` | `client.new` returns `Error(InvalidUrl("the URL scheme must be http or https"))`, and you get no client |
| A secured cluster gets no credentials, or wrong ones | `Error(Rejected(status: 401, body: "Unauthorized"))` |
| The index does not exist | `Error(Rejected(status: 404, body:))`, and the body holds `index_not_found_exception` |

`client.describe_error` turns any of them into one line of text, for a log or for a function that returns `Result(_, String)`, as `find_users_by_name` does. No error contains the user name or the password from the base URL. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) lists every error and shows what to do with each one.

## Test your code

The module from this guide has two kinds of code: code that talks to the cluster, and code that reads JSON. Test them apart:

- **The code that talks to the cluster** needs a real cluster. Start the Docker service from [Before you start](#before-you-start) with `docker compose up -d --wait opensearch`. Give each test its own index name, for example `users_` and a unique number, and delete that index at the end of the test. Then the tests can run at the same time and in any order, and `save_and_find(opensearch, index)` returns `Ok([User(id: "123", name: "Alice", email: "alice@example.com")])` against it.
- **The JSON reading** needs no cluster. Copy a real response body from your cluster into your test, and give it to `users_from_response`.
- **The error path** needs no cluster either. A client for an address where nothing listens gives you a real connection error, so you can test that your code passes it on.

Add the test framework as a dev dependency, with the version range that this package tests with:

### The dev dependency on dream_test <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/gleam.toml#L27-L28"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```toml
[dev-dependencies]
dream_test = ">= 3.0.0 and < 4.0.0"
```

Here is a test module for the two parts that need no cluster. It uses [dream_test](https://hexdocs.pm/dream_test):

### Test the user store with a saved response and a refused connection <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_getting_started_testing.gleam#L6-L48"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_getting_started_user_store.{
  User, find_users_by_name, users_from_response,
}

const search_response =
  "{\"took\":1,\"timed_out\":false,\"_shards\":{\"total\":1,\"successful\":1,\"skipped\":0,\"failed\":0},\"hits\":{\"total\":{\"value\":1,\"relation\":\"eq\"},\"max_score\":0.18232156,\"hits\":[{\"_index\":\"users\",\"_id\":\"123\",\"_score\":0.18232156,\"_source\":{\"name\":\"Alice\",\"email\":\"alice@example.com\"}}]}}"

pub fn tests() -> TestSuite {
  describe("user store", [
    it("reads the users out of a search response", fn() {
      // Act
      let users = users_from_response(search_response)

      // Assert
      users
      |> should
      |> be_equal(
        Ok([User(id: "123", name: "Alice", email: "alice@example.com")]),
      )
      |> or_fail_with("Expected Alice from the saved response")
    }),
    it("returns the connection error when no cluster listens", fn() {
      // Arrange
      // Nothing listens on port 1
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let users = find_users_by_name(opensearch, "users", "alice")

      // Assert
      users
      |> should
      |> be_equal(Error(
        "OpenSearch is unavailable: Connection failed: Connection refused",
      ))
      |> or_fail_with("Expected a refused connection")
    }),
  ])
}
```

The first test uses a response body that OpenSearch 2.19.1 sent for the search of [Step 3](#step-3-search-and-read-the-hits). When you change the query or the mapping, copy a new response from your cluster into the test. That keeps the test true to what your cluster sends.

The second test points the client at port 1 on your own machine, where nothing listens. The connection fails at once, with no timeout and no network, and `find_users_by_name` must return the text of that error.

Some answers are hard to get from a real cluster on demand: a 429 from a busy cluster, or a proxy that closes the connection. To test how your code handles them, you need an HTTP server that you control in the test. [dream_mock_server](https://github.com/TrustBound/dream_mock_server) can answer a path with a status and a body that you choose (`server.start_with_config`). Point `client.new` at it, as you would at a cluster. Because every function in the module takes the client as a parameter, your code needs no change for that.

To run the tests with no cluster at all, record the answers one time. Make the client with `client.from_request` from a `dream_http_client` request that has a recorder, as the doc of `client.from_request` shows. In record mode, the recorder sends each request to the cluster and saves the answer. In playback mode, it returns the saved answer and sends nothing.

## Common pitfalls

**Search does not find a document you just saved.** *Symptom:* a test saves a document, searches at once, and gets no hits, but the same search finds it a second later. *Fix:* OpenSearch makes new documents visible at the next refresh. In tests and scripts, refresh the index before you search, as in [Step 5](#step-5-put-it-in-your-program).

**A base URL with no scheme.** *Symptom:* `client.new` returns `Error(InvalidUrl("the URL scheme must be http or https"))`. *Fix:* write `http://localhost:9200`, not `localhost:9200`.

**A password with `@`, `:`, `/` or `%` in it.** *Symptom:* `Error(Rejected(status: 401, body: "Unauthorized"))` with a password you know is right, or `Error(InvalidUrl("the user name or password has invalid percent-encoding"))` from `client.new`. *Fix:* percent-encode the user name and the password before they go in the URL, as `secured_client` in [Step 1](#step-1-create-a-client) does.

**A document ID you encoded yourself.** *Symptom:* a document saved with the ID `a b` shows up as `a%20b`. *Fix:* pass IDs and index names as they are. The `document` functions percent-encode each index name and ID, so `document.index(opensearch, "users", "a#b", body)` sends `PUT /users/_doc/a%23b`, and OpenSearch stores the ID `a#b`. IDs such as `a/b`, `a?b=1`, `my id` and `café` work the same way. If you encode an ID before you pass it, it is encoded two times, and OpenSearch stores the encoded text as the ID. Index names have rules of their own: OpenSearch refuses upper case, `#` and spaces with `invalid_index_name_exception`. `client.send_request` does not encode its path, so encode a name or an ID yourself before you put it in a path for that function.

**The password in your logs.** *Symptom:* a log line or a crash report holds the password. *Fix:* the client keeps the user name and password in the `authorization` header of its base request, in Base64, so do not print the client, its base request or your base URL. The errors of the package never hold them. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) shows a log line that leaves them out.

**A cluster with a self-signed certificate.** *Symptom:* every request to an `https` URL returns an error that starts with `Connection failed:` and names a TLS failure. *Fix:* the client checks the server certificate against the certificate authorities that your operating system trusts. To trust another one, make the client with `client.from_request` from a `dream_http_client` request with `certificate_authority_file` set to the file of your cluster's certificate authority.

## Where to go next

- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): match, term, range and bool queries, pages and sorting, and reading the hits.
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): load many documents in one request, and find the ones that failed.
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): mappings, settings, and the life of an index.
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md): every error the client returns, and what to do about each one.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/): `client`, `document` and `query`.
