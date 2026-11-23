//// Guide: Handling errors, step 5
////
//// Writes a log line for a failed request, with the cluster address but
//// without the user name and password.

import dream_opensearch/client.{type Client}
import gleam/option.{None}
import gleam/uri.{Uri}

/// The base URL of `opensearch` without its user name and password.
pub fn safe_url(opensearch: Client) -> String {
  case uri.parse(opensearch.base_url) {
    Ok(parsed) -> uri.to_string(Uri(..parsed, userinfo: None))
    Error(Nil) -> "(a base URL that cannot be parsed)"
  }
}

pub fn failure_line(opensearch: Client, message: String) -> String {
  "OpenSearch request to " <> safe_url(opensearch) <> " failed: " <> message
}
