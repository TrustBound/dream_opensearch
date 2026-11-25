//// Example for the `dream_opensearch/client` module doc: quick start.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document

pub fn create_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

pub fn index_alice(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
}
