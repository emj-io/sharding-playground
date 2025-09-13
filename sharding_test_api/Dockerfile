FROM ruby:3.3.5-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    sqlite-dev \
    nodejs \
    npm \
    git \
    bash

# Set working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config --global frozen 1 && \
    bundle install

# Copy application code
COPY . .

# Create database directory
RUN mkdir -p db

# Expose port
EXPOSE 3000

# Default command
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]