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
colnames(mixed_data) <- paste0("E", 1:3)

expect_sources_recovered <- function(estimated, sources, threshold = .98) {
  correlations <- abs(stats::cor(estimated, sources))
  expect_true(all(apply(correlations, 1, max) > threshold))
  expect_true(all(apply(correlations, 2, max) > threshold))
}

test_that("extended infomax recovers sources independent of sign and order", {
  set.seed(1)
  init_out <- run_infomax(mixed_data, extended = TRUE, verbose = FALSE)
  sources <- cbind(source_a, source_b, source_c)

  expect_named(init_out, c("M", "W", "S", "iter"))
  expect_sources_recovered(init_out$S, sources)
  expect_equal(init_out$S,
               unname(scale(mixed_data, scale = FALSE)) %*% init_out$W,
               ignore_attr = TRUE)
  expect_equal(init_out$S %*% t(init_out$M),
               unname(scale(mixed_data, scale = FALSE)),
               tolerance = 1e-6,
               ignore_attr = TRUE)
})

test_that("standard infomax returns internally consistent matrices", {
  set.seed(1)
  init_nonext <- run_infomax(mixed_data, extended = FALSE, verbose = FALSE)
  expect_length(init_nonext$iter, 1)
  expect_true(all(is.finite(init_nonext$S)))
  expect_equal(init_nonext$S,
               unname(scale(mixed_data, scale = FALSE)) %*% init_nonext$W,
               ignore_attr = TRUE)
})

test_that("PCA outputs map back to the original feature space", {
  four_electrodes <- cbind(
    mixed_data,
    E4 = 0.5 * mixed_data[, 1] - mixed_data[, 2] + 2 * mixed_data[, 3]
  )

  set.seed(2)
  pca_out <- run_infomax(four_electrodes, pca = 3, verbose = FALSE)

  expect_equal(dim(pca_out$M), c(4L, 3L))
  expect_equal(dim(pca_out$W), c(4L, 3L))
  expect_equal(dim(pca_out$S), c(nrow(four_electrodes), 3L))
  expect_equal(rownames(pca_out$M), colnames(four_electrodes))
  expect_equal(rownames(pca_out$W), colnames(four_electrodes))
  expect_equal(pca_out$S,
               unname(scale(four_electrodes, scale = FALSE)) %*% pca_out$W,
               ignore_attr = TRUE)
  expect_equal(pca_out$S %*% t(pca_out$M),
               unname(scale(four_electrodes, scale = FALSE)),
               tolerance = 1e-6,
               ignore_attr = TRUE)
})

test_that("arguments are validated before training", {
  expect_error(run_infomax(matrix("x", 3, 2), verbose = FALSE),
               "numeric matrix")
  expect_error(run_infomax(matrix(1, 3, 2), verbose = FALSE),
               "not full rank")
  expect_error(run_infomax(mixed_data, pca = 0), "`pca`")
  expect_error(run_infomax(mixed_data, pca = 1), "`pca`")
  expect_error(run_infomax(mixed_data, pca = 1.5), "`pca`")
  expect_error(run_infomax(mixed_data, blocksize = 0), "`blocksize`")
  expect_error(run_infomax(mixed_data, blocksize = nrow(mixed_data) + 1),
               "`blocksize`")
  expect_error(run_infomax(mixed_data, maxiter = 0), "`maxiter`")
  expect_error(run_infomax(mixed_data, tol = NA_real_), "`tol`")
})

test_that("early convergence preserves the actual iteration count", {
  set.seed(3)
  converged <- run_infomax(mixed_data, tol = 1e6, maxiter = 50,
                           verbose = FALSE)
  expect_equal(converged$iter, 3)
})

test_that("whitening can be disabled explicitly", {
  set.seed(4)
  unwhitened <- run_infomax(mixed_data, whiten = "none", maxiter = 1,
                            verbose = FALSE)
  expect_equal(dim(unwhitened$S), dim(mixed_data))
  expect_true(all(is.finite(unwhitened$S)))
})
