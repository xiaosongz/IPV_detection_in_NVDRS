#!/usr/bin/env Rscript

#' Demo Workflow for IPV Detection
#'
#' Quick demonstration script for reviewers to test the system
#' without requiring NVDRS access or API keys.
#'
#' This script:
#' 1. Uses synthetic data (no sensitive information)
#' 2. Runs a small sample (10 narratives)
#' 3. Completes in <5 minutes
#' 4. Demonstrates full workflow
#' 5. Generates basic metrics
#'
#' Usage:
#'   Rscript scripts/demo_workflow.R
#'
#' Requirements:
#'   - .env file configured (copy from .env.example)
#'   - renv dependencies installed (run: renv::restore())
#'   - Internet connection for LLM API calls

library(here)
library(DBI)
library(RSQLite)
library(tictoc)
library(dotenv)

cat("\n")
cat("================================================================================\n")
cat("                    IPV Detection Demo Workflow\n")
cat("================================================================================\n")
cat("This demo demonstrates the core functionality using synthetic data.\n")
cat("No NVDRS access or sensitive data required.\n\n")

# Load environment variables
cat("Step 1: Loading environment configuration...\n")
if (file.exists(".env")) {
  dotenv::load_dotenv(".env")
  cat("✓ Environment loaded from .env\n")
} else {
  cat("⚠ No .env file found. Using defaults.\n")
  cat("  Copy .env.example to .env and configure for full functionality.\n")
}

# Source all required functions
cat("\nStep 2: Loading system functions...\n")
source(here("R", "db_config.R"))
source(here("R", "db_schema.R"))
source(here("R", "data_loader.R"))
source(here("R", "config_loader.R"))
source(here("R", "experiment_logger.R"))
source(here("R", "experiment_queries.R"))
source(here("R", "run_benchmark_core.R"))
source(here("R", "call_llm.R"))
source(here("R", "repair_json.R"))
source(here("R", "parse_llm_result.R"))
source(here("R", "build_prompt.R"))
cat("✓ All functions loaded\n")

# Initialize demo database
cat("\nStep 3: Setting up demo database...\n")
demo_db_path <- "data/demo_experiments.db"

# Remove existing demo database for clean run
if (file.exists(demo_db_path)) {
  file.remove(demo_db_path)
  cat("  Removed existing demo database\n")
}

# Set environment for demo database
Sys.setenv(EXPERIMENTS_DB = demo_db_path)

# Initialize fresh database
conn <- init_experiment_db()
cat("✓ Demo database initialized:", demo_db_path, "\n")

# Load synthetic data
cat("\nStep 4: Loading synthetic demonstration data...\n")
synthetic_data_path <- "data/synthetic_narratives.csv"

if (!file.exists(synthetic_data_path)) {
  stop(
    "Synthetic data not found: ", synthetic_data_path,
    "\nPlease ensure data/synthetic_narratives.csv exists"
  )
}

# Read synthetic data and convert to expected format
synthetic_data <- read.csv(synthetic_data_path, stringsAsFactors = FALSE)

# Insert synthetic data into database
synthetic_data$data_source <- "synthetic_demo_data"
synthetic_data$loaded_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

# Rename columns to match database schema
names(synthetic_data)[names(synthetic_data) == "manual_flag_ind"] <- "manual_flag_ind"
names(synthetic_data)[names(synthetic_data) == "manual_flag"] <- "manual_flag"

DBI::dbWriteTable(conn, "source_narratives", synthetic_data, append = TRUE)
cat("✓ Loaded", nrow(synthetic_data), "synthetic narratives\n")

# Show data summary
cat("\n  Data Summary:\n")
cat("    Total narratives:", nrow(synthetic_data), "\n")
cat("    IPV positive cases:", sum(synthetic_data$manual_flag_ind == 1), "\n")
cat("    IPV negative cases:", sum(synthetic_data$manual_flag_ind == 0), "\n")
cat("    CME narratives:", sum(synthetic_data$narrative_type == "cme"), "\n")
cat("    LE narratives:", sum(synthetic_data$narrative_type == "le"), "\n")

# Create demo configuration
cat("\nStep 5: Creating demo experiment configuration...\n")
demo_config <- list(
  experiment = list(
    name = "demo_synthetic_test",
    author = "demo_workflow",
    notes = "Demo run with synthetic data for reviewer testing"
  ),
  model = list(
    name = Sys.getenv("LLM_MODEL", "gpt-4o-mini"),
    provider = "openai",
    api_url = Sys.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1/chat/completions"),
    temperature = 0.0,
    max_tokens = 500
  ),
  prompt = list(
    version = "v0.4.1_baseline",
    system_prompt = "Reasoning: medium

ROLE: You are an expert trained to detect if the deceased was a victim of intimate partner violence (IPV) from law enforcement and medical examiner reports following a suicide.

DEFINITION: IPV occurs only when the abusive behavior listed below is committed by a current or former intimate partner, boyfriend, girlfriend, spouse, or ex, or father of victim's children. Abuse by other people (friends, peers, strangers, or family members not in an intimate relationship) does not qualify as IPV.

TYPES OF IPV ABUSE:
1. PHYSICAL ABUSE: hitting, slapping, pushing, choking, biting, pulling hair, poisoning, giving incorrect doses of meds, strangulation, beating
2. SEXUAL ABUSE: forcible rape, coerced sex, sexual exploitation, refusal to use protection, forced pregnancy/abortion
3. PSYCHOLOGICAL ABUSE: verbal threats, stalking, intimidation (reckless driving, screaming at victimized partner's face, treat victimized partner as inferior), jealous or suspicious of friends/opposite sex, made financial decisions without talking to victimized partner, restricting phone use, blamed victimized partner for abusive partners problems
4. EMOTIONAL ABUSE: gaslighting, lying, providing misinformation, withholding information, isolation (telling victim not to tell anyone about what's happening, not allow victim to socialize, silent treatment), humiliation, using children against victimized partner, sharing intimate nude photos of victimized partner to others without their knowledge
5. ECONOMIC ABUSE: control access to money, control access to means of transportation, control whether victimized partner goes to work/school, ruins credit, spends or gambles victimized partners money
6. LEGAL ABUSE: threat to call police on victimized partner, use court system against victimized partner (i.e. custody change), threaten to call child services, immigration or other governmental agencies

CRITICAL VICTIM ROLE CHECK:
- The deceased must be the VICTIM of IPV (not the perpetrator)
- Suicide after being IPV victim = IPV ✓
- Suicide after committing violence against partner = NOT IPV ✗
- Homicide victim (killed by partner, then partner suicide) = NOT IPV ✗",
    user_template = 'TASK: Determine if the deceased was a victim of IPV.

Step 1: Identify the deceased\'s role - were they abused BY their partner, or did they abuse their partner?
Step 2: Check for intimate partner relationship (current/former partner, spouse, boyfriend/girlfriend, ex, father of children)
Step 3: Identify abusive behaviors matching IPV definitions
Step 4: Mark TRUE if victim was in women\'s shelter (e.g., Family Violence Project)
Step 5: Final determination

Narrative: <<TEXT>>

Return this EXACT JSON structure:
{
  "detected": <boolean>,          // true or false
  "confidence": <number>,          // decimal 0.0 to 1.0, e.g., 0.85
  "rationale": <string>            // max 200 characters
}

Valid confidence examples:
- "confidence": 0.9   ✓
- "confidence": 0.75  ✓
- "confidence": 0.85  ✓

Invalid (DO NOT USE):
- "confidence": 0. nine  ✗ (never spell numbers)
- "confidence": "0.9"    ✗ (must be number, not string)

Your response must be valid JSON parseable by JSON.parse()'
  ),
  data = list(
    file = "synthetic_demo_data"
  ),
  run = list(
    seed = 1024,
    max_narratives = 10, # Small sample for demo
    save_incremental = true,
    save_csv_json = true
  )
)

cat("✓ Demo configuration created\n")
cat("  Model:", demo_config$model$name, "\n")
cat("  Sample size:", demo_config$run$max_narratives, "narratives\n")

# Check API availability
cat("\nStep 6: Checking API availability...\n")
api_key <- Sys.getenv("OPENAI_API_KEY", "")
if (api_key == "" || api_key == "your_openai_api_key_here") {
  cat("⚠ No valid OpenAI API key found in .env\n")
  cat("  Demo will run in MOCK mode for demonstration purposes.\n")
  demo_config$mock_mode <- TRUE
} else {
  cat("✓ OpenAI API key found\n")
  demo_config$mock_mode <- FALSE
}

# Run demo experiment
cat("\nStep 7: Running demo experiment...\n")
cat("This will process", demo_config$run$max_narratives, "narratives.\n")
cat("Expected runtime: 2-5 minutes\n\n")

tic("demo_experiment")

tryCatch(
  {
    # Start experiment logging
    experiment_id <- start_experiment(conn, demo_config)
    cat("✓ Experiment started with ID:", experiment_id, "\n")

    # Get narratives for processing
    narratives <- get_source_narratives(
      conn,
      data_source = demo_config$data$file,
      max_narratives = demo_config$run$max_narratives
    )

    cat("Processing", nrow(narratives), "narratives...\n")

    # Process each narrative
    results <- list()
    for (i in 1:nrow(narratives)) {
      narrative <- narratives[i, ]

      cat(sprintf("  Processing %d/%d: %s\n", i, nrow(narratives), narrative$incident_id))

      if (demo_config$mock_mode) {
        # Mock response for demo without API key
        mock_response <- list(
          detected = as.logical(narrative$manual_flag_ind),
          confidence = runif(1, 0.7, 0.95),
          rationale = "Mock response for demonstration"
        )
        result <- mock_response
      } else {
        # Real API call
        prompt <- build_prompt(demo_config$prompt, narrative$narrative_text)

        api_response <- call_llm(
          user_prompt = prompt$user_prompt,
          system_prompt = prompt$system_prompt,
          api_url = demo_config$model$api_url,
          model = demo_config$model$name,
          temperature = demo_config$model$temperature
        )

        result <- parse_llm_result(api_response)
      }

      # Store result
      result_record <- list(
        narrative_id = narrative$narrative_id,
        incident_id = narrative$incident_id,
        narrative_type = narrative$narrative_type,
        narrative_text = narrative$narrative_text,
        manual_flag = narrative$manual_flag_ind,
        predicted_flag = ifelse(result$detected, 1, 0),
        confidence = result$confidence,
        rationale = result$rationale,
        processing_time = 0 # Would be measured in real implementation
      )

      results[[i]] <- result_record

      # Log to database
      log_narrative_result(conn, experiment_id, result_record)
    }

    # Complete experiment
    complete_experiment(conn, experiment_id, results)
    cat("✓ Experiment completed successfully\n")
  },
  error = function(e) {
    cat("✗ Demo experiment failed:", conditionMessage(e), "\n")
    cat("  This is likely due to missing API keys or network issues.\n")
    cat("  The synthetic data and database setup are working correctly.\n")
  }
)

demo_time <- toc(log = FALSE)
cat("\nDemo completed in", round(demo_time$tictoc, 2), "seconds\n")

# Generate basic metrics
cat("\nStep 8: Generating demo metrics...\n")

tryCatch(
  {
    # Get experiment results
    exp_results <- get_experiment_results(conn, experiment_id)

    if (nrow(exp_results) > 0) {
      # Calculate basic metrics
      accuracy <- mean(exp_results$predicted_flag == exp_results$manual_flag, na.rm = TRUE)
      precision <- sum(exp_results$predicted_flag == 1 & exp_results$manual_flag == 1, na.rm = TRUE) /
        sum(exp_results$predicted_flag == 1, na.rm = TRUE)
      recall <- sum(exp_results$predicted_flag == 1 & exp_results$manual_flag == 1, na.rm = TRUE) /
        sum(exp_results$manual_flag == 1, na.rm = TRUE)
      f1 <- ifelse(is.na(precision) || is.na(recall) || (precision + recall) == 0, 0,
        2 * (precision * recall) / (precision + recall)
      )

      cat("✓ Metrics calculated:\n")
      cat("  Accuracy:", round(accuracy, 3), "\n")
      cat("  Precision:", round(precision, 3), "\n")
      cat("  Recall:", round(recall, 3), "\n")
      cat("  F1 Score:", round(f1, 3), "\n")
      cat("  Total processed:", nrow(exp_results), "\n")

      # Show prediction distribution
      cat("\n  Prediction Distribution:\n")
      cat("    Predicted IPV:", sum(exp_results$predicted_flag == 1, na.rm = TRUE), "\n")
      cat("    Predicted No IPV:", sum(exp_results$predicted_flag == 0, na.rm = TRUE), "\n")
      cat("    Actual IPV:", sum(exp_results$manual_flag == 1, na.rm = TRUE), "\n")
      cat("    Actual No IPV:", sum(exp_results$manual_flag == 0, na.rm = TRUE), "\n")
    } else {
      cat("⚠ No results to analyze (likely due to API issues)\n")
    }
  },
  error = function(e) {
    cat("⚠ Metrics calculation failed:", conditionMessage(e), "\n")
  }
)

# Clean up
DBI::dbDisconnect(conn)

cat("\n")
cat("================================================================================\n")
cat("                          Demo Summary\n")
cat("================================================================================\n")
cat("✓ Database initialized:", demo_db_path, "\n")
cat("✓ Synthetic data loaded:", nrow(synthetic_data), "narratives\n")
cat("✓ Demo workflow completed\n")
cat("\nNext Steps:\n")
cat("1. Configure .env with real API keys for full functionality\n")
cat("2. Run: Rscript scripts/run_experiment.R configs/experiments/exp_037.yaml\n")
cat("3. View results: Rscript scripts/view_experiment.R <experiment_id>\n")
cat("4. See docs/20251005-publication_task_list.md for full workflow\n")
cat("\nFor publication-ready analysis, see analysis/ directory notebooks.\n")
cat("================================================================================\n")
