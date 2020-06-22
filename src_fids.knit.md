---
title: "src_fids.R"
author: "Dean Koch"
date: "June 18, 2020"
output: github_document
---

**Forest Insect and Disease Survey** (FIDS) 2001-2019, from the BC Ministry of Forests.

**license:** <a href="https://www2.gov.bc.ca/gov/content/data/open-data/open-government-licence-bc" target="_blank">Open Government Licence - British Columbia</a>

**size on disk**: 926 MB source data, ?? written as output





**overview**

Aerial overview surveys (AOS) of forest damage due to disease and insects have been conducted yearly by federal and provincial environment
ministries for many decades. since 1999, in BC, this job has been taken over by the Ministry of Forests and data collection protocols have 
become more consistent. These data are <a href="https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/">made available online</a>
each year, providing a time series on mountain pine beetle activity covering a large geographical extent. 

This script extracts polygons corresponding to the four major bark beetle pests in BC, keeping the subset of data for the years specified in 
`cfg$src$years`. It then rasterizes these data to our reference grid, and saves the results. This collection also contains records all the way back to 
the early 1900s (collected by the Canadian Forest Service), and includes a large number of other forest pests and diseases. We extract only the period 
2001-2019, and the damage polygons for: mountain pine beetle ('IBM'), spruce beetle ('IBS'), Douglas-fir beetle ('IBD'), and western balsam bark beetle 
('IBB'). This can be changed by adjusting the list elements `cfg.src$years`, and `cfg.src$spp.codes`, below. In total, we process 656,550 features.
 
Polygon and point data up to 2016 have been consolidated and archived into a single zip file
(see the <a href="https://catalogue.data.gov.bc.ca/dataset/pest-infestation-polygons">BC Data Catalogue</a> entry).
Years 2017, 2018, 2019 must be downloaded from their 
<a href="https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/">individual directories</a>, 
where point and polygon data are stored separately. Metadata and survey protocols can be found
<a href="https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/Data_stds/">here</a>.

**metadata**

We start by defining the source metadata needed to download, parse, and organize everything:



```r
# define the source metadata
cfg.src = list(
  
  # url for the zip archive (historical), and web directories to look for more recent years
  web = list(pre2017 = 'https://pub.data.gov.bc.ca/datasets/450b67bb-02d5-4526-8bc0-ac7924125a1e/pest_infestation_poly.zip',
             yr2017 = 'https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/2017/Final%20Dataset/',
             yr2018 = 'https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/2018/shapefiles/',
             yr2019 = 'https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/2019/spatial_data/'),
  
  # filenames for historical gdb geometry tables, and filename info for more recent shapefiles 
  fname = list(pre2017 = c(gdb = 'pest_infestation_poly.gdb'),
               yr2017 = list(prefix = 'FHF_2017',
                             suffix = c(spot = '_Spot',
                                        poly = '_Poly'),
                             ext = c(dbf = '.dbf', 
                                     prj = '.prj',
                                     shp = '.shp', 
                                     shx = '.shx')),
               yr2018 = list(prefix = 'AOS_2018',
                             suffix = c(spot = '_Spot_Jan21',
                                        poly = '_Poly_Jan21'),
                             ext = c(dbf = '.dbf',
                                     prj = '.prj',
                                     shp = '.shp',
                                     shx = '.shx')),
               yr2019 = list(prefix = 'AOS_2019',
                             suffix = c(spot = '_Spots',
                                        poly = '_Polygons'),
                             ext = c(dbf = '.dbf',
                                     prj = '.prj',
                                     sbn = '.sbn',
                                     sbx = '.sbx', 
                                     shp = '.shp',
                                     shx = '.shx'))),
  
  # feature names to save (ESRI driver + bug in GDAL abbreviates to 7 characters)
  feat.name = list(pre2017 = c(severity = 'PEST_SEVERITY_CODE',
                                species = 'PEST_SPECIES_CODE',
                                year = 'CAPTURE_YEAR'),
                   recent = c(severity = 'SEVERITY',
                              species = 'FHF', 
                              year = 'YEAR')),
  
  # character vectors naming the years to extract
  years = setNames(2001:2019, nm=paste0('yr', 2001:2019)),
  
  # pest severity codes to save
  sev.codes = list(pre2004 = c(light = 'L',
                               moderate = 'M',
                               severe = 'S'),
                   post2003 = c(trace = 'T',
                                light = 'L',
                                moderate = 'M',
                                severe = 'S',
                                verysevere = 'V')),
  
  # minimum, maximum, and midpoints of severity % values
  sev.stats = list(pre2004 = list(light = c(min=0, mid=5.5, max=10)/100,
                                  moderate = c(min=10, mid=20, max=30)/100,
                                  severe = c(min=30, mid=65, max=100)/100),
                   post2003 = list(trace = c(min=0, mid=0.5, max=1)/100,
                                   light = c(min=1, mid=5, max=10)/100,
                                   moderate = c(min=10, mid=20, max=30)/100,
                                   severe = c(min=30, mid=40, max=50)/100,
                                   verysevere = c(min=50, mid=75, max=100)/100)),
  
  # pest species codes to evaluate (currently bark beetles only)
  spp.codes = c(IBM = 'IBM', # mountain pine beetle 
                IBS = 'IBS', # spruce beetle
                IBD = 'IBD', # Douglas-fir beetle
                IBB = 'IBB') # western balsam bark beetle
)
```

Notice the `cfg.src` list is quite a bit more complicated here than for the other data collections, because the data collection protocols
and syntax for the database files changes from year to year. Fortunately, for years prior to 2017, the province has consolidated all datasets 
into a single ESRI geodatabase (the zip archive, downloaded below). This script will combine all years into single ESRI shapefile.


```r
# update the metadata list
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.src=cfg.src)

# set up the source filenames
cfg$src$fname$pre2017 = file.path(cfg$src$dir, cfg$src$fname$pre2017)
years.recent = names(cfg$src$fname)[names(cfg$src$fname) != 'pre2017']
for(year in years.recent)
{
  # stitch together <prefix><suffix><ext> for web urls and source filenames on disk
  types = cfg$src$fname[[year]]$suffix
  fname.temp = setNames(lapply(types, function(type) paste0(cfg$src$fname[[year]]$prefix, type, cfg$src$fname[[year]]$ext)), names(types))
  cfg$src$web[[year]] = lapply(fname.temp, function(type) setNames(paste0(cfg$src$web[[year]], type), names(cfg$src$fname[[year]]$ext)))
  cfg$src$fname[[year]] = lapply(fname.temp, function(type) setNames(file.path(cfg$src$dir, type), names(cfg$src$fname[[year]]$ext)))
}
```

The data collection methods for the FIDS have evolved over time. In the period 1999-2003, operators would use a 3-level classification
system (L, M, S); Since 2004, two additional categories (T, V) have been added (as defined in the list elements of `cfg$src$sev.codes`). 
Thus we aggregate the severity layers differently for the period 2001-2003, and 2004-2019, as defined in the list elements of
`cfg$src$sev.stats`. 
  
To rasterize these data, we will first rasterize (and save to disk) each severity level separately, producing a binary raster indicating 
coverage of the pixel by any polygon of a given severity. We then flatten these layers together, by assigning to each pixel the minimum,
midpoint, or maximum of the intervals specified in `cfg$src$sev.stats`. Thus in the years 2001-2003, we construct 6 different layers per 
year: 


```r
# define the two distinct data collection periods
idx.pre2004 = cfg$src$years %in% 2001:2003
idx.post2003 = !idx.pre2004

# define names of variables to extract/construct as output
varname.pre2004 = c(names(cfg$src$sev.codes[['pre2004']]), names(cfg$src$sev.stats[['pre2004']][[1]]))
varname.pre2004 = setNames(nm=varname.pre2004)

# nested lapply to build filename tree for 2001-2003
fname.pre2004 = lapply(cfg$src$years[idx.pre2004], function(year) {
  lapply(cfg$src$spp.codes, function(spp) {
    lapply(varname.pre2004, function(var) { 
      file.path(data.dir, collection, year, paste0(spp, '_', var, '_', year, '.tif')) 
    })
  })
})
```

(3 years) X (4 species) X (3 severity levels + 3 flattened versions) = 72 (full-extent) files


```r
print(length(unlist(fname.pre2004)))
```

```
## [1] 72
```

For the years 2004-2019 there are 5 severity levels recorded: 


```r
# repeat for 2004-2019
varname.post2003 = c(names(cfg$src$sev.codes[['post2003']]), names(cfg$src$sev.stats[['post2003']][[1]]))
varname.post2003 = setNames(nm=varname.post2003)
fname.post2003 = lapply(cfg$src$years[idx.post2003], function(year) {
  lapply(cfg$src$spp.codes, function(spp) {
    lapply(varname.post2003, function(var) { 
      file.path(data.dir, collection, year, paste0(spp, '_', var, '_', year, '.tif')) 
    })
  })
}) 
```

(16 years) X (4 species) X (5 severity levels + 3 flattened versions) = 512 (full-extent) files


```r
print(length(unlist(fname.post2003)))
```

```
## [1] 512
```

We add both segments of the time series to the `cfg` metadata list, and define a filename for the 
simplified shapefile, before moving on:
 


```r
# combine the filename lists 
cfg$out$fname$tif$full = c(fname.pre2004, fname.post2003)

# set up the filename for the output shapefile (containing all years)
cfg$out$fname$shp = c(fire=paste0(file.path(data.dir, cfg$out$name, collection), '_std.shp'))
```

**downloads**

The source data collection (926 MB total) is downloaded in pieces, and layer combined and simplified, with a copy saved to the `data.dir` subdirectory.
Once a file is downloaded/extracted, the script will reuse it instead of downloading it again (unless `force.download` is set to `TRUE`) 



```r
# check if any of the rasters need to be downloaded again:
idx.todownload = sapply(unlist(cfg$src$fname), function(fname) ifelse(force.download, TRUE, !file.exists(fname)))
if(any(idx.todownload))
{
  # download the geodatabase as needed.. 
  # (some code below hidden from markdown:)

} else {
  
  print('using existing source files:') 
  print(cfg$src$fname)
}
```

```
## [1] "using existing source files:"
## $pre2017
## [1] "H:/git-MPB/rasterbc/data/fids/source/pest_infestation_poly.gdb"
## 
## $yr2017
## $yr2017$spot
##                                                      dbf                                                      prj 
## "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Spot.dbf" "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Spot.prj" 
##                                                      shp                                                      shx 
## "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Spot.shp" "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Spot.shx" 
## 
## $yr2017$poly
##                                                      dbf                                                      prj 
## "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Poly.dbf" "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Poly.prj" 
##                                                      shp                                                      shx 
## "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Poly.shp" "H:/git-MPB/rasterbc/data/fids/source/FHF_2017_Poly.shx" 
## 
## 
## $yr2018
## $yr2018$spot
##                                                            dbf                                                            prj 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Spot_Jan21.dbf" "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Spot_Jan21.prj" 
##                                                            shp                                                            shx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Spot_Jan21.shp" "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Spot_Jan21.shx" 
## 
## $yr2018$poly
##                                                            dbf                                                            prj 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Poly_Jan21.dbf" "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Poly_Jan21.prj" 
##                                                            shp                                                            shx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Poly_Jan21.shp" "H:/git-MPB/rasterbc/data/fids/source/AOS_2018_Poly_Jan21.shx" 
## 
## 
## $yr2019
## $yr2019$spot
##                                                       dbf                                                       prj 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.dbf" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.prj" 
##                                                       sbn                                                       sbx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.sbn" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.sbx" 
##                                                       shp                                                       shx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.shp" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Spots.shx" 
## 
## $yr2019$poly
##                                                          dbf                                                          prj 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.dbf" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.prj" 
##                                                          sbn                                                          sbx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.sbn" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.sbx" 
##                                                          shp                                                          shx 
## "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.shp" "H:/git-MPB/rasterbc/data/fids/source/AOS_2019_Polygons.shx"
```


**processing**

Start by opening the historical database and extracting the desired subset (2001-2016)


```r
# reload the bc borders shapefile and mask
prov.sf = sf::st_read(cfg.borders$out$fname$shp['prov'])
bc.mask.tif = raster::raster(cfg.borders$out$fname$tif$full['prov'])

# load historical geodatabase, verify projection, drop unneeded features and fields, rename fields
fids.sf = sf::st_transform(sf::st_read(cfg$src$fname['pre2017']), sf::st_crs(prov.sf))
idx.fids.yr = unlist(sf::st_drop_geometry(fids.sf[, which(names(fids.sf) == cfg$src$feat.name$pre2017['year'])])) %in% cfg$src$years
idx.fids.spp = unlist(sf::st_drop_geometry(fids.sf[, which(names(fids.sf) == cfg$src$feat.name$pre2017['species'])])) %in% cfg$src$spp.codes 
fids.sf = fids.sf[idx.fids.yr & idx.fids.spp, cfg$src$feat.name$pre2017]
names(fids.sf) = c(names(cfg$src$feat.name$pre2017), 'geometry')
sf::st_geometry(fids.sf) = 'geometry'
```

The more recent years (2017-2019) are now loaded one at a time and appended to `fids.sf`, with spot data
being converted to circular polygons, rated 'severe', with radii determined by the `SPOT_AREA` field. See the 
<a href="https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/Data_stds/AOS%20Standards%202019.pdf">AOS Standards 2019</a>
guide for more info on this conversion. Expect this to take 5 minutes or so.


```r
# read in and append the recent years
recent.years = names(cfg$src$fname)[names(cfg$src$fname) != 'pre2017']
for(year in recent.years)
{
  # read in polygons and omit all but geometry and forest health factor (species) columns
  poly.recent.sf = sf::st_transform(sf::st_read(cfg$src$fname[[year]][['poly']][['shp']]), sf::st_crs(prov.sf))
  colnum.spp = which(names(poly.recent.sf) == cfg$src$feat.name$recent['species'])
  idx.fids.spp = unlist(sf::st_drop_geometry(poly.recent.sf[, colnum.spp])) %in% cfg$src$spp.codes 
  poly.recent.sf = poly.recent.sf[idx.fids.spp, names(poly.recent.sf) %in% cfg$src$feat.name$recent]
  
  # rename columns and append to historical data
  order.colnames = match(names(poly.recent.sf), c(cfg$src$feat.name$recent, 'geometry'))
  names(poly.recent.sf) = c(names(cfg$src$feat.name$recent), 'geometry')[order.colnames]
  sf::st_geometry(poly.recent.sf) = 'geometry'
  fids.sf = rbind(fids.sf, poly.recent.sf)
  
  # read in spots, retain only the species of interest
  spot.recent.sf = sf::st_transform(sf::st_read(cfg$src$fname[[year]][['spot']][['shp']]), sf::st_crs(prov.sf))
  colnum.spp = which(names(spot.recent.sf) == cfg$src$feat.name$recent['species'])
  idx.fids.spp = unlist(sf::st_drop_geometry(spot.recent.sf[, colnum.spp])) %in% cfg$src$spp.codes 
  spot.recent.sf = spot.recent.sf[idx.fids.spp,]
  
  # convert point data to polygon circles (SPOT_AREA in m^2)
  spot.radii = sqrt(1e4*spot.recent.sf$SPOT_AREA/pi)
  for(spot.radius in unique(spot.radii))
  {
    # st_buffer creates a circle centered at each point
    temp.sf = sf::st_buffer(spot.recent.sf[spot.radii==spot.radius, cfg$src$feat.name$recent], dist=spot.radius)
    
    # rename the columns to match fids.sf, append
    order.colnames = match(names(temp.sf), c(cfg$src$feat.name$recent, 'geometry'))
    names(temp.sf) = c(names(cfg$src$feat.name$recent), 'geometry')[order.colnames]
    sf::st_geometry(temp.sf) = 'geometry'
    fids.sf = rbind(fids.sf, temp.sf)
  }
  
}
```

Now that all of the data are merged into `fids.sf`, we can save to a single ESRI shapefile (1.89 GB)


```r
# write shapefile with selected polygons/features to disk, reload 
sf::st_write(fids.sf, cfg$out$fname$shp, append=FALSE)
fids.sf = sf::st_read(cfg$out$fname$shp)
```

Next, rasterize the contents, producing (for each combination of year, species, severity code) a numeric layer
indicating the proportion of the area in each grid cell covered by a pest damage polygon (total size 4.5 GB).
This is a lot of processing: **expect the following chunk to take around 12-16 hours to complete**.

I find that `raster::removeTmpFiles` is sometimes not working in loops, so there is a possibility of accumulating lots of 
temporary '.gri' files in the default temp directory drive (created when `raster` objects are manipulated in memory). This
will quickly fill up a hard drive. These files are automatically deleted upon ending the R session, but not during the loop.
To avoid this problem, within each loop, I set the tempfiles directory explicitly and delete it at the end. 


```r
# set tempfiles directory
fids.tempdir = tempdir()
dir.create(fids.tempdir, showWarnings=F, recursive=T)
raster::rasterOptions(tmpdir=fids.tempdir)

# rasterize polygons by pest (outer loop), severity code (middle loop), and year (inner loops), with parallel execution over SNCR blocks
n.severities = c(rep(length(cfg$src$sev.codes[['pre2004']]), sum(idx.pre2004)), rep(length(cfg$src$sev.codes[['post2003']]), sum(!idx.pre2004)))
n.years = length(unlist(cfg$src$years))
n.species = length(cfg$src$spp.codes)
pb.inner = txtProgressBar(min=1, max=sum(n.species*n.severities), style=3)
counter = 0
for(idx.year in 1:n.years)
{
  for(idx.species in 1:n.species)
  {
    for(idx.severity in 1:n.severities[idx.year])
    {
      # define attributes for this layer
      year = cfg$src$years[idx.year]
      species = cfg$src$spp.codes[idx.species]
      if(year < 2004)
      {
        severity = cfg$src$sev.codes[['pre2004']][idx.severity]
        
      } else {
        
        severity = cfg$src$sev.codes[['post2003']][idx.severity]
      }
      dest.file = cfg$out$fname$tif$full[[names(year)]][[names(species)]][[names(severity)]]
      
      # identify subset of polygons to rasterize
      idx.to.rasterize = fids.sf$year==year & fids.sf$species==species & fids.sf$severity==severity
      fids.to.rasterize.sf = fids.sf[idx.to.rasterize,]
      
      # some output on progress for the user
      counter = counter + 1
      setTxtProgressBar(pb.inner, counter)
      species.string = paste0(species, ' (', idx.species, ' of ', n.species, ')')
      severity.string = paste0(severity, ' (', idx.severity, ' of ', n.severities[idx.year], ')')
      year.string = paste0(year, ' (', idx.year, ' of ', n.years, ')')
      print(paste0('processing year ', year.string, ', species code ', species.string, ', severity code ', severity.string))
      
      # check if there are any polygons before calling the rasterization function... 
      if(nrow(fids.to.rasterize.sf) > 0)
      {
        print(paste('processing', nrow(fids.to.rasterize.sf), 'polygons...'))
        MPB_rasterize(poly.sf=fids.to.rasterize.sf, 
                      mask.tif=bc.mask.tif, 
                      dest.file=dest.file, 
                      aggr.factor=10, 
                      blocks.sf=snrc.sf, 
                      n.cores=n.cores)
        
      } else {
        
        # with no polygons we just write an empty raster
        print(paste('no polygons, skipping this year...'))
        raster::writeRaster(raster::mask(bc.mask.tif, bc.mask.tif, maskvalue=1, updatevalue=0), dest.file, overwrite=TRUE)
      }
    } 
    
    # junk removal (temporary raster .gri files)
    unlink(fids.tempdir, recursive=T, force=T)
    dir.create(fids.tempdir, showWarnings=F, recursive=T)
  }
}
close(pb.inner)
```

Lastly, I go through by year, aggregating severity levels at each pixel to produce (for each combination of year, species) a numeric layer
indicating the proportion of the area in each grid cell damaged by a given pest, and writing to disk (total written: ?? MB). 

For example in 2001-2003 this is done by taking (at each pixel) the inner product of c(`Low`, `Moderate`, `Severe`) and the values
`c(0.055, 0.2, 0.65)`. This produces a layer representing the (aggregated) midpoint (`mid`) of each AOS severity observation.
A similar calculation is done to construct the minima and maxima (`min`, and `max`), of the possible ranges of damage levels, as they
are defined in the AOS Standards 2019 guide
(<a href="https://www.for.gov.bc.ca/ftp/HFP/external/!publish/Aerial_Overview/Data_stds/">PDF link</a>).

Notice that this coding scheme is different for the pre2014 and post2013 periods, as defined in the list elements of `cfg$src$sev.codes`.


```r
# set tempfiles directory
fids.tempdir = tempdir()
dir.create(fids.tempdir, showWarnings=F, recursive=T)
raster::rasterOptions(tmpdir=fids.tempdir)

# loop over years and species
print('flattening severity layers into proportion-of-cell-area estimates...')
n.years = length(unlist(cfg$src$years))
n.species = length(cfg$src$spp.codes)
pb = txtProgressBar(min=1, max=n.years*n.species, style=3)
for(idx.year in 1:n.years)
{
  for(idx.species in 1:n.species)
  {
    # define attributes for these layers
    year = cfg$src$years[idx.year]
    species = cfg$src$spp.codes[idx.species]
    
    # handle year-dependent severity categories
    if(year < 2004)
    {
      severities = cfg$src$sev.codes[['pre2004']]
      severity.stats = cfg$src$sev.stats[['pre2004']]
        
    } else {
      
      severities = cfg$src$sev.codes[['post2003']]
      severity.stats = cfg$src$sev.stats[['post2003']]
    }
    n.severities = length(severities)
    dest.files = cfg$out$fname$tif$full[[names(year)]][[names(species)]][names(severity.stats[[1]])]
    
    # some output on progress for the user
    setTxtProgressBar(pb, idx.species + n.species*(idx.year-1))
    species.string = paste0(species, ' (', idx.species, ' of ', n.species, ')')
    year.string = paste0(year, ' (', idx.year, ' of ', n.years, ')')
    print(paste0('processing ', n.severities, ' severity levels in year ', year.string, ', species code ', species.string))
    
    # create base layers of zeros and NAs (bc.mask.tif has 1's everywhere that is non-NA)
    out.min.tif = raster::mask(bc.mask.tif, bc.mask.tif, maskvalue=1, updatevalue=0)
    out.mid.tif = out.min.tif
    out.max.tif = out.min.tif
    
    # loop to overlay severity levels (note that raster::overlay() function doesn't seem to speed this up)
    for(idx.severity in 1:length(severities))
    {
      # load the individual-severity damage layer
      severity = severities[idx.severity]
      dmg.percent.tif = raster::setMinMax(raster::raster(cfg$out$fname$tif$full[[names(year)]][[names(species)]][[names(severity)]]))
      
      # skip the overlay if the input layer is all NA (indicating no polygons for this year/species/severity level)
      if(!is.na(minValue(dmg.percent.tif)))
      {
        out.min.tif = out.min.tif + ( severity.stats[[names(severity)]]['min'] * dmg.percent.tif )
        out.mid.tif = out.mid.tif + ( severity.stats[[names(severity)]]['mid'] * dmg.percent.tif ) 
        out.max.tif = out.max.tif + ( severity.stats[[names(severity)]]['max'] * dmg.percent.tif )
      }
    }

    # ensure polygon overlap can't produce >100% values
    if(maxValue(out.max.tif) > 1)
    {
      # raster::mask() trick is faster than square-bracket indexing 
      out.max.tif = raster::mask(out.max.tif, out.max.tif > 1, maskvalue=1, updatevalue=1)
    }
    
    # write all three yearly rasters to disk temporarily (these will be deleted after bundling time series)
    raster::writeRaster(out.min.tif, dest.files[['min']], overwrite=TRUE)
    raster::writeRaster(out.mid.tif, dest.files[['mid']], overwrite=TRUE)
    raster::writeRaster(out.max.tif, dest.files[['max']], overwrite=TRUE)
    
    # junk removal (large temporary raster .gri files accumulate otherwise)
    unlink(fids.tempdir, recursive=T, force=T)
    dir.create(fids.tempdir, showWarnings=F, recursive=T)
  }
}
close(pb)
```

Finally, we split all layers up into mapsheets corresponding to the NTS/SNRC codes (365 MB total). This is broken up into two
calls to `MPB_split`, in order to handle the addition of two new layers starting in 2004 (`trace` and `verysevere`):

Expect this to take around 15-25 minutes


```r
# define the 2001-2003 period and the layers to split for those years
years.pre2004 = cfg$src$years[cfg$src$years < 2004]
severity.stats = cfg$src$sev.stats[['pre2004']]
varnames = c(names(cfg$src$sev.codes$pre2004), names(severity.stats[[1]]))
varnames.consolidated = unlist(lapply(names(cfg$src$spp.codes), function(species) paste0(species, '_', varnames)))

# create a temporary metadata list for this period
cfg.pre2004 = cfg
cfg.pre2004$src$years = years.pre2004
cfg.pre2004$out$fname$tif$full = lapply(cfg.pre2004$out$fname$tif$full[names(years.pre2004)], function(year) setNames(unlist(year), varnames.consolidated))

# function call to crop and save blocks, looping over years
cfg.blocks.pre2004 = MPB_split(cfg.pre2004, snrc.sf)

# define the 2004-2019 period and the layers to split for those years
years.post2003 = cfg$src$years[cfg$src$years > 2003]
severity.stats = cfg$src$sev.stats[['post2003']]
varnames = c(names(cfg$src$sev.codes$post2003), names(severity.stats[[1]]))
varnames.consolidated = unlist(lapply(names(cfg$src$spp.codes), function(species) paste0(species, '_', varnames)))

# create a temporary metadata list for this period
cfg.post2003 = cfg
cfg.post2003$src$years = years.post2003
cfg.post2003$out$fname$tif$full = lapply(cfg.post2003$out$fname$tif$full[names(years.post2003)], function(year) setNames(unlist(year), varnames.consolidated))

# function call to crop and save blocks, looping over years
cfg.blocks.post2003 = MPB_split(cfg.post2003, snrc.sf)

# update metadata list `cfg` and save it to `data.dir`.
cfg = MPB_metadata(collection, cfg.in=cfg, cfg.out=list(fname=list(tif=list(block=c(cfg.blocks.pre2004, cfg.blocks.post2003)))))
saveRDS(cfg, file=cfg.filename)
```

Metadata (including file paths) can now be loaded from 'fids.rds' located in `data.dir` using `readRDS()`.



