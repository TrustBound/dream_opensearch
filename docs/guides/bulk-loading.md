# Loading documents in bulk

You have a few thousand records to put in OpenSearch: an import from a file, a nightly sync from your database, or a fresh index to fill. One request for each document is slow. The bulk API takes many documents in one request. But it has a catch that bites almost everyone the first time: a bulk request that comes back `Ok` can still hold documents that failed. This guide loads a list of books with the bulk API, finds the books that failed and why, loads in batches, and retries the ones that can pass on a second try.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [Step 1: Build the bulk body](#step-1-build-the-bulk-body)
- [Step 2: Send it](#step-2-send-it)
- [Step 3: Find the documents that failed](#step-3-find-the-documents-that-failed)
- [Step 4: Load in batches](#step-4-load-in-batches)
- [Step 5: Retry the rejected documents](#step-5-retry-the-rejected-documents)
- [Which action to use](#which-action-to-use)
- [When the whole request fails](#when-the-whole-request-fails)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- Turn a list of `Book` values into a bulk request body.
- Send it in one request.
- Get back the list of books that failed, each with its status and the reason OpenSearch gave.
- Load a long list in batches of a size you choose.
- Load the rejected books once more, and keep the ones that cannot pass.
- Test the loader against a real cluster in Docker, and the body and the response reading with no cluster.

## Before you start

Add the package, and `gleam_json` to build the body and read the response:

```sh
gleam add dream_opensearch gleam_json
```

The examples load books into an index named `books`, with a `title`, an `author` and a `year` for each book. Each function takes the index name, so a test can load into an index of its own. [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md) creates that index with a strict mapping, where `year` is an `integer`. If the index does not exist, OpenSearch creates it with its default settings on the first write.

Every example in this guide is tested against OpenSearch 2.19.1 in Docker. [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) shows the Docker service, and `docker compose up -d --wait opensearch` starts it. The responses you see here are bodies that the cluster really sent. `took`, `_seq_no` and `_version` change from run to run.

## Step 1: Build the bulk body

A bulk body is NDJSON: newline-delimited JSON. Each line is one complete JSON object, and each line ends with a newline. For each document there are two lines:

1. An action line, which says what to do and where: `{"index":{"_index":"books","_id":"1"}}`.
2. The document itself.

Build the body from your values, never by hand. This is the start of a `book_loader` module:

### Build the bulk body for a list of books <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_books.gleam#L6-L50"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Book {
  Book(id: String, title: String, author: String, year: Int)
}

pub type FailedItem {
  FailedItem(id: String, status: Int, error_type: String, reason: String)
}

/// Builds the bulk body: an action line and a document line for each book,
/// each line ended by a newline.
pub fn bulk_body(index: String, books: List(Book)) -> String {
  books
  |> list.flat_map(book_lines(index, _))
  |> list.map(fn(line) { json.to_string(line) <> "\n" })
  |> string.concat
}

fn book_lines(index: String, book: Book) -> List(json.Json) {
  let action =
    json.object([
      #(
        "index",
        json.object([
          #("_index", json.string(index)),
          #("_id", json.string(book.id)),
        ]),
      ),
    ])
  let source =
    json.object([
      #("title", json.string(book.title)),
      #("author", json.string(book.author)),
      #("year", json.int(book.year)),
    ])
  [action, source]
}
```

The import list holds what all the steps of this guide need, so you can add the next steps to the same module.

`json.to_string` writes each object on one line, with no line breaks inside it, which is what NDJSON needs. `bulk_body` puts a newline after every line, the last one too. For the index `books` and two books it returns:

### The bulk body of two books <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_bulk_body.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"index":{"_index":"books","_id":"1"}}
{"title":"Programming Gleam","author":"Jo Lee","year":2024}
{"index":{"_index":"books","_id":"2"}}
{"title":"Gleam for Erlang Developers","author":"Sam Park","year":2022}
```

The action line names the index, so one bulk request can write to several indexes. It also names the document ID, so loading the same list twice replaces the documents instead of making copies.

## Step 2: Send it

`document.bulk` sends the body to `POST /_bulk`. Add this to the module:

### Load a list of books in one request <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_books.gleam#L52-L63"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Loads `books` in one bulk request. Returns the books that failed.
pub fn load_books(
  opensearch: Client,
  index: String,
  books: List(Book),
) -> Result(List(FailedItem), String) {
  use body <- result.try(
    document.bulk(opensearch, bulk_body(index, books))
    |> result.map_error(client.describe_error),
  )
  failed_items(body)
}
```

`load_books(opensearch, "books", books)` sends the body of Step 1. When every document is stored, OpenSearch answers with status 200 and one item for each document, in the order of the body:

### The answer when every book is stored <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_all_stored.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"took":4,"errors":false,"items":[{"index":{"_index":"books","_id":"1","_version":1,"result":"created","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":0,"_primary_term":1,"status":201}},{"index":{"_index":"books","_id":"2","_version":1,"result":"created","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":1,"_primary_term":1,"status":201}}]}
```

`errors` is `false`, and each item has a status of 201 (created) or 200 (replaced). For this response, `load_books` returns `Ok([])`: no book failed.

## Step 3: Find the documents that failed

Here is the catch. When some documents fail and others succeed, OpenSearch still answers the bulk request with status 200. So `document.bulk` returns `Ok`, and the failures are inside the body. This response is for three books in the `books` index with the strict mapping. Books 1 and 2 were stored. Book 3 has a `year` of 3000000000, which does not fit an `integer`:

### The answer when one book fails <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_one_failed.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"took":3,"errors":true,"items":[{"index":{"_index":"books","_id":"1","_version":1,"result":"created","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":0,"_primary_term":1,"status":201}},{"index":{"_index":"books","_id":"2","_version":1,"result":"created","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":1,"_primary_term":1,"status":201}},{"index":{"_index":"books","_id":"3","status":400,"error":{"type":"mapper_parsing_exception","reason":"failed to parse field [year] of type [integer] in document with id '3'. Preview of field's value: '3000000000'","caused_by":{"type":"input_coercion_exception","reason":"Numeric value (3000000000) out of range of int (-2147483648 - 2147483647)\n at [Source: REDACTED (`StreamReadFeature.INCLUDE_SOURCE_IN_LOCATION` disabled); line: 1, column: 70]"}}}}]}
```

`errors` is `true`, and the failed items have an `error` object. Add this reader to the module. `load_books` from Step 2 already calls it:

### Read the failed items from a bulk response <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_books.gleam#L65-L101"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Reads the failed items out of the body of a bulk response.
pub fn failed_items(body: String) -> Result(List(FailedItem), String) {
  json.parse(body, decode.at(["items"], decode.list(item_decoder())))
  |> result.map(option.values)
  |> result.replace_error("Unexpected bulk response: " <> body)
}

// Each item has one key: the action of its line in the request
fn item_decoder() -> decode.Decoder(Option(FailedItem)) {
  decode.one_of(decode.at(["index"], outcome_decoder()), [
    decode.at(["create"], outcome_decoder()),
    decode.at(["update"], outcome_decoder()),
    decode.at(["delete"], outcome_decoder()),
  ])
}

fn outcome_decoder() -> decode.Decoder(Option(FailedItem)) {
  use id <- decode.field("_id", decode.string)
  use status <- decode.field("status", decode.int)
  use error <- decode.optional_field(
    "error",
    None,
    decode.map(error_decoder(), Some),
  )
  decode.success(
    option.map(error, fn(error) {
      let #(error_type, reason) = error
      FailedItem(id:, status:, error_type:, reason:)
    }),
  )
}

fn error_decoder() -> decode.Decoder(#(String, String)) {
  use error_type <- decode.field("type", decode.string)
  use reason <- decode.field("reason", decode.string)
  decode.success(#(error_type, reason))
}
```

`failed_items` reads every item, keeps the ones with an `error`, and drops the rest. It ignores the fields it does not need, such as `caused_by`. For the response above, `load_books` returns:

### The failed items that load_books returns <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_failed_items.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok([FailedItem(id: "3", status: 400, error_type: "mapper_parsing_exception", reason: "failed to parse field [year] of type [integer] in document with id '3'. Preview of field's value: '3000000000'")])
```

A failed item can mean two very different things:

- Status 400, as for book 3: the document does not fit the mapping. It fails the same way every time, until the data changes. A document with a field that a strict mapping does not name fails the same way, with `strict_dynamic_mapping_exception`.
- Status 429, with `es_rejected_execution_exception`: the cluster was too busy to take the document. The same document can pass a moment later. A cluster sends it only under heavy load, so the tests of this guide cannot make one happen on demand.

Each item has one key, and the key is the action of its line in the request. `item_decoder` reads `index`, `create`, `update` and `delete` items, so the reader also works for bulk bodies with other actions.

Always read the items. Do not stop at `Ok`, and do not trust `errors` alone either: the items tell you which documents failed, and that is what you need to act on.

## Step 4: Load in batches

One huge bulk request is slow to build, heavy on memory, and can hit the request size limit of the cluster. Send the list in batches instead. Add this to the module:

### Load books in batches <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_books.gleam#L103-L117"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Loads `books` with one bulk request for each `batch_size` books. Stops at
/// the first request that fails as a whole.
pub fn load_in_batches(
  opensearch: Client,
  index: String,
  books: List(Book),
  batch_size: Int,
) -> Result(List(FailedItem), String) {
  books
  |> list.sized_chunk(batch_size)
  |> list.try_fold([], fn(failed, batch) {
    use batch_failed <- result.map(load_books(opensearch, index, batch))
    list.append(failed, batch_failed)
  })
}
```

`list.sized_chunk` cuts the list into batches of `batch_size` books, and the last batch holds the rest. `list.try_fold` sends the batches one after another and collects the failed items of all of them. `load_in_batches(opensearch, "books", books, 2)` with the three books of Step 3 sends two requests: the first with books 1 and 2, the second with book 3. It returns the failed item of book 3, as `load_books` did.

When a whole request fails, `try_fold` stops and returns that error. For example, a cluster refuses a request body that is larger than its limit (`http.max_content_length`, 100 MB by default) with status 413 and no body, so `load_in_batches` returns `Error("OpenSearch rejected the request with status 413: ")`. The batches before it are already stored. Since every action line has an ID, you can load the whole list again: the stored books are replaced with the same data.

A good batch size depends on the size of your documents. Start with about 5 to 15 MB of body for each request, or a few thousand small documents, and measure.

## Step 5: Retry the rejected documents

A status 429 means "too many requests". The cluster rejected the document because its queues were full, not because the document is wrong. Those documents are worth one more try. Add this to the module:

### Retry the books that the cluster rejected <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_books.gleam#L119-L137"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// Loads once more the books that OpenSearch rejected with status 429
/// (too many requests). Returns the books that still failed.
pub fn retry_rejected(
  opensearch: Client,
  index: String,
  books: List(Book),
  failed: List(FailedItem),
) -> Result(List(FailedItem), String) {
  let #(rejected, permanent) =
    list.partition(failed, fn(item) { item.status == 429 })
  let rejected_ids = list.map(rejected, fn(item) { item.id })
  case list.filter(books, fn(book) { list.contains(rejected_ids, book.id) }) {
    [] -> Ok(permanent)
    retry -> {
      use still_failed <- result.map(load_books(opensearch, index, retry))
      list.append(permanent, still_failed)
    }
  }
}
```

`retry_rejected` splits the failures into the 429s and the rest. It loads the rejected books once more, and returns the failures that are left: the permanent ones, and any books that the cluster rejected again. When there is nothing to retry, it sends no request.

Say a busy cluster also rejected book 2 of Step 3, so `failed` holds a 429 item for book 2 and the 400 item for book 3. Then `retry_rejected(opensearch, "books", books, failed)` sends a bulk request with only book 2. When that one is stored, the function returns:

### The failures left after the retry <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_retry_result.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok([FailedItem(id: "3", status: 400, error_type: "mapper_parsing_exception", reason: "failed to parse field [year] of type [integer] in document with id '3'. Preview of field's value: '3000000000'")])
```

What is left is a list of documents to log or to fix. In a real program, wait a little before the retry, so that the cluster can catch up.

## Which action to use

The action line decides what OpenSearch does with each document. This guide uses `index`. The other actions use the same two-line form, except `delete`, which has no document line.

| Your situation | Action | What a failure looks like |
|:---|:---|:---|
| Store the document, and replace it if the ID exists | `index` | Only real problems, such as a field that does not fit the mapping |
| Store the document only if the ID is new | `create` | Status 409, `version_conflict_engine_exception`, when the ID exists |
| Change some fields of a stored document | `update`, with `{"doc":{...}}` as the second line | Status 404, `document_missing_exception`, when the ID does not exist |
| Remove a document | `delete`, with no second line | No error object when the ID does not exist: status 404, with `result` set to `not_found` |

And for each kind of failed item, what to do:

| Status of the item | Meaning | What to do |
|:---|:---|:---|
| 429 | The cluster was too busy | Retry it after a short wait, as in Step 5 |
| 400 | The document does not fit the mapping, or the line is wrong | Fix the data or the mapping. A retry fails again |
| 409 | A `create` for an ID that exists | Usually fine to skip. Use `index` if you meant to replace |
| 404 | An `update` of a document that does not exist | Send it as `index` instead, if the full document is at hand |

## When the whole request fails

Some problems fail the whole request, not single items. Then OpenSearch answers with status 400 or more, and `document.bulk` returns `Error(Rejected(status, body))`. `load_books` turns that error into text with `client.describe_error`. Nothing in that request is stored.

The most common one is a body that does not end with a newline. `bulk_body` always ends with one, but a body you build by hand might not. OpenSearch answers with status 400 and this body:

### The answer to a body with no final newline <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/outputs/guide_bulk_loading_no_final_newline.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"error":{"root_cause":[{"type":"illegal_argument_exception","reason":"The bulk request must be terminated by a newline [\\n]"}],"type":"illegal_argument_exception","reason":"The bulk request must be terminated by a newline [\\n]"},"status":400}
```

A body over the size limit of the cluster gets status 413 with no body, so the error is `Rejected(status: 413, body: "")`. A cluster that cannot take writes at all answers with status 503, and a refused connection gives `Unavailable("Connection failed: Connection refused")`. In both cases, nothing in that request is stored, and the earlier batches of `load_in_batches` stay stored. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) shows how to tell these errors apart in code, and which ones are worth a retry.

## Test your code

Test the loading against a real cluster: start the Docker service from [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) with `docker compose up -d --wait opensearch`, give each test an index of its own, load, refresh, count, and delete the index at the end. A document that does not fit the mapping, such as a `year` of 3000000000, gives you a real failed item.

The two parts of the loader that are easy to get wrong are the body and the reading of the response, and neither needs a cluster:

- **The body.** Assert the exact string `bulk_body` returns. That catches a missing newline or a wrong action line.
- **The failed items.** Give `failed_items` a response with a failure in it. Partial failures are rare on a quiet development cluster, so this test is often the only place your failure handling runs before production.

Add `dream_test` as a dev dependency, with the version range that this package tests with:

### The dev dependency on dream_test <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/gleam.toml#L27-L28"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```toml
[dev-dependencies]
dream_test = ">= 3.0.0 and < 4.0.0"
```

Here is a test module for both parts:

### Test the bulk body and the failed items <a href="https://github.com/TrustBound/dream_opensearch/blob/4.0.0/test/snippets/guide_bulk_loading_testing.gleam#L5-L48"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_bulk_loading_books.{
  Book, FailedItem, bulk_body, failed_items,
}

pub fn tests() -> TestSuite {
  describe("book loading", [
    it("ends every line of the bulk body with a newline", fn() {
      // Act
      let body =
        bulk_body("books", [Book("1", "Programming Gleam", "Jo Lee", 2024)])

      // Assert
      body
      |> should
      |> be_equal(
        "{\"index\":{\"_index\":\"books\",\"_id\":\"1\"}}\n"
        <> "{\"title\":\"Programming Gleam\",\"author\":\"Jo Lee\",\"year\":2024}\n",
      )
      |> or_fail_with("Expected an action line and a document line")
    }),
    it("finds the item that failed", fn() {
      // Arrange
      let response =
        "{\"took\":4,\"errors\":true,\"items\":["
        <> "{\"index\":{\"_id\":\"1\",\"status\":201}},"
        <> "{\"index\":{\"_id\":\"2\",\"status\":429,\"error\":"
        <> "{\"type\":\"es_rejected_execution_exception\",\"reason\":\"busy\"}}}]}"

      // Act
      let failed = failed_items(response)

      // Assert
      failed
      |> should
      |> be_equal(
        Ok([FailedItem("2", 429, "es_rejected_execution_exception", "busy")]),
      )
      |> or_fail_with("Only book 2 failed")
    }),
  ])
}
```

The response in the second test is shorter than a real one, and it holds a 429 item, which a quiet cluster does not send. The reader only needs `_id`, `status` and `error`, so a short body keeps the test easy to read. Use a full response from your cluster when you want to be sure of the real shape, as the 400 response of Step 3.

## Common pitfalls

**Treating `Ok` as success.** *Symptom:* the import reports success, but some documents are not in the index. *Fix:* a bulk request with failed items still returns `Ok`. Read the items, as `failed_items` in [Step 3](#step-3-find-the-documents-that-failed) does.

**No newline after the last line.** *Symptom:* `Error` with `The bulk request must be terminated by a newline [\\n]`. *Fix:* end every line with `\n`, the last one too.

**A JSON document over several lines.** *Symptom:* the whole request fails with status 400 and `illegal_argument_exception`, for example `Malformed action/metadata line [3], expected START_OBJECT but found [VALUE_STRING]`. *Fix:* each document must be on one line. `json.to_string` writes one line. A JSON string from a file or another tool can hold line breaks, so parse it and write it again with `json.to_string`.

**An empty body.** *Symptom:* `Error` with a `parse_exception` body, `request body is required`, when the list of books is empty. *Fix:* `bulk_body([])` is an empty string, and OpenSearch refuses a bulk request with no actions. Do not send a request for an empty list.

**Documents not in search results yet.** *Symptom:* a search right after the load finds fewer documents than you loaded. *Fix:* OpenSearch makes new documents visible at the next refresh. In tests and scripts, refresh the index after the load with `client.send_request(opensearch, http.Post, "/books/_refresh", "")`.

**One request for everything.** *Symptom:* a load of a large file fails with `Error("OpenSearch rejected the request with status 413: ")` (status 413, with no body), or runs out of memory. *Fix:* load in batches, as in [Step 4](#step-4-load-in-batches).

## Where to go next

- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): create the `books` index with a mapping before you load it.
- [Searching an index](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): find the books you loaded.
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md): which errors of a whole request are worth a retry.
- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): connect, save, find and delete one document.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/dream_opensearch/document.html): `bulk` and the other document functions.
