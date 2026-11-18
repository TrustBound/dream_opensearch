//// Example for the `query.range` doc.

import dream_opensearch/client.{type Client}
import dream_opensearch/document
import dream_opensearch/query

// Find products with price between 10 and 100
pub fn search_products_by_price(opensearch: Client) -> Result(String, String) {
  let price_query = query.range("price", "10", "100")
  document.search(opensearch, "products", price_query)
}
