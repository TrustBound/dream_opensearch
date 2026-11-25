//// The `document` functions percent-encode each index name and document ID
//// as one path segment: every byte outside the RFC 3986 unreserved set
//// (`A-Z a-z 0-9 - . _ ~`) goes out as `%XX`, with the bytes of UTF-8 and
//// upper-case hex digits.
////
//// The one-shot server in `opensearch_test_server` records the request
//// target exactly as it arrives on the wire.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/result
import opensearch_cluster
import opensearch_test_server.{type TestServer, Respond}

fn serve() -> #(TestServer, Client) {
  let server = opensearch_test_server.start(Respond(200, "{}"))
  #(
    server,
    opensearch_cluster.client_for(opensearch_test_server.base_url(server)),
  )
}

fn request_line(server: TestServer) -> Result(#(String, String), Nil) {
  opensearch_test_server.await_request(server)
  |> result.map(opensearch_test_server.request_line)
}

pub fn tests() -> TestSuite {
  describe("dream_opensearch/document: path encoding", [
    group("document IDs", [
      it("index encodes # in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "a#b", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/a%23b")))
        |> or_fail_with("The # must not end the path")
      }),
      it("index encodes / in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "a/b", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/a%2Fb")))
        |> or_fail_with("The / must not split the ID in two segments")
      }),
      it("index encodes ? and = in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "a?b=1", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/a%3Fb%3D1")))
        |> or_fail_with("The ? must not start a query string")
      }),
      it("index encodes a space in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "my id", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/my%20id")))
        |> or_fail_with("The space must go out as %20")
      }),
      it("index encodes the UTF-8 bytes of a non-ASCII ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "café ☕", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/caf%C3%A9%20%E2%98%95")))
        |> or_fail_with("Each UTF-8 byte must go out as %XX, upper case")
      }),
      it("index encodes % in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "a%20b", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/a%2520b")))
        |> or_fail_with("An ID that looks encoded must be encoded again")
      }),
      it("index keeps the unreserved characters", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", "Az09-._~", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/users/_doc/Az09-._~")))
        |> or_fail_with("Unreserved characters must stay as they are")
      }),
      it("index encodes the other reserved characters", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "users", ":@!$&'()*+,;[]", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(
          Ok(#("PUT", "/users/_doc/%3A%40%21%24%26%27%28%29%2A%2B%2C%3B%5B%5D")),
        )
        |> or_fail_with("Every reserved character must be encoded")
      }),
      it("delete encodes # in the ID", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.delete(opensearch, "users", "a#b")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("DELETE", "/users/_doc/a%23b")))
        |> or_fail_with("delete must not delete document a")
      }),
    ]),
    group("index names", [
      it("index encodes the index name", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.index(opensearch, "my users", "1", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/my%20users/_doc/1")))
        |> or_fail_with("The index name is a path segment too")
      }),
      it("search encodes the index name", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.search(opensearch, "a#b", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("POST", "/a%23b/_search")))
        |> or_fail_with("search must keep the whole index name")
      }),
      it("delete encodes the index name", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.delete(opensearch, "a/b", "1")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("DELETE", "/a%2Fb/_doc/1")))
        |> or_fail_with("delete must keep the index name as one segment")
      }),
      it("create_index encodes the index name", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.create_index(opensearch, "a?b", "{}")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("PUT", "/a%3Fb")))
        |> or_fail_with("create_index must not send a query string")
      }),
      it("delete_index encodes the index name", fn() {
        // Arrange
        let #(server, opensearch) = serve()

        // Act
        let _ = document.delete_index(opensearch, "books*")

        // Assert
        request_line(server)
        |> should
        |> be_equal(Ok(#("DELETE", "/books%2A")))
        |> or_fail_with("* is not unreserved, so it goes out encoded")
      }),
    ]),
  ])
}
