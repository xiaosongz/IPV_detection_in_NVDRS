# Improvement Plan: Automated Experiment Tracking

This document outlines a plan to evolve the current benchmarking process into a robust, automated, and database-driven experiment tracking system.

## 1. The Vision: From Manual Scripts to an Experiment Hub

The current process, while functional, is manual and error-prone. By implementing a more structured approach, we can create an "Experiment Hub" that will serve as a single source of truth for all benchmarking and experimentation activities.

**The core of this vision is a centralized database that tracks everything:**

*   **Experiments:** High-level information about each experiment, including the author, the model, the prompt, and the start/end times.
*   **Narratives:** Detailed, narrative-level results, including the LLM's reasoning, the generated flag, and a comparison to the ground truth.
*   **Performance:** Automated summaries of each experiment's performance, including accuracy, precision, recall, and other key metrics.

## 2. Community Best Practices

My research into community best practices for MLOps and experiment tracking confirms that your vision is spot-on. The key principles are:

*   **Centralized Tracking:** All experiment metadata, results, and artifacts should be stored in a central location.
*   **Automation:** The process of running experiments and logging results should be as automated as possible.
*   **Reproducibility:** It should be easy to reproduce any experiment, including the exact code, data, and configuration.
*   **Analysis and Comparison:** The system should make it easy to analyze and compare the results of different experiments.

While there are dedicated tools like MLflow and Weights & Biases, your existing database-centric approach is a great foundation to build upon. We can create a powerful, custom solution without the overhead of a new tool.

## 3. Proposed Solution: A Database-Driven Workflow

I propose we enhance the existing database with a more comprehensive schema and build a new, automated workflow around it.

### 3.1. Enhanced Database Schema

We will add the following tables to your database. This schema is designed to be flexible and extensible.

**`experiments` table:**

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER` | Primary Key |
| `name` | `TEXT` | A human-readable name for the experiment |
| `author` | `TEXT` | The person who ran the experiment |
| `prompt_id` | `INTEGER` | Foreign key to the `prompts` table |
| `model_id` | `INTEGER` | Foreign key to the `models` table |
| `start_time` | `TIMESTAMP` | When the experiment started |
| `end_time` | `TIMESTAMP` | When the experiment finished |
| `total_narratives` | `INTEGER` | The total number of narratives processed |
| `positives` | `INTEGER` | The number of positive flags |
| `negatives` | `INTEGER` | The number of negative flags |
| `false_positives` | `INTEGER` | The number of false positives |
| `false_negatives` | `INTEGER` | The number of false negatives |
| `percent_overlap` | `REAL` | The percentage of overlap with manual flags |

**`prompts` table:**

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER` | Primary Key |
| `prompt_text` | `TEXT` | The full text of the prompt |
| `prompt_hash` | `TEXT` | A unique hash of the prompt text |

**`models` table:**

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER` | Primary Key |
| `model_name` | `TEXT` | The name of the model (e.g., "gpt-4") |
| `provider` | `TEXT` | The LLM provider (e.g., "OpenAI") |

**`results` table:**

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `INTEGER` | Primary Key |
| `experiment_id` | `INTEGER` | Foreign key to the `experiments` table |
| `narrative_id` | `TEXT` | The ID of the narrative |
| `rational` | `TEXT` | The LLM's rationale for its decision |
| `flag` | `BOOLEAN` | The IPV flag (TRUE/FALSE) |
| `reasoning_steps` | `TEXT` | The LLM's step-by-step reasoning |
| `is_false_positive` | `BOOLEAN` | Whether the result is a false positive |
| `is_false_negative` | `BOOLEAN` | Whether the result is a false negative |

### 3.2. Automated Workflow

The new workflow will be orchestrated by a master script that reads experiment configurations from a file.

1.  **Configuration:** We'll create a `config/experiments.yml` file to define the experiments to be run. This file will specify the prompt, the model, and other experiment parameters.

    ```yaml
    - experiment_name: "Baseline GPT-4"
      author: "Andrea"
      prompt_file: "prompts/baseline.txt"
      model_name: "gpt-4"
      provider: "OpenAI"

    - experiment_name: "Improved Prompt with GPT-3.5"
      author: "Xiaosong"
      prompt_file: "prompts/improved.txt"
      model_name: "gpt-3.5-turbo"
      provider: "OpenAI"
    ```

2.  **Master Script:** A new `scripts/run_experiments.R` script will:
    *   Read the `experiments.yml` file.
    *   For each experiment:
        *   Create a new record in the `experiments` table.
        *   Run the benchmark, processing each narrative.
        *   For each narrative, create a new record in the `results` table.
        *   After all narratives are processed, update the `experiments` record with the summary statistics.

## 4. Implementation Plan

I can help you implement this plan. Here's a step-by-step guide:

### Step 1: Implement the Database Schema

I can write the SQL `CREATE TABLE` statements for the new tables and add them to a new file, `inst/sql/experiment_hub_schema.sql`.

### Step 2: Create the Configuration and Master Script

I can create the `config/experiments.yml` template and the `scripts/run_experiments.R` master script.

### Step 3: Modify the `store_llm_result` function

I can update the `store_llm_result` function to log results to the new `results` table, linking them to the appropriate experiment.

### Step 4: Create Analysis and Reporting Scripts

I can create a new R script, `analysis/summarize_experiments.R`, that queries the database and generates a summary report of all experiments.

## 5. Conclusion

By implementing this plan, you will have a powerful, automated, and scalable system for running benchmarks and tracking experiments. This will not only save you time and effort but also provide you with a wealth of data for analyzing and improving your models.

I am ready to start implementing this plan. Please let me know if you'd like me to proceed.
