# Comprehensive seed data for testing multi-tenant application
# This creates organizations of varying sizes to test scaling scenarios

puts "🌱 Creating seed data for multi-tenant test app..."

# Clear existing data
puts "Clearing existing data..."
AuditLog.delete_all
FeatureUsage.delete_all
Task.delete_all
Project.delete_all
User.delete_all
Organization.delete_all

# Organization templates with different sizes
organization_templates = [
  # Small organizations (1-5 users)
  { name: "Startup Alpha", plan: "free", user_count: 2, project_count: 1, tasks_per_project: 5 },
  { name: "Freelance Design Co", plan: "free", user_count: 3, project_count: 2, tasks_per_project: 8 },
  { name: "Beta Consultancy", plan: "pro", user_count: 5, project_count: 3, tasks_per_project: 12 },

  # Medium organizations (10-50 users)
  { name: "TechCorp Solutions", plan: "pro", user_count: 15, project_count: 5, tasks_per_project: 20 },
  { name: "Digital Marketing Plus", plan: "pro", user_count: 25, project_count: 8, tasks_per_project: 15 },
  { name: "DevOps Masters", plan: "enterprise", user_count: 35, project_count: 12, tasks_per_project: 25 },

  # Large organizations (50+ users)
  { name: "Enterprise Corp", plan: "enterprise", user_count: 75, project_count: 20, tasks_per_project: 40 },
  { name: "Global Solutions Inc", plan: "enterprise", user_count: 120, project_count: 30, tasks_per_project: 35 },
  { name: "Mega Systems Ltd", plan: "enterprise", user_count: 200, project_count: 50, tasks_per_project: 30 },

  # Test edge cases
  { name: "Solo Worker", plan: "free", user_count: 1, project_count: 1, tasks_per_project: 3 },
  { name: "Project Heavy Org", plan: "enterprise", user_count: 20, project_count: 100, tasks_per_project: 5 },
  { name: "Task Heavy Org", plan: "enterprise", user_count: 10, project_count: 5, tasks_per_project: 200 }
]

# User role distribution
USER_ROLES = %w[admin member viewer].freeze
PROJECT_STATUSES = %w[active archived completed].freeze
TASK_STATUSES = %w[todo in_progress done].freeze
TASK_PRIORITIES = %w[low medium high].freeze

# Feature names for usage tracking
FEATURE_NAMES = %w[
  users_created users_listed projects_created projects_listed
  tasks_created tasks_listed tasks_updated projects_updated
].freeze

def create_organization_data(template, org_id)
  puts "  Creating #{template[:name]} (ID: #{org_id})"

  # Create organization
  org = Organization.create!(
    id: org_id,
    name: template[:name],
    plan_type: template[:plan]
  )

  # Create users
  users = []
  template[:user_count].times do |i|
    role = case i
           when 0 then 'admin'  # First user is always admin
           when 1..2 then 'member'  # Next 2 are members
           else USER_ROLES.sample  # Rest are random
           end

    users << User.create!(
      organization: org,
      email: "user#{i + 1}@#{template[:name].downcase.gsub(/\s+/, '')}.com",
      name: "User #{i + 1}",
      role: role
    )
  end

  # Create projects
  projects = []
  template[:project_count].times do |i|
    status = case i % 10
             when 8..9 then PROJECT_STATUSES.sample  # 20% non-active
             else 'active'  # 80% active
             end

    projects << Project.create!(
      organization: org,
      name: "Project #{i + 1}",
      description: "Description for project #{i + 1} in #{org.name}",
      status: status
    )
  end

  # Create tasks
  total_tasks = 0
  projects.each do |project|
    template[:tasks_per_project].times do |i|
      status = TASK_STATUSES.sample
      priority = case i % 5
                 when 4 then 'high'    # 20% high priority
                 when 3 then 'low'     # 20% low priority
                 else 'medium'         # 60% medium priority
                 end

      assigned_user = users.sample if rand < 0.8  # 80% of tasks are assigned

      due_date = case rand
                 when 0..0.1 then Date.current - rand(30).days  # 10% overdue
                 when 0.1..0.3 then Date.current + rand(7).days   # 20% due soon
                 when 0.3..0.7 then Date.current + rand(30).days  # 40% due later
                 else nil  # 30% no due date
                 end

      Task.create!(
        project: project,
        organization: org,
        assigned_user: assigned_user,
        title: "Task #{i + 1} for #{project.name}",
        description: "Detailed description for task #{i + 1}",
        status: status,
        priority: priority,
        due_date: due_date
      )
      total_tasks += 1
    end
  end

  puts "    ✓ #{users.count} users, #{projects.count} projects, #{total_tasks} tasks"

  # Create audit logs and feature usage
  create_audit_and_usage_data(org_id, template)
end

def create_audit_and_usage_data(org_id, template)
  # Create audit logs for recent activity
  audit_actions = %w[created_user updated_user created_project updated_project created_task updated_task deleted_task]

  # Create 30-90 days of audit history
  (30..90).to_a.sample.times do
    date = rand(90.days).seconds.ago

    AuditLog.create!(
      organization_id: org_id,
      user_id: nil,  # Simplified - no user association in seeds
      action: audit_actions.sample,
      resource_type: %w[User Project Task].sample,
      resource_id: rand(1000),
      metadata: { source: 'seed_data', timestamp: date },
      created_at: date,
      updated_at: date
    )
  end

  # Create feature usage data for last 60 days
  60.times do |days_ago|
    date = Date.current - days_ago.days

    # Each organization uses features differently based on size
    usage_multiplier = case template[:user_count]
                       when 1..5 then 1
                       when 6..25 then 3
                       when 26..50 then 8
                       else 15
                       end

    FEATURE_NAMES.each do |feature|
      usage_count = (rand(10) + 1) * usage_multiplier

      # Not all features used every day
      next if rand < 0.3

      FeatureUsage.create!(
        organization_id: org_id,
        feature_name: feature,
        usage_count: usage_count,
        date: date
      )
    end
  end
end

# Create all organizations
puts "\n📊 Creating organizations..."
organization_templates.each_with_index { |template, index| create_organization_data(template, index + 1) }

# Summary
puts "\n📈 Seed data summary:"
org_count = Organization.count
user_count = User.count
project_count = Project.count
task_count = Task.count
audit_count = AuditLog.count
usage_count = FeatureUsage.count

puts "  #{org_count} organizations created"
puts "  #{user_count} users created"
puts "  #{project_count} projects created"
puts "  #{task_count} tasks created"
puts "  #{audit_count} audit logs created"
puts "  #{usage_count} feature usage records created"

puts "\n✅ Seed data creation complete!"
puts "\n🧪 Test the API with these calls:"
puts "  # Single-tenant operations:"
puts "  GET /api/v1/organizations/1/users"
puts "  GET /api/v1/organizations/5/projects"
puts "  GET /api/v1/organizations/10/tasks"
puts ""
puts "  # Cross-tenant admin operations:"
puts "  GET /api/v1/admin/organizations"
puts "  GET /api/v1/admin/audit_logs"
puts "  GET /api/v1/admin/feature_usage"