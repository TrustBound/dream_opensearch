//// Example for the `document.bulk` doc.

import dream_opensearch/client.{type Client, type OpenSearchError}
import dream_opensearch/document

pub fn bulk_index_users(
  opensearch: Client,
  index: String,
) -> Result(String, OpenSearchError) {
  // NDJSON format: action and document on alternating lines
  let ndjson =
    "{ \"index\": { \"_index\": \""
    <> index
    <> "\", \"_id\": \"1\" } }\n"
    <> "{ \"name\": \"Alice\", \"email\": \"alice@example.com\" }\n"
    <> "{ \"index\": { \"_index\": \""
    <> index
    <> "\", \"_id\": \"2\" } }\n"
    <> "{ \"name\": \"Bob\", \"email\": \"bob@example.com\" }\n"

  document.bulk(opensearch, ndjson)
}
