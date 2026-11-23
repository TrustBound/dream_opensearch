//// Tests for the snippets of the bulk loading guide
//// (docs/guides/bulk-loading.md), against the real OpenSearch of
//// `opensearch_cluster`. Each test uses its own index and deletes it.
////
//// The node of `docker-compose.yml` takes request bodies up to 1 MB
//// (`http.max_content_length`), so a test can make a real 413.
////
//// A cluster does not report how many requests it got, so the batch test
//// that counts requests uses the local test server of
//// `opensearch_test_server`, with bodies copied from the real cluster.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import guide_responses
import opensearch_cluster
import opensearch_test_server.{Respond}
import snippets/guide_bulk_loading_books.{type Book, Book, FailedItem}
import snippets/guide_managing_indexes_create

const programming_gleam =
  Book(id: "1", title: "Programming Gleam", author: "Jo Lee", year: 2024)

const gleam_for_erlang =
  Book(
    id: "2",
    title: "Gleam for Erlang Developers",
    author: "Sam Park",
    year: 2022,
  )

const far_future =
  Book(
    id: "3",
    title: "Notes from the Future",
    author: "Kim Ito",
    year: 3_000_000_000,
  )

/// The failed item that OpenSearch 2.19.1 returns for `far_future` in an
/// index with the mapping of the managing indexes guide.
const unparsable =
  FailedItem(
    id: "3",
    status: 400,
    error_type: "mapper_parsing_exception",
    reason: "failed to parse field [year] of type [integer] in document with id '3'. Preview of field's value: '3000000000'",
  )

/// A rejected item, as `retry_rejected` gets it. A cluster rejects
/// documents with status 429 only under load, so the tests cannot make one
/// happen. The reason is the start of the reason that OpenSearch writes.
const rejected =
  FailedItem(
    id: "2",
    status: 429,
    error_type: "es_rejected_execution_exception",
    reason: "rejected execution of coordinating operation",
  )

/// The number of documents in `index`, after a refresh.
fn count(opensearch: Client, index: String) -> Result(Int, String) {
  use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
  use body <- result.try(client.send_request(
    opensearch,
    http.Get,
    "/" <> index <> "/_count",
    "",
  ))
  json.parse(body, decode.at(["count"], decode.int))
  |> result.replace_error("Unexpected count response: " <> body)
}

fn create_books_index(
  opensearch: Client,
  index: String,
) -> Result(Nil, String) {
  guide_managing_indexes_create.create_books_index(opensearch, index)
}

/// A book whose title alone is larger than the 1 MB limit of the node.
fn huge_book(id: String) -> Book {
  Book(id:, title: string.repeat("a", 1_100_000), author: "Kim Ito", year: 2024)
}

pub fn tests() -> TestSuite {
  describe("bulk loading guide", [
    group("step 1: the bulk body", [
      it("bulk_body writes two lines for each book", fn() {
        // Act
        let body =
          guide_bulk_loading_books.bulk_body("books", [
            programming_gleam,
            gleam_for_erlang,
          ])

        // Assert
        body
        |> should
        |> be_equal(
          "{\"index\":{\"_index\":\"books\",\"_id\":\"1\"}}\n{\"title\":\"Programming Gleam\",\"author\":\"Jo Lee\",\"year\":2024}\n{\"index\":{\"_index\":\"books\",\"_id\":\"2\"}}\n{\"title\":\"Gleam for Erlang Developers\",\"author\":\"Sam Park\",\"year\":2022}\n",
        )
        |> or_fail_with("bulk_body should match the guide")
      }),
      it("bulk_body of no books is empty", fn() {
        // Act
        let body = guide_bulk_loading_books.bulk_body("books", [])

        // Assert
        body
        |> should
        |> be_equal("")
        |> or_fail_with("No books, no lines")
      }),
    ]),
    group("step 2: send it", [
      it("load_books stores every book and returns no failures", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_books_index(opensearch, index))
          use failed <- result.try(
            guide_bulk_loading_books.load_books(opensearch, index, [
              programming_gleam,
              gleam_for_erlang,
            ]),
          )
          use stored <- result.try(count(opensearch, index))
          Ok(#(failed, stored))
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#([], 2)))
        |> or_fail_with("Both books should be stored")
      }),
      it("load_books creates a missing index on the first write", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use failed <- result.try(
            guide_bulk_loading_books.load_books(opensearch, index, [
              programming_gleam,
              gleam_for_erlang,
            ]),
          )
          use stored <- result.try(count(opensearch, index))
          Ok(#(failed, stored))
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#([], 2)))
        |> or_fail_with("OpenSearch should create the index")
      }),
    ]),
    group("step 3: find what failed", [
      it("load_books returns the book that does not fit the mapping", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_books_index(opensearch, index))
          use failed <- result.try(
            guide_bulk_loading_books.load_books(opensearch, index, [
              programming_gleam,
              gleam_for_erlang,
              far_future,
            ]),
          )
          use stored <- result.try(count(opensearch, index))
          Ok(#(failed, stored))
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#([unparsable], 2)))
        |> or_fail_with("Book 3 failed, books 1 and 2 are stored")
      }),
      it("failed_items reads create, update and delete items too", fn() {
        // Act
        let failed = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use _ <- result.try(document.index(
            opensearch,
            index,
            "1",
            "{\"title\":\"Programming Gleam\"}",
          ))
          let action = fn(name, id) {
            "{\""
            <> name
            <> "\":{\"_index\":\""
            <> index
            <> "\",\"_id\":\""
            <> id
            <> "\"}}\n"
          }
          let ndjson =
            action("create", "1")
            <> "{\"title\":\"Programming Gleam\"}\n"
            <> action("update", "9")
            <> "{\"doc\":{\"title\":\"Missing\"}}\n"
            <> action("delete", "8")
          use body <- result.try(document.bulk(opensearch, ndjson))
          guide_bulk_loading_books.failed_items(body)
        }

        // Assert
        failed
        |> should
        |> be_equal(
          Ok([
            FailedItem(
              id: "1",
              status: 409,
              error_type: "version_conflict_engine_exception",
              reason: "[1]: version conflict, document already exists (current version [1])",
            ),
            FailedItem(
              id: "9",
              status: 404,
              error_type: "document_missing_exception",
              reason: "[9]: document missing",
            ),
          ]),
        )
        |> or_fail_with(
          "The create and the update failed, the delete has no error",
        )
      }),
      it("failed_items names a body it cannot read", fn() {
        // Act
        let failed = guide_bulk_loading_books.failed_items("{}")

        // Assert
        failed
        |> should
        |> be_equal(Error("Unexpected bulk response: {}"))
        |> or_fail_with("A body with no items is unexpected")
      }),
    ]),
    group("step 4: batches", [
      it("load_in_batches stores every batch", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_books_index(opensearch, index))
          use failed <- result.try(guide_bulk_loading_books.load_in_batches(
            opensearch,
            index,
            [programming_gleam, gleam_for_erlang, far_future],
            2,
          ))
          use stored <- result.try(count(opensearch, index))
          Ok(#(failed, stored))
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#([unparsable], 2)))
        |> or_fail_with("The failures of both batches should come back")
      }),
      it("load_in_batches sends one request for each batch", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            Respond(200, guide_responses.two_books_loaded),
            Respond(200, guide_responses.book_three_failed),
          ])
        let opensearch = client.new(opensearch_test_server.base_url(server))
        let books = [programming_gleam, gleam_for_erlang, far_future]

        // Act
        let failed =
          guide_bulk_loading_books.load_in_batches(
            opensearch,
            "books",
            books,
            2,
          )

        // Assert
        [server, server]
        |> list.map(opensearch_test_server.await_request)
        |> result.all
        |> result.map(list.map(_, opensearch_test_server.request_body))
        |> result.map(fn(bodies) { #(failed, bodies) })
        |> should
        |> be_equal(
          Ok(
            #(Ok([unparsable]), [
              guide_bulk_loading_books.bulk_body("books", [
                programming_gleam,
                gleam_for_erlang,
              ]),
              guide_bulk_loading_books.bulk_body("books", [far_future]),
            ]),
          ),
        )
        |> or_fail_with("Expected two batches: two books, then one")
      }),
      it("load_in_batches stops at a request that is too large", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_books_index(opensearch, index))
          let books = [
            programming_gleam,
            gleam_for_erlang,
            huge_book("4"),
            huge_book("5"),
          ]
          let failed =
            guide_bulk_loading_books.load_in_batches(
              opensearch,
              index,
              books,
              2,
            )
          use stored <- result.try(count(opensearch, index))
          Ok(#(failed, stored))
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#(Error(""), 2)))
        |> or_fail_with("A 413 has no body, and the first batch stays stored")
      }),
    ]),
    group("step 5: retry", [
      it("retry_rejected loads the 429 book again", fn() {
        // Act
        let retried = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_books_index(opensearch, index))
          use still_failed <- result.try(
            guide_bulk_loading_books.retry_rejected(
              opensearch,
              index,
              [programming_gleam, gleam_for_erlang, far_future],
              [rejected, unparsable],
            ),
          )
          use stored <- result.try(count(opensearch, index))
          Ok(#(still_failed, stored))
        }

        // Assert
        retried
        |> should
        |> be_equal(Ok(#([unparsable], 1)))
        |> or_fail_with("Only book 2 goes again, book 3 stays failed")
      }),
      it("retry_rejected sends nothing when nothing was rejected", fn() {
        // Arrange
        let opensearch = client.new("http://127.0.0.1:1")

        // Act
        let still_failed =
          guide_bulk_loading_books.retry_rejected(
            opensearch,
            "books",
            [far_future],
            [
              unparsable,
            ],
          )

        // Assert
        still_failed
        |> should
        |> be_equal(Ok([unparsable]))
        |> or_fail_with("No 429, no request")
      }),
    ]),
    group("failures", [
      it("a body with no final newline fails the whole request", fn() {
        // Act
        let sent = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          document.bulk(
            opensearch,
            "{\"index\":{\"_index\":\""
              <> index
              <> "\",\"_id\":\"1\"}}\n{\"title\":\"Programming Gleam\"}",
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        sent
        |> should
        |> be_equal(Ok(Error(Ok(#("illegal_argument_exception", 400)))))
        |> or_fail_with("Expected the illegal_argument_exception body")
      }),
      it("the reason names the missing newline", fn() {
        // Act
        let sent = document.bulk(opensearch_cluster.client(), "{}")

        // Assert
        sent
        |> should
        |> be_equal(Error(
          "{\"error\":{\"root_cause\":[{\"type\":\"illegal_argument_exception\",\"reason\":\"The bulk request must be terminated by a newline [\\\\n]\"}],\"type\":\"illegal_argument_exception\",\"reason\":\"The bulk request must be terminated by a newline [\\\\n]\"},\"status\":400}",
        ))
        |> or_fail_with("Expected the whole error body")
      }),
      it("a document over two lines fails the whole request", fn() {
        // Act
        let sent = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          document.bulk(
            opensearch,
            "{\"index\":{\"_index\":\""
              <> index
              <> "\",\"_id\":\"1\"}}\n{\"title\":\n\"Programming Gleam\"}\n",
          )
          |> Ok
        }

        // Assert
        sent
        |> should
        |> be_equal(
          Ok(Error(
            "{\"error\":{\"root_cause\":[{\"type\":\"illegal_argument_exception\",\"reason\":\"Malformed action/metadata line [3], expected START_OBJECT but found [VALUE_STRING]\"}],\"type\":\"illegal_argument_exception\",\"reason\":\"Malformed action/metadata line [3], expected START_OBJECT but found [VALUE_STRING]\"},\"status\":400}",
          )),
        )
        |> or_fail_with("The second line of the document is read as an action")
      }),
      it("an empty list of books fails with parse_exception", fn() {
        // Act
        let loaded =
          guide_bulk_loading_books.load_books(
            opensearch_cluster.client(),
            "books",
            [],
          )

        // Assert
        loaded
        |> should
        |> be_equal(Error(
          "{\"error\":{\"root_cause\":[{\"type\":\"parse_exception\",\"reason\":\"request body is required\"}],\"type\":\"parse_exception\",\"reason\":\"request body is required\"},\"status\":400}",
        ))
        |> or_fail_with("OpenSearch refuses an empty bulk body")
      }),
    ]),
  ])
}
