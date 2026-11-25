//// Guide: Handling errors, test your code
////
//// Tests the error handling with the exact strings the client returns.

import dream_opensearch/client
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/result
import snippets/guide_handling_errors_classify.{
  BadConfiguration, Rejected, Unreachable, classify,
}

pub fn tests() -> TestSuite {
  describe("classify", [
    it("reads a missing index from its error body", fn() {
      // Arrange
      let body =
        "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}"

      // Act
      let error = classify(body)

      // Assert
      error
      |> should
      |> be_equal(Rejected(
        404,
        "index_not_found_exception",
        "no such index [books]",
      ))
      |> or_fail_with("Expected a 404 rejection")
    }),
    it("calls a refused connection unreachable", fn() {
      // Arrange
      let opensearch = client.new("http://127.0.0.1:1")

      // Act
      let error =
        document.delete(opensearch, "books", "1")
        |> result.map_error(classify)

      // Assert
      error
      |> should
      |> be_equal(Error(Unreachable("Connection refused")))
      |> or_fail_with("Nothing listens on port 1")
    }),
    it("calls a URL with no scheme a bad configuration", fn() {
      // Arrange
      let opensearch = client.new("localhost:9200")

      // Act
      let error =
        document.delete(opensearch, "books", "1")
        |> result.map_error(classify)

      // Assert
      error
      |> should
      |> be_equal(
        Error(BadConfiguration("Invalid OpenSearch URL: the URL has no host")),
      )
      |> or_fail_with("A URL needs http:// or https://")
    }),
  ])
}
