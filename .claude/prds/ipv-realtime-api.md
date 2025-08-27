---
name: ipv-realtime-api
description: REST API endpoint for real-time IPV detection in narratives
status: backlog
created: 2025-08-27T21:44:47Z
---

# PRD: IPV Real-time API

## Executive Summary

A minimalist REST API that exposes the IPV detection functionality via HTTP, allowing real-time analysis of death investigation narratives. Following Unix philosophy, this API does exactly one thing: accepts narrative text via HTTP POST and returns IPV detection results. No frameworks, no complexity - just a simple HTTP wrapper around the existing 30-line `detect_ipv()` function.

## Problem Statement

### Current Situation
- IPV detection currently requires R environment and direct function calls
- Integration with web applications, data pipelines, and non-R systems is difficult
- Researchers using other languages (Python, JavaScript) cannot easily access the functionality
- No standardized way to share the detection capability across teams or institutions

### Why Now?
- Growing demand for real-time IPV detection in production systems
- Need for language-agnostic access to the detection capability
- Research collaborations require shared infrastructure
- Health departments requesting automated integration capabilities

## User Stories

### Primary Persona: Research Application Developer
**As a** developer building public health surveillance systems  
**I want to** call IPV detection via a simple HTTP API  
**So that** I can integrate it into my existing Python/JavaScript/Java application  

**Acceptance Criteria:**
- Single HTTP endpoint for detection
- JSON request/response format
- Clear error messages
- Sub-second response time

### Secondary Persona: Data Pipeline Engineer
**As a** data engineer processing NVDRS streams  
**I want to** send narratives to an API for real-time classification  
**So that** I can flag potential IPV cases as they enter the system  

**Acceptance Criteria:**
- Reliable endpoint with high availability
- Consistent response format
- Proper HTTP status codes
- Rate limiting information in headers

### Tertiary Persona: Public Health Analyst
**As an** analyst without programming skills  
**I want to** use tools like Postman or curl to check individual narratives  
**So that** I can validate specific cases without writing code  

**Acceptance Criteria:**
- Simple authentication (if any)
- Clear API documentation
- Example requests provided
- Human-readable error messages

## Requirements

### Functional Requirements

#### Core Endpoint
- **POST /detect**
  - Accept narrative text in request body
  - Return IPV detection result
  - Support both JSON and plain text input

#### Request Format
```json
{
  "narrative": "string",
  "config": {
    "model": "optional-override",
    "api_url": "optional-override"
  }
}
```

#### Response Format
```json
{
  "detected": true,
  "confidence": 0.85,
  "processing_time_ms": 523,
  "model_used": "gpt-oss-120b",
  "timestamp": "2025-08-27T21:44:47Z"
}
```

#### Error Handling
- 400 Bad Request - Invalid input format
- 413 Payload Too Large - Narrative exceeds token limit
- 429 Too Many Requests - Rate limit exceeded
- 500 Internal Server Error - LLM API failure
- 503 Service Unavailable - LLM backend unreachable

### Non-Functional Requirements

#### Performance
- Response time: <2 seconds for 95% of requests
- Throughput: Support 10 requests per second
- Concurrent connections: Handle 50 simultaneous requests
- Startup time: <5 seconds

#### Reliability
- Availability: 99% uptime during business hours
- Graceful degradation when LLM unavailable
- Automatic retry for transient failures
- Health check endpoint (/health)

#### Security
- Optional API key authentication
- HTTPS support (user-configured)
- No storage of narratives
- Configurable CORS headers
- Rate limiting per API key

#### Simplicity
- Single file implementation (<200 lines)
- Minimal dependencies (existing + web server)
- No database requirement
- No session management
- Stateless operation

## Success Criteria

### Quantitative Metrics
- API handles 1000+ requests per day
- 95% of requests complete in <2 seconds
- Zero narrative data stored or logged
- <200 lines of additional code

### Qualitative Metrics
- Researchers report easy integration
- No learning curve for basic usage
- Maintains Unix philosophy
- Community creates client libraries

### Adoption Indicators
- 10+ external systems integrate within 3 months
- Used in at least 2 research publications
- Forked for specialized deployments
- Zero feature requests (it's complete)

## Constraints & Assumptions

### Technical Constraints
- Must work with existing `detect_ipv()` function
- Cannot modify core detection logic
- Must remain stateless
- No complex deployment requirements

### Resource Constraints
- No dedicated infrastructure budget
- Single developer implementation
- No ongoing maintenance commitment
- Community-supported model

### Assumptions
- Users have basic HTTP/REST knowledge
- LLM backend remains available
- Network latency acceptable for real-time use
- Users handle their own data persistence

## Out of Scope

### Explicitly NOT Building
- ❌ Batch processing endpoints
- ❌ Webhook/callback mechanisms
- ❌ User management system
- ❌ Result storage/retrieval
- ❌ Web UI or dashboard
- ❌ Multi-tenant isolation
- ❌ Request queuing system
- ❌ Result caching layer
- ❌ GraphQL or WebSocket support
- ❌ SDK or client libraries

### Future Considerations (Not Now)
- Multiple LLM provider support
- Advanced authentication (OAuth, JWT)
- Narrative preprocessing
- Custom prompt templates via API
- Metrics/monitoring endpoints

## Dependencies

### Internal Dependencies
- `detect_ipv()` function (core detection logic)
- LLM configuration (environment variables)
- Existing error handling patterns

### External Dependencies
- R runtime environment
- HTTP server library (e.g., plumber, httpuv)
- LLM API endpoint (LM Studio or compatible)
- Network connectivity

### Infrastructure Dependencies
- Server/container to host API
- Optional: Reverse proxy (nginx, caddy)
- Optional: SSL certificates
- Optional: Monitoring tools

## Implementation Approach

### Recommended Architecture
```
HTTP Request → R Web Server → detect_ipv() → LLM API
                    ↓
HTTP Response ← JSON Format ← Parse Result
```

### Technology Choice
- **plumber**: R package for REST APIs (minimal, simple)
- Alternative: **httpuv** for even lower-level control
- No frameworks, ORMs, or complex middleware

### Deployment Options
1. **Local**: Run on research server (simplest)
2. **Container**: Docker with R + plumber
3. **Cloud Function**: AWS Lambda, Google Cloud Run
4. **Traditional**: SystemD service on Linux

## Risks & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| LLM API downtime | High | Medium | Return 503 with clear message |
| Rate limit abuse | Medium | High | Implement per-IP limits |
| Large narrative DoS | Medium | Low | Set max payload size |
| Feature creep | High | High | Reject all additions |

## Timeline Estimate

### Implementation Phases
1. **Core API** (2 hours)
   - Single endpoint
   - Basic error handling
   - JSON I/O

2. **Configuration** (1 hour)
   - Environment variables
   - Optional authentication
   - CORS headers

3. **Documentation** (1 hour)
   - README update
   - Example requests
   - Deployment guide

**Total: 4 hours of development**

## Success Looks Like

```bash
# A researcher anywhere can do this:
curl -X POST http://ipv-api.local/detect \
  -H "Content-Type: application/json" \
  -d '{"narrative": "Victim shot by ex-husband"}' 

# And get this:
{
  "detected": true,
  "confidence": 0.92
}
```

No more, no less. The Unix way.