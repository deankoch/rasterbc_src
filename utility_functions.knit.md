---
title: "utility_functions.R"
author: "Dean Koch"
date: "June 10, 2020"
output: github_document
---


This loads required packages, sets up parameters, and defines some helper functions. It is sourced at
the beginning of all of the individual downloading/pre-processing scripts ('src_*.R').

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
# blockwise/parallel rasterization (presence/absence -> numeric) 
MPB_rasterize = function(poly.sf, mask.tif, dest.file, aggr.factor=10, blocks.sf=NULL, n.cores=1) 
{
  # rasterizes the input shapefile poly.sf (a POLYGON or MULTIPOLYGON) as GeoTiff written to 
  # path in dest.file (a character vector). mask.tif (a RasterLayer) provides the ouput geometry  
  # (crs, resolution, extent), and its NA values (if any) are used to mask the output (non-NA
  # are ignored).
  
  # (some code below hidden from markdown:)
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
  
  # (some code below hidden from markdown:)
}
```

This function returns a nested list of the form `list(cfg.in, cfg.src)`, where `cfg.in` is a list containing info about the source
urls, filenames, variable names, *etc*; and `cfg.src` contains info about the output files (post-processing). The idea is that
in the 'src_\<collection\>.R' script we call this once with only `collection` specified to get a template list, whose entries are then 
filled in as the script progresses. At the end we save this metadata to '\<collection\>.RData' in `data.dir`.

Each layer uses the same 
<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">Albers projection and NAD83 datum</a>, 
and a cropped version of the grid layout in
<a href="http://hectaresBC.org" target="_blank">hectaresBC</a>,
the parameters of which are hard-coded in this convenience function:


```r
# defines the coordinate reference system (CRS)
MPB_crs = function()
{
  # Returns a list containing various objects related to the reference system.
  # extent, resolution, dimensions are based on hectaresBC, and standard projection/datum for BC
  
  # EPSG code for CRS, resolution in metres, and alignment parameters for grid
  epsg.ref = 3005
  res.ref = c(100,100)
  xmin = 273287.5
  xmax = 1870688
  ymin = 359688
  ymax = 1735788
  
  # (some code below hidden from markdown:)
}
```

Users who wish to use a different reference system may change these parameters before running the 'src_\*.R' scripts.

Most of the 'src_\*.R' scripts first create the raster layers for the full BC extent, before splitting them into smaller mapsheets.
The following convenience function does the splitting, and returns a list of the filenames written


```r
# automated splitting of rasters into mapsheets
MPB_split = function(cfg.in, snrc.sf) 
{
  # snrc.sf is the sf object containing the mapsheet polygons to loop over
  # The function expects cfg.in$out$fname$tif$full to be a character vector of paths to 
  # full-province raster layers. It loops over them, splitting each one (ie crop -> mask) 
  # according the polygons in snrc.sf
  
  # if cfg.in$src contains a (top-level) entry named 'years', it is assumed that cfg.in$out$fname$tif$full 
  # is a list of character string vectors, one list per year. In that case, MPB_split calls itself
  # recursively to run the splitting jobs separately on each of the lists in cfg.in$out$fname$tif$full,
  # writing to subdirectories of cfg.in$out$dir.block, and modifying all names appropriately.
  
  # (some code below hidden from markdown:)
}
```

This function could be easily modified to split over any other tiling of the BC extent.

**rasterbc functions (development)**

The following are functions that I plan to add to the rasterBC package:

Returns the giant nested list of metadata for all of the collections


```r
metadata_bc = function()
{
  # Returns a giant nested list containing the metada for all raster collections. 
  # 
  # For now, this simply scans data.dir and loads all .rds files (ie cfg lists) as entries
  # in the return list. It is assumed that any .rds file found in this directory is of the
  # syntax generated by the 'src_*.R' scripts, and that their contents point to files that
  # exist on disk.
  #
  # In the rasterbc pacakge, this function will probably be hidden from the user and will
  # load the metadata in a more sensible way.
  # (some code below hidden from markdown:)
}
```

Returns the NTS/SNRC mapsheets simple features object  


```r
loadblocks_bc = function()
{
  # load the shapefiles corresponding to the NTS/SNRC mapsheet codes
  # 
  # The NTS/SNRC mapsheets boundaries shapefile is a pretty big (529 KB) binary - 
  # hopefully not too big for CRAN
  #
  # In the rasterbc pacakge, this function will probably be hidden from the user and will
  # store/load the binary in a more sensible way.
  # (some code below hidden from markdown:)
}


findblocks_bc = function(input.sf=NULL)
{
  # returns (in a character vector) the 4-character SNRC/NTS mapsheet codes corresponding
  # to mapsheets all that intersect with the geometry set(s) in input.sf. If input.sf is 
  # NULL, returns the character vector of all codes, ordered according to the rows of the 
  # simple features object returned by blocks_bc.
  # (some code below hidden from markdown:)
}

projection_bc = function(input.sf)
{
  # reproject sfc object (as needed) to the default NAD83 / BC Albers projection 
  # returns the (possibly reprojected) sf object.
  # (some code below hidden from markdown:)
}

# to do: add extra arguments
getraster_bc = function(collection=NULL, varname=NULL, year=NULL, region=NULL)
{
  # if collection is NULL or invalid, return the list of valid options
  cfg = metadata_bc()
  if(is.null(collection))
  {
    print('the following collections are available:') 
    print(names(cfg))
    return()
  }
  if(!(collection %in% names(cfg)))
  {
    print(paste0('Error: collection \'', collection, '\' not found')) 
    getraster_bc()
    return()
  }
  
  # for now I will ignore year and just develop the static layers case (dem, bgcz, borders)
  if(is.null(cfg[[collection]]$years))
  {
    # if varname is NULL or invalid, return the list of valid options
    if(is.null(varname))
    {
      print('the following variables are available:') 
      print(names(cfg[[collection]]$out$fname$tif$full))
      return()
    }
    if(!(varname %in% names(cfg[[collection]]$out$fname$tif$full)))
    {
      print(paste0('Error: varname \'', varname, '\' not found in collection \'', collection, '\'')) 
      getraster_bc(collection)
      return()
    }
  }
  
}
```


