//// Example for the `document.delete_index` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn delete_old_index(opensearch: Client) -> String {
  case document.delete_index(opensearch, "old_index") {
    Ok(_response) -> "Index deleted"
    Error(message) -> "Error: " <> message
  }
}
