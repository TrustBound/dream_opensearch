//// Example for the `dream_opensearch/query` module doc: a custom query.

import gleam/json

pub fn build_bool_query() -> String {
  json.object([
    #(
      "query",
      json.object([
        #(
          "bool",
          json.object([
            #(
              "must",
              json.preprocessed_array([
                json.object([
                  #("match", json.object([#("name", json.string("Alice"))])),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string()
}
