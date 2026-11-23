//// Example for the `query.term` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

// Find all users with status "active"
pub fn search_active_users(
  opensearch: Client,
  index: String,
) -> Result(String, String) {
  let status_query = query.term("status", "active")
  document.search(opensearch, index, status_query)
}
