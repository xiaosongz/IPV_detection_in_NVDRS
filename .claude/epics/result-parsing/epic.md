---
name: result-parsing
status: backlog
created: 2025-08-28T01:14:26Z
progress: 0%
prd: .claude/prds/result-parsing.md
github: https://github.com/xiaosongz/IPV_detection_in_NVDRS/issues/1
---

# Epic: Result Parsing

## Overview

Implement minimal, Unix-philosophy compliant functions to parse LLM responses from `call_llm()` and store them in databases. The solution provides two simple functions: `parse_llm_result()` for data extraction and `store_llm_result()` for database persistence, supporting SQLite (simple) and PostgreSQL (scalable) backends.

## Architecture Decisions

### Technology Stack
- **R Base + DBI**: Leverage existing R ecosystem, use DBI for database abstraction
- **SQLite + RSQLite**: Default storage for simplicity (single file, zero config)
- **PostgreSQL + RPostgres**: Optional scalable backend for production use
- **No ORM/Framework**: Direct SQL for transparency and performance

### Design Patterns
- **Functional Approach**: Pure functions with clear inputs/outputs
- **Database Agnostic**: Abstract storage layer using DBI interface
- **Fail Gracefully**: Return structured errors instead of crashes
- **User Control**: No automatic behavior, user decides when/how to store

### Key Decisions
1. **Single Parse Function**: One function handles all LLM response formats
2. **Pluggable Storage**: Database backend chosen at runtime
3. **Schema Auto-Creation**: Tables created automatically on first use
4. **Error Preservation**: Malformed responses stored with error details

## Technical Approach

### Core Components

#### Parsing Layer (`R/parse_llm_result.R`)
```r
parse_llm_result <- function(llm_response, narrative_id = NULL, metadata = list()) {
  # Extract structured data from call_llm() response
  # Handle malformed JSON gracefully
  # Add metadata (timestamp, model, tokens, etc.)
  # Return standardized list structure
}
```

#### Storage Layer (`R/store_llm_result.R`)
```r
store_llm_result <- function(parsed_result, connection) {
  # Database-agnostic storage using DBI
  # Auto-create tables if needed
  # Handle duplicates gracefully
  # Return success/failure status
}
```

#### Database Utilities (`R/db_utils.R`)
```r
# Connection helpers
connect_sqlite(db_path)
connect_postgres(host, dbname, user, password)

# Schema management
ensure_schema(connection)
get_schema_version(connection)
```

### Database Schema

#### Core Table Design
```sql
-- Single table for simplicity, following Unix philosophy
CREATE TABLE llm_results (
    id INTEGER PRIMARY KEY,
    narrative_id TEXT,
    narrative_text TEXT,
    system_prompt TEXT,
    user_prompt TEXT,
    model TEXT,
    temperature REAL,
    detected BOOLEAN,
    confidence REAL,
    raw_response TEXT,
    tokens_used INTEGER,
    response_time_ms INTEGER,
    error_message TEXT,
    metadata_json TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Minimal indexes for performance
CREATE INDEX idx_llm_results_created_at ON llm_results(created_at);
CREATE INDEX idx_llm_results_detected ON llm_results(detected);
CREATE INDEX idx_llm_results_narrative_id ON llm_results(narrative_id);
```

### Integration Points

#### With Existing Code
- Extends `call_llm()` output without modification
- Uses existing `build_prompt()` for metadata extraction
- Compatible with current Unix philosophy approach

#### Data Flow
```
call_llm() → raw response → parse_llm_result() → structured data → store_llm_result() → database
```

## Implementation Strategy

### Development Phases

#### Phase 1: Core Parsing (3-4 days)
- Analyze actual LLM response structures from `call_llm()`
- Implement `parse_llm_result()` with comprehensive error handling
- Create test suite with malformed response scenarios
- Document expected input/output formats

#### Phase 2: SQLite Storage (2-3 days)  
- Implement `store_llm_result()` with SQLite backend
- Create schema management functions
- Add connection utilities and helpers
- Integration testing with real data

#### Phase 3: PostgreSQL Support (1-2 days)
- Extend storage layer for PostgreSQL
- Test concurrent access scenarios
- Performance optimization for large datasets
- Production deployment documentation

## Task Breakdown Preview

High-level task categories that will be created:
- [ ] **Data Analysis**: Capture and analyze actual LLM response structures
- [ ] **Core Parser**: Implement `parse_llm_result()` function with error handling
- [ ] **SQLite Storage**: Create database storage layer with SQLite backend
- [ ] **PostgreSQL Extension**: Add PostgreSQL support to storage layer
- [ ] **Schema Management**: Auto-create tables and handle versioning
- [ ] **Integration Testing**: End-to-end testing with real IPV detection workflow
- [ ] **Documentation**: Usage examples and database setup guides
- [ ] **Performance Validation**: Verify storage/query performance targets

## Dependencies

### External Dependencies
- **RSQLite** package (for SQLite support)
- **RPostgres** package (for PostgreSQL support)  
- **DBI** package (database abstraction layer)
- **jsonlite** package (already available in project)

### Internal Dependencies
- Stable `call_llm()` function (already implemented)
- Test dataset in `data-raw/` (already available)
- Existing project structure and conventions

### Infrastructure Dependencies
- File system write access (for SQLite files)
- PostgreSQL server (for production deployments)
- Network connectivity (for remote databases)

## Success Criteria (Technical)

### Performance Benchmarks
- **Parse Rate**: >500 responses/second on typical hardware
- **SQLite Storage**: >1000 inserts/second for batch operations
- **PostgreSQL Storage**: >5000 inserts/second with proper indexing
- **Query Performance**: <100ms for filtered queries on 100K+ records

### Quality Gates
- **Parse Success Rate**: >98% for well-formed LLM responses
- **Error Handling**: Graceful degradation for 100% of malformed inputs
- **Data Integrity**: ACID compliance, no data loss scenarios
- **Memory Efficiency**: <1MB memory overhead per 1000 results

### Acceptance Criteria
- Researchers can store results from IPV detection workflows
- Multiple database backends work interchangeably
- Error scenarios are handled without crashing R sessions
- Performance meets stated targets for expected data volumes

## Estimated Effort

### Overall Timeline: 6-9 days
- **Core Development**: 6-7 days
- **Testing & Validation**: 1-2 days
- **Documentation**: 1 day (integrated throughout)

### Resource Requirements
- **Primary Developer**: 1 R expert with database experience
- **Testing Support**: Access to sample LLM responses and test datasets
- **Infrastructure**: SQLite (included), PostgreSQL (optional setup)

### Critical Path Items
1. **LLM Response Analysis**: Understanding actual data structures from `call_llm()`
2. **Error Handling Design**: Comprehensive approach to malformed responses
3. **Database Schema**: Optimal table design for query performance
4. **Integration Testing**: Validation with real IPV detection workflows

### Risk Mitigation
- **LLM Format Changes**: Version detection and graceful degradation
- **Performance Issues**: Database indexing and query optimization
- **Concurrent Access**: Transaction management and connection pooling
- **Data Loss**: ACID transactions and backup recommendations

## Tasks Created
- [ ] #2 - Analyze LLM Response Data Structure (parallel: true)
- [ ] #3 - Implement Core LLM Result Parser (parallel: false)
- [ ] #4 - Create Database Schema and SQLite Storage (parallel: false)
- [ ] #5 - Add PostgreSQL Storage Support (parallel: true)
- [ ] #6 - Integration Testing and Performance Validation (parallel: true)
- [ ] #7 - Documentation and Usage Examples (parallel: true)

Total tasks: 6
Parallel tasks: 4
Sequential tasks: 2
Estimated total effort: 66-88 hours
## Technical Notes

### Simplification Opportunities
- **Single Table Design**: Avoid complex relational schema for simplicity
- **Direct SQL**: No ORM overhead, transparent database operations  
- **Function Composition**: Users combine parsing and storage as needed
- **Leverage DBI**: Use standard R database interface for portability

### Integration with Unix Philosophy
- **Do One Thing Well**: Parse function only parses, storage function only stores
- **Composable Tools**: Users chain functions in their own workflows
- **Text In/Out**: Clear input/output contracts, no hidden state
- **User Control**: No automatic behavior, explicit function calls only
