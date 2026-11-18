//// Black-box tests for `dream_opensearch/query`.
////
//// Every builder returns a JSON string, so each test pins the whole string.

import dream_opensearch/query
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/types.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/string

pub fn tests() -> TestSuite(Nil) {
  describe("dream_opensearch/query", [
    group("match_all", [
      it("returns match all query json", fn() {
        // Arrange
        // (no input)

        // Act
        let query_json = query.match_all()

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"match_all\":{}}}")
        |> or_fail_with("match_all returns match all query json")
      }),
    ]),
    group("term", [
      it("returns term query json", fn() {
        // Arrange
        let field = "status"
        let value = "published"

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"term\":{\"status\":\"published\"}}}")
        |> or_fail_with("term returns term query json")
      }),
      it("with empty field and value returns empty keys", fn() {
        // Arrange
        let field = ""
        let value = ""

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"term\":{\"\":\"\"}}}")
        |> or_fail_with("term with empty field and value returns empty keys")
      }),
      it("with quote and backslash in value escapes them", fn() {
        // Arrange
        let field = "name"
        let value = "say \"hi\" \\ bye"

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"term\":{\"name\":\"say \\\"hi\\\" \\\\ bye\"}}}",
        )
        |> or_fail_with("term with quote and backslash in value escapes them")
      }),
      it("with quote in field escapes it", fn() {
        // Arrange
        let field = "a\"b"
        let value = "x"

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"term\":{\"a\\\"b\":\"x\"}}}")
        |> or_fail_with("term with quote in field escapes it")
      }),
      it("with newline tab and control character escapes them", fn() {
        // Arrange
        let field = "notes"
        let value = "line1\nline2\ttab\u{0001}"

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"term\":{\"notes\":\"line1\\nline2\\ttab\\u0001\"}}}",
        )
        |> or_fail_with(
          "term with newline tab and control character escapes them",
        )
      }),
      it("with unicode value keeps it", fn() {
        // Arrange
        let field = "名前"
        let value = "zoë 日本 🎉"

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"term\":{\"名前\":\"zoë 日本 🎉\"}}}")
        |> or_fail_with("term with unicode value keeps it")
      }),
      it("with json like value keeps it as a string", fn() {
        // Arrange
        let field = "status"
        let value = "\"},\"match_all\":{\""

        // Act
        let query_json = query.term(field, value)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"term\":{\"status\":\"\\\"},\\\"match_all\\\":{\\\"\"}}}",
        )
        |> or_fail_with("term with json like value keeps it as a string")
      }),
      it("with very long value keeps whole value", fn() {
        // Arrange
        let value = string.repeat("x", 100_000)

        // Act
        let query_json = query.term("f", value)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"term\":{\"f\":\""
          <> string.repeat("x", 100_000)
          <> "\"}}}",
        )
        |> or_fail_with("term with very long value keeps whole value")
      }),
    ]),
    group("range", [
      it("returns range query json", fn() {
        // Arrange
        let field = "price"
        let gte = "10"
        let lte = "100"

        // Act
        let query_json = query.range(field, gte, lte)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"range\":{\"price\":{\"gte\":\"10\",\"lte\":\"100\"}}}}",
        )
        |> or_fail_with("range returns range query json")
      }),
      it("with date bounds returns them as strings", fn() {
        // Arrange
        let field = "created_at"
        let gte = "2026-01-01T00:00:00Z"
        let lte = "now"

        // Act
        let query_json = query.range(field, gte, lte)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"range\":{\"created_at\":{\"gte\":\"2026-01-01T00:00:00Z\",\"lte\":\"now\"}}}}",
        )
        |> or_fail_with("range with date bounds returns them as strings")
      }),
      it("with empty bounds returns empty strings", fn() {
        // Arrange
        let field = "age"
        let gte = ""
        let lte = ""

        // Act
        let query_json = query.range(field, gte, lte)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"range\":{\"age\":{\"gte\":\"\",\"lte\":\"\"}}}}",
        )
        |> or_fail_with("range with empty bounds returns empty strings")
      }),
      it("with quotes backslash and newline escapes them", fn() {
        // Arrange
        let field = "f\"x"
        let gte = "a\\b"
        let lte = "c\nd"

        // Act
        let query_json = query.range(field, gte, lte)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"range\":{\"f\\\"x\":{\"gte\":\"a\\\\b\",\"lte\":\"c\\nd\"}}}}",
        )
        |> or_fail_with("range with quotes backslash and newline escapes them")
      }),
      it("with unicode bounds keeps them", fn() {
        // Arrange
        let field = "名前"
        let gte = "α"
        let lte = "ω🎉"

        // Act
        let query_json = query.range(field, gte, lte)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"range\":{\"名前\":{\"gte\":\"α\",\"lte\":\"ω🎉\"}}}}",
        )
        |> or_fail_with("range with unicode bounds keeps them")
      }),
    ]),
    group("match", [
      it("returns match query json", fn() {
        // Arrange
        let field = "title"
        let text = "hello world"

        // Act
        let query_json = query.match(field, text)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"match\":{\"title\":\"hello world\"}}}")
        |> or_fail_with("match returns match query json")
      }),
      it("with empty field and text returns empty keys", fn() {
        // Arrange
        let field = ""
        let text = ""

        // Act
        let query_json = query.match(field, text)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"match\":{\"\":\"\"}}}")
        |> or_fail_with("match with empty field and text returns empty keys")
      }),
      it("with quote backslash and newline escapes them", fn() {
        // Arrange
        let field = "body"
        let text = "he said \"no\"\\\nthen left"

        // Act
        let query_json = query.match(field, text)

        // Assert
        query_json
        |> should
        |> be_equal(
          "{\"query\":{\"match\":{\"body\":\"he said \\\"no\\\"\\\\\\nthen left\"}}}",
        )
        |> or_fail_with("match with quote backslash and newline escapes them")
      }),
      it("with unicode text keeps it", fn() {
        // Arrange
        let field = "title"
        let text = "café 東京 🎉"

        // Act
        let query_json = query.match(field, text)

        // Assert
        query_json
        |> should
        |> be_equal("{\"query\":{\"match\":{\"title\":\"café 東京 🎉\"}}}")
        |> or_fail_with("match with unicode text keeps it")
      }),
    ]),
  ])
}
