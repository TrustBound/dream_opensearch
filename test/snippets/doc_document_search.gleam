//// Example for the `document.search` doc.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import dream_opensearch/query

pub fn search_for_alice(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  let name_query = query.match("name", "Alice")
  document.search(opensearch, index, name_query)
}
