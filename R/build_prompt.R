#' Build Prompt Messages for LLM API
#'
#' Creates properly formatted message array for LLM API calls.
#' Both system and user prompts are required.
#'
#' @param system_prompt Character string. System-level instructions that
#'   define the AI's role and behavior.
#' @param user_prompt Character string. The user's prompt/question to send.
#'
#' @return A list containing the messages array formatted for API request:
#'   \describe{
#'     \item{messages}{List of message objects with role and content}
#'   }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Build prompt messages
#' messages <- build_prompt(
#'   system_prompt = "You are a helpful assistant.",
#'   user_prompt = "What is machine learning?"
#' )
#' }
#'
build_prompt <- function(system_prompt, user_prompt) {

  # Validate inputs
  if (!is.character(system_prompt) || length(system_prompt) != 1) {
    stop("'system_prompt' must be a single character string", call. = FALSE)
  }
  if (!is.character(user_prompt) || length(user_prompt) != 1) {
    stop("'user_prompt' must be a single character string", call. = FALSE)
  }

  # Build messages array
  list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_prompt)
  )
}