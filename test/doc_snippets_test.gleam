//// Tests for the code blocks in the doc comments of `src/`.
////
//// Requests go to the one-shot server in `opensearch_test_server` on
//// 127.0.0.1, not to a real OpenSearch. The tests check the request each
//// snippet sends and the result it returns.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/result
import opensearch_test_server.{Respond}
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

pub fn tests() -> TestSuite {
  describe("doc comment snippets", [
    group("client module", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_client_quick_start.create_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice sends the user to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_client_quick_start.index_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/123", "{\"name\":\"Alice\"}")))
        |> or_fail_with("index alice sends the user to the document path")
      }),
      it("index alice returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_client_quick_start.index_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"result\":\"created\"}"))
        |> or_fail_with("index alice returns the response body")
      }),
    ]),
    group("client.new", [
      it("create local client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_client_new.create_local_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("create local client uses localhost 9200")
      }),
      it("create client with credentials keeps the url", fn() {
        // Act
        let opensearch = doc_client_new.create_client_with_credentials()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("https://user:pass@search.example.com:9200")
        |> or_fail_with("create client with credentials keeps the url")
      }),
    ]),
    group("client.send_request", [
      it("get user sends get to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_client_send_request.get_user(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(Ok(#("GET", "/users/_doc/123", "")))
        |> or_fail_with("get user sends get to the document path")
      }),
      it("get user returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"found\":true}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_client_send_request.get_user(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"found\":true}"))
        |> or_fail_with("get user returns the response body")
      }),
    ]),
    group("document module", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = doc_document_quick_start.create_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("create client uses localhost 9200")
      }),
      it("index alice sends the user to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_quick_start.index_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "PUT",
            "/users/_doc/123",
            "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}",
          )),
        )
        |> or_fail_with("index alice sends the user to the document path")
      }),
      it("index alice returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_quick_start.index_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"result\":\"created\"}"))
        |> or_fail_with("index alice returns the response body")
      }),
    ]),
    group("document.index", [
      it("index alice sends the user to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_index.index_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "PUT",
            "/users/_doc/123",
            "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}",
          )),
        )
        |> or_fail_with("index alice sends the user to the document path")
      }),
      it("index alice reports success", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_index.index_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Indexed successfully")
        |> or_fail_with("index alice reports success")
      }),
      it("index alice reports the error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(400, "{\"status\":400}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_index.index_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Error: {\"status\":400}")
        |> or_fail_with("index alice reports the error body")
      }),
    ]),
    group("document.search", [
      it("search for alice sends a match query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_search.search_for_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/users/_search",
            "{\"query\":{\"match\":{\"name\":\"Alice\"}}}",
          )),
        )
        |> or_fail_with("search for alice sends a match query")
      }),
      it("search for alice returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"hits\":{\"total\":1}}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_search.search_for_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"hits\":{\"total\":1}}"))
        |> or_fail_with("search for alice returns the response body")
      }),
    ]),
    group("document.delete", [
      it("delete user sends delete to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_delete.delete_user(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(Ok(#("DELETE", "/users/_doc/123", "")))
        |> or_fail_with("delete user sends delete to the document path")
      }),
      it("delete user reports success", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"result\":\"deleted\"}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_delete.delete_user(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Document deleted")
        |> or_fail_with("delete user reports success")
      }),
      it("delete user reports the error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(404, "{\"found\":false}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_delete.delete_user(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Error: {\"found\":false}")
        |> or_fail_with("delete user reports the error body")
      }),
    ]),
    group("document.create_index", [
      it("create users index sends the mapping", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_create_index.create_users_index(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "PUT",
            "/users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"},\"email\":{\"type\":\"keyword\"}}}}",
          )),
        )
        |> or_fail_with("create users index sends the mapping")
      }),
      it("create users index returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"acknowledged\":true}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_create_index.create_users_index(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"acknowledged\":true}"))
        |> or_fail_with("create users index returns the response body")
      }),
    ]),
    group("document.delete_index", [
      it("delete old index sends delete to the index path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_delete_index.delete_old_index(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(Ok(#("DELETE", "/old_index", "")))
        |> or_fail_with("delete old index sends delete to the index path")
      }),
      it("delete old index reports success", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"acknowledged\":true}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_delete_index.delete_old_index(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Index deleted")
        |> or_fail_with("delete old index reports success")
      }),
      it("delete old index reports the error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(404, "{\"status\":404}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_delete_index.delete_old_index(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Error: {\"status\":404}")
        |> or_fail_with("delete old index reports the error body")
      }),
    ]),
    group("document.bulk", [
      it("bulk index users sends ndjson to the bulk path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_document_bulk.bulk_index_users(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/_bulk",
            "{ \"index\": { \"_index\": \"users\", \"_id\": \"1\" } }\n{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n{ \"index\": { \"_index\": \"users\", \"_id\": \"2\" } }\n{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n",
          )),
        )
        |> or_fail_with("bulk index users sends ndjson to the bulk path")
      }),
      it("bulk index users returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"errors\":false}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = doc_document_bulk.bulk_index_users(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"errors\":false}"))
        |> or_fail_with("bulk index users returns the response body")
      }),
    ]),
    group("query module: quick start", [
      it("search by name sends a match query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_quick_start.search_by_name(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/users/_search",
            "{\"query\":{\"match\":{\"name\":\"Alice\"}}}",
          )),
        )
        |> or_fail_with("search by name sends a match query")
      }),
      it("search by status sends a term query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_quick_start.search_by_status(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/users/_search",
            "{\"query\":{\"term\":{\"status\":\"active\"}}}",
          )),
        )
        |> or_fail_with("search by status sends a term query")
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
    ]),
    group("query.match_all", [
      it("search all users sends a match all query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_match_all.search_all_users(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#("POST", "/users/_search", "{\"query\":{\"match_all\":{}}}")),
        )
        |> or_fail_with("search all users sends a match all query")
      }),
    ]),
    group("query.term", [
      it("search active users sends a term query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_term.search_active_users(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/users/_search",
            "{\"query\":{\"term\":{\"status\":\"active\"}}}",
          )),
        )
        |> or_fail_with("search active users sends a term query")
      }),
    ]),
    group("query.range", [
      it("search products by price sends a range query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_range.search_products_by_price(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/products/_search",
            "{\"query\":{\"range\":{\"price\":{\"gte\":\"10\",\"lte\":\"100\"}}}}",
          )),
        )
        |> or_fail_with("search products by price sends a range query")
      }),
    ]),
    group("query.match", [
      it("search users named alice sends a match query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = doc_query_match.search_users_named_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/users/_search",
            "{\"query\":{\"match\":{\"name\":\"Alice\"}}}",
          )),
        )
        |> or_fail_with("search users named alice sends a match query")
      }),
    ]),
  ])
}
