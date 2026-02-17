# Profile infomax on EEG-realistic data sizes
# Requires: profvis, bench
# Install with: install.packages(c("profvis", "bench"))
#
# Usage: Rscript inst/benchmarks/profile_infomax.R

library(infomax)

make_data <- function(n_samps, n_comps, seed = 42) {
  set.seed(seed)
  S <- matrix(rnorm(n_samps * n_comps), n_samps, n_comps)
  A <- matrix(rnorm(n_comps^2), n_comps, n_comps)
  S %*% A
}

# Small: fast enough for profvis
x_small <- make_data(5000, 10)

# Medium: representative of typical EEG analysis
x_medium <- make_data(15000, 32)

# Large: realistic EEG scale
x_large <- make_data(30000, 64)

message("=== profvis profile (small: 10ch x 5000) ===")
if (requireNamespace("profvis", quietly = TRUE)) {
  p <- profvis::profvis({
    run_infomax(x_small, extended = TRUE, verbose = FALSE, backend = "r")
  })
  print(p)
} else {
  message("profvis not installed; run: install.packages('profvis')")
}

message("\n=== bench::mark timings ===")
if (requireNamespace("bench", quietly = TRUE)) {

  message("Small (10 ch x 5000 samp):")
  bm_small <- bench::mark(
    r = run_infomax(x_small, extended = TRUE, verbose = FALSE, backend = "r"),
    iterations = 5, check = FALSE
  )
  print(bm_small[, c("expression", "min", "median", "mem_alloc", "n_itr")])

  message("\nMedium (32 ch x 15000 samp):")
  bm_medium <- bench::mark(
    r = run_infomax(x_medium, extended = TRUE, verbose = FALSE, backend = "r"),
    iterations = 3, check = FALSE
  )
  print(bm_medium[, c("expression", "min", "median", "mem_alloc", "n_itr")])

  message("\nLarge (64 ch x 30000 samp):")
  bm_large <- bench::mark(
    r = run_infomax(x_large, extended = TRUE, verbose = FALSE, backend = "r"),
    iterations = 3, check = FALSE
  )
  print(bm_large[, c("expression", "min", "median", "mem_alloc", "n_itr")])

} else {
  message("bench not installed; run: install.packages('bench')")
}
