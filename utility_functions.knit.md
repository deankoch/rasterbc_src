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
library(RCurl)

# handle tifs, shapefiles
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
# all downloaded source files and output files go here
data.dir = here('data')
```

By default this is the subdirectory 'data' relative to the location of the R project file (...\\rasterbc\\data). 
Around 60GB of data in total will be downloaded/written by the 'src_\*.R' scripts. Feel free to change this to another 
path (*eg.* a drive with more free space), but be careful about assigning it to an existing directory 
as I do not check for existing files, so *anything already in data.dir could get overwritten*.

Some of the rasterization jobs are very time-consuming. This can be sped up by running things in parallel. 


```r
#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
```

Rasterization of an NTS tile requires around 6GB of memory. So with 3 cores going in parallel we need at least 18GB of RAM. 
If you are encountering out-of-memory errors, consider reducing 'n.cores', or changing the code to parallelize over 
smaller chunks (*eg.* the TRIM tiles within each NTS tile) via the `blocks.sf` argument below.

**Convenience functions**


```r
# blockwise/parallel rasterization of large shapefiles
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
layer at `aggr.factor` times higher resolution than `mask.tif`. This high-resolution layer is then downsampled (by averaging 
with `gdalwarp`) to the desired output resolution. 

`blocks.sf` allows large jobs to be done in parallel, by providing 
a partition to split the work over, and (optionally) merging everything together at the end using `gdalUtils::mosaic_rasters`. 

After downloading and processing each data collection, I store the metadata in a big nested list structure:


```r
# metadata list builder for different sources
MPB_metadata = function(collection, cfg.in=NULL, cfg.src=NULL, cfg.out=NULL)
{
  # If called with 'collection' only, creates the storage directory and returns a 
  # (mostly empty) list with entries to be filled in later. If cfg.in is specified, 
  # then elements in cfg.src and/or cfg.out which are missing from cfg.in are added to 
  # the output list. 
  
  # (contents below are hidden from markdown: see utility_functions.R for details)
}
```

This function returns a nested list of the form `list(cfg.in, cfg.src)`, where `cfg.in` is a list containing info about the source
urls, filenames, variable names, *etc*; and `cfg.src` contains info about the output files (post-processing). The idea is that
in the 'src_\<collection\>.R' script we call this once with only `collection` specified to get a template list, whose entries are then 
filled in as the script progresses. At the end we save this metadata to '\<collection\>.RData' in `data.dir`.




