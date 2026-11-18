//// Example for the `document.search` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

pub fn search_for_alice(opensearch: Client) -> Result(String, String) {
  let name_query = query.match("name", "Alice")
  document.search(opensearch, "users", name_query)
}
