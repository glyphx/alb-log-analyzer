# ALB Log Analyzer

A colorful command-line tool for analyzing AWS Application Load Balancer (ALB) logs with real-time filtering and beautiful output formatting.

## Features

- 🌈 **Colorized Output**: Status codes, IPs, and fields are color-coded for easy reading
- 🔍 **Real-time Filtering**: Filter by endpoint and time range
- 🏗️ **Multi-Environment**: Support for prod, staging, and dev environments  
- 📊 **Smart Caching**: Caches downloaded logs for faster subsequent queries
- 🎯 **IP Tracing**: Special mode to trace specific IP addresses across endpoints

## Setup

1. **Copy the configuration template:**
   ```bash
   cp alb_logs.conf.template alb_logs.conf
   ```

2. **Edit `alb_logs.conf` with your actual AWS S3 bucket names and paths**

3. **Ensure AWS CLI is configured with appropriate permissions**

## Usage

### Basic Log Analysis
```bash
./alb_logs.sh <endpoint> <minutes_back> [--env <environment>] [--fresh]
```

### Examples
```bash
# Get /api requests from last 10 minutes in prod
./alb_logs.sh /api 10 --env prod

# Get /health requests from last 5 minutes in staging with fresh download
./alb_logs.sh /health 5 --env staging --fresh
```

### IP Tracing Mode
```bash
./alb_logs_ip.sh --ip <ip_address> <endpoint1> [endpoint2] [endpoint3] ...
```

## Color Legend

- 🟢 **Green**: 200/201/204 status codes, user agents
- 🔵 **Blue**: 304 status codes  
- 🟡 **Yellow**: 401/403 status codes
- 🔴 **Red**: 4xx/5xx error status codes, slow response times (>1s)
- 🟠 **Salmon**: IP addresses
- 🟣 **Purple**: Received bytes
- 🔵 **Cyan**: Target processing times

## Requirements

- AWS CLI configured with S3 access
- Bash shell
- Standard Unix utilities (awk, sed, sort, etc.)
