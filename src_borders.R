#' ---
#' title: "BC borders"
#' author: "Dean Koch"
#' date: "June 10, 2020"
#' output: github_document
#' ---
#' 
#' 
#' This is the initial setup script for reproducing the rasterbc dataset. 
#' It downloads some shapefiles to define boundaries, and sets up configuration details for GIS processing.
#' 


library(here)

source(here('utility_functions.R'))

# some more comment testing
# /* testin
# multiline
# g */ 

# here is a regular code comment, that will remain as such
summary(VADeaths)


#+ echo=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src/src_borders.R'), run_pandoc=FALSE, clean=TRUE)
# rmarkdown::render(here('src/src_borders.R'))