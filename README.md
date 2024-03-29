
<!-- README.md is generated from README.Rmd. Please edit that file -->

# infomax

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://www.tidyverse.org/lifecycle/#experimental)

[![R-CMD-check](https://github.com/craddm/infomax/workflows/R-CMD-check/badge.svg)](https://github.com/craddm/infomax/actions)

[![codecov](https://codecov.io/gh/craddm/infomax/branch/master/graph/badge.svg?token=8VYL66NE7Z)](https://codecov.io/gh/craddm/infomax)
<!-- badges: end -->

The `infomax` package is an R implementation of the Infomax and Extended
Infomax algorithms (Bell & Sejnowski, 1995; Makeig, Bell, Jung, &
Sejnowski, 1996) for Independent Component Analysis.

## Installation

The package is not currently released on
[CRAN](https://CRAN.R-project.org).

You can install the development version from
[GitHub](https://github.com/) with:

``` r
# install.packages("remotes")
remotes::install_github("eegverse/infomax")
```

## Example

``` r
library(infomax)
## basic example code
```

ICA can be used to separate linear mixtures of different, independent
signal sources.

In the example below, we generate two independent signals and then mix
them together.

``` r
time_x <- seq(0, 1, by = 1/256)
source_a <- sin(2 * pi * 5 * time_x)
source_b <- sin(2 * pi * 10 * time_x)
plot(time_x, source_a, type = "l")
```

<img src="man/figures/README-unnamed-chunk-2-1.png" width="100%" />

``` r
plot(time_x, source_b, type = "l")
```

<img src="man/figures/README-unnamed-chunk-2-2.png" width="100%" />

``` r
plot(time_x, source_a + 2 * source_b, type = "l")
```

<img src="man/figures/README-unnamed-chunk-2-3.png" width="100%" />

``` r
plot(time_x, source_a * 3.4 + 1.5 * source_b, type = "l")
```

<img src="man/figures/README-unnamed-chunk-2-4.png" width="100%" />

The function returns the estimated mixing matrix, unmixing matrix, and
unmixed source timecourses.

``` r
mixed_data <- matrix(NA,
                     nrow = length(time_x),
                     ncol = 2)
mixed_data[, 1] <- source_a + 2 * source_b
mixed_data[, 2] <- source_a * 3.4 + 1.5 * source_b
dat_out <- run_infomax(mixed_data, whiten = "PCA")
#> Step: 1, lrate: 0.007213, wchange: 0.28490205, angledelta:  0.0
#> Step: 2, lrate: 0.007213, wchange: 0.19372638, angledelta:  0.0
#> Step: 3, lrate: 0.007213, wchange: 0.06888960, angledelta: 57.2
#> Step: 4, lrate: 0.007213, wchange: 0.01313297, angledelta: 110.8
#> Step: 5, lrate: 0.007069, wchange: 0.00574232, angledelta: 77.0
#> Step: 6, lrate: 0.006928, wchange: 0.00548345, angledelta: 123.5
#> Step: 7, lrate: 0.006789, wchange: 0.00702279, angledelta: 49.7
#> Step: 8, lrate: 0.006789, wchange: 0.01773996, angledelta: 107.8
#> Step: 9, lrate: 0.006653, wchange: 0.00209702, angledelta: 153.3
#> Step: 10, lrate: 0.006520, wchange: 0.00693405, angledelta: 59.9
#> Step: 11, lrate: 0.006520, wchange: 0.00798864, angledelta: 98.5
#> Step: 12, lrate: 0.006390, wchange: 0.01428885, angledelta: 108.8
#> Step: 13, lrate: 0.006262, wchange: 0.01934073, angledelta: 139.2
#> Step: 14, lrate: 0.006137, wchange: 0.00502298, angledelta: 19.1
#> Step: 15, lrate: 0.006137, wchange: 0.00600605, angledelta: 142.0
#> Step: 16, lrate: 0.006014, wchange: 0.00174998, angledelta: 104.8
#> Step: 17, lrate: 0.005894, wchange: 0.00060647, angledelta: 158.0
#> Step: 18, lrate: 0.005776, wchange: 0.01723064, angledelta: 91.6
#> Step: 19, lrate: 0.005661, wchange: 0.00226964, angledelta: 141.5
#> Step: 20, lrate: 0.005547, wchange: 0.00759579, angledelta: 69.5
#> Step: 21, lrate: 0.005436, wchange: 0.00345549, angledelta: 76.0
#> Step: 22, lrate: 0.005328, wchange: 0.00246479, angledelta: 136.2
#> Step: 23, lrate: 0.005221, wchange: 0.00050635, angledelta: 46.3
#> Step: 24, lrate: 0.005221, wchange: 0.00660329, angledelta: 67.7
#> Step: 25, lrate: 0.005117, wchange: 0.01255634, angledelta: 137.9
#> Step: 26, lrate: 0.005014, wchange: 0.02255722, angledelta: 111.9
#> Step: 27, lrate: 0.004914, wchange: 0.02261153, angledelta: 132.0
#> Step: 28, lrate: 0.004816, wchange: 0.01751547, angledelta: 139.9
#> Step: 29, lrate: 0.004719, wchange: 0.00863023, angledelta: 66.3
#> Step: 30, lrate: 0.004625, wchange: 0.00616765, angledelta: 155.2
#> Step: 31, lrate: 0.004533, wchange: 0.00872553, angledelta: 10.6
#> Step: 32, lrate: 0.004533, wchange: 0.00936136, angledelta: 162.8
#> Step: 33, lrate: 0.004442, wchange: 0.00282772, angledelta: 83.9
#> Step: 34, lrate: 0.004353, wchange: 0.02376058, angledelta: 133.8
#> Step: 35, lrate: 0.004266, wchange: 0.01080905, angledelta: 150.6
#> Step: 36, lrate: 0.004181, wchange: 0.00783784, angledelta: 123.3
#> Step: 37, lrate: 0.004097, wchange: 0.00633128, angledelta: 147.0
#> Step: 38, lrate: 0.004015, wchange: 0.00671098, angledelta: 163.2
#> Step: 39, lrate: 0.003935, wchange: 0.00336665, angledelta: 138.5
#> Step: 40, lrate: 0.003856, wchange: 0.00502550, angledelta: 103.8
#> Step: 41, lrate: 0.003779, wchange: 0.00220277, angledelta: 137.1
#> Step: 42, lrate: 0.003703, wchange: 0.00158227, angledelta: 131.9
#> Step: 43, lrate: 0.003629, wchange: 0.00279609, angledelta: 145.9
#> Step: 44, lrate: 0.003557, wchange: 0.00688606, angledelta: 131.3
#> Step: 45, lrate: 0.003486, wchange: 0.00680703, angledelta: 173.0
#> Step: 46, lrate: 0.003416, wchange: 0.00250783, angledelta: 168.6
#> Step: 47, lrate: 0.003348, wchange: 0.00039759, angledelta: 168.2
#> Step: 48, lrate: 0.003281, wchange: 0.00013156, angledelta: 58.4
#> Step: 49, lrate: 0.003281, wchange: 0.00042586, angledelta: 121.1
#> Step: 50, lrate: 0.003215, wchange: 0.00281717, angledelta: 118.8
#> Step: 51, lrate: 0.003151, wchange: 0.00585233, angledelta: 168.1
#> Step: 52, lrate: 0.003088, wchange: 0.00024821, angledelta: 57.4
#> Step: 53, lrate: 0.003088, wchange: 0.00305397, angledelta: 134.4
#> Step: 54, lrate: 0.003026, wchange: 0.00298151, angledelta: 95.4
#> Step: 55, lrate: 0.002965, wchange: 0.00678104, angledelta: 156.3
#> Step: 56, lrate: 0.002906, wchange: 0.00219808, angledelta: 152.6
#> Step: 57, lrate: 0.002848, wchange: 0.00068130, angledelta: 77.9
#> Step: 58, lrate: 0.002791, wchange: 0.00112608, angledelta: 50.1
#> Step: 59, lrate: 0.002791, wchange: 0.00036177, angledelta: 49.0
#> Step: 60, lrate: 0.002791, wchange: 0.00174587, angledelta: 153.1
#> Step: 61, lrate: 0.002735, wchange: 0.00090990, angledelta: 56.7
#> Step: 62, lrate: 0.002735, wchange: 0.00108477, angledelta: 77.0
#> Step: 63, lrate: 0.002681, wchange: 0.00004078, angledelta: 81.2
#> Step: 64, lrate: 0.002627, wchange: 0.00272043, angledelta: 101.1
#> Step: 65, lrate: 0.002574, wchange: 0.00125290, angledelta: 128.3
#> Step: 66, lrate: 0.002523, wchange: 0.00020079, angledelta: 88.9
#> Step: 67, lrate: 0.002472, wchange: 0.00041261, angledelta: 86.3
#> Step: 68, lrate: 0.002423, wchange: 0.00087700, angledelta: 174.5
#> Step: 69, lrate: 0.002375, wchange: 0.00064767, angledelta: 114.0
#> Step: 70, lrate: 0.002327, wchange: 0.00079537, angledelta: 148.3
#> Step: 71, lrate: 0.002281, wchange: 0.00003013, angledelta: 24.5
#> Step: 72, lrate: 0.002281, wchange: 0.00012213, angledelta: 94.1
#> Step: 73, lrate: 0.002235, wchange: 0.00017055, angledelta: 132.2
#> Step: 74, lrate: 0.002190, wchange: 0.00246607, angledelta: 92.3
#> Step: 75, lrate: 0.002146, wchange: 0.00151409, angledelta: 145.6
#> Step: 76, lrate: 0.002103, wchange: 0.00031788, angledelta: 148.0
#> Step: 77, lrate: 0.002061, wchange: 0.00108846, angledelta: 99.2
#> Step: 78, lrate: 0.002020, wchange: 0.00040767, angledelta: 47.3
#> Step: 79, lrate: 0.002020, wchange: 0.00062909, angledelta: 145.7
#> Step: 80, lrate: 0.001980, wchange: 0.00013104, angledelta: 65.6
#> Step: 81, lrate: 0.001940, wchange: 0.00000327, angledelta: 75.0
#> Step: 82, lrate: 0.001901, wchange: 0.00015313, angledelta: 55.4
#> Step: 83, lrate: 0.001901, wchange: 0.00149364, angledelta: 74.7
#> Step: 84, lrate: 0.001863, wchange: 0.00305039, angledelta: 121.8
#> Step: 85, lrate: 0.001826, wchange: 0.00077491, angledelta: 121.1
#> Step: 86, lrate: 0.001790, wchange: 0.00093906, angledelta: 125.5
#> Step: 87, lrate: 0.001754, wchange: 0.00018180, angledelta: 93.3
#> Step: 88, lrate: 0.001719, wchange: 0.00015410, angledelta: 42.5
#> Step: 89, lrate: 0.001719, wchange: 0.00009494, angledelta: 99.1
#> Step: 90, lrate: 0.001684, wchange: 0.00041558, angledelta: 25.6
#> Step: 91, lrate: 0.001684, wchange: 0.00051778, angledelta: 102.8
#> Step: 92, lrate: 0.001651, wchange: 0.00081025, angledelta: 81.0
#> Step: 93, lrate: 0.001618, wchange: 0.00109604, angledelta: 161.1
#> Step: 94, lrate: 0.001585, wchange: 0.00057895, angledelta: 175.3
#> Step: 95, lrate: 0.001554, wchange: 0.00013129, angledelta: 164.4
#> Step: 96, lrate: 0.001522, wchange: 0.00060014, angledelta: 126.4
#> Step: 97, lrate: 0.001492, wchange: 0.00009162, angledelta: 158.5
#> Step: 98, lrate: 0.001462, wchange: 0.00011620, angledelta: 68.0
#> Step: 99, lrate: 0.001433, wchange: 0.00037434, angledelta: 125.7
#> Step: 100, lrate: 0.001404, wchange: 0.00050255, angledelta: 105.9
#> Step: 101, lrate: 0.001376, wchange: 0.00001011, angledelta: 106.9
#> Step: 102, lrate: 0.001349, wchange: 0.00012580, angledelta: 162.5
#> Step: 103, lrate: 0.001322, wchange: 0.00002849, angledelta: 112.5
#> Step: 104, lrate: 0.001295, wchange: 0.00011231, angledelta: 61.4
#> Step: 105, lrate: 0.001269, wchange: 0.00003048, angledelta: 154.4
#> Step: 106, lrate: 0.001244, wchange: 0.00003842, angledelta: 84.5
#> Step: 107, lrate: 0.001219, wchange: 0.00022530, angledelta: 138.7
#> Step: 108, lrate: 0.001195, wchange: 0.00031276, angledelta: 37.0
#> Step: 109, lrate: 0.001195, wchange: 0.00015811, angledelta: 148.2
#> Step: 110, lrate: 0.001171, wchange: 0.00005842, angledelta: 94.8
#> Step: 111, lrate: 0.001147, wchange: 0.00001251, angledelta: 71.4
#> Step: 112, lrate: 0.001124, wchange: 0.00001967, angledelta: 134.4
#> Step: 113, lrate: 0.001102, wchange: 0.00010144, angledelta: 87.5
#> Step: 114, lrate: 0.001080, wchange: 0.00016130, angledelta: 86.7
#> Step: 115, lrate: 0.001058, wchange: 0.00017447, angledelta: 143.9
#> Step: 116, lrate: 0.001037, wchange: 0.00012742, angledelta: 126.1
#> Step: 117, lrate: 0.001016, wchange: 0.00005223, angledelta: 128.7
#> Step: 118, lrate: 0.000996, wchange: 0.00023688, angledelta: 106.6
#> Step: 119, lrate: 0.000976, wchange: 0.00002937, angledelta: 97.4
#> Step: 120, lrate: 0.000957, wchange: 0.00018728, angledelta: 170.5
#> Step: 121, lrate: 0.000938, wchange: 0.00005520, angledelta: 158.4
#> Step: 122, lrate: 0.000919, wchange: 0.00000947, angledelta: 126.7
#> Step: 123, lrate: 0.000900, wchange: 0.00003605, angledelta: 80.6
#> Step: 124, lrate: 0.000882, wchange: 0.00002980, angledelta: 120.0
#> Step: 125, lrate: 0.000865, wchange: 0.00001249, angledelta: 89.1
#> Step: 126, lrate: 0.000847, wchange: 0.00001080, angledelta: 155.9
#> Step: 127, lrate: 0.000830, wchange: 0.00006515, angledelta: 97.0
#> Step: 128, lrate: 0.000814, wchange: 0.00006241, angledelta: 101.0
#> Step: 129, lrate: 0.000798, wchange: 0.00004524, angledelta: 53.8
#> Step: 130, lrate: 0.000798, wchange: 0.00002732, angledelta: 132.1
#> Step: 131, lrate: 0.000782, wchange: 0.00004272, angledelta: 141.7
#> Step: 132, lrate: 0.000766, wchange: 0.00004027, angledelta: 142.4
#> Step: 133, lrate: 0.000751, wchange: 0.00001677, angledelta: 105.1
#> Step: 134, lrate: 0.000736, wchange: 0.00007619, angledelta: 69.0
#> Step: 135, lrate: 0.000721, wchange: 0.00002384, angledelta: 116.2
#> Step: 136, lrate: 0.000707, wchange: 0.00005678, angledelta: 16.6
#> ICA running time: 0.07 s
plot(time_x,
     dat_out$S[,1],
     type = "l")
```

<img src="man/figures/README-unnamed-chunk-3-1.png" width="100%" />

``` r
plot(time_x,
     dat_out$S[,2],
     type = "l")
```

<img src="man/figures/README-unnamed-chunk-3-2.png" width="100%" />

## References

-   Bell, A.J., & Sejnowski, T.J. (1995). An information-maximization
    approach to blind separation and blind deconvolution. *Neural
    Computation, 7,* 1129-159
-   Makeig, S., Bell, A.J., Jung, T-P and Sejnowski, T.J., “Independent
    component analysis of electroencephalographic data,” In: D.
    Touretzky, M. Mozer and M. Hasselmo (Eds). Advances in Neural
    Information Processing Systems 8:145-151, MIT Press, Cambridge, MA
    (1996).
