#include <RcppEigen.h>
using namespace Rcpp;

// [[Rcpp::export]]
SEXP eigenMapMatMult(const Eigen::Map<Eigen::MatrixXd> A, Eigen::Map<Eigen::MatrixXd> B){

  Eigen::MatrixXd C = A * B;

  return Rcpp::wrap(C);
}

// [[Rcpp::export]]
SEXP eigenMatMult(Eigen::MatrixXd A, Eigen::MatrixXd B){
  Eigen::MatrixXd C = A * B;

  return Rcpp::wrap(C);
}

// [[Rcpp::export]]
SEXP eigAddBis(const Eigen::Map<Eigen::MatrixXd> A,
               Eigen::Map<Eigen::MatrixXd> B,
               Eigen::Map<Eigen::MatrixXd> bias) {
  Eigen::MatrixXd C = A * B;
  C += bias;
  return Rcpp::wrap(C);
}
