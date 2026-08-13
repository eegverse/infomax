# Run the (extended) Infomax algorithim in R
# 
# @param x Data matrix (rows = samples, columns = channels)
# @param maxiter Maximum number of iterations to run the algorithm
# @param blocksize Size of blocks of data used for learning
# @param lrate Initial learning rate
# @param kurt_size Size of blocks for kurtosis checking. Defaults to 6000 or
#   length of data, whichever is smaller.
# @param annealdeg Angle at which learning rate reduced.
# @param annealstep Annealing rate at which learning rate reduced.
# @param tol Tolerance for convergence of ICA. Defaults to 1e-07.
# @param extended Run extended-Infomax. Defaults to TRUE.
# @param verbose Print informative messages for each update of the algorithm.
# @return A list containing:
# * **weights**:  Estimated unmixing matrix
# * **iter**: Number of iterations completed
# * **converged**: TRUE if the algorithm converged, FALSE otherwise
# * **stop_reason**: Reason for stopping the algorithm ("maxiter", "small_angle", or "tol")
# * **restart_count**: Number of times the algorithm restarted due to weight blowup
# * **final_lrate**: Final learning rate after annealing
# @keywords internal

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

  delta <- numeric(n_comps^2)
  olddelta <- numeric(n_comps^2)
  oldsigns <- numeric(n_comps)

  extblocks <- 1
  signcount <- 0
  signcount_threshold <- 25
  signcount_step <- 2
  blockno <- 1
  min_lrate <- 1e-10

  nblock <- n_samps %/% blocksize
  lastt <- (nblock - 1) * blocksize + 1
  n_small_angle <- 20
  count_small_angle <- 0

  # Optimization: pre-compute sign matrix (updated only when signs change)
  if (extended) {
    signs_mat <- matrix(signs, n_comps, n_comps, byrow = TRUE)
  }

  converged <- FALSE
  stop_reason <- "maxiter"

  while (iter < maxiter && !converged) {
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
        y <- plogis(-u)

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

          test_act2 <- test_act * test_act

          kurt <- colMeans(test_act2 * test_act2) / colMeans(test_act2)^2 - 3

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
      angle_denom <- sqrt(change * oldchange)

      if (is.finite(angle_denom) && angle_denom > 0) {
        cos_angle <- sum(delta * olddelta) / angle_denom
        cos_angle <- max(-1, min(1, cos_angle))
        angledelta <- acos(cos_angle) * 180 / pi
      } else {
        angledelta <- 0
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
            converged <- TRUE
            stop_reason <- "small_angle"
            }
         }
      }

      if (iter > 2 && is.finite(change) && change < tol) {
        converged <- TRUE
        stop_reason <- "tol"
      } else if (!is.finite(change) || change > blowup_limit) {
        lrate <- lrate * blowup_fac
      }

    } else {

      iter <- 0
      blowup <- FALSE
      blockno <- 1
      count_small_angle <- 0
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
       iter = iter,
       converged = converged,
       stop_reason = stop_reason,
       restart_count = restart_count,
       final_lrate = lrate)
}
