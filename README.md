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
./alb_logs.sh --ip <ip_address> <endpoint1>[,endpoint2,...] [--env <environment>] [--cache|--fresh]
./alb_logs.sh --ip <ip_address> <minutes> [--env <environment>] [--cache|--fresh]
./alb_logs.sh --ip <ip_address> [--env <environment>] [--cache|--fresh]
```

## Arguments

- **endpoint**: API endpoint(s) to filter. Use comma-separated for multiple:
  - Single: `/api`, `/burn`, `/marketplace`
  - Multiple: `/marketplace,/cart,/burn`
- **minutes**: Number of minutes back to search (regular mode only)
- **--ip**: IP address to trace (IP mode only)

## Options

- **--env**: Environment: `prod` (default), `staging`, `dev`
- **--cache**: Use smart caching (downloads only missing data)
- **--fresh**: Force fresh download (ignore cache completely)

## Output Columns

- **EDT Time**: Request timestamp in your local timezone
- **Req_Proc_Time**: Request processing time - time from LB receiving request to sending to target
- **ELB_Status**: Load balancer status code (colorized)
- **Target_Proc_Time**: Target processing time - time from LB sending request to target starting response
- **Target_Status**: Target application status code - what the backend actually returned (colorized)
- **Received_Bytes**: Request size in bytes
- **Client_IP**: Source IP address (colorized)
- **User_Agent**: Browser/client user agent (truncated, colorized)
- **Endpoint**: API endpoint path (colorized)

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
```

### IP Tracing Mode
```bash
# Trace IP across single endpoint
./alb_logs.sh --ip 64.252.70.194 /marketplace

# Trace IP across multiple endpoints
./alb_logs.sh --ip 10.0.0.50 /api,/auth,/burn --cache

# Trace IP for specific time range (last 30 minutes)
./alb_logs.sh --ip 64.252.70.194 30 --cache

# Trace IP across all endpoints (no time limit)
./alb_logs.sh --ip 64.252.70.194 --cache

# Trace IP in staging environment
./alb_logs.sh --ip 192.168.1.100 /notifications/subscribe --env staging
```

## Environments

- **prod**: Production logs (default)
- **staging**: Staging environment logs  
- **dev**: Development environment logs

## Cache Behavior

- Cache files stored as `alb_logs_<env>_cache.log`
- **--cache**: Use cached data when available, download missing ranges
- **--fresh**: Force complete fresh download, update cache
- **No flag**: Download fresh data without caching
- IP tracing works with both cached and fresh data

## Requirements

- AWS CLI configured with S3 access
- Bash shell
- Standard Unix utilities (awk, sed, sort, etc.)

## Notes

- Downloads fresh data by default for accuracy
- Smart cache downloads only missing time ranges
- Times automatically converted from UTC to local timezone
- Results sorted chronologically
- Multiple endpoints show combined results with endpoint column
- IP mode processes most selective filter first for optimal performance

## Help

For complete usage information:
```bash
./alb_logs.sh --help
```
