---
title: "src_pine.R"
author: "Dean Koch"
date: "June 16, 2020"
output: github_document
---


Forest attributes model output from Beaudoin *et al.*
(<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2013-0401" target="_blank">2014</a>, 
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2017-0184" target="_blank">2017</a>), based on
interpolations of Canada’s <a href="https://nfi.nfis.org/en/" target="_blank">National Forest Inventory</a> (NFI) photoplots
and various remotely sensed datasets.

This script follows the same template as 'src_dem.R'. For more detail, see comments in 'src_dem.knit.md'



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
collection = 'pine'
cfg = MPB_metadata(collection)
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))
```


**source information**

The National Forest Inventory uses photo-interpreted polygons to classify the landscape by vegetation type. This, and other 
remote sensing datasets relating to vegetation, topography and climatology, such as 
<a href="https://modis.gsfc.nasa.gov/data/" target="_blank">MODIS</a>, and 
<a href="https://landsat.gsfc.nasa.gov/data/" target="_blank">Landsat</a>, 
can be used to inform interpolation-based models of forest inventory. The model of 
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2017-0184" target="_blank">Beaudoin *et al.* (2017)</a>
uses knn-interpolation to construct Canada-wide predictions of forest attributes in two years, 2001 and 2011. It is an
updated version of the predictions from an earlier CJFR publication,
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2013-0401" target="_blank">Beaudoin *et al.* (2014)</a>.

This script downloads the full datasets, transforms them to align with our grid, clips to the BC extent, and extracts a subset of 
attributes most relevant to mountain pine beetle activity. Note that these data are referenced to a MODIS grid 
(<a href="https://www.spatialreference.org/ref/sr-org/8787/html/" target="_blank">NAD83 / Lambert Conformal Conic</a>), 
so we have to transform (warp) them to our coordinate reference system
(<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a>).

Layers `veg` and `vegTreed` estimate the percent area that is vegetated or treed (respectively), within the grid cell covered by a given
pixel; `needle` estimates the % of the area represented by `vegTreed` that is covered by needle-leafed species; and the individual `pinus*`
layers estimate the percent of `needle` represented by the species indicated in the 3-letter suffix (*eg.* `pinusCon` indicates
*Pinus contorta*, and `pinusSpp` indicates undetermined *Pinus* species). Layer `age` estimates the (typical) age of members of the leading 
species.

A more detailed description of the model development and data definitions can be found in the two publications linked above, and at the
<a href="https://open.canada.ca/data/en/dataset/ec9e2659-1c29-4ddb-87a2-6aced147a990" target="_blank">Open Canada Metadata page</a>.
Download links to the source files can be found
<a href="https://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/canada-forests-attributes_attributs-forests-canada/" target="_blank">here</a>
(as of June, 2020).

The <a href="https://open.canada.ca/en/open-government-licence-canada" target="_blank">Open Government Licence - Canada</a> applies. 



```r
# define the source metadata
cfg.src = list(
  
  # urls to download from
  web = c(yr2001 = 'http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/canada-forests-attributes_attributs-forests-canada/2001-attributes_attributs-2001/', 
          yr2011 = 'http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/canada-forests-attributes_attributs-forests-canada/2011-attributes_attributs-2011/'),
  
  # character vectors naming the years selected
  years = c(yr2001 = '2001',
            yr2011 = '2011'),
  
  # all files are of form: <fname.prefix><year><feat.name><fname.suffix>
  fname.prefix = 'NFI_MODIS250m_',
  fname.suffix = '_v1.tif',
  feat.name = c(veg = '_kNN_LandCover_Veg',
                vegTreed = '_kNN_LandCover_VegTreed',
                needle = '_kNN_SpeciesGroups_Needleleaf_Spp',
                age = '_kNN_Structure_Stand_Age',
                pinusAlb = '_kNN_Species_Pinu_Alb',
                pinusBan = '_kNN_Species_Pinu_Ban',
                pinusCon = '_kNN_Species_Pinu_Con',
                pinusMon = '_kNN_Species_Pinu_Mon',
                pinusPon = '_kNN_Species_Pinu_Pon',
                pinusRes = '_kNN_Species_Pinu_Res',
                pinusSpp = '_kNN_Species_Pinu_Spp',
                pinusStr = '_kNN_Species_Pinu_Str',
                pinusSyl = '_kNN_Species_Pinu_Syl')
)
```

```r
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)
```

We build a list of URLs to download from, and set up the full-extent output filenames before proceeding: 


```r
# set up the source filenames, urls, and full-extent output filenames
varnames = setNames(nm=names(cfg$src$feat.name))
src.filenames = lapply(cfg$src$years, function(year) setNames(paste0(cfg$src$fname.prefix, year, cfg$src$feat.name, cfg$src$fname.suffix), varnames)) 
cfg$src$web = lapply(setNames(nm=names(cfg$src$years)), function(year) setNames(paste0(cfg$src$web[year], src.filenames[[year]]), varnames))
cfg$src$fname = lapply(cfg$src$years, function(year) setNames(paste0(file.path(cfg$src$dir, cfg$src$fname.prefix), year, cfg$src$feat.name, cfg$src$fname.suffix), varnames)) 
cfg$out$fname$tif$full = lapply(cfg$src$years, function(year) setNames(file.path(data.dir, cfg$out$name, year, paste0(varnames, '_std_', year, '.tif')), varnames))
```

To help keep the data files organized, whenever there are multiple years associated with a dataset, we store the corresponding
year-specific layers in separate subfolders of `file.path(data.dir, collection)` and `file.path(data.dir, collection, 'blocks')`. 
These are created automatically in the call to `MPB_metadata` whenever the named list element `years` exists in the `cfg$src` or 
`cfg.src` arguments (see 'utility_functions.R' for details); *eg.* here we have two subfolders, corresponding to the layers for 
2001 and 2011.

**downloads**

26 large shapefiles are downloaded here: 13 attributes for each of the two years, covering all of Canada (1.9 GB total).
Once these files are downloaded/extracted, the script will use the existing ones instead of downloading it all again (unless
`force.download` is set to `TRUE`) 


```
## [1] "using existing source files:"
## $yr2001
##                                                                                               veg 
##                "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_LandCover_Veg_v1.tif" 
##                                                                                          vegTreed 
##           "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_LandCover_VegTreed_v1.tif" 
##                                                                                            needle 
## "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_SpeciesGroups_Needleleaf_Spp_v1.tif" 
##                                                                                               age 
##          "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Structure_Stand_Age_v1.tif" 
##                                                                                          pinusAlb 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Alb_v1.tif" 
##                                                                                          pinusBan 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Ban_v1.tif" 
##                                                                                          pinusCon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Con_v1.tif" 
##                                                                                          pinusMon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Mon_v1.tif" 
##                                                                                          pinusPon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Pon_v1.tif" 
##                                                                                          pinusRes 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Res_v1.tif" 
##                                                                                          pinusSpp 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Spp_v1.tif" 
##                                                                                          pinusStr 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Str_v1.tif" 
##                                                                                          pinusSyl 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2001_kNN_Species_Pinu_Syl_v1.tif" 
## 
## $yr2011
##                                                                                               veg 
##                "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_LandCover_Veg_v1.tif" 
##                                                                                          vegTreed 
##           "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_LandCover_VegTreed_v1.tif" 
##                                                                                            needle 
## "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_SpeciesGroups_Needleleaf_Spp_v1.tif" 
##                                                                                               age 
##          "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Structure_Stand_Age_v1.tif" 
##                                                                                          pinusAlb 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Alb_v1.tif" 
##                                                                                          pinusBan 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Ban_v1.tif" 
##                                                                                          pinusCon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Con_v1.tif" 
##                                                                                          pinusMon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Mon_v1.tif" 
##                                                                                          pinusPon 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Pon_v1.tif" 
##                                                                                          pinusRes 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Res_v1.tif" 
##                                                                                          pinusSpp 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Spp_v1.tif" 
##                                                                                          pinusStr 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Str_v1.tif" 
##                                                                                          pinusSyl 
##             "H:/git-MPB/rasterbc/data/pine/source/NFI_MODIS250m_2011_kNN_Species_Pinu_Syl_v1.tif"
```


**processing**




```r
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])
```

First, clip each layer to BC, warp to Albers, and write this full-province raster to disk (3.46 GB total).
This involves a lot of big read/write operations, so expect it to take about 15-30 minutes to complete.


```r
# loop over years and attributes to process each geotiff one at a time
print('warping/clipping pine layers...')
pb = txtProgressBar(min=1, max=length(unlist(cfg$out$fname$tif$full)), style=3)
for(idx.yr in 1:length(cfg$src$years))
{
  for(idx.tif in 1:length(cfg$src$feat.name))
  {
    setTxtProgressBar(pb, idx.tif + (idx.yr-1)*length(cfg$src$feat.name))
    src.filename = cfg$src$fname[[idx.yr]][[idx.tif]]
    dest.filename = cfg$out$fname$tif$full[[idx.yr]][idx.tif]

    # crop input layer to BC border extent (after reprojecting that polygon)
    temp.tif = raster::raster(src.filename)
    temp.crs = raster::crs(temp.tif)
    prov.reprojected.sf = sf::st_transform(prov.sf, temp.crs)
    temp.tif = raster::crop(temp.tif, prov.reprojected.sf, snap='out')
    
    # write this temporary layer to disk (in original MODIS projection), then delete from memory
    temp.path = paste0(tempfile(), '.tif')
    raster::writeRaster(temp.tif, temp.path)
    rm(temp.tif)
    
    # warp raster data to reference system (via tempfile and external GDAL call), saving to disk
    gdalUtils::gdalwarp(srcfile=temp.path, 
                        dstfile=dest.filename, 
                        s_srs=temp.crs, 
                        t_srs=raster::crs(bc.mask.tif), 
                        tr=raster::res(bc.mask.tif), 
                        r='bilinear', 
                        te=raster::bbox(bc.mask.tif),
                        overwrite=TRUE, 
                        verbose=FALSE)

    # delete tempfile from disk, reload new version, compute min/max stats, clip to mask, overwrite on disk
    unlink(temp.path)
    temp.tif = raster::mask(raster::setMinMax(raster::raster(dest.filename)), bc.mask.tif)
    raster::writeRaster(temp.tif, dest.filename, overwrite=TRUE)
    rm(temp.tif)
  }
}
close(pb)
```

The individual `pinus*` layers predict abundance by species. It can be more useful to have an aggregate quantity,
the proportion of needle-leafed trees from genus *Pinus* (*eg.* to represent the density of hosts vulnerable to mountain 
pine beetle). This is simply the sum of all the `pinus*` layers. We compute that sum below, saving the result as a new layer, 
`pinusTotal` for each year (618 MB total). Expect this to take about 15-20 minutes



```r
# add the new filenames to the metadata list
varnames['pinusTotal'] = 'pinusTotal'
cfg$out$fname$tif$full = lapply(cfg$src$years, function(year) setNames(file.path(data.dir, cfg$out$name, year, paste0(varnames, '_std_', year, '.tif')), varnames))

# create new layer that is the sum of all individual Pinus species layers
# identify all the pinus* layers
idx.pinus = startsWith(varnames, 'pinus') & varnames != 'pinusTotal'
idx.total = varnames == 'pinusTotal'
```

```r
# outer loop over years
print('summing pinus layers...')
pb = txtProgressBar(min=1, max=length(cfg$src$years)*sum(idx.pinus), style=3)
for(idx.yr in 1:length(cfg$src$years))
{
  # filenames to read/write
  src.filenames = cfg$out$fname$tif$full[[idx.yr]][idx.pinus]
  dest.filename = cfg$out$fname$tif$full[[idx.yr]][idx.total]
  
  # create base layer of zeros and NAs (bc.mask.tif has 1's everywhere that is non-NA)
  temp.tif = raster::mask(bc.mask.tif, bc.mask.tif, maskvalue=1, updatevalue=0)
  
  # inner loop over Pinus species layers 
  for(idx.layer in 1:sum(idx.pinus))
  {
    setTxtProgressBar(pb, idx.layer + (idx.yr-1)*sum(idx.pinus))

    # add the individual Pinus species layer to the total
    temp.tif = temp.tif + raster::raster(src.filenames[[idx.layer]])
  }
  
  # correction if we exceed 100%: raster::mask() trick is faster than square-bracket indexing
  temp.tif = mask(temp.tif, temp.tif > 100, maskvalue=1, updatevalue=100)

  # write raster to disk, remove tempfile from memory
  raster::writeRaster(temp.tif, dest.filename, overwrite=TRUE)
  rm(temp.tif)
}
close(pb)
```

While the above can also be done more simply using the `raster::overlay` function (bundling all pinus* layers into a `rasterBrick`), 
I have found this to be slower and more prone to out-of-memory issues than simply looping over the layers.

Finally, we split all layers up into mapsheets corresponding to the NTS/SNRC codes (4.16 GB total). Expect this to take around 15-20 minutes


```r
# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)
```

Notice that the `MPB_metadata` function detects the `years` entry in `cfg$src`, and automatically loops over 
each year (calling itself with the appropriately modified `cfg.in` argument). The resulting entries of 
`cfg$out$fname$tif$block` are named to match `cfg$src$years`, and each file written to disk is 
assigned a year suffix in addition to the NTS/SNRC mapsheet code (*ie.* they are of the form 
'\<varname\>_\<year\>_\<mapsheet\>.tif').

A tidier solution to dealing with both spatial *and* temporal indices is to bundle all of the year-referenced
layers of a given variable together, into a multiband geotiff (represented in R as a `rasterBrick`), with one
band per year. However I have found these files awkward to deal with in R, and the filesizes of the time-series data
(fires, cutblocks, insect damage) increases substantially (by around 18X).



```r
# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
```

```
## [1] "pine source subdirectory exists"
## [1] "source data storage: H:/git-MPB/rasterbc/data/pine/source"
## [1] "pine mapsheets subdirectory exists"
## [1] "mapsheets data storage: H:/git-MPB/rasterbc/data/pine/blocks"
## [1] "pine yearly subdirectories exist"
## [1] "yearly data storage:"
## [1] "H:/git-MPB/rasterbc/data/pine/2001" "H:/git-MPB/rasterbc/data/pine/2011"
## [1] "pine yearly (blockwise) subdirectories exist"
## [1] "yearly (blockwise) data storage:"
## [1] "H:/git-MPB/rasterbc/data/pine/blocks/2001" "H:/git-MPB/rasterbc/data/pine/blocks/2011"
```

```r
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'pine.rds' located in `data.dir` using `readRDS()`.



