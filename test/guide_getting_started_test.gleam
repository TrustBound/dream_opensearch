//// Tests for the snippets of the getting started guide
//// (docs/guides/getting-started.md), against the real OpenSearch of
//// `opensearch_cluster`. Each test uses its own index and deletes it.
////
//// The requests that the guide shows (request lines, bodies and the
//// `authorization` header) are checked on the local test server of
//// `opensearch_test_server`, because a cluster does not report the
//// requests it got.
////
//// Each `text` block of the guide is a file in `test/outputs/`, and a test
//// here compares it with the real output (see `guide_output`).

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_test/matchers.{be_equal, or_fail_with, should}
import dream_test/suite.{type TestSuite}
import dream_test/unit.{describe, group, it}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import guide_output
import guide_responses
import opensearch_cluster
import opensearch_test_server.{type TestServer, Respond}
import snippets/guide_getting_started_connect
import snippets/guide_getting_started_user_store.{type User, User}

const alice = User(id: "123", name: "Alice", email: "alice@example.com")

fn base_url(opensearch: Client) -> String {
  opensearch.base_url
}

/// `result` and `_version` of the body of an index or delete response.
fn result_and_version(body: String) -> Result(#(String, Int), String) {
  let decoder = {
    use outcome <- decode.field("result", decode.string)
    use version <- decode.field("_version", decode.int)
    decode.success(#(outcome, version))
  }
  json.parse(body, decoder)
  |> result.replace_error("Unexpected body: " <> body)
}

/// The `type` of the field `field` in the mapping of `index`.
fn field_type(
  opensearch: Client,
  index: String,
  field: String,
) -> Result(String, String) {
  use body <- result.try(client.send_request(
    opensearch,
    http.Get,
    "/" <> index <> "/_mapping",
    "",
  ))
  json.parse(
    body,
    decode.at([index, "mappings", "properties", field, "type"], decode.string),
  )
  |> result.replace_error("Unexpected mapping: " <> body)
}

/// The fields of a response body that change from run to run.
const varying_fields = ["took", "max_score", "_score"]

/// The next request that `server` got, as the guide shows a request.
fn captured_request(server: TestServer) -> Result(String, Nil) {
  use request <- result.map(opensearch_test_server.await_request(server))
  guide_output.request(request.method, request.target, request.body)
}

/// `found` with the field labels of `User`, as the guide shows it.
fn labelled_users(found: Result(List(User), String)) -> String {
  case found {
    Ok(users) ->
      "Ok([" <> string.join(list.map(users, labelled_user), ", ") <> "])"
    Error(message) -> "Error(" <> string.inspect(message) <> ")"
  }
  |> guide_output.lines
}

fn labelled_user(user: User) -> String {
  "User(id: "
  <> string.inspect(user.id)
  <> ", name: "
  <> string.inspect(user.name)
  <> ", email: "
  <> string.inspect(user.email)
  <> ")"
}

fn create_empty_index(
  opensearch: Client,
  index: String,
) -> Result(Nil, String) {
  document.create_index(opensearch, index, "{}")
  |> result.replace(Nil)
}

pub fn tests() -> TestSuite {
  describe("getting started guide", [
    group("step 1: connect", [
      it("local_client points to localhost 9200", fn() {
        // Act
        let opensearch = guide_getting_started_connect.local_client()

        // Assert
        opensearch.base_url
        |> should
        |> be_equal("http://localhost:9200")
        |> or_fail_with("local_client should use localhost:9200")
      }),
      it("secured_client percent-encodes the user name and password", fn() {
        // Act
        let opensearch =
          guide_getting_started_connect.secured_client(
            "https://search.example.com:9200",
            "admin",
            "p@ss:w/rd",
          )

        // Assert
        opensearch
        |> result.map(base_url)
        |> result.map(guide_output.lines)
        |> should
        |> be_equal(Ok(guide_output.file("guide_getting_started_secured_url")))
        |> or_fail_with("The password should be percent-encoded")
      }),
      it("secured_client sends the user name and password in Base64", fn() {
        // Arrange
        let server = opensearch_test_server.start(Respond(201, "{}"))
        let assert Ok(opensearch) =
          guide_getting_started_connect.secured_client(
            opensearch_test_server.base_url(server),
            "admin",
            "p@ss:w/rd",
          )

        // Act
        let _saved =
          guide_getting_started_user_store.save_user(opensearch, "users", alice)
        let sent = {
          use request <- result.map(opensearch_test_server.await_request(server))
          opensearch_test_server.header_values(request, "authorization")
          |> list.map(fn(value) {
            guide_output.lines("authorization: " <> value)
          })
          |> string.concat
        }

        // Assert
        sent
        |> should
        |> be_equal(
          Ok(guide_output.file("guide_getting_started_authorization")),
        )
        |> or_fail_with("Expected one Basic header for admin:p@ss:w/rd")
      }),
      it("secured_client saves a user on a secured cluster", fn() {
        // Arrange
        let assert Ok(opensearch) =
          guide_getting_started_connect.secured_client(
            opensearch_cluster.secured_base_url(),
            "admin",
            opensearch_cluster.secured_admin_password,
          )

        // Act
        let saved = {
          use index <- opensearch_cluster.with_index_on(opensearch, "users")
          Ok(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
        }

        // Assert
        saved
        |> should
        |> be_equal(Ok(Ok(Nil)))
        |> or_fail_with("The password with : @ and / should be accepted")
      }),
      it("a wrong password gets Unauthorized from a secured cluster", fn() {
        // Arrange
        let assert Ok(opensearch) =
          guide_getting_started_connect.secured_client(
            opensearch_cluster.secured_base_url(),
            "admin",
            "not-the-password",
          )

        // Act
        let saved =
          guide_getting_started_user_store.save_user(opensearch, "users", alice)

        // Assert
        saved
        |> should
        |> be_equal(Error("Unauthorized"))
        |> or_fail_with("A 401 should come back as its plain text body")
      }),
      it("no credentials get Unauthorized from a secured cluster", fn() {
        // Arrange
        let opensearch = client.new(opensearch_cluster.secured_base_url())

        // Act
        let found =
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            "users",
            "alice",
          )

        // Assert
        found
        |> should
        |> be_equal(Error("Unauthorized"))
        |> or_fail_with("A request with no credentials gets a 401")
      }),
    ]),
    group("step 2: save a user", [
      it("save_user sends the user to PUT /<index>/_doc/<id>", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(
            201,
            guide_responses.user_indexed,
          ))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _saved =
          guide_getting_started_user_store.save_user(opensearch, "users", alice)
        let sent = captured_request(server)

        // Assert
        sent
        |> should
        |> be_equal(Ok(guide_output.file("guide_getting_started_save_request")))
        |> or_fail_with("Expected the request that the guide shows")
      }),
      it("OpenSearch answers the first save with result created", fn() {
        // Act
        let answer = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use body <- result.try(document.index(
            opensearch,
            index,
            "123",
            "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}",
          ))
          guide_output.stable_body(body, index, "users", varying_fields)
        }

        // Assert
        answer
        |> should
        |> be_equal(guide_output.stable_file(
          "guide_getting_started_save_response",
          varying_fields,
        ))
        |> or_fail_with("Expected the body that the guide shows")
      }),
      it("save_user creates the index on the first write", fn() {
        // Act
        let stored = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
          field_type(opensearch, index, "name")
        }

        // Assert
        stored
        |> should
        |> be_equal(Ok("text"))
        |> or_fail_with("OpenSearch should guess text for the name")
      }),
      it("indexing the same ID twice creates, then updates", fn() {
        // Act
        let outcomes = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          let body = "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}"
          use first <- result.try(document.index(opensearch, index, "123", body))
          use second <- result.try(document.index(
            opensearch,
            index,
            "123",
            body,
          ))
          [first, second]
          |> list.map(result_and_version)
          |> result.all
        }

        // Assert
        outcomes
        |> should
        |> be_equal(Ok([#("created", 1), #("updated", 2)]))
        |> or_fail_with("The second save should replace the first")
      }),
    ]),
    group("step 3: find users", [
      it("a search right after the save finds nobody", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            index,
            "alice",
          )
        }

        // Assert
        found
        |> should
        |> be_equal(Ok([]))
        |> or_fail_with("A new document is not visible before a refresh")
      }),
      it("find_users_by_name finds Alice after a refresh", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
          use Nil <- result.try(guide_getting_started_user_store.refresh(
            opensearch,
            index,
          ))
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            index,
            "alice",
          )
        }

        // Assert
        found
        |> labelled_users
        |> should
        |> be_equal(guide_output.file("guide_getting_started_found_users"))
        |> or_fail_with("alice should match Alice")
      }),
      it("find_users_by_name sends a match query to the search endpoint", fn() {
        // Arrange
        let server =
          opensearch_test_server.start(Respond(200, guide_responses.alice_found))
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let _found =
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            "users",
            "alice",
          )
        let sent = captured_request(server)

        // Assert
        sent
        |> should
        |> be_equal(
          Ok(guide_output.file("guide_getting_started_search_request")),
        )
        |> or_fail_with("Expected the request that the guide shows")
      }),
      it("OpenSearch answers the search with Alice under hits.hits", fn() {
        // Act
        let answer = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
          use Nil <- result.try(guide_getting_started_user_store.refresh(
            opensearch,
            index,
          ))
          use body <- result.try(document.search(
            opensearch,
            index,
            "{\"query\":{\"match\":{\"name\":\"alice\"}}}",
          ))
          guide_output.stable_body(body, index, "users", varying_fields)
        }

        // Assert
        answer
        |> should
        |> be_equal(guide_output.stable_file(
          "guide_getting_started_search_response",
          varying_fields,
        ))
        |> or_fail_with("Expected the body that the guide shows")
      }),
      it("find_users_by_name returns the 404 of a missing index", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            index,
            "alice",
          )
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        found
        |> should
        |> be_equal(Ok(Error(Ok(#("index_not_found_exception", 404)))))
        |> or_fail_with("A missing index should come back as its body")
      }),
      it("users_from_response names a body it cannot read", fn() {
        // Act
        let users = guide_getting_started_user_store.users_from_response("{}")

        // Assert
        users
        |> should
        |> be_equal(Error("Unexpected search response: {}"))
        |> or_fail_with("An empty object has no hits")
      }),
    ]),
    group("step 4: delete a user", [
      it("delete_user deletes the document of the user", fn() {
        // Act
        let left = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(guide_getting_started_user_store.save_user(
            opensearch,
            index,
            alice,
          ))
          use Nil <- result.try(guide_getting_started_user_store.delete_user(
            opensearch,
            index,
            "123",
          ))
          use Nil <- result.try(guide_getting_started_user_store.refresh(
            opensearch,
            index,
          ))
          guide_getting_started_user_store.find_users_by_name(
            opensearch,
            index,
            "alice",
          )
        }

        // Assert
        left
        |> should
        |> be_equal(Ok([]))
        |> or_fail_with("Alice should be gone")
      }),
      it("a delete of a missing document is a 404 with not_found", fn() {
        // Act
        let deleted = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(create_empty_index(opensearch, index))
          document.delete(opensearch, index, "123")
          |> result.map_error(result_and_version)
          |> Ok
        }

        // Assert
        deleted
        |> should
        |> be_equal(Ok(Error(Ok(#("not_found", 1)))))
        |> or_fail_with("The 404 body has result not_found")
      }),
      it(
        "a delete after two saves and a delete is not_found at version 4",
        fn() {
          // Act
          let answer = {
            use opensearch, index <- opensearch_cluster.with_index("users")
            use Nil <- result.try(guide_getting_started_user_store.save_user(
              opensearch,
              index,
              alice,
            ))
            use Nil <- result.try(guide_getting_started_user_store.save_user(
              opensearch,
              index,
              alice,
            ))
            use _deleted <- result.try(document.delete(opensearch, index, "123"))
            case document.delete(opensearch, index, "123") {
              Ok(body) -> Error("Expected a 404, got: " <> body)
              Error(body) ->
                guide_output.stable_body(body, index, "users", varying_fields)
            }
          }

          // Assert
          answer
          |> should
          |> be_equal(guide_output.stable_file(
            "guide_getting_started_delete_not_found",
            varying_fields,
          ))
          |> or_fail_with("Expected the body that the guide shows")
        },
      ),
      it("delete_user accepts a user that is not there", fn() {
        // Act
        let deleted = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          use Nil <- result.try(create_empty_index(opensearch, index))
          Ok(guide_getting_started_user_store.delete_user(
            opensearch,
            index,
            "123",
          ))
        }

        // Assert
        deleted
        |> should
        |> be_equal(Ok(Ok(Nil)))
        |> or_fail_with("A not_found result should be Ok")
      }),
      it("delete_user returns a missing index as an error", fn() {
        // Act
        let deleted = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          guide_getting_started_user_store.delete_user(opensearch, index, "123")
          |> result.map_error(opensearch_cluster.error_type_and_status)
          |> Ok
        }

        // Assert
        deleted
        |> should
        |> be_equal(Ok(Error(Ok(#("index_not_found_exception", 404)))))
        |> or_fail_with("A missing index should stay an error")
      }),
    ]),
    group("step 5: the program", [
      it("save_and_find returns Alice", fn() {
        // Act
        let found = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          Ok(guide_getting_started_user_store.save_and_find(opensearch, index))
        }

        // Assert
        found
        |> should
        |> be_equal(Ok(Ok([alice])))
        |> or_fail_with("save_and_find should find Alice")
      }),
      it("main prints the result of save_and_find like this", fn() {
        // Act
        let printed = {
          use opensearch, index <- opensearch_cluster.with_index("users")
          guide_getting_started_user_store.save_and_find(opensearch, index)
          |> guide_output.inspected
          |> Ok
        }

        // Assert
        printed
        |> should
        |> be_equal(Ok(guide_output.file("guide_getting_started_main_output")))
        |> or_fail_with("string.inspect should leave out the labels")
      }),
      it("save_and_find saves, refreshes and searches, in that order", fn() {
        // Arrange
        let server =
          opensearch_test_server.start_sequence([
            Respond(201, guide_responses.user_indexed),
            Respond(200, guide_responses.refreshed),
            Respond(200, guide_responses.alice_found),
          ])
        let opensearch = client.new(opensearch_test_server.base_url(server))

        // Act
        let found =
          guide_getting_started_user_store.save_and_find(opensearch, "users")

        // Assert
        [server, server, server]
        |> list.map(opensearch_test_server.await_request)
        |> result.all
        |> result.map(
          list.map(_, fn(request) {
            guide_output.request(request.method, request.target, "")
          }),
        )
        |> result.map(fn(requests) { #(found, string.concat(requests)) })
        |> should
        |> be_equal(
          Ok(#(
            Ok([alice]),
            guide_output.file("guide_getting_started_save_and_find_requests"),
          )),
        )
        |> or_fail_with("Expected save, refresh, search")
      }),
    ]),
  ])
}
