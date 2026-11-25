//// Guide: Searching an index, test your code
////
//// Tests a query builder and a response reader with no cluster.

import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_searching_books.{
  Book, SearchResult, search_result_from_response,
}
import snippets/guide_searching_bool.{in_stock_query}

pub fn tests() -> TestSuite {
  describe("book search", [
    it("asks for the second page of ten", fn() {
      // Act
      let query_json = in_stock_query("gleam", 2020, 2, 10)

      // Assert
      query_json
      |> should
      |> be_equal(
        "{\"query\":{\"bool\":{\"must\":[{\"match\":{\"title\":\"gleam\"}}],"
        <> "\"filter\":[{\"term\":{\"in_stock\":true}},"
        <> "{\"range\":{\"year\":{\"gte\":2020}}}]}},"
        <> "\"from\":10,\"size\":10,\"sort\":[{\"year\":{\"order\":\"desc\"}}]}",
      )
      |> or_fail_with("Page 2 of 10 should start at hit 10")
    }),
    it("reads the total and the books of a response", fn() {
      // Arrange
      let body =
        "{\"hits\":{\"total\":{\"value\":12,\"relation\":\"eq\"},\"hits\":["
        <> "{\"_id\":\"7\",\"_source\":{\"title\":\"Gleam in Action\","
        <> "\"author\":\"Jo Lee\",\"year\":2024,\"in_stock\":true}}]}}"

      // Act
      let result = search_result_from_response(body)

      // Assert
      result
      |> should
      |> be_equal(
        Ok(
          SearchResult(total: 12, books: [
            Book(
              id: "7",
              title: "Gleam in Action",
              author: "Jo Lee",
              year: 2024,
              in_stock: True,
            ),
          ]),
        ),
      )
      |> or_fail_with("Expected 12 matches and one book on this page")
    }),
  ])
}
