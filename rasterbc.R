#' ---
#' title: "rasterbc.R"
#' author: "Dean Koch"
#' date: "June 19, 2020"
#' output: github_document
#' ---
#' 
#' **Development version**: testing R code for fetching/caching/loading mapsheets

#' Some preamble - I will need to organize this kind of data loading stuff into a function or RData data file for the package
#+ results='hide'

# set the data directory and load helper functions
library(here)
source('utility_functions.R')

# load the NTS/SNRC mapsheets
blocks.sf = loadblocks_bc()
blocks.codes = findblocks_bc()

#' To demonstrate this package we'll need a polygon covering a (relatively) small geographical extent in BC. 
#' Start by loading the `bcmaps` package and grabbing the polygons for the BC provincial boundary and the 
#' Central Okanagan Regional District
example.name = 'Regional District of Central Okanagan'
library(bcmaps)
bc.bound.sf = bc_bound()
districts.sf = regional_districts()
example.sf = districts.sf[districts.sf$ADMIN_AREA_NAME==example.name, ]

#' Now have a look at where the selected district lies in the province, with reference to the NTS/SNRC grid.
#' We use `st_geometry` to drop the feature columns from the `sf` objects and keep only the geometries, which helps to de-clutter
#' plots whenever we're just interested in the location(s) of something, and not the attributes attached to those locations.
plot(st_geometry(blocks.sf), main=example.name, border='red')
plot(st_geometry(bc.bound.sf), add=TRUE, col=adjustcolor('blue', alpha.f=0.2))
plot(st_geometry(example.sf), add=TRUE, col=adjustcolor('yellow', alpha.f=0.5))
#'  The `add=TRUE` argument tells `plot` to overlay the new shape(s) onto our initial plot (the NTS/SNRC grid in red), and
#' the `border` and `col` arguments specify the outline and fill colours, respectively. 
#' 
#' The base function `adjustcolor` is a very handy one-liner for making opaque colours transparent, *eg.* here it makes the NTS/SNRC grid 
#' lines visible after overlaying the (filled) BC polygon.
#' 
#' Looking closely, `example.sf` (in yellow) overlaps with three different NTS/SNRC mapsheet blocks. To fetch all of the raster data corresponding to
#' this polygon, we will need to download three files with the appropriate mapsheet codes. These 4-character codes can be added as annotations on this plot
#' by a simple `text` call, where `st_coordinates(st_centroid(st_geometry(blocks.sf)))` returns a matrix of coordinates. 
plot(st_geometry(blocks.sf), main=example.name, border='red')
plot(st_geometry(bc.bound.sf), add=TRUE, col=adjustcolor('blue', alpha.f=0.2))
plot(st_geometry(example.sf), add=TRUE, col=adjustcolor('yellow', alpha.f=0.5))
text(st_coordinates(st_centroid(st_geometry(blocks.sf))), labels=blocks.codes, cex=0.5)

#' We see that the required mapsheets are coded as: `O92H`, `O82E`, and `O82L`. The `rasterbc::findblocks_bc` function finds the codes automatically:
example.codes = findblocks_bc(example.sf)
print(example.codes)

#' `metadata_bc()` returns the list that contains the filenames associated with these blocks, *eg.* for the elevation (`dem`) layer we have the 
#' following three rasters:
cfg = metadata_bc()
collection = 'dem'
varname = 'dem'
example.filenames = cfg[[collection]]$out$fname$tif$block[[varname]][example.codes]
print(example.filenames) 

#' These can be merged together into a larger block that covers the `example.sf` polygon:
# merge the blocks using an external (GDAL) mosaic call, via tempfile
example.tempfile = paste0(tempfile(), '.tif')
gdalUtils::mosaic_rasters(example.filenames, dst_dataset=example.tempfile)

# load the output, assign min/max stats and variable name
example.tif = setMinMax(raster::raster(example.tempfile))
names(example.tif) = varname

# plot the result
plot(example.tif, main=paste0(example.name, '\nDigital Elevation Model'), colNA='black')
plot(st_geometry(example.sf), add=TRUE)
plot(st_geometry(blocks.sf), add=TRUE, border='red')
text(st_coordinates(st_centroid(st_geometry(blocks.sf))), labels=blocks.codes, cex=0.5)

#' From here it is straightforward to crop or clip the layer to the boundary of the polygon:
 
# create a cropped version, plot the result
example.cropped.tif = raster::crop(example.tif, example.sf)
plot(example.cropped.tif, main=paste0(example.name, '\nDigital Elevation Model'), colNA='black')
plot(st_geometry(example.sf), add=TRUE)

# create a clipped version, plot the result
example.clipped.tif = raster::mask(example.cropped.tif, example.sf)
plot(example.clipped.tif, main=paste0(example.name, '\nDigital Elevation Model'), colNA='black')
plot(st_geometry(example.sf), add=TRUE)


#' Cropping or clipping to the region of interest is very easy with the `raster` package:
#' 




#' When downloading a layer, you have the option of requesting the full BC extent, or supplying a polygon (sf object) that specifies 
#' a smaller geographical extent. eg. to get the elevation data for the example district, use this command
#' 





#' 
# # load the borders info and shapefiles for mapsheets
# cfg.borders = readRDS(here('data', 'borders.rds'))
# blocks.sf = sf::st_read(cfg.borders$out$fname$shp['blocks'])
# blocks.codes = cfg.borders$out$code
# 
# # create the source data directory, metadata list and its path on disk
# collection = 'fids'
# 
#
# 


#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('rasterbc.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('rasterbc.R'))
