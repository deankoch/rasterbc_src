# rasterbc_src
Provides easy access to gridded mountain pine beetle (MPB) datasets in British Columbia (BC) in the period 2001-2018

A number of datasets relevant to MPB ecology are publicly available online from various environment ministries, but acquiring them can be cumbersome. Large filesizes, differing projections and data-structures, and arcane file formats can be big challenges for the novice GIS user. This project aims to make these datasets more accessible to the scientific community, by taking care of the heavy lifting in GIS, and transforming them to a common gridded (raster) reference system more amenable to large-scale data-driven analyses in R. A convenient R-based distribution system for this raster data allows ecologists and modellers to more quickly and easily get involved in MPB research.

The data product prepared here consolidates 8 source datasets relevant to modelers interested in the spatial ecology of the MPB, and other forest health factors in BC. Note that these source data are *not* collected by us; We simply have simply repackaged a set publicly available collections to make it easier for the ecological/modelling research community to access and use them. Users will find links to the source webpages and catalogue entries -- along with attributions and licensing details -- in the 8 individual R scripts (src_\*.R), and their associated markdown webpages (src_\*.knit.md).  

This project has two parts: 

1. This repository (rasterbc_src) contains all of the code necessary to reproduce our database of geotiff layers. A set of 8 R scripts are provided, each of which: downloads a different public data collection, extracts the contents and pulls relevant attributes, corrects any invalid geometries, reprojects and/or warps the source data (as needed) to match our reference grid, and writes the output to disk. At the end of each script, the (large) output rasters are split into 89 blocks, corresponding to the NTS/SNRC mapsheets covering the BC landmass, so that they can be more easily loaded, distributed and processed. A permanent copy of both the full extent and smaller block size rasters are hosted for public access on FRDR, where they will remain unchanged and referenced by a DOI. 

2. A sister repository (rasterbc) offers an R package that automates the process of downloading and importing these data into R. Users simply specify a geographical area of interest (within the province of BC), and the variables of interest, and rasterbc automatically retrieves the necessary (block) layers from FRDR, merging them (as needed), and returning them to the user as `raster::RasterLayer` objects. 

Note that the spatial reference system used here 
(<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a>)
is shared by both the 
<a href="https://cran.r-project.org/web/packages/bcmaps/index.html" target="_blank">bcmaps</a>
package and the
(<a href="http://hectaresBC.org" target="_blank">hectaresBC</a>) website,
so users can combine data from all three sources without fussing with projections and alignment. 

As much as possible, I have tried to use the (more modern) `sf` package in lieu of the (more widely used) `sp` package. Both are great, but
`sf` seems more future-proof, and more efficiently coded for a lot of this GIS work. Regrettably, I wound up with a mixture of function calls 
to both packages, in part because some important features are still unavailable in `sf`, and also because some of the data collections are in
"legacy" file formats more easily dealt with by `sp`. Note that GDAL (and its dependents `rgdal`, `sp`, `sf`, `raster`) are in the middle of a 
<a href="https://www.r-spatial.org/r/2020/03/17/wkt.html" target="_blank">PROJ6/GDAL3 transition</a>,
so quite often you will see a warning when opening a source file containing older PROJ representations of the coordinate reference 
system, or when writing raster files using `raster::writeRaster()`. More on this 
<a href="http://rgdal.r-forge.r-project.org/articles/PROJ6_GDAL3.html" target="_blank">here</a>,

 
