time_x <- seq(0, 1, by = 1/256)
source_a <- sin(2 * pi * 5 * time_x)
source_b <- sin(2 * pi * 10 * time_x)
source_c <- sin(2 * pi * 8 * time_x  + .4)
mixed_data <- matrix(NA,
                     nrow = length(time_x),
                     ncol = 3)
mixed_data[, 1] <- source_a - 2 * source_b + 1.2 * source_c
mixed_data[, 2] <- source_a * 3.4 + 1.5 * source_b - 2 * source_c
mixed_data[, 3] <- source_a * .9 - 2.5 * source_b + .8 * source_c

test_that("extended infomax runs (r backend)", {
  init_out <- run_infomax(mixed_data, extended = TRUE, verbose = FALSE)
  expect_type(init_out, "list")
  expect_true(abs(cor(init_out$S[, 1], source_a)) > .98)
  expect_true(abs(cor(init_out$S[, 2], source_b)) > .98)
  expect_true(abs(cor(init_out$S[, 3], source_c)) > .98)
  init_nonext <- run_infomax(mixed_data, extended = FALSE, verbose = FALSE)
  expect_type(init_nonext, "list")
  expect_true(abs(cor(init_nonext$S[, 1], source_a)) < .69)
  expect_true(abs(cor(init_nonext$S[, 1], source_a)) > .67)
  expect_true(abs(cor(init_nonext$S[, 2], source_b)) > .37)
  expect_true(abs(cor(init_nonext$S[, 2], source_b)) < .39)
  expect_true(abs(cor(init_nonext$S[, 3], source_c)) > .67)
  expect_true(abs(cor(init_nonext$S[, 3], source_c)) < .69)
})

test_that("cpp backend recovers sources", {
  out_cpp <- run_infomax(mixed_data, extended = TRUE, verbose = FALSE,
                         backend = "cpp")
  expect_type(out_cpp, "list")
  # Each sorted component should correlate > 0.98 with one of the true sources.
  # Both backends use independent random shuffles so we compare to known truth,
  # not to each other's output.
  cors <- abs(cor(out_cpp$S, cbind(source_a, source_b, source_c)))
  expect_true(max(cors[1, ]) > .98)
  expect_true(max(cors[2, ]) > .98)
  expect_true(max(cors[3, ]) > .98)
})

test_that("weight blowups restart safely", {
  set.seed(1)
  x <- matrix(rnorm(400), nrow = 100, ncol = 4)

  for (backend in c("r", "cpp")) {
    out <- run_infomax(x, lrate = 3, maxiter = 2,
                       verbose = FALSE, backend = backend)
    expect_true(all(is.finite(out$W)), info = backend)
    expect_true(all(is.finite(out$S)), info = backend)
  }
})
