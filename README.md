# Sharding Playground

A multi-tenant SaaS application ready for experimenting with database sharding strategies and distributed data patterns.

**Current State:** Standard Rails API without sharding - ready to add sharding functionality.

## Project Structure

```
/
├── sharding_test_api/   # Rails API application
├── sharding-tools/      # Collection of sharding utilities
│   ├── shard-router/    # Request routing logic
│   ├── data-migrator/   # Cross-shard migration tools
│   └── analytics/       # Cross-shard reporting tools
└── docs/               # Documentation and examples
```

## Quick Start

### Local Development (Ruby)

1. **Install Ruby 3.3.0** (using rbenv/rvm)
   ```bash
   rbenv install 3.3.0
   rbenv local 3.3.0
   ```

2. **Setup Rails API**
   ```bash
   cd sharding_test_api
   bundle install
   bundle exec rails new . --api --database=sqlite3 --skip-git
   bundle exec rails db:create db:migrate
   bundle exec rails server
   ```

3. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

### Docker Development

1. **Start services**
   ```bash
   docker-compose up --build
   ```

2. **Access API**
   ```
   http://localhost:3000
   ```

## Data Model

Multi-tenant project management SaaS:

- **organizations**: Tenant boundary (future shard key: `organization_id`)
- **users**: Belongs to organization
- **projects**: Belongs to organization
- **tasks**: Belongs to project/organization
- **audit_logs**: Cross-tenant compliance data
- **feature_usage**: Cross-tenant analytics

## API Endpoints

### Organization-scoped operations
- `GET /api/v1/organizations/:org_id/projects`
- `POST /api/v1/organizations/:org_id/tasks`
- `GET /api/v1/organizations/:org_id/users`

### Cross-tenant admin operations
- `GET /api/v1/admin/organizations`
- `GET /api/v1/admin/audit-logs`
- `GET /api/v1/admin/feature-usage`