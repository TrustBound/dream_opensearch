//// Black-box tests for `dream_opensearch/document`.
////
//// Requests go to a one-shot server on 127.0.0.1 (see
//// `opensearch_test_server`), which records the request exactly as it
//// arrives and answers with the status and body each test chooses.

import dream_opensearch/client
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/types.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/result
import opensearch_test_server.{Respond}

pub fn tests() -> TestSuite(Nil) {
  describe("dream_opensearch/document", [
    group("index", [
      it("sends put to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/123")))
        |> or_fail_with("index sends put to expected path")
      }),
      it("sends given body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok("{\"name\":\"Alice\"}"))
        |> or_fail_with("index sends given body unchanged")
      }),
      it("with 201 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(201, "{\"result\":\"created\"}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"result\":\"created\"}"))
        |> or_fail_with("index with 201 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            400,
            "{\"error\":{\"type\":\"mapper_parsing_exception\"},\"status\":400}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        result
        |> should
        |> be_equal(Error(
          "{\"error\":{\"type\":\"mapper_parsing_exception\"},\"status\":400}",
        ))
        |> or_fail_with("index with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("index when nothing listens returns connection error")
      }),
    ]),
    group("search", [
      it("sends post to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("POST", "/users/_search")))
        |> or_fail_with("search sends post to expected path")
      }),
      it("sends given body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok("{\"query\":{\"match_all\":{}}}"))
        |> or_fail_with("search sends given body unchanged")
      }),
      it("with 200 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            200,
            "{\"hits\":{\"total\":{\"value\":0},\"hits\":[]}}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"hits\":{\"total\":{\"value\":0},\"hits\":[]}}"))
        |> or_fail_with("search with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            404,
            "{\"error\":{\"type\":\"index_not_found_exception\"},\"status\":404}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        result
        |> should
        |> be_equal(Error(
          "{\"error\":{\"type\":\"index_not_found_exception\"},\"status\":404}",
        ))
        |> or_fail_with("search with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("search when nothing listens returns connection error")
      }),
    ]),
    group("delete", [
      it("sends delete to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = document.delete(os_client, "users", "123")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("DELETE", "/users/_doc/123")))
        |> or_fail_with("delete sends delete to expected path")
      }),
      it("sends empty body", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = document.delete(os_client, "users", "123")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(""))
        |> or_fail_with("delete sends empty body")
      }),
      it("with 200 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"result\":\"deleted\"}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = document.delete(os_client, "users", "123")

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"result\":\"deleted\"}"))
        |> or_fail_with("delete with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            404,
            "{\"_id\":\"123\",\"result\":\"not_found\"}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = document.delete(os_client, "users", "123")

        // Assert
        result
        |> should
        |> be_equal(Error("{\"_id\":\"123\",\"result\":\"not_found\"}"))
        |> or_fail_with("delete with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result = document.delete(os_client, "users", "123")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("delete when nothing listens returns connection error")
      }),
    ]),
    group("create_index", [
      it("sends put to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.create_index(
            os_client,
            "users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
          )

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("PUT", "/users")))
        |> or_fail_with("create_index sends put to expected path")
      }),
      it("sends given body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.create_index(
            os_client,
            "users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
          )

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
        ))
        |> or_fail_with("create_index sends given body unchanged")
      }),
      it("with 200 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            200,
            "{\"acknowledged\":true,\"index\":\"users\"}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.create_index(
            os_client,
            "users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
          )

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"acknowledged\":true,\"index\":\"users\"}"))
        |> or_fail_with("create_index with 200 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            400,
            "{\"error\":{\"type\":\"resource_already_exists_exception\"},\"status\":400}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.create_index(
            os_client,
            "users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
          )

        // Assert
        result
        |> should
        |> be_equal(Error(
          "{\"error\":{\"type\":\"resource_already_exists_exception\"},\"status\":400}",
        ))
        |> or_fail_with("create_index with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result =
          document.create_index(
            os_client,
            "users",
            "{\"mappings\":{\"properties\":{\"name\":{\"type\":\"text\"}}}}",
          )

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with(
          "create_index when nothing listens returns connection error",
        )
      }),
    ]),
    group("delete_index", [
      it("sends delete to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = document.delete_index(os_client, "old_index")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("DELETE", "/old_index")))
        |> or_fail_with("delete_index sends delete to expected path")
      }),
      it("sends empty body", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = document.delete_index(os_client, "old_index")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(""))
        |> or_fail_with("delete_index sends empty body")
      }),
      it("with 200 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"acknowledged\":true}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = document.delete_index(os_client, "old_index")

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"acknowledged\":true}"))
        |> or_fail_with("delete_index with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            404,
            "{\"error\":{\"type\":\"index_not_found_exception\"},\"status\":404}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = document.delete_index(os_client, "old_index")

        // Assert
        result
        |> should
        |> be_equal(Error(
          "{\"error\":{\"type\":\"index_not_found_exception\"},\"status\":404}",
        ))
        |> or_fail_with("delete_index with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result = document.delete_index(os_client, "old_index")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with(
          "delete_index when nothing listens returns connection error",
        )
      }),
    ]),
    group("bulk", [
      it("sends post to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("POST", "/_bulk")))
        |> or_fail_with("bulk sends post to expected path")
      }),
      it("sends given body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
        ))
        |> or_fail_with("bulk sends given body unchanged")
      }),
      it("with 200 returns ok response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            200,
            "{\"took\":3,\"errors\":false,\"items\":[]}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"took\":3,\"errors\":false,\"items\":[]}"))
        |> or_fail_with("bulk with 200 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            400,
            "{\"error\":{\"type\":\"illegal_argument_exception\"},\"status\":400}",
          ))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        result
        |> should
        |> be_equal(Error(
          "{\"error\":{\"type\":\"illegal_argument_exception\"},\"status\":400}",
        ))
        |> or_fail_with("bulk with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("bulk when nothing listens returns connection error")
      }),
    ]),
  ])
}
