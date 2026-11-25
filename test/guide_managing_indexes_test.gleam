//// Tests for the snippets of the managing indexes guide
//// (docs/guides/managing-indexes.md), against the real OpenSearch of
//// `opensearch_cluster`. Each test uses its own indexes and deletes them.
////
//// A real cluster always sends `count` and `created`, so the two tests of
//// a body with neither use the local test server of
//// `opensearch_test_server`, with a real refresh response as the body.
////
//// Each `text` block of the guide is a file in `test/outputs/`, and a test
//// here compares it with the real output (see `guide_output`). The request
//// of `copy_index` is checked on the local test server too, because a
//// cluster does not report the requests it got.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result
import gleam/string
import guide_output
import guide_responses
import opensearch_cluster
import opensearch_test_server.{Respond}
import snippets/guide_managing_indexes_create
import snippets/guide_managing_indexes_maintain

fn client_for_body(body: String) -> Client {
  let server = opensearch_test_server.start(Respond(200, body))
  client.new(opensearch_test_server.base_url(server))
}

fn load_two_books(opensearch: Client, index: String) -> Result(Nil, String) {
  let action = fn(id) {
    "{\"index\":{\"_index\":\"" <> index <> "\",\"_id\":\"" <> id <> "\"}}\n"
  }
  document.bulk(
    opensearch,
    action("1")
      <> "{\"title\":\"Programming Gleam\",\"author\":\"Jo Lee\",\"year\":2024,\"in_stock\":true}\n"
      <> action("2")
      <> "{\"title\":\"Gleam for Erlang Developers\",\"author\":\"Sam Park\",\"year\":2022,\"in_stock\":false}\n",
  )
  |> result.replace(Nil)
}

fn create_and_load(opensearch: Client, index: String) -> Result(Nil, String) {
  use Nil <- result.try(guide_managing_indexes_create.create_books_index(
    opensearch,
    index,
  ))
  use Nil <- result.try(load_two_books(opensearch, index))
  guide_managing_indexes_maintain.refresh_index(opensearch, index)
}

fn hit_total(body: String) -> Result(Int, String) {
  json.parse(body, decode.at(["hits", "total", "value"], decode.int))
  |> result.replace_error("Unexpected search response: " <> body)
}

/// The field of a response body that changes from run to run.
const varying_fields = ["took"]

/// `body` with its index UUID, which changes from run to run, written as
/// `<index UUID>`. A body with no `error.index_uuid` stays as it is.
fn without_index_uuid(body: String) -> String {
  case json.parse(body, decode.at(["error", "index_uuid"], decode.string)) {
    Ok(uuid) -> string.replace(body, uuid, "<index UUID>")
    Error(_) -> body
  }
}

/// The stable fields of a body from the index `index` of a test.
fn stable_body(body: String, index: String) -> Result(Dynamic, String) {
  guide_output.stable_body(
    without_index_uuid(body),
    index,
    "books",
    varying_fields,
  )
}

/// The stable fields of the output file `name`.
fn stable_file(name: String) -> Result(Dynamic, String) {
  guide_output.stable_json(
    without_index_uuid(guide_output.file(name)),
    varying_fields,
  )
}

pub fn tests() -> TestSuite {
  describe("managing indexes guide", [
    group("step 1: create", [
      it("books_index_body holds the settings and the mapping", fn() {
        // Act
        let body = guide_managing_indexes_create.books_index_body()

        // Assert
        guide_output.lines(body)
        |> should
        |> be_equal(guide_output.file("guide_managing_indexes_books_index_body"))
        |> or_fail_with("Expected the body of the guide")
      }),
      it("create_index answers acknowledged on a single node", fn() {
        // Act
        let created = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use body <- result.try(document.create_index(
            opensearch,
            index,
            guide_managing_indexes_create.books_index_body(),
          ))
          stable_body(body, index)
        }

        // Assert
        created
        |> should
        |> be_equal(stable_file("guide_managing_indexes_created"))
        |> or_fail_with("The primary shard starts, the replica waits")
      }),
      it("create_books_index returns an existing index as an error", fn() {
        // Act
        let created = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(opensearch, index),
          )
          case
            guide_managing_indexes_create.create_books_index(opensearch, index)
          {
            Ok(Nil) -> Error("Expected a 400 for an index that exists")
            Error(body) -> stable_body(body, index)
          }
        }

        // Assert
        created
        |> should
        |> be_equal(stable_file("guide_managing_indexes_already_exists"))
        |> or_fail_with("The second create should fail")
      }),
      it("a strict mapping refuses a field it does not name", fn() {
        // Act
        let indexed = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(opensearch, index),
          )
          document.index(
            opensearch,
            index,
            "1",
            "{\"title\":\"Programming Gleam\",\"auhtor\":\"Jo Lee\"}",
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        indexed
        |> should
        |> be_equal(Ok(Error(Ok(#("strict_dynamic_mapping_exception", 400)))))
        |> or_fail_with("The typo auhtor should be refused")
      }),
    ]),
    group("step 2: create when missing", [
      it("ensure_books_index creates, then accepts the existing index", fn() {
        // Act
        let ensured = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          let first =
            guide_managing_indexes_create.ensure_books_index(opensearch, index)
          let second =
            guide_managing_indexes_create.ensure_books_index(opensearch, index)
          Ok(#(first, second))
        }

        // Assert
        ensured
        |> should
        |> be_equal(Ok(#(Ok(Nil), Ok(Nil))))
        |> or_fail_with("Both calls should be Ok")
      }),
      it("ensure_books_index keeps the error of an upper-case name", fn() {
        // Act
        let ensured =
          guide_managing_indexes_create.ensure_books_index(
            opensearch_cluster.client(),
            "Books",
          )

        // Assert
        ensured
        |> result.map_error(guide_output.lines)
        |> should
        |> be_equal(
          Error(guide_output.file("guide_managing_indexes_invalid_name")),
        )
        |> or_fail_with("A bad name must not pass as already exists")
      }),
    ]),
    group("step 3: check, refresh and count", [
      it("index_exists is true for an index that exists", fn() {
        // Act
        let exists = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(opensearch, index),
          )
          guide_managing_indexes_maintain.index_exists(opensearch, index)
        }

        // Assert
        exists
        |> should
        |> be_equal(Ok(True))
        |> or_fail_with("The index was just created")
      }),
      it("index_exists is false for a missing index", fn() {
        // Act
        let exists = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          guide_managing_indexes_maintain.index_exists(opensearch, index)
        }

        // Assert
        exists
        |> should
        |> be_equal(Ok(False))
        |> or_fail_with("No index was created")
      }),
      it("index_exists keeps a 401 as an error", fn() {
        // Arrange
        let assert Ok(opensearch) =
          opensearch_cluster.secured_client("admin", "not-the-password")

        // Act
        let exists =
          guide_managing_indexes_maintain.index_exists(opensearch, "books")

        // Assert
        exists
        |> should
        |> be_equal(Error("Unauthorized"))
        |> or_fail_with("A wrong password is not a missing index")
      }),
      it("a HEAD with a wrong password gets an empty error", fn() {
        // Arrange
        let assert Ok(opensearch) =
          opensearch_cluster.secured_client("admin", "not-the-password")

        // Act
        let checked = client.send_request(opensearch, http.Head, "/books", "")

        // Assert
        checked
        |> should
        |> be_equal(Error(""))
        |> or_fail_with("A HEAD answer has no body, a 401 neither")
      }),
      it("index_exists keeps a connection error", fn() {
        // Act
        let exists =
          guide_managing_indexes_maintain.index_exists(
            client.new("http://127.0.0.1:1"),
            "books",
          )

        // Assert
        exists
        |> should
        |> be_equal(Error("Connection failed: Connection refused"))
        |> or_fail_with("A refused connection is not a missing index")
      }),
      it("count_documents counts the documents after a refresh", fn() {
        // Act
        let counted = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(create_and_load(opensearch, index))
          guide_managing_indexes_maintain.count_documents(opensearch, index)
        }

        // Assert
        counted
        |> should
        |> be_equal(Ok(2))
        |> or_fail_with("Two books were loaded")
      }),
      it("count_documents names a body it cannot read", fn() {
        // Act
        let counted =
          guide_managing_indexes_maintain.count_documents(
            client_for_body(guide_responses.refreshed),
            "books",
          )

        // Assert
        counted
        |> should
        |> be_equal(Error(
          "Unexpected count response: " <> guide_responses.refreshed,
        ))
        |> or_fail_with("A body with no count is unexpected")
      }),
    ]),
    group("step 4: copy", [
      it("copy_index copies every document", fn() {
        // Act
        let copied = {
          use opensearch, source, destination <- opensearch_cluster.with_two_indexes(
            "books",
          )
          use Nil <- result.try(create_and_load(opensearch, source))
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(
              opensearch,
              destination,
            ),
          )
          use created <- result.try(guide_managing_indexes_maintain.copy_index(
            opensearch,
            source,
            destination,
          ))
          use Nil <- result.try(guide_managing_indexes_maintain.refresh_index(
            opensearch,
            destination,
          ))
          use counted <- result.try(
            guide_managing_indexes_maintain.count_documents(
              opensearch,
              destination,
            ),
          )
          Ok(#(created, counted))
        }

        // Assert
        copied
        |> should
        |> be_equal(Ok(#(2, 2)))
        |> or_fail_with("Both books should be in the new index")
      }),
      it("copy_index sends the source and the destination to _reindex", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            200,
            guide_output.file("guide_managing_indexes_reindex_response"),
          ))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _copied =
          guide_managing_indexes_maintain.copy_index(
            opensearch,
            "books_v1",
            "books_v2",
          )
        let sent = {
          use request <- result.map(opensearch_test_server.await_request(server))
          guide_output.request(request.method, request.target, request.body)
        }

        // Assert
        sent
        |> should
        |> be_equal(
          Ok(guide_output.file("guide_managing_indexes_reindex_request")),
        )
        |> or_fail_with("Expected the request that the guide shows")
      }),
      it("OpenSearch answers the reindex when it has copied both books", fn() {
        // Act
        let answer = {
          use opensearch, source, destination <- opensearch_cluster.with_two_indexes(
            "books",
          )
          use Nil <- result.try(create_and_load(opensearch, source))
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(
              opensearch,
              destination,
            ),
          )
          use body <- result.try(client.send_request(
            opensearch,
            http.Post,
            "/_reindex",
            "{\"source\":{\"index\":\""
              <> source
              <> "\"},\"dest\":{\"index\":\""
              <> destination
              <> "\"}}",
          ))
          guide_output.stable_json(body, varying_fields)
        }

        // Assert
        answer
        |> should
        |> be_equal(stable_file("guide_managing_indexes_reindex_response"))
        |> or_fail_with("Expected the body that the guide shows")
      }),
      it("copy_index from a missing index is a 404", fn() {
        // Act
        let copied = {
          use opensearch, source, destination <- opensearch_cluster.with_two_indexes(
            "books",
          )
          guide_managing_indexes_maintain.copy_index(
            opensearch,
            source,
            destination,
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        copied
        |> should
        |> be_equal(Ok(Error(Ok(#("index_not_found_exception", 404)))))
        |> or_fail_with("The source does not exist")
      }),
      it("copy_index names a body it cannot read", fn() {
        // Act
        let copied =
          guide_managing_indexes_maintain.copy_index(
            client_for_body(guide_responses.refreshed),
            "books_v1",
            "books_v2",
          )

        // Assert
        copied
        |> should
        |> be_equal(Error(
          "Unexpected reindex response: " <> guide_responses.refreshed,
        ))
        |> or_fail_with("A body with no created is unexpected")
      }),
      it("a mapping cannot change the type of a field", fn() {
        // Act
        let changed = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(opensearch, index),
          )
          client.send_request(
            opensearch,
            http.Put,
            "/" <> index <> "/_mapping",
            "{\"properties\":{\"author\":{\"type\":\"text\"}}}",
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        changed
        |> should
        |> be_equal(Ok(Error(Ok(#("illegal_argument_exception", 400)))))
        |> or_fail_with("keyword cannot become text")
      }),
      it("a first write without a mapping breaks term on author", fn() {
        // Act
        let total = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(load_two_books(opensearch, index))
          use Nil <- result.try(guide_managing_indexes_maintain.refresh_index(
            opensearch,
            index,
          ))
          use body <- result.try(document.search(
            opensearch,
            index,
            query.term("author", "Jo Lee"),
          ))
          hit_total(body)
        }

        // Assert
        total
        |> should
        |> be_equal(Ok(0))
        |> or_fail_with("The guessed type of author is text")
      }),
    ]),
    group("step 5: delete", [
      it("delete_index_if_present deletes, then accepts a missing index", fn() {
        // Act
        let deleted = {
          use opensearch, index <- opensearch_cluster.with_index("books")
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(opensearch, index),
          )
          let first =
            guide_managing_indexes_maintain.delete_index_if_present(
              opensearch,
              index,
            )
          let second =
            guide_managing_indexes_maintain.delete_index_if_present(
              opensearch,
              index,
            )
          use exists <- result.try(guide_managing_indexes_maintain.index_exists(
            opensearch,
            index,
          ))
          Ok(#(first, second, exists))
        }

        // Assert
        deleted
        |> should
        |> be_equal(Ok(#(Ok(Nil), Ok(Nil), False)))
        |> or_fail_with("The index should be gone")
      }),
      it("delete_index_if_present keeps a 403 of a user without rights", fn() {
        // Act
        let deleted = {
          use admin <- result.try(opensearch_cluster.secured_admin_client())
          use index <- opensearch_cluster.with_index_on(admin, "books")
          let user = opensearch_cluster.index_name("reader")
          let user_path = "/_plugins/_security/api/internalusers/" <> user
          use _ <- result.try(client.send_request(
            admin,
            http.Put,
            user_path,
            "{\"password\":\"Reader-Pa55word!\",\"backend_roles\":[]}",
          ))
          use Nil <- result.try(
            guide_managing_indexes_create.create_books_index(admin, index),
          )
          use reader <- result.try(opensearch_cluster.secured_client(
            user,
            "Reader-Pa55word!",
          ))
          let outcome =
            guide_managing_indexes_maintain.delete_index_if_present(
              reader,
              index,
            )
            |> result.map_error(opensearch_cluster.error_type_and_status)
          use _ <- result.try(client.send_request(
            admin,
            http.Delete,
            user_path,
            "",
          ))
          Ok(outcome)
        }

        // Assert
        deleted
        |> should
        |> be_equal(Ok(Error(Ok(#("security_exception", 403)))))
        |> or_fail_with("A user without rights gets 403, not 401")
      }),
      it("delete_index with * deletes every index that matches", fn() {
        // Act
        let left = {
          use opensearch, index <- opensearch_cluster.with_index("wildcard")
          let copy = index <> "_copy"
          let outcome = {
            use Nil <- result.try(
              guide_managing_indexes_create.create_books_index(
                opensearch,
                index,
              ),
            )
            use Nil <- result.try(
              guide_managing_indexes_create.create_books_index(opensearch, copy),
            )
            use _ <- result.try(document.delete_index(opensearch, index <> "*"))
            use index_exists <- result.try(
              guide_managing_indexes_maintain.index_exists(opensearch, index),
            )
            use copy_exists <- result.try(
              guide_managing_indexes_maintain.index_exists(opensearch, copy),
            )
            Ok(#(index_exists, copy_exists))
          }
          use Nil <- result.try(
            guide_managing_indexes_maintain.delete_index_if_present(
              opensearch,
              copy,
            ),
          )
          outcome
        }

        // Assert
        left
        |> should
        |> be_equal(Ok(#(False, False)))
        |> or_fail_with("The encoded * is still a wildcard to OpenSearch")
      }),
    ]),
  ])
}
