

```r
# ---
# title: "utility_functions.R"
# author: "Dean Koch"
# date: "June 10, 2020"
# output: github_document
# ---
```



This loads required packages, sets up parameters, and defines some helper functions. It is sourced at
the beginning of all of the individual downloading/pre-processing scripts.

**The following packages are required:**



```r
# provides sensible guess for working directory
library(here)

# scraping
library(rvest)
library(RCurl)

# handling tifs, shapefiles
library(raster)
library(rgdal)
library(gdalUtils)
library(sf)
library(fasterize)

# plotting 
library(quickPlot)
library(ggplot2)

# parallel execution
library(doSNOW)
```

**Important user-defined parameters**

be aware of the default storage path:


```r
# define/create a directory for storage of all downloaded source files and output files 
data.dir = here('data')
```

By default this is the subdirectory 'data' relative to the location of the R project file (.../rasterbc/data). 
Around 60GB of data in total will be downloaded/written by the 'src_\*.R' scripts. Feel free to change this to another 
path (*eg.* a drive with more free space), but be careful not to assign it to to an existing directory 
as I do not check for existing files, so *anything already data.dir could get overwritten*.



```r
#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
```

Rasterization requires around 6GB or memory per core. Consider reducing 'n.cores' if you are encountering out-of-memory errors.

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
a partition to split the work over, and merging everything together at the end using `gdalUtils::mosaic_rasters`. 





---
title: utility_functions.R
author: deank
date: '2020-06-10'

---
