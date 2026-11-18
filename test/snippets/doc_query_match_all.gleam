//// Example for the `query.match_all` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

pub fn search_all_users(opensearch: Client) -> Result(String, String) {
  let all_query = query.match_all()
  document.search(opensearch, "users", all_query)
}
