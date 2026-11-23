//// Tests for the code blocks in this module's README.md.
////
//// Requests go to the one-shot server in `opensearch_test_server` on
//// 127.0.0.1 with a port from the operating system, not to a real
//// OpenSearch. The tests check the request each snippet sends and the result
//// it returns.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/int
import gleam/result
import opensearch_test_server.{Respond}
import snippets/readme_bulk_operations
import snippets/readme_client_setup
import snippets/readme_custom_queries
import snippets/readme_index_management
import snippets/readme_indexing_documents
import snippets/readme_quick_start
import snippets/readme_searching

pub fn tests() -> TestSuite {
  describe("README snippets", [
    group("Quick Start", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = readme_quick_start.create_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("quick start create client uses localhost 9200")
      }),
      it("index alice sends put to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(201, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_quick_start.index_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/123")))
        |> or_fail_with(
          "quick start index alice sends put to the document path",
        )
      }),
      it("index alice sends the user as json", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(201, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_quick_start.index_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok("{\"name\":\"Alice\",\"email\":\"alice@example.com\"}"))
        |> or_fail_with("quick start index alice sends the user as json")
      }),
      it("search for alice sends a match query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_quick_start.search_for_alice(opensearch)

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
        |> or_fail_with("quick start search for alice sends a match query")
      }),
      it("search for alice returns the response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"hits\":{\"total\":1}}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = readme_quick_start.search_for_alice(opensearch)

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"hits\":{\"total\":1}}"))
        |> or_fail_with(
          "quick start search for alice returns the response body",
        )
      }),
      it("delete alice sends delete to the document path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_quick_start.delete_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("DELETE", "/users/_doc/123")))
        |> or_fail_with(
          "quick start delete alice sends delete to the document path",
        )
      }),
    ]),
    group("Client Setup", [
      it("create local client uses localhost 9200", fn() {
        // Act
        let opensearch = readme_client_setup.create_local_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("client setup create local client uses localhost 9200")
      }),
      it("create client with credentials keeps url", fn() {
        // Act
        let opensearch = readme_client_setup.create_client_with_credentials()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("https://user:pass@search.example.com:9200")
        |> or_fail_with("client setup create client with credentials keeps url")
      }),
      it("credentials in url send basic authorization header", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let port = opensearch_test_server.port(server)
        let opensearch =
          client.new("http://user:pass@127.0.0.1:" <> int.to_string(port))

        // Act
        let _ = readme_quick_start.search_for_alice(opensearch)

        // Assert: base64 of "user:pass"
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok(["Basic dXNlcjpwYXNz"]))
        |> or_fail_with(
          "client setup credentials in url send basic authorization header",
        )
      }),
    ]),
    group("Indexing Documents", [
      it("index user sends the user with age as json", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(201, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_indexing_documents.index_user(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"age\":30}",
        ))
        |> or_fail_with(
          "indexing documents index user sends the user with age as json",
        )
      }),
      it("index user reports success", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = readme_indexing_documents.index_user(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Indexed successfully")
        |> or_fail_with("indexing documents index user reports success")
      }),
      it("index user reports the error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            400,
            "{\"error\":\"bad request\"}",
          ))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = readme_indexing_documents.index_user(opensearch)

        // Assert
        result
        |> should
        |> be_equal("Error: {\"error\":\"bad request\"}")
        |> or_fail_with("indexing documents index user reports the error body")
      }),
    ]),
    group("Searching", [
      it("search by name sends a match query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_searching.search_by_name(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok("{\"query\":{\"match\":{\"name\":\"Alice\"}}}"))
        |> or_fail_with("searching search by name sends a match query")
      }),
      it("search by status sends a term query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_searching.search_by_status(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok("{\"query\":{\"term\":{\"status\":\"active\"}}}"))
        |> or_fail_with("searching search by status sends a term query")
      }),
      it("search by age sends a range query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_searching.search_by_age(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"query\":{\"range\":{\"age\":{\"gte\":\"18\",\"lte\":\"65\"}}}}",
        ))
        |> or_fail_with("searching search by age sends a range query")
      }),
      it("search all sends a match all query to the search path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_searching.search_all(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#("POST", "/users/_search", "{\"query\":{\"match_all\":{}}}")),
        )
        |> or_fail_with(
          "searching search all sends a match all query to the search path",
        )
      }),
    ]),
    group("Custom Queries", [
      it("search active users named alice sends a bool query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          readme_custom_queries.search_active_users_named_alice(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"name\":\"Alice\"}}],\"filter\":[{\"term\":{\"status\":\"active\"}}]}}}",
        ))
        |> or_fail_with(
          "custom queries search active users named alice sends a bool query",
        )
      }),
    ]),
    group("Index Management", [
      it("create users index sends the mapping", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_index_management.create_users_index(opensearch)

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
        |> or_fail_with("index management create users index sends the mapping")
      }),
      it("delete old index sends delete to the index path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_index_management.delete_old_index(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("DELETE", "/old_index")))
        |> or_fail_with(
          "index management delete old index sends delete to the index path",
        )
      }),
    ]),
    group("Bulk Operations", [
      it("bulk index users sends ndjson to the bulk path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = readme_bulk_operations.bulk_index_users(opensearch)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line_and_body)
        |> should
        |> be_equal(
          Ok(#(
            "POST",
            "/_bulk",
            "{ \"index\": { \"_index\": \"users\", \"_id\": \"1\" } }\n"
              <> "{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n"
              <> "{ \"index\": { \"_index\": \"users\", \"_id\": \"2\" } }\n"
              <> "{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n",
          )),
        )
        |> or_fail_with(
          "bulk operations bulk index users sends ndjson to the bulk path",
        )
      }),
    ]),
  ])
}
