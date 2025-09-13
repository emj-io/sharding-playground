# Use SQLite for Development Environment

## Status
**Accepted**

## Context
We need to choose a database for the development environment that supports our sharding architecture while being simple to set up and manage for developers.

Requirements:
- Support for multiple databases (one per shard)
- Easy setup without external dependencies
- Fast test execution
- Ability to prototype sharding concepts

## Decision
Use SQLite for development and testing environments, with separate SQLite database files for each shard.

**File Structure**:
- `db/development.sqlite3` - Primary database (unused in sharding)
- `db/development_shard_0.sqlite3` - Shard 0
- `db/development_shard_1.sqlite3` - Shard 1
- `db/development_shard_2.sqlite3` - Shard 2
- `db/development_shared.sqlite3` - Cross-tenant data (audit logs, analytics)

## Consequences

### Positive Consequences
- **Zero setup**: No external database installation required
- **Fast tests**: SQLite in-memory databases for test suite
- **Simple file management**: Easy to backup, reset, or inspect individual shards
- **No connection limits**: SQLite handles concurrent connections well for development
- **Version control friendly**: Can commit database files for demos
- **Cross-platform**: Works identically on all developer machines

### Negative Consequences
- **Not production-like**: Different from PostgreSQL/MySQL used in production
- **Limited concurrency**: SQLite has write serialization limitations
- **Missing features**: No advanced SQL features that might be used in production
- **File locking**: Potential issues with file-based locking
- **Performance characteristics**: Different from production database performance

### Neutral Consequences
- **Migration testing**: Can test schema migrations but behavior may differ from production
- **Connection pooling**: Rails connection pooling still works but differently
- **Backup procedures**: File-based backup is different from production procedures

## Implementation Requirements

### Database Configuration
```yaml
development:
  shard_0:
    adapter: sqlite3
    database: db/development_shard_0.sqlite3
    pool: 5
    timeout: 5000

  shard_1:
    adapter: sqlite3
    database: db/development_shard_1.sqlite3
    pool: 5
    timeout: 5000

  # ... additional shards
```

### Development Tools
- Rake tasks to create/migrate/seed all shard databases
- Development reset command to clean all shards
- Database inspection tools for debugging

### Test Configuration
```yaml
test:
  shard_0:
    adapter: sqlite3
    database: ":memory:"
    pool: 5
    timeout: 5000
```

## Alternatives Considered

### Alternative 1: PostgreSQL with Schemas
- **Description**: Single PostgreSQL instance with separate schemas per shard
- **Pros**: More production-like, schema-based isolation
- **Cons**: Requires PostgreSQL installation, more complex setup
- **Why rejected**: Adds setup complexity for marginal development benefit

### Alternative 2: Docker PostgreSQL
- **Description**: PostgreSQL running in Docker containers
- **Pros**: Production-like environment, isolated from host system
- **Cons**: Docker dependency, slower startup, resource overhead
- **Why rejected**: Too much infrastructure for development environment

### Alternative 3: Single SQLite Database
- **Description**: Simulate sharding with single database and application-level routing
- **Pros**: Even simpler setup, faster operations
- **Cons**: Doesn't actually test sharding logic, connection management
- **Why rejected**: Wouldn't catch sharding-specific issues

### Alternative 4: MySQL
- **Description**: MySQL with separate databases per shard
- **Pros**: More production-like than SQLite
- **Cons**: Installation complexity, setup overhead
- **Why rejected**: Similar to PostgreSQL option, too much setup burden

## Related Decisions
- [001-organization-shard-key.md](./001-organization-shard-key.md) - Sharding strategy this supports
- Future ADR needed: Production database choice (PostgreSQL vs MySQL)
- Future ADR needed: Production database hosting strategy

---

## Implementation Notes

### Development Workflow
1. `rails db:sharding:create` - Create all shard databases
2. `rails db:sharding:migrate` - Migrate all shards
3. `rails db:sharding:seed` - Seed all shards with test data
4. `rails db:sharding:reset` - Drop and recreate all shards

### Test Performance
Using `:memory:` databases for tests provides very fast test execution while still testing sharding logic.

### File Management
SQLite files are gitignored but can be committed for specific demos or examples.

### Debugging
Each shard can be inspected independently using SQLite command-line tools or GUI applications.

### Migration Strategy
- Migrations run against all shards automatically
- Schema consistency checked across all shards
- Migration failures cleaned up across all shards

### Production Transition
When moving to production:
- Database configuration changes to PostgreSQL/MySQL
- Connection pooling settings adjusted for network databases
- Backup/restore procedures implemented for each shard
- Monitoring added for database-specific metrics