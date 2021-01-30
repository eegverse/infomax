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

test_that("extended infomax runs", {
  init_out <- run_infomax(mixed_data)
  expect_type(init_out, "list")
  expect_true(abs(cor(init_out$S[, 1], source_a)) > .98)
  expect_true(abs(cor(init_out$S[, 2], source_b)) > .98)
  expect_true(abs(cor(init_out$S[, 3], source_c)) > .98)
  init_nonext <- run_infomax(mixed_data, extended = FALSE)
  expect_type(init_nonext, "list")
  expect_true(abs(cor(init_nonext$S[, 1], source_a)) > .98)
  expect_true(abs(cor(init_nonext$S[, 2], source_b)) > .98)
  expect_true(abs(cor(init_nonext$S[, 3], source_c)) > .98)
})
