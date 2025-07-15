##### Tratemiento y generacion datos####
library(tibble)
library(tidyr)
library(purrr)  #Functional programming, para simplificar/reemplazar loops
library(lhs)
library(ggplot2)
library(readr)
library(stringr)
setwd(here::here())
getwd()
## calibration.cal ##
n_sample <- 20

# Parameter bounds (zonal)
par_bound_zonal <- tibble(
  'CRB_esco' = c(0.25, 1),
  'CRB_epco' = c(0, 1),
  'CRB_cn2' = c(0, 10),
  'CRB_awc' = c(-20, 40),
  'CRB_perco' = c(0.9, 0.95),
  'CRB_z' = c(-60, -40),
  'CRB_k' = c(20, 150),
  'CRB_cn3_swf' = c(0, 0.3),
  'CRB_bd' = c(-30, -10),
  'CRB_latq_co' = c(-0.3, 0.25),
  'CRB_ovn' = c(-20, 20),
  'CRB_lat_ttime' = c(10, 20),
  'DEA_esco' = c(0, 1),
  'DEA_epco' = c(0, 1),
  'DEA_cn2' = c(-30, -10),
  'DEA_awc' = c(10, 40),
  'DEA_perco' = c(0.45, 0.6),
  'DEA_z' = c(-10, 10),
  'DEA_k' = c(-25, 75),
  'DEA_cn3_swf' = c(-0.25, 0.5),
  'DEA_bd' = c(-30, -10),
  'DEA_latq_co' = c(0, 0.5),
  'DEA_ovn' = c(-20, 20),
  'DEA_lat_ttime' = c(0.55, 30),
  'ALL_chn' = c(0.05, 0.15),
  'ALL_surlag' = c(0.1, 7.5)
)

# Number of parameters
n_par <- ncol(par_bound_zonal)

# Latin Hypercube Sampling for calibration parameters
par_zonal_tag_cal <- randomLHS(n = n_sample, k = n_par) %>%
  as_tibble(.name_repair = 'minimal') %>%
  set_names(names(par_bound_zonal)) %>%
  map2_df(., par_bound_zonal, ~ (.x * (.y[2] - .y[1]) + .y[1]))

# Save calibration parameters to CSV
write_csv(par_zonal_tag_cal, "R1_cal.csv")


## gw.input ##
par_bound_zonal <- tibble(
  'kaqu1' = c(1, 2.5),
  'kaqu2' = c(0.5, 1),
  'syaqu1' = c(0.003, 0.006),
  'syaqu2' = c(0.005, 0.015),
  'bed_k1' = c(0.000025, 0.0001),
  'bed_k2' = c(0.000005, 0.00001),
  'bed_th1' = c(0.15, 0.25),
  'bed_th2' = c(0.01, 2.5),
  'bed_dep' = c(0.01, 3),
  'rech1' = c(0.1, 10),
  'rech2' = c(0.1, 30),
  'bedt_res' = c(0.01, 5),
  'bedK_res' = c(0.00001, 0.0005)
)

n_par <- ncol(par_bound_zonal)

# Latin Hypercube Sampling for input parameters
par_zonal_tag_input <- randomLHS(n = n_sample, k = n_par) %>%
  as_tibble(.name_repair = 'minimal') %>%
  set_names(names(par_bound_zonal)) %>%
  map2_df(., par_bound_zonal, ~ (.x * (.y[2] - .y[1]) + .y[1]))

# Save input parameters to CSV
write_csv(par_zonal_tag_input, "R1_input.csv")


# Plotting the results
library(ggplot2)
library(tidyr)

# Convert to long format
par_zonal_tag_long <- par_zonal_tag_input %>%
  pivot_longer(cols = everything(), names_to = "parameter", values_to = "value")

# Histogram plot of each parameter
ggplot(par_zonal_tag_long, aes(x = value)) +
  geom_histogram(bins = 30, fill = "skyblue", color = "black", alpha = 0.7) +
  facet_wrap(~ parameter, scales = "free") +
  theme_minimal() +
  labs(title = "Parameter Value Distributions", x = "Value", y = "Frequency")


###### Generate matrix to modify calibration.cal #####
param_df <- par_zonal_tag_cal
lines <- readLines("TxtInOut/calibration.cal")

# Modify the third value in each line starting from line 4
par_cal <- list()
for (k in 1:20) {
  for (i in 4:length(lines)) {
    parts <- strsplit(lines[i], "\\s+")[[1]]  # Split line by whitespace
    if (length(parts) >= 3) {  # Ensure at least 3 elements per line
      Param <- as.numeric(param_df[k, ])
      parts[3] <- as.character(Param[i - 3])  # Replace the third value
      lines[i] <- paste(parts, collapse = "\t")  # Reconstruct the line
    }
  }
  par_cal[[k]] <- lines  # Save modified lines as one realization
}

# Save list of calibration configurations
write_rds(par_cal, "TxtInOut/R1_cal.rds")


###### Generate matrix to modify gwflow.input #####
param_df_gw <- par_zonal_tag_input
lines2 <- readLines("TxtInOut/gwflow.input")

par_cal_input <- list()
for (k in 1:20) {
  
  # Section to edit: lines for static parameters
  a <- lines2[c(21:36, 2228)] #Depends on your gwflow.input template
  split_a <- strsplit(a, "\\s+")
  
  # Replace recharge values in a specific section
  count_numbers <- 1
  numeric_values <- param_df_gw[k, ]
  b <- lines2[c(849:1117)] #Depends on your gwflow.input template
  val1 <- as.character(round(numeric_values["rech1"], 1))
  val2 <- as.character(round(numeric_values["rech2"], 1))
  
  # Step 1: Use temporary placeholders
  b <- str_replace_all(b, "\\b1\\b", "TEMP_RECH1")
  b <- str_replace_all(b, "\\b2\\b", "TEMP_RECH2")
  
  # Step 2: Replace placeholders with actual values
  b <- str_replace_all(b, "TEMP_RECH1", val1)
  b <- str_replace_all(b, "TEMP_RECH2", val2)
  
  # Step 3: Normalize whitespace
  b <- gsub("\\s+", "\t", trimws(b))
  
  # Extract reservoir parameters
  c <- as.character(c(numeric_values["bedt_res"], numeric_values["bedK_res"]) %>% unlist(.))
  
  # Update the "a" section with first 9 numeric values
  numeric_values <- param_df_gw[k, ][c(1:9)] #Depends on your gwflow.input template
  for (i in seq_along(split_a)) {
    current_split <- split_a[[i]]
    if (i >= 3 && length(current_split) == 3 && current_split[1] == "") {
      current_split[3] <- as.character(numeric_values[count_numbers])
      count_numbers <- count_numbers + 1
    } else if (i == length(split_a) && length(current_split) < 3) {
      current_split <- c("", as.character(numeric_values[length(numeric_values)]))
    }
    split_a[[i]] <- current_split
  }
  
  # Reconstruct section a
  for (i in 1:length(split_a)) {
    a[i] <- paste(split_a[[i]], collapse = "\t")
  }
  
  # Store the modified sections as one realization
  par_cal_input[[k]] <- c(a, b, c)
}

# Save list of input configurations
write_rds(par_cal_input, "TxtInOut/R1_input.rds")
