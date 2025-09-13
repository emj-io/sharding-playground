# Use Organization ID as Shard Key

## Status
**Accepted**

## Context
We need to determine how to distribute tenant data across multiple database shards. The sharding strategy must provide good isolation, predictable performance, and simple implementation for developers.

Our multi-tenant application has:
- Organizations as the primary tenant boundary
- Each organization has users, projects, and tasks
- Need for both single-tenant and cross-tenant operations
- Goal of single-shard-per-request architecture

## Decision
We will use `organization_id` as the shard key, with each organization's complete dataset stored on one shard.

**Sharding Algorithm**: `shard_number = organization_id % SHARD_COUNT`

## Consequences

### Positive Consequences
- **Perfect tenant isolation**: Each organization's data is completely separate
- **Simple developer experience**: Single-tenant operations require no sharding awareness
- **Predictable performance**: Each request hits exactly one database
- **Easy backup/restore**: Can backup individual tenants
- **Clear data ownership**: All organization data lives in one place
- **Simple connection management**: One connection per request

### Negative Consequences
- **Uneven distribution**: Organization IDs may not distribute evenly across shards
- **Large tenant problem**: One very large organization can overwhelm a shard
- **Cross-tenant complexity**: Admin operations require querying multiple shards
- **Rebalancing difficulty**: Moving organizations between shards is complex
- **Resource overhead**: Each shard has its own connection pool and overhead

### Neutral Consequences
- **Schema replication**: Each shard needs identical schema
- **Migration complexity**: Schema changes must be applied to all shards
- **Monitoring complexity**: Must monitor health of each shard independently

## Implementation Requirements

### Core Components
1. **Shard Router**: Maps organization_id to shard name
2. **Sharding Middleware**: Routes requests to correct shard
3. **Database Configuration**: Multiple database connections
4. **Cross-Shard Query Tools**: For admin operations

### Code Changes
- Add sharding middleware to request pipeline
- Modify models to work with multiple databases
- Create admin controllers for cross-shard operations
- Update tests to handle multiple shards

### Operational Requirements
- Database provisioning for each shard
- Migration tools for all shards
- Monitoring for each shard
- Backup/restore procedures per shard

## Alternatives Considered

### Alternative 1: User ID as Shard Key
- **Description**: Shard by individual user rather than organization
- **Pros**: More even distribution, finer-grained scaling
- **Cons**: Splits organization data across shards, complicates most queries
- **Why rejected**: Would require cross-shard queries for basic organization operations

### Alternative 2: Geographic Sharding
- **Description**: Shard by user/organization location
- **Pros**: Data locality, potential compliance benefits
- **Cons**: Uneven distribution, complexity, not relevant to our use case
- **Why rejected**: Adds unnecessary complexity without clear benefits

### Alternative 3: Hash-Based Sharding
- **Description**: Use hash of organization name or other attribute
- **Pros**: Better distribution than modulo of sequential IDs
- **Cons**: More complex routing, harder to predict shard for debugging
- **Why rejected**: Marginal benefits don't justify complexity increase

### Alternative 4: Directory-Based Sharding
- **Description**: Maintain a lookup table mapping organizations to shards
- **Pros**: Perfect control over distribution, easy rebalancing
- **Cons**: Additional infrastructure, single point of failure, lookup overhead
- **Why rejected**: Adds significant complexity and infrastructure requirements

## Related Decisions
- [002-sqlite-development.md](./002-sqlite-development.md) - Database choice for development
- Future ADR needed: Production database sharding strategy
- Future ADR needed: Cross-shard query optimization strategy

---

## Implementation Notes

### Current Shard Count
Starting with 3 shards for development and testing. Can be increased as needed.

### Monitoring Requirements
- Track request distribution across shards
- Monitor shard performance independently
- Alert on shard unavailability
- Track cross-shard operation performance

### Future Considerations
- May need to implement dedicated shards for very large organizations
- Consider hash-based distribution if ID patterns cause uneven distribution
- Evaluate tenant size-based routing as application grows