//// Guide: Getting started, step 1
////
//// Creates a client for a local cluster and for a secured cluster.

import dream_opensearch/client.{type Client, type OpenSearchError, InvalidUrl}
import gleam/option.{Some}
import gleam/result
import gleam/uri.{Uri}

/// A client for a cluster on your own machine, with no security plugin.
pub fn local_client() -> Result(Client, OpenSearchError) {
  client.new("http://localhost:9200")
}

/// A client for a secured cluster. Every request sends the user name and
/// password as HTTP Basic authentication.
pub fn secured_client(
  url: String,
  user: String,
  password: String,
) -> Result(Client, OpenSearchError) {
  use parsed <- result.try(
    uri.parse(url)
    |> result.replace_error(InvalidUrl(reason: "the URL cannot be parsed")),
  )
  // Percent-encode both parts, so that `@`, `:` and `/` cannot break the URL
  let userinfo = uri.percent_encode(user) <> ":" <> uri.percent_encode(password)
  client.new(uri.to_string(Uri(..parsed, userinfo: Some(userinfo))))
}
