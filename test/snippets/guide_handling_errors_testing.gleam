//// Guide: Handling errors, test your code
////
//// Tests the error handling with real errors of the client.

import dream_opensearch/client.{InvalidUrl, Rejected, Unavailable}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/result
import snippets/guide_handling_errors_classify.{
  ErrorDetails, error_details, worth_a_retry,
}

pub fn tests() -> TestSuite {
  describe("error handling", [
    it("reads a missing index from its error body", fn() {
      // Arrange
      let error =
        Rejected(
          status: 404,
          body: "{\"error\":{\"root_cause\":[{\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"}],\"type\":\"index_not_found_exception\",\"reason\":\"no such index [books]\",\"index\":\"books\",\"resource.id\":\"books\",\"resource.type\":\"index_or_alias\",\"index_uuid\":\"_na_\"},\"status\":404}",
        )

      // Act
      let details = error_details(error)

      // Assert
      details
      |> should
      |> be_equal(
        Ok(ErrorDetails("index_not_found_exception", "no such index [books]")),
      )
      |> or_fail_with("Expected a missing index")
    }),
    it("retries a refused connection", fn() {
      // Arrange
      // Nothing listens on port 1
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let retry =
        document.delete(opensearch, "books", "1")
        |> result.map_error(worth_a_retry)

      // Assert
      retry
      |> should
      |> be_equal(Error(True))
      |> or_fail_with("A refused connection is worth a retry")
    }),
    it("does not retry a URL with no scheme", fn() {
      // Act
      let created = client.new("localhost:9200")

      // Assert
      created
      |> result.map_error(fn(error) { #(error, worth_a_retry(error)) })
      |> should
      |> be_equal(
        Error(#(InvalidUrl("the URL scheme must be http or https"), False)),
      )
      |> or_fail_with("A URL needs http:// or https://")
    }),
    it("gives the reason of an unavailable cluster", fn() {
      // Arrange
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let deleted = document.delete(opensearch, "books", "1")

      // Assert
      deleted
      |> should
      |> be_equal(Error(Unavailable("Connection failed: Connection refused")))
      |> or_fail_with("Nothing listens on port 1")
    }),
  ])
}
