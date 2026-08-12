#' Run Infomax Independent Component Analysis
#'
#' Run Infomax or extended-Infomax on a matrix of data. Uses a mini-batch stochastic
#' gradient descent algorithm. The matrix can be prewhitened in several ways. The default is to perform
#' sphering using the inverse of the square root of the covariance matrix of the
#' original data, the method used by the 'EEGLAB' and 'MNE-Python' toolboxes in
#' other languages. Whitening methods implemented in the package `whitening` are
#' `PCA`, `ZCA`, `ZCA-cor`, and `PCA-cor`. Please see the `whitening` package
#' for further information on their implementation of these methods.
#'
#' @param x matrix of data; features in columns, samples in rows.
#' @param centre Mean-centre columns before running the algorithm. Defaults to
#'   TRUE.
#' @param pca A whole number of components to retain with PCA dimensionality
#'   reduction. Must be at least two and no greater than the processed data rank.
#'   Often helpful when the data is rank deficient.
#' @param anneal Annealing rate at which learning rate reduced.
#' @param annealdeg Angle at which learning rate reduced.
#' @param tol Tolerance for convergence of ICA. Defaults to 1e-07.
#' @param lrate Initial learning rate. When `NULL`, a heuristic based on the
#'   number of components is used.
#' @param blocksize Size of blocks of data used for learning. Must be a whole
#'   number between one and the number of samples.
#' @param kurtsize Size of blocks for kurtosis checking. Defaults to 6000 or
#'   length of data, whichever is smaller.
#' @param maxiter Maximum number of iterations. Defaults to 200.
#' @param extended Run extended-Infomax. Defaults to TRUE.
#' @param whiten Whitening method to use. See notes on usage.
#' @param verbose Print informative messages for each update of the algorithm.
#' @author Matt Craddock \email{matt@@mattcraddock.com}
#' @examples
#' time_x <- seq(0, 1, by = 1/256)
#' source_a <- sin(2 * pi * 5 * time_x)
#' source_b <- sin(2 * pi * 10 * time_x)
#' plot(time_x, source_a, type = "l")
#' plot(time_x, source_b, type = "l")
#' plot(time_x, source_a + 2 * source_b, type = "l")
#' plot(time_x, source_a * 3.4 + 1.5 * source_b, type = "l")
#' mixed_data <- matrix(NA,
#'     nrow = length(time_x),
#'     ncol = 2)
#' mixed_data[, 1] <- source_a + 2 * source_b
#' mixed_data[, 2] <- source_a * 3.4 + 1.5 * source_b
#' dat_out <- run_infomax(mixed_data, whiten = "PCA")
#' plot(time_x, dat_out$S[, 1],
#'     type = "l")
#' plot(time_x,
#'      dat_out$S[, 2],
#'      type = "l")
#' @references * Bell, A.J., & Sejnowski, T.J. (1995). An
#' information-maximization approach to blind separation and blind
#' deconvolution. *Neural Computation, 7,* 1129-159
#' * Makeig, S., Bell, A.J., Jung, T-P and Sejnowski, T.J., "Independent component analysis of
#' electroencephalographic data,"  In: D. Touretzky, M. Mozer and M. Hasselmo
#' (Eds). Advances in Neural  Information Processing Systems 8:145-151, MIT
#' Press, Cambridge, MA (1996).
#' @return A list containing:
#' * **S**:  Matrix of source estimates
#' * **M**:  Estimated mixing matrix (features by components)
#' * **W**:  Estimated unmixing matrix (features by components)
#' * **iter**: Number of iterations completed
#' @export
run_infomax <- function(x,
                        centre = TRUE,
                        pca = NULL,
                        anneal = .98,
                        annealdeg = 60,
                        tol = 1e-7,
                        lrate = NULL,
                        blocksize = NULL,
                        kurtsize = 6000,
                        maxiter = 200,
                        extended = TRUE,
                        whiten = c("sqrtm",
                                   "ZCA",
                                   "PCA",
                                   "ZCA-cor",
                                   "PCA-cor",
                                   "none"),
                        verbose = TRUE) {

  x <- as.matrix(x)
  feature_names <- colnames(x)
  whiten <- match.arg(whiten)

  if (!is.numeric(x) || length(dim(x)) != 2L) {
    stop("`x` must be a numeric matrix.", call. = FALSE)
  }
  if (nrow(x) < 2L || ncol(x) < 2L) {
    stop("`x` must contain at least two samples and two features.",
         call. = FALSE)
  }
  if (anyNA(x) || any(!is.finite(x))) {
    stop("`x` must not contain missing or infinite values.", call. = FALSE)
  }

  check_flag <- function(value, name) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop(sprintf("`%s` must be TRUE or FALSE.", name), call. = FALSE)
    }
  }
  check_scalar <- function(value, name, lower, upper = Inf,
                           integer = FALSE, lower_open = FALSE) {
    valid <- is.numeric(value) && length(value) == 1L && is.finite(value)
    if (valid) {
      valid_lower <- if (lower_open) value > lower else value >= lower
      valid <- valid_lower && value <= upper && (!integer || value == floor(value))
    }
    if (!valid) {
      qualifier <- if (integer) "a whole number" else "a number"
      stop(sprintf("`%s` must be %s between %s%s and %s.",
                   name, qualifier, if (lower_open) "> " else "", lower, upper),
           call. = FALSE)
    }
  }

  check_flag(centre, "centre")
  check_flag(extended, "extended")
  check_flag(verbose, "verbose")
  check_scalar(anneal, "anneal", 0, 1, lower_open = TRUE)
  check_scalar(annealdeg, "annealdeg", 0, 180)
  check_scalar(tol, "tol", 0, lower_open = TRUE)
  check_scalar(kurtsize, "kurtsize", 1, integer = TRUE)
  check_scalar(maxiter, "maxiter", 1, integer = TRUE)

  if (!is.null(pca)) {
    check_scalar(pca, "pca", 2, ncol(x), integer = TRUE)
    pca <- as.integer(pca)
  }
  if (!is.null(lrate)) {
    check_scalar(lrate, "lrate", 0, lower_open = TRUE)
  }

  # Set blocksize if not provided
  if (is.null(blocksize)) {
    blocksize <- ceiling(min(5 * log(nrow(x)), 0.3 * nrow(x)))
  }
  check_scalar(blocksize, "blocksize", 1, nrow(x), integer = TRUE)
  blocksize <- as.integer(blocksize)

  # Center the data if required
  if (centre) {
    x <- scale(x, scale = FALSE)
    if (verbose) message("Removing column means...")
  }

  # Check the rank of the data actually supplied to PCA/ICA. Centering can
  # reduce rank, so checking the uncentered input is insufficient.
  data_rank <- as.integer(Matrix::rankMatrix(x))
  if (is.null(pca) && data_rank < ncol(x)) {
    stop("Matrix is not full rank; use `pca` to reduce its dimensionality.",
         call. = FALSE)
  }
  if (!is.null(pca) && pca > data_rank) {
    stop(sprintf("`pca` must not exceed the processed data rank (%d).", data_rank),
         call. = FALSE)
  }

  # Perform PCA if specified
  pca_decomp <- if (!is.null(pca)) {
    pca_decomp <- eigen(stats::cov(x))
    x_original_space <- x
    x <- x %*% pca_decomp$vectors[, 1:pca]
    pca_decomp
  } else {
    NULL
  }

  # Set initial learning rate if not provided
  if (is.null(lrate)) {
    lrate <- .01 / log(ncol(x)^2)
  }

  # Whitening the data
  whitened_data <- do_whitening(x, whiten)

  # Train ICA
  start_time <- proc.time()
  rotation_mat <- ext_in(whitened_data$x_white,
                         blocksize = blocksize,
                         lrate = lrate, maxiter = maxiter,
                         annealdeg = annealdeg,
                         annealstep = anneal,
                         tol = tol,
                         extended = extended,
                         kurt_size = kurtsize,
                         verbose = verbose)

  # Calculate mixing and unmixing matrices
  unmix_mat <- crossprod(rotation_mat$weights, whitened_data$white_cov)
  mixing_mat <- MASS::ginv(unmix_mat, tol = 0)

  if (!is.null(pca_decomp)) {
    mixing_mat <- pca_decomp$vectors[, 1:ncol(x)] %*% mixing_mat
  }

  # Variance accounted for (VAF)
  comp_var <- colSums(mixing_mat^2)
  vafs <- comp_var / sum(comp_var)
  mixing_mat <- mixing_mat[, order(vafs, decreasing = TRUE)]

  unmixing_mat <- t(MASS::ginv(mixing_mat, tol = 0))
  rownames(mixing_mat) <- feature_names
  rownames(unmixing_mat) <- feature_names

  if (verbose) {
    end_time <- proc.time() - start_time
    message(sprintf("ICA running time: %.3f s", end_time[[3]]))
  }

  if (!is.null(pca_decomp)) {
    x <- x_original_space
  }
  S <- x %*% unmixing_mat
  colnames(S) <- sprintf("Comp%03d", 1:ncol(S))

  list(M = mixing_mat, W = unmixing_mat, S = S, iter = rotation_mat$iter)
}

ext_in <- function(x,
                   maxiter,
                   blocksize,
                   lrate,
                   kurt_size = 6000,
                   annealdeg,
                   annealstep,
                   tol,
                   extended = TRUE,
                   verbose = TRUE) {

  n_comps <- ncol(x)
  n_samps <- nrow(x)

  weights <- diag(n_comps)
  startweights <- weights
  oldweights <- weights
  oldchange <- 0

  bias <- array(0,
                dim = c(n_comps, 1))
  onesrow <- array(1,
                  dim = c(1, blocksize))

  BI <- blocksize * diag(n_comps)

  signs <- rep(1, n_comps)
  signs[1] <- -1

  iter <- 0
  extmomentum <- 0.5
  old_kurt <- 0
  signsbias <- .02
  max_weight <- 1e8

  # blowup and restart
  blowup_limit <- 1e9
  blowup <- FALSE
  blowup_fac <- 0.8
  restart_fac <- .9

  kurt_size <- min(kurt_size,
                   nrow(x))

  degconst <- 180 / pi

  delta <- numeric(n_comps^2)
  oldsigns <- numeric(n_comps)

  signcounts <- NULL
  extblocks <- 1
  signcount_threshold <- 25
  signcount_step <- 2
  blockno <- 1

  w_change <- tol

  nblock <- n_samps %/% blocksize
  lastt <- (nblock - 1) * blocksize + 1
  n_small_angle <- 20
  count_small_angle <- 0
  converged <- FALSE

  if (extended) {
    loss_fun <- tanh
    bias_fun <- function(y) {
      colSums(y) * - 2
    }

    update_weights <- function(weights,
                               BI,
                               signs,
                               n_comps,
                               u,
                               y) {
      weights %*% (BI - matrix(signs, n_comps, n_comps, byrow = TRUE) * crossprod(u, y) - crossprod(u))
    }

  } else {
    loss_fun <-
      function(u) {
        1 / (1 + exp(-u))
      }
    bias_fun <- function(y) {
      colSums(1 - 2 * y)
    }

    update_weights <- function(weights,
                               BI,
                               signs,
                               n_comps,
                               u,
                               y) {
      weights %*% (BI + crossprod(u, (1 - 2 * y)))
    }

  }

  while (iter < maxiter && !converged) {
    # shuffle timepoints
    perms <- sample.int(nrow(x))
    for (t in seq(1, lastt, by = blocksize)) {
      this_set <- perms[t:(t + blocksize - 1)]
      u <- x[this_set, ] %*% weights
      u <- u + matrix(bias[, 1],
                       blocksize,
                       n_comps,
                       byrow = TRUE)

      y <- loss_fun(u)

      #weights <- weights + lrate * weights %*% (BI - matrix(signs, n_comps, n_comps, byrow = TRUE) * crossprod(u, y) - crossprod(u))

      weights <- weights + lrate * update_weights(weights,
                                                  BI,
                                                  signs,
                                                  n_comps,
                                                  u,
                                                  y)
      bias <- bias + lrate * bias_fun(y) #colSums(y) * -2

      # check weights
      if (max(abs(weights)) > max_weight) {
        blowup <- TRUE
      }

      if (extended) {
        # kurtosis estimation
        if (extblocks > 0 & blockno %% extblocks == 0) {
          if (kurt_size < n_samps) {
            test_act <- x[sample.int(nrow(x), kurt_size), ] %*% weights
          } else {
            test_act <- x %*% weights
          }

          kurt <- colMeans(test_act * test_act * test_act * test_act) / colMeans(test_act^2)^2
          kurt <- kurt - 3

          if (extmomentum > 0) {
            kurt <- extmomentum * old_kurt + (1 - extmomentum) * kurt
            old_kurt <- kurt
          }

          signs <- sign(kurt + signsbias)

          if (isTRUE(all.equal(signs, oldsigns))) {
            signcount <- signcount + 1
          } else {
            signcount <- 0
          }

          oldsigns <- signs
          signcounts <- c(signcounts,
                          signcount)
          if (signcount >= signcount_threshold) {
            extblocks <- trunc(extblocks * signcount_step)
            signcount <- 0
          }
        }
      }
      blockno <- blockno + 1
      if (blowup) {
        break
      }
    }
    if (!blowup) {
      wtchange <- weights - oldweights
      iter <- iter + 1
      angledelta <- 0
      delta <- as.numeric(wtchange)
      change <- sum(wtchange * wtchange)

      if (iter > 2) {
        angle_denom <- sqrt(change * oldchange)
        if (is.finite(angle_denom) && angle_denom > 0) {
          angle_cos <- sum(delta * olddelta) / angle_denom
          angle_cos <- max(-1, min(1, angle_cos))
          angledelta <- degconst * acos(angle_cos)
        }
      }

      oldweights <- weights

      if (verbose) {
        message(paste0(
          sprintf("Step: %d, lrate: %5f, wchange: %8.8f, angledelta: %4.1f",
                  iter,
                  lrate,
                  change,
                  angledelta)
          )
        )
      }

      if (angledelta > annealdeg) {
        lrate <- lrate * annealstep
        olddelta <- delta
        oldchange <- change
        count_small_angle <- 0
      } else {
        if (iter == 1) {
          olddelta <- delta
          oldchange <- change
        }
        if (n_small_angle > 0) {
           count_small_angle <- count_small_angle + 1
           if (count_small_angle > n_small_angle) {
             converged <- TRUE
           }
         }
      }

      if (iter > 2 & change < w_change) {
        converged <- TRUE
      } else if (change > blowup_limit) {
        lrate <- lrate * blowup_fac
      }

    } else {

      iter <- 0
      blowup <- FALSE
      blockno <- 1
      lrate <- lrate * restart_fac
      message(paste("Weights blown up, lowering lrate to ",
                    lrate))
      weights <- startweights
      oldweights <- startweights
      olddelta <- numeric(n_comps)
      bias <- array(0,
                    dim = c(n_comps, 1))

      extblocks <- 0
      signs <- rep(1, n_comps)
      signs[1] <- -1
      oldsigns <- numeric(n_comps)
    }

  }
  list(weights = weights,
       iter = iter)
}

do_whitening <- function(x,
                         whiten) {

  if (identical(whiten, "none")) {
    white_cov <- diag(ncol(x))
    x_white <- x
  } else if (identical(whiten,
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
