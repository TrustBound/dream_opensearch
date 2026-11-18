//// Example for the `dream_opensearch/document` module doc: quick start.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

pub fn create_client() -> Client {
  client.new("http://localhost:9200")
}

pub fn index_alice(opensearch: Client) -> Result(String, String) {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
    ])
  document.index(opensearch, "users", "123", json.to_string(user))
}
