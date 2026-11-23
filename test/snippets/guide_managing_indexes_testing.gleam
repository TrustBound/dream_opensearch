//// Guide: Managing indexes, test your code
////
//// Tests the index body with no cluster, and the setup code against a
//// cluster that cannot be reached.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import gleam/dynamic/decode
import gleam/json
import snippets/guide_managing_indexes_create.{
  books_index_body, ensure_books_index,
}

pub fn tests() -> TestSuite {
  describe("books index", [
    it("maps the author as a keyword", fn() {
      // Arrange
      let author_type =
        decode.at(["mappings", "properties", "author", "type"], decode.string)

      // Act
      let mapped = json.parse(books_index_body(), author_type)

      // Assert
      mapped
      |> should
      |> be_equal(Ok("keyword"))
      |> or_fail_with("term queries on author need a keyword field")
    }),
    it("returns the connection error when no cluster listens", fn() {
      // Arrange
      let opensearch = client.new("http://127.0.0.1:1")

      // Act
      let created = ensure_books_index(opensearch, "books")

      // Assert
      created
      |> should
      |> be_equal(Error("Connection failed: Connection refused"))
      |> or_fail_with("Expected a refused connection")
    }),
  ])
}
