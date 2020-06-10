#' ---
#' title: "borders"
#' author: "Dean Koch"
#' date: "June 10, 2020"
#' output: github_document
#' ---
#'
#' This is the initial setup script for reproducing the rasterbc dataset. 
#' It downloads some shapefiles to define BC borders, sets up config for preprocessing.
#' 
#' The geographical projection system is set to match the one used in the `bcmaps` package (Albers NAD83, standard in BC). 
#' Resolution and extent are set to match hectaresBC.org and extents are defined for each individual output tile (10km x 10km mapsheet).
#' 
#' 
#' 





## here is a regular code comment, that will remain as such
summary(VADeaths)

#' Here's some more prose. I can use usual markdown syntax to make things
#' **bold** or *italics*. Let's use an example from the `dotchart()` help to
#' make a Cleveland dot plot from the `VADeaths` data. I even bother to name
#' this chunk, so the resulting PNG has a decent name.
#+ dotchart
dotchart(VADeaths, main = "Death Rates in Virginia - 1940")

#' ---
#' R script (markdown render-ready)
#' rmarkdown::render(here('src_borders.R'), run_pandoc=FALSE, clean=TRUE)
#' ---