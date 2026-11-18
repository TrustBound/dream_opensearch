//// Example for the `document.create_index` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import gleam/json

pub fn create_users_index(opensearch: Client) -> Result(String, String) {
  let mapping =
    json.object([
      #(
        "mappings",
        json.object([
          #(
            "properties",
            json.object([
              #("name", json.object([#("type", json.string("text"))])),
              #("email", json.object([#("type", json.string("keyword"))])),
            ]),
          ),
        ]),
      ),
    ])
  document.create_index(opensearch, "users", json.to_string(mapping))
}
