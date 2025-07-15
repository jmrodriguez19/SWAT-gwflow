library(future.apply)
library(future)
library(readr)
library(tidyr)
library(dplyr)
library(data.table)
setwd ("C:/Jose_ACMA/GWflow/SWAT_gwflow_cal/")

########### DefinitiveCoreIteration ############

# Stop any existing multisession workers
workers <- future:::plan("multisession")$workers
for (worker_id in seq_along(workers)) {
  future:::cluster_stop(workers[[worker_id]])
}

# Set working directory to TxtInOut folder
setwd(file.path(getwd(), "TxtInOut"))

# Define directories
original_dir <- file.path(getwd())
param_dir     <- original_dir
model_copies_dir <- file.path(original_dir, "Copy_model")

# Remove any existing model copies
unlink(model_copies_dir, recursive = TRUE)

# Number of cores for parallel processing
num_cores <- 20

# Configure future plan for multiprocessing
plan(multisession, workers = num_cores)

# Directory for model copies
model_copies_dir <- file.path(original_dir, "Copy_model")

# Read parameter files
param_df    <- readRDS(file.path(param_dir, "R1_cal.rds"))
param_df_gw <- readRDS(file.path(param_dir, "R1_input.rds"))

# Function to run a batch of iterations
run_batch <- function(batch) {
  batch_results <- lapply(batch, process_iteration)
  return(batch_results)
}

# Function to process a single iteration
process_iteration <- function(k) {
  tryCatch({
    library(dplyr)
    library(readr)
    library(stats)
    
    # Create iteration directory
    iter_dir <- file.path(model_copies_dir, paste0("thread_", k))
    dir.create(iter_dir, recursive = TRUE)
    
    # Copy all files from original directory into iteration folder
    all_files <- list.files(original_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    for (f in all_files) {
      file.copy(f, file.path(iter_dir, basename(f)))
    }
    
    # Write calibration parameters
    calib_file <- file.path(iter_dir, "calibration.cal")
    writeLines(param_df[[k]], calib_file)
    
    # Prepare gwflow input files
    setwd(original_dir)
    gwflow_base   <- readLines("gwflow.input")
    gwflow_copy   <- file.path(iter_dir, "gwflow.input")
    rescells_base <- readLines("gwflow.rescells")
    rescells_copy <- file.path(iter_dir, "gwflow.rescells")
    
    gwflow_base[c(21:36, 2228, 1389:1657)] <- param_df_gw[[k]][1:286]#Depends on your gwflow.input template
    rescells_base[c(3, 4)] <- param_df_gw[[k]][287:288]#Depends on your gwflow.input template
    
    writeLines(gwflow_base, gwflow_copy)
    writeLines(rescells_base, rescells_copy)
    
    # Run the SWAT+ executable
    setwd(iter_dir)
    system("SWAT+.exe")
    
    # Read groundwater balance output
    gw_balance_file <- file.path(iter_dir, "gwflow_balance_gw_aa")
    gw_fluxes <- readr::read_table(gw_balance_file, skip = 27) %>% .[, c(2:9, 14)]
    
    # Read surface water balance output
    wb_file <- file.path(iter_dir, "basin_wb_aa.txt")
    wb_daily <- readr::read_table(wb_file, skip = 1, col_names = TRUE) %>%
      .[-1, ] %>%
      mutate_all(as.numeric)
    
    # Clean up iteration directory
    unlink(iter_dir, recursive = TRUE)
    
    # Return named list of outputs
    return(setNames(
      list(gw_fluxes, wb_daily),
      c(paste0("thread_", k, "_gw_fluxes"),
        paste0("thread_", k, "_wb_SWAT"))
    ))
    
  }, error = function(e) {
    message("Error in iteration ", k, ": ", e$message)
    return(NULL)
  })
}

# Define sequence of iterations and batch structure
iteration_sequence <- 1:2
num_cores <- 1  # Adjust based on available CPU cores
batch_ids <- rep(1:num_cores, length.out = length(iteration_sequence))
batches <- split(iteration_sequence, batch_ids)

# Base path for output files
base_path <- "C:/Jose_ACMA/GWflow/SWAT_gwflow_cal/"

# Process each sub-iteration across batches
for (i in seq_along(batches[[1]])) {
  tryCatch({
    # Execute each batch in parallel
    batch_results <- future_lapply(lapply(batches, "[", i), run_batch)
    
    # Define filename for current batch results
    file_name <- paste0(base_path, i, ".rds")
    
    # Save results to RDS
    write_rds(batch_results, file_name)
    
    # Free memory
    rm(batch_results)
    gc()
    
  }, error = function(e) {
    message("Error in batch ", i, ": ", e$message)
    # Optionally log or retry
  })
}



#### PROCESS RESULTS ####

# Base path for result files
setwd ("C:/Jose_ACMA/GWflow/SWAT_gwflow_cal/")
results_path <- getwd()
file_names   <- paste0(results_path, "/", 1:2, ".rds")  # adjust 1:2 to number of files
data_files   <- lapply(file_names, readRDS)

# Unnest all nested lists into a single list
combined_list <- list()
for (i in seq_along(data_files)) {
  for (k in seq_along(data_files[[i]])) {
    for (n in seq_along(data_files[[i]][[k]])) {
      combined_list <- c(list(data_files[[i]][[k]][[n]]), combined_list)
    }
  }
}
combined_list <- rev(combined_list)

#### Groundwater flux variables ####
# Extract the first element (gw_flux) from each list item
gw_flux_list <- lapply(combined_list, `[[`, 1)
# Bind into one data.table with station identifier
gw_flux <- data.table::rbindlist(gw_flux_list, idcol = "station")

#### Surface water balance (WB) variables ####
# Extract the second element (wb_daily) from each list item
wb_list <- lapply(combined_list, `[[`, 2)
# Bind into one data.table with station identifier
wb <- data.table::rbindlist(wb_list, idcol = "station")

# Estimate groundwater contribution
GW_contribution <- ((-gw_flux$gwsw) + (-gw_flux$satx)) /
  (wb$latq_cha + wb$surq_cha + (-gw_flux$gwsw) + (-gw_flux$satx))

#### Calibration parameters ####
calib_params <- read.csv("R1_cal.csv")
calib_CRB    <- calib_params[, 1:12]
calib_DET    <- calib_params[, 13:24]
calib_BASI   <- calib_params[, 25:26]

#### Input parameters ####
input_params <- read.csv("R1_input.csv")
input_CRB    <- input_params[, c(1, 3, 5, 7)]
input_DET    <- input_params[, c(2, 4, 6, 8)]

#### Function to plot parameter range vs. hydrologic variable ####
plot_dotty <- function(par, crit, crit_label = "crit", n_col = 3) {
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  
  dotty_tbl <- par %>%
    mutate(crit = crit) %>%
    pivot_longer(cols = -crit, names_to = "parameter")
  
  ggplot(dotty_tbl, aes(x = value, y = crit)) +
    geom_point() +
    geom_smooth() +
    facet_wrap(~ parameter, ncol = n_col, scales = "free_x") +
    labs(x = "Parameter value change", y = crit_label) +
    theme_bw()
}

# Generate dotty plots
plot_dotty(par = calib_CRB, crit = GW_contribution, crit_label = "gc")
plot_dotty(par = calib_DET, crit = GW_contribution, crit_label = "gc")
