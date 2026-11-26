//// Example for the `client.to_error` doc.

import dream_errors
import dream_opensearch/client.{type Client, type OpenSearchError}
import gleam/http
import gleam/result

pub fn get_document(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(String, dream_errors.Error(OpenSearchError)) {
  client.send_request(opensearch, http.Get, "/" <> index <> "/_doc/" <> id, "")
  |> result.map_error(client.to_error)
}
