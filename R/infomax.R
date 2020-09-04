#' Run Infomax ICA
#'
#' Run Infomax and extended-Infomax on a matrix of data. Mini-batch stochastic gradient descent algorithm.
#'
#' @param x matrix of data; features in columns, samples in rows.
#' @param centre mean-centre columns
#' @param pca Use PCA dimensionality reduction
#' @param anneal Anneal rate at which learning rate reduced
#' @param annealdeg Angle at which learning rate reduced
#' @param tol Tolerance for convergence of ICA
#' @param lrate Initial learning rate
#' @param blocksize size of blocks of data used for learning
#' @param kurtsize Size of blocks for kurtosis checking
#' @param maxiter Maximum number of iterations
#' @param extended Run extended-Infomax
#' @param whiten Whitening method to use
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
                        whiten = c("ZCA",
                                   "PCA",
                                   "ZCA-cor",
                                   "PCA-cor",
                                   "none",
                                   "eeglab"),
                        verbose = TRUE) {

  x <- as.matrix(x)
  whiten <- match.arg(whiten,
                      c("ZCA", "PCA",
                        "ZCA-cor", "PCA-cor",
                        "none", "eeglab"))

  if (is.null(pca)) {
    if (Matrix::rankMatrix(x) < ncol(x)) {
      stop("Matrix is not full rank.")
    }
  }

  # heuristic from EEGLAB; mne uses floor(sqrt(n_samps / 3))
  if (is.null(blocksize)) {
    blocksize <-
      ceiling(min(5 * log(nrow(x)),
                  0.3 * nrow(x)))
  }

  # # 1. remove channel means
  if (centre) {
   x <- scale(x, scale = FALSE)
  }

  # 2. perform pca if necessary
  if (!is.null(pca)) {
    pca_decomp <- eigen(stats::cov(x))
    eigenvals <- pca_decomp$values
    pca_decomp <- pca_decomp$vectors
    x_o <- x
    x <- x %*% pca_decomp[, 1:pca]
    pca_flag <- TRUE
    ncomp <- pca
  } else {
    pca_flag <- FALSE
    ncomp <- ncol(x)
  }

  # use mne-python lrate heuristic - eeglab one sets it too small.
  if (is.null(lrate)) {
    lrate <- .01 / log(ncomp^2)
  }

  # 3. perform whitening/sphering
  if (identical(whiten, "eeglab")) {
    white_cov <- 2.0 * pracma::sqrtm(cov(x))$Binv
    x_white <- t(tcrossprod(white_cov, x))
  } else {
    white_cov <-
      whitening::whiteningMatrix(stats::cov(as.matrix(x)),
                                 method = whiten)
    x_white <- whitening::whiten(x,
                                 method = whiten)
  }


  # # #cov(x)

  #



  # 4. Train ICA
  start_time <- proc.time()
  rotation_mat <-
    ext_in(x_white,
           blocksize = blocksize,
           lrate = lrate,
           maxiter = maxiter,
           annealdeg = annealdeg,
           annealstep = anneal,
           tol = tol,
           verbose = verbose)


   #unmix_mat <- sweep(unmix_mat, 2, sqrt(eigenvals[1:pca]), "/")
   #mixing_mat <- MASS::ginv(unmix_mat)
  unmix_mat <- crossprod(rotation_mat, white_cov)
  mixing_mat <- MASS::ginv(unmix_mat, tol = 0)
   # mixing_mat <-
   #    MASS::ginv(white_cov, tol = 0) %*% t(unmix_mat)
   #
  if (pca_flag) {
    mixing_mat <- pca_decomp[, 1:pca] %*% mixing_mat
  }

  comp_var <- colSums(mixing_mat^2)
  vafs <- comp_var / sum(comp_var)
  vaf_order <-
    sort(vafs,
       decreasing = TRUE,
       index.return = TRUE)$ix
  mixing_mat <- mixing_mat[, vaf_order]

  unmixing_mat <- t(MASS::ginv(mixing_mat, tol = 0))

  if (pca_flag) {
     x <- x_o
  }

  if (verbose) {
    end_time <-  proc.time() - start_time
    message(paste0("ICA running time: ",
                   round(end_time[[3]], 3),
                   " s"))
  }

  S <- as.data.frame(x %*% unmixing_mat)
  names(S) <- sprintf("Comp%03d", 1:ncol(S))
  list(M = mixing_mat,
       W = unmixing_mat,
       S = S)
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
  min_lrate <- 1e-10

  nblock <- n_samps %/% blocksize
  lastt <- (nblock - 1) * blocksize + 1
  n_small_angle <- 20
  count_small_angle <- 0
  sum_change <- 0
  cum_delta <- 0

  while (iter < maxiter) {
    # shuffle timepoints
    perms <- sample.int(nrow(x))

    quick_time <- proc.time()
    for (t in seq(1, lastt, by = blocksize)) {
      this_set <- perms[t:(t + blocksize - 1)]
      u <- x[this_set, ] %*% weights
      #u <- eigenMatMult(x[this_set, ], weights)
      #u <- u + bias[, 1]
      u <- u + matrix(bias[, 1],
                       blocksize,
                       n_comps,
                       byrow = TRUE)
      y <- tanh(u)

      weights <- weights + lrate * weights %*% (BI - matrix(signs, n_comps, n_comps, byrow = TRUE) * crossprod(u, y) - crossprod(u))

      bias <- bias + lrate * colSums(y) * -2

      # check weights
      if (max(abs(weights)) > max_weight) {
        blowup <- TRUE
      }

      # kurtosis estimation
      if (extblocks > 0 & blockno %% extblocks == 0) {
        if (kurt_size < n_samps) {
          test_act <- x[sample.int(nrow(x), kurt_size), ] %*% weights
        } else {
          test_act <- x %*% weights
        }

        #m4 <- colMeans(test_act * test_act * test_act * test_act)
        #m2 <- colMeans(test_act^2)^2
        #kurt <- m4 / m2 - 3
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
      #sum_change <- sum(cum_delta + wtchange * wtchange)
      #sum_change <- (oldweights * .9 + (1-.9) * wtchange^2)

      if (iter > 2) {
        angledelta <- acos(sum(delta * olddelta) /
                             sqrt(change * oldchange))
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
        #lrate <- lrate / sqrt(sum_change + 1e-06)
        olddelta <- delta
        oldchange <- change
      } else {
        if (iter == 1) {
          olddelta <- delta
          oldchange <- change
        }
        # if (n_small_angle > 0) {
        #   count_small_angle <- count_small_angle + 1
        #   if (count_small_angle > n_small_angle) {
        #     maxiter <- iter
        #   }
        # }
      }

      if (iter > 2 & change < w_change) {
        iter <- maxiter
      } else if (change > blowup_limit) {
        lrate <- lrate * blowup_fac
      }

      #cum_delta <- cum_delta + delta^2
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
    hej <- proc.time() - quick_time
    cat(round(hej[[3]], 3))
  }
  weights
}
