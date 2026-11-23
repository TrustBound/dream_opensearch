//// Guide: Handling errors, steps 2 to 4
////
//// Turns the error string of dream_opensearch into a typed error, and
//// decides which errors are worth a retry.

import gleam/dynamic/decode
import gleam/json

pub type OpenSearchError {
  /// The client could not connect: refused, unknown host, TLS failure.
  Unreachable(reason: String)
  /// The connection broke or went quiet after the request went out.
  Interrupted(message: String)
  /// The base URL cannot be used. No request went out.
  BadConfiguration(message: String)
  /// OpenSearch answered with an error object.
  Rejected(status: Int, error_type: String, reason: String)
  /// Any other answer with an error status, as it came.
  OtherAnswer(body: String)
}

pub fn classify(message: String) -> OpenSearchError {
  case message {
    "Connection failed: " <> reason -> Unreachable(reason)
    "Remote closed connection" | "Timed out after " <> _ -> Interrupted(message)
    "Invalid OpenSearch URL: " <> _
    | "Invalid credentials in the OpenSearch URL: " <> _ ->
      BadConfiguration(message)
    _ -> from_body(message)
  }
}

fn from_body(body: String) -> OpenSearchError {
  case json.parse(body, rejected_decoder()) {
    Ok(rejected) -> rejected
    Error(_) -> OtherAnswer(body)
  }
}

fn rejected_decoder() -> decode.Decoder(OpenSearchError) {
  use status <- decode.field("status", decode.int)
  use error_type <- decode.subfield(["error", "type"], decode.string)
  use reason <- decode.subfield(["error", "reason"], decode.string)
  decode.success(Rejected(status:, error_type:, reason:))
}

/// True for the errors that can go away if you send the same request
/// again a little later.
pub fn worth_a_retry(error: OpenSearchError) -> Bool {
  case error {
    Unreachable(_) | Interrupted(_) -> True
    Rejected(status: 429, ..)
    | Rejected(status: 502, ..)
    | Rejected(status: 503, ..)
    | Rejected(status: 504, ..) -> True
    Rejected(..) | BadConfiguration(_) | OtherAnswer(_) -> False
  }
}
