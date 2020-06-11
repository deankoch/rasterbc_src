Utility functions
================
Dean Koch
June 10, 2020

This loads required packages, and defines some helper functions. It is
sourced by all of the individual  downloading/pre-processing scripts.

Required packages: make sure these are all installed

``` r
# sensible guess for working directory
library(here)

# packages for scraping
library(rvest)
library(RCurl)

# handle tifs, shapefiles
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
