//// Response bodies for the few tests that use the local test server of
//// `opensearch_test_server` instead of the real cluster. Each body is
//// copied from OpenSearch 2.19.1 (the cluster of `docker-compose.yml`),
//// except where a comment says otherwise.

/// `PUT /users/_doc/123` of a new document.
pub const user_indexed =
  "{\"_index\":\"users\",\"_id\":\"123\",\"_version\":1,\"result\":\"created\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1}"

/// `POST /users/_refresh`.
pub const refreshed = "{\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0}}"

/// `POST /users/_search` for `alice`, after a refresh.
pub const alice_found =
  "{\"took\":1,\"timed_out\":false,\"_shards\":{\"total\":1,\"successful\":1,\"skipped\":0,\"failed\":0},\"hits\":{\"total\":{\"value\":1,\"relation\":\"eq\"},\"max_score\":0.18232156,\"hits\":[{\"_index\":\"users\",\"_id\":\"123\",\"_score\":0.18232156,\"_source\":{\"name\":\"Alice\",\"email\":\"alice@example.com\"}}]}}"

/// `POST /_bulk` with books 1 and 2 into `books`.
pub const two_books_loaded =
  "{\"took\":4,\"errors\":false,\"items\":[{\"index\":{\"_index\":\"books\",\"_id\":\"1\",\"_version\":1,\"result\":\"created\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":0,\"_primary_term\":1,\"status\":201}},{\"index\":{\"_index\":\"books\",\"_id\":\"2\",\"_version\":1,\"result\":\"created\",\"_shards\":{\"total\":2,\"successful\":1,\"failed\":0},\"_seq_no\":1,\"_primary_term\":1,\"status\":201}}]}"

/// `POST /_bulk` with book 3, whose year does not fit an `integer`.
pub const book_three_failed =
  "{\"took\":0,\"errors\":true,\"items\":[{\"index\":{\"_index\":\"books\",\"_id\":\"3\",\"status\":400,\"error\":{\"type\":\"mapper_parsing_exception\",\"reason\":\"failed to parse field [year] of type [integer] in document with id '3'. Preview of field's value: '3000000000'\",\"caused_by\":{\"type\":\"input_coercion_exception\",\"reason\":\"Numeric value (3000000000) out of range of int (-2147483648 - 2147483647)\\n at [Source: REDACTED (`StreamReadFeature.INCLUDE_SOURCE_IN_LOCATION` disabled); line: 1, column: 70]\"}}}}]}"

/// A cluster that is still starting answers with this error and status
/// 503. The tests cannot make a real cluster do that on demand, so this
/// body is written in the form of the other OpenSearch error bodies.
pub const cluster_not_ready =
  "{\"error\":{\"root_cause\":[{\"type\":\"cluster_block_exception\",\"reason\":\"blocked by: [SERVICE_UNAVAILABLE/1/state not recovered / initialized];\"}],\"type\":\"cluster_block_exception\",\"reason\":\"blocked by: [SERVICE_UNAVAILABLE/1/state not recovered / initialized];\"},\"status\":503}"

/// The default 502 page of nginx, as a proxy in front of a cluster sends it.
pub const bad_gateway_page =
  "<html>\r\n<head><title>502 Bad Gateway</title></head>\r\n<body>\r\n<center><h1>502 Bad Gateway</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"
