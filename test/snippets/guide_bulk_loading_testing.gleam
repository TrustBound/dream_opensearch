//// Guide: Loading documents in bulk, test your code
////
//// Tests the bulk body and the reading of a bulk response with no cluster.

import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_bulk_loading_books.{
  Book, FailedItem, bulk_body, failed_items,
}

pub fn tests() -> TestSuite {
  describe("book loading", [
    it("ends every line of the bulk body with a newline", fn() {
      // Act
      let body =
        bulk_body("books", [Book("1", "Programming Gleam", "Jo Lee", 2024)])

      // Assert
      body
      |> should
      |> be_equal(
        "{\"index\":{\"_index\":\"books\",\"_id\":\"1\"}}\n"
        <> "{\"title\":\"Programming Gleam\",\"author\":\"Jo Lee\",\"year\":2024}\n",
      )
      |> or_fail_with("Expected an action line and a document line")
    }),
    it("finds the item that failed", fn() {
      // Arrange
      let response =
        "{\"took\":4,\"errors\":true,\"items\":["
        <> "{\"index\":{\"_id\":\"1\",\"status\":201}},"
        <> "{\"index\":{\"_id\":\"2\",\"status\":429,\"error\":"
        <> "{\"type\":\"es_rejected_execution_exception\",\"reason\":\"busy\"}}}]}"

      // Act
      let failed = failed_items(response)

      // Assert
      failed
      |> should
      |> be_equal(
        Ok([FailedItem("2", 429, "es_rejected_execution_exception", "busy")]),
      )
      |> or_fail_with("Only book 2 failed")
    }),
  ])
}
