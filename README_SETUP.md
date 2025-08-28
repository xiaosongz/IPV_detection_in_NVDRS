# LLM API Setup

## Configuration Methods

### Method 1: Environment Variables (Persistent)
Create a `.Renviron` file in the project root:
```
LLM_API_URL=http://192.168.10.22:1234/v1/chat/completions
LLM_MODEL=openai/gpt-oss-120b
```

### Method 2: R Session Setup (Temporary)
Set in your R script before calling functions:
```r
Sys.setenv(LLM_API_URL = "http://192.168.10.22:1234/v1/chat/completions")
Sys.setenv(LLM_MODEL = "openai/gpt-oss-120b")
```

### Method 3: Use Setup Function
```r
source("R/setup_llm.R")
setup_llm()  # Uses defaults
# OR
setup_llm(api_url = "your_api_url", model = "your_model")
```

### Method 4: Direct Parameters
Override defaults in function calls:
```r
call_llm(
  user_prompt = "...",
  system_prompt = "...",
  api_url = "http://your-server:1234/v1/chat/completions",
  model = "your-model"
)
```

## Common API Endpoints

- **LM Studio**: `http://localhost:1234/v1/chat/completions`
- **Ollama**: `http://localhost:11434/v1/chat/completions`
- **OpenAI**: `https://api.openai.com/v1/chat/completions` (requires API key)
- **Local Network**: `http://192.168.x.x:1234/v1/chat/completions`