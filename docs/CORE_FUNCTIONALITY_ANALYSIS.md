# IPV Detection Package - 核心功能分析
*by Linus Torvalds perspective*

## 一句话总结

**本质任务**：读CSV → 调用LLM API → 判断是否存在家庭暴力 → 输出结果

就这么简单。不需要650行代码。

## 当前问题诊断

### 🔴 致命问题

1. **过度工程地狱**
   - 14个R文件做一件事
   - R6类解决函数式问题
   - 5层抽象处理简单文本

2. **特殊情况癌症**
   ```r
   # 现状：
   detect_ipv() → detect_ipv_simple() → detect_ipv_forensic()
   reconcile_results() → reconcile_le_cme() → reconcile_batch_results()
   
   # 应该是：
   detect_ipv(text) → result
   ```

3. **数据结构灾难**
   - forensic_data_structure.R: 500行存储一个列表
   - IPVForensicResult R6类: 面向对象的overkilll
   - 应该就是个data.frame

## 核心功能（实际需要的）

### 必要功能 - 3个

1. **文本分类**
   ```r
   detect_ipv(text, type = "LE") → list(detected = TRUE/FALSE, confidence = 0.85)
   ```

2. **批量处理**
   ```r
   process_batch(dataframe) → dataframe with results
   ```

3. **配置管理**
   ```r
   load_config() → list(api_url, model, weights)
   ```

### 可选功能 - 2个

4. **日志记录**（如果必须）
   ```r
   log_request(incident_id, response, time_ms)
   ```

5. **结果导出**
   ```r
   write.csv(results, file)
   ```

## 清洁架构设计

### 文件结构（150行搞定）

```
nvdrsipvdetector/
├── R/
│   ├── detect.R      # 核心检测 (50行)
│   ├── batch.R       # 批量处理 (30行)
│   └── utils.R       # 工具函数 (70行)
├── inst/
│   └── config.yml    # 默认配置
└── tests/
    └── test-detect.R # 基础测试
```

### 核心实现

**detect.R:**
```r
#' Detect IPV in narrative text
#' @export
detect_ipv <- function(text, type = c("LE", "CME"), config = NULL) {
  if (is.null(config)) config <- load_config()
  type <- match.arg(type)
  
  # 构建提示词
  prompt <- sprintf(config$prompts[[type]], trimws(text))
  
  # 调用API
  response <- httr2::request(config$api$url) %>%
    httr2::req_body_json(list(
      model = config$api$model,
      messages = list(list(role = "user", content = prompt))
    )) %>%
    httr2::req_perform() %>%
    httr2::resp_body_json()
  
  # 解析结果
  list(
    detected = response$choices[[1]]$message$content$detected,
    confidence = response$choices[[1]]$message$content$confidence
  )
}
```

**batch.R:**
```r
#' Process multiple narratives
#' @export
process_batch <- function(data, config = NULL) {
  data %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      ipv_le = detect_ipv(NarrativeLE, "LE", config),
      ipv_cme = detect_ipv(NarrativeCME, "CME", config),
      ipv_final = (ipv_le$confidence * 0.4 + ipv_cme$confidence * 0.6) > 0.7
    ) %>%
    dplyr::ungroup()
}
```

### 数据流（单向，无分支）

```
CSV → read_csv() → data.frame
  ↓
data.frame → process_batch() → foreach row:
  ↓
  narrative → detect_ipv() → API call → parse → result
  ↓
data.frame with results → write_csv() → CSV
```

## 删除清单（垃圾回收）

### 必须删除的文件
- `forensic_analysis.R` - 学术过度工程
- `forensic_data_structure.R` - 500行废话
- `forensic_integration.R` - 解决不存在的问题
- `forensic_examples.R` - 示例？用test/
- `error_handling.R` - tryCatch就够了
- `validation.R` - 计算准确率需要14个函数？
- `reconciliation.R` - 一个weighted.mean()的事
- `test_tracking.R` - 什么鬼？

### 必须删除的概念
- R6类 - 这不是Java
- "forensic analysis" - 编造的需求
- 5层函数调用 - 直接调用
- 特殊情况处理 - 重新设计消除它们

## Linus式重构步骤

### Phase 1: 推倒（1天）
```bash
rm -rf R/forensic*.R
rm -rf R/test_tracking.R
rm -rf R/error_handling.R
rm -rf R/validation.R
rm -rf R/reconciliation.R
```

### Phase 2: 重建（2小时）
```r
# 1. 写detect.R - 核心功能
# 2. 写batch.R - 批量处理
# 3. 写utils.R - 辅助函数
# 4. 完成。没有第5步。
```

### Phase 3: 测试（1小时）
```r
# 测试3个场景：
test_that("detects IPV", {...})
test_that("handles missing narrative", {...})  
test_that("processes batch", {...})
# 完成。
```

## 性能对比

### 现在（垃圾）
- 代码行数：~2000行
- 文件数：14个
- 复杂度：O(wtf)
- 维护成本：高
- Bug表面积：巨大

### 重构后（干净）
- 代码行数：150行
- 文件数：3个
- 复杂度：O(n)
- 维护成本：几乎零
- Bug表面积：最小

## 给未来维护者的话

> "好代码的标志不是它能处理多少特殊情况，而是它不需要特殊情况。"

这个包的核心功能就是：
1. 读文本
2. 问AI
3. 返回答案

如果你觉得需要超过200行代码，你就是在过度工程。

记住：**Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away.**

---

*"Talk is cheap. Show me the code." - Linus Torvalds*