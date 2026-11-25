//// Example for the `client.from_request` doc.

import dream_http_client/client as http_client
import dream_http_client/recorder.{type Recorder}
import dream_opensearch/client.{type Client}
import gleam/http

pub fn create_recorded_client(recorder: Recorder) -> Client {
  http_client.new()
  |> http_client.scheme(http.Http)
  |> http_client.host("localhost")
  |> http_client.port(9201)
  |> http_client.timeout(5000)
  |> http_client.recorder(recorder)
  |> client.from_request
}
