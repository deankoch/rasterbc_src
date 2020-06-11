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
#' Note that the spatial reference system used here 
#' (<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a>)
#' is shared by both the 
#' <a href="https://cran.r-project.org/web/packages/bcmaps/index.html" target="_blank">bcmaps</a>
#' package and the
#' (<a href="http://hectaresBC.org" target="_blank">hectaresBC</a>) website,
#' so users can combine data from all three sources without fooling around with projection and alignment. 
#' 

library(here)

# some more comment testing
# /* testin
# multiline
# g */ 

# here is a regular code comment, that will remain as such
summary(VADeaths)


#+ echo=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src_borders.R'), output_file=here('src_borders.md'), run_pandoc=FALSE, clean=TRUE)
# rmarkdown::render(here('src_borders.R'))
       