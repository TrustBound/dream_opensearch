# Client setup

This guide shows how to create a client for an OpenSearch cluster. It also shows how the client sends a user name and password, and which errors a request can return.

## Create a client

`client.new` takes the base URL of the cluster. The base URL includes the protocol and the port. The client removes a trailing slash from the URL.

### Client Setup <a href="https://github.com/TrustBound/dream_opensearch/blob/3.0.0/test/snippets/readme_client_setup.gleam#L6-L17"><img align="right" alt="Tested snippet" src="https://img.shields.io/badge/%F0%9F%A7%AA_tested-snippet-lightgreen.svg?style=flat-square"></a>

```gleam
import dream_opensearch/client.{type Client}

// Basic setup
pub fn create_local_client() -> Client {
  client.new("http://localhost:9200")
}

// With authentication: every request sends the user name and password as
// HTTP Basic authentication
pub fn create_client_with_credentials() -> Client {
  client.new("https://user:pass@search.example.com:9200")
}
```

Some base URLs:

- `http://localhost:9200`
- `https://search.example.com:9200`
- `https://user:pass@search.example.com:9200`

`client.new` does not check the URL. `client.send_request` parses it on each request.

## Credentials in the base URL

When the URL has a user name and password, the client sends them on every request in an `authorization: Basic ...` header. It does not send them in the request line or the `host` header. Percent-encode special characters in the user name or password (for example `@` as `%40`, `:` as `%3A`, `/` as `%2F`): the client decodes them before it encodes the header. A URL with a user name and no password sends an empty password. A URL with no user name sends no `authorization` header.

## Errors

Every operation in `dream_opensearch/document` sends its request with `client.send_request`, so it returns these errors:

- The response status is 400 or more: the response body, unchanged.
- The connection fails: `Connection failed: <reason>`, for example `Connection failed: Connection refused`.
- The response body is not valid UTF-8, with any status: `The OpenSearch response body is not valid UTF-8`.
- The URL cannot be parsed: `Invalid OpenSearch URL: the URL cannot be parsed`. No request is sent.
- The URL has no host: `Invalid OpenSearch URL: the URL has no host`. No request is sent.
- The user name or password has invalid percent-encoding: `Invalid credentials in the OpenSearch URL: the user name or password has invalid percent-encoding`. No request is sent.

No error message contains the user name or password.

## Functions

- `client.new(base_url)`: create a new OpenSearch client.
- `client.send_request(client, method, path, body)`: send a raw HTTP request to the cluster, with the `Content-Type: application/json` header. The `dream_opensearch/document` module uses it for every operation. Most applications should use that module instead.

## See also

- [Getting started](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/getting-started.md): install the package and index, search and delete a first document
- [Indexing documents](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/indexing-documents.md): add, replace and delete documents
- [Searching](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/searching.md): search with the query builders or with your own query JSON
- [Index management](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/index-management.md): create an index with a mapping and delete an index
- [Bulk operations](https://github.com/TrustBound/dream_opensearch/blob/main/docs/guides/bulk-operations.md): index many documents in one request
- [README](https://github.com/TrustBound/dream_opensearch/blob/main/README.md)
