# Whiten the data using the specified method. This function is used internally by the infomax function and is not intended for direct use by users.
# @keywords internal
do_whitening <- function(x,
                         whiten) {

  if (identical(whiten,
                "sqrtm")) {
    white_cov <- eigen(stats::cov(x))
    white_cov <- white_cov$vectors %*% diag(1/sqrt(white_cov$values)) %*% MASS::ginv(white_cov$vectors)
    white_cov <- 2 * white_cov
    x_white <- t(tcrossprod(white_cov,
                            x))
  } else {
    white_cov <-
      whitening::whiteningMatrix(stats::cov(as.matrix(x)),
                                 method = whiten)
    x_white <- whitening::whiten(x,
                                 method = whiten)
  }
  list(x_white = x_white,
       white_cov = white_cov)
}
