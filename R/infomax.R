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
#' @param pca A scalar. Use PCA dimensionality reduction. Often helpful when the
#'   data is rank deficient.
#' @param anneal Annealing rate at which learning rate reduced.
#' @param annealdeg Angle at which learning rate reduced.
#' @param tol Tolerance for convergence of ICA. Defaults to 1e-07.
#' @param lrate Initial learning rate. NULL
#' @param blocksize Size of blocks of data used for learning.
#' @param kurtsize Size of blocks for kurtosis checking. Defaults to 6000 or
#'   length of data, whichever is smaller.
#' @param maxiter Maximum number of iterations. Defaults to 200.
#' @param extended Run extended-Infomax. Defaults to TRUE.
#' @param whiten Whitening method to use. See notes on usage.
#' @param verbose Print informative messages for each update of the algorithm.
#' @param backend Which backend to use: `"r"` (pure R) or `"cpp"` (C++/RcppArmadillo).
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
#' * **M**:  Estimated mixing matrix
#' * **W**:  Estimated unmixing matrix
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
                        verbose = TRUE,
                        backend = c("r", "cpp")) {

  x <- as.matrix(x)
  whiten <- match.arg(whiten)
  backend <- match.arg(backend)

  if (!is.numeric(x) || length(dim(x)) != 2L ||
      nrow(x) < 2L || ncol(x) < 1L) {
    stop("x must be a numeric matrix with at least two rows and one column.")
  }
  if (any(!is.finite(x))) {
    stop("x must contain only finite values.")
  }
  if (!is.logical(centre) || length(centre) != 1L || is.na(centre) ||
      !is.logical(extended) || length(extended) != 1L || is.na(extended) ||
      !is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("centre, extended, and verbose must be single TRUE/FALSE values.")
  }
  if (!is.null(pca) &&
      (length(pca) != 1L || !is.numeric(pca) || !is.finite(pca) ||
       pca < 1L || pca > min(nrow(x) - 1L, ncol(x)) ||
       pca != floor(pca))) {
    stop("pca must be an integer between 1 and the available data rank.")
  }
  scalar_controls <- list(anneal = anneal, annealdeg = annealdeg,
                          tol = tol, maxiter = maxiter, kurtsize = kurtsize)
  if (any(vapply(scalar_controls, function(z) {
    length(z) != 1L || !is.numeric(z) || !is.finite(z)
  }, logical(1)))) {
    stop("anneal, annealdeg, tol, maxiter, and kurtsize must be finite scalars.")
  }
  if (anneal <= 0 || anneal > 1 || annealdeg < 0 || tol < 0 ||
      maxiter < 1 || maxiter != floor(maxiter) || kurtsize < 1 ||
      kurtsize != floor(kurtsize)) {
    stop("Invalid annealing, tolerance, iteration, or kurtosis parameters.")
  }
  if (!is.null(lrate) &&
      (length(lrate) != 1L || !is.numeric(lrate) || !is.finite(lrate) ||
       lrate <= 0)) {
    stop("lrate must be a positive finite scalar.")
  }

  # Set blocksize if not provided
  blocksize <- ifelse(is.null(blocksize),
                      max(1L, ceiling(min(5 * log(nrow(x)), 0.3 * nrow(x)))),
                      blocksize)
  if (length(blocksize) != 1L || !is.numeric(blocksize) ||
      !is.finite(blocksize) || blocksize < 1 ||
      blocksize != floor(blocksize) || blocksize > nrow(x)) {
    stop("blocksize must be a positive integer no larger than nrow(x).")
  }

  # Center the data if required
  if (centre) {
    x <- scale(x, scale = FALSE)
    if (verbose) message("Removing column means...")
  }

  # Check rank after centering, since centering can reduce the rank by one.
  if (Matrix::rankMatrix(x) < if (is.null(pca)) ncol(x) else pca) {
    stop("x does not have sufficient rank for the requested number of components.")
  }

  # Perform PCA if specified
  x_orig <- x
  pca_decomp <- if (!is.null(pca)) {
    pca_decomp <- eigen(stats::cov(x))
    x <- x %*% pca_decomp$vectors[, 1:pca]
    pca_decomp
  } else {
    NULL
  }

  # Set initial learning rate if not provided
  lrate <- ifelse(is.null(lrate), .01 / log(ncol(x)^2), lrate)

  # Whitening the data
  whitened_data <- do_whitening(x, whiten)

  # Train ICA
  start_time <- proc.time()

  if (backend == "cpp") {
    rotation_mat <- ext_in_cpp(whitened_data$x_white,
                               maxiter = maxiter,
                               blocksize = blocksize,
                               lrate = lrate,
                               kurt_size = kurtsize,
                               annealdeg = annealdeg,
                               annealstep = anneal,
                               tol = tol,
                               extended = extended,
                               verbose = verbose)
  } else {
    rotation_mat <- ext_in(whitened_data$x_white,
                           blocksize = blocksize,
                           lrate = lrate, maxiter = maxiter,
                           annealdeg = annealdeg,
                           annealstep = anneal,
                           tol = tol,
                           extended = extended,
                           kurt_size = kurtsize,
                           verbose = verbose)
  }

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

  if (verbose) {
    end_time <- proc.time() - start_time
    message(sprintf("ICA running time: %.3f s", end_time[[3]]))
  }

  S <- x_orig %*% unmixing_mat
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

  # Optimization: store bias as a plain vector (not a matrix)
  bias <- numeric(n_comps)

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
  max_restarts <- 50
  restart_count <- 0

  kurt_size <- min(kurt_size,
                   nrow(x))

  degconst <- 180 / pi

  delta <- numeric(n_comps^2)
  olddelta <- numeric(n_comps^2)
  oldsigns <- numeric(n_comps)

  extblocks <- 1
  signcount <- 0
  signcount_threshold <- 25
  signcount_step <- 2
  blockno <- 1

  w_change <- tol
  min_lrate <- 1e-10

  nblock <- n_samps %/% blocksize
  lastt <- (nblock - 1) * blocksize + 1
  n_small_angle <- 20
  count_small_angle <- 0

  # Optimization: pre-compute sign matrix (updated only when signs change)
  if (extended) {
    signs_mat <- matrix(signs, n_comps, n_comps, byrow = TRUE)
  }

  while (iter < maxiter) {
    # shuffle timepoints
    perms <- sample.int(nrow(x))
    for (t in seq(1, lastt, by = blocksize)) {
      this_set <- perms[t:(t + blocksize - 1)]
      u <- x[this_set, ] %*% weights
      # Optimization: bias is a plain vector; sweep is cleaner than matrix()
      u <- sweep(u, 2, bias, "+")

      if (extended) {
        y <- tanh(u)

        # Optimization: inlined weight update (no closure call overhead)
        # uses pre-computed signs_mat instead of rebuilding each block
        weights <- weights + lrate * weights %*%
          (BI - signs_mat * crossprod(u, y) - crossprod(u))

        bias <- bias - 2 * lrate * colSums(y)
      } else {
        y <- 1 / (1 + exp(-u))

        weights <- weights + lrate * weights %*%
          (BI + crossprod(u, (1 - 2 * y)))

        bias <- bias + lrate * colSums(1 - 2 * y)
      }

      # Check the update before doing any further calculations. In particular,
      # do not send non-finite weights into the kurtosis calculation.
      if (!all(is.finite(weights)) ||
          !all(is.finite(bias)) ||
          !is.finite(lrate) ||
          max(abs(weights)) > max_weight) {
        blowup <- TRUE
      }

      if (blowup) {
        break
      }

      if (extended) {
        # kurtosis estimation (sign adaptation)
        if (extblocks > 0 && blockno %% extblocks == 0) {
          if (kurt_size < n_samps) {
            test_act <- x[sample.int(nrow(x), kurt_size), ] %*% weights
          } else {
            test_act <- x %*% weights
          }

          kurt <- colMeans(test_act^4) / colMeans(test_act^2)^2 - 3

          if (extmomentum > 0) {
            kurt <- extmomentum * old_kurt + (1 - extmomentum) * kurt
            old_kurt <- kurt
          }

          new_signs <- sign(kurt + signsbias)

          if (isTRUE(all.equal(new_signs, oldsigns))) {
            signcount <- signcount + 1
          } else {
            signcount <- 0
          }

          oldsigns <- new_signs

          # Optimization: only rebuild signs_mat when signs actually changed
          if (!identical(new_signs, signs)) {
            signs <- new_signs
            signs_mat <- matrix(signs, n_comps, n_comps, byrow = TRUE)
          } else {
            signs <- new_signs
          }

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
      change <- sum(delta * delta)

      if (iter > 2) {
        cos_angle <- sum(delta * olddelta) / sqrt(change * oldchange)
        cos_angle <- max(-1, min(1, cos_angle))
        angledelta <- acos(cos_angle)
        angledelta <- degconst * angledelta
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
      } else {
        if (iter == 1) {
          olddelta <- delta
          oldchange <- change
        }
        if (n_small_angle > 0) {
           count_small_angle <- count_small_angle + 1
           if (count_small_angle > n_small_angle) {
             maxiter <- iter
           }
         }
      }

      if (iter > 2 && is.finite(change) && change < w_change) {
        iter <- maxiter
      } else if (!is.finite(change) || change > blowup_limit) {
        lrate <- lrate * blowup_fac
      }

    } else {

      iter <- 0
      blowup <- FALSE
      blockno <- 1
      restart_count <- restart_count + 1
      if (restart_count > max_restarts ||
          !is.finite(lrate) || lrate * restart_fac < min_lrate) {
        stop("Infomax failed after repeated weight blowups.")
      }
      lrate <- lrate * restart_fac
      if (verbose) {
        message(paste("Weights blown up, lowering lrate to ", lrate))
      }
      weights <- startweights
      oldweights <- startweights
      olddelta <- numeric(n_comps^2)
      oldchange <- 0
      bias <- numeric(n_comps)

      extblocks <- 1
      signs <- rep(1, n_comps)
      signs[1] <- -1
      signs_mat <- matrix(signs, n_comps, n_comps, byrow = TRUE)
      oldsigns <- numeric(n_comps)
      old_kurt <- 0
      signcount <- 0
    }

  }
  list(weights = weights,
       iter = iter)
}

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
