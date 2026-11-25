//// Black-box tests for `dream_opensearch/client`.
////
//// The answers with status 200, 201, 400 and 404 come from the real
//// OpenSearch of `opensearch_cluster`, each in its own index.
////
//// The other tests use a one-shot server on 127.0.0.1 (see
//// `opensearch_test_server`), which records the request line, headers and
//// body exactly as they arrive (a cluster does not report the requests it
//// got), and which sends what a cluster cannot be made to send on demand:
//// statuses such as 204, 399, 500 and 503, a body that is not JSON or not
//// UTF-8, and a TLS handshake.

import dream_opensearch/client.{Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import opensearch_cluster
import opensearch_test_server.{CaptureRawBytes, Respond, RespondBytes}

pub fn tests() -> TestSuite {
  describe("dream_opensearch/client", [
    group("new", [
      it("without trailing slash keeps url", fn() {
        // Arrange
        let base_url = "http://localhost:9200"

        // Act
        let result = client.new(base_url)

        // Assert
        result
        |> should
        |> be_equal(Client(base_url: "http://localhost:9200"))
        |> or_fail_with("new without trailing slash keeps url")
      }),
      it("with trailing slash removes it", fn() {
        // Arrange
        let base_url = "http://localhost:9200/"

        // Act
        let result = client.new(base_url)

        // Assert
        result
        |> should
        |> be_equal(Client(base_url: "http://localhost:9200"))
        |> or_fail_with("new with trailing slash removes it")
      }),
      it("with path prefix and trailing slash keeps prefix", fn() {
        // Arrange
        let base_url = "https://search.example.com:9200/opensearch/"

        // Act
        let result = client.new(base_url)

        // Assert
        result
        |> should
        |> be_equal(Client(
          base_url: "https://search.example.com:9200/opensearch",
        ))
        |> or_fail_with("new with path prefix and trailing slash keeps prefix")
      }),
      it("with empty string returns empty base url", fn() {
        // Arrange
        let base_url = ""

        // Act
        let result = client.new(base_url)

        // Assert
        result
        |> should
        |> be_equal(Client(base_url: ""))
        |> or_fail_with("new with empty string returns empty base url")
      }),
    ]),
    group("send_request: the request it builds", [
      it("sends given method and path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_doc/123", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/users/_doc/123")))
        |> or_fail_with("send_request sends given method and path")
      }),
      it("sends patch method", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          client.send_request(os_client, http.Patch, "/users/_doc/1", "{}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("PATCH", "/users/_doc/1")))
        |> or_fail_with("send_request sends patch method")
      }),
      it("sends one json content type header", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ =
          client.send_request(os_client, http.Post, "/users/_search", "{}")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "content-type"))
        |> should
        |> be_equal(Ok(["application/json"]))
        |> or_fail_with("send_request sends one json content type header")
      }),
      it("sends body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))
        let body = "{\"name\":\"O'Brien \\\"Al\\\" \\\\ zoë 日本\",\n\"x\":1}"

        // Act
        let _ = client.send_request(os_client, http.Put, "/users/_doc/1", body)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(
          "{\"name\":\"O'Brien \\\"Al\\\" \\\\ zoë 日本\",\n\"x\":1}",
        ))
        |> or_fail_with("send_request sends body unchanged")
      }),
      it("with empty body sends empty body", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = client.send_request(os_client, http.Delete, "/users", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(""))
        |> or_fail_with("send_request with empty body sends empty body")
      }),
      it("sends one megabyte body unchanged", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))
        let body = string.repeat("a", 1_048_576)

        // Act
        let _ = client.send_request(os_client, http.Post, "/_bulk", body)

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_body)
        |> should
        |> be_equal(Ok(string.repeat("a", 1_048_576)))
        |> or_fail_with("send_request sends one megabyte body unchanged")
      }),
      it("with trailing slash base url sends single slash path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url(server) <> "/")

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/users/_search")))
        |> or_fail_with(
          "send_request with trailing slash base url sends single slash path",
        )
      }),
      it("with base url path prefix prepends prefix", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url(server) <> "/opensearch")

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/opensearch/users/_search")))
        |> or_fail_with(
          "send_request with base url path prefix prepends prefix",
        )
      }),
      it("with empty path requests root", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = client.send_request(os_client, http.Get, "", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/")))
        |> or_fail_with("send_request with empty path requests root")
      }),
      it("with https base url starts tls handshake", fn() {
        // Arrange
        let server = opensearch_test_server.start(CaptureRawBytes)
        let os_client =
          client.new(
            "https://127.0.0.1:"
            <> int.to_string(opensearch_test_server.port(server)),
          )

        // Act
        let _ = client.send_request(os_client, http.Get, "/", "")

        // Assert: 22 (0x16) is the TLS handshake record type of a ClientHello
        opensearch_test_server.await_raw_bytes(server)
        |> result.try(bit_array.slice(_, 0, 1))
        |> should
        |> be_equal(Ok(<<22>>))
        |> or_fail_with("send_request with https base url starts tls handshake")
      }),
    ]),
    group("send_request: how it maps responses and failures", [
      it("with 200 returns ok body", fn() {
        // Act
        let result = {
          use body <- result.try(client.send_request(
            opensearch_cluster.client(),
            http.Get,
            "/",
            "",
          ))
          json.parse(body, decode.at(["tagline"], decode.string))
          |> result.replace_error("Unexpected root response: " <> body)
        }

        // Assert
        result
        |> should
        |> be_equal(Ok("The OpenSearch Project: https://opensearch.org/"))
        |> or_fail_with("send_request with 200 returns ok body")
      }),
      it("with 201 returns ok body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use body <- result.try(client.send_request(
            os_client,
            http.Put,
            "/" <> index <> "/_doc/1",
            "{}",
          ))
          json.parse(body, decode.at(["result"], decode.string))
          |> result.replace_error("Unexpected index response: " <> body)
        }

        // Assert
        result
        |> should
        |> be_equal(Ok("created"))
        |> or_fail_with("send_request with 201 returns ok body")
      }),
      it("with 204 and empty body returns ok empty string", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(204, ""))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Ok(""))
        |> or_fail_with(
          "send_request with 204 and empty body returns ok empty string",
        )
      }),
      it("with 200 non json body returns ok body unchanged", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "plain text, not JSON"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Ok("plain text, not JSON"))
        |> or_fail_with(
          "send_request with 200 non json body returns ok body unchanged",
        )
      }),
      it("with 200 and a body that is not UTF-8 returns an error", fn() {
        // Arrange
        let server = opensearch_test_server.start(RespondBytes(200, <<255, 0>>))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("The OpenSearch response body is not valid UTF-8"))
        |> or_fail_with("A 200 body that is not UTF-8 should be an error")
      }),
      it("with 500 and a body that is not UTF-8 returns an error", fn() {
        // Arrange
        let server = opensearch_test_server.start(RespondBytes(500, <<255, 0>>))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("The OpenSearch response body is not valid UTF-8"))
        |> or_fail_with("A 500 body that is not UTF-8 should be an error")
      }),
      it("with 200 unicode body returns ok body unchanged", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"name\":\"zoë 日本 🎉\"}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Ok("{\"name\":\"zoë 日本 🎉\"}"))
        |> or_fail_with(
          "send_request with 200 unicode body returns ok body unchanged",
        )
      }),
      it("with 399 returns ok body", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(399, "edge"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Ok("edge"))
        |> or_fail_with("send_request with 399 returns ok body")
      }),
      it("with 400 returns error body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(document.create_index(os_client, index, "{}"))
          client.send_request(
            os_client,
            http.Post,
            "/" <> index <> "/_search",
            "{",
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        result
        |> should
        |> be_equal(Ok(Error(Ok(#("json_e_o_f_exception", 400)))))
        |> or_fail_with("send_request with 400 returns error body")
      }),
      it("with 404 returns error body", fn() {
        // Act
        let result = {
          use os_client, index <- opensearch_cluster.with_index("users")
          use _ <- result.try(document.create_index(os_client, index, "{}"))
          // The index name varies, so put the name of the test in its place
          client.send_request(
            os_client,
            http.Get,
            "/" <> index <> "/_doc/9",
            "",
          )
          |> result.map_error(string.replace(_, index, "users"))
          |> Ok
        }

        // Assert
        result
        |> should
        |> be_equal(
          Ok(Error("{\"_index\":\"users\",\"_id\":\"9\",\"found\":false}")),
        )
        |> or_fail_with("send_request with 404 returns error body")
      }),
      it("with 500 returns error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(500, "{\"status\":500}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("{\"status\":500}"))
        |> or_fail_with("send_request with 500 returns error body")
      }),
      it("with 503 non json body returns error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(503, "Service Unavailable"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Service Unavailable"))
        |> or_fail_with(
          "send_request with 503 non json body returns error body",
        )
      }),
      it("with error status and empty body returns error empty string", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(502, ""))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error(""))
        |> or_fail_with(
          "send_request with error status and empty body returns error empty string",
        )
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          client.new(opensearch_test_server.unreachable_base_url())

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with(
          "send_request when nothing listens returns connection error",
        )
      }),
    ]),
    group("send_request: credentials in the base URL", [
      it("with user and password sends basic authorization", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:pass",
          ))

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_search", "")

        // Assert: base64 of "user:pass"
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok(["Basic dXNlcjpwYXNz"]))
        |> or_fail_with(
          "send_request with user and password sends basic authorization",
        )
      }),
      it("with percent encoded at in password decodes it", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:p%40ss",
          ))

        // Act
        let _ = client.send_request(os_client, http.Get, "/", "")

        // Assert: base64 of "user:p@ss"
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok(["Basic dXNlcjpwQHNz"]))
        |> or_fail_with(
          "send_request with percent encoded at in password decodes it",
        )
      }),
      it("with percent encoded colon and slash in password decodes them", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:p%40%3A%2Fss",
          ))

        // Act
        let _ = client.send_request(os_client, http.Get, "/", "")

        // Assert: base64 of "user:p@:/ss"
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok(["Basic dXNlcjpwQDovc3M="]))
        |> or_fail_with(
          "send_request with percent encoded colon and slash in password decodes them",
        )
      }),
      it("with user and no password returns ok body", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user",
          ))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Ok("{}"))
        |> or_fail_with(
          "send_request with user and no password returns ok body",
        )
      }),
      it("with user and no password sends empty password", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user",
          ))

        // Act
        let _ = client.send_request(os_client, http.Get, "/", "")

        // Assert: base64 of "user:"
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok(["Basic dXNlcjo="]))
        |> or_fail_with(
          "send_request with user and no password sends empty password",
        )
      }),
      it("without credentials sends no authorization", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client = client.new(opensearch_test_server.base_url(server))

        // Act
        let _ = client.send_request(os_client, http.Get, "/", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "authorization"))
        |> should
        |> be_equal(Ok([]))
        |> or_fail_with(
          "send_request without credentials sends no authorization",
        )
      }),
      it("with credentials keeps them out of the request line", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:pass",
          ))

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/users/_search")))
        |> or_fail_with(
          "send_request with credentials keeps them out of the request line",
        )
      }),
      it("with credentials keeps them out of the host header", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:pass",
          ))
        let expected_host =
          "127.0.0.1:" <> int.to_string(opensearch_test_server.port(server))

        // Act
        let _ = client.send_request(os_client, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "host"))
        |> should
        |> be_equal(Ok([expected_host]))
        |> or_fail_with(
          "send_request with credentials keeps them out of the host header",
        )
      }),
      it("with credentials and query string keeps query", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          client.new(opensearch_test_server.base_url_with_userinfo(
            server,
            "user:pass",
          ))

        // Act
        let _ =
          client.send_request(os_client, http.Get, "/users/_search?size=5", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/users/_search?size=5")))
        |> or_fail_with(
          "send_request with credentials and query string keeps query",
        )
      }),
      it("with credentials when nothing listens hides password", fn() {
        // Arrange
        let os_client =
          client.new(
            "http://user:secret-password@127.0.0.1:"
            <> int.to_string(opensearch_test_server.unused_port()),
          )

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with(
          "send_request with credentials when nothing listens hides password",
        )
      }),
      it("with invalid percent encoding in password returns error", fn() {
        // Arrange
        let os_client = client.new("http://user:secret%zz@127.0.0.1:9200")

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert: the message names the problem and does not hold the password
        result
        |> should
        |> be_equal(Error(
          "Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding",
        ))
        |> or_fail_with(
          "send_request with invalid percent encoding in password returns error",
        )
      }),
    ]),
    group("send_request: base URLs it cannot use", [
      it("with a base URL that has no host returns error", fn() {
        // Arrange
        let os_client = client.new("opensearch-without-scheme")

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Invalid OpenSearch URL: the URL has no host"))
        |> or_fail_with(
          "send_request with a base URL that has no host returns error",
        )
      }),
      it("with a base URL that cannot be parsed returns error", fn() {
        // Arrange
        let os_client = client.new("http://[::1")

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Invalid OpenSearch URL: the URL cannot be parsed"))
        |> or_fail_with(
          "send_request with a base URL that cannot be parsed returns error",
        )
      }),
      it("with a host that does not resolve returns the lookup error", fn() {
        // Arrange: a base URL with no port; the .invalid top-level domain never
        // resolves (RFC 6761)
        let os_client = client.new("http://opensearch.invalid")

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error("Connection failed: DNS resolution failed (NXDOMAIN)"))
        |> or_fail_with(
          "send_request with a host that does not resolve returns the lookup error",
        )
      }),
    ]),
  ])
}
