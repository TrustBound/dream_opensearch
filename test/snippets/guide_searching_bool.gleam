//// Guide: Searching an index, steps 4 and 5
////
//// Builds a bool query with paging and sorting, with `gleam/json`.

import gleam/json

/// Books in stock whose title matches `words`, published in `from_year` or
/// later, newest first, one page at a time. `page` counts from 1.
pub fn in_stock_query(
  words: String,
  from_year: Int,
  page: Int,
  per_page: Int,
) -> String {
  let bool_query =
    json.object([
      #(
        "bool",
        json.object([
          // `must` clauses decide which books match, and how well
          #(
            "must",
            json.preprocessed_array([match("title", json.string(words))]),
          ),
          // `filter` clauses only include or exclude, with no score
          #(
            "filter",
            json.preprocessed_array([
              term("in_stock", json.bool(True)),
              at_least("year", json.int(from_year)),
            ]),
          ),
        ]),
      ),
    ])
  json.object([
    #("query", bool_query),
    #("from", json.int({ page - 1 } * per_page)),
    #("size", json.int(per_page)),
    #("sort", json.preprocessed_array([newest_first()])),
  ])
  |> json.to_string
}

fn match(field: String, value: json.Json) -> json.Json {
  json.object([#("match", json.object([#(field, value)]))])
}

fn term(field: String, value: json.Json) -> json.Json {
  json.object([#("term", json.object([#(field, value)]))])
}

fn at_least(field: String, value: json.Json) -> json.Json {
  json.object([
    #("range", json.object([#(field, json.object([#("gte", value)]))])),
  ])
}

fn newest_first() -> json.Json {
  json.object([#("year", json.object([#("order", json.string("desc"))]))])
}
