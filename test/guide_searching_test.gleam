//// Tests for the snippets of the searching guide
//// (docs/guides/searching.md), against the real OpenSearch of
//// `opensearch_cluster`. Each test creates its own index with the mapping
//// of the managing indexes guide, loads three books, and deletes the index.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/result
import gleam/string
import opensearch_cluster
import snippets/guide_managing_indexes_create
import snippets/guide_searching_books.{type SearchResult, Book, SearchResult}
import snippets/guide_searching_bool

const programming_gleam =
  Book(
    id: "1",
    title: "Programming Gleam",
    author: "Jo Lee",
    year: 2024,
    in_stock: True,
  )

const gleam_for_erlang =
  Book(
    id: "2",
    title: "Gleam for Erlang Developers",
    author: "Sam Park",
    year: 2022,
    in_stock: False,
  )

const learning_erlang =
  Book(
    id: "3",
    title: "Learning Erlang",
    author: "Jo Lee",
    year: 2019,
    in_stock: True,
  )

fn books_ndjson(index: String) -> String {
  let action = fn(id) {
    "{\"index\":{\"_index\":\"" <> index <> "\",\"_id\":\"" <> id <> "\"}}\n"
  }
  action("1")
  <> "{\"title\":\"Programming Gleam\",\"author\":\"Jo Lee\",\"year\":2024,\"in_stock\":true}\n"
  <> action("2")
  <> "{\"title\":\"Gleam for Erlang Developers\",\"author\":\"Sam Park\",\"year\":2022,\"in_stock\":false}\n"
  <> action("3")
  <> "{\"title\":\"Learning Erlang\",\"author\":\"Jo Lee\",\"year\":2019,\"in_stock\":true}\n"
}

/// Runs `search` on a new index that holds the three books.
fn with_books(
  search: fn(Client, String) -> Result(SearchResult, String),
) -> Result(Result(SearchResult, String), String) {
  use opensearch, index <- opensearch_cluster.with_index("books")
  use Nil <- result.try(guide_managing_indexes_create.create_books_index(
    opensearch,
    index,
  ))
  use _ <- result.try(document.bulk(opensearch, books_ndjson(index)))
  use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
  Ok(search(opensearch, index))
}

pub fn tests() -> TestSuite {
  describe("searching guide", [
    group("step 1: match", [
      it("books_about finds the two Gleam books, best match first", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.books_about(opensearch, index, "gleam")
          })

        // Assert
        found
        |> should
        |> be_equal(
          Ok(
            Ok(
              SearchResult(total: 2, books: [
                programming_gleam,
                gleam_for_erlang,
              ]),
            ),
          ),
        )
        |> or_fail_with("gleam should match both Gleam titles")
      }),
      it("books_about with no match is an empty result", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.books_about(opensearch, index, "rust")
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 0, books: []))))
        |> or_fail_with("No match is not an error")
      }),
    ]),
    group("step 2: term", [
      it("books_by finds the books of one author", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.books_by(opensearch, index, "Jo Lee")
          })

        // Assert
        found
        |> should
        |> be_equal(
          Ok(
            Ok(
              SearchResult(total: 2, books: [programming_gleam, learning_erlang]),
            ),
          ),
        )
        |> or_fail_with("Jo Lee wrote books 1 and 3")
      }),
      it("books_by needs the exact case of the keyword", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.books_by(opensearch, index, "jo lee")
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 0, books: []))))
        |> or_fail_with("A keyword is not analyzed")
      }),
      it("a term query on a text field finds nothing", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.search_books(
              opensearch,
              index,
              query.term("title", "Programming Gleam"),
            )
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 0, books: []))))
        |> or_fail_with("A text field holds lower-case words")
      }),
      it("a term query sends a boolean as a string that works", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.search_books(
              opensearch,
              index,
              query.term("in_stock", "false"),
            )
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 1, books: [gleam_for_erlang]))))
        |> or_fail_with("OpenSearch converts the string false")
      }),
    ]),
    group("step 3: range", [
      it("books_published_between includes both bounds", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.books_published_between(
              opensearch,
              index,
              2022,
              2024,
            )
          })

        // Assert
        found
        |> should
        |> be_equal(
          Ok(
            Ok(
              SearchResult(total: 2, books: [
                programming_gleam,
                gleam_for_erlang,
              ]),
            ),
          ),
        )
        |> or_fail_with("2022 and 2024 are both in the range")
      }),
    ]),
    group("step 4: bool, paging and sorting", [
      it("in_stock_query builds the first page", fn() {
        // Act
        let query_json =
          guide_searching_bool.in_stock_query("gleam", 2020, 1, 10)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"title\":\"gleam\"}}],\"filter\":[{\"term\":{\"in_stock\":true}},{\"range\":{\"year\":{\"gte\":2020}}}]}},\"from\":0,\"size\":10,\"sort\":[{\"year\":{\"order\":\"desc\"}}]}",
        )
        |> or_fail_with("Expected the bool query of the guide")
      }),
      it("in_stock_query finds the Gleam book in stock from 2020 on", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.search_books(
              opensearch,
              index,
              guide_searching_bool.in_stock_query("gleam", 2020, 1, 10),
            )
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 1, books: [programming_gleam]))))
        |> or_fail_with("Book 2 is not in stock, book 3 is not about Gleam")
      }),
      it("sorts all books in stock newest first, one to a page", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.search_books(
              opensearch,
              index,
              "{\"query\":{\"term\":{\"in_stock\":true}},\"from\":1,\"size\":1,"
                <> "\"sort\":[{\"year\":{\"order\":\"desc\"}}]}",
            )
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok(SearchResult(total: 2, books: [learning_erlang]))))
        |> or_fail_with("Page 2 of 1 holds the older book in stock")
      }),
    ]),
    group("failures", [
      it("a missing index comes back as its 404 body", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          guide_searching_books.books_about(opensearch, index, "gleam")
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        found
        |> should
        |> be_equal(Ok(Error(Ok(#("index_not_found_exception", 404)))))
        |> or_fail_with("Expected the index_not_found_exception body")
      }),
      it("a query OpenSearch cannot parse comes back as its 400 body", fn() {
        // Act
        let found =
          with_books(fn(opensearch, index) {
            guide_searching_books.search_books(
              opensearch,
              index,
              "{\"query\":{\"matches\":{\"title\":\"gleam\"}}}",
            )
          })
          |> result.map(result.map_error(
            _,
            opensearch_cluster.error_type_and_status,
          ))

        // Assert
        found
        |> should
        |> be_equal(Ok(Error(Ok(#("parsing_exception", 400)))))
        |> or_fail_with("Expected the parsing_exception body")
      }),
      it("a hit without a year is an unexpected response", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          let notes =
            "{\"title\":\"Notes\",\"author\":\"Kim\",\"in_stock\":true}"
          use _ <- result.try(document.index(opensearch, index, "9", notes))
          use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
          guide_searching_books.books_about(opensearch, index, "notes")
          |> result.map_error(string.starts_with(
            _,
            "Unexpected search response: {\"took\":",
          ))
          |> Ok
        }

        // Assert
        found
        |> should
        |> be_equal(Ok(Error(True)))
        |> or_fail_with("A book with no year should not decode")
      }),
    ]),
  ])
}
