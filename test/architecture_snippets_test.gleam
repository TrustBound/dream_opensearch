//// Tests for the dream_opensearch snippet of the architecture reference,
//// against the real OpenSearch of `opensearch_cluster`. Each test uses its
//// own index and deletes it.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result
import gleam/string
import opensearch_cluster
import snippets/architecture_opensearch

pub fn tests() -> TestSuite {
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
    it("index log entry stores the message under doc-id-123", fn() {
      // Act
      let stored = {
        use opensearch, index <- opensearch_cluster.with_index("logs")
        use _ <- result.try(architecture_opensearch.index_log_entry(
          opensearch,
          index,
          "Started",
        ))
        use body <- result.try(client.send_request(
          opensearch,
          http.Get,
          "/" <> index <> "/_doc/doc-id-123",
          "",
        ))
        json.parse(body, decode.at(["_source", "message"], decode.string))
        |> result.replace_error("Unexpected document: " <> body)
      }

      // Assert
      stored
      |> should
      |> be_equal(Ok("Started"))
      |> or_fail_with("The message should be stored")
    }),
    it("index log entry returns the created response body", fn() {
      // Act
      let answered = {
        use opensearch, index <- opensearch_cluster.with_index("logs")
        // The index name varies, so put the name of the example in its place
        architecture_opensearch.index_log_entry(opensearch, index, "Started")
        |> result.map(string.replace(_, index, "logs"))
      }

      // Assert
      answered
      |> should
      |> be_equal(Ok(
        "{\"_index\":\"logs\",\"_id\":\"doc-id-123\",\"_version\":1,\"result\":\"created\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1}",
      ))
      |> or_fail_with("index log entry returns the response body")
    }),
  ])
}
