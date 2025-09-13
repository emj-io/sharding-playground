# Architecture Documentation

This directory contains comprehensive documentation about database sharding, multi-tenancy patterns, and distributed system design, with practical examples from our Rails API implementation.

## 📚 Documentation Structure

### [Fundamentals](./fundamentals/)
Core concepts and principles for understanding sharding and distributed systems:
- **[Sharding Basics](./fundamentals/sharding-basics.md)** - What is sharding, when to use it, trade-offs
- **[Multi-Tenancy Patterns](./fundamentals/multi-tenancy-patterns.md)** - Different approaches to multi-tenant architecture
- **[Data Modeling for Sharding](./fundamentals/data-modeling.md)** - How to design your data model for sharding
- **[Consistency Models](./fundamentals/consistency-models.md)** - CAP theorem, eventual consistency, transactions

### [Patterns](./patterns/)
Design patterns and strategies for sharded systems:
- **[Shard Key Selection](./patterns/shard-key-selection.md)** - Choosing the right shard key strategy
- **[Cross-Shard Queries](./patterns/cross-shard-queries.md)** - Strategies for querying across multiple shards
- **[Data Migration](./patterns/data-migration.md)** - Moving and rebalancing data between shards
- **[Monitoring & Observability](./patterns/monitoring-observability.md)** - How to monitor sharded systems

### [Implementation](./implementation/)
Practical implementation guides with Rails examples:
- **[Rails Sharding Setup](./implementation/rails-sharding-setup.md)** - Step-by-step Rails sharding implementation
- **[Connection Management](./implementation/connection-management.md)** - Database connection handling across shards
- **[Middleware & Routing](./implementation/middleware-routing.md)** - Request routing to correct shards
- **[Testing Strategies](./implementation/testing-strategies.md)** - How to test sharded applications

### [Architecture Decisions](./decisions/)
Architecture Decision Records (ADRs) documenting key design choices:
- **[ADR Template](./decisions/000-adr-template.md)** - Template for documenting decisions
- **[Organization ID as Shard Key](./decisions/001-organization-shard-key.md)** - Why we chose organization_id
- **[SQLite for Development](./decisions/002-sqlite-development.md)** - Database choice for local development

### [Examples](./examples/)
Practical code examples and case studies:
- **[Rails Application Structure](./examples/rails-application-structure.md)** - Current application design and patterns
- **[Common Scenarios](./examples/common-scenarios.md)** - Typical single-tenant and cross-tenant operations
- **[Before & After Sharding](./examples/before-after-sharding.md)** - Code comparison showing migration path

## 🎯 Using This Documentation

### For Learning
Start with **Fundamentals** to understand core concepts, then move to **Patterns** for design strategies, and finally **Implementation** for practical application.

### For Reference
Use **Patterns** and **Implementation** as quick reference guides when implementing specific features.

### For Decision Making
Consult **Architecture Decisions** to understand the rationale behind design choices and apply similar reasoning to new decisions.

### For Examples
Check **Examples** for practical code snippets and real-world scenarios from our Rails application.

## 🚀 Getting Started

If you're new to sharding, start here:
1. [Sharding Basics](./fundamentals/sharding-basics.md)
2. [Multi-Tenancy Patterns](./fundamentals/multi-tenancy-patterns.md)
3. [Shard Key Selection](./patterns/shard-key-selection.md)
4. [Rails Sharding Setup](./implementation/rails-sharding-setup.md)

## 🤝 Contributing

When adding new documentation:
- Include practical examples from our Rails application when possible
- Document trade-offs and alternatives considered
- Follow the ADR format for architectural decisions
- Keep content focused and actionable