//// Guide: Handling errors, step 5
////
//// Makes a client with a timeout of its own.

import dream_http_client/client as http_client
import dream_opensearch/client.{type Client}
import gleam/http

/// A client for the cluster at `host` and `port` that waits at most
/// `timeout_ms` for each answer.
pub fn client_with_timeout(host: String, port: Int, timeout_ms: Int) -> Client {
  http_client.new()
  |> http_client.scheme(http.Http)
  |> http_client.host(host)
  |> http_client.port(port)
  |> http_client.timeout(timeout_ms)
  |> client.from_request
}
