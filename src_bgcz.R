#' ---
#' title: "src_bgcz.R"
#' author: "Dean Koch"
#' date: "June 15, 2020"
#' output: github_document
#' ---
#' 
#' 
#' Biogeoclimatic Zone (BGCZ) classification (version 11, August 10th, 2018) from the BC Ministry of Forests. Runtime around 10 minutes 
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
#' The BC Ministry of Forest's
#' <a href="https://www.for.gov.bc.ca/hre/becweb/" target="_blank">Biogeoclimatic Ecosystem Classification (BEC)</a> 
#' system categorizes BC forestland based on a number of criteria. This script collects the climatic (zonal) classification,
#' which identifies areas of (relatively) uniform climate as polygons, based on vegetation, soils, and topography. The
#' database is updated periodically; This version (v11) is current as of June, 2020.  
#' 
#' There are  16 zones, each one named after its geographical/climatic characteristics and/or climax species (see
#' <a href="https://www.for.gov.bc.ca/hfd/library/documents/treebook/biogeo/biogeo.htm" target="_blank">here</a>
#' for brochures on 14 of them). Zones are divided into subzones based on precipitation and temperature or continentality 
#' (see <a href="https://www.for.gov.bc.ca/hre/becweb/system/how/index.html#naming_bec_units" target="_blank">here</a>
#' for an overview of subzone codes); and these are further subdivided into five possible variants based on specifics of
#' soil and vegetation. In addition, we have simpler feature sets indicating the landcover type (water, ice, land), region (general
#' place name) and organizational region (a more specific place name).
#' 
#' A more detailed description of these labels can be found on the 
#' <a href="https://catalogue.data.gov.bc.ca/dataset/f358a53b-ffde-4830-a325-a5a03ff672c3" target="_blank">BC Data Catalogue Metadata page</a>,
#' and a table of full text descriptions for each subzone and variant can be found in the (xlsx) spreadsheet
#' <a href="https://www.for.gov.bc.ca/ftp/HRE/external/!publish/becmaps/GISdata/BGC_BC_v11_HectareSummary.xlsx" target="_blank">linked here</a>.
#' 
#' The <a href="https://www2.gov.bc.ca/gov/content/data/open-data/open-government-licence-bc" target="_blank">Open Government Licence - British Columbia</a> applies.
#' 
#' 
# define the source metadata
cfg.src = list(
  
  # url to download from
  web = 'https://www.for.gov.bc.ca/ftp/HRE/external/!publish/becmaps/GISdata/WithLandCover/BGCv11_WithLandcover.gdb.zip',
  
  # filename for the gdb geometry tables (actually a directory) 
  fname = c(gdb='BGCv11_WithLandcover.gdb'),
  
  # feature names to save (note ESRI driver used by GDAL has weird abbreviation behaviour)
  feat.name = c(region = 'REG_NAME',
                org = 'ORG_NAME', 
                cover = 'LAND_COVER_CLASS',
                zone = 'ZONE', 
                subzone = 'SUBZONE', 
                variant = 'VARIANT')
)

#+ results='hide'
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

#' We set up the full-extent output filenames before proceeding  

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
#' Once these files are downloaded/extracted, the script will use the existing ones instead of downloading it all again (unless
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
#' due to a limitation in the ESRI shapefile format. It seems that if *any* of the names exceed 10 characters,  GDAL abbreviates
#' *all* of them to 7 characters, which easily leads to bugs (especially if the abbreviations are not unique). 
#' 



#' Next we rasterize each of the features listed in `cfg.src$feat.name`. The categorical data are converted to
#' integer (to be compatible with the geotiff format), and we save the conversion table as a list in `cfg$out$code`
#' (*eg.* the `n`th entry of `cfg$out$code$varname` is coded as `n` in the corresponding raster) 
#+ eval=FALSE

# reload the shapefile to overwrite the large source database in memory
bgcz.sf = sf::st_read(cfg$out$fname$shp)

# save factor level codes with a sensible ordering
cfg$out$code = lapply(varnames, function(feat) sort(unique(unlist(sf::st_drop_geometry(bgcz.sf[, feat]))), na.last=TRUE))

# convert character columns to integer
bgcz.sf[,1:length(varnames)] = sapply(varnames, function(feature) match(unlist(st_drop_geometry(bgcz.sf[,feature])), cfg$out$code[[feature]]))

#' There is probably a more direct way of doing this using a `factor` representation. Note that 
#' <a href="https://cran.r-project.org/doc/manuals/r-release/NEWS.html" target="_blank">a recent upgrade</a> 
#' to R (v4.0.1) now has different 
#' default behaviour for loading columns of categorical data (*eg.* previous versions of R would load columns 
#' of `bgcz.sf` as factors, not strings). 
#' 

#' Now we can rasterize and write to disk (185 MB total)
#+ eval=FALSE
# loop over variable names to rasterize
pb = txtProgressBar(min=1, max=length(varnames), style=3)
for(idx.feature in 1:length(varnames))
{
  # rasterize, apply provincial borders mask, then write to disk
  setTxtProgressBar(pb, idx.feature)
  temp.tif = raster::mask(fasterize::fasterize(bgcz.sf, bc.mask.tif, field=varnames[idx.feature], fun='last'), bc.mask.tif)
  raster::writeRaster(temp.tif, cfg$out$fname$tif$full[idx.feature], overwrite=TRUE)
}
close(pb)

# garbage collection
rm(list=c('bgcz.sf', 'temp.tif'))

#' Finally, split these layers up into mapsheets corresponding to the NTS/SNRC codes (228 MB)
#+ eval=FALSE

# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)

#' Metadata (including file paths) can now be loaded from 'bgcz.rds' located in `data.dir` using `readRDS()`.

#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src_bgcz.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('src_bgcz.R'))
