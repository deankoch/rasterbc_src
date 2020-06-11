# rasterbc
Provides easy access to gridded mountain pine beetle (MPB) datasets in British Columbia (BC) in the period 2001-2018

This project has three parts: 

1. A database of geotiff layers relevant to ecological modellers studying the MPB epidemic in BC (in /data)

2. an R package to automatically download subsets covering specific geographical areas (a separate repository)

3. R code for reproducing (1), by downloading from various government sources and performing the necessary GIS operations (in /src)

Datasets from environment ministries are publicly available online, but acquiring them can be cumbersome. Large filesizes, differing projections/data-structures, and arcane file formats can be big challenges for the novice GIS user. This project aims to make these data more accessible to the scientific community, by taking care of the heavy lifting in GIS and providing a convenient R-based distribution system. 

Layers are organized as mapsheets (a tiling of the full landbase of BC), allowing users to download small subsets corresponding to the geographic extent of their study area(s).

Note that the spatial reference system used here 
(<a href="https://spatialreference.org/ref/epsg/nad83-bc-albers/" target="_blank">NAD83 / BC Albers</a>)
is shared by both the 
<a href="https://cran.r-project.org/web/packages/bcmaps/index.html" target="_blank">bcmaps</a>
package and the
(<a href="http://hectaresBC.org" target="_blank">hectaresBC</a>) website,
so users can combine data from all three sources without fooling around with projection and alignment. 
 
