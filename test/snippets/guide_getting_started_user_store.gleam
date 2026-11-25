//// Guide: Getting started, steps 2 to 5
////
//// A small store of users in an index: save, find and delete.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query
import gleam/dynamic/decode
import gleam/http
import gleam/io
import gleam/json
import gleam/result
import gleam/string

pub type User {
  User(id: String, name: String, email: String)
}

/// Stores `user` under its ID in `index`. Saving the same ID again
/// replaces the user.
pub fn save_user(
  opensearch: Client,
  index: String,
  user: User,
) -> Result(Nil, String) {
  let body =
    json.object([
      #("name", json.string(user.name)),
      #("email", json.string(user.email)),
    ])
    |> json.to_string
  document.index(opensearch, index, user.id, body)
  |> result.replace(Nil)
}

/// Finds the users whose name matches `name`, best match first.
pub fn find_users_by_name(
  opensearch: Client,
  index: String,
  name: String,
) -> Result(List(User), String) {
  use body <- result.try(document.search(
    opensearch,
    index,
    query.match("name", name),
  ))
  users_from_response(body)
}

/// Reads the users out of the body of a search response.
pub fn users_from_response(body: String) -> Result(List(User), String) {
  json.parse(body, decode.at(["hits", "hits"], decode.list(user_hit())))
  |> result.replace_error("Unexpected search response: " <> body)
}

fn user_hit() -> decode.Decoder(User) {
  use id <- decode.field("_id", decode.string)
  use name <- decode.subfield(["_source", "name"], decode.string)
  use email <- decode.subfield(["_source", "email"], decode.string)
  decode.success(User(id:, name:, email:))
}

/// Deletes the user with `id`. A user that is not there is not an error.
pub fn delete_user(
  opensearch: Client,
  index: String,
  id: String,
) -> Result(Nil, String) {
  document.delete(opensearch, index, id)
  |> result.replace(Nil)
  |> result.try_recover(ignore_not_found)
}

fn ignore_not_found(body: String) -> Result(Nil, String) {
  case json.parse(body, decode.at(["result"], decode.string)) {
    Ok("not_found") -> Ok(Nil)
    _ -> Error(body)
  }
}

/// Makes the documents indexed so far in `index` visible to search.
pub fn refresh(opensearch: Client, index: String) -> Result(Nil, String) {
  client.send_request(opensearch, http.Post, "/" <> index <> "/_refresh", "")
  |> result.replace(Nil)
}

pub fn main() -> Nil {
  client.new("http://localhost:9200")
  |> save_and_find("users")
  |> string.inspect
  |> io.println
}

/// Saves Alice, makes her visible to search, and finds her by name.
pub fn save_and_find(
  opensearch: Client,
  index: String,
) -> Result(List(User), String) {
  let alice = User(id: "123", name: "Alice", email: "alice@example.com")
  use Nil <- result.try(save_user(opensearch, index, alice))
  use Nil <- result.try(refresh(opensearch, index))
  find_users_by_name(opensearch, index, "alice")
}
