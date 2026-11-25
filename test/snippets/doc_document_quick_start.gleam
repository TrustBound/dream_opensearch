//// Example for the `dream_opensearch/document` module doc: quick start.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import gleam/json

pub fn create_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

pub fn index_alice(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
    ])
  document.index(opensearch, index, "123", json.to_string(user))
}
