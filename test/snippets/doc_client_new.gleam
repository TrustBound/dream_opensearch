//// Example for the `client.new` doc.

import dream_opensearch/client.{type Client, type OpenSearchError}

pub fn create_local_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

pub fn create_client_with_credentials() -> Result(Client, OpenSearchError) {
  client.new("https://user:pass@search.example.com:9200")
}
