#' Call LLM API with a prompt
#'
#' Sends a text prompt to a Large Language Model API and returns the response.
#' This is a minimal wrapper around the OpenAI-compatible chat completions endpoint.
#'
#' @param user_prompt Character string. The user's prompt/question to send to the LLM.
#' @param system_prompt Character string. System-level instructions that
#'   define the AI's role and behavior.
#' @param api_url Character string. The API endpoint URL. Defaults to environment
#'   variable LLM_API_URL or local LM Studio endpoint.
#' @param model Character string. The model identifier to use. Defaults to
#'   environment variable LLM_MODEL or "openai/gpt-oss-120b".
#' @param temperature Numeric. Controls randomness in the response. 0 = deterministic,
#'   1 = maximum randomness. Default is 0.1 for mostly consistent responses.
#'
#' @return A list containing the full API response, including:
#'   \describe{
#'     \item{choices}{List of response choices, typically one}
#'     \item{usage}{Token usage statistics}
#'     \item{model}{Model used for generation}
#'     \item{id}{Unique identifier for this completion}
#'   }
#'   The actual text response is in \code{result$choices[[1]]$message$content}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' response <- call_llm("What is intimate partner violence?")
#' content <- response$choices[[1]]$message$content
#'
#' # With system and user prompts
#' sys_prompt <- "You are a forensic analyst. Respond only with JSON."
#' user_prompt <- "Analyze this narrative for IPV indicators..."
#' response <- call_llm(user_prompt, system_prompt = sys_prompt)
#'
#' # With custom temperature
#' response <- call_llm("Analyze this narrative...", temperature = 0)
#' }
#'
#' @seealso
#' \url{https://platform.openai.com/docs/api-reference/chat/create}
#'
call_llm <- function(user_prompt,
                     system_prompt,
                     api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
                     model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b"),
                     temperature = 0.1) {

  # Validate inputs
  if (!is.character(user_prompt) || length(user_prompt) != 1) {
    stop("'user_prompt' must be a single character string", call. = FALSE)
  }
  if (!is.character(system_prompt) || length(system_prompt) != 1) {
    stop("'system_prompt' must be a single character string", call. = FALSE)
  }
  if (!is.numeric(temperature) || temperature < 0 || temperature > 1) {
    stop("'temperature' must be a number between 0 and 1", call. = FALSE)
  }

  # Build messages array using build_prompt
  messages <- build_prompt(system_prompt, user_prompt)

  # Build request body
  request_body <- list(
    model = model,
    messages = messages,
    temperature = temperature
  )

  # Make API call and return response
  httr2::request(api_url) |>
    httr2::req_body_json(request_body) |>
    httr2::req_timeout(30) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
}
