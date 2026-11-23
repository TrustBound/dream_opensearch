import architecture_snippets_test
import client_test
import doc_snippets_test
import document_encoding_cluster_test
import document_encoding_test
import document_test
import dream_test/coverage
import dream_test/reporters/bdd
import dream_test/reporters/progress
import dream_test/runner
import guide_bulk_loading_test
import guide_getting_started_test
import guide_handling_errors_test
import guide_managing_indexes_test
import guide_searching_test
import opensearch_cluster
import query_test
import readme_snippets_test
import snippets/guide_bulk_loading_testing
import snippets/guide_getting_started_testing
import snippets/guide_handling_errors_testing
import snippets/guide_managing_indexes_testing
import snippets/guide_searching_testing

pub fn main() {
  opensearch_cluster.require_cluster()
  runner.new([
    client_test.tests(),
    document_test.tests(),
    document_encoding_test.tests(),
    document_encoding_cluster_test.tests(),
    query_test.tests(),
    readme_snippets_test.tests(),
    architecture_snippets_test.tests(),
    doc_snippets_test.tests(),
    guide_getting_started_test.tests(),
    guide_getting_started_testing.tests(),
    guide_searching_test.tests(),
    guide_searching_testing.tests(),
    guide_bulk_loading_test.tests(),
    guide_bulk_loading_testing.tests(),
    guide_managing_indexes_test.tests(),
    guide_managing_indexes_testing.tests(),
    guide_handling_errors_test.tests(),
    guide_handling_errors_testing.tests(),
  ])
  |> runner.progress_reporter(progress.new())
  |> runner.results_reporters([bdd.new()])
  |> runner.coverage(
    coverage.new()
    |> coverage.show_missing()
    |> coverage.minimum_percent(100.0)
    |> coverage.json_path("build/coverage/coverage.json"),
  )
  |> runner.exit_on_failure()
  |> runner.run()
}
