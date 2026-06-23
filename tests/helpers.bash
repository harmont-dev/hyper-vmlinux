# Shared helpers for hypercfg bats tests.
# Resolves paths relative to this file so tests run from any CWD.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
scripts_dir() {
  echo "$(repo_root)/scripts"
}
fixtures_dir() {
  echo "$(repo_root)/tests/fixtures"
}
