#' ---
#' title: "src_borders.R"
#' author: "Dean Koch"
#' date: "June 10, 2020"
#' output: github_document
#' ---
#' 
#' 
#' This is the initial setup script for reproducing the rasterbc dataset. 
#' It downloads some shapefiles to define boundaries, and sets up configuration details for GIS processing.
#' 

# download again to rewrite existing files? 
force.download = FALSE

# load the helper functions
library(here)
source(here('utility_functions.R'))

# create the source data directory and metadata list
collection = 'borders'
cfg = MPB_metadata(collection)

#'
#' **source information**
#' 
#' These data are from the National Topographic System (NTS) of Canada 
#' (<a href="https://www.nrcan.gc.ca/maps-tools-publications/maps/topographic-maps/10995" target="_blank">Natural Resources Canada</a>).
#' The web url below points to an
#' <a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/vector/index/" target="_blank">ftp directory</a>
#' containing a zip archive with shapefiles for provincial borders, and for a tiling of BC's geographical area into 
#' smaller blocks (or *mapsheets*, indexed by a 
#' <a href="https://www.nrcan.gc.ca/earth-sciences/geography/topographic-information/maps/9765" target="_blank">number-letter code</a>).
#' The <a href="https://open.canada.ca/en/open-government-licence-canada" target="_blank">Open Government Licence - Canada</a> applies.

# define the source metadata
cfg.src = list(
  
  # url to download from
  web = 'http://ftp.geogratis.gc.ca/pub/nrcan_rncan/vector/index/nts_snrc.zip',
  
  # filename strings of the shapefiles for BC provincial border and SNRC mapsheets 
  fname.prefix = c(prov = 'prov_territo', 
                   snrc = 'nts_snrc_250k'),
  
  # feature names to save
  feat.name = c(NTS_SNRC = 'NTS_SNRC',
                NAME_ENG = 'NAME_ENG', 
                NOM_FRA = 'NOM_FRA')
)

# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

#' From the provincial border polygon we will construct a binary raster indicating whether the grid cell lies 
#' in BC (`prov`); In addition we store the latitude and longitude for each cell (`latitude`, `longitude`) 
#' in separate layers. Copies of the reprojected provincial border and mapsheet polygons will be saved as shapefile.
#' 

# set up the source and output filenames
varnames = setNames(nm=c(names(cfg$src$fname.prefix), lat='latitude', long='longitude'))
cfg$src$fname = setNames(paste0(file.path(cfg$src$path, cfg$src$fname.prefix), '.shp'), varnames[c('prov', 'snrc')])
cfg$out$path$shp = setNames(paste0(file.path(data.dir, cfg$out$subdir, varnames[c('prov', 'snrc')]), '_std.shp'), varnames[c('prov', 'snrc')])
prefix.tif = setNames(file.path(data.dir, cfg$out$subdir, varnames[!(varnames %in% 'snrc')]), varnames[!(varnames %in% 'snrc')])
cfg$out$path$tif$full = setNames(paste0(prefix.tif, '.tif'), varnames[!(varnames %in% 'snrc')])


#' `prefix.tif` gives the first part of the filenames that will later be assigned to each of the mapsheets, along with a suffix
#' of the form '_\<SNRC-code\>.tif'. First we need to download and open the SNRC shapefile to find out which mapsheet codes are relevant.
#'
#' **downloads**
#' 
#' This is a relatively small zip archive (12.2 MB, or 55.1 MB uncompressed)

# check if we need to download it again:
if(!all(file.exists(cfg$src$fname)) | force.download)
{
  #+ eval=FALSE
  # download the zip to temporary file (12.2 MB), extract to disk
  borders.tmp = tempfile('borders_temp', cfg$src$path, '.zip')
  download.file(url=cfg$src$web, destfile=borders.tmp, mode='wb')
  borders.paths = unzip(borders.tmp, exdir=cfg$src$path)
  unlink(borders.tmp)
  
  #' verify that the two source files listed in `cfg$src$fname` are among the extracted files
  all(cfg$src$fname %in% borders.paths)
  
} else {
 
  print('using existing source files:') 
  print(cfg$src$fname)
}

#'
#' **processing**
#' 
#' 

#' First, prepare a mask for in-province pixels and save it to disk:

# load the provincial boundaries polygons and NTS/SNRC blocks, reprojecting to crs(bc.mask.tif)
prov.sf = sf::st_transform(sf::st_read(dsn=cfg$src$fname['prov']), MPB_crs()$epsg) 
snrc.sf = sf::st_transform(sf::st_read(dsn=cfg$src$fname['snrc']), MPB_crs()$epsg)

# create a mask for in-province pixels (setting reference extent and resolution)
ref.tif = raster::crop(MPB_crs()$tif, prov.sf[prov.sf$PROV_TERRI=='BC',1], snap='out')
bc.sf = prov.sf[prov.sf$PROV_TERRI=='BC',1]

# replace character column with numeric, rasterize, and write (20.2 MB) 
#+ eval=FALSE
bc.sf$PROV_TERRI = 0
bc.mask.tif = fasterize::fasterize(sf=bc.sf, raster=ref.tif, field='PROV_TERRI', fun='any')
raster::writeRaster(bc.mask.tif, cfg$out$path$tif$full['prov'], overwrite=TRUE)

#' Next, build a list of NTS/SNRC codes that overlap with BC landmass

# find which SNRC codes intersect with BC, Yukon, Northwest Territories
bc.blocks.idx = sf::st_intersects(sf::st_geometry(prov.sf[prov.sf$PROV_TERRI=='BC',1]), sf::st_geometry(snrc.sf), sparse=FALSE)
yt.blocks.idx = sf::st_intersects(sf::st_geometry(prov.sf[prov.sf$PROV_TERRI=='YT',1]), sf::st_geometry(snrc.sf), sparse=FALSE)
nt.blocks.idx = sf::st_intersects(sf::st_geometry(prov.sf[prov.sf$PROV_TERRI=='NT',1]), sf::st_geometry(snrc.sf), sparse=FALSE)
omit.blocks.idx = yt.blocks.idx | nt.blocks.idx | is.na(snrc.sf$NAME_ENG)

#' There seem to be some overlap/imprecision issues with the provincial border polygons: some of the coastal mapsheets
#' (see below, in blue) are missing from this intersection (in yellow). I add them back manually...
missing.blocks = c('102O', '103O', '114O', '104C', '114I', '114P', '114O')
plot(st_geometry(bc.sf), col='yellow')
plot(st_geometry(snrc.sf)[bc.blocks.idx & !omit.blocks.idx], add=TRUE)
plot(st_geometry(snrc.sf)[snrc.sf$NTS_SNRC %in% missing.blocks], add=TRUE, col='blue')
incl.blocks.idx = bc.blocks.idx & !omit.blocks.idx | snrc.sf$NTS_SNRC %in% missing.blocks
incl.features.idx = which(names(snrc.sf) %in% cfg$src$feat.name)

#' ... and save reprojected/simplified version of the source shapefile data (1.1 MB).
#+ eval=FALSE
sf::st_write(snrc.sf[incl.blocks.idx, incl.features.idx], cfg$out$path$shp['snrc'], append=FALSE)
sf::st_write(bc.sf, cfg$out$path$shp['prov'], append=FALSE)

#' Now reload these files to overwrite the (larger) source shapefiles in memory: 
#' The NTS/SNRC codes in `cfg$out$code` should match those in the NTS mapsheet collection for BC
#' (<a href="https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/index/index_pdf/NTS-SNRC_Index%205_British_Columbia_300dpi.pdf" target="_blank">PDF link</a>).
#+ results='hide'
snrc.sf = sf::st_read(cfg$out$path$shp['snrc'])
prov.sf = sf::st_read(cfg$out$path$shp['prov'])
cfg$out$code = snrc.sf$NTS_SN

#' Create `latitude`, `longitude` layers via `sp` package (slow step, taking around 5 minutes), then save to disk (285 MB, 352 MB)
#+ eval=FALSE
# load the in-province mask (raster), convert to points dataframe 
bc.mask.tif = raster::raster(cfg$out$path$tif$full['prov'])
bc.coords.df = data.frame(raster::coordinates(bc.mask.tif))
sp::coordinates(bc.coords.df) = c('x', 'y')
sp::proj4string(bc.coords.df) = raster::crs(bc.mask.tif)

# reproject to lat/long, apply mask, and write
bc.coords.df = sp::spTransform(bc.coords.df, CRS=sp::CRS('+proj=longlat +ellps=GRS80'))
raster::writeRaster(raster::mask(raster::setValues(bc.mask.tif, bc.coords.df$y), bc.mask.tif), cfg$out$path$tif$full['latitude'], overwrite=TRUE)
raster::writeRaster(raster::mask(raster::setValues(bc.mask.tif, bc.coords.df$x), bc.mask.tif), cfg$out$path$tif$full['longitude'], overwrite=TRUE)

#' Finally, split these layers up into mapsheets corresponding to the NTS/SNRC codes
# To do: add block subfolder to data/*/ in utility_functions.R
# To do: add the output filenames earlier in this script
# To do: build a loop that does the crop/save. Remember to reload rasters where eval=FALSE
# To do: write RData file with final cfg list
# par(mfrow)
# plot(raster(cfg$out$path$tif$full['latitude']))
# plot(raster(cfg$out$path$tif$full['longitude']))


#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('src_borders.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('src_borders.R'))
