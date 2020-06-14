#' ---
#' title: "utility_functions.R"
#' author: "Dean Koch"
#' date: "June 10, 2020"
#' output: github_document
#' ---
#' 
#' 

#' This loads required packages, sets up parameters, and defines some helper functions. It is sourced at
#' the beginning of all of the individual downloading/pre-processing scripts.
#' 
#' **The following packages are required:**
#' 

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

#' **Important user-defined parameters**
#' 
#' be aware of the default storage path:
# all downloaded source files and output files go here
data.dir = here('data')
# /*
if(!dir.exists(data.dir))
{
  dir.create(data.dir, recursive=TRUE)
  print(paste('data directory', data.dir, 'created'))
  
} else {
  
  print(paste('data directory', data.dir, 'exists'))
}
# */

#' By default this is the subdirectory 'data' relative to the location of the R project file (...\\rasterbc\\data). 
#' Around 60GB of data in total will be downloaded/written by the 'src_\*.R' scripts. Feel free to change this to another 
#' path (*eg.* a drive with more free space), but be careful about assigning it to an existing directory 
#' as I do not check for existing files, so *anything already in data.dir could get overwritten*.
#'
#' Some of the rasterization jobs are very time-consuming. This can be sped up by running things in parallel. 

#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
#' Rasterization of an NTS tile requires around 6GB of memory. So with 3 cores going in parallel we need at least 18GB of RAM. 
#' If you are encountering out-of-memory errors, consider reducing 'n.cores', or changing the code to parallelize over 
#' smaller chunks (*eg.* the TRIM tiles within each NTS tile) via the `blocks.sf` argument below.
#' 

#' **Convenience functions**

# blockwise/parallel rasterization of large shapefiles
MPB_rasterize = function(poly.sf, mask.tif, dest.file, aggr.factor=10, blocks.sf=NULL, n.cores=1) 
{
  # rasterizes the input shapefile poly.sf (a POLYGON or MULTIPOLYGON) as GeoTiff written to 
  # path in dest.file (a character vector). mask.tif (a RasterLayer) provides the ouput geometry  
  # (crs, resolution, extent), and its NA values (if any) are used to mask the output (non-NA
  # are ignored).
  
  # (some code below hidden from markdown:)
  # /*
  
  # blocks.sf (a POLYGON or MULTIPOLYGON) optionally supplies a set of polygons (subsets of the 
  # region in mask.tif, covering its extent) over which to loop MPB_rasterize; n.cores (integer 
  # > 0) allows this to be done in parallel. Precision is set by aggr.factor (integer > 1) 
  
  # Note: projections aren't checked or transformed, so the crs() of all inputs (poly.sf, 
  # mask.tif, blocks.sf) should match.
  
  # extract geometry of shapefile input and create dummy attribute with (uniform) value 1
  poly.sf = sf::st_geometry(poly.sf)
  poly.sf = sf::st_sf(list(dummy=rep(1, length(poly.sf)), poly.sf))
  
  # check for and fix any bad geometries
  if(!all(sf::st_is_valid(poly.sf)))
  {
    poly.sf = sf::st_make_valid(poly.sf)
  }
  
  # prepare new mask raster with higher resolution
  mask.highres.tif = mask.tif 
  raster::res(mask.highres.tif) = (1/aggr.factor)*raster::res(mask.tif)  
  
  # handle cases of default and blockwise execution 
  if(is.null(blocks.sf))
  {
    # default: mask.highres.tif not split into blocks
    
    # fast presence/absence rasterization to high res grid
    temp.highres.tif = fasterize(poly.sf, mask.highres.tif, field=NULL, fun='any', background=0)
    
    # downsample to reference grid to get % coverage (via GDAL and tempfile)
    temp.tif = paste0(tempfile(), '.tif')
    raster::writeRaster(temp.highres.tif, temp.tif)
    gdalwarp(temp.tif, dest.file, raster::crs(mask.tif), raster::crs(mask.tif), tr=raster::res(mask.tif) , r='average', te=raster::bbox(mask.tif), overwrite=TRUE)
    unlink(temp.tif)
    rm(temp.highres.tif)
    
  } else {
    
    # blockwise execution: mask.highres.tif split according to polygons in blocks.sf
    blocks.sf = st_geometry(blocks.sf)
    
    # prepare filenames for temporary storage of block rasters while using GDAL
    mosaic.temp.tif = paste0(tempfile(), '_', 1:length(blocks.sf), '.tif')
    
    if(n.cores == 1)
    {
      # serial loop over polygons in blocks.sf
      print(paste0('looping over ', length(blocks.sf), ' blocks in serial...'))
      pb = txtProgressBar(min=1, max=length(blocks.sf), style=3)
      for(idx.block in 1:length(blocks.sf))
      {
        setTxtProgressBar(pb, idx.block)
        
        # crop poly.sf to block, count number of polygons overlapping, proceed only if some polygons overlap
        poly.cropped.sf = suppressWarnings(sf::st_crop(poly.sf, blocks.sf[idx.block]))
        n.poly = nrow(poly.cropped.sf)
        
        if(n.poly > 0)
        {
          # find bounding box for cropped polygons
          poly.cropped.bbox = raster::extent(sf::as_Spatial(poly.cropped.sf))
          
          # fast presence/absence rasterization to high res grid
          temp.highres.tif = fasterize::fasterize(poly.sf, raster::crop(mask.highres.tif, poly.cropped.bbox), field=NULL, fun='any', background=0)
          
          # find bounding box in output grid for this (cropped) bounding box
          temp.highres.bbox = sf::st_bbox(raster::crop(mask.tif, poly.cropped.bbox))
          
          # downsample to reference grid to get % coverage (via GDAL and tempfile)
          temp.tif = paste0(tempfile(), '.tif')
          raster::writeRaster(temp.highres.tif, temp.tif, format='GTiff')
          gdalUtils::gdalwarp(temp.tif, mosaic.temp.tif[idx.block], raster::crs(mask.tif), raster::crs(mask.tif), tr=raster::res(mask.tif) , r='average', te=temp.highres.bbox, overwrite=TRUE)
          unlink(temp.tif)
        }
      }
      close(pb)
      
    } else {
      
      # set up parallel execution backend
      print(paste0('processing ', length(blocks.sf), ' blocks in parallel (', n.cores, ' cores)'))
      cl = snow::makeCluster(n.cores)
      doSNOW::registerDoSNOW(cl)
      
      # set up a progress bar function for .options.snow
      pb = txtProgressBar(min=1, max=length(blocks.sf), style=3)
      opts.progress = list(progress = function(n) setTxtProgressBar(pb, n))
      
      # run the parallel loop
      invisible(foreach::foreach(idx.block=1:length(blocks.sf), .options.snow=opts.progress)) %dopar% {
        
        # crop poly.sf to block, count number of polygons overlapping, proceed only if some polygons overlap
        poly.cropped.sf = suppressWarnings(sf::st_crop(poly.sf, blocks.sf[idx.block]))
        n.poly = nrow(poly.cropped.sf)
        
        if(n.poly > 0)
        {
          # find bounding box for cropped polygons
          poly.cropped.bbox = raster::extent(sf::as_Spatial(poly.cropped.sf))
          
          # fast presence/absence rasterization to high res grid
          temp.highres.tif = fasterize::fasterize(poly.sf, raster::crop(mask.highres.tif, poly.cropped.bbox), field=NULL, fun='any', background=0)
          
          # find bounding box in output grid for this (cropped) bounding box
          temp.highres.bbox = sf::st_bbox(raster::crop(mask.tif, poly.cropped.bbox))
          
          # downsample to reference grid to get % coverage (via GDAL and tempfile)
          temp.tif = paste0(tempfile(), '.tif')
          raster::writeRaster(temp.highres.tif, temp.tif, format='GTiff')
          gdalUtils::gdalwarp(temp.tif, mosaic.temp.tif[idx.block], raster::crs(mask.tif), raster::crs(mask.tif), tr=raster::res(mask.tif) , r='average', te=temp.highres.bbox, overwrite=TRUE)
          unlink(temp.tif)
        }
      }
      close(pb)
      stopCluster(cl)
    }
    
    # tidy up removed blocks, merge all remaining, writing to output file 
    print('merging blocks...')
    idx.mosaic = file.exists(mosaic.temp.tif)
    if(!any(idx.mosaic))
    {
      # if none of the blocks overlapped with any polygons, write the mask and finish
      mask.out.tif = raster::setValues(mask.tif, rep(NA, ncell(mask.tif)))
      raster::writeRaster(mask.out.tif, dest.file, overwrite=TRUE)
      return()
      
    } else {
      
      # finish by merging all files in mosaic list
      gdalUtils::mosaic_rasters(mosaic.temp.tif[idx.mosaic], dst_dataset=dest.file)
    }
    
    # delete tempfiles
    invisible(unlink(unlist(mosaic.temp.tif)))
  }
  
  # match spatial extents, clip raster to mask, write to disk, return the RasterLayer object 
  out.tif = raster::raster(dest.file)
  out.tif = raster::mask(out.tif, out.tif, updatevalue=0, updateNA=TRUE)
  out.tif = mask(raster::crop(raster::extend(out.tif, bc.mask.tif, value=0), mask.tif, snap='near'), mask.tif)
  raster::writeRaster(out.tif, dest.file, format='GTiff', overwrite=TRUE)
  return(out.tif)
  # */ 
}

#' This works by calling `fasterize::fasterize` (with `fun='any'`) on the polygons in `poly.sf` to make a presence/absence 
#' layer at `aggr.factor` times higher resolution than `mask.tif`. This high-resolution layer is then downsampled (by averaging 
#' with `gdalwarp`) to the desired output resolution. 
#' 
#' `blocks.sf` allows large jobs to be done in parallel, by providing 
#' a partition to split the work over, and (optionally) merging everything together at the end using `gdalUtils::mosaic_rasters`. 
#' 

#' After downloading and processing each data collection, I store the metadata in a big nested list structure:
# metadata list builder for different sources
MPB_metadata = function(collection, cfg.in=NULL, cfg.src=NULL, cfg.out=NULL)
{
  # If called with 'collection' only, creates the storage directory and returns a 
  # (mostly empty) list with entries to be filled in later. If cfg.in is specified, 
  # then elements in cfg.src and/or cfg.out which are missing from cfg.in are added to 
  # the output list. 
  
  # (some code below hidden from markdown:)
  # /*
  
  # define storage directory for source files (creating it if necessary)
  subdir.src = file.path(data.dir, collection, 'source')
  if(!dir.exists(subdir.src))
  {
    dir.create(subdir.src, recursive=TRUE)
    print(paste(collection, 'subdirectory created'))
    
  } else {
  
    print(paste(collection, 'subdirectory exists'))
  }
  print(paste('source data storage:', subdir.src))
  
  # define storage directory for mapsheet files (creating it if necessary)
  subdir.block = file.path(data.dir, collection, 'blocks')
  if(!dir.exists(subdir.block))
  {
    dir.create(subdir.block, recursive=TRUE)
    print(paste(collection, 'subdirectory created'))
    
  } else {
    
    print(paste(collection, 'subdirectory exists'))
  }
  print(paste('mapsheets data storage:', subdir.block))
  
  # create the source metadata list
  temp.src = list(web = NULL,
                  fname = NULL,
                  dir = subdir.src)
  
  # create the output data metadata list
  temp.out = list(name = collection,
                  dir.block = subdir.block,
                  fname = list(shp=NULL,
                               tif=list(full=NULL, block=NULL)),
                  code = NULL)
  
  # update these lists as needed
  if(!is.null(cfg.in)) {

    # create modified version of cfg.src...
    if(is.null(cfg.src)) {
      
      cfg.src = modifyList(temp.src, cfg.in$src, keep.null=TRUE)
      
    } else {
      
      cfg.src = modifyList(cfg.in$src, cfg.src, keep.null=FALSE) 
      
    }
    
    # create modified version of cfg.out...
    if(is.null(cfg.out)) {
     
      cfg.out = modifyList(temp.out, cfg.in$out, keep.null=FALSE)
      
    } else {

      cfg.out = modifyList(cfg.in$out, cfg.out, keep.null=TRUE) 
      
    }
    
  } else {
    
    # nothing to modify, return defaults
    cfg.src = temp.src
    cfg.out = temp.out
  }

  # assemble and return the list
  return(list(src=cfg.src, out=cfg.out))
  # */
}

#' This function returns a nested list of the form `list(cfg.in, cfg.src)`, where `cfg.in` is a list containing info about the source
#' urls, filenames, variable names, *etc*; and `cfg.src` contains info about the output files (post-processing). The idea is that
#' in the 'src_\<collection\>.R' script we call this once with only `collection` specified to get a template list, whose entries are then 
#' filled in as the script progresses. At the end we save this metadata to '\<collection\>.RData' in `data.dir`.
#' 

#' Each layer uses the same 
#' <a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">Albers projection and NAD83 datum</a>, 
#' and a cropped version of the grid layout in
#' <a href="http://hectaresBC.org" target="_blank">hectaresBC</a>,
#' the parameters of which are hard-coded in this convenience function:
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
  # /*
  
  # build some raster/sf objects from this information
  extent.ref = raster::extent(x=xmin, xmax=xmax, ymin=ymin, ymax=ymax)
  ref.tif = raster::raster(crs=sf::st_crs(epsg.ref)$proj4string, ext=extent.ref, res=res.ref, vals=NULL)
  
  # construct/return the list
  list(epsg = epsg.ref,
       proj4 = st_crs(epsg.ref)$proj4string,
       ext = extent.ref,
       res = res.ref,
       tif = ref.tif)
  # */
}

#' Users who wish to use a different reference system may change these parameters before running the 'src_\*.R' scripts.
#' 


#' Most of the 'src_\*.R' scripts first create the raster layers for the full BC extent, before splitting them into smaller mapsheets.
#' The following convenience function does the splitting, and returns a list of the filenames written
# automated splitting of rasters into mapsheets
MPB_split = function(cfg.in, snrc.sf) 
{
  # snrc.sf is the sf object containing the mapsheet polygons to loop over
  # The function expects cfg.in$out$fname$tif$full to be a character vector of paths to 
  # full-province raster layers. It loops over them, splitting each one (ie crop -> mask) 
  # according the polygons in snrc.sf
  
  # (some code below hidden from markdown:)
  # /*
  
  # get vector of NTS/SNRC names
  snrc.names = snrc.sf$NTS_SNRC
  
  # define paths to output mapsheets
  prefix.tif = setNames(file.path(cfg.in$out$dir.block, names(cfg.in$out$fname$tif$full)), names(cfg.in$out$fname$tif$full))
  block.paths = lapply(prefix.tif, function(varpath) setNames(paste0(varpath, '_', snrc.names, '.tif'), snrc.names))
  print(paste('writing to', cfg.in$out$dir.block, '...'))
  
  pb = txtProgressBar(min=1, max=length(snrc.names), style=3)
  for(idx.varname in 1:length(block.paths))
  {
    # load the full BC raster
    print(paste0('splitting ', cfg.in$out$fname$tif$full[idx.varname], ' into mapsheets...'))
    temp.tif = raster::raster(cfg.in$out$fname$tif$full[idx.varname])
    
    #loop over NTS/SNRC mapsheets, cropping full BC rasters and saving to disk 
    for(idx.snrc in 1:length(snrc.names))
    {
      setTxtProgressBar(pb, idx.snrc)
      dest.file = block.paths[[idx.varname]][[idx.snrc]]
      
      # find bounding box for mapsheet, crop/mask raster and save 
      block.sf = sf::st_geometry(snrc.sf[idx.snrc,])
      block.bbox = raster::extent(sf::as_Spatial(block.sf))
      cropped.temp.tif = raster::mask(raster::crop(temp.tif, block.bbox, snap='out'), sf::as_Spatial(block.sf))
      raster::writeRaster(cropped.temp.tif, dest.file, overwrite=TRUE)
    }
  }
  close(pb)
  return(block.paths)
  # */
}

#' This function could be easily modified to split over any other tiling of the BC extent.

#+ include=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('utility_functions.R'), run_pandoc=FALSE, clean=TRUE)
# ... or to html ...
# rmarkdown::render(here('utility_functions.R'))