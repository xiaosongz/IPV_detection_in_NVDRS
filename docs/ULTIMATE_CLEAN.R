# Ultimate Clean IPV Detection
# "Do ONE thing well" - Unix Philosophy
# Total: ~30 lines of actual code

# ============================================================
# THE ONLY FUNCTION YOU NEED
# ============================================================
detect_ipv <- function(text, config = NULL) {
  # 默认配置 - 简单的list
  if (is.null(config)) {
    config <- list(
      api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
      model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b"),
      prompt_template = Sys.getenv("IPV_PROMPT", 
        "Analyze for intimate partner violence: %s\nReturn JSON: {detected: bool, confidence: 0-1}")
    )
  }
  
  # 空输入 = 空输出
  if (is.null(text) || is.na(text) || trimws(text) == "") {
    return(list(detected = NA, confidence = 0, error = "empty input"))
  }
  
  # 构建提示
  prompt <- sprintf(config$prompt_template, trimws(text))
  
  # 调用API并返回
  tryCatch({
    response <- httr2::request(config$api_url) |>
      httr2::req_body_json(list(
        model = config$model,
        messages = list(list(role = "user", content = prompt))
      )) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    # 返回解析的结果
    jsonlite::fromJSON(response$choices[[1]]$message$content)
    
  }, error = function(e) {
    list(detected = NA, confidence = 0, error = e$message)
  })
}

# ============================================================
# 就这样。一个函数。30行。完成。
# ============================================================

# 用户自己决定怎么用：
# 
# 单个检测：
#   result <- detect_ipv("narrative text here")
#
# 批量处理（用户自己写）：
#   df$ipv_result <- lapply(df$narrative, detect_ipv)
#
# 自定义提示词：
#   my_config <- list(
#     api_url = "http://my-llm:8080/v1/chat/completions",
#     model = "llama-70b",
#     prompt_template = "我的自定义提示词：%s"
#   )
#   result <- detect_ipv(text, my_config)
#
# 就是这么简单。