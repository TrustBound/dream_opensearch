//// Guide: Handling errors, step 4
////
//// Writes a log line for a failed request, with the cluster address but
//// without the user name and password.

import dream_http_client/client as http_client
import dream_opensearch/client.{type Client, type OpenSearchError}
import gleam/http
import gleam/int
import gleam/option.{None, Some}

/// The scheme, the host and the port of `opensearch`. The base request
/// keeps the password only in its `authorization` header, so this has none.
pub fn address(opensearch: Client) -> String {
  let base = client.base_request(opensearch)
  let port = case http_client.get_port(base) {
    Some(port) -> ":" <> int.to_string(port)
    None -> ""
  }
  http.scheme_to_string(http_client.get_scheme(base))
  <> "://"
  <> http_client.get_host(base)
  <> port
}

pub fn failure_line(opensearch: Client, error: OpenSearchError) -> String {
  "OpenSearch request to "
  <> address(opensearch)
  <> " failed: "
  <> client.describe_error(error)
}
