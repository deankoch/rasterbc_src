---
title: "src_gfc.R"
author: "Dean Koch"
date: "June 16, 2020"
output: github_document
---

Forest extent and change estimates based on Landsat 7 and 8 imaging data (spanning 2000-2019) from
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2013-0401" target="_blank">Hansen *et al.*, 2013</a>





```r
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
collection = 'gfc'
cfg = MPB_metadata(collection)
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))
```


**source information**

This script fetches the British-Columbia extent of the (global) forest change (GFS) data products published by
<a href="http://earthenginepartners.appspot.com/science-2013-global-forest/download_v1.7.html" target="_blank">Hansen/UMD/Google/USGS/NASA</a>
and documented in a 
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2013-0401" target="_blank">2013 Science publication</a>.
Estimates are generated from a bagged decision tree model relating multi-band reflectance values from the
<a href="https://landsat.gsfc.nasa.gov/landsat-data-continuity-mission/" target="_blank">Landsat 7 and 8</a> 
satellites to various tree cover classifications. (for more information on the methods, see the paper's 
<a href="https://science.sciencemag.org/highwire/filestream/594982/field_highwire_adjunct_files/0/Hansen.SM.pdf" target="_blank">supplementary materials</a>).

This script downloads the relevant granules from the most recent version (v1.7, as of June, 2020), transforms them to align with our grid,
clips to the BC extent, and finally splits all layers into blocks.

Layer `treecover` is a (one-time) percent tree cover estimate for year 2000, where a location is defined as treed if vegetation height exceeds 
5 metres. Pixels are classified as treed (or not) based on a 50\% cutoff criterion for percent grid cell area covered by trees. Layer `gain` 
classifies pixels as having transformed from non-treed to treed at some point during the period 2000-2019; and `loss` is a *yearly* classification of 
stand-level disturbance, identifying pixels that transformed from treed to non-treed during the years 2000, ..., 2018.
Layer `mask` identifies landcover type (water versus land) and NA areas, similar to the `cover` variable from the BC BGCZ. 

Two multispectral cloud-free image composites are also available from this source, however they
are omitted (for now) to keep file sizes under control.   


The GFC source data are licensed under the
<a href="http://creativecommons.org/licenses/by/4.0/" target="_blank">Creative Commons Attribution 4.0 International License</a>. This script
modifies them by applying a bilinear transformation to align with our
<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a> grid. 



```r
# define the source metadata
cfg.src = list(
  
  # web directory where the granules are published
  web = 'https://storage.googleapis.com/earthenginepartners-hansen/GFC-2019-v1.7/',
  
  # all files are of form: <fname.prefix><feat.name><fname.suffix>.tif
  fname.prefix = 'Hansen_GFC-2019-v1.7_',
  feat.name = c(treecover = 'treecover2000_',
                gain = 'gain_', 
                loss = 'lossyear_',
                mask = 'datamask_'),
  
  # coordinate strings of the five 10x10 degree granules covering BC extent
  fname.suffix = c(granule1 = '60N_140W.tif', 
                   granule2 = '60N_130W.tif', 
                   granule3 = '60N_120W.tif', 
                   granule4 = '50N_130W.tif', 
                   granule5 = '50N_120W.tif'),
  
  # character vectors naming the years to extract from lossyear
  years = setNames(2001:2019, nm=paste0('yr', 2001:2019))
  
  
  
)
```

```r
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)
```

We build a list of URLs to download from, and set up the full-extent output filenames before proceeding: 


```r
# set up the source filenames, urls
varnames = setNames(nm=names(cfg$src$feat.name))
src.filenames = lapply(cfg$src$fname.suffix, function(suffix) setNames(paste0(cfg$src$fname.prefix, cfg$src$feat.name, suffix), varnames))
cfg$src$web = lapply(src.filenames, function(granule) setNames(paste0(cfg$src$web, granule), varnames))
cfg$src$fname = lapply(cfg$src$fname.suffix, function(suffix) setNames(paste0(file.path(cfg$src$dir, cfg$src$fname.prefix), cfg$src$feat.name, suffix), varnames)) 

# loss is a time series (and will be split by year), whereas the other layers are one-time estimates
varnames.static = varnames[varnames != 'loss']
fnames.loss = lapply(cfg$src$years, function(year) c(loss=file.path(data.dir, cfg$out$name, year, paste0('loss_std_', year, '.tif'))))
fnames.static = setNames(file.path(data.dir, cfg$out$name, paste0(varnames.static, '_std.tif')), varnames.static)
cfg$out$fname$tif$full = c(fnames.static, fnames.loss)
```

The `loss` layer is split into yearly (binary) rasters in separate subdirectories of `file.path(data.dir, collection)` and 
`file.path(data.dir, collection, 'blocks')` (named by year). These directories are created automatically in the call to `MPB_metadata`. 
Here, there are 19 subfolders, for the years 2000, ..., 2018

**downloads**

20 large shapefiles are downloaded here: 4 attributes for each of the 5 granules, covering all of BC (2.4 GB total).
Once these files are downloaded/extracted, the script will use the existing ones instead of downloading it all again (unless
`force.download` is set to `TRUE`) 


```
## [1] "using existing source files:"
## $granule1
##                                                                             treecover 
## "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_treecover2000_60N_140W.tif" 
##                                                                                  gain 
##          "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_gain_60N_140W.tif" 
##                                                                                  loss 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_lossyear_60N_140W.tif" 
##                                                                                  mask 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_datamask_60N_140W.tif" 
## 
## $granule2
##                                                                             treecover 
## "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_treecover2000_60N_130W.tif" 
##                                                                                  gain 
##          "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_gain_60N_130W.tif" 
##                                                                                  loss 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_lossyear_60N_130W.tif" 
##                                                                                  mask 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_datamask_60N_130W.tif" 
## 
## $granule3
##                                                                             treecover 
## "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_treecover2000_60N_120W.tif" 
##                                                                                  gain 
##          "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_gain_60N_120W.tif" 
##                                                                                  loss 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_lossyear_60N_120W.tif" 
##                                                                                  mask 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_datamask_60N_120W.tif" 
## 
## $granule4
##                                                                             treecover 
## "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_treecover2000_50N_130W.tif" 
##                                                                                  gain 
##          "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_gain_50N_130W.tif" 
##                                                                                  loss 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_lossyear_50N_130W.tif" 
##                                                                                  mask 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_datamask_50N_130W.tif" 
## 
## $granule5
##                                                                             treecover 
## "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_treecover2000_50N_120W.tif" 
##                                                                                  gain 
##          "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_gain_50N_120W.tif" 
##                                                                                  loss 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_lossyear_50N_120W.tif" 
##                                                                                  mask 
##      "H:/git-MPB/rasterbc/data/gfc/source/Hansen_GFC-2019-v1.7_datamask_50N_120W.tif"
```


**processing**



```r
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])

# temporarily add lossyear to list of static layers
fnames.static = c(fnames.static, loss=file.path(data.dir, cfg$out$name, 'lossyear_temp_std.tif'))
```

First, we combine the five granules into a single mosaic raster for each of the four variables, clipping to BC extent,
and warping to BC Albers projection. Full province rasters are then written to disk (410 MB total), with `loss` being split into 18
binary rasters indicating loss in each of the yearlong periods 2000-2001, 2001-2002, ..., 2018-2019. Paths to these output rasters
can be found in `cfg$out$fname$tif$full`. Expect this to take about 15-20 minutes 
to complete.


```r
# loop over static layers (writes 180 MB)
print('merging, warping, downscaling GFC layers...')
pb = txtProgressBar(min=1, max=length(fnames.static), style=3)
for(idx.layer in 1:length(fnames.static))
{
  # print progress
  setTxtProgressBar(pb, idx.layer)
  varname = names(fnames.static)[idx.layer]
  
  # set up filenames to process
  dest.filename = fnames.static[idx.layer]
  source.filenames = sapply(cfg$src$fname, function(granule) granule[[which(names(granule)==varname)]] )
  
  # store source CRS
  crs.gfc = raster::crs(raster::raster(source.filenames[[1]]))
  
  # find the combined extent of all granules and write a temporary template raster of these dimensions
  extent.tomerge = do.call(raster::merge, lapply(as.character(source.filenames), function(granule) raster::extent(raster::raster(granule))))
  temp.tif = paste0(tempfile(), '.tif')
  raster::writeRaster(raster::raster(extent.tomerge, crs=crs.gfc), temp.tif)
  
  # merge all granules, writing to tempfile, then warp (using GDAL)
  gdalUtils::mosaic_rasters(source.filenames, dst_dataset=temp.tif)
  gdalUtils::gdalwarp(srcfile=temp.tif, 
                      dstfile=dest.filename, 
                      s_srs=crs.gfc, 
                      t_srs=raster::crs(bc.mask.tif), 
                      tr=raster::res(bc.mask.tif), 
                      r='bilinear', 
                      te=raster::bbox(bc.mask.tif), 
                      overwrite=TRUE, 
                      verbose=TRUE)

  # clip to mask and write to disk
  temp.tif = raster::mask(raster::crop(raster::raster(dest.filename), bc.mask.tif, snap='out'), bc.mask.tif)
  raster::writeRaster(temp.tif, dest.filename, overwrite=TRUE)
}
close(pb)

# split lossyear to create binary rasters indicating loss at each pixel in that year (writes 262 MB)
lossyear.tif = raster::raster(fnames.static['loss'])
pb = txtProgressBar(min=1, max=length(cfg$src$years), style=3)
for(idx.year in 1:length(cfg$src$years))
{
  setTxtProgressBar(pb, idx.year)
  
  # define output
  year.string = names(cfg$src$years)[idx.year]
  year = cfg$src$years[idx.year]
  dest.filename = cfg$out$fname$tif$full[[year.string]]
  
  # define a temporary binary raster indicating loss in current year, then write to disk
  temp.tif = lossyear.tif == idx.year
  raster::writeRaster(temp.tif, dest.filename, overwrite=TRUE)
  unlink(temp.tif)
}
close(pb)
```

The `loss` layer is now split into yearly rasters, so we can delete the temporary file 


```r
# delete the temporary raster
unlink(fnames.static['loss'])
fnames.static = fnames.static[names(fnames.static) != 'loss']
```

Finally, we split all layers up into mapsheets corresponding to the NTS/SNRC codes (580 MB total). Expect this to take around 30 minutes.
The use of a temporary metadata list, `cfg.temp`, is a kludge to prevent `MPB_split` from looking for yearly data in the static variables.


```r
# define temporary metadata list without the yearly variable
cfg.temp = cfg
cfg.temp$src$years = NULL
idx.static = names(cfg.temp$out$fname$tif$full) %in% varnames.static
cfg.temp$out$fname$tif$full = cfg.temp$out$fname$tif$full[idx.static]

# crop and save blocks for static variables
cfg.static.blocks = MPB_split(cfg.temp, snrc.sf)

# now omit the static variables, so that MPB_split builds yearly filenames
cfg.temp = cfg
cfg.temp$out$fname$tif$full = cfg.temp$out$fname$tif$full[!idx.static]
cfg.loss.blocks = MPB_split(cfg.temp, snrc.sf)

# combine the filename lists
cfg.blocks = c(cfg.static.blocks, cfg.loss.blocks)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'gfc.rds' located in `data.dir` using `readRDS()`.



