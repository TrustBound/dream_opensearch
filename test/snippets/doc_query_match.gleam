//// Example for the `query.match` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

// Search for users with "Alice" in the name field
pub fn search_users_named_alice(
  opensearch: Client,
  index: String,
) -> Result(String, String) {
  let name_query = query.match("name", "Alice")
  document.search(opensearch, index, name_query)
}
