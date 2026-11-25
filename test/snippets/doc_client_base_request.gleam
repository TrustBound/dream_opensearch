//// Example for the `client.base_request` doc.

import dream_http_client/client as http_client
import dream_opensearch/client.{type Client}

pub fn host_of(opensearch: Client) -> String {
  http_client.get_host(client.base_request(opensearch))
}
