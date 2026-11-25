//// Guide: Handling errors, steps 2 and 3
////
//// Reads the error object out of an OpenSearch answer, and decides which
//// errors are worth a retry.

import dream_opensearch/client.{
  type OpenSearchError, InvalidResponseBody, InvalidUrl, NoRecording, Rejected,
  TimedOut, Unavailable,
}
import gleam/dynamic/decode
import gleam/json
import gleam/result

/// The `error` object of an OpenSearch answer.
pub type ErrorDetails {
  ErrorDetails(error_type: String, reason: String)
}

/// The type and the reason of a `Rejected` error, when its body is an
/// OpenSearch error object. `Error(Nil)` for any other error or body.
pub fn error_details(error: OpenSearchError) -> Result(ErrorDetails, Nil) {
  case error {
    Rejected(body:, ..) ->
      json.parse(body, details_decoder())
      |> result.replace_error(Nil)
    _ -> Error(Nil)
  }
}

fn details_decoder() -> decode.Decoder(ErrorDetails) {
  use error_type <- decode.subfield(["error", "type"], decode.string)
  use reason <- decode.subfield(["error", "reason"], decode.string)
  decode.success(ErrorDetails(error_type:, reason:))
}

/// True for the errors that can go away if you send the same request
/// again a little later.
pub fn worth_a_retry(error: OpenSearchError) -> Bool {
  case error {
    Unavailable(_) | TimedOut(_) -> True
    Rejected(status: 429, ..)
    | Rejected(status: 502, ..)
    | Rejected(status: 503, ..)
    | Rejected(status: 504, ..) -> True
    Rejected(..) | InvalidUrl(_) | InvalidResponseBody(_) | NoRecording(..) ->
      False
  }
}
