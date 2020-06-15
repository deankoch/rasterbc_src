---
title: "src_dem.R"
author: "Dean Koch"
date: "June 15, 2020"
output: github_document
---


Digital Elevation Map (DEM) and derived products, slope and aspect. Runtime around 5-10 minutes 

After running 'src_borders.R' we now have a set of polygons ('snrc_std.shp', loaded as `snrc.sf`, below)
with which to split the data into blocks (*ie* mapsheets). The path of this shapefile is stored in the `cfg.borders` 
metadata list, which can be loaded from the file 'borders.rds' located in the `data.dir` directory.



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
```

As with the 'borders' collection, we will fill in the metadata as we go, and save a copy to disk at the end 


```r
# create the source data directory, metadata list and its path on disk
collection = 'dem'
cfg = MPB_metadata(collection)
```

```
## [1] "dem source subdirectory exists"
## [1] "source data storage: H:/git-MPB/rasterbc/data/dem/source"
## [1] "dem mapsheets subdirectory exists"
## [1] "mapsheets data storage: H:/git-MPB/rasterbc/data/dem/blocks"
```

```r
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))
```


**source information**

We access an archived (2017) copy of Natural Resources Canada's (NRCan) Canadian Digital Elevation Map (CDEM; see the PDF overview
<a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cdem_mnec/doc/CDEM_en.pdf" target="_blank">here</a>, 
and more detailed documentation 
<a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cdem_mnec/doc/CDEM_product_specs.pdf" target="_blank">here</a>).
The web url below points to an
<a href="http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cdem_mnec/" target="_blank">ftp directory</a>
containing the (zipped) DEM rasters at various resolutions. 

The <a href="https://open.canada.ca/en/open-government-licence-canada" target="_blank">Open Government Licence - Canada</a> applies.

The 3 (arc)second resolution in the archive is sufficient for our purposes, but users may wish to look at the higher (1 and 2 sec) 
resolution datasets available from the newer
<a href="https://open.canada.ca/data/en/dataset/957782bf-847c-4644-a757-e383c0057995" target="_blank">High Resolution</a> DEM. 
A useful directory of Canadian DEM products can be found
<a href="https://www.nrcan.gc.ca/science-and-data/science-and-research/earth-sciences/geography/topographic-information/download-directory-documentation/17215" target="_blank">here</a>. 


```r
# define the source metadata
cfg.src = list(
  
  # url to download from
  web = 'http://ftp.geogratis.gc.ca/pub/nrcan_rncan/elevation/cdem_mnec/archive/cdem_3sec.zip',
  
  # files in the zip
  fname = c(tif = 'cdem_3sec.tif')
)
```

```r
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)
```

After warping the elevation layer to the reference coordinate system, we will compute the derived quantities `slope` and `aspect`. 
We set up these output filenames before proceeding  


```r
# set up the source and full-extent output filenames
varnames = setNames(nm=c(dem='dem', slope='slope', aspect='aspect'))
cfg$src$fname = c(dem=file.path(cfg$src$dir, cfg$src$fname))
cfg$out$fname$tif$full = setNames(file.path(data.dir, cfg$out$name, paste0(varnames, '_std.tif')), varnames)
```

**downloads**

This is a large zip archive containing a *very large* geotiff file (2.5 GB, or **21 GB uncompressed**).

Once the file is downloaded/extracted, the script will use the existing file instead of downloading it again (unless
`force.download` is set to `TRUE`) 


```
## [1] "using existing source files:"
##                                                 dem 
## "H:/git-MPB/rasterbc/data/dem/source/cdem_3sec.tif"
```


**processing**




```r
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])
```

First, crop the elevation layer and write the full extent to disk in a temporary file (1.7 GB):


```r
# load the gigantic source raster, note GDAL warning about the outdated PROJ string
temp.tif = paste0(tempfile(), '.tif')
dem.tif = raster::raster(cfg$src$fname['dem'])
```

```r
# crop to BC using a fast GDAL translate operation via tempfile
dem.bbox = st_bbox(sf::st_transform(prov.sf, raster::crs(dem.tif)))
gdalUtils::gdal_translate(src_dataset=cfg$src$fname['dem'], 
                          dst_dataset=temp.tif, 
                          projwin=dem.bbox[c('xmin', 'ymax', 'xmax', 'ymin')])
```

Next, warp the DEM using fast GDAL warp call, save to disk (859 MB), delete tempfile


```r
# reload DEM raster with smaller cropped version, then warp
dem.tif = raster::raster(temp.tif)
gdalUtils::gdalwarp(srcfile=temp.tif, 
                    dstfile=cfg$out$fname$tif$full['dem'], 
                    s_srs=raster::crs(dem.tif), 
                    t_srs=raster::crs(bc.mask.tif), 
                    tr=raster::res(bc.mask.tif), 
                    r='bilinear', te=raster::bbox(bc.mask.tif), 
                    overwrite=TRUE, 
                    verbose=TRUE)
```

Note that with large data files, these (external) GDAL calls are much faster than using package `raster`.
Here (and anywhere else a warp is done) I use bilinear interpolation to assign values to grid-points. Note that, 
wherever possible, it is best to avoid warping (a kind of raster-to-raster reprojection), because it is a lossy 
operation, introducing a new source of error. 


```r
# reload dem, compute min/max stats, clip to mask, rewrite to disk (415 MB)
```

```r
bc.dem.tif = raster::mask(raster::setMinMax(raster::raster(cfg$out$fname$tif$full['dem'])), bc.mask.tif)
raster::writeRaster(bc.dem.tif, cfg$out$fname$tif$full['dem'], overwrite=TRUE)
unlink(temp.tif)
```

Next we compute the slope and aspect layers, and write full-extent rasters to disk (875 MB total)


```r
# compute slope
gdalUtils::gdaldem(mode='slope', 
                   input_dem=cfg$out$fname$tif$full['dem'], 
                   output=cfg$out$fname$tif$full['slope'], 
                   compute_edges=TRUE)

# reload, compute min/max stats, clip to mask, rewrite to disk (441 MB)
bc.slope.tif = raster::mask(raster::setMinMax(raster::raster(cfg$out$fname$tif$full['slope'])), bc.mask.tif)
raster::writeRaster(bc.slope.tif, cfg$out$fname$tif$full['slope'], overwrite=TRUE)

# compute aspect
gdalUtils::gdaldem(mode='aspect', 
                   input_dem=cfg$out$fname$tif$full['dem'], 
                   output=cfg$out$fname$tif$full['aspect'], 
                   compute_edges=TRUE)

# reload, compute min/max stats, clip to mask, rewrite to disk (434 MB)
bc.aspect.tif = raster::mask(raster::setMinMax(raster::raster(cfg$out$fname$tif$full['aspect'])), bc.mask.tif)
raster::writeRaster(bc.aspect.tif, cfg$out$fname$tif$full['aspect'], overwrite=TRUE)

# garbage collection
rm(list=c('dem.tif', 'bc.slope.tif', 'bc.aspect.tif'))
```

Finally, split these layers up into mapsheets corresponding to the NTS/SNRC codes (1.2 GB)


```r
# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'dem.rds' located in `data.dir` using `readRDS()`.



