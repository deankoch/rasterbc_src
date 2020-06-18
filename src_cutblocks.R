#' ---
#' title: "src_cutblocks.R"
#' author: "Dean Koch"
#' date: "June 16, 2020"
#' output: github_document
#' ---
#' 
#' Reported harvest cutblocks and photo-interpreted disturbance 
#' locations attributed to harvest on crown lands, in the years 2001-2018. 
#' From the BC Ministry of Forests, Lands, Natural Resource Operations and Rural Development. 
#' 

#' 
#+ results='hide'
# download again to rewrite existing files? 
force.download = FALSE

# load the helper functions
library(here)
source(here('utility_functions.R'))

# load the borders info and shapefiles for mapsheets
cfg.borders = readRDS(here('data', 'borders.rds'))
snrc.sf = sf::st_read(cfg.borders$out$fname$shp['snrc'])
snrc.codes = cfg.borders$out$code

# create the source data directory, metadata list and its path on disk
collection = 'cutblocks'
cfg = MPB_metadata(collection)
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))

#'
#' **source information**
#' 
#' This collection consolidates data from: the Reporting Silviculture Updates and Land Status Tracking System 
#' (<a href="https://www2.gov.bc.ca/gov/content/industry/forestry/managing-our-forest-resources/silviculture/silviculture-reporting-results" target="_blank">RESULTS</a>); 
#' photo-interpretation records from the 
#' <a href="https://www2.gov.bc.ca/gov/content/industry/forestry/managing-our-forest-resources/forest-inventory/forest-cover-inventories" target="_blank">Vegetation Resources Inventory</a>
#' (VRI); and Landsat forest cover change detection; Spanning the years 2001-2018.
#' 
#' Some metadata is available in the
#' <a href="https://catalogue.data.gov.bc.ca/dataset/harvested-areas-of-bc-consolidated-cutblocks-" target="_blank">BC Data Catalogue</a>
#' and a more complete documentation can be found in the 
#' <a href="https://www.for.gov.bc.ca/ftp/HTS/external/!publish/consolidated_cutblocks/About%20Consolidated%20Cut%20Blocks%202020.pdf" target="_blank">linked PDF</a>.
#' Note that these harvest data cover crown land only, and, for years prior to 2012 may include reserve areas not harvested.
#' 
#' The cutblocks source data have an
#' <a href="https://www2.gov.bc.ca/gov/content/home/copyright">Access only</a> license. This script
#' modifies them by rasterizing to our reference grid and splitting them by year and by NTS/SNRC block. 
#' 
# define the source metadata
cfg.src = list(
  
  # url for the zip archive
  web = 'https://www.for.gov.bc.ca/ftp/HTS/external/!publish/consolidated_cutblocks/Consolidated_Cutblocks.zip',
  
  # filename for the gdb geometry table (actually a directory) 
  fname = c(gdb='Consolidated_Cutblocks.gdb'),
  
  # feature names to save (note ESRI driver used by GDAL has weird abbreviation behaviour)
  feat.name = c(harvest = 'Harvest_Year'),
  
  # character vectors naming the years to extract from lossyear
  years = setNames(2001:2018, nm=paste0('yr', 2001:2018))
)

#+ results='hide'
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

# set up the source and full-extent output filenames
cfg$src$fname = c(harvest=file.path(cfg$src$dir, cfg$src$fname))
cfg$out$fname$shp = c(harvest=paste0(file.path(data.dir, cfg$out$name, collection), '_std.shp'))
cfg$out$fname$tif$full = lapply(cfg$src$years, function(year) c(harvest=file.path(data.dir, cfg$out$name, year, paste0('cutblocks_std_', year, '.tif'))))

#' **downloads**
#' 
#' The zip archive contains a geodatabase (386.7 MB, or 567 MB uncompressed), which will be exported to ESRI shapefile.
#' Once these files are downloaded/extracted, the script will use the existing ones instead of downloading it all again (unless
#' `force.download` is set to `TRUE`) 

#+ eval=FALSE
# check if any of the rasters need to be downloaded again:
idx.todownload = sapply(unlist(cfg$src$fname), function(fname) ifelse(force.download, TRUE, !file.exists(fname)))
if(any(idx.todownload))
{
  # download the zip to temporary file (386.7 MB), extract to disk
  cutblocks.tmp = tempfile('cutblocks_temp', cfg$src$dir, '.zip')
  download.file(url=cfg$src$web, destfile=cutblocks.tmp, mode='wb')
  cutblocks.paths = unzip(cutblocks.tmp, exdir=cfg$src$dir)
  unlink(cutblocks.tmp) 
    
} else {
 
  print('using existing source files:') 
  print(cfg$src$fname)
}

#'
#' **processing**
#' 

#+ eval=FALSE
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])

# load gdb (slow), make sure we are in the correct projection 
cutblocks.sf = sf::st_transform(sf::st_read(cfg$src$fname), sf::st_crs(bc.mask.tif))

# omit all but harvest attribute and selected years, rename columns
idx.cutblocks = unlist(st_drop_geometry(cutblocks.sf[, cfg$src$feat.name])) %in% cfg$src$years
cutblocks.sf = cutblocks.sf[idx.cutblocks, cfg$src$feat.name] 
names(cutblocks.sf) = c(names(cfg.src$feat.name), 'geometry')
sf::st_geometry(cutblocks.sf) = 'geometry'

# write shapefile to disk (1.58 GB), reload
sf::st_write(cutblocks.sf, cfg$out$fname$shp, append=FALSE)
cutblocks.sf = sf::st_read(cfg$out$fname$shp)

#' We saved a copy of the dataset as shapefile (for easier handling in R), retaining only the harvest year column
#' to keep file sizes down (1.58 GB). Next we rasterize the contents, producing a (binary) layer in each year indicating 
#' harvest activity (total size 227 MB). Expect this to take around 10-15 minutes
#'
#'
#+ eval=FALSE
# construct a base layer of 0's and NAs
base.tif = raster::mask(bc.mask.tif, bc.mask.tif, maskvalue=1, updatevalue=0)

# loop to rasterize years individually
pb = txtProgressBar(min=1, max=length(cfg$src$years), style=3)
for(idx.year in 1:length(cfg$src$years))
{
  # define polygons to rasterize
  setTxtProgressBar(pb, idx.year)
  year = cfg$src$years[idx.year]
  idx.towrite = unlist(sf::st_drop_geometry(cutblocks.sf)) == year 

  # rasterize, apply provincial borders mask, then write to disk
  temp.tif = fasterize::fasterize(cutblocks.sf[idx.towrite,], bc.mask.tif, field=names(cfg$src$feat.name), fun='any')
  temp.tif = raster::mask(base.tif, temp.tif, updatevalue=1, inverse=TRUE)
  raster::writeRaster(temp.tif, cfg$out$fname$tif$full[[idx.year]], overwrite=TRUE)
  rm(temp.tif)
}
close(pb)

#' Finally, we split all layers up into mapsheets corresponding to the NTS/SNRC codes (367 MB total). Expect this to take around 10 minutes
#+ eval=FALSE

# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)

#' Metadata (including file paths) can now be loaded from 'cutblocks.rds' located in `data.dir` using `readRDS()`.

#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src_cutblocks.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('src_cutblocks.R'))
