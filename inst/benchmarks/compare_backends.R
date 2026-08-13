# Compare R vs C++ backends across EEG-realistic data sizes
# Requires: bench
# Install with: install.packages("bench")
#
# Usage: Rscript inst/benchmarks/compare_backends.R

library(infomax)

make_data <- function(n_samps, n_comps, seed = 42) {
  set.seed(seed)
  S <- matrix(rnorm(n_samps * n_comps), n_samps, n_comps)
  A <- matrix(rnorm(n_comps^2), n_comps, n_comps)
  S %*% A
}

sizes <- list(
  small  = list(n = 5000,  m = 10),
  medium = list(n = 15000, m = 32),
  large  = list(n = 30000, m = 64)
)

if (!requireNamespace("bench", quietly = TRUE)) {
  stop("Please install 'bench': install.packages('bench')")
}

results <- lapply(names(sizes), function(sz) {
  s <- sizes[[sz]]
  x <- make_data(s$n, s$m)
  message(sprintf("\n--- %s (%d ch x %d samp) ---", sz, s$m, s$n))
  bm <- bench::mark(
    R   = run_infomax(x, extended = TRUE, verbose = FALSE, backend = "r"),
    cpp = run_infomax(x, extended = TRUE, verbose = FALSE, backend = "cpp"),
    iterations = 3,
    check = FALSE
  )
  print(bm[, c("expression", "min", "median", "mem_alloc", "n_itr")])
  bm
})

names(results) <- names(sizes)
message("\nDone. Check 'results' for full bench output.")
