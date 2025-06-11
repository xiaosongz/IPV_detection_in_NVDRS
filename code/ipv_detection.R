library(readxl)
library(writexl)
library(dplyr)
library(purrr)
library(httr2)
library(jsonlite)
library(dotenv)
library(ratelimitr)

load_dot_env()                      # pulls OPENAI_API_KEY from .env
key <- Sys.getenv("OPENAI_API_KEY")
stopifnot(nzchar(key))

## ---------- helpers --------------------------------------------------
openai_chat <- function(prompt, model = "gpt-4o-mini") {
  resp <- request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      "Authorization" = paste("Bearer", key),
      "Content-Type"  = "application/json"
    ) |>
    req_body_json(list(
      model       = model,
      temperature = 0,
      messages    = list(
        list(role = "system",
             content = paste(
               "You are a forensic epidemiologist.",
               "Return strictly valid JSON: {\"ipv_flag\":\"yes|no|unclear\"}",
               "Definitions:",
               " yes     → evidence clearly shows intimate‑partner violence.",
               " no      → evidence clearly rules IPV out or points elsewhere.",
               " unclear → narrative insufficient or ambiguous.",
               "Reply with **nothing but** that JSON."
             )),
        list(role = "user", content = prompt)
      )
    )) |>
    req_perform() |>
    resp_body_json()
  
  flag <- fromJSON(resp$choices[[1]]$message$content)$ipv_flag
  if(!flag %in% c("yes","no","unclear")) flag <- "unclear"
  flag
}

## simple 1‑req/sec limiter (GPT‑4o‑mini => 3 r/s soft cap)
rl_chat <- limit_rate(openai_chat, rate(n=1, period=1))

## ---------- run on file ---------------------------------------------
df <- read_excel("data/sui_all_flagged.xlsx") |>
  mutate(row_id = row_number()) |>          # keep original order
  select(row_id, NarrativeCME, NarrativeLE)

df_out <- df |>
  mutate(
    IPV_CME = map_chr(NarrativeCME, rl_chat),
    IPV_LE  = map_chr(NarrativeLE,  rl_chat),
    IPV_notes = case_when(
      IPV_CME == "yes" | IPV_LE == "yes" ~ "possible IPV signal—review",
      IPV_CME == "unclear" & IPV_LE == "unclear" ~ "needs manual review",
      TRUE ~ NA_character_
    )
  )

write_xlsx(df_out, "output/sui_all_flagged_with_ipv.xlsx")
