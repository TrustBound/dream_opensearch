//// Example for the `document.delete_index` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn delete_old_index(opensearch: Client, index: String) -> String {
  case document.delete_index(opensearch, index) {
    Ok(_response) -> "Index deleted"
    Error(message) -> "Error: " <> message
  }
}
