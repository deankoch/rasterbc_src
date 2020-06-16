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
updated version of the predictions from an 
<a href="https://www.nrcresearchpress.com/doi/full/10.1139/cjfr-2013-0401" target="_blank">earlier CJFR publication</a>.

This script downloads the full datasets, transforms them to align with our grid, clips to the BC extent, and extracts a subset of 
attributes most relevant to mountain pine beetle activity. Note that these data are referenced to the original MODIS grid 
(<a href="https://www.spatialreference.org/ref/sr-org/8787/html/" target="_blank">NAD83 / Lambert Conformal Conic</a>), 
so we have to transform (warp) them to our coordinate reference system
(<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a>).
A more detailed description of the model development and data sources can be found in the two publications linked above, and at the
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
cfg$out$fname$tif$full = lapply(cfg$src$years, function(year) setNames(file.path(data.dir, cfg$out$name, paste0(varnames, '_std_', year, '.tif')), varnames))
```

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

First, clip each layer to BC and write this full-province raster to disk in a temporary file (1.7 GB):


```r
# load the gigantic source raster, note GDAL warning about the outdated PROJ string
temp.tif = paste0(tempfile(), '.tif')
pine.tif = raster::raster(cfg$src$fname$yr2001['veg'])
```

```r
# crop to BC using a fast GDAL translate operation via tempfile
pine.bbox = st_bbox(sf::st_transform(prov.sf, raster::crs(pine.tif)))
gdalUtils::gdal_translate(src_dataset=cfg$src$fname['pine'], 
                          dst_dataset=temp.tif, 
                          projwin=pine.bbox[c('xmin', 'ymax', 'xmax', 'ymin')])
```

Next, warp the pine using fast GDAL warp call, save to disk (859 MB), delete tempfile


```r
# reload pine raster with smaller cropped version, then warp
pine.tif = raster::raster(temp.tif)
gdalUtils::gdalwarp(srcfile=temp.tif, 
                    dstfile=cfg$out$fname$tif$full['pine'], 
                    s_srs=raster::crs(pine.tif), 
                    t_srs=raster::crs(bc.mask.tif), 
                    tr=raster::res(bc.mask.tif), 
                    r='bilinear', te=raster::bbox(bc.mask.tif), 
                    overwrite=TRUE, 
                    verbose=TRUE)
```

With large data files, these (external) GDAL calls are much faster than using package `raster`.
Here (and anywhere else a warp is done) I use bilinear interpolation to assign values to grid-points. Note that, 
wherever possible, it is best to avoid warping (a kind of raster-to-raster reprojection), because it is a lossy 
operation, introducing a new source of error. 


```r
# reload pine, compute min/max stats, clip to mask, rewrite to disk (415 MB)
```

```r
bc.pine.tif = raster::mask(raster::setMinMax(raster::raster(cfg$out$fname$tif$full['pine'])), bc.mask.tif)
raster::writeRaster(bc.pine.tif, cfg$out$fname$tif$full['pine'], overwrite=TRUE)
unlink(temp.tif)
```

Finally, split these layers up into mapsheets corresponding to the NTS/SNRC codes (228 MB)


```r
# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'pine.rds' located in `data.dir` using `readRDS()`.



