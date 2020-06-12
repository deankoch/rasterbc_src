---
title: "src_borders.R"
author: "Dean Koch"
date: "June 10, 2020"
output: github_document
---


This is the initial setup script for reproducing the rasterbc dataset. 
It downloads some shapefiles to define boundaries, and sets up configuration details for GIS processing.



```r
# load the helper functions
library(here)
source(here('utility_functions.R'))
```

```
## [1] "data directory H:/git-MPB/rasterbc/data exists"
```

```r
# create the source data directory and metadata list
collection = 'borders'
cfg = MPB_metadata(collection)
```

```
## [1] "borders subdirectory exists"
## [1] "source data storage: H:/git-MPB/rasterbc/data/borders/source"
```


**source information**

These data are from the National Topographic System (NTS) of Canada 
(<a href="https://www.nrcan.gc.ca/maps-tools-publications/maps/topographic-maps/10995" target="_blank">Natural Resources Canada</a>)
The web url below points to a zip archive containing a shapefile of provincial borders, and a shapefile of polygons for a tiling of 
the geography into smaller blocks (or *mapsheets*, indexed by a 
<a href="https://www.nrcan.gc.ca/earth-sciences/geography/topographic-information/maps/9765" target="_blank">number-letter code</a>).
The <a href="https://open.canada.ca/en/open-government-licence-canada" target="_blank">Open Government Licence - Canada</a> applies.


```r
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
```

```
## [1] "borders subdirectory exists"
## [1] "source data storage: H:/git-MPB/rasterbc/data/borders/source"
```

From the provincial border polygon we will construct a binary raster indicating whether the grid cell lies 
in the BC landmass (`prov`); In addition we store the latitude and longitude for each cell (`latitude`,
`longitude`) in separate layers. Copies of the reprojected provincial border and mapsheet polygons will be saved as shapefile.



```r
# set up the source and output filenames
varnames = setNames(nm=c(names(cfg$src$fname.prefix), lat='latitude', long='longitude'))
cfg$src$fname = setNames(paste0(file.path(cfg$src$path, cfg$src$fname.prefix), '.shp'), varnames[c('prov', 'snrc')])
cfg$out$path$shp = setNames(paste0(file.path(data.dir, cfg$out$subdir, varnames[c('prov', 'snrc')]), '_std.shp'), varnames[c('prov', 'snrc')])
prefix.tif = setNames(file.path(data.dir, cfg$out$subdir, varnames[!(varnames %in% 'snrc')]), varnames[!(varnames %in% 'snrc')])
```

`prefix.tif` gives the first part of the filenames that will later be assigned to each of the mapsheets, along with a suffix
of the form '_\<SNRC-code\>.tif'. First we need to download and open the SNRC shapefile to find out which mapsheet codes are relevant.

**downloads**

This is a relatively small zip archive (12.2 MB, or 55.1 MB uncompressed)


```r
# download the zip to temporary file (12.2 MB), extract to disk
borders.tmp = tempfile('borders_temp', cfg$src$path, '.zip')
download.file(url=cfg$src$web, destfile=borders.tmp, mode='wb')
borders.paths = unzip(borders.tmp, exdir=cfg$src$path)
unlink(borders.tmp)
```

verify that the two source files listed in `cfg$src$fname` are among the extracted files


```r
all(cfg$src$fname %in% borders.paths)
```

```
## [1] TRUE
```


**processing**



```r
# some more comment testing

# here is a regular code comment, that will remain as such
summary(VADeaths)
```

```
##    Rural Male     Rural Female     Urban Male     Urban Female  
##  Min.   :11.70   Min.   : 8.70   Min.   :15.40   Min.   : 8.40  
##  1st Qu.:18.10   1st Qu.:11.70   1st Qu.:24.30   1st Qu.:13.60  
##  Median :26.90   Median :20.30   Median :37.00   Median :19.30  
##  Mean   :32.74   Mean   :25.18   Mean   :40.48   Mean   :25.28  
##  3rd Qu.:41.00   3rd Qu.:30.90   3rd Qu.:54.60   3rd Qu.:35.10  
##  Max.   :66.00   Max.   :54.30   Max.   :71.10   Max.   :50.00
```


