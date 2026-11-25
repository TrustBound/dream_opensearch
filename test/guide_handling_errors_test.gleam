//// Tests for the snippets and the error table of the error handling guide
//// (docs/guides/handling-errors.md). The answers of OpenSearch come from
//// the real cluster of `opensearch_cluster`. The local test server of
//// `opensearch_test_server` stands in only for what a cluster cannot be
//// made to do on demand: close a connection with no answer, hold a request
//// with no answer, send a body that is not UTF-8. Refused connections go to
//// a port where nothing listens.
////
//// Each `text` block of the guide is a file in `test/outputs/`, and a test
//// here compares it with the real output (see `guide_output`).

import dream_opensearch/client.{
  type Client, InvalidResponseBody, InvalidUrl, NoRecording, Rejected, TimedOut,
  Unavailable,
}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/http
import gleam/list
import gleam/result
import gleam/string
import guide_output
import guide_responses
import opensearch_cluster
import opensearch_test_server.{
  type Reply, CloseWithoutAnswer, HoldWithoutAnswer, RespondBytes,
}
import snippets/guide_handling_errors_classify.{type ErrorDetails, ErrorDetails}
import snippets/guide_handling_errors_log
import snippets/guide_handling_errors_timeout

/// `details` with the field labels, as the guide shows it.
fn labelled(details: Result(ErrorDetails, Nil)) -> String {
  case details {
    Ok(ErrorDetails(error_type:, reason:)) ->
      "Ok(ErrorDetails(error_type: "
      <> string.inspect(error_type)
      <> ", reason: "
      <> string.inspect(reason)
      <> "))"
    Error(Nil) -> "Error(Nil)"
  }
  |> guide_output.lines
}

fn client_for(reply: Reply) -> Client {
  let server = opensearch_test_server.start(reply)
  opensearch_cluster.client_for(opensearch_test_server.base_url(server))
}

fn search_books(opensearch: Client) -> Result(String, client.OpenSearchError) {
  document.search(opensearch, "books", "{}")
}

pub fn tests() -> TestSuite {
  describe("handling errors guide", [
    group("step 1: the errors", [
      it("a refused connection", fn() {
        // Act
        let searched =
          search_books(opensearch_cluster.client_for("http://127.0.0.1:1"))

        // Assert
        searched
        |> should
        |> be_equal(Error(Unavailable("Connection failed: Connection refused")))
        |> or_fail_with("Expected a refused connection")
      }),
      it("a host that does not resolve", fn() {
        // Act
        let searched =
          search_books(opensearch_cluster.client_for(
            "http://no-such-host.invalid:9200",
          ))

        // Assert
        searched
        |> should
        |> be_equal(
          Error(Unavailable(
            "Connection failed: DNS resolution failed (NXDOMAIN)",
          )),
        )
        |> or_fail_with("Expected a failed lookup")
      }),
      it("a server that closes the connection with no answer", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            CloseWithoutAnswer,
            CloseWithoutAnswer,
          ])
        let opensearch =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let searched = search_books(opensearch)

        // Assert
        searched
        |> should
        |> be_equal(Error(Unavailable("Remote closed connection")))
        |> or_fail_with("Expected a closed connection")
      }),
      it("a closed connection makes the client send a POST one time", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            CloseWithoutAnswer,
            CloseWithoutAnswer,
          ])
        let opensearch =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let searched = search_books(opensearch)

        // Assert
        [server, server]
        |> list.map(opensearch_test_server.await_request)
        |> list.map(result.map(_, opensearch_test_server.request_line))
        |> fn(requests) { #(searched, requests) }
        |> should
        |> be_equal(
          #(Error(Unavailable("Remote closed connection")), [
            Ok(#("POST", "/books/_search")),
            Error(Nil),
          ]),
        )
        |> or_fail_with("The POST should arrive one time only")
      }),
      it("a closed connection makes the client send a PUT two times", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            CloseWithoutAnswer,
            CloseWithoutAnswer,
          ])
        let opensearch =
          opensearch_cluster.client_for(opensearch_test_server.base_url(server))

        // Act
        let indexed = document.index(opensearch, "books", "1", "{}")

        // Assert
        [server, server]
        |> list.map(opensearch_test_server.await_request)
        |> list.map(result.map(_, opensearch_test_server.request_line))
        |> fn(requests) { #(indexed, requests) }
        |> should
        |> be_equal(
          #(Error(Unavailable("Remote closed connection")), [
            Ok(#("PUT", "/books/_doc/1")),
            Ok(#("PUT", "/books/_doc/1")),
          ]),
        )
        |> or_fail_with("The same PUT should arrive two times")
      }),
      it("a server that sends no answer within the timeout", fn() {
        // Arrange
        let server = opensearch_test_server.start(HoldWithoutAnswer)
        let opensearch =
          guide_handling_errors_timeout.client_with_timeout(
            "127.0.0.1",
            opensearch_test_server.port(server),
            100,
          )

        // Act
        let searched = search_books(opensearch)

        // Assert
        searched
        |> should
        |> be_equal(Error(TimedOut(timeout_ms: 100)))
        |> or_fail_with("Expected the timeout of the base request")
      }),
      it("a URL with no scheme", fn() {
        // Act
        let created = client.new("localhost:9200")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL scheme must be http or https")))
        |> or_fail_with("Expected no scheme")
      }),
      it("a URL that cannot be parsed", fn() {
        // Act
        let created = client.new("http://[::1")

        // Assert
        created
        |> should
        |> be_equal(Error(InvalidUrl("the URL cannot be parsed")))
        |> or_fail_with("Expected a parse error")
      }),
      it("a password with a bare percent sign", fn() {
        // Act
        let created = client.new("http://admin:p%zz@localhost:9200")

        // Assert
        created
        |> should
        |> be_equal(
          Error(InvalidUrl(
            "the user name or password has invalid percent-encoding",
          )),
        )
        |> or_fail_with("Expected a credentials error")
      }),
      it("an OpenSearch error comes back as its status and body", fn() {
        // Act
        let searched = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          case document.search(opensearch, index, "{}") {
            Ok(body) -> Error("Expected a 404, got: " <> body)
            // The index name varies, so put the name of the guide in its place
            Error(Rejected(status: 404, body:)) ->
              guide_output.stable_json(string.replace(body, index, "books"), [])
            Error(error) -> Error(client.describe_error(error))
          }
        }

        // Assert
        searched
        |> should
        |> be_equal(
          guide_output.stable_file("guide_handling_errors_missing_index", []),
        )
        |> or_fail_with("Expected the error body")
      }),
      it("a plain text 401 comes back as its body", fn() {
        // Act
        let searched =
          search_books(
            opensearch_cluster.client_for(opensearch_cluster.secured_base_url()),
          )

        // Assert
        searched
        |> should
        |> be_equal(Error(Rejected(status: 401, body: "Unauthorized")))
        |> or_fail_with("Expected Unauthorized")
      }),
      it("an error status with no body has an empty body", fn() {
        // Act
        let checked = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          Ok(client.send_request(opensearch, http.Head, "/" <> index, ""))
        }

        // Assert
        checked
        |> should
        |> be_equal(Ok(Error(Rejected(status: 404, body: ""))))
        |> or_fail_with("A HEAD for a missing index gets a 404 with no body")
      }),
      it("a body that is not UTF-8", fn() {
        // Act
        let searched = search_books(client_for(RespondBytes(200, <<255, 254>>)))

        // Assert
        searched
        |> should
        |> be_equal(Error(InvalidResponseBody(status: 200)))
        |> or_fail_with("Expected the UTF-8 error")
      }),
    ]),
    group("step 2: error_details", [
      it("error_details reads the type and the reason", fn() {
        // Act
        let details = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          document.search(opensearch, index, "{}")
          // The index name varies, so put the name of the guide in its place
          |> opensearch_cluster.rejected_body
          |> result.map_error(string.replace(_, index, "books"))
          |> result.map_error(Rejected(status: 404, body: _))
          |> result.map_error(guide_handling_errors_classify.error_details)
          |> Ok
        }

        // Assert
        details
        |> result.map(result.map_error(_, labelled))
        |> should
        |> be_equal(
          Ok(Error(guide_output.file("guide_handling_errors_classified"))),
        )
        |> or_fail_with("Expected a 404 index_not_found_exception")
      }),
      it("error_details has no details for the other errors", fn() {
        // Arrange
        let errors = [
          Rejected(status: 401, body: "Unauthorized"),
          Rejected(status: 502, body: guide_responses.bad_gateway_page),
          Rejected(status: 404, body: ""),
          Unavailable("Connection failed: Connection refused"),
          TimedOut(timeout_ms: 30_000),
        ]

        // Act
        let details =
          list.map(errors, guide_handling_errors_classify.error_details)

        // Assert
        details
        |> should
        |> be_equal([Error(Nil), Error(Nil), Error(Nil), Error(Nil), Error(Nil)])
        |> or_fail_with("Only an OpenSearch error object has details")
      }),
    ]),
    group("step 3: retry", [
      it("worth_a_retry says yes to the passing failures", fn() {
        // Arrange
        let errors = [
          Unavailable("Connection failed: Connection refused"),
          Unavailable("Remote closed connection"),
          TimedOut(timeout_ms: 30_000),
          Rejected(status: 503, body: guide_responses.cluster_not_ready),
          Rejected(status: 429, body: ""),
          Rejected(status: 502, body: guide_responses.bad_gateway_page),
          Rejected(status: 504, body: ""),
        ]

        // Act
        let answers =
          list.map(errors, guide_handling_errors_classify.worth_a_retry)

        // Assert
        answers
        |> should
        |> be_equal([True, True, True, True, True, True, True])
        |> or_fail_with("All of these can pass")
      }),
      it("worth_a_retry says no to the rest", fn() {
        // Arrange
        let errors = [
          Rejected(status: 404, body: ""),
          Rejected(status: 400, body: ""),
          Rejected(status: 401, body: "Unauthorized"),
          InvalidUrl("the URL has no host"),
          InvalidResponseBody(status: 200),
          NoRecording(method: "GET", url: "http://localhost:9201/", details: ""),
        ]

        // Act
        let answers =
          list.map(errors, guide_handling_errors_classify.worth_a_retry)

        // Assert
        answers
        |> should
        |> be_equal([False, False, False, False, False, False])
        |> or_fail_with("None of these change on their own")
      }),
    ]),
    group("step 4: logs", [
      it("failure_line leaves out the user name and password", fn() {
        // Arrange
        let opensearch =
          opensearch_cluster.client_for(
            "https://admin:s3cret@search.example.com:9200",
          )

        let refused =
          document.search(
            opensearch_cluster.client_for(
              opensearch_test_server.unreachable_base_url(),
            ),
            "books",
            "{}",
          )

        // Act
        let line =
          refused
          |> result.map_error(guide_handling_errors_log.failure_line(
            opensearch,
            _,
          ))
          |> result.map_error(guide_output.lines)

        // Assert
        line
        |> should
        |> be_equal(
          Error(guide_output.file("guide_handling_errors_failure_line")),
        )
        |> or_fail_with("The log line should not hold the password")
      }),
      it("address leaves out a port that the base URL does not set", fn() {
        // Act
        let address =
          guide_handling_errors_log.address(opensearch_cluster.client_for(
            "http://search.example.com",
          ))

        // Assert
        address
        |> should
        |> be_equal("http://search.example.com")
        |> or_fail_with("Expected no port")
      }),
    ]),
  ])
}
