# Managing indexes

OpenSearch creates an index for you on the first write, and it guesses the type of each field. That works until a guess is wrong: an author name split into words so that exact matches fail, a year stored as text so that ranges sort `"999"` after `"2024"`, or a typo in a field name that quietly adds a new field. The fix is to create the index yourself, with a mapping, before any data goes in. This guide creates an index with settings and a mapping, makes the setup safe to run on every start of your program, checks and counts an index, moves data to a new mapping, and deletes what you no longer need.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [Step 1: Create an index with a mapping](#step-1-create-an-index-with-a-mapping)
- [Step 2: Create the index only when it is missing](#step-2-create-the-index-only-when-it-is-missing)
- [Step 3: Check, refresh and count](#step-3-check-refresh-and-count)
- [Step 4: Change a mapping by copying to a new index](#step-4-change-a-mapping-by-copying-to-a-new-index)
- [Step 5: Delete an index](#step-5-delete-an-index)
- [Which function to use](#which-function-to-use)
- [When index operations fail](#when-index-operations-fail)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- Create a `books` index with one shard, one replica and a strict mapping.
- Run the setup on every start of your program, and accept an index that already exists.
- Find out whether an index exists, make new documents visible, and count the documents.
- Copy all documents into a new index with another mapping.
- Delete an index, and accept one that is already gone.
- Test the setup code against a real cluster in Docker, and with no cluster.

## Before you start

Add the package, and `gleam_json` to build the bodies and read the responses:

```sh
gleam add dream_opensearch gleam_json
```

The user that your client sends needs the rights to create and delete indexes. On a cluster with the security plugin, that is a role with index management rights, which your normal application user might not have. Many teams run the index setup with a separate user.

Every example in this guide is tested against OpenSearch 2.19.1 in Docker. [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) shows the Docker service, and `docker compose up -d --wait opensearch` starts it. The tests of rights and passwords use a second node with the security plugin on. The responses you see here are bodies that the cluster really sent. `took` and the index UUID in an error change from run to run.

## Step 1: Create an index with a mapping

The request that creates an index takes a body with two parts: `settings`, which set up the index, and `mappings`, which set the type of each field. Build both with `gleam/json`. This is the start of a `books_index` module:

### Create the books index with settings and a mapping <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_create.gleam#L6-L53"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/json
import gleam/result

/// The settings and the mapping of an index for books.
pub fn books_index_body() -> String {
  json.object([
    #(
      "settings",
      json.object([
        #("number_of_shards", json.int(1)),
        #("number_of_replicas", json.int(1)),
      ]),
    ),
    #(
      "mappings",
      json.object([
        // Refuse documents with fields that the mapping does not name
        #("dynamic", json.string("strict")),
        #(
          "properties",
          json.object([
            #("title", field_type("text")),
            #("author", field_type("keyword")),
            #("year", field_type("integer")),
            #("in_stock", field_type("boolean")),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn field_type(name: String) -> json.Json {
  json.object([#("type", json.string(name))])
}

/// Creates the index `index_name` for books.
pub fn create_books_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  document.create_index(opensearch, index_name, books_index_body())
  |> result.replace(Nil)
}
```

`books_index_body()` returns this body:

```text
{"settings":{"number_of_shards":1,"number_of_replicas":1},"mappings":{"dynamic":"strict","properties":{"title":{"type":"text"},"author":{"type":"keyword"},"year":{"type":"integer"},"in_stock":{"type":"boolean"}}}}
```

`create_books_index(opensearch, "books")` sends it with `document.create_index`, as `PUT /books`. OpenSearch answers with status 200:

```text
{"acknowledged":true,"shards_acknowledged":true,"index":"books"}
```

What each part does:

- `number_of_shards` splits the index into parts that can live on different nodes. One shard is right for an index of a few gigabytes or less. You cannot change it later without a copy to a new index.
- `number_of_replicas` keeps copies of each shard on other nodes. You can change it at any time. On a cluster with one node, a replica has nowhere to go, and the cluster health shows yellow. That is fine for development.
- `"dynamic": "strict"` makes OpenSearch refuse a document with a field that the mapping does not name. Without it, a typo such as `auhtor` adds a new field, and your searches on `author` miss that document.
- `text` fields are analyzed for full-text search, `keyword` fields hold exact values for `term` queries, sorting and counts, and `integer` and `boolean` are what they say. [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md) shows how each type changes a query.

The index name goes in the URL path, and `document.create_index` percent-encodes it, so the whole name reaches OpenSearch. OpenSearch wants index names in lower case, with no spaces and none of the characters `\`, `/`, `*`, `?`, `"`, `<`, `>`, `|`, `,` and `#`. It refuses other names with status 400 and `invalid_index_name_exception`, for example `Invalid index name [a#b], must not contain '#'`.

## Step 2: Create the index only when it is missing

You want the index to exist before your program writes to it, so the natural place for `create_books_index` is the start of the program. But the second start fails: the index is already there. OpenSearch answers with status 400:

```text
{"error":{"root_cause":[{"type":"resource_already_exists_exception","reason":"index [books/szRdA72vTjirBMobGJfr3g] already exists","index":"books","index_uuid":"szRdA72vTjirBMobGJfr3g"}],"type":"resource_already_exists_exception","reason":"index [books/szRdA72vTjirBMobGJfr3g] already exists","index":"books","index_uuid":"szRdA72vTjirBMobGJfr3g"},"status":400}
```

Accept that one error, and keep all others. Add this to the module:

### Create the books index unless it exists <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_create.gleam#L55-L69"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Creates the index `index_name` for books, unless it already exists.
pub fn ensure_books_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  create_books_index(opensearch, index_name)
  |> result.try_recover(accept_existing)
}

fn accept_existing(body: String) -> Result(Nil, String) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("resource_already_exists_exception") -> Ok(Nil)
    _ -> Error(body)
  }
}
```

`ensure_books_index(opensearch, "books")` returns `Ok(Nil)` when it creates the index, and `Ok(Nil)` when the index already exists. Any other error stays an error. For example, a name in upper case gets status 400 with `invalid_index_name_exception`, and `ensure_books_index(opensearch, "Books")` returns that body as the error:

```text
{"error":{"root_cause":[{"type":"invalid_index_name_exception","reason":"Invalid index name [Books], must be lowercase","index":"Books","index_uuid":"_na_"}],"type":"invalid_index_name_exception","reason":"Invalid index name [Books], must be lowercase","index":"Books","index_uuid":"_na_"},"status":400}
```

It reads the error type from the body, not the status. Status 400 also means a bad mapping or a bad name, and those must not pass as "already exists".

Why not check first, and create only when the index is missing? Because two copies of your program can start at the same time. Both check, both see no index, and one of the two creates fails anyway. Create and accept "already exists" is safe in that case too.

`ensure_books_index` does not compare the mapping of an existing index with yours. If you change `books_index_body`, an existing index keeps its old mapping. Step 4 shows how to move to a new one.

## Step 3: Check, refresh and count

The `document` module covers creating and deleting an index. For the other index APIs, use `client.send_request`, which sends any method, path and body to the cluster with your base URL and credentials. This is a second module, `index_tools`, with three of them:

### Check, refresh and count an index <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_maintain.gleam#L6-L58"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result

/// Tells whether the index `index_name` exists.
pub fn index_exists(
  opensearch: Client,
  index_name: String,
) -> Result(Bool, String) {
  case client.send_request(opensearch, http.Get, "/" <> index_name, "") {
    Ok(_) -> Ok(True)
    Error(body) -> accept_not_found(body)
  }
}

fn accept_not_found(body: String) -> Result(Bool, String) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("index_not_found_exception") -> Ok(False)
    _ -> Error(body)
  }
}

/// Makes the documents indexed so far visible to search.
pub fn refresh_index(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  client.send_request(
    opensearch,
    http.Post,
    "/" <> index_name <> "/_refresh",
    "",
  )
  |> result.replace(Nil)
}

/// Counts the documents in the index `index_name`.
pub fn count_documents(
  opensearch: Client,
  index_name: String,
) -> Result(Int, String) {
  use body <- result.try(client.send_request(
    opensearch,
    http.Get,
    "/" <> index_name <> "/_count",
    "",
  ))
  json.parse(body, decode.at(["count"], decode.int))
  |> result.replace_error("Unexpected count response: " <> body)
}
```

Here is what each function sends, and what it returns:

| Function | Request | Returns |
|:---|:---|:---|
| `index_exists(opensearch, "books")` | `GET /books` | `Ok(True)` for status 200, `Ok(False)` for a 404 with `index_not_found_exception` |
| `refresh_index(opensearch, "books")` | `POST /books/_refresh` | `Ok(Nil)` |
| `count_documents(opensearch, "books")` | `GET /books/_count` | `Ok(2)` for the body `{"count":2,"_shards":{"total":1,"successful":1,"skipped":0,"failed":0}}` |

`index_exists` sends a GET for the index, and reads the error type of a 404, as `ensure_books_index` does. Why not a HEAD request, which gets only a status? Because a HEAD answer has no body, so every error status comes back as `Error("")`, an empty string. A HEAD for a missing index gives `Error("")`, and so does a HEAD with a wrong password on a secured cluster: the 401 has no body either. With a GET, a wrong password stays `Error("Unauthorized")`, and a refused connection stays `Error("Connection failed: Connection refused")`. A missing index is not the same as a cluster you cannot reach, and your program must not treat them the same.

`refresh_index` makes the documents indexed so far visible to search. By default OpenSearch refreshes each index about once a second, so you need this only when you search right after a write, as in tests and scripts.

`count_documents` reads the `count` field. Count after a refresh, or the count can miss the newest documents. When the body has no `count`, it returns `Error("Unexpected count response: <the body>")`.

## Step 4: Change a mapping by copying to a new index

You cannot change the type of a field in an existing index. To change a mapping, create a new index with the new mapping, and copy the documents into it with the reindex API. Add this to `index_tools`:

### Copy every document into another index <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_maintain.gleam#L60-L81"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Copies every document of `source` into `destination`. Returns how many
/// documents OpenSearch created.
pub fn copy_index(
  opensearch: Client,
  source: String,
  destination: String,
) -> Result(Int, String) {
  let body =
    json.object([
      #("source", json.object([#("index", json.string(source))])),
      #("dest", json.object([#("index", json.string(destination))])),
    ])
    |> json.to_string
  use response <- result.try(client.send_request(
    opensearch,
    http.Post,
    "/_reindex",
    body,
  ))
  json.parse(response, decode.at(["created"], decode.int))
  |> result.replace_error("Unexpected reindex response: " <> response)
}
```

`copy_index(opensearch, "books_v1", "books_v2")` sends:

```text
POST /_reindex
{"source":{"index":"books_v1"},"dest":{"index":"books_v2"}}
```

OpenSearch copies the documents and answers when it is done:

```text
{"took":59,"timed_out":false,"total":2,"updated":0,"created":2,"deleted":0,"batches":1,"version_conflicts":0,"noops":0,"retries":{"bulk":0,"search":0},"throttled_millis":0,"requests_per_second":-1.0,"throttled_until_millis":0,"failures":[]}
```

This body is from a copy of an index with two books, so the function returns `Ok(2)`. The whole move is four calls:

1. `create_books_index(opensearch, "books_v2")`, with the new mapping in `books_index_body`.
2. `copy_index(opensearch, "books_v1", "books_v2")`.
3. Point your program at `books_v2`.
4. `delete_index_if_present(opensearch, "books_v1")`, from Step 5, when you are sure.

The reindex request waits until the copy is done, and a large index takes a long time. The client waits 30 seconds for an answer (the default of `dream_http_client`), so a copy that takes longer returns `Error("Timed out after 30000ms")`, while OpenSearch goes on with the copy. A copy from an index that does not exist gets status 404 with `index_not_found_exception`. Count the documents of the new index to see when it is done. To switch your program from one index to another with no change to your code, put an alias in front of the indexes, with `client.send_request` and the `_aliases` API.

## Step 5: Delete an index

`document.delete_index` deletes an index and every document in it, at once, with no way to undo it. A clean-up script usually wants to accept an index that is already gone. Add this to `index_tools`:

### Delete an index if it is there <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_maintain.gleam#L83-L99"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Deletes the index `index_name`. An index that is not there is not an
/// error.
pub fn delete_index_if_present(
  opensearch: Client,
  index_name: String,
) -> Result(Nil, String) {
  document.delete_index(opensearch, index_name)
  |> result.replace(Nil)
  |> result.try_recover(accept_missing)
}

fn accept_missing(body: String) -> Result(Nil, String) {
  case json.parse(body, decode.at(["error", "type"], decode.string)) {
    Ok("index_not_found_exception") -> Ok(Nil)
    _ -> Error(body)
  }
}
```

`delete_index_if_present(opensearch, "books_v1")` sends `DELETE /books_v1`, and OpenSearch answers `{"acknowledged":true}`. For an index that does not exist, OpenSearch answers with status 404 and an `index_not_found_exception` body, and the function returns `Ok(Nil)`. Every other error stays an error. On a secured cluster, a user without the right to delete gets status 403 and a `security_exception` body, such as `no permissions for [indices:admin/delete] and User [name=probe_reader, backend_roles=[], requestedTenant=null]`.

To delete one document instead of the whole index, use `document.delete`, which [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#step-4-delete-a-document) shows.

## Which function to use

| Your situation | Use | Why |
|:---|:---|:---|
| Create an index with settings and a mapping | `document.create_index` | `PUT /<index>` with your body. Fails if the index exists |
| Create it on every start of a program | `document.create_index`, and accept `resource_already_exists_exception` | Safe when two copies start at once |
| Delete an index and all of its documents | `document.delete_index` | `DELETE /<index>`. Cannot be undone |
| Find out whether an index exists | `client.send_request` with `http.Head` | Status 200 or 404, no body |
| Make new documents visible now | `client.send_request` with `/<index>/_refresh` | For tests and scripts |
| Count, copy, read the mapping, set aliases | `client.send_request` with the API path | The `document` module does not cover these APIs |

## When index operations fail

Every function returns `Error(String)`. For an answer from OpenSearch, the string is the response body, and the error type in it tells you what went wrong:

| What happened | Status | Error type in the body |
|:---|:---|:---|
| Create an index that exists | 400 | `resource_already_exists_exception` |
| Create an index with a name in upper case | 400 | `invalid_index_name_exception` |
| Delete or search an index that does not exist | 404 | `index_not_found_exception` |
| No credentials, or wrong ones, on a secured cluster | 401 | None: the body is the plain text `Unauthorized` |
| A user without the needed rights | 403 | `security_exception` |
| Change the type of a mapped field | 400 | `illegal_argument_exception` |
| A field that a strict mapping does not name | 400 | `strict_dynamic_mapping_exception` |
| HEAD for a missing index, or with a wrong password | 404 or 401 | No body: the error is `""` |

The error type is at `error.type` in the JSON. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) shows how to read it into a typed error for all of your code, not only for index setup.

## Test your code

Test the setup code against a real cluster: start the Docker service from [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) with `docker compose up -d --wait opensearch`. Then `ensure_books_index` called two times returns `Ok(Nil)` two times, and `index_exists` returns `Ok(True)`.

The setup code also has a part you can test as a plain value, the index body, and a part you can test with no cluster:

- **The body.** Parse the string that `books_index_body` returns, and assert the field types that your searches depend on. A test like that fails when someone changes `author` to `text` and breaks every `term` query on it.
- **The error path.** A client for an address where nothing listens gives a real connection error, and `ensure_books_index` must pass it on, not read it as "already exists".

Add `dream_test` as a dev dependency, from GitHub, with the commit that this package tests with:

```toml
[dev-dependencies]
dream_test = { git = "https://github.com/TrustBound/dream_test.git", ref = "1639959578a14ae3577f8e3ae5cac058f933aa53" }
```

Here is a test module for both:

### Test the index body and the setup error path <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_managing_indexes_testing.gleam#L6-L46"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/dynamic/decode
import gleam/json
import snippets/guide_managing_indexes_create.{
  books_index_body, ensure_books_index,
}

pub fn tests() -> TestSuite {
  describe("books index", [
    it("maps the author as a keyword", fn() {
      // Arrange
      let author_type =
        decode.at(["mappings", "properties", "author", "type"], decode.string)

      // Act
      let mapped = json.parse(books_index_body(), author_type)

      // Assert
      mapped
      |> should
      |> be_equal(Ok("keyword"))
      |> or_fail_with("term queries on author need a keyword field")
    }),
    it("returns the connection error when no cluster listens", fn() {
      // Arrange
      let opensearch = client.new("http://127.0.0.1:1")

      // Act
      let created = ensure_books_index(opensearch, "books")

      // Assert
      created
      |> should
      |> be_equal(Error("Connection failed: Connection refused"))
      |> or_fail_with("Expected a refused connection")
    }),
  ])
}
```

To run your setup against a real cluster in a test, give each test run its own index name, for example with a random suffix, and delete the index at the end with `delete_index_if_present`. Then tests that run at the same time do not share an index.

## Common pitfalls

**Changing the mapping of an existing index.** *Symptom:* you change a field type in `books_index_body`, but searches act as before. Or a `PUT /books/_mapping` with the new type fails with `illegal_argument_exception`. *Fix:* the type of an existing field cannot change. Create a new index and copy the data, as in [Step 4](#step-4-change-a-mapping-by-copying-to-a-new-index). You can add new fields to a mapping, but not change the old ones.

**Writing before the index exists.** *Symptom:* searches on `author` with `term` find nothing, and `count_documents` says the documents are there. *Fix:* the first write created the index with guessed types, and `author` became a `text` field. Create the index with your mapping before the first write, with `ensure_books_index` at the start of your program.

**A missing index read as a cluster problem, or the other way around.** *Symptom:* your program creates an index when the cluster is down, or reports a cluster failure for a missing index. *Fix:* tell the cases apart. A HEAD for a missing index gives `Error("")`. A connection failure gives a message that starts with `Connection failed:`.

**Index names in upper case.** *Symptom:* `invalid_index_name_exception`. *Fix:* use lower case. Avoid spaces and the characters `#`, `?`, `/` and `*` too. The `document` functions percent-encode the name, so OpenSearch gets the whole name and names the problem in the error. `client.send_request` does not encode its path, so the functions of Step 3 need names that need no encoding.

**Deleting with a wildcard.** *Symptom:* `delete_index(opensearch, "books*")` deletes every index whose name starts with `books`. The client sends the `*` percent-encoded, but OpenSearch decodes it and reads a wildcard. With the default settings of OpenSearch 2.19.1, the delete works. *Fix:* delete indexes by their full name, one at a time.

**A replica on a single node.** *Symptom:* the cluster health is yellow on your development machine. *Fix:* a replica cannot live on the same node as its shard. That is harmless in development. Set `number_of_replicas` to 0 there if the yellow status bothers you.

## Where to go next

- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): fill the new index with many documents in one request.
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): how the field types of the mapping change a query.
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md): read the error type of any OpenSearch error into a typed value.
- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): connect, save, find and delete one document.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/dream_opensearch/document.html): `create_index`, `delete_index` and `client.send_request`.
