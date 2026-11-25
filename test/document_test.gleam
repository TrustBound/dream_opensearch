//// Black-box tests for `dream_opensearch/document`.
////
//// The answers come from the real OpenSearch of `opensearch_cluster`. Each
//// test that writes uses its own index from `opensearch_cluster.with_index`
//// and deletes it at the end.
////
//// The request that each function sends (method, path and body as they
//// arrive) is checked on a one-shot server on 127.0.0.1 (see
//// `opensearch_test_server`), because a cluster does not report the
//// requests it got.

import dream_opensearch/client
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string
import opensearch_cluster
import opensearch_test_server.{Respond}

pub fn tests() -> TestSuite {
  describe("dream_opensearch/document", [
    group("index", [
      it("sends put to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          // The index name varies, so put the name of the test in its place
          document.index(os_client, index, "123", "{\"name\":\"Alice\"}")
          |> result.map(string.replace(_, index, "users"))
          |> opensearch_cluster.as_text
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(
          "{\"_index\":\"users\",\"_id\":\"123\",\"_version\":1,\"result\":\"created\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1}",
        ))
        |> or_fail_with("index with 201 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Act
        let result =
          document.index(
            opensearch_cluster.client(),
            "Users",
            "123",
            "{\"name\":\"Alice\"}",
          )

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Rejected(
            status: 400,
            body: "{\"error\":{\"root_cause\":[{\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"}],\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"},\"status\":400}",
          )),
        )
        |> or_fail_with("index with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result =
          document.index(os_client, "users", "123", "{\"name\":\"Alice\"}")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with("index when nothing listens returns connection error")
      }),
    ]),
    group("search", [
      it("sends post to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.create_index(os_client, index, "{}")
            |> opensearch_cluster.as_text,
          )
          use body <- result.try(
            document.search(os_client, index, "{\"query\":{\"match_all\":{}}}")
            |> opensearch_cluster.as_text,
          )
          json.parse(body, decode.at(["hits", "total", "value"], decode.int))
          |> result.replace_error("Unexpected search response: " <> body)
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(0))
        |> or_fail_with("search with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          // The index name varies, so put the name of the test in its place
          document.search(os_client, index, "{\"query\":{\"match_all\":{}}}")
          |> opensearch_cluster.rejected_body
          |> result.map_error(string.replace(_, index, "users"))
          |> Ok
        }

        // Assert
        result
        |> should
        |> be_equal(
          Ok(Error(
            "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [users]\",\"index\":\"users\",\"resource.id\":\"users\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [users]\",\"index\":\"users\",\"resource.id\":\"users\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}",
          )),
        )
        |> or_fail_with("search with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result =
          document.search(os_client, "users", "{\"query\":{\"match_all\":{}}}")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with("search when nothing listens returns connection error")
      }),
    ]),
    group("delete", [
      it("sends delete to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.index(os_client, index, "123", "{\"name\":\"Alice\"}")
            |> opensearch_cluster.as_text,
          )
          // The index name varies, so put the name of the test in its place
          document.delete(os_client, index, "123")
          |> result.map(string.replace(_, index, "users"))
          |> opensearch_cluster.as_text
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(
          "{\"_index\":\"users\",\"_id\":\"123\",\"_version\":2,\"result\":\"deleted\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":1,\"_primary_term\":1}",
        ))
        |> or_fail_with("delete with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(
            document.create_index(os_client, index, "{}")
            |> opensearch_cluster.as_text,
          )
          // The index name varies, so put the name of the test in its place
          document.delete(os_client, index, "123")
          |> opensearch_cluster.rejected_body
          |> result.map_error(string.replace(_, index, "users"))
          |> Ok
        }

        // Assert
        result
        |> should
        |> be_equal(
          Ok(Error(
            "{\"_index\":\"users\",\"_id\":\"123\",\"_version\":1,\"result\":\"not_found\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1}",
          )),
        )
        |> or_fail_with("delete with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result = document.delete(os_client, "users", "123")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with("delete when nothing listens returns connection error")
      }),
    ]),
    group("create_index", [
      it("sends put to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          // The index name varies, so put the name of the test in its place
          document.create_index(os_client, index, "{}")
          |> result.map(string.replace(_, index, "users"))
          |> opensearch_cluster.as_text
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(
          "{\"acknowledged\":true,\"shards_acknowledged\":true,\"index\":\"users\"}",
        ))
        |> or_fail_with("create_index with 200 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Act
        let result =
          document.create_index(opensearch_cluster.client(), "Users", "{}")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Rejected(
            status: 400,
            body: "{\"error\":{\"root_cause\":[{\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"}],\"type\":\"invalid_index_name_exception\",\"reason\":\"Invalid index name [Users], must be lowercase\",\"index\":\"Users\",\"index_uuid\":\"_na_\"},\"status\":400}",
          )),
        )
        |> or_fail_with("create_index with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

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
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with(
          "create_index when nothing listens returns connection error",
        )
      }),
    ]),
    group("delete_index", [
      it("sends delete to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("old_index")
          use _ <- result.try(
            document.create_index(os_client, index, "{}")
            |> opensearch_cluster.as_text,
          )
          Ok(document.delete_index(os_client, index))
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(Ok("{\"acknowledged\":true}")))
        |> or_fail_with("delete_index with 200 returns ok response body")
      }),
      it("with 404 returns error response body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("old_index")
          // The index name varies, so put the name of the test in its place
          document.delete_index(os_client, index)
          |> opensearch_cluster.rejected_body
          |> result.map_error(string.replace(_, index, "old_index"))
          |> Ok
        }

        // Assert
        result
        |> should
        |> be_equal(
          Ok(Error(
            "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [old_index]\",\"index\":\"old_index\",\"resource.id\":\"old_index\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [old_index]\",\"index\":\"old_index\",\"resource.id\":\"old_index\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}",
          )),
        )
        |> or_fail_with("delete_index with 404 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result = document.delete_index(os_client, "old_index")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with(
          "delete_index when nothing listens returns connection error",
        )
      }),
    ]),
    group("bulk", [
      it("sends post to expected path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use body <- result.try(
            document.bulk(
              os_client,
              "{\"index\":{\"_index\":\""
                <> index
                <> "\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
            )
            |> opensearch_cluster.as_text,
          )
          json.parse(body, decode.at(["errors"], decode.bool))
          |> result.replace_error("Unexpected bulk response: " <> body)
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(False))
        |> or_fail_with("bulk with 200 returns ok response body")
      }),
      it("with 400 returns error response body", fn() {
        // Act
        let result = document.bulk(opensearch_cluster.client(), "{}")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Rejected(
            status: 400,
            body: "{\"error\":{\"root_cause\":[{\"type\":\"illegal_argument_exception\",\"reason\":\"The bulk request must be terminated by a newline [\\\\n]\"}],\"type\":\"illegal_argument_exception\",\"reason\":\"The bulk request must be terminated by a newline [\\\\n]\"},\"status\":400}",
          )),
        )
        |> or_fail_with("bulk with 400 returns error response body")
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result =
          document.bulk(
            os_client,
            "{\"index\":{\"_index\":\"users\",\"_id\":\"1\"}}\n{\"name\":\"Alice\"}\n",
          )

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with("bulk when nothing listens returns connection error")
      }),
    ]),
  ])
}
