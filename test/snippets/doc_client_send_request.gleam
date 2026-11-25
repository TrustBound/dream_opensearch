//// Example for the `client.send_request` doc.

import dream_opensearch/client.{type Client, type OpenSearchError}
import gleam/http

pub fn get_user(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  client.send_request(opensearch, http.Get, "/" <> index <> "/_doc/123", "")
}
