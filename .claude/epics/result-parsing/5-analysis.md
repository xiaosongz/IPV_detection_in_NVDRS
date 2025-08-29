---
issue: 5
title: Add PostgreSQL Storage Support
created: 2025-08-29T16:45:56Z
complexity: medium
parallel_streams: 3
estimated_hours: 8-12
---

# Issue #5 Analysis: Add PostgreSQL Storage Support

## Overview
Extend storage layer to support PostgreSQL backend alongside existing SQLite implementation. Focus on maintaining backwards compatibility while adding production-ready PostgreSQL support.

## Parallel Work Streams

### Stream A: Database Connection Layer (3-4 hours)
**Agent Type**: backend-architect
**Files**:
- `R/db_utils.R` - Add PostgreSQL connection functions
- `R/.env` - Environment configuration
- `tests/testthat/test-db_utils.R` - Connection tests

**Tasks**:
1. Add `connect_postgres()` function with environment variable support
2. Implement connection pooling for PostgreSQL
3. Add connection type detection utilities
4. Ensure proper error handling and connection cleanup
5. Test both SQLite and PostgreSQL connections

**Dependencies**: None - can start immediately

### Stream B: Storage Function Enhancement (3-4 hours)
**Agent Type**: backend-architect
**Files**:
- `R/store_llm_result.R` - Extend for PostgreSQL
- `inst/sql/schema.sql` - PostgreSQL schema
- `tests/testthat/test-store_llm_result.R` - Storage tests

**Tasks**:
1. Modify `store_llm_result()` to detect connection type
2. Create PostgreSQL-optimized schema (SERIAL, proper indexes)
3. Implement batch insert optimization for PostgreSQL
4. Add transaction support for concurrent writes
5. Test storage with both database backends

**Dependencies**: Needs Stream A for connection utilities

### Stream C: Documentation & Performance (2-3 hours)
**Agent Type**: performance-engineer
**Files**:
- `docs/POSTGRESQL_SETUP.md` - Production setup guide
- `tests/performance/benchmark_postgres.R` - Performance tests
- `config/config.yml.example` - Configuration examples

**Tasks**:
1. Write production deployment documentation
2. Create performance benchmarking scripts
3. Document environment variable configuration
4. Add migration guide from SQLite to PostgreSQL
5. Test and validate >5000 inserts/second target

**Dependencies**: Needs Streams A & B completed for testing

## Coordination Points

1. **Schema Compatibility**: Stream B must ensure schema works for both SQLite and PostgreSQL
2. **Connection Interface**: Stream A defines interface that Stream B uses
3. **Performance Testing**: Stream C validates work from Streams A & B
4. **Environment Variables**: All streams use consistent naming (POSTGRES_* prefix)

## Risk Areas

1. **Breaking Changes**: Must maintain backwards compatibility with SQLite
2. **Performance**: PostgreSQL must meet >5000 inserts/second target
3. **Connection Pooling**: Proper resource management for production use
4. **Schema Differences**: Handle AUTOINCREMENT vs SERIAL correctly

## Success Criteria

- ✅ Both SQLite and PostgreSQL backends work transparently
- ✅ Performance meets or exceeds targets
- ✅ Zero breaking changes to existing API
- ✅ Production-ready with proper documentation
- ✅ All tests pass for both backends

## Implementation Order

1. Start Stream A immediately (connection layer)
2. Start Stream B after A completes core functions
3. Start Stream C after A & B have basic functionality
4. All streams converge for final integration testing

## Notes

- PostgreSQL credentials already configured in `R/.env`
- Host: memini.lan, Port: 5433, Database: postgres
- RPostgres package dependency already added to DESCRIPTION
- Existing SQLite implementation must remain default option