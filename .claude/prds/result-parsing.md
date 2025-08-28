---
name: result-parsing
description: Parse and store LLM results from IPV detection in database with multiple storage options
status: backlog
created: 2025-08-28T01:11:55Z
---

# PRD: Result Parsing

## Executive Summary

Create simple, composable functions to parse LLM results from `call_llm()` and store them in databases. Following Unix philosophy, provide minimal parsing functions that users can combine with their choice of database storage, supporting both local SQLite for simplicity and PostgreSQL for scale.

## Problem Statement

### Current Pain Points
- LLM results from `call_llm()` are ephemeral - lost after R session ends
- No systematic way to store IPV detection results for analysis
- Researchers need persistent storage for large-scale narrative analysis
- Cannot track performance metrics or build datasets from results
- No way to resume interrupted processing or avoid re-processing

### Why This Matters Now
- Researchers are processing hundreds of narratives requiring persistence
- Need to build validation datasets by comparing results over time  
- Performance analysis requires historical data storage
- Compliance may require audit trails of AI decisions

## User Stories

### Primary Persona: Public Health Researcher
**As a** public health researcher processing NVDRS narratives  
**I want to** store IPV detection results in a database  
**So that** I can analyze patterns, track accuracy, and build datasets

**Acceptance Criteria:**
- Parse LLM JSON responses into structured data
- Store narrative text, detection results, confidence scores, and metadata
- Query results by date, confidence level, or detection status
- Export results to CSV/Excel for analysis
- Handle malformed LLM responses gracefully

### Secondary Persona: Data Analyst
**As a** data analyst working with IPV detection results  
**I want to** query stored results using SQL  
**So that** I can create reports and perform statistical analysis

**Acceptance Criteria:**
- Access via standard SQL queries
- Aggregate results by time periods
- Filter by confidence thresholds
- Join with original case data
- Export query results

### Tertiary Persona: System Administrator
**As a** system administrator managing the analysis infrastructure  
**I want to** choose appropriate database backends  
**So that** I can optimize for our scale and performance needs

**Acceptance Criteria:**
- Support SQLite for single-user simple deployments
- Support PostgreSQL for multi-user production deployments
- Handle database creation and schema migration
- Provide backup/recovery guidance

## Requirements

### Functional Requirements

#### Core Parsing Function
```r
parse_llm_result(response, narrative_id = NULL, metadata = NULL)
```
- Extract structured data from `call_llm()` response
- Handle malformed JSON gracefully (return NA with error info)
- Include timestamp, model info, token usage
- Support optional narrative ID and metadata

#### Database Storage Functions
```r
store_result_sqlite(parsed_result, db_path)
store_result_postgres(parsed_result, connection)
```
- Store parsed results to database
- Create tables if they don't exist
- Handle duplicate detection
- Return success/failure status

#### Schema Management
- Automatic table creation with optimal indexes
- Version migration support
- Data integrity constraints

#### Query Helpers (Optional)
```r
query_results(db, filters = list(), limit = NULL)
export_results(db, format = "csv", file_path)
```

### Non-Functional Requirements

#### Performance
- Parse 100+ results per second
- Store 1000+ results per second in SQLite
- Store 10,000+ results per second in PostgreSQL
- Minimal memory footprint (<50MB for 10K results)

#### Data Integrity
- Foreign key constraints where applicable
- Atomic transactions for batch operations
- Duplicate detection and handling
- Backup-friendly schema design

#### Scalability
- SQLite: Up to 1M results, single user
- PostgreSQL: Unlimited scale, multi-user
- Partitioning support for large datasets
- Connection pooling for concurrent access

#### Security
- No sensitive data in connection strings
- Environment variable configuration
- Prepared statements (SQL injection prevention)
- Optional encryption at rest

## Success Criteria

### Measurable Outcomes
- **Storage Rate**: >1000 results/second average
- **Query Performance**: <100ms for filtered queries on 100K+ results
- **Data Integrity**: 99.99% success rate for well-formed responses
- **Error Handling**: Graceful degradation for malformed responses
- **Adoption**: Used by researchers processing >1000 narratives

### Key Metrics
- Parse success rate (target: >95% for typical LLM outputs)
- Storage latency (target: <10ms per result)
- Query response time (target: <500ms for complex queries)
- Database size efficiency (target: <1KB per result average)

## Database Recommendations

### Option 1: SQLite (Recommended for Small Scale)
**Pros:**
- Zero configuration, single file
- Perfect for single users/machines
- Excellent R integration via RSQLite
- ACID compliant, reliable

**Cons:**
- Single writer limitation
- Not suitable for concurrent access
- Limited to ~1TB practical size

**Use Cases:** Individual researchers, development, small datasets

### Option 2: PostgreSQL (Recommended for Production)
**Pros:**
- Full SQL compliance, rich data types
- Excellent performance and scalability
- Strong R integration via RPostgres
- JSON column support for flexible schemas

**Cons:**
- Requires server setup and maintenance
- More complex configuration

**Use Cases:** Multi-user deployments, large datasets, production systems

### Option 3: DuckDB (Emerging Option)
**Pros:**
- Analytical workload optimized
- Excellent R integration
- Single file like SQLite but faster analytics

**Cons:**
- Newer, less ecosystem support
- Primarily read-optimized

## Schema Design

### Core Tables

#### `llm_requests`
```sql
CREATE TABLE llm_requests (
    id INTEGER PRIMARY KEY,
    narrative_id TEXT,
    narrative_text TEXT NOT NULL,
    system_prompt TEXT NOT NULL,
    user_prompt TEXT NOT NULL,
    model TEXT NOT NULL,
    temperature REAL,
    api_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### `llm_responses`
```sql
CREATE TABLE llm_responses (
    id INTEGER PRIMARY KEY,
    request_id INTEGER REFERENCES llm_requests(id),
    detected BOOLEAN,
    confidence REAL,
    raw_response TEXT,
    tokens_used INTEGER,
    response_time_ms INTEGER,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### `processing_batches` (Optional)
```sql
CREATE TABLE processing_batches (
    id INTEGER PRIMARY KEY,
    name TEXT,
    description TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    total_records INTEGER,
    successful_records INTEGER
);
```

## Constraints & Assumptions

### Technical Constraints
- Must work with existing `call_llm()` function
- R environment required
- Database drivers must be available
- Network access for PostgreSQL

### Assumptions
- LLM responses follow consistent JSON structure
- Users have basic SQL knowledge for queries
- Database storage is acceptable for sensitive data
- Processing happens on trusted networks

### Timeline Constraints
- Initial implementation: 1-2 weeks
- Testing and refinement: 1 week
- Documentation: 3-5 days

## Out of Scope

### Explicitly NOT Building
- ❌ Web interface for database management
- ❌ Real-time streaming/event processing
- ❌ Advanced analytics or ML on stored results
- ❌ Multi-tenant database management
- ❌ Database administration tools
- ❌ Data visualization dashboards
- ❌ API endpoints for external access
- ❌ User authentication/authorization system

### Future Considerations
- Data warehouse integration
- Advanced query optimization
- Automated data archival
- Performance monitoring dashboard

## Dependencies

### External Dependencies
- **RSQLite** package for SQLite support
- **RPostgres** package for PostgreSQL support  
- **DBI** package for database abstraction
- **jsonlite** package (already required)

### Internal Dependencies
- `call_llm()` function must be stable
- `build_prompt()` function for metadata
- Test dataset for validation

### Infrastructure Dependencies
- SQLite: File system write access
- PostgreSQL: Database server and network access
- R environment with package installation rights

## Implementation Phases

### Phase 1: Core Parsing (Week 1)
- Analyze actual LLM response structure
- Create `parse_llm_result()` function
- Comprehensive error handling
- Unit tests for edge cases

### Phase 2: SQLite Integration (Week 1)
- SQLite storage functions
- Schema creation and migration
- Basic query helpers
- Integration tests

### Phase 3: PostgreSQL Support (Week 2)
- PostgreSQL connection management
- Production-ready schema
- Performance optimization
- Load testing

### Phase 4: Documentation & Examples (Week 2)
- Usage examples and tutorials
- Database setup guides
- Performance benchmarking
- Migration utilities

## Risk Mitigation

### Technical Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM response format changes | High | Version detection, graceful degradation |
| Database connection failures | Medium | Retry logic, local fallback |
| Performance degradation | Medium | Indexing, query optimization |
| Data corruption | High | ACID transactions, backup verification |

### Business Risks  
| Risk | Impact | Mitigation |
|------|--------|------------|
| Privacy compliance | High | Local database option, encryption |
| Scalability limits | Medium | Multiple database options |
| User adoption | Low | Simple API, good documentation |

## Success Definition

This feature will be considered successful when:
1. Researchers can reliably store and query IPV detection results
2. Performance meets stated targets for their data volumes
3. Data integrity is maintained across processing sessions
4. Multiple database backends work seamlessly
5. Documentation enables self-service adoption

The implementation should embody the project's Unix philosophy: simple tools that do one thing well, composable by users for their specific workflows.