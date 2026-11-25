//// Example for the `dream_opensearch/client` module doc: quick start.

import dream_opensearch/client.{type Client}
import dream_opensearch/document

pub fn create_client() -> Client {
  client.new("http://localhost:9200")
}

pub fn index_alice(
  opensearch: Client,
  index: String,
) -> Result(String, String) {
  document.index(opensearch, index, "123", "{\"name\":\"Alice\"}")
}
