//// OpenSearch HTTP client
////
//// This module provides a simple HTTP client for interacting with OpenSearch
//// (or Elasticsearch) clusters. It handles the low-level HTTP communication
//// needed for document operations, searches, and index management.
////
//// ## Quick Start
////
//// ### Create a client and index a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_quick_start.gleam#L3-L15"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
////
//// ```gleam
//// import dream_opensearch/client.{type Client, type OpenSearchError}
//// import dream_opensearch/document
////
//// pub fn create_client() -> Result(Client, OpenSearchError) {
////   client.new("http://localhost:9200")
//// }
////
//// pub fn index_alice(
////   opensearch: Client,
////   index: String,
//// ) -> Result(String, OpenSearchError) {
////   document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
//// }
//// ```
////
//// ## Two ways to make a client
////
//// - `new` takes a base URL, such as `http://localhost:9200`. It checks the
////   URL one time and returns `Error(InvalidUrl(..))` when it cannot use it.
//// - `from_request` takes a dream_http_client `ClientRequest`. Use it to set
////   what a URL cannot hold: a timeout, a connection pool, a certificate
////   authority file, other headers, or a recorder for tests.
////
//// Each request of the client starts from the same base request. It keeps
//// the scheme, the host, the port, the headers, the timeouts and the
//// recorder of the base request, and sets the method, the path, the query
//// and the body.
////
//// ## Base URL
////
//// The base URL should point to your OpenSearch cluster. It can include a
//// user name and password, which the client sends as HTTP Basic
//// authentication on every request:
////
//// - `http://localhost:9200`
//// - `https://search.example.com:9200`
//// - `https://user:pass@search.example.com:9200`
////
//// Percent-encode `@`, `:` and `/` in the user name or password (`%40`,
//// `%3A`, `%2F`). The client decodes them before it builds the
//// `authorization` header.
////
//// ## Errors
////
//// Every function returns `OpenSearchError` for a failure. Match on its
//// variants to decide what to do, and use `describe_error` for a log line.

import dream_errors.{type Error, Conflict, Failed, Invalid, NotFound, Timeout}
import dream_http_client/client.{
  type ClientRequest, type Header, type HttpResponse, type SendError,
  type TransportError, ConnectFailed, ConnectionError, Goaway, ProcessDown,
  RemoteClosed, RequestError, ResponseError, StreamReset, Unexpected, add_header,
  get_headers, get_path, send, transport_error_to_string,
} as http_client
import gleam/bit_array.{base64_encode, from_string}
import gleam/http.{type Method, type Scheme, Http, Https}
import gleam/int.{to_string}
import gleam/list.{filter}
import gleam/option.{type Option, None, Some, to_result}
import gleam/result.{map, replace_error, try, unwrap}
import gleam/string.{drop_end, ends_with, lowercase, split_once}
import gleam/uri.{type Uri, parse, percent_decode}

/// OpenSearch client configuration
///
/// A connection to an OpenSearch cluster: the base request that every
/// request of the client starts from. Make one with `new` or
/// `from_request`, and read the base request with `base_request`.
///
/// The type is opaque, so a `Client` always holds a base request that `new`
/// or `from_request` made.
pub opaque type Client {
  Client(base: ClientRequest)
}

/// Why an OpenSearch request failed.
///
/// No variant holds the user name or the password of the base URL.
///
/// ## Variants
///
/// - `InvalidUrl`: `new` cannot use the base URL. `reason` says why, for
///   example `the URL has no host`. Only `new` returns it, and no request is
///   sent.
/// - `Unavailable`: the request got no HTTP answer. The connection was
///   refused or closed, the host name did not resolve, the TLS handshake
///   failed, or the HTTP/2 stream or connection failed. `reason` is the
///   text of the dream_http_client transport error, for example
///   `Connection failed: Connection refused`.
/// - `TimedOut`: no answer came within the timeout of the request, which is
///   30000 ms unless the base request sets another. The request was sent,
///   and the cluster can still finish it. `timeout_ms` is that timeout.
/// - `Rejected`: OpenSearch answered with status 400 or more. `body` is its
///   answer, which usually holds the error details as JSON.
/// - `InvalidResponseBody`: the answer body is not valid UTF-8. `status` is
///   the status of the answer, with any value.
/// - `NoRecording`: the base request has a dream_http_client recorder in
///   playback mode, and no recording matches the request. Nothing is sent.
///   `method` and `url` name the request, and `details` is the text of
///   dream_http_client, which shows the nearest recordings.
pub type OpenSearchError {
  /// `new` cannot use the base URL.
  InvalidUrl(reason: String)
  /// The request got no HTTP answer.
  Unavailable(reason: String)
  /// No answer came within the timeout of the request.
  TimedOut(timeout_ms: Int)
  /// OpenSearch answered with status 400 or more.
  Rejected(status: Int, body: String)
  /// The answer body is not valid UTF-8.
  InvalidResponseBody(status: Int)
  /// A playback recorder has no recording for the request.
  NoRecording(method: String, url: String, details: String)
}

/// Create a new OpenSearch client from a base URL
///
/// The base URL must have the scheme `http` or `https` and a host. It can
/// have a port, a path prefix, and a user name and password. A trailing
/// slash is removed.
///
/// A user name and password in the URL (`https://user:pass@host:9200`) make
/// every request send the header
/// `authorization: Basic <base64(user:password)>`. The user name and
/// password are percent-decoded first, and a URL with no password sends an
/// empty password. They are not sent in the request line or the `host`
/// header.
///
/// ## Parameters
///
/// - `base_url`: The base URL of the OpenSearch cluster
///
/// ## Returns
///
/// - `Ok(Client)`: a client for the cluster at `base_url`.
/// - `Error(InvalidUrl(reason))`: the URL cannot be used. `reason` is one of:
///   - `the URL cannot be parsed`
///   - `the URL scheme must be http or https`
///   - `the URL has no host`
///   - `the URL has a query or a fragment`
///   - `the user name or password has invalid percent-encoding`
///
/// No reason contains the user name or password.
///
/// ## See Also
///
/// - `from_request`: makes a client from a dream_http_client request.
/// - `send_request`: sends a request to the cluster of this client.
///
/// ## Example
///
/// ### Create a client <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_new.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client, type OpenSearchError}
///
/// pub fn create_local_client() -> Result(Client, OpenSearchError) {
///   client.new("http://localhost:9200")
/// }
///
/// pub fn create_client_with_credentials() -> Result(Client, OpenSearchError) {
///   client.new("https://user:pass@search.example.com:9200")
/// }
/// ```
pub fn new(base_url: String) -> Result(Client, OpenSearchError) {
  use parsed <- try(parse(base_url) |> invalid_url("the URL cannot be parsed"))
  use scheme <- try(parse_scheme(parsed.scheme))
  use host <- try(
    to_result(parsed.host, Nil) |> invalid_url("the URL has no host"),
  )
  use Nil <- try(reject_query_and_fragment(parsed))
  use authorization <- try(parse_authorization(parsed.userinfo))
  http_client.new()
  |> http_client.scheme(scheme)
  |> http_client.host(host)
  |> add_port(parsed.port)
  |> http_client.path(trim_trailing_slash(parsed.path))
  |> add_authorization(authorization)
  |> from_request
  |> Ok
}

/// Create a new OpenSearch client from a dream_http_client request
///
/// Every request of the client starts from `base`. It keeps the scheme, the
/// host, the port, the headers, the timeouts, the connection pool, the
/// certificate authority file and the recorder of `base`. For each request,
/// the client sets the method, the body and the header
/// `content-type: application/json`, which replaces a `content-type` header
/// of `base`. The path of the request is the path of `base` with the API
/// path added after it, so the path of `base` is a prefix. A query in the
/// API path replaces the query of `base`.
///
/// ## Parameters
///
/// - `base`: The dream_http_client request that every request starts from
///
/// ## Returns
///
/// A `Client` for the cluster of `base`.
///
/// ## See Also
///
/// - `new`: makes a client from a base URL.
/// - `base_request`: reads the base request back.
///
/// ## Example
///
/// ### Create a client with a timeout and a recorder <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_from_request.gleam#L3-L16"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_http_client/client as http_client
/// import dream_http_client/recorder.{type Recorder}
/// import dream_opensearch/client.{type Client}
/// import gleam/http
///
/// pub fn create_recorded_client(recorder: Recorder) -> Client {
///   http_client.new()
///   |> http_client.scheme(http.Http)
///   |> http_client.host("localhost")
///   |> http_client.port(9201)
///   |> http_client.timeout(5000)
///   |> http_client.recorder(recorder)
///   |> client.from_request
/// }
/// ```
pub fn from_request(base: ClientRequest) -> Client {
  Client(base: http_client.path(base, trim_trailing_slash(get_path(base))))
}

/// The base request of a client
///
/// Returns the dream_http_client request that every request of `client`
/// starts from. For a client from `new`, it holds the scheme, the host, the
/// port, the path prefix and the `authorization` header of the base URL.
///
/// The `authorization` header holds the password in base64. Do not print or
/// log it.
///
/// ## Example
///
/// ### Read the host of a client <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_base_request.gleam#L3-L8"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_http_client/client as http_client
/// import dream_opensearch/client.{type Client}
///
/// pub fn host_of(opensearch: Client) -> String {
///   http_client.get_host(client.base_request(opensearch))
/// }
/// ```
pub fn base_request(client: Client) -> ClientRequest {
  client.base
}

/// Send HTTP request to OpenSearch
///
/// Sends a raw HTTP request to the OpenSearch cluster. The
/// `dream_opensearch/document` module uses it for every operation. Most
/// applications should use that module instead.
///
/// The request starts from the base request of the client (see
/// `from_request`) and has the header `content-type: application/json`.
///
/// ## Parameters
///
/// - `client`: The OpenSearch client
/// - `method`: The HTTP method (GET, POST, PUT, DELETE, etc.)
/// - `path`: The API path (e.g., "/users/_doc/123" or "/users/_search"),
///   sent after the path prefix of the client as it is. A `?` starts the
///   query. This function does not percent-encode the path: encode an index
///   name or a document ID with characters outside `A-Z a-z 0-9 - . _ ~`
///   yourself. The `dream_opensearch/document` functions encode them for
///   you.
/// - `body`: The request body as a JSON string
///
/// ## Returns
///
/// - `Ok(String)`: The response body as a string (status < 400)
/// - `Error(OpenSearchError)`: See Errors.
///
/// ## Errors
///
/// - `Rejected(status, body)`: the response status is 400 or more. `body`
///   is the response body, unchanged.
/// - `Unavailable(reason)`: the request got no answer. For example
///   `Connection failed: Connection refused`, or
///   `Connection failed: DNS resolution failed (NXDOMAIN)` for a host name
///   that does not resolve. When the server closes the connection with no
///   answer, the reason is `Remote closed connection`: for GET, HEAD, PUT
///   and DELETE, the HTTP client sends the request once more on a new
///   connection before it returns this error. It sends a POST one time
///   only.
/// - `TimedOut(timeout_ms)`: the server sent no answer within the timeout
///   (30000 ms unless the base request sets another). The request was sent,
///   and the cluster can still finish it.
/// - `InvalidResponseBody(status)`: the response body is not valid UTF-8,
///   with any status.
/// - `NoRecording(method, url, details)`: a playback recorder of the base
///   request has no recording for the request. Nothing is sent.
///
/// No error contains the user name or password of the base URL.
///
/// ## See Also
///
/// - `new` and `from_request`: create the client.
/// - `describe_error`: turns an error into one line of text.
/// - `dream_opensearch/document`: the operations built on this function.
///
/// ## Example
///
/// ### Get a document <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_send_request.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client, type OpenSearchError}
/// import gleam/http
///
/// pub fn get_user(
///   opensearch: Client,
///   index: String,
/// ) -> Result(String, OpenSearchError) {
///   client.send_request(opensearch, http.Get, "/" <> index <> "/_doc/123", "")
/// }
/// ```
pub fn send_request(
  client: Client,
  method: Method,
  path: String,
  body: String,
) -> Result(String, OpenSearchError) {
  client.base
  |> build_request(method, path, body)
  |> send
  |> response_to_result
}

/// Turn an error into one line of text
///
/// The text names the kind of failure and its details, for a log or a
/// message to an operator. It never holds the user name or password of the
/// base URL. A `Rejected` error holds the body of the OpenSearch answer.
///
/// ## Returns
///
/// - `InvalidUrl(reason)`: `Invalid OpenSearch URL: <reason>`
/// - `Unavailable(reason)`: `OpenSearch is unavailable: <reason>`
/// - `TimedOut(timeout_ms)`: `OpenSearch sent no answer within <timeout_ms> ms`
/// - `Rejected(status, body)`: `OpenSearch rejected the request with status <status>: <body>`
/// - `InvalidResponseBody(status)`: `The OpenSearch response body is not valid UTF-8 (status <status>)`
/// - `NoRecording(method, url, details)`: `No recording for the OpenSearch request: <details>`.
///   `details` can have more than one line.
///
/// ## Example
///
/// ### Log an error <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_describe_error.gleam#L3-L11"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
/// import dream_opensearch/client.{type Client}
/// import gleam/http
///
/// pub fn health_line(opensearch: Client) -> String {
///   case client.send_request(opensearch, http.Get, "/_cluster/health", "") {
///     Ok(_body) -> "OpenSearch is healthy"
///     Error(error) -> client.describe_error(error)
///   }
/// }
/// ```
pub fn describe_error(error: OpenSearchError) -> String {
  case error {
    InvalidUrl(reason:) -> "Invalid OpenSearch URL: " <> reason
    Unavailable(reason:) -> "OpenSearch is unavailable: " <> reason
    TimedOut(timeout_ms:) ->
      "OpenSearch sent no answer within " <> to_string(timeout_ms) <> " ms"
    Rejected(status:, body:) ->
      "OpenSearch rejected the request with status "
      <> to_string(status)
      <> ": "
      <> body
    InvalidResponseBody(status:) ->
      "The OpenSearch response body is not valid UTF-8 (status "
      <> to_string(status)
      <> ")"
    NoRecording(details:, ..) ->
      "No recording for the OpenSearch request: " <> details
  }
}

/// Map an error to the shared error of the Dream packages
///
/// Gives a `dream_errors.Error`, the error type that the Dream packages
/// share, and keeps the `OpenSearchError` as the cause. The message is the
/// text of `describe_error`: text for developers and logs, not for the
/// users of an app.
///
/// ## Returns
///
/// - `InvalidUrl`: `Invalid`
/// - `Unavailable`: `Unavailable`
/// - `TimedOut`: `Timeout`
/// - `Rejected` with status 404: `NotFound`. `NotFound` has no cause, so
///   the message holds the status and the body.
/// - `Rejected` with status 409: `Conflict`
/// - `Rejected` with another status, `InvalidResponseBody` and
///   `NoRecording`: `Failed`
///
/// ## Example
///
/// ### Read a document with the shared error <a href="https://github.com/TrustBound/dream_opensearch/blob/4.1.0/test/snippets/doc_client_to_error.gleam#L5-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>
///
/// ```gleam
///   type Client, type OpenSearchError, send_request, to_error,
/// }
/// import gleam/http.{Get}
/// import gleam/result.{map_error}
///
/// pub fn get_document(
///   opensearch: Client,
///   index: String,
///   id: String,
/// ) -> Result(String, Error(OpenSearchError)) {
///   send_request(opensearch, Get, "/" <> index <> "/_doc/" <> id, "")
///   |> map_error(to_error)
/// }
/// ```
pub fn to_error(error: OpenSearchError) -> Error(OpenSearchError) {
  let message = describe_error(error)
  case error {
    InvalidUrl(..) -> Invalid(message, error)
    Unavailable(..) -> dream_errors.Unavailable(message, error)
    TimedOut(..) -> Timeout(message, error)
    Rejected(status: 404, ..) -> NotFound(message)
    Rejected(status: 409, ..) -> Conflict(message, error)
    Rejected(..) | InvalidResponseBody(..) | NoRecording(..) ->
      Failed(message, error)
  }
}

fn invalid_url(
  outcome: Result(value, Nil),
  reason: String,
) -> Result(value, OpenSearchError) {
  replace_error(outcome, InvalidUrl(reason:))
}

fn parse_scheme(scheme: Option(String)) -> Result(Scheme, OpenSearchError) {
  case scheme {
    Some("http") -> Ok(Http)
    Some("https") -> Ok(Https)
    _ -> Error(InvalidUrl(reason: "the URL scheme must be http or https"))
  }
}

fn reject_query_and_fragment(parsed: Uri) -> Result(Nil, OpenSearchError) {
  case parsed.query, parsed.fragment {
    None, None -> Ok(Nil)
    _, _ -> Error(InvalidUrl(reason: "the URL has a query or a fragment"))
  }
}

fn trim_trailing_slash(path: String) -> String {
  case ends_with(path, "/") {
    True -> drop_end(path, 1)
    False -> path
  }
}

fn parse_authorization(
  userinfo: Option(String),
) -> Result(Option(String), OpenSearchError) {
  case userinfo {
    None -> Ok(None)
    Some(encoded_userinfo) ->
      encoded_userinfo
      |> decode_credentials
      |> map(basic_authorization)
      |> map(Some)
  }
}

/// Splits `user:password` at the first `:` and percent-decodes both parts.
/// A userinfo with no `:` is a user name with an empty password.
/// The error never holds the user name or the password.
fn decode_credentials(
  encoded_userinfo: String,
) -> Result(#(String, String), OpenSearchError) {
  let #(encoded_user, encoded_password) =
    split_once(encoded_userinfo, on: ":")
    |> unwrap(#(encoded_userinfo, ""))
  let invalid_encoding =
    "the user name or password has invalid percent-encoding"
  use user <- try(percent_decode(encoded_user) |> invalid_url(invalid_encoding))
  use password <- try(
    percent_decode(encoded_password) |> invalid_url(invalid_encoding),
  )
  Ok(#(user, password))
}

fn basic_authorization(credentials: #(String, String)) -> String {
  let #(user, password) = credentials
  "Basic " <> base64_encode(from_string(user <> ":" <> password), True)
}

fn build_request(
  base: ClientRequest,
  method: Method,
  path: String,
  body: String,
) -> ClientRequest {
  let #(api_path, query) = split_query(path)
  base
  |> http_client.method(method)
  |> http_client.path(root_if_empty(get_path(base) <> api_path))
  |> add_query(query)
  |> http_client.headers(without_content_type(get_headers(base)))
  |> add_header("content-type", "application/json")
  |> http_client.body(body)
}

fn split_query(path: String) -> #(String, Option(String)) {
  case split_once(path, on: "?") {
    Ok(#(api_path, query)) -> #(api_path, Some(query))
    Error(Nil) -> #(path, None)
  }
}

fn root_if_empty(path: String) -> String {
  case path {
    "" -> "/"
    _ -> path
  }
}

fn without_content_type(headers: List(Header)) -> List(Header) {
  filter(headers, fn(header) { lowercase(header.name) != "content-type" })
}

fn add_port(request: ClientRequest, port: Option(Int)) -> ClientRequest {
  case port {
    Some(port_value) -> http_client.port(request, port_value)
    None -> request
  }
}

fn add_query(request: ClientRequest, query: Option(String)) -> ClientRequest {
  case query {
    Some(query_value) -> http_client.query(request, query_value)
    None -> request
  }
}

fn add_authorization(
  request: ClientRequest,
  authorization: Option(String),
) -> ClientRequest {
  case authorization {
    Some(header_value) -> add_header(request, "authorization", header_value)
    None -> request
  }
}

fn response_to_result(
  response: Result(HttpResponse, SendError),
) -> Result(String, OpenSearchError) {
  case response {
    Ok(response) -> body_text(response)
    Error(ResponseError(response: response)) ->
      body_text(response) |> try(rejected(response.status, _))
    Error(RequestError(error: transport_error)) ->
      Error(from_transport_error(transport_error))
  }
}

fn rejected(status: Int, body: String) -> Result(String, OpenSearchError) {
  Error(Rejected(status:, body:))
}

// OpenSearch answers with JSON, which is UTF-8. A body that is not UTF-8 has
// no text form, so it is an error.
fn body_text(response: HttpResponse) -> Result(String, OpenSearchError) {
  http_client.body_text(response)
  |> replace_error(InvalidResponseBody(status: response.status))
}

// Each variant of `http_client.TransportError` is named, with no catch-all,
// so a new variant in dream_http_client is a compile error here.
fn from_transport_error(error: TransportError) -> OpenSearchError {
  case error {
    http_client.TimedOut(timeout_ms:) -> TimedOut(timeout_ms:)
    http_client.NoRecording(method:, url:, ..) ->
      NoRecording(method:, url:, details: transport_error_to_string(error))
    ConnectFailed(..)
    | RemoteClosed
    | StreamReset(..)
    | Goaway(..)
    | ConnectionError(..)
    | ProcessDown(..)
    | Unexpected(..) -> Unavailable(reason: transport_error_to_string(error))
  }
}
