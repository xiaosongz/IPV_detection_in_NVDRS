# LLM Response Structure Analysis

Generated: 2025-08-27

## Summary Statistics

- Total scenarios tested: 20
- Successful responses: 20
- Error responses: 0
- Malformed JSON: 0
- Partial/Warning: 0

## Response Structure Fields

### Top-level fields found in successful responses:
- `choices`
- `choices.finish_reason`
- `choices.index`
- `choices.logprobs`
- `choices.message`
- `choices.message.content`
- `choices.message.reasoning`
- `choices.message.role`
- `choices.message.tool_calls`
- `created`
- `id`
- `model`
- `object`
- `stats`
- `system_fingerprint`
- `test_metadata`
- `usage`
- `usage.completion_tokens`
- `usage.prompt_tokens`
- `usage.total_tokens`

## Detailed Field Analysis

### Successful Response Examples

#### Example 1: basic_ipv_positive
```json
{
  "id": "chatcmpl-ff280lg3yhll0rs924bbx",
  "object": "chat.completion",
  "created": 1756344270,
  "model": "openai/gpt-oss-120b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "<|channel|>final <|constrain|>JSON<|message|>{\n  \"detected\": true,\n  \"confidence\": 0.99\n}",
        "reasoning": "We need detect IPV content. Yes it's intimate partner violence. confidence high.",
        "tool_calls": []
      },
      "logprobs": {},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 122,
    "completion_tokens": 46,
    "total_tokens": 168
  },
  "stats": {},
  "system_fingerprint": "openai/gpt-oss-120b",
  "test_metadata": {
    "scenario_name": "basic_ipv_positive",
    "elapsed_seconds": 1.4875,
    "timestamp": "2025-08-27 21:24:29",
    "prompt_length": 70,
    "system_prompt_length": 126
  }
}
```

#### Example 2: basic_ipv_negative
```json
{
  "id": "chatcmpl-0xulh7pldfajapfoyjpa5",
  "object": "chat.completion",
  "created": 1756344272,
  "model": "openai/gpt-oss-120b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "{\n  \"detected\": false,\n  \"confidence\": 0.99\n}",
        "reasoning": "User statement not about IPV. So detection false.",
        "tool_calls": []
      },
      "logprobs": {},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 116,
    "completion_tokens": 38,
    "total_tokens": 154
  },
  "stats": {},
  "system_fingerprint": "openai/gpt-oss-120b",
  "test_metadata": {
    "scenario_name": "basic_ipv_negative",
    "elapsed_seconds": 0.7046,
    "timestamp": "2025-08-27 21:24:31",
    "prompt_length": 53,
    "system_prompt_length": 126
  }
}
```

#### Example 3: complex_narrative
```json
{
  "id": "chatcmpl-onkztx76bia4qtfw8f0xci",
  "object": "chat.completion",
  "created": 1756344273,
  "model": "openai/gpt-oss-120b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "{\n  \"detected\": true,\n  \"confidence\": 0.97,\n  \"indicators\": [\n    \"domestic disputes\",\n    \"victim\",\n    \"partner\"\n  ]\n}",
        "reasoning": "We need to detect IPV indicators. Text mentions \"victim had a long history of domestic disputes with their partner.\" That's an indicator of intimate partner violence. So detected true, high confidence.",
        "tool_calls": []
      },
      "logprobs": {},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 374,
    "completion_tokens": 89,
    "total_tokens": 463
  },
  "stats": {},
  "system_fingerprint": "openai/gpt-oss-120b",
  "test_metadata": {
    "scenario_name": "complex_narrative",
    "elapsed_seconds": 1.9198,
    "timestamp": "2025-08-27 21:24:33",
    "prompt_length": 1420,
    "system_prompt_length": 144
  }
}
```

## Proposed Standardized Parse Output

Based on the analysis, the parsed output should have this structure:

```r
list(
  # Core IPV detection results
  detected = logical(),        # TRUE/FALSE/NA
  confidence = numeric(),      # 0.0-1.0
  
  # Metadata from LLM response
  model = character(),         # Model used
  created_at = character(),    # Timestamp from response
  response_id = character(),   # Unique ID from LLM
  
  # Usage metrics
  tokens_used = integer(),     # Total tokens
  prompt_tokens = integer(),   # Input tokens
  completion_tokens = integer(), # Output tokens
  
  # Processing metadata
  response_time_ms = numeric(), # Response time
  narrative_id = character(),   # User-provided ID
  narrative_length = integer(), # Input length
  
  # Error handling
  parse_error = logical(),     # TRUE if parsing failed
  error_message = character(), # Error details if any
  raw_response = character()   # Original JSON string
)
```

## Testing Notes

- Responses are generally consistent in structure
- JSON parsing is reliable when proper prompts are used
- Error responses need graceful handling
- Token usage information is always present in successful calls
- Response IDs provide unique tracking
