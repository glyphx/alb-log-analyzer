# ALB Log Analysis Tool

A colorful command-line tool for analyzing AWS Application Load Balancer logs with real-time filtering, IP tracing, and beautiful output formatting.

## Features

- 🌈 **Colorized Output**: Status codes, IPs, and fields are color-coded for easy reading
- 🔍 **Real-time Filtering**: Filter by endpoint and time range
- 🎯 **IP Tracing**: Special mode to trace specific IP addresses across endpoints
- 🏗️ **Multi-Environment**: Support for prod, staging, and dev environments  
- 📊 **Smart Caching**: Caches downloaded logs for faster subsequent queries
- ⚡ **Efficient Processing**: O(n) performance with optimized filtering
- 🌈 **Rainbow Headers**: Beautiful colorized output for easy reading
- 🔒 **Safe Queries**: Always requires timeframe to prevent accidental large data searches

## Setup

1. **Copy the configuration template:**
   ```bash
   cp alb_logs.conf.template alb_logs.conf
   ```

2. **Edit `alb_logs.conf` with your actual AWS S3 bucket names and paths**

3. **Ensure AWS CLI is configured with appropriate permissions**

## Usage

### Regular Mode
```bash
./alb_logs.sh <endpoint1>[,endpoint2,...] <minutes> [--env <environment>] [--cache|--fresh]
```

### IP Tracing Mode
```bash
./alb_logs.sh --ip <ip_address> <endpoint1>[,endpoint2,...] <minutes> [--env <environment>] [--cache|--fresh]
```

## Arguments

- **endpoint**: API endpoint(s) to filter. Use comma-separated for multiple:
  - Single: `/api`, `/burn`, `/marketplace`
  - Multiple: `/marketplace,/cart,/burn`
- **minutes**: Number of minutes back to search (required for all modes)
- **--ip**: IP address to trace (IP mode only)

## Options

- **--env**: Environment: `prod` (default), `staging`, `dev`
- **--cache**: Use smart caching (downloads only missing data)
- **--fresh**: Force fresh download (ignore cache completely)

## Output Columns

- **EDT Time**: Request timestamp in your local timezone (8-char fixed width)
- **Client_IP**: Source IP address (15-char fixed width, colorized)
- **ELB_Status**: Load balancer status code (colorized)
- **Target_Status**: Target application status code - what the backend actually returned (colorized)
- **Req_Proc_Time**: Request processing time - time from LB receiving request to sending to target
- **Target_Proc_Time**: Target processing time - time from LB sending request to target starting response
- **Received_Bytes**: Request size in bytes
- **Endpoint**: API endpoint path (colorized)
- **User_Agent**: Browser/client user agent (truncated, colorized)

## Status Colors

- 🟢 **200/201/204**: Success responses
- 🔵 **304**: Not modified
- 🟡 **401/403**: Authentication/authorization errors
- 🔴 **4xx/5xx**: Other client/server errors

## Examples

### Regular Mode
```bash
# Single endpoint: /burn requests (last 60 minutes)
./alb_logs.sh /burn 60

# Multiple endpoints: marketplace + cart (30 min)
./alb_logs.sh /marketplace,/cart 30

# Three endpoints with caching (2 hours)
./alb_logs.sh /api,/auth,/burn 120 --cache

# Staging environment with fresh download
./alb_logs.sh /health 15 --env staging --fresh

# Update endpoints (supports all HTTP methods)
./alb_logs.sh /users/update 30 --cache
```

### IP Tracing Mode
```bash
# Trace IP across single endpoint (last 60 minutes)
./alb_logs.sh --ip 64.252.70.194 /marketplace 60

# Trace IP across multiple endpoints (30 minutes)
./alb_logs.sh --ip 10.0.0.50 /api,/auth,/burn 30 --cache

# Trace IP in staging environment
./alb_logs.sh --ip 192.168.1.100 /notifications/subscribe 15 --env staging
```

## Environments

- **prod**: Production logs (default)
- **staging**: Staging environment logs  
- **dev**: Development environment logs

## Cache Behavior

- Cache files stored as `alb_logs_<env>_cache.log`
- **--cache**: Use cached data when available, download missing ranges
- **--fresh**: Force complete fresh download, update cache
- **No flag**: Use existing cache if available, smart caching by default
- **Status indicators**: Shows 'cached', 'smart cache', or 'fresh data'
- Smart cache automatically detects missing time ranges and downloads only needed data
- IP tracing works with all cache modes

## Requirements

- AWS CLI configured with S3 access
- Bash shell
- Standard Unix utilities (awk, sed, sort, etc.)

## Notes

- **Timeframe Required**: All queries must specify a time range to prevent accidental large data searches
- **Smart Caching**: Automatically uses existing cache and downloads missing data when needed
- **HTTP Method Support**: Extracts endpoints from all HTTP methods (GET, POST, PUT, PATCH, DELETE, OPTIONS)
- **Fixed-Width Columns**: Time and IP columns use consistent spacing for better readability
- Times automatically converted from UTC to local timezone
- Results sorted chronologically
- Multiple endpoints show combined results with endpoint column
- IP mode processes most selective filter first for optimal performance

## Help

For complete usage information:
```bash
./alb_logs.sh --help
```
