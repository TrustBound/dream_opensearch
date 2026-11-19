//// Example for the `client.send_request` doc.

import dream_opensearch/client.{type Client}
import gleam/http

pub fn get_user(opensearch: Client) -> Result(String, String) {
  client.send_request(opensearch, http.Get, "/users/_doc/123", "")
}
