//// Example for the `query.match_all` doc.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document
import dream_opensearch/query

pub fn search_all_users(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  let all_query = query.match_all()
  document.search(opensearch, index, all_query)
}
