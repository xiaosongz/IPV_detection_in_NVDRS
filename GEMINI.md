# Gemini Code Assistant Context

## Project Overview

This R project provides a minimalist approach to detecting Intimate Partner Violence (IPV) in text narratives using Large Language Models (LLMs). The core of the project is the `detect_ipv` function, which sends a narrative to an LLM and parses the response to determine if IPV is present.

The project is designed with a "Unix philosophy" in mind, providing simple, focused functions that can be composed together. It includes optional features for storing results in a database (SQLite or PostgreSQL) and for tracking and comparing different prompt versions through experiments.

### Key Technologies

*   **Language:** R
*   **Core Packages:**
    *   `httr2`: For making HTTP requests to the LLM API.
    *   `jsonlite`: For working with JSON data.
    *   `DBI`, `RSQLite`, `RPostgres`: For database interactions.
    *   `digest`: For hashing prompts.
*   **Database:** SQLite (for local development) and PostgreSQL (for production).

### Architecture

The project is structured as an R package. The main components are:

*   **Core Functions:**
    *   `call_llm()`: Makes the API call to the LLM.
    *   `parse_llm_result()`: Parses the JSON response from the LLM.
    *   `store_llm_result()`: Stores the parsed result in the database.
*   **Database Utilities:**
    *   `get_db_connection()`, `connect_postgres()`: Functions to connect to SQLite and PostgreSQL databases.
    *   `ensure_schema()`: Creates the necessary database tables.
*   **Experiment Utilities:**
    *   `register_prompt()`: Registers a new prompt version for an experiment.
    *   `start_experiment()`, `complete_experiment()`: Functions to manage the lifecycle of an experiment.
    *   `store_experiment_result()`: Stores results for a specific experiment.

## Building and Running

This is an R package, so the standard R development workflow applies.

### Installation

To use the package, you can either source the R files directly or build and install the package.

```R
# Install dependencies
install.packages(c("httr2", "jsonlite", "DBI", "RSQLite", "RPostgres", "digest"))

# Load the functions
source("R/0_setup.R")
source("R/call_llm.R")
source("R/parse_llm_result.R")
source("R/store_llm_result.R")
source("R/db_utils.R")
source("R/experiment_utils.R")
```

### Running Tests

The project uses the `testthat` package for testing. To run the tests, you can use the following command in an R session:

```R
# Run all tests
testthat::test_dir("tests/testthat")
```

## Development Conventions

*   **Style:** The code follows the `tidyverse` style guide.
*   **Simplicity:** The project emphasizes simplicity and minimalism, avoiding unnecessary abstractions.
*   **Documentation:** Functions are well-documented using `roxygen2` style comments.
*   **Database:** The project provides a unified interface for working with both SQLite and PostgreSQL. Schema definitions are located in the `inst/sql` directory.
*   **Experiments:** The project has a dedicated set of functions and a database schema for managing and tracking experiments with different prompts.
