//// Tests for the snippets and the error table of the error handling guide
//// (docs/guides/handling-errors.md). The answers of OpenSearch come from
//// the real cluster of `opensearch_cluster`. The local test server of
//// `opensearch_test_server` stands in only for what a cluster cannot be
//// made to do on demand: close a connection with no answer, send a body
//// that is not UTF-8. Refused connections go to a port where nothing
//// listens.
////
//// Each `text` block of the guide is a file in `test/outputs/`, and a test
//// here compares it with the real output (see `guide_output`).

import dream_opensearch/client.{type Client}
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
import opensearch_test_server.{type Reply, CloseWithoutAnswer, RespondBytes}
import snippets/guide_handling_errors_classify.{
  type OpenSearchError, BadConfiguration, Interrupted, OtherAnswer, Rejected,
  Unreachable,
}
import snippets/guide_handling_errors_log

/// `error` with the field labels of `Rejected`, as the guide shows it.
/// The other variants are printed with `string.inspect`.
fn labelled(error: OpenSearchError) -> String {
  case error {
    Rejected(status:, error_type:, reason:) ->
      "Rejected(status: "
      <> string.inspect(status)
      <> ", error_type: "
      <> string.inspect(error_type)
      <> ", reason: "
      <> string.inspect(reason)
      <> ")"
    _ -> string.inspect(error)
  }
  |> guide_output.lines
}

fn client_for(reply: Reply) -> Client {
  let server = opensearch_test_server.start(reply)
  client.new(opensearch_test_server.base_url(server))
}

fn search_books(opensearch: Client) -> Result(String, String) {
  document.search(opensearch, "books", "{}")
}

pub fn tests() -> TestSuite {
  describe("handling errors guide", [
    group("step 1: the error strings", [
      it("a refused connection", fn() {
        // Act
        let searched = search_books(client.new("http://127.0.0.1:1"))

        // Assert
        searched
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("Expected a refused connection")
      }),
      it("a host that does not resolve", fn() {
        // Act
        let searched =
          search_books(client.new("http://no-such-host.invalid:9200"))

        // Assert
        searched
        |> should
        |> be_equal(Error("Connection failed: DNS resolution failed (NXDOMAIN)"))
        |> or_fail_with("Expected a failed lookup")
      }),
      it("a server that closes the connection with no answer", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            CloseWithoutAnswer,
            CloseWithoutAnswer,
          ])
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let searched = search_books(opensearch)

        // Assert
        searched
        |> should
        |> be_equal(Error("Remote closed connection"))
        |> or_fail_with("Expected a closed connection")
      }),
      it("a closed connection makes the client send a POST one time", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            CloseWithoutAnswer,
            CloseWithoutAnswer,
          ])
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let searched = search_books(opensearch)

        // Assert
        [server, server]
        |> list.map(opensearch_test_server.await_request)
        |> list.map(result.map(_, opensearch_test_server.request_line))
        |> fn(requests) { #(searched, requests) }
        |> should
        |> be_equal(
          #(Error("Remote closed connection"), [
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
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let indexed = document.index(opensearch, "books", "1", "{}")

        // Assert
        [server, server]
        |> list.map(opensearch_test_server.await_request)
        |> list.map(result.map(_, opensearch_test_server.request_line))
        |> fn(requests) { #(indexed, requests) }
        |> should
        |> be_equal(
          #(Error("Remote closed connection"), [
            Ok(#("PUT", "/books/_doc/1")),
            Ok(#("PUT", "/books/_doc/1")),
          ]),
        )
        |> or_fail_with("The same PUT should arrive two times")
      }),
      it("a URL with no scheme", fn() {
        // Act
        let searched = search_books(client.new("localhost:9200"))

        // Assert
        searched
        |> should
        |> be_equal(Error("Invalid OpenSearch URL: the URL has no host"))
        |> or_fail_with("Expected no host")
      }),
      it("a URL that cannot be parsed", fn() {
        // Act
        let searched = search_books(client.new("http://[::1"))

        // Assert
        searched
        |> should
        |> be_equal(Error("Invalid OpenSearch URL: the URL cannot be parsed"))
        |> or_fail_with("Expected a parse error")
      }),
      it("a password with a bare percent sign", fn() {
        // Act
        let searched =
          search_books(client.new("http://admin:p%zz@localhost:9200"))

        // Assert
        searched
        |> should
        |> be_equal(Error(
          "Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding",
        ))
        |> or_fail_with("Expected a credentials error")
      }),
      it("an OpenSearch error comes back as its body", fn() {
        // Act
        let searched = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          // The index name varies, so put the name of the guide in its place
          document.search(opensearch, index, "{}")
          |> result.map_error(string.replace(_, index, "books"))
          |> Ok
        }

        // Assert
        searched
        |> result.map(fn(outcome) {
          case outcome {
            Ok(body) -> Error("Expected a 404, got: " <> body)
            Error(body) -> guide_output.stable_json(body, [])
          }
        })
        |> result.flatten
        |> should
        |> be_equal(
          guide_output.stable_file("guide_handling_errors_missing_index", []),
        )
        |> or_fail_with("Expected the error body")
      }),
      it("a plain text 401 comes back as its body", fn() {
        // Act
        let searched =
          search_books(client.new(opensearch_cluster.secured_base_url()))

        // Assert
        searched
        |> should
        |> be_equal(Error("Unauthorized"))
        |> or_fail_with("Expected Unauthorized")
      }),
      it("an error status with no body is an empty string", fn() {
        // Act
        let checked = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          Ok(client.send_request(opensearch, http.Head, "/" <> index, ""))
        }

        // Assert
        checked
        |> should
        |> be_equal(Ok(Error("")))
        |> or_fail_with("A HEAD for a missing index gets a 404 with no body")
      }),
      it("a body that is not UTF-8", fn() {
        // Act
        let searched = search_books(client_for(RespondBytes(200, <<255, 254>>)))

        // Assert
        searched
        |> should
        |> be_equal(Error("The OpenSearch response body is not valid UTF-8"))
        |> or_fail_with("Expected the UTF-8 error")
      }),
    ]),
    group("step 2 and 3: classify", [
      it("classify reads status, type and reason", fn() {
        // Act
        let error = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          // The index name varies, so put the name of the guide in its place
          document.search(opensearch, index, "{}")
          |> result.map_error(string.replace(_, index, "books"))
          |> result.map_error(guide_handling_errors_classify.classify)
          |> Ok
        }

        // Assert
        error
        |> result.map(result.map_error(_, labelled))
        |> should
        |> be_equal(
          Ok(Error(guide_output.file("guide_handling_errors_classified"))),
        )
        |> or_fail_with("Expected a 404 index_not_found_exception")
      }),
      it("classify sorts every kind of message", fn() {
        // Arrange
        let messages = [
          "Connection failed: Connection refused",
          "Remote closed connection",
          "Timed out after 30000ms",
          "Invalid OpenSearch URL: the URL has no host",
          "Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding",
          "Unauthorized",
          guide_responses.bad_gateway_page,
          "",
        ]

        // Act
        let errors = list.map(messages, guide_handling_errors_classify.classify)

        // Assert
        errors
        |> should
        |> be_equal([
          Unreachable("Connection refused"),
          Interrupted("Remote closed connection"),
          Interrupted("Timed out after 30000ms"),
          BadConfiguration("Invalid OpenSearch URL: the URL has no host"),
          BadConfiguration(
            "Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding",
          ),
          OtherAnswer("Unauthorized"),
          OtherAnswer(guide_responses.bad_gateway_page),
          OtherAnswer(""),
        ])
        |> or_fail_with("Each message should land in its variant")
      }),
    ]),
    group("step 4: retry", [
      it("worth_a_retry says yes to the passing failures", fn() {
        // Arrange
        let errors = [
          Unreachable("Connection refused"),
          Interrupted("Remote closed connection"),
          guide_handling_errors_classify.classify(
            guide_responses.cluster_not_ready,
          ),
          Rejected(429, "es_rejected_execution_exception", "busy"),
          Rejected(502, "bad_gateway", "proxy"),
          Rejected(504, "gateway_timeout", "proxy"),
        ]

        // Act
        let answers =
          list.map(errors, guide_handling_errors_classify.worth_a_retry)

        // Assert
        answers
        |> should
        |> be_equal([True, True, True, True, True, True])
        |> or_fail_with("All of these can pass")
      }),
      it("worth_a_retry says no to the rest", fn() {
        // Arrange
        let errors = [
          Rejected(404, "index_not_found_exception", "no such index [books]"),
          Rejected(400, "parsing_exception", "unknown query [matches]"),
          BadConfiguration("Invalid OpenSearch URL: the URL has no host"),
          OtherAnswer("Unauthorized"),
        ]

        // Act
        let answers =
          list.map(errors, guide_handling_errors_classify.worth_a_retry)

        // Assert
        answers
        |> should
        |> be_equal([False, False, False, False])
        |> or_fail_with("None of these change on their own")
      }),
    ]),
    group("step 5: logs", [
      it("failure_line leaves out the user name and password", fn() {
        // Arrange
        let opensearch =
          client.new("https://admin:s3cret@search.example.com:9200")

        let refused =
          document.search(
            client.new(opensearch_test_server.unreachable_base_url()),
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
      it("safe_url names a URL it cannot parse", fn() {
        // Act
        let url = guide_handling_errors_log.safe_url(client.new("http://[::1"))

        // Assert
        url
        |> should
        |> be_equal("(a base URL that cannot be parsed)")
        |> or_fail_with("Expected the placeholder")
      }),
    ]),
  ])
}
