//// Example for the `document.index` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

pub fn index_alice(opensearch: Client, index: String) -> String {
  let user =
    json.object([
      #("name", json.string("Alice")),
      #("email", json.string("alice@example.com")),
    ])

  case document.index(opensearch, index, "123", json.to_string(user)) {
    Ok(_response) -> "Indexed successfully"
    Error(message) -> "Error: " <> message
  }
}
