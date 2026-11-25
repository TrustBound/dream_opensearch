//// Proof against the real OpenSearch that the `document` functions keep
//// index names and document IDs whole: a document with a special ID is
//// stored under exactly that ID, found by it, and deleted, and the
//// document `a` next to it is not touched. An index name that OpenSearch
//// refuses comes back as the real error of OpenSearch.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/json
import gleam/result
import opensearch_cluster

/// What happened to a document with the ID `id`.
type RoundTrip {
  RoundTrip(
    /// The `_id` of the hits of a search for exactly `id`.
    found_ids: List(String),
    /// The `result` of the delete of `id`.
    deleted: String,
    /// The `_id` of every document left after the delete.
    left_ids: List(String),
  )
}

fn hit_ids(body: String) -> Result(List(String), String) {
  json.parse(
    body,
    decode.at(["hits", "hits"], decode.list(decode.at(["_id"], decode.string))),
  )
  |> result.replace_error("Unexpected search response: " <> body)
}

fn search_ids(
  opensearch: Client,
  index: String,
  query_json: String,
) -> Result(List(String), String) {
  use body <- result.try(
    document.search(opensearch, index, query_json) |> opensearch_cluster.as_text,
  )
  hit_ids(body)
}

fn ids_query(id: String) -> String {
  json.object([
    #(
      "query",
      json.object([
        #("ids", json.object([#("values", json.array([id], json.string))])),
      ]),
    ),
  ])
  |> json.to_string
}

fn delete_result(body: String) -> Result(String, String) {
  json.parse(body, decode.at(["result"], decode.string))
  |> result.replace_error("Unexpected delete response: " <> body)
}

/// Stores the documents `a` and `id`, searches for `id`, deletes `id`, and
/// lists the documents that are left.
fn round_trip(id: String) -> Result(RoundTrip, String) {
  use opensearch, index <- opensearch_cluster.with_index("ids")
  use _ <- result.try(
    document.index(opensearch, index, "a", "{\"n\":1}")
    |> opensearch_cluster.as_text,
  )
  use _ <- result.try(
    document.index(opensearch, index, id, "{\"n\":2}")
    |> opensearch_cluster.as_text,
  )
  use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
  use found_ids <- result.try(search_ids(opensearch, index, ids_query(id)))
  use deleted_body <- result.try(
    document.delete(opensearch, index, id) |> opensearch_cluster.as_text,
  )
  use deleted <- result.try(delete_result(deleted_body))
  use Nil <- result.try(opensearch_cluster.refresh(opensearch, index))
  use left_ids <- result.try(search_ids(
    opensearch,
    index,
    "{\"query\":{\"match_all\":{}}}",
  ))
  Ok(RoundTrip(found_ids:, deleted:, left_ids:))
}

fn error_type_and_reason(body: String) -> Result(#(String, String), String) {
  let decoder = {
    use error_type <- decode.subfield(["error", "type"], decode.string)
    use reason <- decode.subfield(["error", "reason"], decode.string)
    decode.success(#(error_type, reason))
  }
  json.parse(body, decoder)
  |> result.replace_error("Unexpected error body: " <> body)
}

fn create_refused_index(name: String) -> Result(#(String, String), String) {
  case document.create_index(opensearch_cluster.client(), name, "{}") {
    Ok(body) -> Error("OpenSearch created the index: " <> body)
    Error(client.Rejected(body:, ..)) -> error_type_and_reason(body)
    Error(error) -> Error(client.describe_error(error))
  }
}

pub fn tests() -> TestSuite {
  describe("dream_opensearch/document: path encoding on a real cluster", [
    group("document IDs", [
      it("stores, finds and deletes the ID a#b", fn() {
        // Act
        let trip = round_trip("a#b")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["a#b"], "deleted", ["a"])))
        |> or_fail_with("a#b must not touch document a")
      }),
      it("stores, finds and deletes the ID a/b", fn() {
        // Act
        let trip = round_trip("a/b")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["a/b"], "deleted", ["a"])))
        |> or_fail_with("a/b must be one ID")
      }),
      it("stores, finds and deletes the ID a?b=1", fn() {
        // Act
        let trip = round_trip("a?b=1")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["a?b=1"], "deleted", ["a"])))
        |> or_fail_with("a?b=1 must not become a query string")
      }),
      it("stores, finds and deletes the ID my id", fn() {
        // Act
        let trip = round_trip("my id")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["my id"], "deleted", ["a"])))
        |> or_fail_with("my id must reach OpenSearch")
      }),
      it("stores, finds and deletes a non-ASCII ID", fn() {
        // Act
        let trip = round_trip("café ☕")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["café ☕"], "deleted", ["a"])))
        |> or_fail_with("The UTF-8 ID must come back the same")
      }),
      it("stores, finds and deletes an ID that looks encoded", fn() {
        // Act
        let trip = round_trip("a%20b")

        // Assert
        trip
        |> should
        |> be_equal(Ok(RoundTrip(["a%20b"], "deleted", ["a"])))
        |> or_fail_with("%20 in an ID must stay %20, not a space")
      }),
    ]),
    group("index names that OpenSearch refuses", [
      it("an upper-case name gets invalid_index_name_exception", fn() {
        // Act
        let refused = create_refused_index("Books")

        // Assert
        refused
        |> should
        |> be_equal(
          Ok(#(
            "invalid_index_name_exception",
            "Invalid index name [Books], must be lowercase",
          )),
        )
        |> or_fail_with("OpenSearch should refuse the upper case")
      }),
      it("a name with # gets invalid_index_name_exception", fn() {
        // Act
        let refused = create_refused_index("a#b")

        // Assert
        refused
        |> should
        |> be_equal(
          Ok(#(
            "invalid_index_name_exception",
            "Invalid index name [a#b], must not contain '#'",
          )),
        )
        |> or_fail_with("The whole name a#b should reach OpenSearch")
      }),
      it("a name with a space gets invalid_index_name_exception", fn() {
        // Act
        let refused = create_refused_index("my books")

        // Assert
        refused
        |> should
        |> be_equal(
          Ok(#(
            "invalid_index_name_exception",
            "Invalid index name [my books], must not contain the following characters [ , \", *, \\, <, |, ,, >, /, ?]",
          )),
        )
        |> or_fail_with("The whole name my books should reach OpenSearch")
      }),
    ]),
  ])
}
