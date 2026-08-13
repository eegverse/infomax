// [[Rcpp::depends(RcppArmadillo)]]
#define ARMA_DONT_USE_OPENMP
#include <RcppArmadillo.h>
using namespace Rcpp;

//' Core Extended Infomax ICA (C++ backend)
//'
//' Internal C++ implementation of the mini-batch stochastic gradient descent
//' Infomax/Extended-Infomax algorithm. Called by \code{run_infomax()} when
//' \code{backend = "cpp"}.
//'
//' @param x Data matrix, samples in rows, components in columns (n_samps x n_comps).
//' @param maxiter Maximum number of outer iterations.
//' @param blocksize Mini-batch size.
//' @param lrate Initial learning rate.
//' @param kurt_size Number of samples for kurtosis estimation.
//' @param annealdeg Angle threshold for learning rate annealing.
//' @param annealstep Learning rate multiplier on annealing.
//' @param tol Convergence tolerance on squared weight change.
//' @param extended If TRUE, run Extended Infomax (tanh + kurtosis sign adaptation).
//' @param verbose If TRUE, print progress each iteration.
//' @return A list with \code{weights} (n_comps x n_comps) and \code{iter} (int).
//' @keywords internal
// [[Rcpp::export]]
List ext_in_cpp(const arma::mat& x,
                int maxiter,
                int blocksize,
                double lrate,
                int kurt_size,
                double annealdeg,
                double annealstep,
                double tol,
                bool extended,
                bool verbose) {

  int n_comps = x.n_cols;
  int n_samps = x.n_rows;

  // Transpose once for cache-friendly column access in inner loop:
  // x_t is n_comps x n_samps; x_t.cols(idx) pulls a block without row-select
  arma::mat x_t = x.t();

  arma::mat W = arma::eye<arma::mat>(n_comps, n_comps);
  arma::mat W_old = W;
  arma::mat W_start = W;
  arma::vec bias = arma::zeros<arma::vec>(n_comps);
  arma::mat BI = (double)blocksize * arma::eye<arma::mat>(n_comps, n_comps);

  arma::vec signs = arma::ones<arma::vec>(n_comps);
  signs(0) = -1.0;
  arma::vec oldsigns = arma::zeros<arma::vec>(n_comps);

  int nblock = n_samps / blocksize;
  int lastt = (nblock - 1) * blocksize;  // last valid block start (0-indexed)

  double max_weight   = 1e8;
  double blowup_limit = 1e9;
  double blowup_fac   = 0.8;
  double restart_fac  = 0.9;
  double extmomentum  = 0.5;
  double signsbias    = 0.02;
  double degconst     = 180.0 / arma::datum::pi;

  int extblocks          = 1;
  int signcount          = 0;
  int blockno            = 1;
  int signcount_threshold = 25;
  int signcount_step     = 2;
  int n_small_angle      = 20;
  int count_small_angle  = 0;

  arma::vec old_kurt = arma::zeros<arma::vec>(n_comps);

  arma::vec olddelta = arma::zeros<arma::vec>(n_comps * n_comps);
  double oldchange   = 0.0;
  bool blowup        = false;
  int iter           = 0;

  kurt_size = std::min(kurt_size, n_samps);

  // Cache signs as rowvec for each_row() scaling; updated only when signs change
  arma::rowvec signs_r = signs.t();

  // Use R's RNG for reproducible, consistent behaviour with the R backend
  auto r_randperm = [&](int n) -> arma::uvec {
    Rcpp::IntegerVector p = Rcpp::sample(n, n, false);
    arma::uvec out(n);
    for (int i = 0; i < n; i++) out[i] = (arma::uword)(p[i] - 1);
    return out;
  };
  auto r_randsamp = [&](int n, int k) -> arma::uvec {
    Rcpp::IntegerVector p = Rcpp::sample(n, k, false);
    arma::uvec out(k);
    for (int i = 0; i < k; i++) out[i] = (arma::uword)(p[i] - 1);
    return out;
  };

  while (iter < maxiter) {
    arma::uvec perms = r_randperm(n_samps);
    blowup = false;

    for (int t = 0; t <= lastt; t += blocksize) {
      // Pull block using transposed layout: n_comps x blocksize
      arma::uvec idx = perms.subvec(t, t + blocksize - 1);
      // u = x_block * W  (blocksize x n_comps)
      arma::mat u = x_t.cols(idx).t() * W;
      u.each_row() += bias.t();

      arma::mat grad;
      if (extended) {
        arma::mat ut = u.t();
        arma::mat y  = arma::tanh(u);
        arma::mat uy = ut * y;
        uy.each_row() %= signs_r;      // column-scale by signs, no diagmat alloc
        grad = BI - uy - ut * u;

        W += lrate * W * grad;
        bias -= 2.0 * lrate * arma::sum(y, 0).t();
      } else {
        arma::mat y        = 1.0 / (1.0 + arma::exp(-u));
        arma::mat one_m_2y = 1.0 - 2.0 * y;   // compute once, reuse twice
        arma::mat ut       = u.t();
        grad = BI + ut * one_m_2y;

        W += lrate * W * grad;
        bias += lrate * arma::sum(one_m_2y, 0).t();
      }

      if (arma::abs(W).max() > max_weight) {
        blowup = true;
        break;
      }

      // Kurtosis-based sign adaptation (extended mode only)
      if (extended && extblocks > 0 && blockno % extblocks == 0) {
        arma::mat test_act;
        if (kurt_size < n_samps) {
          arma::uvec kidx = r_randsamp(n_samps, kurt_size);
          test_act = x_t.cols(kidx).t() * W;
        } else {
          test_act = x * W;
        }

        arma::mat ta2 = test_act % test_act;
        arma::vec kurt = arma::mean(ta2 % ta2, 0).t() /
                         arma::square(arma::mean(ta2, 0).t()) - 3.0;

        if (extmomentum > 0.0) {
          kurt = extmomentum * old_kurt + (1.0 - extmomentum) * kurt;
          old_kurt = kurt;
        }

        arma::vec new_signs = arma::sign(kurt + signsbias);

        if (arma::all(new_signs == oldsigns)) {
          signcount++;
        } else {
          signcount = 0;
        }
        oldsigns = new_signs;
        signs    = new_signs;
        signs_r  = signs.t();

        if (signcount >= signcount_threshold) {
          extblocks = (int)(extblocks * signcount_step);
          signcount = 0;
        }
      }
      blockno++;
    }

    if (!blowup) {
      arma::mat wtchange = W - W_old;
      iter++;
      arma::vec delta = arma::vectorise(wtchange);
      double change = arma::dot(delta, delta);
      double angledelta = 0.0;

      if (iter > 2) {
        double cosval = arma::dot(delta, olddelta) /
                        std::sqrt(change * oldchange);
        cosval = std::max(-1.0, std::min(1.0, cosval));
        angledelta = degconst * std::acos(cosval);
      }

      W_old = W;

      if (verbose) {
        Rcpp::Rcout << "Step: " << iter
                    << ", lrate: " << lrate
                    << ", wchange: " << change
                    << ", angledelta: " << angledelta
                    << "\n";
      }

      if (angledelta > annealdeg) {
        lrate *= annealstep;
        olddelta = delta;
        oldchange = change;
      } else {
        if (iter == 1) {
          olddelta = delta;
          oldchange = change;
        }
        if (n_small_angle > 0) {
          count_small_angle++;
          if (count_small_angle > n_small_angle) {
            maxiter = iter;
          }
        }
      }

      if (iter > 2 && change < tol) {
        iter = maxiter;
      } else if (change > blowup_limit) {
        lrate *= blowup_fac;
      }

    } else {
      // Blowup: reset and lower learning rate
      iter = 0;
      blowup = false;
      blockno = 1;
      lrate *= restart_fac;
      if (verbose) {
        Rcpp::Rcout << "Weights blown up, lowering lrate to " << lrate << "\n";
      }
      W = W_start;
      W_old = W_start;
      olddelta = arma::zeros<arma::vec>(n_comps * n_comps);
      oldchange = 0.0;
      bias = arma::zeros<arma::vec>(n_comps);
      extblocks = 0;
      signs    = arma::ones<arma::vec>(n_comps);
      signs(0) = -1.0;
      signs_r  = signs.t();
      oldsigns = arma::zeros<arma::vec>(n_comps);
      old_kurt = arma::zeros<arma::vec>(n_comps);
      signcount = 0;
    }
  }

  return List::create(Named("weights") = W, Named("iter") = iter);
}
