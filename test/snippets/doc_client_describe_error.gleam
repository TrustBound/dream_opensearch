//// Example for the `client.describe_error` doc.

import dream_opensearch/client.{type Client}
import gleam/http

pub fn health_line(opensearch: Client) -> String {
  case client.send_request(opensearch, http.Get, "/_cluster/health", "") {
    Ok(_body) -> "OpenSearch is healthy"
    Error(error) -> client.describe_error(error)
  }
}
