//// Example for the `document.delete` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn delete_user(opensearch: Client, index: String) -> String {
  case document.delete(opensearch, index, "123") {
    Ok(_response) -> "Document deleted"
    Error(message) -> "Error: " <> message
  }
}
