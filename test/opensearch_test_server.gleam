//// One-shot local HTTP server that records the request it receives.
////
//// Each `start` opens a new socket on 127.0.0.1 with a port chosen by the
//// operating system, so tests never share a port. The server accepts one
//// connection, answers as told by `Reply`, and stops.

import gleam/int
import gleam/list

pub type TestServer

/// What the server does after it has read the request.
pub type Reply {
  /// Answer with this status and body (content-type: application/json).
  Respond(status: Int, body: String)
  /// Answer with this status and these body bytes, which need not be text.
  RespondBytes(status: Int, body: BitArray)
  /// Report the first bytes the client sends, then close (used for TLS).
  CaptureRawBytes
  /// Read the request, then close the connection with no answer.
  CloseWithoutAnswer
  /// Read the request, then send nothing until the client closes the
  /// connection (or 3 seconds pass).
  HoldWithoutAnswer
}

/// The request as it arrived on the wire. Header names are lowercase.
pub type CapturedRequest {
  CapturedRequest(
    method: String,
    target: String,
    headers: List(#(String, String)),
    body: String,
  )
}

@external(erlang, "opensearch_test_server_ffi", "start")
pub fn start(reply: Reply) -> TestServer

/// Like `start`, but answers one connection for each reply, in order. Use
/// it for code that sends more than one request. `await_request` returns
/// the captured requests in the order they arrived.
@external(erlang, "opensearch_test_server_ffi", "start_sequence")
pub fn start_sequence(replies: List(Reply)) -> TestServer

@external(erlang, "opensearch_test_server_ffi", "port")
pub fn port(server: TestServer) -> Int

@external(erlang, "opensearch_test_server_ffi", "await_request")
pub fn await_request(server: TestServer) -> Result(CapturedRequest, Nil)

@external(erlang, "opensearch_test_server_ffi", "await_raw_bytes")
pub fn await_raw_bytes(server: TestServer) -> Result(BitArray, Nil)

@external(erlang, "opensearch_test_server_ffi", "unused_port")
pub fn unused_port() -> Int

/// `http://127.0.0.1:<port>` for this server.
pub fn base_url(server: TestServer) -> String {
  "http://127.0.0.1:" <> int.to_string(port(server))
}

/// A base URL on 127.0.0.1 where nothing listens.
pub fn unreachable_base_url() -> String {
  "http://127.0.0.1:" <> int.to_string(unused_port())
}

/// Method and request target, e.g. `#("PUT", "/users/_doc/123")`.
pub fn request_line(request: CapturedRequest) -> #(String, String) {
  #(request.method, request.target)
}

/// Every value sent for the header `name` (lowercase), in order.
pub fn header_values(request: CapturedRequest, name: String) -> List(String) {
  list.key_filter(request.headers, name)
}

/// The body of the captured request.
pub fn request_body(request: CapturedRequest) -> String {
  request.body
}

/// Method, request target and body, e.g.
/// `#("POST", "/users/_search", "{}")`.
pub fn request_line_and_body(
  request: CapturedRequest,
) -> #(String, String, String) {
  #(request.method, request.target, request.body)
}

/// `http://<userinfo>@127.0.0.1:<port>` for this server, e.g. with
/// `userinfo` set to `user:pass`.
pub fn base_url_with_userinfo(server: TestServer, userinfo: String) -> String {
  "http://" <> userinfo <> "@127.0.0.1:" <> int.to_string(port(server))
}
