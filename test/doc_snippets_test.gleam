//// Tests for the code blocks in the doc comments of `src/`, against the real
//// OpenSearch of `opensearch_cluster`.
////
//// Each example takes the index name as a parameter, so each test gets its
//// own index from `opensearch_cluster.with_index` and deletes it at the end.
//// The tests check what each example stores, finds or returns.

import dream_opensearch/client.{type Client, type OpenSearchError, send_request}
import dream_opensearch/document.{create_index}
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode.{at, bool, subfield, success}
import gleam/http.{Get}
import gleam/int.{to_string}
import gleam/json.{parse}
import gleam/list.{sort, try_map}
import gleam/result.{map, map_error, replace_error, try}
import gleam/string.{compare, replace}
import opensearch_cluster.{
  as_text, base_url_of, client_for, error_type_and_status, refresh,
  rejected_body, with_index,
}
import opensearch_test_server.{unused_port}
import snippets/doc_client_describe_error.{health_line}
import snippets/doc_client_new.{
  create_client_with_credentials, create_local_client,
}
import snippets/doc_client_quick_start
import snippets/doc_client_send_request.{get_user}
import snippets/doc_document_bulk.{bulk_index_users}
import snippets/doc_document_create_index.{create_users_index}
import snippets/doc_document_delete.{delete_user}
import snippets/doc_document_delete_index.{delete_old_index}
import snippets/doc_document_index
import snippets/doc_document_quick_start
import snippets/doc_document_search.{search_for_alice}
import snippets/doc_query_custom.{build_bool_query}
import snippets/doc_query_match.{search_users_named_alice}
import snippets/doc_query_match_all.{search_all_users}
import snippets/doc_query_quick_start.{search_by_name, search_by_status}
import snippets/doc_query_range.{search_products_by_price}
import snippets/doc_query_term.{search_active_users}

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
  use _ <- try(
    try_map(documents, fn(entry) {
      document.index(opensearch, index, entry.0, entry.1)
    })
    |> as_text,
  )
  refresh(opensearch, index)
}

/// Runs `search` on a new index with `documents`, and returns the IDs of the
/// hits, sorted.
fn found_ids(
  prefix: String,
  documents: List(#(String, String)),
  search: fn(Client, String) -> Result(String, OpenSearchError),
) -> Result(List(String), String) {
  use opensearch, index <- with_index(prefix)
  use Nil <- try(load(opensearch, index, documents))
  use body <- try(search(opensearch, index) |> as_text)
  parse(body, at(["hits", "hits"], decode.list(at(["_id"], decode.string))))
  |> map(sort(_, compare))
  |> replace_error("Unexpected search response: " <> body)
}

/// The value of the field `field` in the `_source` of document 123 of
/// `index`.
fn stored_field(
  opensearch: Client,
  index: String,
  field: String,
) -> Result(String, String) {
  use body <- try(
    send_request(opensearch, Get, "/" <> index <> "/_doc/123", "")
    |> as_text,
  )
  parse(body, at(["_source", field], decode.string))
  |> replace_error("Unexpected document: " <> body)
}

/// The `result` field of an index or delete response.
fn result_field(body: String) -> Result(String, String) {
  parse(body, at(["result"], decode.string))
  |> replace_error("Unexpected response: " <> body)
}

pub fn tests() -> TestSuite {
  describe("doc comment snippets", [
    group("client module", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_client_quick_start.create_client()

        // Assert
        opensearch
        |> map(base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice creates the document 123 with her name", fn() {
        // Act
        let stored = {
          use opensearch, index <- with_index("users")
          use body <- try(
            doc_client_quick_start.index_alice(opensearch, index)
            |> as_text,
          )
          use outcome <- try(result_field(body))
          use name <- try(stored_field(opensearch, index, "name"))
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
        let line = health_line(opensearch)

        // Assert
        line
        |> should
        |> be_equal("OpenSearch is healthy")
        |> or_fail_with("health line says OpenSearch is healthy")
      }),
      it("health line describes a refused connection", fn() {
        // Arrange
        let opensearch =
          client_for("http://127.0.0.1:" <> to_string(unused_port()))

        // Act
        let line = health_line(opensearch)

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
        let opensearch = create_local_client()

        // Assert
        opensearch
        |> map(base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create local client uses localhost 9200")
      }),
      it("create client with credentials keeps the url", fn() {
        // Act
        let opensearch = create_client_with_credentials()

        // Assert
        opensearch
        |> map(base_url_of)
        |> should
        |> be_equal(Ok("https://search.example.com:9200"))
        |> or_fail_with("create client with credentials keeps the url")
      }),
    ]),
    group("client.send_request", [
      it("get user returns the stored document", fn() {
        // Act
        let fetched = {
          use opensearch, index <- with_index("users")
          use _ <- try(
            document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
            |> as_text,
          )
          use body <- try(
            get_user(opensearch, index)
            |> as_text,
          )
          let decoder = {
            use found <- decode.field("found", bool)
            use name <- subfield(["_source", "name"], decode.string)
            success(#(found, name))
          }
          parse(body, decoder)
          |> replace_error("Unexpected document: " <> body)
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
          use opensearch, index <- with_index("users")
          use _ <- try(
            create_index(opensearch, index, "{}")
            |> as_text,
          )
          get_user(opensearch, index)
          |> rejected_body
          |> map_error(parse(_, at(["found"], bool)))
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
        |> map(base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice stores her email", fn() {
        // Act
        let stored = {
          use opensearch, index <- with_index("users")
          use _ <- try(
            doc_document_quick_start.index_alice(opensearch, index)
            |> as_text,
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
          use opensearch, index <- with_index("users")
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
        let found = found_ids("users", users, search_for_alice)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches")
      }),
      it("search for alice in a missing index is a 404", fn() {
        // Act
        let found = {
          use opensearch, index <- with_index("users")
          search_for_alice(opensearch, index)
          |> map_error(error_type_and_status)
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
          use opensearch, index <- with_index("users")
          use _ <- try(
            document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
            |> as_text,
          )
          Ok(delete_user(opensearch, index))
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
          use opensearch, index <- with_index("users")
          use _ <- try(
            create_index(opensearch, index, "{}")
            |> as_text,
          )
          // The index name varies, so put the name of the example in its place
          delete_user(opensearch, index)
          |> replace(index, "users")
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
          use opensearch, index <- with_index("users")
          // The index name varies, so put the name of the example in its place
          create_users_index(opensearch, index)
          |> map(replace(_, index, "users"))
          |> as_text
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
          use opensearch, index <- with_index("users")
          use _ <- try(
            create_users_index(opensearch, index)
            |> as_text,
          )
          use body <- try(
            send_request(opensearch, Get, "/" <> index <> "/_mapping", "")
            |> as_text,
          )
          parse(
            body,
            at(
              [index, "mappings", "properties", "email", "type"],
              decode.string,
            ),
          )
          |> replace_error("Unexpected mapping: " <> body)
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
          use opensearch, index <- with_index("users")
          use _ <- try(
            create_users_index(opensearch, index)
            |> as_text,
          )
          create_users_index(opensearch, index)
          |> map_error(error_type_and_status)
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
          use opensearch, index <- with_index("old_index")
          use _ <- try(
            create_index(opensearch, index, "{}")
            |> as_text,
          )
          Ok(delete_old_index(opensearch, index))
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
          use opensearch, index <- with_index("old_index")
          // The index name varies, so put the name of the example in its place
          delete_old_index(opensearch, index)
          |> replace(index, "old_index")
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
          use opensearch, index <- with_index("users")
          use body <- try(
            bulk_index_users(opensearch, index)
            |> as_text,
          )
          use errors <- try(
            parse(body, at(["errors"], bool))
            |> replace_error("Unexpected bulk response: " <> body),
          )
          use Nil <- try(refresh(opensearch, index))
          use counted <- try(
            send_request(opensearch, Get, "/" <> index <> "/_count", "")
            |> as_text,
          )
          parse(counted, at(["count"], decode.int))
          |> map(fn(count) { #(errors, count) })
          |> replace_error("Unexpected count response: " <> counted)
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
        let found = found_ids("users", users, search_by_name)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches the name")
      }),
      it("search by status finds the active user", fn() {
        // Act
        let found = found_ids("users", users, search_by_status)

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
        let query_json = build_bool_query()

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
            document.search(opensearch, index, build_bool_query())
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
        let found = found_ids("users", users, search_all_users)

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
        let found = found_ids("users", users, search_active_users)

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
        let found = found_ids("products", products, search_products_by_price)

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
        let found = found_ids("users", users, search_users_named_alice)

        // Assert
        found
        |> should
        |> be_equal(Ok(["1"]))
        |> or_fail_with("Only Alice matches the name")
      }),
    ]),
  ])
}
