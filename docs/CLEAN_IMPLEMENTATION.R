# Clean IPV Detection Implementation
# "Good taste" version - by Linus standards
# Total: ~100 lines of actual code

# ============================================================
# CONFIG - 外部化所有变量
# ============================================================
load_config <- function(path = Sys.getenv("CONFIG_PATH", "config.yml")) {
  config <- yaml::read_yaml(path)
  
  # 环境变量覆盖
  config$api$url <- Sys.getenv("LLM_API_URL", config$api$url)
  config$api$model <- Sys.getenv("LLM_MODEL", config$api$model)
  
  config
}

# ============================================================
# CORE - 唯一重要的函数
# ============================================================
detect_ipv <- function(narrative, 
                      type = c("LE", "CME"), 
                      config = NULL) {
  
  # 参数处理 - 无特殊情况
  if (is.null(config)) config <- load_config()
  type <- match.arg(type)
  narrative <- trimws(narrative)
  
  # 空值直接返回 - 不是特殊情况，是正常流程
  if (is.na(narrative) || narrative == "") {
    return(list(detected = NA, confidence = 0, reason = "empty"))
  }
  
  # 构建请求 - 简单直接
  prompt <- sprintf(
    "Analyze this %s narrative for intimate partner violence indicators: %s\n
    Respond with JSON: {detected: boolean, confidence: 0-1, indicators: []}",
    type, narrative
  )
  
  # API调用 - 一次成功或失败
  response <- tryCatch({
    httr2::request(config$api$url) |>
      httr2::req_body_json(list(
        model = config$api$model,
        messages = list(list(role = "user", content = prompt)),
        temperature = 0.1
      )) |>
      httr2::req_timeout(30) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }, error = function(e) {
    list(error = e$message)
  })
  
  # 解析响应 - 无分支
  if (!is.null(response$error)) {
    return(list(detected = NA, confidence = 0, error = response$error))
  }
  
  # 提取结果
  content <- response$choices[[1]]$message$content
  if (is.character(content)) {
    content <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  }
  
  list(
    detected = content$detected %||% NA,
    confidence = content$confidence %||% 0,
    indicators = content$indicators %||% character(0)
  )
}

# ============================================================
# BATCH - 向量化处理
# ============================================================
process_narratives <- function(data, config = NULL) {
  if (is.null(config)) config <- load_config()
  
  # 简单的向量化 - R的强项
  data$ipv_le <- lapply(data$NarrativeLE, detect_ipv, type = "LE", config = config)
  data$ipv_cme <- lapply(data$NarrativeCME, detect_ipv, type = "CME", config = config)
  
  # 组合结果 - 一行搞定
  data$ipv_final <- mapply(function(le, cme) {
    w <- config$weights %||% c(le = 0.4, cme = 0.6)
    score <- le$confidence * w["le"] + cme$confidence * w["cme"]
    list(
      detected = score > (config$threshold %||% 0.7),
      confidence = score,
      source = if(le$confidence > cme$confidence) "LE" else "CME"
    )
  }, data$ipv_le, data$ipv_cme, SIMPLIFY = FALSE)
  
  data
}

# ============================================================
# UTILS - 最小辅助
# ============================================================

# NULL合并操作符 - 消除if-else
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# 简单的进度显示
with_progress <- function(x, fn, ...) {
  pb <- txtProgressBar(min = 0, max = length(x), style = 3)
  on.exit(close(pb))
  
  lapply(seq_along(x), function(i) {
    setTxtProgressBar(pb, i)
    fn(x[[i]], ...)
  })
}

# ============================================================
# MAIN - 用户接口
# ============================================================
analyze_ipv <- function(input_file, output_file = NULL) {
  # 读取
  data <- read.csv(input_file, stringsAsFactors = FALSE)
  
  # 处理
  results <- process_narratives(data)
  
  # 输出
  if (!is.null(output_file)) {
    # 展平嵌套列表用于CSV输出
    results$ipv_le_detected <- sapply(results$ipv_le, `[[`, "detected")
    results$ipv_cme_detected <- sapply(results$ipv_cme, `[[`, "detected")
    results$ipv_final_detected <- sapply(results$ipv_final, `[[`, "detected")
    results$ipv_final_confidence <- sapply(results$ipv_final, `[[`, "confidence")
    
    # 删除列表列
    results$ipv_le <- results$ipv_cme <- results$ipv_final <- NULL
    
    write.csv(results, output_file, row.names = FALSE)
  }
  
  invisible(results)
}

# ============================================================
# 就这些。没有更多了。
# ============================================================

# 使用示例：
# results <- analyze_ipv("data.csv", "results.csv")

# 这就是全部。100行解决所有问题。
# 没有R6类，没有S4方法，没有复杂继承。
# 只有函数，数据，和清晰的流程。