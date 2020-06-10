# rasterbc
Provides easy access to gridded mountain pine beetle (MPB) datasets in British Columbia (BC) in the period 2001-2018

This project has three parts: 

(1) A database of geotiff layers relevant to ecological modellers studying the MPB epidemic in BC 
(2) an R package to automatically download subsets covering specific geographical areas
(3) R code for reproducing (1), by downloading from various government sources and performing the necessary GIS operations 
blah

Datasets from environment ministries are publicly available online, but acquiring them can be cumbersome. Large filesizes, differing projections/data-structures, and arcane file formats can be big challenges for the novice GIS user. This project aims to make these data more accessible to the scientific community, by taking care of the heavy lifting in GIS and providing a convenient R-based distribution system. 

Layers are organized as mapsheets (a tiling of the full landbase of BC), allowing users to download small subsets corresponding to the geographic extent of their study area(s).
