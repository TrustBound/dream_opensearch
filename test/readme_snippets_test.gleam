//// Tests for the code blocks in this module's README.md. The quick start
//// is also "The short version" of the getting started guide.
////
//// The quick start writes to the index `users`, by name. This is the only
//// test that uses that index on the real cluster of `opensearch_cluster`,
//// and it deletes the index at the end.

import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/json
import gleam/result
import opensearch_cluster
import snippets/readme_quick_start

fn hit_ids(body: String) -> Result(List(String), String) {
  json.parse(
    body,
    decode.at(["hits", "hits"], decode.list(decode.at(["_id"], decode.string))),
  )
  |> result.replace_error("Unexpected search response: " <> body)
}

fn result_field(body: String) -> Result(String, String) {
  json.parse(body, decode.at(["result"], decode.string))
  |> result.replace_error("Unexpected response: " <> body)
}

/// Indexes, finds and deletes Alice in `users`, then deletes the index.
fn quick_start() -> Result(#(String, List(String), String), String) {
  let opensearch = opensearch_cluster.client()
  let outcome = {
    use indexed <- result.try(
      readme_quick_start.index_alice(opensearch) |> opensearch_cluster.as_text,
    )
    use created <- result.try(result_field(indexed))
    use Nil <- result.try(opensearch_cluster.refresh(opensearch, "users"))
    use found <- result.try(
      readme_quick_start.search_for_alice(opensearch)
      |> opensearch_cluster.as_text,
    )
    use found_ids <- result.try(hit_ids(found))
    use deleted <- result.try(
      readme_quick_start.delete_alice(opensearch) |> opensearch_cluster.as_text,
    )
    use deleted_result <- result.try(result_field(deleted))
    Ok(#(created, found_ids, deleted_result))
  }
  use _ <- result.try(
    document.delete_index(opensearch, "users") |> opensearch_cluster.as_text,
  )
  outcome
}

pub fn tests() -> TestSuite {
  describe("README snippets", [
    group("Quick Start", [
      it("create client uses localhost 9200", fn() {
        // Act
        let opensearch = readme_quick_start.create_client()

        // Assert
        opensearch
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("quick start create client uses localhost 9200")
      }),
      it("indexes, finds and deletes Alice on a real cluster", fn() {
        // Act
        let outcome = quick_start()

        // Assert
        outcome
        |> should
        |> be_equal(Ok(#("created", ["123"], "deleted")))
        |> or_fail_with("Alice should be created, found by name and deleted")
      }),
    ]),
  ])
}
