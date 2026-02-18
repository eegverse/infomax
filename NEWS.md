# infomax (development version)

* Added C++ backend (`ext_in_cpp()`) via RcppArmadillo for the core ICA iteration loop.
* `run_infomax()` gains a `backend` argument (`"r"` or `"cpp"`) to select the implementation.
* C++ backend is ~3.6× faster than the R backend on real EEG data (69 components × 54,416 samples).
* Fixed OpenMP configuration: `ARMA_DONT_USE_OPENMP` is set to prevent thread overhead from degrading performance on typical EEG matrix sizes.

# infomax 0.1.0

* Added a `NEWS.md` file to track changes to the package.
* Added basic tests.
