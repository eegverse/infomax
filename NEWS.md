# infomax (development version)

* Added validation for input matrices and core algorithm parameters.
* Fixed small-input block-size handling and silenced R-backend restart messages
  when `verbose = FALSE`.
* Added C++ backend (`ext_in_cpp()`) via RcppArmadillo for the core ICA iteration loop.
* `run_infomax()` gains a `backend` argument (`"r"` or `"cpp"`) to select the implementation.
* C++ backend is ~3.6× faster than the R backend on real EEG data (69 components × 54,416 samples).
* Fixed OpenMP configuration: `ARMA_DONT_USE_OPENMP` is set to prevent thread overhead from degrading performance on typical EEG matrix sizes.
* Improved weight blow-up recovery in both backends: non-finite updates are detected before kurtosis estimation, restarts are bounded, and extended-Infomax sign adaptation is restored after a restart.

# infomax 0.1.0

* Added a `NEWS.md` file to track changes to the package.
* Added basic tests.
