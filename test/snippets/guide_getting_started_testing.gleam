//// Guide: Getting started, test your code
////
//// Tests the user store with a saved search response and with a cluster
//// that cannot be reached.

import dream_opensearch/client
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, it}
import snippets/guide_getting_started_user_store.{
  User, find_users_by_name, users_from_response,
}

const search_response =
  "{\"took\":1,\"timed_out\":false,\"_shards\":{\"total\":1,\"successful\":1,\"skipped\":0,\"failed\":0},\"hits\":{\"total\":{\"value\":1,\"relation\":\"eq\"},\"max_score\":0.18232156,\"hits\":[{\"_index\":\"users\",\"_id\":\"123\",\"_score\":0.18232156,\"_source\":{\"name\":\"Alice\",\"email\":\"alice@example.com\"}}]}}"

pub fn tests() -> TestSuite {
  describe("user store", [
    it("reads the users out of a search response", fn() {
      // Act
      let users = users_from_response(search_response)

      // Assert
      users
      |> should
      |> be_equal(
        Ok([User(id: "123", name: "Alice", email: "alice@example.com")]),
      )
      |> or_fail_with("Expected Alice from the saved response")
    }),
    it("returns the connection error when no cluster listens", fn() {
      // Arrange
      // Nothing listens on port 1
      let assert Ok(opensearch) = client.new("http://127.0.0.1:1")

      // Act
      let users = find_users_by_name(opensearch, "users", "alice")

      // Assert
      users
      |> should
      |> be_equal(Error(
        "OpenSearch is unavailable: Connection failed: Connection refused",
      ))
      |> or_fail_with("Expected a refused connection")
    }),
  ])
}
