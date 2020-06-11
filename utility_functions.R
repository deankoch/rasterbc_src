#' ---
#' title: "Utility functions"
#' author: "Dean Koch"
#' date: "June 10, 2020"
#' output: github_document
#' ---
#' 
#' 
#' This loads required packages, and defines some helper functions. It is sourced by
#' all of the individual \code{src_*()} downloading/pre-processing scripts. 
#' 

#' Required packages: make sure these are all installed
#' 
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


#+ echo=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('utility_functions.R'), run_pandoc=FALSE, clean=TRUE)
# rmarkdown::render(here('utility_functions.R'))