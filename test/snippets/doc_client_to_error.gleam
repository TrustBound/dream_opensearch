//// Example for the `client.to_error` doc.

import dream_errors.{type Error}
import dream_opensearch/client.{
  type Client, type OpenSearchError, send_request, to_error,
}
import gleam/http.{Get}
import gleam/result.{map_error}

pub fn get_document(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(String, Error(OpenSearchError)) {
  send_request(opensearch, Get, "/" <> index <> "/_doc/" <> id, "")
  |> map_error(to_error)
}
