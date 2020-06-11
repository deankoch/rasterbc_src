utility\_functions.R
================
Dean Koch
June 10, 2020

This loads required packages, sets up parameters, and defines some
helper functions. It is sourced at the beginning of all of the
individual downloading/pre-processing scripts.

**The following packages are required:**

``` r
# provides sensible guess for working directory
library(here)

# scraping
library(rvest)
library(RCurl)

# handling tifs, shapefiles
library(raster)
library(rgdal)
library(gdalUtils)
library(sf)
library(fasterize)

# plotting 
library(quickPlot)
library(ggplot2)

# parallel execution
library(doSNOW)
```

**important user-defined parameters**

``` r
# define/create a directory for storage of all downloaded source files and output files 
data.dir = here('data')
```

By default this is the subdirectory ‘data’ relative to the location of
the R project file (ie. …/rasterbc/data). Around 60GB of data in total
will be downloaded/written. Feel free to change this to another path
(eg. a drive with more free space), but be careful not to assign it to
to an existing directory as I do not check for existing files, so
*anything already in data.dir could get overwritten*.

``` r
#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
```

Rasterization requires around 6GB per core, so consider reducing this if
you are encountering out of memory errors
