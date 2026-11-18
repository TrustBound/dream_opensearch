//// Example for the `document.delete` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn delete_user(opensearch: Client) -> String {
  case document.delete(opensearch, "users", "123") {
    Ok(_response) -> "Document deleted"
    Error(message) -> "Error: " <> message
  }
}
