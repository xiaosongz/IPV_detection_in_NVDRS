# Product Requirements Document: nvdrsipv

*一个遵循Unix哲学的R包*

## 1. 产品概述

### 1.1 一句话描述
**nvdrsipv** - 调用LLM API检测文本中亲密伴侣暴力(IPV)指标的极简R包。

### 1.2 核心价值主张
- **做一件事，做到极致** - 只负责文本→API→结果
- **零学习曲线** - 会R就会用这个包
- **完全透明** - 用户知道每一步发生了什么
- **可组合性** - 与R生态系统完美集成

### 1.3 非目标（明确不做什么）
- ❌ 不处理文件I/O
- ❌ 不管理数据批处理
- ❌ 不提供UI界面
- ❌ 不做结果可视化
- ❌ 不管理API密钥（用环境变量）
- ❌ 不做数据验证（垃圾进，垃圾出）

## 2. 用户场景

### 2.1 目标用户
- **主要用户**: 公共卫生研究人员分析NVDRS数据
- **次要用户**: 任何需要检测文本中暴力内容的R用户
- **技术水平**: 会基础R编程

### 2.2 核心用例

#### 用例1: 单条记录检测
```r
library(nvdrsipv)

# 用户故事：研究员Sarah需要快速检查一条可疑记录
narrative <- "The victim's ex-boyfriend broke into her apartment..."
result <- detect_ipv(narrative)

# 结果
print(result$detected)    # TRUE
print(result$confidence)  # 0.92
print(result$indicators)  # ["ex-boyfriend", "broke into", "victim"]
```

#### 用例2: 批量处理（用户控制）
```r
# 用户故事：研究员需要处理1000条记录
data <- read_csv("nvdrs_2023.csv")

# 方式1: 简单串行
data$ipv_result <- lapply(data$narrative_text, detect_ipv)

# 方式2: 并行处理
library(furrr)
plan(multisession, workers = 4)
data$ipv_result <- future_map(data$narrative_text, detect_ipv)

# 方式3: 管道处理
results <- data %>%
  filter(!is.na(narrative_text)) %>%
  mutate(ipv = map(narrative_text, detect_ipv)) %>%
  unnest_wider(ipv)
```

#### 用例3: 自定义配置
```r
# 用户故事：机构使用内部LLM服务器
config <- list(
  api_url = "https://llm.institution.edu/v1/chat/completions",
  model = "llama3-70b-instruct",
  prompt_template = readr::read_file("custom_ipv_prompt.txt"),
  timeout = 60,
  retry_times = 3
)

result <- detect_ipv(narrative, config)
```

## 3. 功能规格

### 3.1 核心API

#### 主函数: `detect_ipv()`

```r
detect_ipv <- function(
  text,                    # 要分析的文本
  config = NULL,          # 配置列表(可选)
  .progress = FALSE       # 显示进度(用于批处理)
)
```

**输入**:
- `text`: 字符串，长度1-50000字符
- `config`: 列表，包含API配置
- `.progress`: 逻辑值，是否显示进度条

**输出**:
```r
list(
  detected = TRUE/FALSE,     # 是否检测到IPV
  confidence = 0.0-1.0,      # 置信度
  indicators = character(),   # 检测到的指标词
  reasoning = character(),    # LLM的推理说明(可选)
  error = NULL               # 错误信息(如果有)
)
```

#### 辅助函数: `load_config()`

```r
load_config <- function(
  path = "~/.nvdrsipv/config.yml",  # 配置文件路径
  validate = TRUE                    # 是否验证配置
)
```

### 3.2 配置规格

#### 默认配置结构
```yaml
# ~/.nvdrsipv/config.yml
api:
  url: ${NVDRSIPV_API_URL:-http://localhost:1234/v1/chat/completions}
  model: ${NVDRSIPV_MODEL:-gpt-4}
  timeout: 30
  retry_times: 3
  retry_delay: 2  # exponential backoff

prompt:
  template: |
    Analyze the following text for indicators of intimate partner violence (IPV).
    
    Text: {text}
    
    Respond in JSON format:
    {
      "detected": boolean,
      "confidence": 0.0-1.0,
      "indicators": ["indicator1", "indicator2"],
      "reasoning": "brief explanation"
    }
  
  max_tokens: 500
  temperature: 0.1

logging:
  enabled: false
  level: "INFO"
  file: "~/.nvdrsipv/logs/api_calls.log"
```

#### 环境变量
```bash
NVDRSIPV_API_URL    # API端点
NVDRSIPV_MODEL      # 模型名称
NVDRSIPV_API_KEY    # API密钥(如果需要)
NVDRSIPV_CONFIG     # 配置文件路径
```

### 3.3 错误处理

#### 错误类型与处理
| 错误类型 | 返回值 | 用户行为 |
|---------|--------|---------|
| 空输入 | `list(detected=NA, confidence=0, error="empty input")` | 过滤或跳过 |
| API超时 | `list(detected=NA, confidence=0, error="timeout")` | 重试或记录 |
| 无效JSON | `list(detected=NA, confidence=0, error="invalid response")` | 检查模型 |
| 网络错误 | `list(detected=NA, confidence=0, error="connection failed")` | 检查连接 |

#### 重试机制
```r
# 内置指数退避
retry_times: 3
delays: [2, 4, 8] seconds
```

## 4. 技术架构

### 4.1 依赖关系
```yaml
Imports:
  httr2 (>= 1.0.0)    # HTTP请求
  jsonlite (>= 1.8)   # JSON处理
  
Suggests:
  yaml               # 配置文件
  testthat (>= 3.0)  # 测试
  parallel           # 并行示例
  future             # 异步示例
```

### 4.2 文件结构
```
nvdrsipv/
├── R/
│   ├── detect.R          # 核心函数 (30行)
│   ├── config.R          # 配置管理 (20行)
│   └── utils.R           # 辅助函数 (10行)
├── inst/
│   ├── config/
│   │   └── default.yml   # 默认配置模板
│   └── examples/
│       ├── basic.R       # 基础示例
│       ├── batch.R       # 批处理示例
│       └── custom.R      # 自定义示例
├── tests/
│   └── testthat/
│       ├── test-detect.R # 核心测试
│       └── test-config.R # 配置测试
├── man/                  # 自动生成的文档
├── DESCRIPTION          # 包元数据
├── NAMESPACE           # 导出定义
├── README.md           # 快速开始
└── LICENSE             # MIT
```

### 4.3 性能指标
- **延迟**: < 2秒/请求 (取决于LLM)
- **吞吐**: ~30请求/分钟 (单线程)
- **内存**: < 50MB (1000条记录)
- **包大小**: < 100KB

## 5. 开发计划

### Phase 1: MVP (第1周)
- [ ] 实现 `detect_ipv()` 核心函数
- [ ] 基础错误处理
- [ ] 最小可用文档

### Phase 2: 配置管理 (第2周)
- [ ] 实现 `load_config()`
- [ ] 环境变量支持
- [ ] 配置验证

### Phase 3: 生产就绪 (第3周)
- [ ] 重试机制
- [ ] 完整测试覆盖
- [ ] 性能优化
- [ ] 示例脚本

### Phase 4: 发布 (第4周)
- [ ] CRAN检查
- [ ] 文档完善
- [ ] GitHub发布
- [ ] 用户指南

## 6. 成功指标

### 6.1 技术指标
- **代码行数**: < 100行 (不含测试)
- **测试覆盖**: > 95%
- **依赖数量**: ≤ 2个强制依赖
- **CRAN检查**: 0 errors, 0 warnings

### 6.2 用户指标
- **学习时间**: < 5分钟读懂README
- **首次使用**: < 1分钟出结果
- **集成难度**: 复制粘贴即可用

### 6.3 质量指标
- **Bug率**: < 1 bug/1000次调用
- **API兼容性**: 支持OpenAI兼容接口
- **向后兼容**: 永不破坏API

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|-----|------|---------|
| LLM API变更 | 高 | 抽象接口层，版本锁定 |
| 速率限制 | 中 | 内置重试，用户控制并发 |
| 模型准确性 | 高 | 不是包的责任，用户选择模型 |
| 依赖更新 | 低 | 最小依赖，严格版本控制 |

## 8. 设计原则（不可违背）

1. **简单优于功能** - 宁可让用户写3行代码，不要猜测需求
2. **透明优于魔法** - 用户必须知道发生了什么
3. **组合优于集成** - 做好一件事，让用户组合
4. **标准优于创新** - 用R的惯用方式，不要发明新概念
5. **文档优于功能** - 好的文档比更多功能重要

## 9. 反模式（绝对避免）

❌ **不要做的事**:
- 自动批处理 - 让用户用 `lapply()`
- 进度条 - 让用户用 `pbapply()`
- 缓存机制 - 让用户用 `memoise()`
- 结果验证 - 返回原始结果，用户自己验证
- 数据框操作 - 用户知道怎么用 `dplyr`
- 文件读写 - 用户知道怎么用 `readr`

## 10. 示例：完整的用户工作流

```r
# 1. 安装
install.packages("nvdrsipv")

# 2. 配置（可选）
# 创建 ~/.nvdrsipv/config.yml 或使用环境变量

# 3. 使用
library(nvdrsipv)
library(tidyverse)

# 读取数据
data <- read_csv("nvdrs_narratives.csv")

# 检测IPV
results <- data %>%
  # 数据清理 - 用户控制
  filter(!is.na(narrative_text)) %>%
  slice_sample(n = 100) %>%  # 先测试100条
  
  # 核心功能 - 包的唯一职责
  mutate(ipv = map(narrative_text, detect_ipv)) %>%
  
  # 结果处理 - 用户控制
  unnest_wider(ipv) %>%
  filter(!is.na(detected)) %>%
  select(case_id, detected, confidence, indicators)

# 保存结果
write_csv(results, "ipv_detection_results.csv")

# 生成报告（用户自己做）
results %>%
  summarise(
    total = n(),
    ipv_detected = sum(detected),
    avg_confidence = mean(confidence)
  )
```

## 11. 最终交付物

1. **R包**: `nvdrsipv_1.0.0.tar.gz` (<100KB)
2. **文档**: 
   - README.md - 5分钟快速开始
   - vignette - 完整使用指南
   - pkgdown网站 - 在线文档
3. **示例**:
   - 单条检测
   - 批量处理
   - 并行处理
   - 错误处理
4. **测试**: >95%覆盖率

## 12. Linus的最终审查标准

```text
✓ 代码能在5分钟内完全理解？
✓ 删除任何一行会损失功能？
✓ 添加任何一行是过度设计？
✓ 用户第一次就能用对？
✓ 出错时用户知道为什么？
```

**如果任何一个是"否"，重新设计。**

---

*"Simplicity is the ultimate sophistication." - Leonardo da Vinci*

*这个包的成功不在于它能做多少，而在于它拒绝做多少。*