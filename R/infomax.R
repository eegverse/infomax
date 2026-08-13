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
      nrow(x) < 2L || ncol(x) < 2L) {
    stop("x must be a numeric matrix with at least two rows and two columns.")
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
       pca < 2L || pca > min(nrow(x) - 1L, ncol(x)) ||
       pca != floor(pca))) {
    stop("pca must be an integer between 2 and the available data rank.")
  }
  scalar_controls <- list(anneal = anneal, annealdeg = annealdeg,
                          tol = tol, maxiter = maxiter, kurtsize = kurtsize)
  if (any(vapply(scalar_controls, function(z) {
    length(z) != 1L || !is.numeric(z) || !is.finite(z)
  }, logical(1)))) {
    stop("anneal, annealdeg, tol, maxiter, and kurtsize must be finite scalars.")
  }
  if (anneal <= 0 || anneal > 1 || annealdeg < 0 || annealdeg > 180 || tol < 0 ||
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
  if (is.null(blocksize)) {
    blocksize <- max(1L, ceiling(min(5 * log(nrow(x)), 0.3 * nrow(x))))
  }

  if (length(blocksize) != 1L || !is.numeric(blocksize) ||
      !is.finite(blocksize) || blocksize < 1 ||
      blocksize != floor(blocksize) || blocksize > nrow(x)) {
    stop("blocksize must be a positive integer no larger than nrow(x).")
  }

  # Centre the data if required
  if (centre) {
    x <- scale(x, scale = FALSE)
    if (verbose) message("Removing column means...")
  }

  # Check rank after centreing, since centreing can reduce the rank by one.
  if (Matrix::rankMatrix(x) < if (is.null(pca)) ncol(x) else pca) {
    stop("x does not have sufficient rank for the requested number of components.")
  }

  if (identical(whiten, "none") && !is.null(pca) && pca < ncol(x)) {
    stop("Cannot use PCA dimensionality reduction without whitening.")
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
  if (is.null(lrate)) {
    lrate <- 0.01 / log(ncol(x)^2)
  } 

  # Whitening the data
  if (identical(whiten, "none")) {
    whitened_data <- list(x_white = x, white_cov = diag(ncol(x)))
  } else {
    if (verbose) message("Whitening data...")
    whitened_data <- do_whitening(x, whiten)
  }
  
  # Train ICA
  start_time <- proc.time()

  if (identical(backend, "cpp")) {
    rotation_mat <- ext_in_cpp(
      whitened_data$x_white,
      maxiter = maxiter,
      blocksize = blocksize,
      lrate = lrate,
      kurt_size = kurtsize,
      annealdeg = annealdeg,
      annealstep = anneal,
      tol = tol,
      extended = extended,
      verbose = verbose
    )
  } else {
    rotation_mat <- ext_in(
      whitened_data$x_white,
      blocksize = blocksize,
      lrate = lrate,
      maxiter = maxiter,
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

  list(
    M = mixing_mat,
    W = unmixing_mat,
    S = S,
    iter = rotation_mat$iter,
    converged = rotation_mat$converged,
    stop_reason = rotation_mat$stop_reason,
    final_lrate = rotation_mat$final_lrate,
    restart_count = rotation_mat$restart_count)
}

