//// Example for the `client.new` doc.

import dream_opensearch/client.{type Client}

pub fn create_local_client() -> Client {
  client.new("http://localhost:9200")
}

pub fn create_client_with_credentials() -> Client {
  client.new("https://user:pass@search.example.com:9200")
}
