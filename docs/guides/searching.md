# Searching an index

Your documents are in OpenSearch, and now you want to find them again: by words in a title, by an exact author, by a range of years, or by all of those at once, one page at a time. And you want Gleam values back, not a JSON string. This guide builds a small search module for a book catalog, from a first query to a combined, paged and sorted search, with tests.

## Table of Contents

- [What you'll build](#what-youll-build)
- [Before you start](#before-you-start)
- [How a search works](#how-a-search-works)
- [Which query to use](#which-query-to-use)
- [Step 1: Run a query and read the hits](#step-1-run-a-query-and-read-the-hits)
- [Step 2: Find exact values with term](#step-2-find-exact-values-with-term)
- [Step 3: Find a range of values](#step-3-find-a-range-of-values)
- [Step 4: Combine conditions, then page and sort](#step-4-combine-conditions-then-page-and-sort)
- [When a search fails](#when-a-search-fails)
- [Test your code](#test-your-code)
- [Common pitfalls](#common-pitfalls)
- [Where to go next](#where-to-go-next)

## What you'll build

In this guide you'll:

- Send any query to an index of books and get back the number of matches and a list of `Book` values.
- Search the words of a title.
- Find the books of one author, by the exact name.
- Find the books published between two years.
- Combine a text search with filters, and ask for one page of results in a fixed order.
- Test the queries and the response reading with no cluster.

## Before you start

Add the package, and `gleam_json` to build queries and read responses:

```sh
gleam add dream_opensearch gleam_json
```

The examples search an index named `books`, with this mapping:

| Field | Type | Example |
|:---|:---|:---|
| `title` | `text` | `"Programming Gleam"` |
| `author` | `keyword` | `"Jo Lee"` |
| `year` | `integer` | `2024` |
| `in_stock` | `boolean` | `true` |

The types matter for search, and this guide says why at each step. [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md) creates this index, and [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md) fills it.

Every example in this guide is tested against OpenSearch 2.19.1 in Docker, in an index with this mapping. [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) shows the Docker service, and `docker compose up -d --wait opensearch` starts it. The responses you see here are bodies that the cluster really sent. `took` and the scores change with the documents in the index and from run to run.

## How a search works

A search is one request. You send a JSON query to `POST /<index>/_search`, and OpenSearch answers with the matching documents. In this package:

- The builders in `dream_opensearch/query` return the whole request body as a string. `query.match("title", "gleam")` returns `{"query":{"match":{"title":"gleam"}}}`.
- `document.search(client, index, query_json)` sends that string, and returns `Ok` with the response body as a string.
- Reading the response is your part. You decode it with `gleam/json` into your own types.

The builders cover the common single queries. For anything more, you write the query JSON yourself with `gleam/json`, as [Step 4](#step-4-combine-conditions-then-page-and-sort) shows.

## Which query to use

| Your situation | Use | Why |
|:---|:---|:---|
| Words that a person types, in any case and any order, in a `text` field | `query.match(field, text)` | OpenSearch analyzes the text first, so `gleam` finds `Programming Gleam` |
| One exact value: a status, a tag, an ID, an author in a `keyword` field | `query.term(field, value)` | No analysis. The value must equal the stored value exactly |
| Values between two bounds, both included: years, prices, dates | `query.range(field, gte, lte)` | Matches `gte <= value <= lte`. Both bounds are strings |
| Every document, for example to browse or to count | `query.match_all()` | Matches all documents, with the same score |
| Several conditions, an open-ended range, a page, a sort | Your own JSON, built with `gleam/json` | The builders return complete bodies, so you cannot put one inside another |

## Step 1: Run a query and read the hits

Start with the part every search needs: send a query and turn the response into Gleam values. Write it once, and every search in the module uses it:

### Search the books index and read the hits <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_searching_books.gleam#L6-L63"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

pub type Book {
  Book(id: String, title: String, author: String, year: Int, in_stock: Bool)
}

pub type SearchResult {
  /// `total` counts every match, `books` holds one page of them.
  SearchResult(total: Int, books: List(Book))
}

/// Sends `query_json` to `index` and reads the hits.
pub fn search_books(
  opensearch: Client,
  index: String,
  query_json: String,
) -> Result(SearchResult, String) {
  use body <- result.try(document.search(opensearch, index, query_json))
  search_result_from_response(body)
}

/// Reads the total and the books out of the body of a search response.
pub fn search_result_from_response(
  body: String,
) -> Result(SearchResult, String) {
  json.parse(body, search_result_decoder())
  |> result.replace_error("Unexpected search response: " <> body)
}

fn search_result_decoder() -> decode.Decoder(SearchResult) {
  use total <- decode.subfield(["hits", "total", "value"], decode.int)
  use books <- decode.subfield(["hits", "hits"], decode.list(book_hit()))
  decode.success(SearchResult(total:, books:))
}

fn book_hit() -> decode.Decoder(Book) {
  use id <- decode.field("_id", decode.string)
  use title <- decode.subfield(["_source", "title"], decode.string)
  use author <- decode.subfield(["_source", "author"], decode.string)
  use year <- decode.subfield(["_source", "year"], decode.int)
  use in_stock <- decode.subfield(["_source", "in_stock"], decode.bool)
  decode.success(Book(id:, title:, author:, year:, in_stock:))
}

/// Full-text search in the titles.
pub fn books_about(
  opensearch: Client,
  index: String,
  words: String,
) -> Result(SearchResult, String) {
  search_books(opensearch, index, query.match("title", words))
}
```

`search_books` takes the index name and any query string. It sends the query with `document.search`, and gives the body to `search_result_from_response`. The other functions of the module take the index name too, so a test can use an index of its own.

`books_about(opensearch, "books", "gleam")` sends this request:

### The request of books_about <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_match_request.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
POST /books/_search
{"query":{"match":{"title":"gleam"}}}
```

For an index that holds these two books, OpenSearch answers with this body:

### The answer to the match query <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_match_response.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"took":1,"timed_out":false,"_shards":{"total":1,"successful":1,"skipped":0,"failed":0},"hits":{"total":{"value":2,"relation":"eq"},"max_score":0.21110919,"hits":[{"_index":"books","_id":"1","_score":0.21110919,"_source":{"title":"Programming Gleam","author":"Jo Lee","year":2024,"in_stock":true}},{"_index":"books","_id":"2","_score":0.160443,"_source":{"title":"Gleam for Erlang Developers","author":"Sam Park","year":2022,"in_stock":false}}]}}
```

The shorter title gets the higher score, so `Programming Gleam` comes first.

The decoder reads two things from it:

- `hits.total.value`: how many documents match in all. That is the number you show as "2 results".
- `hits.hits`: the documents of this page, best match first. Each hit has the document ID in `_id`, its relevance in `_score`, and the document you stored in `_source`.

So `books_about` returns:

### The result of books_about <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_books_about.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
Ok(SearchResult(total: 2, books: [Book(id: "1", title: "Programming Gleam", author: "Jo Lee", year: 2024, in_stock: True), Book(id: "2", title: "Gleam for Erlang Developers", author: "Sam Park", year: 2022, in_stock: False)]))
```

When nothing matches, the request still succeeds. `hits.hits` is an empty list, and the function returns `Ok(SearchResult(total: 0, books: []))`. An empty result is not an error.

Keep `total` and `books` apart in your head. OpenSearch returns 10 hits unless you ask for another page size, so `total` can be much larger than the length of `books`. [Step 4](#step-4-combine-conditions-then-page-and-sort) sets the page.

## Step 2: Find exact values with term

A match query is right for words a person types. For a value that must be exact, such as an author's name from a list, use a term query. Add this to the module:

### Find the books of one author <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_searching_books.gleam#L65-L72"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// The books of one author, spelled exactly as stored.
pub fn books_by(
  opensearch: Client,
  index: String,
  author: String,
) -> Result(SearchResult, String) {
  search_books(opensearch, index, query.term("author", author))
}
```

`books_by(opensearch, "books", "Jo Lee")` sends:

### The request of books_by <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_term_request.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
POST /books/_search
{"query":{"term":{"author":"Jo Lee"}}}
```

A term query does not analyze the value. It finds the documents whose field holds exactly `Jo Lee`, in that case: `books_by(opensearch, "books", "jo lee")` finds nothing. That works because `author` is a `keyword` field, which stores the value as one unit.

A `text` field is different. OpenSearch splits it into lower-case words when it stores it, so the title `Programming Gleam` is stored as `programming` and `gleam`. A term query for `Programming Gleam` on `title` looks for that whole string among those words, and finds nothing. Use `match` on `text` fields and `term` on `keyword`, number and boolean fields.

`query.term` always sends the value as a JSON string. For a number or a boolean field, OpenSearch converts the string, so `query.term("in_stock", "false")` finds the books that are not in stock. To send a real JSON `true` or `2024`, build the query yourself, as in Step 4.

## Step 3: Find a range of values

To find the books from a span of years, use a range query:

### Find the books published between two years <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_searching_books.gleam#L74-L84"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
/// The books published from `first_year` to `last_year`, both included.
pub fn books_published_between(
  opensearch: Client,
  index: String,
  first_year: Int,
  last_year: Int,
) -> Result(SearchResult, String) {
  let years =
    query.range("year", int.to_string(first_year), int.to_string(last_year))
  search_books(opensearch, index, years)
}
```

`books_published_between(opensearch, "books", 2020, 2024)` sends:

### The request of books_published_between <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_range_request.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
POST /books/_search
{"query":{"range":{"year":{"gte":"2020","lte":"2024"}}}}
```

Both bounds are included: `gte` means greater than or equal, and `lte` means less than or equal. `query.range` takes both bounds as strings, so the function converts the years with `int.to_string`, and OpenSearch converts them back to the type of the field. The same works for dates, with strings such as `"2024-01-01"`.

`query.range` always sends both bounds. For "2020 or later", with no upper bound, or for a bound that is not included (`gt`, `lt`), write the range yourself, as the next step does.

## Step 4: Combine conditions, then page and sort

A real search screen asks for more than one thing at once: books about Gleam, in stock, from 2020 on, newest first, ten to a page. That is a bool query with paging and a sort. The builders return complete bodies, so you cannot nest one in another. Build the whole body with `gleam/json` instead:

### Build a bool query with paging and sorting <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_searching_bool.gleam#L5-L61"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import gleam/json

/// Books in stock whose title matches `words`, published in `from_year` or
/// later, newest first, one page at a time. `page` counts from 1.
pub fn in_stock_query(
  words: String,
  from_year: Int,
  page: Int,
  per_page: Int,
) -> String {
  let bool_query =
    json.object([
      #(
        "bool",
        json.object([
          // `must` clauses decide which books match, and how well
          #(
            "must",
            json.preprocessed_array([match("title", json.string(words))]),
          ),
          // `filter` clauses only include or exclude, with no score
          #(
            "filter",
            json.preprocessed_array([
              term("in_stock", json.bool(True)),
              at_least("year", json.int(from_year)),
            ]),
          ),
        ]),
      ),
    ])
  json.object([
    #("query", bool_query),
    #("from", json.int({ page - 1 } * per_page)),
    #("size", json.int(per_page)),
    #("sort", json.preprocessed_array([newest_first()])),
  ])
  |> json.to_string
}

fn match(field: String, value: json.Json) -> json.Json {
  json.object([#("match", json.object([#(field, value)]))])
}

fn term(field: String, value: json.Json) -> json.Json {
  json.object([#("term", json.object([#(field, value)]))])
}

fn at_least(field: String, value: json.Json) -> json.Json {
  json.object([
    #("range", json.object([#(field, json.object([#("gte", value)]))])),
  ])
}

fn newest_first() -> json.Json {
  json.object([#("year", json.object([#("order", json.string("desc"))]))])
}
```

The parts of the body:

- `bool.must` holds the clauses that decide what matches and how well. The text search goes here, because its score orders the results by relevance.
- `bool.filter` holds the clauses that only include or exclude. They do not change the score, and OpenSearch can cache them. Exact values and ranges go here.
- `at_least` writes a range with only `gte`, which `query.range` cannot do.
- `from` and `size` select the page. `from` is the number of hits to skip, so page 1 starts at 0 and page 2 starts at `per_page`.
- `sort` orders the results by `year`, newest first, instead of by score.

`in_stock_query("gleam", 2020, 1, 10)` returns this body:

### The body of in_stock_query <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_in_stock_query.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"query":{"bool":{"must":[{"match":{"title":"gleam"}}],"filter":[{"term":{"in_stock":true}},{"range":{"year":{"gte":2020}}}]}},"from":0,"size":10,"sort":[{"year":{"order":"desc"}}]}
```

Send it with the function from Step 1, as `search_books(opensearch, "books", in_stock_query("gleam", 2020, 1, 10))`, and you get a `SearchResult` back as before. For the two books above, that is `Ok(SearchResult(total: 1, books: [Book(id: "1", title: "Programming Gleam", author: "Jo Lee", year: 2024, in_stock: True)]))`: book 2 is about Gleam, but it is not in stock. `total` still counts every match, so you can work out the number of pages from it.

Note that `in_stock_query` sends no request. It is a plain function from your parameters to a string, so you can test it with no cluster, as [Test your code](#test-your-code) does.

## When a search fails

`search_books` returns `Error(String)` in three kinds of cases.

**The index does not exist.** OpenSearch answers with status 404, and the error is the response body:

### The answer for a missing index <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_missing_index.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"error":{"root_cause":[{"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"}],"type":"index_not_found_exception","reason":"no such index [books]","index":"books","resource.id":"books","resource.type":"index_or_alias","index_uuid":"_na_"},"status":404}
```

**OpenSearch cannot read the query.** A misspelled query type, such as `matches` for `match`, gets status 400 and a body that says where the problem is:

### The answer to a misspelled query <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/outputs/guide_searching_parse_error.txt"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```text
{"error":{"root_cause":[{"type":"parsing_exception","reason":"unknown query [matches] did you mean any of [match, match_all]?","line":1,"col":21}],"type":"parsing_exception","reason":"unknown query [matches] did you mean any of [match, match_all]?","line":1,"col":21,"caused_by":{"type":"named_object_not_found_exception","reason":"[1:21] unknown field [matches]"}},"status":400}
```

The builders always write valid queries. This error comes from JSON that you build yourself, so test your query builders, as the next section shows.

**The response does not fit your decoder.** The request worked, but a document lacks a field the decoder needs. For example, a book with no `year` makes the whole page fail with `Error("Unexpected search response: <the body>")`. If some documents can lack a field, read it with `decode.optional_field` and make the field an `Option` in your type.

A refused connection, a wrong URL and the other errors of the client come back as messages. [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md) lists them, and shows how to tell an OpenSearch error from a connection error in code.

## Test your code

Test the searches themselves against a real cluster: start the Docker service from [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md#before-you-start) with `docker compose up -d --wait opensearch`, create an index with a name of its own for each test, load a few books, refresh the index, search, and delete the index at the end. That is how the examples of this guide are tested.

The search module also has two parts that you can test with no cluster at all:

- **The queries.** `in_stock_query` is a pure function. Assert the exact JSON it returns, and you know what goes to OpenSearch.
- **The response reading.** `search_result_from_response` takes a body. Give it a saved response, and assert the values.

Add `dream_test` as a dev dependency, from GitHub, with the commit that this package tests with:

### The dev dependency on dream_test <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/gleam.toml#L27-L29"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```toml
[dev-dependencies]
# Switched to a Hex version range once it is published.
dream_test = { git = "https://github.com/TrustBound/dream_test.git", ref = "1639959578a14ae3577f8e3ae5cac058f933aa53" }
```

Here is a test module for both parts:

### Test a query builder and the response reader <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/guide_searching_testing.gleam#L5-L59"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_searching_books.{
  Book, SearchResult, search_result_from_response,
}
import snippets/guide_searching_bool.{in_stock_query}

pub fn tests() -> TestSuite {
  describe("book search", [
    it("asks for the second page of ten", fn() {
      // Act
      let query_json = in_stock_query("gleam", 2020, 2, 10)

      // Assert
      query_json
      |> should
      |> be_equal(
        "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"title\":\"gleam\"}}],"
        <> "\"filter\":[{\"term\":{\"in_stock\":true}},"
        <> "{\"range\":{\"year\":{\"gte\":2020}}}]}},"
        <> "\"from\":10,\"size\":10,\"sort\":[{\"year\":{\"order\":\"desc\"}}]}",
      )
      |> or_fail_with("Page 2 of 10 should start at hit 10")
    }),
    it("reads the total and the books of a response", fn() {
      // Arrange
      let body =
        "{\"hits\":{\"total\":{\"value\":12,\"relation\":\"eq\"},\"hits\":["
        <> "{\"_id\":\"7\",\"_source\":{\"title\":\"Gleam in Action\","
        <> "\"author\":\"Jo Lee\",\"year\":2024,\"in_stock\":true}}]}}"

      // Act
      let result = search_result_from_response(body)

      // Assert
      result
      |> should
      |> be_equal(
        Ok(
          SearchResult(total: 12, books: [
            Book(
              id: "7",
              title: "Gleam in Action",
              author: "Jo Lee",
              year: 2024,
              in_stock: True,
            ),
          ]),
        ),
      )
      |> or_fail_with("Expected 12 matches and one book on this page")
    }),
  ])
}
```

The first test pins down the paging: page 2 of 10 starts at hit 10. The second test reads a response where `total` is 12 and the page holds one book, which is the case a paging screen must get right.

Use real responses from your cluster in these tests where you can. Run the query once against a development cluster, copy the body into the test, and you test the decoder against what your cluster really sends.

## Common pitfalls

**A term query that finds nothing.** *Symptom:* `query.term("title", "Programming Gleam")` returns no hits, but the book is there. *Fix:* `title` is a `text` field, which OpenSearch stores as lower-case words. Use `query.match` on `text` fields, and `query.term` on `keyword`, number and boolean fields. If you need both, map the field as `text` with a `keyword` sub-field.

**A builder inside a bool query.** *Symptom:* a `parsing_exception` from a bool query that holds the output of `query.match`. *Fix:* each builder returns a whole body, `{"query":{...}}`, and a body cannot go inside another query. Build the clauses with `gleam/json`, as in [Step 4](#step-4-combine-conditions-then-page-and-sort).

**Only ten results.** *Symptom:* `total` says 37, but `books` holds 10. *Fix:* OpenSearch returns 10 hits unless the body has `size`. Set `from` and `size` for the page you want.

**No hits right after a write.** *Symptom:* a test indexes a book and searches at once, and finds nothing. *Fix:* OpenSearch makes new documents visible at the next refresh, about once a second by default. Refresh the index before you search in tests, with `client.send_request(opensearch, http.Post, "/books/_refresh", "")`.

**One bad document fails the whole page.** *Symptom:* `Unexpected search response` for a search that worked yesterday. *Fix:* a document without a field your decoder needs makes `decode.list` fail. Make that field optional in the decoder, or make sure every document has it, for example with a strict mapping. See [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md).

**A range with numbers in it.** *Symptom:* a compile error when you pass `2020` to `query.range`. *Fix:* the bounds are strings. Convert numbers with `int.to_string`, or write the range with `json.int` yourself.

## Where to go next

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): connect, save, find and delete, from an empty project.
- [Loading documents in bulk](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-loading.md): fill the `books` index with many documents in one request.
- [Managing indexes](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/managing-indexes.md): the mapping that makes `term` and `range` work.
- [Handling errors](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/handling-errors.md): tell a missing index from a refused connection in code.
- [API reference on HexDocs](https://hexdocs.pm/dream_opensearch/dream_opensearch/query.html): `match`, `term`, `range` and `match_all`.
