//// Tests for the code blocks in the doc comments of `src/`, against the real
//// OpenSearch of `opensearch_cluster`.
////
//// Each example takes the index name as a parameter, so each test gets its
//// own index from `opensearch_cluster.with_index` and deletes it at the end.
//// The tests check what each example stores, finds or returns.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import opensearch_cluster
import opensearch_test_server
import snippets/doc_client_describe_error
import snippets/doc_client_new
import snippets/doc_client_quick_start
import snippets/doc_client_send_request
import snippets/doc_document_bulk
import snippets/doc_document_create_index
import snippets/doc_document_delete
import snippets/doc_document_delete_index
import snippets/doc_document_index
import snippets/doc_document_quick_start
import snippets/doc_document_search
import snippets/doc_query_custom
import snippets/doc_query_match
import snippets/doc_query_match_all
import snippets/doc_query_quick_start
import snippets/doc_query_range
import snippets/doc_query_term

/// Alice, active, and Bob, inactive, as users 1 and 2.
const users = [
  #(
    "1",
    "{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"status\":\"active\"}",
  ),
  #(
    "2",
    "{\"name\":\"Bob\",\"email\":\"bob@example.com\",\"status\":\"inactive\"}",
  ),
]

/// Three products, at the prices 5, 50 and 500.
const products = [
  #("1", "{\"name\":\"Pen\",\"price\":5}"),
  #("2", "{\"name\":\"Lamp\",\"price\":50}"),
  #("3", "{\"name\":\"Desk\",\"price\":500}"),
]

/// Indexes each `#(id, json)` of `documents` in `index`, then refreshes it.
fn load(
  opensearch: Client,
  index: String,
  documents: List(#(String, String)),
) -> Result(Nil, String) {
  use _ <- result.try(
    list.try_map(documents, fn(entry) {
      document.index(opensearch, index, entry.0, entry.1)
    })
    |> opensearch_cluster.as_text,
  )
  opensearch_cluster.refresh(opensearch, index)
}

/// Runs `search` on a new index with `documents`, and returns the IDs of the
/// hits, sorted.
fn found_ids(
  prefix: String,
  documents: List(#(String, String)),
  search: fn(Client, String) -> Result(String, client.OpenSearchError),
) -> Result(List(String), String) {
  use opensearch, index <- opensearch_cluster.with_index(prefix)
  use Nil <- result.try(load(opensearch, index, documents))
  use body <- result.try(
    search(opensearch, index) |> opensearch_cluster.as_text,
  )
  json.parse(
    body,
    decode.at(["hits", "hits"], decode.list(decode.at(["_id"], decode.string))),
  )
  |> result.map(list.sort(_, string.compare))
  |> result.replace_error("Unexpected search response: " <> body)
}

/// The value of the field `field` in the `_source` of document 123 of
/// `index`.
fn stored_field(
  opensearch: Client,
  index: String,
  field: String,
) -> Result(String, String) {
  use body <- result.try(
    client.send_request(opensearch, http.Get, "/" <> index <> "/_doc/123", "")
    |> opensearch_cluster.as_text,
  )
  json.parse(body, decode.at(["_source", field], decode.string))
  |> result.replace_error("Unexpected document: " <> body)
}

/// The `result` field of an index or delete response.
fn result_field(body: String) -> Result(String, String) {
  json.parse(body, decode.at(["result"], decode.string))
  |> result.replace_error("Unexpected response: " <> body)
}

pub fn tests() -> TestSuite {
  describe("doc comment snippets", [
    group("client module", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_client_quick_start.create_client()

        // Assert
        opensearch
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice creates the document 123 with her name", fn() {
        // Act
        let stored = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use body <- result.try(
            doc_client_quick_start.index_alice(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          use outcome <- result.try(result_field(body))
          use name <- result.try(stored_field(opensearch, index, "name"))
          Ok(#(outcome, name))
        }

        // Assert
        stored
        |> should
        |> be_equal(Ok(#("created", "Alice")))
        |> or_fail_with("Alice should be stored under 123")
      }),
    ]),
    group("client.describe_error", [
      it("health line says OpenSearch is healthy", fn() {
        // Arrange
        let opensearch = opensearch_cluster.client()

        // Act
        let line = doc_client_describe_error.health_line(opensearch)

        // Assert
        line
        |> should
        |> be_equal("OpenSearch is healthy")
        |> or_fail_with("health line says OpenSearch is healthy")
      }),
      it("health line describes a refused connection", fn() {
        // Arrange
        let opensearch =
          opensearch_cluster.client_for(
            "http://127.0.0.1:"
            <> int.to_string(opensearch_test_server.unused_port()),
          )

        // Act
        let line = doc_client_describe_error.health_line(opensearch)

        // Assert
        line
        |> should
        |> be_equal(
          "OpenSearch is unavailable: Connection failed: Connection refused",
        )
        |> or_fail_with("health line describes a refused connection")
      }),
    ]),
    group("client.new", [
      it("create local client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_client_new.create_local_client()

        // Assert
        opensearch
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create local client uses localhost 9200")
      }),
      it("create client with credentials keeps the url", fn() {
        // Act
        let opensearch = doc_client_new.create_client_with_credentials()

        // Assert
        opensearch
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("https://search.example.com:9200"))
        |> or_fail_with("create client with credentials keeps the url")
      }),
    ]),
    group("client.send_request", [
      it("get user returns the stored document", fn() {
        // Act
        let fetched = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
            |> opensearch_cluster.as_text,
          )
          use body <- result.try(
            doc_client_send_request.get_user(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          let decoder = {
            use found <- decode.field("found", decode.bool)
            use name <- decode.subfield(["_source", "name"], decode.string)
            decode.success(#(found, name))
          }
          json.parse(body, decoder)
          |> result.replace_error("Unexpected document: " <> body)
        }

        // Assert
        fetched
        |> should
        |> be_equal(Ok(#(True, "Alice")))
        |> or_fail_with("get user should find Alice")
      }),
      it("get user of a missing document is a 404 with found false", fn() {
        // Act
        let fetched = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.create_index(opensearch, index, "{}")
            |> opensearch_cluster.as_text,
          )
          doc_client_send_request.get_user(opensearch, index)
          |> opensearch_cluster.rejected_body
          |> result.map_error(json.parse(_, decode.at(["found"], decode.bool)))
          |> Ok
        }

        // Assert
        fetched
        |> should
        |> be_equal(Ok(Error(Ok(False))))
        |> or_fail_with("A missing document comes back as its 404 body")
      }),
    ]),
    group("document module", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_document_quick_start.create_client()

        // Assert
        opensearch
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice stores her email", fn() {
        // Act
        let stored = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            doc_document_quick_start.index_alice(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          stored_field(opensearch, index, "email")
        }

        // Assert
        stored
        |> should
        |> be_equal(Ok("alice@example.com"))
        |> or_fail_with("Alice's email should be stored under 123")
      }),
    ]),
    group("document.index", [
      it("index alice reports success", fn() {
        // Act
        let reported = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          Ok(doc_document_index.index_alice(opensearch, index))
        }

        // Assert
        reported
        |> should
        |> be_equal(Ok("Indexed successfully"))
        |> or_fail_with("index alice reports success")
      }),
      it("index alice reports the error body of a refused index name", fn() {
        // Act
        let reported =
          doc_document_index.index_alice(opensearch_cluster.client(), "Users")

        // Assert
        reported
        |> should
        |> be_equal(
          "Error: OpenSearch rejected the request with status 400: {\"error\":{\"root_cause\":[{\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"}],\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"},\"status\":400}",
        )
        |> or_fail_with("An upper-case index name gets a 400")
      }),
    ]),
    group("document.search", [
      it("search for alice finds her", fn() {
        // Act
        let found =
          found_ids("users", users, doc_document_search.search_for_alice)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches")
      }),
      it("search for alice in a missing index is a 404", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          doc_document_search.search_for_alice(opensearch, index)
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        found
        |> should
        |> be_equal(Ok(Error(Ok(#("index_not_found_exception", 404)))))
        |> or_fail_with("A missing index comes back as its 404 body")
      }),
    ]),
    group("document.delete", [
      it("delete user reports success", fn() {
        // Act
        let reported = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
            |> opensearch_cluster.as_text,
          )
          Ok(doc_document_delete.delete_user(opensearch, index))
        }

        // Assert
        reported
        |> should
        |> be_equal(Ok("Document deleted"))
        |> or_fail_with("delete user reports success")
      }),
      it("delete user reports the 404 body of a missing document", fn() {
        // Act
        let reported = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.create_index(opensearch, index, "{}")
            |> opensearch_cluster.as_text,
          )
          // The index name varies, so put the name of the example in its place
          doc_document_delete.delete_user(opensearch, index)
          |> string.replace(index, "users")
          |> Ok
        }

        // Assert
        reported
        |> should
        |> be_equal(Ok(
          "Error: OpenSearch rejected the request with status 404: {\"_index\":\"users\",\"_id\":\"123\",\"_version\":1,\"result\":\"not_found\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1}",
        ))
        |> or_fail_with("A missing document gets a 404 with not_found")
      }),
    ]),
    group("document.create_index", [
      it("create users index answers acknowledged", fn() {
        // Act
        let created = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          // The index name varies, so put the name of the example in its place
          doc_document_create_index.create_users_index(opensearch, index)
          |> result.map(string.replace(_, index, "users"))
          |> opensearch_cluster.as_text
        }

        // Assert
        created
        |> should
        |> be_equal(Ok(
          "{\"acknowledged\":true,\"shards_acknowledged\":true,\"index\":\"users\"}",
        ))
        |> or_fail_with("create users index answers acknowledged")
      }),
      it("create users index maps the email as a keyword", fn() {
        // Act
        let mapped = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            doc_document_create_index.create_users_index(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          use body <- result.try(
            client.send_request(
              opensearch,
              http.Get,
              "/" <> index <> "/_mapping",
              "",
            )
            |> opensearch_cluster.as_text,
          )
          json.parse(
            body,
            decode.at(
              [index, "mappings", "properties", "email", "type"],
              decode.string,
            ),
          )
          |> result.replace_error("Unexpected mapping: " <> body)
        }

        // Assert
        mapped
        |> should
        |> be_equal(Ok("keyword"))
        |> or_fail_with("The mapping of the example should be in place")
      }),
      it("create users index of an existing index is a 400", fn() {
        // Act
        let created = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            doc_document_create_index.create_users_index(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          doc_document_create_index.create_users_index(opensearch, index)
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        created
        |> should
        |> be_equal(Ok(Error(Ok(#("resource_already_exists_exception", 400)))))
        |> or_fail_with("The second create should fail")
      }),
    ]),
    group("document.delete_index", [
      it("delete old index reports success", fn() {
        // Act
        let reported = {
          use opensearch, index <- opensearch_cluster.with_index("old_index")
          use _ <- result.try(
            document.create_index(opensearch, index, "{}")
            |> opensearch_cluster.as_text,
          )
          Ok(doc_document_delete_index.delete_old_index(opensearch, index))
        }

        // Assert
        reported
        |> should
        |> be_equal(Ok("Index deleted"))
        |> or_fail_with("delete old index reports success")
      }),
      it("delete old index reports the 404 body of a missing index", fn() {
        // Act
        let reported = {
          use opensearch, index <- opensearch_cluster.with_index("old_index")
          // The index name varies, so put the name of the example in its place
          doc_document_delete_index.delete_old_index(opensearch, index)
          |> string.replace(index, "old_index")
          |> Ok
        }

        // Assert
        reported
        |> should
        |> be_equal(Ok(
          "Error: OpenSearch rejected the request with status 404: {\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [old_index]\",\"index\":\"old_index\",\"resource.id\":\"old_index\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [old_index]\",\"index\":\"old_index\",\"resource.id\":\"old_index\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}",
        ))
        |> or_fail_with("A missing index gets a 404")
      }),
    ]),
    group("document.bulk", [
      it("bulk index users stores both users with no errors", fn() {
        // Act
        let loaded = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use body <- result.try(
            doc_document_bulk.bulk_index_users(opensearch, index)
            |> opensearch_cluster.as_text,
          )
          use errors <- result.try(
            json.parse(body, decode.at(["errors"], decode.bool))
            |> result.replace_error("Unexpected bulk response: " <> body),
          )
          use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
          use counted <- result.try(
            client.send_request(
              opensearch,
              http.Get,
              "/" <> index <> "/_count",
              "",
            )
            |> opensearch_cluster.as_text,
          )
          json.parse(counted, decode.at(["count"], decode.int))
          |> result.map(fn(count) { #(errors, count) })
          |> result.replace_error("Unexpected count response: " <> counted)
        }

        // Assert
        loaded
        |> should
        |> be_equal(Ok(#(False, 2)))
        |> or_fail_with("Alice and Bob should be stored")
      }),
    ]),
    group("query module: quick start", [
      it("search by name finds Alice", fn() {
        // Act
        let found =
          found_ids("users", users, doc_query_quick_start.search_by_name)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches the name")
      }),
      it("search by status finds the active user", fn() {
        // Act
        let found =
          found_ids("users", users, doc_query_quick_start.search_by_status)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice is active")
      }),
    ]),
    group("query module: custom query", [
      it("build bool query returns the bool query json", fn() {
        // Act
        let query_json = doc_query_custom.build_bool_query()

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"name\":\"Alice\"}}]}}}",
        )
        |> or_fail_with("build bool query returns the bool query json")
      }),
      it("the bool query finds Alice", fn() {
        // Act
        let found =
          found_ids("users", users, fn(opensearch, index) {
            document.search(
              opensearch,
              index,
              doc_query_custom.build_bool_query(),
            )
          })

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches the bool query")
      }),
    ]),
    group("query.match_all", [
      it("search all users finds every user", fn() {
        // Act
        let found =
          found_ids("users", users, doc_query_match_all.search_all_users)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1", "2"]))
        |> or_fail_with("match_all finds Alice and Bob")
      }),
    ]),
    group("query.term", [
      it("search active users finds the active user", fn() {
        // Act
        let found =
          found_ids("users", users, doc_query_term.search_active_users)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice is active")
      }),
    ]),
    group("query.range", [
      it("search products by price finds the product at 50", fn() {
        // Act
        let found =
          found_ids(
            "products",
            products,
            doc_query_range.search_products_by_price,
          )

        // Assert
        found
        |> should
        |> be_equal(Ok(["2"]))
        |> or_fail_with("Only the lamp costs between 10 and 100")
      }),
    ]),
    group("query.match", [
      it("search users named alice finds Alice", fn() {
        // Act
        let found =
          found_ids("users", users, doc_query_match.search_users_named_alice)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches the name")
      }),
    ]),
  ])
}
