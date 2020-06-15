#' ---
#' title: "src_bgcz.R"
#' author: "Dean Koch"
#' date: "June 15, 2020"
#' output: github_document
#' ---
#' 
#' 
#' Biogeoclimatic Zone (BGCZ) classification map from BC's Ministry of Forests. Runtime around ?? minutes 
#' 

#' This script follows the same template as 'src_dem.R'. For more detail, see comments in 'src_dem.knit.md'
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
collection = 'bgcz'
cfg = MPB_metadata(collection)
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))

#'
#' **source information**
#' 
#' We access an archived (2017) copy of Natural Resources Canada's (NRCan) Canadian Digital Elevation Map (Cbgcz; see the PDF overview
#' <a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cbgcz_mnec/doc/Cbgcz_en.pdf" target="_blank">here</a>, 
#' and more detailed documentation 
#' <a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cbgcz_mnec/doc/Cbgcz_product_specs.pdf" target="_blank">here</a>).
#' The web url below points to an
#' <a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cdem_mnec/" target="_blank">ftp directory</a>
#' containing the (zipped) DEM rasters at various resolutions. 
#' 
#' The <a href="https://open.canada.ca/en/open-government-licence-canada" target="_blank">Open Government Licence - Canada</a> applies.
#' 
#' The 3 (arc)second resolution in the archive is sufficient for our purposes, but users may wish to look at the higher (1 and 2 sec) 
#' resolution datasets available from the newer
#' <a href="https://open.canada.ca/data/en/dataset/957782bf-847c-4644-a757-e383c0057995" target="_blank">High Resolution</a> DEM. 
#' A useful directory of Canadian DEM products can be found
#' <a href="https://www.nrcan.gc.ca/science-and-data/science-and-research/earth-sciences/geography/topographic-information/download-directory-documentation/17215" target="_blank">here</a>. 

# define the source metadata
cfg.src = list(
  
  # url to download from
  web = 'https://www.for.gov.bc.ca/ftp/HRE/external/!publish/becmaps/GISdata/WithLandCover/BGCv11_WithLandcover.gdb.zip',
  
  # filename for the gdb geometry tables (actually a directory) 
  fname = c(gdb='BGCv11_WithLandcover.gdb'),
  
  # feature names to save (note ESRI driver used by GDAL has weird abbreviation behaviour)
  feat.name = c(region = 'REG_NAME',
                source = 'ORG_NAME', 
                cover = 'LAND_COVER_CLASS',
                zone = 'ZONE', 
                subzone = 'SUBZONE', 
                variant = 'VARIANT')
)

#+ results='hide'
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

#' After warping the elevation layer to the reference coordinate system, we will compute the derived quantities `slope` and `aspect`. 
#' We set up these output filenames before proceeding  

# set up the source and full-extent output filenames
varnames = setNames(nm=names(cfg$src$feat.name))
cfg$src$fname = c(bgcz=file.path(cfg$src$dir, cfg$src$fname))
cfg$out$fname$shp = c(bgcz=paste0(file.path(data.dir, cfg$out$name, collection), '_std.shp'))
cfg$out$fname$tif$full = setNames(file.path(data.dir, cfg$out$name, paste0(varnames, '_std.tif')), varnames)


#' **downloads**
#' 
#' The zip archive contains a geodatabase, which is represented on disk as a folder containing lots of 
#' crazy-looking user-unfriendly filenames (386.7 MB, or 567 MB uncompressed).
#' 
#' Once these files is downloaded/extracted, the script will use the existing ones instead of downloading it all again (unless
#' `force.download` is set to `TRUE`) 

#+ echo=FALSE
# check if we need to download it again:
if(!all(file.exists(cfg$src$fname)) | force.download)
{
  #+ eval=FALSE
  # download the zip to temporary file (386.7 MB), extract to disk
  bgcz.tmp = tempfile('bgcz_temp', cfg$src$dir, '.zip')
  download.file(url=cfg$src$web, destfile=bgcz.tmp, mode='wb')
  bgcz.paths = unzip(bgcz.tmp, exdir=cfg$src$dir)
  unlink(bgcz.tmp)
  
  #' verify that the extracted directory is the same as the one listed in `cfg$src$fname`
  all(cfg$src$fname %in% dirname(bgcz.paths))
  
} else {
 
  print('using existing source files:') 
  print(cfg$src$fname)
}

#'
#' **processing**
#' 
#' 

#+ results='hide'
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])

#' Start by loading the ESRI geodatabase (using `OpenFileGDB`), and writing a simplified copy to disk as shapefile (1.6 GB). This 
#' file should already be in our target projection, so the `sf::st_transform` call is probably redundant. There are several
#' hundred thousand multipolygons, so this may take a few minutes to complete 
#+ eval=FALSE 
# load BGCZ data, prepare to discard some extraneous fields
bgcz.sf = sf::st_read(cfg$src$fname)
bgcz.features.idx = names(bgcz.sf) %in% cfg.src$feat.name

# reproject to reference crs
bgcz.reproj.sf = sf::st_transform(bgcz.sf[,bgcz.features.idx], sf::st_crs(bc.mask.tif))

# rename attributes, write to disk
names(bgcz.reproj.sf) = c(names(cfg.src$feat.name), 'geometry')
sf::st_geometry(bgcz.reproj.sf) = 'geometry'
sf::st_write(bgcz.reproj.sf, cfg$out$fname$shp, append=FALSE)

#' Notice the feature columns are renamed to match `names(cfg.src$feat.name)`. **These names should be no longer than 10 characters**,
#' due to a limitation in the ESRI shapefile format. Confusingly, if *any* of the names exceed 10 characters,  GDAL abbreviates
#' *all* of them to 7 characters, which easily leads to bugs and errors (if these abbreviations are not unique). 
#' 

#' Next we rasterize each of the features listed in `cfg.src$feat.name`. The categorical (named) classifications are converted to
#' integer (to be compatible with the geotiff format), and we save the conversion table as a list in `cfg$out$code`
#+ eval=FALSE
# reload the shapefile to overwrite the large source database in memory
bgcz.sf = sf::st_read(cfg$out$fname$shp)

# save factor level codes with a sensible ordering
cfg$out$code = lapply(varnames, function(feat) sort(unique(unlist(sf::st_drop_geometry(bgcz.sf[, feat]))), na.last=FALSE))

# convert character columns to integer
# feature = 'region'
# x = unlist(st_drop_geometry(bgcz.sf[,feature]))
# match(x, cfg$out$code[[feature]])
# 
# x %in% cfg$out$code[[feature]]

#' There is probably a more direct way of doing this using a `factor` representation. Note that a recent upgrade to R (v4) now has different 
#' default behaviour for loading columns of categorical data (*eg.* previous versions of R would load columns of `bgcz.sf` as factors, not strings). 

# rasterize each feature layer and write to disk
# bgcz.tif = lapply(names(cfg.src$bgcz$feat.names), function(feat) raster::mask(fasterize::fasterize(bgcz.lcc.sf, bc.mask.tif, feat, 'last'), bc.mask.tif))
# for(idx in 1:length(cfg.src$bgcz$feat.names))
# {
#   # copy feature names to layer names
#   names(bgcz.tif[[idx]]) = names(cfg.src$bgcz$feat.names)[idx]
#   raster::writeRaster(bgcz.tif[[idx]], cfg.data$bgcz$path.out$tif[idx], overwrite=TRUE)
# }

# clean up
#rm(list=c('bgcz.sf', 'bgcz.reproj.sf', 'bgcz.tif'))


#' Finally, split these layers up into mapsheets corresponding to the NTS/SNRC codes (1.2 GB)
#+ eval=FALSE

# function call to crop and save blocks
#cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
#cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
#saveRDS(cfg, file=cfg.filename)

#' Metadata (including file paths) can now be loaded from 'bgcz.rds' located in `data.dir` using `readRDS()`.

#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src_bgcz.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('src_bgcz.R'))
