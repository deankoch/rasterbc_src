---
title: "utility_functions.R"
author: "Dean Koch"
date: "June 10, 2020"
output: github_document
---


This loads required packages, sets up parameters, and defines some helper functions. It is sourced at
the beginning of all of the individual downloading/pre-processing scripts.

**The following packages are required:**



```r
# identify working directory
library(here)

# scrape URLS
library(rvest)
```

```
## Loading required package: xml2
```

```r
library(RCurl)

# handle tifs, shapefiles
library(raster)
```

```
## Loading required package: sp
```

```r
library(rgdal)
```

```
## rgdal: version: 1.5-8, (SVN revision 990)
## Geospatial Data Abstraction Library extensions to R successfully loaded
## Loaded GDAL runtime: GDAL 3.0.4, released 2020/01/28
## Path to GDAL shared files: C:/Program Files/R/R-4.0.1/library/rgdal/gdal
## GDAL binary built with GEOS: TRUE 
## Loaded PROJ runtime: Rel. 6.3.1, February 10th, 2020, [PJ_VERSION: 631]
## Path to PROJ shared files: C:/Program Files/R/R-4.0.1/library/rgdal/proj
## Linking to sp version:1.4-2
## To mute warnings of possible GDAL/OSR exportToProj4() degradation,
## use options("rgdal_show_exportToProj4_warnings"="none") before loading rgdal.
```

```r
library(gdalUtils)
library(sf)
```

```
## Linking to GEOS 3.8.0, GDAL 3.0.4, PROJ 6.3.1
```

```
## 
## Attaching package: 'sf'
```

```
## The following object is masked from 'package:gdalUtils':
## 
##     gdal_rasterize
```

```r
library(fasterize)
```

```
## 
## Attaching package: 'fasterize'
```

```
## The following object is masked from 'package:graphics':
## 
##     plot
```

```
## The following object is masked from 'package:base':
## 
##     plot
```

```r
# plotting 
library(quickPlot)
library(ggplot2)

# parallel execution
library(doSNOW)
```

```
## Loading required package: foreach
```

```
## Loading required package: iterators
```

```
## Loading required package: snow
```

**Important user-defined parameters**

be aware of the default storage path:


```r
# all downloaded source files and output files go here
data.dir = here('data')
dir.create(data.dir, recursive=TRUE)
```

```
## Warning in dir.create(data.dir, recursive = TRUE): 'H:\git-MPB\rasterbc\data' already exists
```

By default this is the subdirectory 'data' relative to the location of the R project file (.../rasterbc/data). 
Around 60GB of data in total will be downloaded/written by the 'src_\*.R' scripts. Feel free to change this to another 
path (*eg.* a drive with more free space), but be careful not to assign it to to an existing directory 
as I do not check for existing files, so *anything already data.dir could get overwritten*.

Some of the rasterization jobs are very time-consuming. This can be sped up by running things in parallel 


```r
#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
```

Rasterization of an NTS tile requires around 6GB. So with 3 cores going in parallel we need at least 18GB of RAM. 
If you are encountering out-of-memory errors, consider reducing 'n.cores', or changing to code to parallelize over 
smaller chunks (*eg.* the TRIM tiles within each NTS tile).

**Convenience functions**


```r
# blockwise/parallel rasterization of big datasets
MPB_rasterize = function(poly.sf, mask.tif, dest.file, aggr.factor=10, blocks.sf=NULL, n.cores=1) 
{
  # rasterizes the input shapefile poly.sf (a POLYGON or MULTIPOLYGON) as GeoTiff written to 
  # path in dest.file (a character vector). mask.tif (a RasterLayer) provides the ouput geometry  
  # (crs, resolution, extent), and its NA values (if any) are used to mask the output (non-NA
  # are ignored).
  
  # (contents below are hidden from markdown: see utility_functions.R for details)
}
```

This works by calling `fasterize::fasterize` (with `fun='any'`) on the polygons in `poly.sf` to make a presence/absence 
layer at `aggr.factor` times higher resolution than `mask.tif`. This high-res layer is then downsampled (by averaging 
with `gdalwarp`) to the desired output resolution. 

`blocks.sf` allows large jobs to be done in parallel, by providing 
a partition to split the work over, and (optionally) merging everything together at the end using `gdalUtils::mosaic_rasters`. 
Here we process the NTS tiles 3 at a time (`n.cores`=3), and theres no need to merge the result because this tiling is how we 
want the data split up in the end.



