# SWAT+GWFlow Calibration using Latin Hypercube Sampling

This project implements an **iterative calibration and sensitivity analysis workflow** for the **SWAT+GWFlow model**, using **Latin Hypercube Sampling (LHS)** for parameter generation. The approach enables evaluation of groundwater contributions and calibration of both surface and subsurface hydrologic parameters in coupled simulations.

## 🛠️ Scripts Overview

### 1. `1_Parametrization.R`

- **Purpose**: Generate multiple combinations of model parameters within predefined bounds.
- **Steps**:
  1. **Load libraries** (`tibble`, `tidyr`, `purrr`, `lhs`, `ggplot2`, `readr`, `stringr`).
  2. **Define parameter bounds** for SWAT+ (soil, routing, percolation, etc.) and GWFlow (aquifer properties, recharge, reservoir).
  3. **Perform Latin Hypercube Sampling** (`lhs::randomLHS`) with `n_sample = 20` and `k = n_par` parameters.
  4. **Map unit-interval samples to actual ranges**, creating two tibbles:
     - `par_zonal_tag_cal` → calibration parameters
     - `par_zonal_tag_input` → GWFlow input parameters
  5. **Save**:
     - CSV files: `R1_cal.csv`, `R1_input.csv`
     - Serialized RDS lists: `TxtInOut/R1_cal.rds`, `TxtInOut/R1_input.rds`
  6. **Visualize** histograms of each sampled parameter to inspect distribution.

### 2. `2_Run_iter_proc.R`

- **Purpose**: Iterate SWAT+GWFlow runs in parallel, process results, and compute a groundwater contribution metric.
- **Steps**:
  1. **Load libraries** (`future.apply`, `future`, `readr`, `tidyr`, `dplyr`, `data.table`).
  2. **Configure parallel backend** (`future::plan(multisession, workers = 20)`).
  3. **Read parameter lists**:  
     - `param_df`  ← `TxtInOut/R1_cal.rds`  
     - `param_df_gw` ← `TxtInOut/R1_input.rds`
  4. **Define** `process_iteration(k)`:
     - Create folder `TxtInOut/Copy_model/thread_k`
     - Copy template files: `calibration.cal`, `gwflow.input`, `gwflow.rescells`
     - Overwrite lines with sampled values from `param_df[[k]]` and `param_df_gw[[k]]`
     - Run `SWAT+.exe` in that folder
     - Read outputs:
       - `gwflow_balance_gw_aa` → groundwater fluxes
       - `basin_wb_aa.txt` → surface water balance
     - Delete temporary folder
     - Return a named list of two data.tables
  5. **Batch execution**:
     - Split iterations into batches
     - Run `future_lapply()` to execute `process_iteration` in parallel
     - Save each batch’s results as `1.rds`, `2.rds`, …
  6. **Post‑processing**:
     - Load all result `.rds`
     - Unnest into a single list
     - Bind into two tables: 
       - `gw_flux` (groundwater flux)
       - `wb` (water balance)
     - Compute **groundwater contribution**:
       ```r
       GW_contribution = (-gw_flux$gwsw - gw_flux$satx) /
                         (wb$latq_cha + wb$surq_cha - gw_flux$gwsw - gw_flux$satx)
       ```
     - Extract calibration & input CSVs subsets and generate **dotty plots** of each parameter against `GW_contribution`.

## 📂 Project Structure
SWAT_gwflow_cal/
├── 1_Parametrization.R # Sampling + matrix creation
├── 2_Run_iter_proc.R # Parallel runs + processing
├── R1_cal.csv # Calibration parameter samples
├── R1_input.csv # GWFlow parameter samples
├── TxtInOut/
│ ├── calibration.cal # SWAT+ template file
│ ├── gwflow.input # GWFlow template file
│ ├── gwflow.rescells # GWFlow template file
│ ├── R1_cal.rds # List of modified calibration files
│ ├── R1_input.rds # List of modified input files
├── 1.rds # Results from batch 1
├── 2.rds # Results from batch 2
├── README.md # Project description
├── .gitignore
└── LICENSE

## ⚙️ Requirements

- **R** ≥ 4.0  
- **Packages**:
  ```r
  install.packages(c(
    "tibble", "tidyr", "purrr", "lhs", "ggplot2", 
    "readr", "stringr", "future", "future.apply", 
    "dplyr", "data.table"
  ))
  
## 📝 License

This project is released under the **MIT License**.  
See the full text in the [LICENSE](LICENSE) file for details.