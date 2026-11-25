//// Example for the `dream_opensearch/query` module doc: quick start.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import dream_opensearch/query

// Full-text search
pub fn search_by_name(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  let name_query = query.match("name", "Alice")
  document.search(opensearch, index, name_query)
}

// Exact term match
pub fn search_by_status(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  let status_query = query.term("status", "active")
  document.search(opensearch, index, status_query)
}
