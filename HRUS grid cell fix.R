# =============================================================================
# NOTE:
# This script is only necessary if an intersection has been performed between 
# the model grid (gridcell) and a simplified HRU shapefile that contains gaps, 
# i.e., it does not fully cover the modeled area.
#
# Its purpose is to correctly redistribute and weight the HRU areas so that 
# the total assigned area per cell matches the original model area.
# =============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# SECTION 1: Load Required Libraries
# ──────────────────────────────────────────────────────────────────────────────

library(sf)       # For reading shapefiles
library(dplyr)    # For data manipulation
library(tidyr)    # For splitting comma-separated values
library(readr)    # For reading tables

# Show current working directory
getwd()


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 2: Read and Prepare Shapefile Data
# ──────────────────────────────────────────────────────────────────────────────

# Define path to the shapefile
shapefile_path <- "shp/hrus2.shp"

# Read the shapefile into an sf object
shp <- st_read(shapefile_path)

# Extract HRUS field, preserve original, split comma‑separated values, and convert to numeric
ID_GIS <- shp %>%
  st_drop_geometry() %>%                # Drop geometry column
  select(HRUS) %>%                      # Keep only HRUS
  mutate(original_values = HRUS) %>%    # Preserve comma‑separated string
  mutate(HRUS = as.character(HRUS)) %>% # Ensure character type
  separate_rows(HRUS, sep = ",") %>%    # Split into rows
  mutate(HRUS = as.numeric(trimws(HRUS))) # Trim whitespace and convert to numeric

# Display the resulting table
print(ID_GIS)

# Rename columns for clarity
colnames(ID_GIS) <- c("gis_id", "HRUS")


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 3: Read HRU Area Data and Merge
# ──────────────────────────────────────────────────────────────────────────────

# Read the .con file, skip first line, select gis_id and area, convert units
ID_GIS2 <- read_table("TxtInOut/hru.con", skip = 1) %>%
  .[, c("gis_id", "area")] %>%
  mutate(hru_area = area * 10000)  # e.g., hectares to m²

# Inspect column names
colnames(ID_GIS2)

# Merge with split HRUS table
ID_GIS2_fin <- ID_GIS %>%
  merge(ID_GIS2, ., by = "gis_id") %>%
  .[, c("gis_id", "HRUS", "hru_area")]

# Inspect merged result
colnames(ID_GIS2_fin)


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 4: Read HRU‑Cell Lookup and Attach Polygon Areas
# ──────────────────────────────────────────────────────────────────────────────

# Read the CSV file resulting from the intersection between the simplified HRUs shp (with gaps) and the gridcell.
HRus <- read.csv(
  "HRU_cell_simp.csv",
  sep = ";"
) %>% .[c(3, 2, 1, 4)]

# Preview lookup table
head(HRus)

# Merge lookup with area data and rename columns
HRus2 <- HRus %>%
  merge(ID_GIS2_fin, ., by = "HRUS") %>%
  .[, c("HRUS", "gis_id", "hru_area.x", "cell_id", "hru_area.y")] %>%
  setNames(c("HRUS", "gis_id", "hru_area", "cell_id", "poly_area"))


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 5: Identify Multi‑HRUS and Distribute Polygon Area
# ──────────────────────────────────────────────────────────────────────────────

# Flag rows with comma‑separated HRUS entries
numeros_con_comas     <- grepl("^\\d+(, \\d+)+$", HRus2$HRUS)
numeros_con_comas     <- HRus2[numeros_con_comas, ]

# Separate single‑HRUS entries
numeros_sin_comas     <- unique(HRus2$HRUS[!grepl(",", HRus2$HRUS)]) %>% as.numeric(.)
numeros_sin_comas2    <- HRus2[HRus2$HRUS %in% numeros_sin_comas, ] 

# List of multi‑HRUS identifiers
Hrus_list <- unique(numeros_con_comas$HRUS)

# Prepare list to hold corrected entries
Hrus_l <- list()

# Loop to split poly_area evenly among parts
for(i in 1:length(Hrus_list)) {
  Tabla <- HRus2[HRus2$HRUS == Hrus_list[i], ]
  Tabla$poly_area <- Tabla$poly_area / length(unique(Tabla$gis_id))
  Hrus_l[[i]] <- Tabla
}

# Combine corrected multi‑HRUS with single‑HRUS
Hrus_cell_corregido <- rbindlist(Hrus_l) %>%
  rbind(numeros_sin_comas2, .)


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 6: Summarise and Merge Adjusted Areas
# ──────────────────────────────────────────────────────────────────────────────

# Sum adjusted polygon areas by gis_id
HRus_group <- Hrus_cell_corregido %>%
  group_by(gis_id) %>%
  summarise(across(starts_with("poly_area"), sum))

# Merge summary back to detailed table
HRus_unio <- Hrus_cell_corregido %>%
  merge(HRus_group, ., by = "gis_id") %>%
  .[, c("HRUS", "gis_id", "hru_area", "cell_id", "poly_area.x", "poly_area.y")]

# Inspect combined table and total corrected area
head(HRus_unio)

#Area of the intersection of the grid cell hrus.
a<-sum(HRus_unio$poly_area.y)
#Entire area of our basin.
b<-HRus_unio %>%  group_by(gis_id) %>% summarise(promedio_hru_area = mean(hru_area, na.rm = TRUE)) %>% summarise(total = sum(promedio_hru_area))
#Area not considered in the intersection
b-a

# Rename columns for final clarity
colnames(HRus_unio) <- c(
  "HRUS", 
  "gis_id", 
  "hru_area_SWAT", 
  "cell_id", 
  "hru_area_Fix", 
  "poly_area"
)


# ──────────────────────────────────────────────────────────────────────────────
# SECTION 7: Calculate Weighting Factors and Verify
# ──────────────────────────────────────────────────────────────────────────────

# Assign to datos for weighting
datos <- HRus_unio

# Compute adjusted weighting factor per gis_id
factores_ponderacion <- datos %>%
  group_by(gis_id) %>%
  mutate(poly_area_sum = sum(poly_area)) %>%
  mutate(peso_ajustado = hru_area_SWAT / sum(poly_area)) %>%
  select(gis_id, poly_area_sum, peso_ajustado) %>%
  distinct()

# Join factors and calculate weighted area
datos_ponderados <- datos %>%
  left_join(factores_ponderacion, by = "gis_id") %>%
  mutate(poly_area_m2_ponderado = poly_area * peso_ajustado)

# Verify weighted sums match original area
verificacion <- datos_ponderados %>%
  group_by(gis_id) %>%
  summarise(
    suma_poly_area_ponderada = sum(poly_area_m2_ponderado),
    Area_m2_original        = first(hru_area_SWAT)
  )

# Print verification results
print(verificacion)

# HRU-Cells Connection Information (gwflow.data)
Final_table<-datos_ponderados[c(4,5,9)]





