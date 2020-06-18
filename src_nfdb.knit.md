---
title: "src_nfdb.R"
author: "Dean Koch"
date: "June 18, 2020"
output: github_document
---

Canadian National Fire Database (NFDB) 2001-2018, from Natural Resources Canada.




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
collection = 'nfdb'
cfg = MPB_metadata(collection)
cfg.filename = file.path(data.dir, paste0(collection, '.rds'))
```


**source information**

The <a href="https://cwfis.cfs.nrcan.gc.ca/ha/nfdb">NFDB</a> is a collection
of wildfire perimeter records from various Canadian fire management agencies, including provinces, 
territories, and Parks Canada, covering all of Canada. 

Metadata are summarized in this 
<a href="https://cwfis.cfs.nrcan.gc.ca/downloads/nfdb/fire_poly/current_version/NFDB_poly_20190607_metadata.pdf">PDF link</a>,
and more details can be found in the file 'NFDB_poly_20190607_metadata.pdf' which is part of the zip archive downloaded and extracted 
to the 'nfdb/source' subdirectory of `data.dir`.

The data are published under an access only license
(<a href="https://cwfis.cfs.nrcan.gc.ca/downloads/nfdb/fire_poly/current_version/NFDB_EN_End-User%20Agreement.pdf">PDF link</a>)
by *the Canadian Forest Service (2019), National Fire Database – Agency FireData.
Natural Resources Canada, Canadian Forest Service, Northern Forestry Centre, Edmonton, Alberta*.
<a href="https://cwfis.cfs.nrcan.gc.ca/ha/nfdb">https://cwfis.cfs.nrcan.gc.ca/ha/nfdb</a>.
 
This script extracts all polygons intersecting with the province of BC, rasterizes them to our reference grid, and 
saves the results. That subset of the database comes (mainly) from the BC Ministry of Forests, Lands and Natural Resource 
Operations - BC Wildfire Service, for which the
<a href="https://www2.gov.bc.ca/gov/content/data/open-data/open-government-licence-bc" target="_blank">Open Government Licence - British Columbia</a>
applies. Note that while this collection contains records for BC all the way back to 1917, we extract only the period 2001-2018. This can be changed 
by adjusting the list element `cfg.src$years`, below.



```r
# define the source metadata
cfg.src = list(
  
  # url for the zip archive
  web = 'https://cwfis.cfs.nrcan.gc.ca/downloads/nfdb/fire_poly/current_version/NFDB_poly.zip',
  
  # filename for the gdb geometry table (actually a directory) 
  fname = 'NFDB_poly_20190607.shp',
  
  # feature names to save (note ESRI driver used by GDAL has weird abbreviation behaviour)
  feat.name = c(year = 'YEAR'),
  
  # character vectors naming the years to extract
  years = setNames(2001:2018, nm=paste0('yr', 2001:2018))
)
```

```r
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

# set up the source and full-extent output filenames
cfg$src$fname = c(fire=file.path(cfg$src$dir, cfg$src$fname))
cfg$out$fname$shp = c(fire=paste0(file.path(data.dir, cfg$out$name, collection), '_std.shp'))
cfg$out$fname$tif$full = lapply(cfg$src$years, function(year) c(fire=file.path(data.dir, cfg$out$name, year, paste0('nfdb_std_', year, '.tif'))))
```

**downloads**

The zip archive (374 MB) contains a shapefile (1 GB uncompressed), a simplified copy of which is saved to the `data.dir` subdirectory in the 
reference projection. Once all files are downloaded/extracted, the script will use existing ones instead of downloading everything again 
(unless `force.download` is set to `TRUE`) 


```r
# check if any of the rasters need to be downloaded again:
idx.todownload = sapply(unlist(cfg$src$fname), function(fname) ifelse(force.download, TRUE, !file.exists(fname)))
if(any(idx.todownload))
{
  # download the zip to temporary file (374 MB), extract to disk
  nfdb.tmp = tempfile('nfdb_temp', cfg$src$dir, '.zip')
  download.file(url=cfg$src$web, destfile=nfdb.tmp, mode='wb')
  nfdb.paths = unzip(nfdb.tmp, exdir=cfg$src$dir)
  unlink(nfdb.tmp) 
  
} else {
  
  print('using existing source files:') 
  print(cfg$src$fname)
}
```


**processing**

Start by opening the database and extracting the desired subset, saving a copy to disk (19 MB)


```r
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])

# load fires shapefile, crop to BC boundary, retain only the specified years, drop 'Z' dimension
nfdb.canada.sf = sf::st_read(cfg$src$fname)
prov.reprojected.sf = sf::st_transform(prov.sf, sf::st_crs(nfdb.canada.sf))
nfdb.bc.idx = c(sf::st_intersects(sf::st_geometry(prov.reprojected.sf), sf::st_geometry(nfdb.canada.sf), sparse=FALSE))
nfdb.years.idx = unlist(sf::st_drop_geometry(nfdb.canada.sf[, cfg$src$feat.name])) %in% 2001:2018
nfdb.sf = st_zm(sf::st_transform(nfdb.canada.sf[nfdb.bc.idx & nfdb.years.idx, ], sf::st_crs(prov.sf)), drop=TRUE, what='ZM')
rm(nfdb.canada.sf)

# omit all attributes except YEAR, rename columns
nfdb.sf = nfdb.sf[, cfg$src$feat.name]
names(nfdb.sf) = c(names(cfg.src$feat.name), 'geometry')
sf::st_geometry(nfdb.sf) = 'geometry'

# write cropped shapefile to disk (19 MB), reload it
sf::st_write(nfdb.sf, cfg$out$fname$shp, append=FALSE)
nfdb.sf = sf::st_read(cfg$out$fname$shp)
```

Next we rasterize the contents, producing a numeric layer in each year indicating 
the proportion of the area in each grid cell covered by wildfire perimeter polygons (total size 227 MB).
Expect this to take around 60-90 minutes.




```r
# rasterize polygons by year (outer loop), with parallel execution over SNRC blocks
n.years.nfdb = length(cfg$src$years)
pb.outer = txtProgressBar(min=1, max=n.years.nfdb, style=3)
for(idx.year in 1:n.yrs.nfdb)
{
  # define output filename and print some progress info for the user 
  year = cfg$src$years[idx.year]
  year.string = names(cfg$src$years)[idx.year]
  print(paste0('processing year ', year, ' (', idx.year, ' of ', n.years.nfdb, ')'))
  setTxtProgressBar(pb.outer, idx.year)
  dest.file = cfg$out$fname$tif$full[[year.string]]
  
  # identify all of the polygons in this particular year
  idx.nfdb.year = unlist(sf::st_drop_geometry(nfdb.sf[, names(cfg$src$feat.name)])) == year
  
  # call the rasterization helper function to run this job in parallel
  MPB_rasterize(nfdb.sf[idx.nfdb.year, ], bc.mask.tif, dest.file, aggr.factor=10, blocks.sf=snrc.sf, n.cores)
}
close(pb.outer)
```

Finally, we split all layers up into mapsheets corresponding to the NTS/SNRC codes (365 MB total). Expect this to take around 15-25 minutes


```r
# function call to crop and save blocks
cfg.blocks = MPB_split(cfg, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=cfg.blocks))))
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'nfdb.rds' located in `data.dir` using `readRDS()`.



