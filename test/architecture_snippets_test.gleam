//// Tests for the dream_opensearch snippet in docs/reference/architecture.md.
////
//// Requests go to the one-shot server in `opensearch_test_server`, not to a
//// real OpenSearch.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/types.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/result
import opensearch_test_server.{Respond}
import snippets/architecture_opensearch

pub fn tests() -> TestSuite(Nil) {
  describe("architecture snippet", [
    it("create client uses localhost 9200", fn() {
      // Arrange
      let opensearch = architecture_opensearch.create_client()

      // Act
      let base_url = opensearch.base_url

      // Assert
      base_url
      |> should
      |> be_equal("http://localhost:9200")
      |> or_fail_with("create client uses localhost 9200")
    }),
    it("index log entry sends put to the document path", fn() {
      // Arrange
      let server = opensearch_test_server.start(Respond(201, "{}"))
      let opensearch = client.new(opensearch_test_server.base_url(server))

      // Act
      let _ = architecture_opensearch.index_log_entry(opensearch, "Started")

      // Assert
      opensearch_test_server.await_request(server)
      |> result.map(opensearch_test_server.request_line)
      |> should
      |> be_equal(Ok(#("PUT", "/logs/_doc/doc-id-123")))
      |> or_fail_with("index log entry sends put to the document path")
    }),
    it("index log entry sends the message as json", fn() {
      // Arrange
      let server = opensearch_test_server.start(Respond(201, "{}"))
      let opensearch = client.new(opensearch_test_server.base_url(server))

      // Act
      let _ = architecture_opensearch.index_log_entry(opensearch, "Started")

      // Assert
      opensearch_test_server.await_request(server)
      |> result.map(opensearch_test_server.request_body)
      |> should
      |> be_equal(Ok("{\"message\":\"Started\"}"))
      |> or_fail_with("index log entry sends the message as json")
    }),
    it("index log entry returns the response body", fn() {
      // Arrange
      let server =
        opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
      let opensearch = client.new(opensearch_test_server.base_url(server))

      // Act
      let result =
        architecture_opensearch.index_log_entry(opensearch, "Started")

      // Assert
      result
      |> should
      |> be_equal(Ok("{\"result\":\"created\"}"))
      |> or_fail_with("index log entry returns the response body")
    }),
  ])
}
