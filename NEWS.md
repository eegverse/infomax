# infomax (development version)

* Fixed PCA dimensionality reduction so that the returned mixing and
  unmixing matrices map components back to the original feature (for example,
  electrode) space.
* Preserved input feature names on the rows of the returned mixing and
  unmixing matrices.
* Added validation for input data, PCA dimensions, minibatch size, and
  algorithm control parameters, with clearer errors for invalid values.
* Fixed convergence handling so that `iter` reports the actual number of
  completed iterations and small-angle convergence requires consecutive
  updates.
* Improved the numerical stability of the weight-change angle calculation.
* Added explicit support for disabling whitening with `whiten = "none"`.
* Expanded and stabilized the test suite, including sign- and
  permutation-invariant source recovery tests and coverage for PCA mapping,
  argument validation, convergence, and disabled whitening.

# infomax 0.1.0

* Added a `NEWS.md` file to track changes to the package.
* Added basic tests.
