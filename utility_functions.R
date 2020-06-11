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
dir.create(data.dir, recursive=TRUE)

#' By default this is the subdirectory 'data' relative to the location of the R project file (.../rasterbc/data). 
#' Around 60GB of data in total will be downloaded/written by the 'src_\*.R' scripts. Feel free to change this to another 
#' path (*eg.* a drive with more free space), but be careful not to assign it to to an existing directory 
#' as I do not check for existing files, so *anything already data.dir could get overwritten*.
#'
#' Some of the rasterization jobs are very time-consuming. This can be sped up by running things in parallel 

#  set the number of cores to use with doSNOW (set to 1 if doSNOW/multicore not available)
n.cores = 3
#' Rasterization of an NTS tile requires around 6GB. So with 3 cores going in parallel we need at least 18GB of RAM. 
#' If you are encountering out-of-memory errors, consider reducing 'n.cores', or changing to code to parallelize over 
#' smaller chunks (*eg.* the TRIM tiles within each NTS tile).
#' 

#' **Convenience functions**

# blockwise/parallel rasterization of big datasets
MPB_rasterize = function(poly.sf, mask.tif, dest.file, aggr.factor=10, blocks.sf=NULL, n.cores=1) 
{
  # rasterizes the input shapefile poly.sf (a POLYGON or MULTIPOLYGON) as GeoTiff written to 
  # path in dest.file (a character vector). mask.tif (a RasterLayer) provides the ouput geometry  
  # (crs, resolution, extent), and its NA values (if any) are used to mask the output (non-NA
  # are ignored).
  
  # (contents below are hidden from markdown: see utility_functions.R for details)
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
#' layer at `aggr.factor` times higher resolution than `mask.tif`. This high-res layer is then downsampled (by averaging 
#' with `gdalwarp`) to the desired output resolution. 
#' 
#' `blocks.sf` allows large jobs to be done in parallel, by providing 
#' a partition to split the work over, and (optionally) merging everything together at the end using `gdalUtils::mosaic_rasters`. 
#' Here we process the NTS tiles 3 at a time (`n.cores`=3), and theres no need to merge the result because this tiling is how we 
#' want the data split up in the end.

#+ echo=FALSE
# Convert to markdown by running the following line (uncommented)...
# rmarkdown::render(here('utility_functions.R'), run_pandoc=FALSE, clean=TRUE)
# rmarkdown::render(here('utility_functions.R'))