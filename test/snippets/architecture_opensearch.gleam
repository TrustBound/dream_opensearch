//// Architecture reference: dream_opensearch
////
//// Creates a client and indexes one log document.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import gleam/json

pub fn create_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

pub fn index_log_entry(
  opensearch: Client,
  index: String,
  message: String,
) -> Result(String, OpenSearchError) {
  let document_json =
    json.object([#("message", json.string(message))])
    |> json.to_string()
  document.index(opensearch, index, "doc-id-123", document_json)
}
