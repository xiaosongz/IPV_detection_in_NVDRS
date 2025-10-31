#' Run Benchmark Core Processing
#'
#' Processes narratives through LLM and logs results to database
#'
#' @param config Experiment configuration from load_experiment_config()
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param narratives Tibble of narratives from get_source_narratives()
#' @param logger Logger object from init_experiment_logger()
#' @return Tibble with all results
#' @export
#' @examples
#' \dontrun{
#' # Set up experiment components
#' config <- load_experiment_config("configs/experiments/exp_037_baseline_v4_t00_medium.yaml")
#' conn <- get_db_connection()
#' experiment_id <- start_experiment(conn, config)
#' logger <- init_experiment_logger(experiment_id)
#' narratives <- get_source_narratives(conn, max_narratives = 10)
#'
#' # Run benchmark (processes narratives through LLM)
#' results <- run_benchmark_core(config, conn, experiment_id, narratives, logger)
#' print(nrow(results))
#'
#' # Finalize experiment
#' finalize_experiment(conn, experiment_id)
#' dbDisconnect(conn)
#' }
run_benchmark_core <- function(config, conn, experiment_id, narratives, logger, batch_size = 100) {
  # Update experiment with total narratives count
  DBI::dbExecute(conn,
    "UPDATE experiments SET n_narratives_total = ? WHERE experiment_id = ?",
    params = list(nrow(narratives), experiment_id)
  )

  cat("\n========================================\n")
  cat("Processing", nrow(narratives), "narratives\n")
  cat("Batch commits every", batch_size, "narratives\n")
  cat("========================================\n\n")

  logger$info(paste("Starting processing of", nrow(narratives), "narratives"))

  processed_count <- 0
  skipped_count <- 0
  error_count <- 0

  for (i in 1:nrow(narratives)) {
    narrative <- narratives[i, ]

    # Build prompts
    system_prompt <- config$prompt$system_prompt
    user_prompt <- substitute_template(config$prompt$user_template, narrative$narrative_text)

    # Call LLM with timing
    tictoc::tic()
    response <- tryCatch(
      {
        call_llm(
          system_prompt = system_prompt,
          user_prompt = user_prompt,
          api_url = config$model$api_url,
          model = config$model$name,
          temperature = config$model$temperature
        )
      },
      error = function(e) {
        list(error = TRUE, error_message = as.character(e))
      }
    )
    timing <- tictoc::toc(quiet = TRUE)
    response_sec <- as.numeric(timing$toc - timing$tic)

    # Parse response
    result <- parse_llm_result(response, narrative_id = narrative$incident_id)

    # Add metadata
    result$row_num <- i
    result$incident_id <- if (is.na(narrative$incident_id)) {
      NA_character_
    } else {
      as.character(narrative$incident_id)
    }
    result$narrative_type <- narrative$narrative_type
    result$narrative_text <- narrative$narrative_text
    result$manual_flag_ind <- narrative$manual_flag_ind
    result$manual_flag <- narrative$manual_flag
    result$response_sec <- response_sec

    # Log to database (handles idempotency via UNIQUE constraint)
    tryCatch(
      {
        log_narrative_result(conn, experiment_id, result)
        processed_count <- processed_count + 1

        # Log success
        logger$performance(narrative$incident_id, response_sec, "OK")
        logger$api_call(narrative$incident_id, response_sec, "SUCCESS")
      },
      error = function(e) {
        error_count <- error_count + 1
        error_msg <- conditionMessage(e)
        
        # Check if it's a duplicate (idempotency violation)
        if (grepl("UNIQUE constraint failed", error_msg, ignore.case = TRUE)) {
          logger$info(paste("Skipped duplicate:", narrative$incident_id, narrative$narrative_type))
          skipped_count <- skipped_count + 1
        } else {
          logger$error(paste("Failed to log result for narrative", narrative$incident_id), e)
          logger$performance(narrative$incident_id, 0, "ERROR")
        }
      }
    )

    # Batched commit and progress update
    if (processed_count %% batch_size == 0 || i == nrow(narratives)) {
      # Commit transaction
      tryCatch({
        # SQLite auto-commits, but we can ensure consistency
        DBI::dbExecute(conn, "PRAGMA wal_checkpoint(PASSIVE)")
      }, error = function(e) {
        # Ignore checkpoint errors
      })
      
      # Update progress in experiments table
      update_experiment_progress(conn, experiment_id, processed_count)
      
      cat(sprintf("  [%d/%d processed", processed_count, nrow(narratives)))
      if (skipped_count > 0) {
        cat(sprintf(", %d skipped", skipped_count))
      }
      if (error_count > 0) {
        cat(sprintf(", %d errors", error_count))
      }
      cat("] - Progress saved\n")
      
      logger$info(sprintf("Progress: %d/%d processed, %d skipped, %d errors (batch commit)", 
                          processed_count, nrow(narratives), skipped_count, error_count))
    } else if (i %% 5 == 0) {
      # Light progress update (no DB write)
      cat(sprintf("  [%d/%d processed", processed_count, nrow(narratives)))
      if (error_count > 0) {
        cat(sprintf(", %d errors", error_count))
      }
      cat("]\n")
    }
  }

  cat("\n========================================\n")
  cat("✓ Processing complete!\n")
  cat("  Processed:", processed_count, "\n")
  if (skipped_count > 0) {
    cat("  Skipped (duplicates):", skipped_count, "\n")
  }
  if (error_count > 0) {
    cat("  Errors:", error_count, "\n")
  }
  cat("========================================\n\n")

  logger$info(paste("Processing complete:", processed_count, "narratives,", skipped_count, "skipped,", error_count, "errors"))

  # Return results from database
  get_experiment_results(conn, experiment_id)
}
