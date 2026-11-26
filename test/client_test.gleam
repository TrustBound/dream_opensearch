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

import dream_errors.{Conflict, Failed, Invalid, NotFound, Timeout}
import dream_http_client/client as http_client
import dream_http_client/recorder
import dream_opensearch/client.{
  InvalidResponseBody, InvalidUrl, NoRecording, Rejected, TimedOut, Unavailable,
  to_error,
}
import dream_opensearch/document.{create_index}
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string.{inspect, replace}
import opensearch_cluster.{as_text, with_index}
import opensearch_test_server.{
  type TestServer, CaptureRawBytes, HoldWithoutAnswer, Respond, RespondBytes,
}
import snippets/doc_client_to_error.{get_document}

/// The recordings of the recorded round trip. Record them again with
/// `RECORD_OPENSEARCH=true gleam test`, with the cluster of
/// `docker-compose.yml` running.
const recordings_directory = "test/recordings/client_round_trip"

/// The index of the recorded round trip. The recordings hold its name, so
/// it is the same in every run.
const recorded_index = "recorded_books"

/// A base request for the local test server `server`.
fn local_base(server: TestServer) -> http_client.ClientRequest {
  http_client.new()
  |> http_client.scheme(http.Http)
  |> http_client.host("127.0.0.1")
  |> http_client.port(opensearch_test_server.port(server))
}

/// Creates the index, indexes one book, gets it and deletes the index.
/// Returns the `result` of the index answer, the title of the book and the
/// `acknowledged` of the delete answer.
fn recorded_round_trip(
  opensearch: client.Client,
) -> Result(#(String, String, Bool), String) {
  use _ <- result.try(
    document.create_index(opensearch, recorded_index, "{}")
    |> opensearch_cluster.as_text,
  )
  use indexed <- result.try(
    document.index(
      opensearch,
      recorded_index,
      "1",
      "{\"title\":\"Programming Gleam\"}",
    )
    |> opensearch_cluster.as_text,
  )
  use fetched <- result.try(
    client.send_request(
      opensearch,
      http.Get,
      "/" <> recorded_index <> "/_doc/1",
      "",
    )
    |> opensearch_cluster.as_text,
  )
  use deleted <- result.try(
    document.delete_index(opensearch, recorded_index)
    |> opensearch_cluster.as_text,
  )
  use outcome <- result.try(
    json.parse(indexed, decode.at(["result"], decode.string))
    |> result.replace_error("Unexpected index answer: " <> indexed),
  )
  use title <- result.try(
    json.parse(fetched, decode.at(["_source", "title"], decode.string))
    |> result.replace_error("Unexpected document: " <> fetched),
  )
  use acknowledged <- result.try(
    json.parse(deleted, decode.at(["acknowledged"], decode.bool))
    |> result.replace_error("Unexpected delete answer: " <> deleted),
  )
  Ok(#(outcome, title, acknowledged))
}

pub fn tests() -> TestSuite {
  describe("dream_opensearch/client", [
    group("new", [
      it("without trailing slash keeps url", fn() {
        // Act
        let created = client.new("http://localhost:9200")

        // Assert
        created
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("new without trailing slash keeps url")
      }),
      it("with trailing slash removes it", fn() {
        // Act
        let created = client.new("http://localhost:9200/")

        // Assert
        created
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("http://localhost:9200"))
        |> or_fail_with("new with trailing slash removes it")
      }),
      it("with https and a path prefix keeps both", fn() {
        // Act
        let created = client.new("https://search.example.com:9200/opensearch/")

        // Assert
        created
        |> result.map(opensearch_cluster.base_url_of)
        |> should
        |> be_equal(Ok("https://search.example.com:9200/opensearch"))
        |> or_fail_with("new keeps the scheme and the path prefix")
      }),
      it("with credentials puts them in the authorization header", fn() {
        // Act
        let created = client.new("http://user:pass@localhost:9200")

        // Assert
        created
        |> result.map(fn(opensearch) {
          let base = client.base_request(opensearch)
          #(
            opensearch_cluster.base_url_of(opensearch),
            http_client.get_headers(base),
          )
        })
        |> should
        |> be_equal(
          Ok(
            #("http://localhost:9200", [
              http_client.Header("authorization", "Basic dXNlcjpwYXNz"),
            ]),
          ),
        )
        |> or_fail_with("The password goes only in the authorization header")
      }),
      it("with an empty string returns invalid url", fn() {
        // Act
        let created = client.new("")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL scheme must be http or https")))
        |> or_fail_with("An empty base URL has no scheme")
      }),
      it("with another scheme returns invalid url", fn() {
        // Act
        let created = client.new("ftp://localhost:9200")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL scheme must be http or https")))
        |> or_fail_with("Only http and https")
      }),
      it("with no host returns invalid url", fn() {
        // Act
        let created = client.new("http:opensearch")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL has no host")))
        |> or_fail_with("A base URL needs a host")
      }),
      it("with a URL that cannot be parsed returns invalid url", fn() {
        // Act
        let created = client.new("http://[::1")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL cannot be parsed")))
        |> or_fail_with("An unclosed IPv6 host cannot be parsed")
      }),
      it("with a query returns invalid url", fn() {
        // Act
        let created = client.new("http://localhost:9200?pretty=true")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL has a query or a fragment")))
        |> or_fail_with("A base URL has no query")
      }),
      it("with a fragment returns invalid url", fn() {
        // Act
        let created = client.new("http://localhost:9200#top")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL has a query or a fragment")))
        |> or_fail_with("A base URL has no fragment")
      }),
      it("with invalid percent encoding in the password hides it", fn() {
        // Act
        let created = client.new("http://user:secret%zz@127.0.0.1:9200")

        // Assert
        created
        |> should
        |> be_equal(
          Error(InvalidUrl(
            "the user name or password has invalid percent-encoding",
          )),
        )
        |> or_fail_with("The reason names the problem, not the password")
      }),
    ]),
    group("from_request", [
      it("keeps the headers of the base request", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch =
          local_base(server)
          |> http_client.add_header("x-trace", "abc")
          |> client.from_request

        // Act
        let _ = client.send_request(opensearch, http.Get, "/", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "x-trace"))
        |> should
        |> be_equal(Ok(["abc"]))
        |> or_fail_with("The base header goes with each request")
      }),
      it("replaces a content type of the base request", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch =
          local_base(server)
          |> http_client.add_header("Content-Type", "text/plain")
          |> client.from_request

        // Act
        let _ = client.send_request(opensearch, http.Get, "/", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.header_values(_, "content-type"))
        |> should
        |> be_equal(Ok(["application/json"]))
        |> or_fail_with("Each request is JSON")
      }),
      it("puts the path of the base request before the API path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch =
          local_base(server)
          |> http_client.path("/opensearch/")
          |> client.from_request

        // Act
        let _ = client.send_request(opensearch, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/opensearch/users/_search")))
        |> or_fail_with("The base path is a prefix")
      }),
      it("keeps the query of the base request for a path with none", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let opensearch =
          local_base(server)
          |> http_client.query("pretty=true")
          |> client.from_request

        // Act
        let _ = client.send_request(opensearch, http.Get, "/users/_search", "")

        // Assert
        opensearch_test_server.await_request(server)
        |> result.map(opensearch_test_server.request_line)
        |> should
        |> be_equal(Ok(#("GET", "/users/_search?pretty=true")))
        |> or_fail_with("The base query stays")
      }),
      it(
        "replaces the query of the base request with the query of the path",
        fn() {
          // Arrange
          let server = opensearch_test_server.start(Respond(200, "{}"))
          let opensearch =
            local_base(server)
            |> http_client.query("pretty=true")
            |> client.from_request

          // Act
          let _ =
            client.send_request(
              opensearch,
              http.Get,
              "/users/_search?size=5",
              "",
            )

          // Assert
          opensearch_test_server.await_request(server)
          |> result.map(opensearch_test_server.request_line)
          |> should
          |> be_equal(Ok(#("GET", "/users/_search?size=5")))
          |> or_fail_with("The query of the path wins")
        },
      ),
      it("returns timed out with the timeout of the base request", fn() {
        // Arrange
        let server = opensearch_test_server.start(HoldWithoutAnswer)
        let opensearch =
          local_base(server)
          |> http_client.timeout(100)
          |> client.from_request

        // Act
        let result = client.send_request(opensearch, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error(TimedOut(timeout_ms: 100)))
        |> or_fail_with("The server holds the request past the timeout")
      }),
      it("base_request returns the base with no trailing slash", fn() {
        // Act
        let base =
          http_client.new()
          |> http_client.host("search.example.com")
          |> http_client.path("/opensearch/")
          |> client.from_request
          |> client.base_request

        // Assert
        #(http_client.get_host(base), http_client.get_path(base))
        |> should
        |> be_equal(#("search.example.com", "/opensearch"))
        |> or_fail_with("The base request comes back")
      }),
    ]),
    group("from_request with a recorder", [
      it("sends a round trip through the recorder", fn() {
        // Act
        let trip = {
          use #(opensearch, started) <- result.try(
            opensearch_cluster.recorded_client(
              recordings_directory,
              opensearch_cluster.recorder_mode(),
            ),
          )
          let outcome = recorded_round_trip(opensearch)
          use Nil <- result.try(recorder.stop(started))
          outcome
        }

        // Assert
        trip
        |> should
        |> be_equal(Ok(#("created", "Programming Gleam", True)))
        |> or_fail_with("The recorded index, get and delete should pass")
      }),
      it("returns no recording for a request with no recording", fn() {
        // Act
        let missed = {
          use #(opensearch, started) <- result.try(
            opensearch_cluster.recorded_client(
              recordings_directory,
              recorder.Playback,
            ),
          )
          let outcome =
            client.send_request(opensearch, http.Get, "/not_recorded", "")
          use Nil <- result.try(recorder.stop(started))
          Ok(outcome)
        }

        // Assert
        missed
        |> result.map(
          result.map_error(_, fn(error) {
            case error {
              NoRecording(method:, url:, ..) -> #(method, url)
              _ -> #("", client.describe_error(error))
            }
          }),
        )
        |> should
        |> be_equal(Ok(Error(#("GET", "http://localhost:9201/not_recorded"))))
        |> or_fail_with("Playback sends nothing for a request it does not know")
      }),
    ]),
    group("describe_error", [
      it("describes each error on one line", fn() {
        // Arrange
        let errors = [
          InvalidUrl("the URL has no host"),
          Unavailable("Connection failed: Connection refused"),
          TimedOut(timeout_ms: 30_000),
          Rejected(status: 404, body: "{\"found\":false}"),
          InvalidResponseBody(status: 200),
          NoRecording(
            method: "GET",
            url: "http://localhost:9201/",
            details: "No recording for GET http://localhost:9201/",
          ),
        ]

        // Act
        let lines = list.map(errors, client.describe_error)

        // Assert
        lines
        |> should
        |> be_equal([
          "Invalid OpenSearch URL: the URL has no host",
          "OpenSearch is unavailable: Connection failed: Connection refused",
          "OpenSearch sent no answer within 30000 ms",
          "OpenSearch rejected the request with status 404: {\"found\":false}",
          "The OpenSearch response body is not valid UTF-8 (status 200)",
          "No recording for the OpenSearch request: No recording for GET http://localhost:9201/",
        ])
        |> or_fail_with("Each error has its line")
      }),
    ]),
    group("send_request: the request it builds", [
      it("sends given method and path", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(200, "{}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))
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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))
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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url(server) <> "/",
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url(server) <> "/opensearch",
          )

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
          opensearch_cluster.client_for(
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
          use body <- result.try(
            client.send_request(opensearch_cluster.client(), http.Get, "/", "")
            |> opensearch_cluster.as_text,
          )
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
          use body <- result.try(
            client.send_request(
              os_client,
              http.Put,
              "/" <> index <> "/_doc/1",
              "{}",
            )
            |> opensearch_cluster.as_text,
          )
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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error(client.InvalidResponseBody(status: 200)))
        |> or_fail_with("A 200 body that is not UTF-8 should be an error")
      }),
      it("with 500 and a body that is not UTF-8 returns an error", fn() {
        // Arrange
        let server = opensearch_test_server.start(RespondBytes(500, <<255, 0>>))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error(client.InvalidResponseBody(status: 500)))
        |> or_fail_with("A 500 body that is not UTF-8 should be an error")
      }),
      it("with 200 unicode body returns ok body unchanged", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, "{\"name\":\"zoë 日本 🎉\"}"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
          use _ <- result.try(
            document.create_index(os_client, index, "{}")
            |> opensearch_cluster.as_text,
          )
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
          use _ <- result.try(
            document.create_index(os_client, index, "{}")
            |> opensearch_cluster.as_text,
          )
          // The index name varies, so put the name of the test in its place
          client.send_request(
            os_client,
            http.Get,
            "/" <> index <> "/_doc/9",
            "",
          )
          |> opensearch_cluster.rejected_body
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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Rejected(status: 500, body: "{\"status\":500}")),
        )
        |> or_fail_with("send_request with 500 returns error body")
      }),
      it("with 503 non json body returns error body", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(503, "Service Unavailable"))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Rejected(status: 503, body: "Service Unavailable")),
        )
        |> or_fail_with(
          "send_request with 503 non json body returns error body",
        )
      }),
      it("with error status and empty body returns error empty string", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(502, ""))
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(Error(client.Rejected(status: 502, body: "")))
        |> or_fail_with(
          "send_request with error status and empty body returns error empty string",
        )
      }),
      it("when nothing listens returns connection error", fn() {
        // Arrange
        let os_client =
          opensearch_cluster.client_for(
            opensearch_test_server.unreachable_base_url(),
          )

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user:pass"),
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user:p%40ss"),
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(
              server,
              "user:p%40%3A%2Fss",
            ),
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user"),
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user"),
          )

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
        let os_client =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user:pass"),
          )

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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user:pass"),
          )
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
          opensearch_cluster.client_for(
            opensearch_test_server.base_url_with_userinfo(server, "user:pass"),
          )

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
          opensearch_cluster.client_for(
            "http://user:secret-password@127.0.0.1:"
            <> int.to_string(opensearch_test_server.unused_port()),
          )

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable("Connection failed: Connection refused")),
        )
        |> or_fail_with(
          "send_request with credentials when nothing listens hides password",
        )
      }),
    ]),
    group("send_request: hosts it cannot reach", [
      it("with a host that does not resolve returns the lookup error", fn() {
        // Arrange: a base URL with no port; the .invalid top-level domain never
        // resolves (RFC 6761)
        let os_client =
          opensearch_cluster.client_for("http://opensearch.invalid")

        // Act
        let result = client.send_request(os_client, http.Get, "/", "")

        // Assert
        result
        |> should
        |> be_equal(
          Error(client.Unavailable(
            "Connection failed: DNS resolution failed (NXDOMAIN)",
          )),
        )
        |> or_fail_with(
          "send_request with a host that does not resolve returns the lookup error",
        )
      }),
    ]),
    group("to_error", [
      it("maps InvalidUrl to Invalid", fn() {
        // Arrange
        let error = InvalidUrl("the URL has no host")

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Invalid(
          "Invalid OpenSearch URL: the URL has no host",
          InvalidUrl("the URL has no host"),
        ))
        |> or_fail_with("Should maps InvalidUrl to Invalid")
      }),
      it("maps Unavailable to Unavailable", fn() {
        // Arrange
        let error = Unavailable("Connection failed: Connection refused")

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(dream_errors.Unavailable(
          "OpenSearch is unavailable: Connection failed: Connection refused",
          Unavailable("Connection failed: Connection refused"),
        ))
        |> or_fail_with("Should maps Unavailable to Unavailable")
      }),
      it("maps TimedOut to Timeout", fn() {
        // Arrange
        let error = TimedOut(timeout_ms: 30_000)

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Timeout(
          "OpenSearch sent no answer within 30000 ms",
          TimedOut(timeout_ms: 30_000),
        ))
        |> or_fail_with("Should maps TimedOut to Timeout")
      }),
      it("maps Rejected with status 404 to NotFound", fn() {
        // Arrange
        let error = Rejected(status: 404, body: "{\"found\":false}")

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(NotFound(
          "OpenSearch rejected the request with status 404: {\"found\":false}",
        ))
        |> or_fail_with("Should maps Rejected with status 404 to NotFound")
      }),
      it("maps Rejected with status 409 to Conflict", fn() {
        // Arrange
        let error = Rejected(status: 409, body: "{\"status\":409}")

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Conflict(
          "OpenSearch rejected the request with status 409: {\"status\":409}",
          Rejected(status: 409, body: "{\"status\":409}"),
        ))
        |> or_fail_with("Should maps Rejected with status 409 to Conflict")
      }),
      it("maps Rejected with status 400 to Failed", fn() {
        // Arrange
        let error = Rejected(status: 400, body: "{\"status\":400}")

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Failed(
          "OpenSearch rejected the request with status 400: {\"status\":400}",
          Rejected(status: 400, body: "{\"status\":400}"),
        ))
        |> or_fail_with("Should maps Rejected with status 400 to Failed")
      }),
      it("maps InvalidResponseBody to Failed", fn() {
        // Arrange
        let error = InvalidResponseBody(status: 200)

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Failed(
          "The OpenSearch response body is not valid UTF-8 (status 200)",
          InvalidResponseBody(status: 200),
        ))
        |> or_fail_with("Should maps InvalidResponseBody to Failed")
      }),
      it("maps NoRecording to Failed", fn() {
        // Arrange
        let error =
          NoRecording(
            method: "GET",
            url: "http://localhost:9201/",
            details: "No recording for GET http://localhost:9201/",
          )

        // Act
        let result = to_error(error)

        // Assert
        result
        |> should
        |> be_equal(Failed(
          "No recording for the OpenSearch request: No recording for GET http://localhost:9201/",
          NoRecording(
            method: "GET",
            url: "http://localhost:9201/",
            details: "No recording for GET http://localhost:9201/",
          ),
        ))
        |> or_fail_with("Should maps NoRecording to Failed")
      }),
      it("the doc snippet maps a missing document to NotFound", fn() {
        // Arrange and act
        let result = {
          use os_client, index <- with_index("users")
          use _ <- result.try(
            create_index(os_client, index, "{}")
            |> as_text,
          )
          // The index name varies, so put the name of the test in its place
          case get_document(os_client, index, "9") {
            Error(NotFound(message)) ->
              Ok(Error(replace(message, index, "users")))
            other -> Ok(Ok(inspect(other)))
          }
        }

        // Assert
        result
        |> should
        |> be_equal(
          Ok(Error(
            "OpenSearch rejected the request with status 404: {\"_index\":\"users\",\"_id\":\"9\",\"found\":false}",
          )),
        )
        |> or_fail_with("Should map the 404 of a missing document to NotFound")
      }),
    ]),
  ])
}
