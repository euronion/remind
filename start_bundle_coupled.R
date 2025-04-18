#!/usr/bin/env Rscript
# |  (C) 2006-2023 Potsdam Institute for Climate Impact Research (PIK)
# |  authors, and contributors see CITATION.cff file. This file is part
# |  of REMIND and licensed under AGPL-3.0-or-later. Under Section 7 of
# |  AGPL-3.0, you are granted additional permissions described in the
# |  REMIND License Exception, version 1.0 (see LICENSE file).
# |  Contact: remind@pik-potsdam.de
if (!is.null(renv::project())) {
  stop("Coupled runs are currently not supported with renv. Please use a snapshot instead. ",
       "How to switch from renv to snapshots: ",
       "https://github.com/remindmodel/remind/blob/develop/tutorials/11_ManagingRenv.md#legacy-snapshots ",
       "How to create a snapshot: https://github.com/remindmodel/remind/blob/develop/tutorials/",
       "04_RunningREMINDandMAgPIE.md#create-snapshot-of-r-libraries")
}
require(lucode2)
require(magclass)
require(gms)
require(remind2)
require(gtools) # required for mixedsort()
require(dplyr) # for filter, secelt, %>%
require(stringr) # for str_sub

helpText <- "
#' Usage:
#' Before running this script, edit start_bundle_coupled.R
#' and specify the user settings
#'
#' Rscript start_bundle_coupled.R [options]
#' Rscript start_bundle_coupled.R scenario_config_coupled_*.csv
#' Rscript start_bundle_coupled.R --test scenario_config_coupled_*.csv
#'
#' scenario_config_coupled_*.csv must be a coupled scenario config .csv file (usually
#' in the config/ directory), which corresponds to a normal scenario_config_*.csv file.
#' Using this will start all REMIND runs specified by \"start = 1\" in that file
#' (check the startgroup option to start a specific group).
#'
#' Control the script's behavior by providing additional arguments:
#'
#'   --help, -h:        show this help text and exit
#'   --gamscompile, -g: compile gms of all selected runs. Combined with
#'                      --interactive, it stops in case of compilation
#'                      errors, allowing to fix them and rerun gamscompile
#'   --interactive, -i: interactively select run(s) to be started. Asks for
#'                      config file also if the one specified as
#'                      path_settings_coupled cannot be found.
#'   --test, -t:        Test scenario configuration and write the RData files
#'                      in the REMIND main folder without starting the runs.
#'   startgroup=MYGROUP  when reading a scenario config .csv file, don't start
#'                       everything specified by \"start = 1\", instead start everything
#'                       specified by \"start = MYGROUP\"
"

########################################################################################################
#################################  U S E R   S E T T I N G S ###########################################
########################################################################################################

# Please provide all files and paths relative to the folder where start_coupled is executed
path_remind <- getwd()   # provide path to REMIND. Default: the actual path which the script is started from
path_magpie <- normalizePath(file.path(getwd(), "..", "magpie"))

# Paths to the files where scenarios are defined
# path_settings_remind contains the detailed configuration of the REMIND scenarios
# path_settings_coupled defines which runs will be started, coupling infos, and optimal gdx and report information that overrides path_settings_remind
# these settings will be overwritten if you provide the path to the coupled file as first command line argument
path_settings_coupled <- file.path(path_remind, "config", "scenario_config_coupled_NGFS_v4.csv")
path_settings_remind  <- sub("scenario_config_coupled", "scenario_config", path_settings_coupled)
                         # file.path(path_remind, "config", "scenario_config.csv")

# You can put a prefix in front of the names of your runs, this will turn e.g. "SSP2-Base" into "prefix_SSP2-Base".
# This allows storing results of multiple coupled runs (which have the same scenario names) in the same MAgPIE and REMIND output folders.
prefix_runname <- "C_"

# If there are existing runs you would like to take the gdxes (REMIND) or reportings (REMIND or MAgPIE) from, provide the path here and the name prefix below.
# Note: the scenario names of the old runs have to be identical to the runs that are to be started. If they differ please provide the names of the old scenarios in the
# file that you specified on path_settings_coupled (scenario_config_coupled_xxx.csv).
path_remind_oldruns <- file.path(path_remind, "output")
path_magpie_oldruns <- file.path(path_magpie, "output")

# If you want the script to find gdxs or reports of older runs as starting point for new runs please
# provide the prefix of the old run names so the script can find them.
prefix_oldruns <-  "C_"

# number of coupling iterations, can also be specified in path_settings_coupled
max_iterations <- 5

# Number of coupling iterations (before final iteration) in which MAgPIE uses higher n600 resolution.
# Until "max_iterations - n600_iterations" iteration MAgPIE runs with n200 resolution.
# Afterwards REMIND runs for "n600_iterations" iterations with results from higher resolution.
n600_iterations <- 0 # max_iterations

# run a compareScenario for each scenario comparing all rem-x: Choose qos (short, priority) or set to FALSE
run_compareScenarios <- "short"

# use an empty magpie model (just reproduces the latest AMT results)
magpie_empty <- FALSE

########################################################################################################
#################################  load command line arguments  ########################################
########################################################################################################

# Source everything from scripts/start so that all functions are available everywhere
invisible(sapply(list.files("scripts/start", pattern = "\\.R$", full.names = TRUE), source))

# Define colors for output
red   <- "\033[0;31m"
green <- "\033[0;32m"
blue  <- "\033[0;34m"
NC    <- "\033[0m"   # No Color

# define arguments that are accepted (test for backward compatibility)
startgroup <- "1"
flags <- lucode2::readArgs("startgroup", .flags = c(h = "--help", g = "--gamscompile", i = "--interactive", p = "--parallel", t = "--test"))
if (! exists("argv")) argv <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% flags) {
  message(helpText)
  q()
}
if ("test" %in% argv) flags <- unique(c(flags, "--test"))
if ("--parallel" %in% flags) {
  message("The flag --parallel is not necessary anymore, as this is default now")
}

# load arguments from command line
argv <- grep('(^-|=|^test$)', argv, value = TRUE, invert = TRUE)
if (length(argv) > 0) {
  file_exists <- file.exists(argv)
  if (sum(file_exists) > 1) stop("Enter only a scenario_config_coupled* file via command line or set all files manually in start_bundle_coupled.R")
  if (!all(file_exists)) stop("Unknown parameter provided: ", paste(argv[!file_exists], collapse = ", "))
  # set config file to not known parameter where the file actually exists
  path_settings_coupled <- file.path(path_remind, argv[[1]])
  if (! grep("scenario_config_coupled", path_settings_coupled))
    stop("Enter only a scenario_config_coupled* file via command line or set all files manually in start_bundle_coupled.R")
  path_settings_remind  <- sub("scenario_config_coupled", "scenario_config", path_settings_coupled)
} else if (! file.exists(path_settings_coupled)) {
  possiblecsv <- Sys.glob(c(file.path("config", "scenario_config_coupled*.csv"),
                            file.path("config", "*", "scenario_config_coupled*.csv")))
  path_settings_coupled <- gms::chooseFromList(possiblecsv, type = "one coupled config file", returnBoolean = FALSE, multiple = FALSE)
  path_settings_remind  <- sub("scenario_config_coupled", "scenario_config", path_settings_coupled)
  message("")
}

message("path_remind:           ", if (dir.exists(path_remind)) green else red, path_remind, NC)
message("path_magpie:           ", if (dir.exists(path_magpie)) green else red, path_magpie, NC)
message("path_settings_coupled: ", if (file.exists(path_settings_coupled)) green else red, path_settings_coupled, NC)
message("path_settings_remind:  ", if (file.exists(path_settings_remind)) green else red, path_settings_remind, NC)
message("path_remind_oldruns:   ", if (dir.exists(path_remind_oldruns)) green else red, path_remind_oldruns, NC)
message("path_magpie_oldruns:   ", if (dir.exists(path_magpie_oldruns)) green else red, path_magpie_oldruns, NC)
message("prefix_runname:        ", prefix_runname)
message("n600_iterations:       ", n600_iterations)
message("run_compareScenarios:  ", run_compareScenarios)

if (! file.exists("output")) dir.create("output")

# Check if dependencies for a REMIND model run are fulfilled
# Use ensureRequirementsInstalled(rerunPrompt="start_bundle_coupled.R") when coupled runs are using renv.
if (requireNamespace("piamenv", quietly = TRUE) && packageVersion("piamenv") >= "0.2.0") {
  piamenv::checkDeps(action = "stop")
} else {
  stop("REMIND requires piamenv >= 0.2.0, please use snapshot 2022_11_18_R4 or later.")
}

errorsfound <- 0
startedRuns <- 0
waitingRuns <- 0
deletedFolders <- 0

stamp <- format(Sys.time(), "_%Y-%m-%d_%H.%M.%S")

if ("--gamscompile" %in% flags && ! file.exists("input/source_files.log")) {
  message("\n### Input data missing, need to compile REMIND first (2 min.)\n")
  system("Rscript start.R config/tests/scenario_config_compile.csv")
}

####################################################
############## F U N C T I O N S ###################
####################################################
.setgdxcopy <- function(needle, stack, new){
  # delete entries in stack that contain needle and append new
  matches <- grepl(needle, stack)
  out <- c(stack[!matches], new)
  return(out)
}

# Returns TRUE if fullname ends with extension (eg. if "C_SSP2-Base/fulldata.gdx" ends with "fulldata.gdx")
# AND if the file given in fullname exists.
.isFileAndAvailable <- function(fullname, extension) {
  isTRUE(stringr::str_sub(fullname, -nchar(extension), -1) == extension) &&
    file.exists(fullname)
}

# find last REMIND / MAgPIE run
findLastRem <- function(folder, scenario) {
  filesfound <- Sys.glob(file.path(folder, paste0(scenario, "-rem-*"), "fulldata.gdx"))
  filesfound <- grep("-rem-[0-9]+.fulldata\\.gdx$", filesfound, value = TRUE)
  return(mixedsort(filesfound)[1])
}
findLastMag <- function(folder, scenario) {
  filesfound <- Sys.glob(file.path(folder, paste0(scenario, "-mag-*"), "report.mif"))
  filesfound <- grep("-mag-[0-9]+.report\\.mif$", filesfound, value = TRUE)
  return(mixedsort(filesfound)[1])
}

####################################################
##############  READ SCENARIO FILES ################
####################################################
# Read-in the switches table, use first column as row names

settings_coupled <- readCheckScenarioConfig(path_settings_coupled, path_remind)
settings_remind  <- readCheckScenarioConfig(path_settings_remind, path_remind)

scenarios_coupled <- selectScenarios(settings = settings_coupled,
                                     interactive = "--interactive" %in% flags,
                                     startgroup = startgroup)

missing <- setdiff(rownames(scenarios_coupled),rownames(settings_remind))
if (!identical(missing, character(0))) {
  message("The following scenarios are given in '", path_settings_coupled,
          "' but could not be found in '", path_settings_remind, "':")
  message("  ", paste(missing, collapse = ", "), "\n")
}

if ("max_iterations" %in% colnames(scenarios_coupled)) {
  if (nrow(unique(scenarios_coupled["max_iterations"])) > 1) {
    stop("You have specified different `max_iterations` for different scenarios, that is not supported.")
  }
  max_iterations <- scenarios_coupled[1, "max_iterations"]
}
message("max_iterations:        ", max_iterations)

common <- intersect(rownames(settings_remind), rownames(scenarios_coupled))
knownRefRuns <- apply(expand.grid(prefix_runname , common, "-rem-", seq(max_iterations)), 1, paste, collapse="")
if (! identical(common, character(0))) {
  message("\n################################\n")
  message("The following ", length(common), " scenarios will be started:")
  message("  ", paste(common, collapse = ", "))
} else {
  stop("No scenario found with start=", startgroup, " in ", basename(path_settings_coupled), " that is also defined in ", basename(path_settings_remind), ".")
}
message("")

# If provided replace gdx paths given in scenario_config with paths given in scenario_config_coupled
for (scen in common) {
  use_path_gdx <- names(path_gdx_list)[! is.na(scenarios_coupled[scen, names(path_gdx_list)])]
  if (length(use_path_gdx) > 0) {
    settings_remind[scen, use_path_gdx] <- scenarios_coupled[scen, use_path_gdx]
    message("For ", scen, ", use data specified in coupled config for: ", paste(use_path_gdx, collapse = ", "), ".")
  }
}

if (file.exists("/p") && "qos" %in% names(scenarios_coupled)
    && sum(scenarios_coupled[common, "qos"] == "priority", na.rm = TRUE) > 4) {
      message("\nAttention, you want to start more than 4 runs with qos=priority mode.")
      message("They may not be able to run in parallel on the PIK cluster.")
}

####################################################
######## PREPARE AND START COUPLED RUNS ############
####################################################

# prepare runs: write RData files
for(scen in common){
  message("\n################################\nPreparing run ", scen, "\n")

  start_now <- FALSE # initalize, will be overwritten if all conditions are satisfied
  runname      <- paste0(prefix_runname, scen)            # name of the run that is used for the folder names
  path_report  <- NULL                                    # sets the path to the report REMIND is started with in the first loop
  qos          <- scenarios_coupled[scen, "qos"]          # set the SLURM quality of service (priority/short/medium/...)
  if(is.null(qos) || is.na(qos)) qos <- "short"           # if qos could not be found in scenarios_coupled use short/medium
  sbatch       <- scenarios_coupled[scen, "sbatch"]       # retrieve sbatch options from scenarios_coupled
  if (is.null(sbatch) || is.na(sbatch)) sbatch <- ""      # if sbatch could not be found in scenarios_coupled use empty string
  start_iter_first <- 1                                   # iteration to start the coupling with
  scenarios_coupled[scen, "start_iter_first"] <- start_iter_first  # is used again when starting runs
  magpie_empty <- scenarios_coupled[scen, "magpie_empty"] # if magpie should be replaced by an empty model
  if (is.null(magpie_empty) || is.na(magpie_empty)) magpie_empty <- FALSE
  if (isTRUE(magpie_empty)) run_compareScenarios <- FALSE # no need to run cs2 on empty model

  # Check for existing REMIND and MAgPIE runs and whether iteration can be continued from those (at least one REMIND iteration has to exist!)
  # Look whether there is already a fulldata.gdx from a former REMIND run (check for old name if provided)
  iter_rem <- 0
  already_rem <- findLastRem(file.path(path_remind, "output"), runname)
  if (! is.na(already_rem)) {
    iter_rem <- as.integer(sub(".*rem-(\\d.*)/.*","\\1", already_rem))
  } else {
    message("No ", scen, " run found in current REMIND directory, now search for oldrun.")
    if (.isFileAndAvailable(scenarios_coupled[scen, "oldrun"], "/fulldata.gdx")) {
      already_rem <- scenarios_coupled[scen, "oldrun"]
    } else {
      lookfor <- if (is.na(scenarios_coupled[scen, "oldrun"])) scen else scenarios_coupled[scen, "oldrun"]
      already_rem <- findLastRem(path_remind_oldruns, paste0(prefix_oldruns, lookfor))
    }
  }

  if (.isFileAndAvailable(settings_remind[scen, "path_gdx"], "/fulldata.gdx")) {
    # if there is a REMIND gdx given in scenario_cofig or scenario_config_coupled, use it instead of the one found automatically
    message("Using REMIND gdx specified in ", basename(path_settings_coupled),
            " or ", basename(path_settings_remind),": ", settings_remind[scen, "path_gdx"])
  } else if (! is.na(already_rem)) {
    # if there is an existing REMIND run, use its gdx for the run to be started
    settings_remind[scen, "path_gdx"] <- normalizePath(already_rem)
    message("Found REMIND gdx here: ", normalizePath(already_rem))
  } else {
    message("No ", scen, " run found in REMIND oldrun directory, starting with ", runname, "-rem-1.")
  }

  # is there already a MAgPIE run with this name?
  iter_mag <- 0
  already_mag <- findLastMag(file.path(path_magpie, "output"), runname)
  if (! is.na(already_mag)) {
    iter_mag <- as.integer(sub(".*mag-(\\d.*)/.*","\\1",already_mag))
  } else {
    message("No ", scen, " run found in current MAgPIE directory, continue with oldrun")
    lookfor <- if (is.na(scenarios_coupled[scen, "oldrun"])) scen else scenarios_coupled[scen, "oldrun"]
    already_mag <- findLastMag(path_magpie_oldruns, paste0(prefix_oldruns, lookfor))
  }

  path_report_found <- NULL
  if (.isFileAndAvailable(scenarios_coupled[scen, "path_report"], "/report.mif")) {
    path_report_found <- scenarios_coupled[scen, "path_report"]
    message("Using MAgPIE report specified in ", basename(path_settings_coupled), ": ", scenarios_coupled[scen, "path_report"])
  } else if (! is.na(already_mag)) {
    path_report_found <- normalizePath(already_mag)
    message("Found MAgPIE report here: ", path_report_found)
  } else {
    message("No ", scen, " run found in MAgPIE oldrun directory, starting REMIND standalone.")
  }

  # decide whether to continue with REMIND or MAgPIE
  scenarios_coupled[scen, "start_magpie"] <- FALSE
  scenarios_coupled[scen, "start_scenario"] <- TRUE
  if (iter_rem == iter_mag + 1 & iter_rem < max_iterations) {
    # if only remind has finished an iteration -> start with magpie in this iteration using a REMIND report
    start_iter_first  <- iter_rem
    path_run    <- gsub("/fulldata.gdx", "", already_rem)
    path_report_found <- Sys.glob(file.path(path_run, "REMIND_generic_*"))[1] # take the first entry to ignore REMIND_generic_*_withoutPlus.mif
    if (is.na(path_report_found)) stop("There is a fulldata.gdx but no REMIND_generic_.mif in ", path_run,
                                       ".\nPlease use Rscript output.R to produce it.")
    message("Found REMIND report here: ", path_report_found)
    message("Starting MAgPIE run ", runname, "-mag-", start_iter_first, ".")
    scenarios_coupled[scen, "start_magpie"] <- TRUE
  } else if (iter_rem == iter_mag) {
    # if remind and magpie iteration is the same -> start next iteration with REMIND with or without MAgPIE report
    start_iter_first <- iter_rem + 1
    message("REMIND and MAgPIE ", if (iter_rem == 0) "were never started" else paste("each finished run", iter_rem), ".")
    message("Starting REMIND run ", runname, "-rem-", start_iter_first, ".")
  } else if (iter_rem >= max_iterations & iter_mag >= max_iterations - 1) {
    message("This scenario is already completed with rem-", iter_rem, " and mag-", iter_mag, " and max_iterations=", max_iterations, ".")
    scenarios_coupled[scen, "start_scenario"] <- FALSE
    next
  } else {
    message(red, "Error", NC, ": REMIND has finished ", iter_rem, " runs, but MAgPIE ", iter_mag, " runs. Something is wrong!")
    errorsfound <- errorsfound + 1
  }
  # save to use it later when starting runs
  scenarios_coupled[scen, "start_iter_first"] <- start_iter_first


  cfg <- readDefaultConfig(path_remind)   # retrieve REMIND settings
  cfg_rem <- cfg
  rm(cfg)
  cfg_rem$title <- scen
  rem_filesstart <- cfg_rem$files2export$start     # save to reset it to that later

  source(file.path(path_magpie, "config", "default.cfg")) # retrieve MAgPIE settings
  cfg_mag <- cfg
  rm(cfg)
  cfg_mag$title <- scen

  # configure MAgPIE according to magpie_scen (scenario needs to be available in scenario_config.cfg)
  if(!is.null(scenarios_coupled[scen, "magpie_scen"])) {
    cfg_mag <- setScenario(cfg_mag, c(trimws(unlist(strsplit(scenarios_coupled[scen, "magpie_scen"], split = ",|\\|"))), "coupling"),
                           scenario_config = file.path(path_magpie, "config", "scenario_config.csv"))
  }
  cfg_mag <- check_config(cfg_mag, reference_file=file.path(path_magpie, "config", "default.cfg"),
                          modulepath = file.path(path_magpie, "modules"))

  # GHG prices will be set to zero (in MAgPIE) until and including the year specified here
  if (!is.null(cfg_mag$gms$c56_mute_ghgprices_until)) {
    # Use the new name of the switch if it exists
    cfg_mag$gms$c56_mute_ghgprices_until <- scenarios_coupled[scen, "no_ghgprices_land_until"]
  } else {
    # To ensure backwards compatibility keep the old switch here for a while (has been transformed into a gms switch in MAgPIE)
    cfg_mag$mute_ghgprices_until <- scenarios_coupled[scen, "no_ghgprices_land_until"]
  }

  # Edit remind main model file, region settings and input data revision based on scenarios table, if cell non-empty
  for (switchname in intersect(c("model", "regionmapping", "extramappings_historic", "inputRevision"), names(settings_remind))) {
    if ( ! is.na(settings_remind[scen, switchname] )) {
      cfg_rem[[switchname]] <- settings_remind[scen, switchname]
    }
  }

  # Edit switches in default.cfg based on scenarios table, if cell non-empty
  for (switchname in intersect(names(cfg_rem$gms), names(settings_remind))) {
    if ( ! is.na(settings_remind[scen, switchname] )) {
      cfg_rem$gms[[switchname]] <- settings_remind[scen, switchname]
    }
  }

  # Set description
  if ("description" %in% names(settings_remind) && ! is.na(settings_remind[scen, "description"])) {
    cfg_rem$description <- gsub('"', '', settings_remind[scen, "description"])
  } else {
    cfg_rem$description <- paste0("Coupled REMIND and MAgPIE run ", scen, " started by ", path_settings_remind, " and ", path_settings_coupled, ".")
  }

  cm_nash_autoconverge <- cfg_rem$gms$cm_nash_autoconverge
  # save cm_nash_autoconverge to be used for last REMIND run
  if ("cm_nash_autoconverge_lastrun" %in% names(scenarios_coupled)) {
    cfg_rem$gms$cm_nash_autoconverge <- scenarios_coupled[scen, "cm_nash_autoconverge_lastrun"]
  }

  # abort on too long paths ----
  cfg_rem$gms$cm_CES_configuration <- calculate_CES_configuration(cfg_rem, check = TRUE)

  for (i in max_iterations:start_iter_first) {
    fullrunname <- paste0(runname, "-rem-", i)
    start_iter <- i

    # If provided replace the path to the MAgPIE report found automatically with path given in scenario_config_coupled.csv
    if (i == start_iter_first) {
      if (! is.na(scenarios_coupled[scen, "path_report"]) & i == 1) {
        path_report <- scenarios_coupled[scen, "path_report"] # sets the path to the report REMIND is started with in the first loop
        message("Replacing path to MAgPIE report with that one specified in\n  ", path_settings_coupled, "\n  ", scenarios_coupled[scen, "path_report"], "\n")
      } else {
        path_report <- path_report_found
      }
    } else {
      # start_coupled.R uses the name of this run to create the name of the MAgPIE report for the subsequent runs (next iteration)
      path_report <- runname
    }

    # if provided use ghg prices for land (MAgPIE) from a different REMIND run than the one MAgPIE runs coupled to
    path_mif_ghgprice_land <- NULL
    if ("path_mif_ghgprice_land" %in% names(scenarios_coupled)) {
      if (! is.na(scenarios_coupled[scen, "path_mif_ghgprice_land"])) {
        if (.isFileAndAvailable(scenarios_coupled[scen, "path_mif_ghgprice_land"], ".mif")) {
            # if real file is given (has ".mif" at the end) take it for path_mif_ghgprice_land
            path_mif_ghgprice_land <- normalizePath(scenarios_coupled[scen, "path_mif_ghgprice_land"])
        } else if (scenarios_coupled[scen, "path_mif_ghgprice_land"] %in% common) {
            # if no real file is given but a reference to another scenario (that has to run first) create path to the reference scenario
            ghgprice_remindrun <- paste0(prefix_runname, scenarios_coupled[scen, "path_mif_ghgprice_land"], "-rem-", i)
            path_mif_ghgprice_land <- file.path(path_remind, "output", ghgprice_remindrun, paste0("REMIND_generic_", ghgprice_remindrun, ".mif"))
        } else {
          message(red, "Error", NC, ": path_mif_ghgprice_land neither an existing file nor a scenario that will be started: ",
                  scenarios_coupled[scen, "path_mif_ghgprice_land"])
          errorsfound <- errorsfound + 1
          path_mif_ghgprice_land <- FALSE
        }
        cfg_mag$path_to_report_ghgprices <- path_mif_ghgprice_land
      }
    }

    # Create list of previously defined paths to gdxs
    gdxlist <- unlist(settings_remind[scen, names(path_gdx_list)])
    names(gdxlist) <- path_gdx_list
    gdxlist[gdxlist %in% rownames(settings_coupled)] <- paste0(prefix_runname, gdxlist[gdxlist %in% rownames(settings_coupled)], "-rem-", i)
    possibleFulldata <- file.path(path_remind, "output", gdxlist, "fulldata.gdx")
    possibleRemindReport <- file.path(path_remind, "output", gdxlist, paste0("REMIND_generic_", gdxlist, ".mif"))
    # if file fulldata.gdx and report already exists because run was already finished, use it directly as input
    replaceByFulldata <- file.exists(possibleFulldata) & file.exists(possibleRemindReport)
    gdxlist[replaceByFulldata] <- possibleFulldata[replaceByFulldata]

    if (i == start_iter_first) {
      gdx_specified <- grepl(".gdx", gdxlist, fixed = TRUE)
      gdx_na <- is.na(gdxlist)
      start_now <- all(gdx_specified | gdx_na)
    }

    # remove gdxlist generated by earlier i
    cfg_rem$files2export$start <- rem_filesstart
    # Remove potential elements that contain ".gdx" and append gdxlist
    cfg_rem$files2export$start <- .setgdxcopy(".gdx", cfg_rem$files2export$start, gdxlist)

    # add table with information about runs that need the fulldata.gdx of the current run as input (will be further processed in start_coupled.R)
    cfg_rem$RunsUsingTHISgdxAsInput <- settings_remind[common, ] %>% select(contains("path_gdx")) %>%    # select columns that have "path_gdx" in their name
                                                 filter(rowSums(. == scen, na.rm = TRUE) > 0)           # select rows that have the current scenario in any column
    if (length(cfg_rem$RunsUsingTHISgdxAsInput[[1]]) > 0) {
      cfg_rem$RunsUsingTHISgdxAsInput[! is.na(cfg_rem$RunsUsingTHISgdxAsInput)] <- paste0(prefix_runname,
                    cfg_rem$RunsUsingTHISgdxAsInput[! is.na(cfg_rem$RunsUsingTHISgdxAsInput)], "-rem-", i)
      rownames(cfg_rem$RunsUsingTHISgdxAsInput) <- paste0(prefix_runname, rownames(cfg_rem$RunsUsingTHISgdxAsInput), "-rem-", i)
    }
    # add the next remind run
    if (i < max_iterations) {
      cfg_rem$RunsUsingTHISgdxAsInput[paste0(runname, "-rem-", (i+1)), "path_gdx"] <- fullrunname
      cfg_rem$gms$cm_nash_autoconverge <- cm_nash_autoconverge
    } else if ("cm_nash_autoconverge_lastrun" %in% names(scenarios_coupled)) {
      cfg_rem$gms$cm_nash_autoconverge <- scenarios_coupled[scen, "cm_nash_autoconverge_lastrun"]
    }

    if (i > start_iter_first || ! start_now) {
      # if no real file is given but a reference to another scenario (that has to run first) create path for input_ref and input_bau
      # using the scenario names given in the columns path_gdx_ref and path_gdx_ref in the REMIND standalone scenario config
      for (path_gdx in names(path_gdx_list)) {
        if (! is.na(cfg_rem$files2export$start[path_gdx_list[path_gdx]]) && ! grepl(".gdx", cfg_rem$files2export$start[path_gdx_list[path_gdx]], fixed = TRUE)) {
          cfg_rem$files2export$start[path_gdx_list[path_gdx]] <- paste0(prefix_runname, settings_remind[scen, path_gdx],
                                                                        "-rem-", i)
        }
      }
      if (i > start_iter_first) {
        cfg_rem$files2export$start["input.gdx"] <- paste0(runname, "-rem-", i-1)
      }
      # If the preceding run has already finished (= its gdx file exist) start
      # the current run immediately. This might be the case e.g. if you started
      # the NDC run in a first batch and now want to start the subsequent policy
      # runs by hand after the NDC has finished.
    }
    if (i == start_iter_first && ! start_now && all(file.exists(cfg_rem$files2export$start[path_gdx_list]) | unlist(gdx_na))) {
        start_now <- TRUE
    }
    foldername <- file.path("output", fullrunname)
    if ((i > start_iter_first || !scenarios_coupled[scen, "start_magpie"]) && file.exists(foldername)) {
      if (errorsfound == 0) {
        if (! "--test" %in% flags) unlink(foldername, recursive = TRUE, force = TRUE)
        message("Delete ", foldername, if ("--test" %in% flags) " if not in test mode", ". ", appendLF = FALSE)
        deletedFolders <- deletedFolders + 1
      }
    }

    if (cfg_rem$gms$optimization == "nash" && cfg_rem$gms$cm_nash_mode == "parallel" && isFALSE(magpie_empty)) {
      # for nash: set the number of CPUs per node to number of regions + 1
      numberOfTasks <- length(unique(read.csv2(cfg_rem$regionmapping)$RegionCode)) + 1
    } else {
      # for negishi and model tests: use only one CPU
      numberOfTasks <- 1
    }

    Rdatafile <- paste0(fullrunname, ".RData")
    message("Save settings to ", Rdatafile)
    save(path_remind, path_magpie, cfg_rem, cfg_mag, runname, fullrunname, max_iterations, start_iter,
         n600_iterations, path_report, qos, sbatch, prefix_runname, run_compareScenarios, magpie_empty,
         numberOfTasks, start_now, file = Rdatafile)

  } # end for (i %in% iterations)

  # convert from logi to character so file.exists does not throw an error
  path_report <- as.character(path_report)


  message("\nSUMMARY")
  message("runname       : ", runname)
  message("Start iter    : ", if (scenarios_coupled[scen, "start_magpie"]) "mag-" else "rem-", start_iter_first)
  message("QOS           : ", qos)
  message("remind gdxes  :")
  for (path_gdx in names(path_gdx_list)) {
      gdxname <- cfg_rem$files2export$start[path_gdx_list[path_gdx]]
      gdxfound <- (is.na(gdxname) || file.exists(gdxname))
      usecolor <- if (gdxfound) green else if (gdxname %in% knownRefRuns) blue else red
      message("  ", str_pad(path_gdx, 23, "right"), ": ", usecolor, gdxname, NC)
  }
  if (! is.null(path_mif_ghgprice_land)) {
    usecolor <- if (isFALSE(path_mif_ghgprice_land)) red else if (file.exists(path_mif_ghgprice_land)) green else blue
    message("ghg_price_mag : ", usecolor, path_mif_ghgprice_land, NC, "\n")
  }
  message("path_report   : ",ifelse(file.exists(path_report),green,red), path_report, NC)
  message("no_ghgprices_land_until: ", cfg_mag$gms$c56_mute_ghgprices_until)

  if ("--gamscompile" %in% flags) {
    message("Compiling ", fullrunname)
    lockID <- gms::model_lock()
    gcresult <- runGamsCompile(if (is.null(cfg_rem$model)) "main.gms" else cfg_rem$model, cfg_rem,
                               interactive = "--interactive" %in% flags)
    gms::model_unlock(lockID)
    errorsfound <- errorsfound + ! gcresult
  }
  if (!start_now) {
    missingRefRuns <- unique(cfg_rem$files2export$start[path_gdx_list][! gdx_specified & ! gdx_na])
    message("Waiting for: ", blue, paste(intersect(knownRefRuns, missingRefRuns), collapse = ", "), NC)
    if (length(setdiff(missingRefRuns, knownRefRuns)) > 0) {
      message(red, "Error", NC, ": Cannot start because ", paste(setdiff(missingRefRuns, knownRefRuns), collapse = ", "), " not found!")
      errorsfound <- errorsfound + length(setdiff(missingRefRuns, knownRefRuns))
    } else {
      waitingRuns <- waitingRuns + 1
    }
  }
}

# start runs
message("\nStarting Runs")
for (scen in common) {
  if (!scenarios_coupled[scen, "start_scenario"]) {
    next
  }
  start_iter_first <- scenarios_coupled[scen, "start_iter_first"]
  runname <- paste0(prefix_runname, scen)
  fullrunname <- paste0(runname, "-rem-", start_iter_first)
  Rdatafile <- paste0(fullrunname, ".RData")
  runEnv <- new.env()
  load(Rdatafile, envir = runEnv)

  if (runEnv$start_now) {
    if (errorsfound > 0) {
      message("Errors found: run ", fullrunname, " NOT submitted to the cluster.")
    } else {
      startedRuns <- startedRuns + 1
      if ("--test" %in% flags || "--gamscompile" %in% flags) {
        message("Test mode: run ", fullrunname, " NOT submitted to the cluster.")
      } else {
        logfile <- file.path("output", fullrunname, paste0("log", if (scenarios_coupled[scen, "start_magpie"]) "-mag", ".txt"))
        if (! file.exists(dirname(logfile))) dir.create(dirname(logfile))
        message("Find logging in ", logfile)
        slurm_command <- paste0("sbatch --qos=", runEnv$qos, " --mem=8000 --job-name=", fullrunname,
        " --output=", logfile, " --mail-type=END --comment=REMIND-MAgPIE --tasks-per-node=", runEnv$numberOfTasks,
        " ", runEnv$sbatch, " --wrap=\"Rscript start_coupled.R coupled_config=", Rdatafile, "\"")
        message(slurm_command)
        exitCode <- system(slurm_command)
        if (0 < exitCode) {
          errorsfound <- errorsfound + 1
          message("sbatch command failed, check logs.")
        }
      }
    }
  }
}

if (! "--test" %in% flags && ! "--gamscompile" %in% flags) {
  system(paste("cp", file.path(path_remind, ".Rprofile "), file.path(path_magpie, ".Rprofile")))
  message("\nCopied REMIND .Rprofile to MAgPIE folder.")
  cs_runs <- paste0(file.path("output", paste0(prefix_runname, common, "-rem-", max_iterations)), collapse = ",")
  cs_name <- paste0("compScen-all-rem-", max_iterations)
  cs_qos <- if (! isFALSE(run_compareScenarios)) run_compareScenarios else "short"
  cs_command <- paste0("sbatch --qos=", cs_qos, " --job-name=", cs_name, " --output=", cs_name, ".out --error=",
    cs_name, ".out --mail-type=END --time=60 --wrap='Rscript scripts/cs2/run_compareScenarios2.R outputDirs=",
    cs_runs, " profileName=REMIND-MAgPIE outFileName=", cs_name,
    " regionList=World,LAM,OAS,SSA,EUR,NEU,MEA,REF,CAZ,CHA,IND,JPN,USA mainRegName=World'")
  message("\n### To start a compareScenario once everything is finished, run:")
  message(cs_command)
}

message("\nFinished: ", deletedFolders, " folders deleted. ", startedRuns, " runs started. ", waitingRuns, " runs are waiting.",
        if("--test" %in% flags) "\nYou are in TEST mode, only RData files were written.")
# make sure we have a non-zero exit status if there were any errors
if (0 < errorsfound) {
  stop(red, errorsfound, NC, " errors were identified, check logs above for details.")
}
