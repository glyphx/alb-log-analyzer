#!/usr/bin/env bash

# Function to build grep pattern for multiple endpoints
build_endpoint_pattern() {
    local endpoints="$1"
    if [[ "$endpoints" == *","* ]]; then
        # Multiple endpoints - convert comma-separated to grep OR pattern
        echo "$endpoints" | sed 's/,/|/g'
    else
        # Single endpoint
        echo "$endpoints"
    fi
}

# Function to process log output
process_logs() {
    awk -F'"' 'BEGIN {
      # Get timezone offset once at startup
      "date +%z" | getline tz_offset_str
      close("date +%z")
      
      # Parse timezone offset (+/-HHMM)
      tz_sign = substr(tz_offset_str, 1, 1) == "-" ? -1 : 1
      tz_hours = substr(tz_offset_str, 2, 2)
      tz_minutes = substr(tz_offset_str, 4, 2)
      tz_offset_seconds = tz_sign * (tz_hours * 3600 + tz_minutes * 60)
    }
    {
      time = substr($1, index($1, " ") + 1)
      utc_time = substr(time, 1, 19)
      
      # Parse UTC timestamp: 2025-01-15T12:34:56
      split(utc_time, dt_parts, "T")
      split(dt_parts[1], date_parts, "-")
      split(dt_parts[2], time_parts, ":")
      
      year = date_parts[1]
      month = date_parts[2] 
      day = date_parts[3]
      hour = time_parts[1]
      minute = time_parts[2]
      second = time_parts[3]
      
      # Convert to epoch seconds (UTC)
      utc_epoch = mktime(year " " month " " day " " hour " " minute " " second)
      
      # Convert to local time
      local_epoch = utc_epoch + tz_offset_seconds
      local_time = strftime("%H:%M:%S", local_epoch)
      
      split($1, fields, " ")
      req_proc_time = fields[6]
      target_proc_time = fields[7]
      response_proc_time = fields[8]
      elb_status = fields[9]
      target_status = fields[10] 
      received_bytes = fields[11]
      sent_bytes = fields[12]
      client_ip = fields[4]
      split(client_ip, ip_parts, ":")
      client_ip = ip_parts[1]
      
      user_agent = $4
      if (length(user_agent) > 50) {
        user_agent = substr(user_agent, 1, 47) "..."
      }
      
      # Color codes
      red = "\033[31m"
      green = "\033[32m"
      yellow = "\033[33m"
      blue = "\033[34m"
      cyan = "\033[36m"
      salmon = "\033[38;5;210m"
      purple = "\033[35m"
      bold = "\033[1m"
      reset = "\033[0m"
      
      # Color status codes
      if (elb_status == "200" || elb_status == "201" || elb_status == "204") {
        elb_color = green bold elb_status reset
      } else if (elb_status == "304") {
        elb_color = blue elb_status reset
      } else if (elb_status == "401" || elb_status == "403") {
        elb_color = yellow elb_status reset
      } else if (elb_status >= "400") {
        elb_color = red bold elb_status reset
      } else {
        elb_color = elb_status
      }
      
      if (target_status == "200" || target_status == "201" || target_status == "204") {
        target_color = green bold target_status reset
      } else if (target_status == "304") {
        target_color = blue target_status reset
      } else if (target_status == "401" || target_status == "403") {
        target_color = yellow target_status reset
      } else if (target_status >= "400") {
        target_color = red bold target_status reset
      } else {
        target_color = target_status
      }
      
      # Color IP addresses with proper padding
      ip_padded = sprintf("%-13s", client_ip)
      ip_color = salmon ip_padded reset
      
      # Color target processing time (red if > 1 second)
      if (target_proc_time > 1.0) {
        time_color = red bold target_proc_time reset
      } else if (target_proc_time > 0.5) {
        time_color = yellow target_proc_time reset
      } else {
        time_color = target_proc_time
      }
      
      # Color target status
      if (target_status == "200" || target_status == "201" || target_status == "204") {
        target_status_color = green bold target_status reset
      } else if (target_status == "304") {
        target_status_color = blue target_status reset
      } else if (target_status == "401" || target_status == "403") {
        target_status_color = yellow target_status reset
      } else if (target_status >= "400") {
        target_status_color = red bold target_status reset
      } else {
        target_status_color = target_status
      }
      
      # Extract endpoint from request
      request_line = $0
      if (match(request_line, /(GET|POST|PUT|PATCH|DELETE|OPTIONS) https:\/\/[^\/]*\/([^" ?]+)/, endpoint_match)) {
        endpoint = "/" endpoint_match[2]
      } else {
        endpoint = "/"
      }
      
      # Color received bytes with proper padding
      bytes_padded = sprintf("%4s", received_bytes)
      bytes_color = purple bytes_padded reset
      
      printf "%-8s | %s | %-3s | %-3s | %-5s | %-6s | %s | %-25s | %s\n", local_time, ip_color, elb_color, target_status_color, req_proc_time, time_color, bytes_color, cyan endpoint reset, green user_agent reset
    }' | sort
}

show_help() {
    echo -e "\033[1m\033[36mALB Log Analysis Tool\033[0m"
    echo ""
    echo -e "\033[33mUSAGE:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m<endpoint1>[,endpoint2,...]\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--cache\033[0m|\033[31m--fresh\033[0m]"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[91m<ip_address>\033[0m \033[36m<endpoint1>[,endpoint2,...]\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--cache\033[0m|\033[31m--fresh\033[0m]"
    echo ""
    echo -e "\033[33mDESCRIPTION:\033[0m"
    echo "    Analyzes AWS Application Load Balancer logs for specific API endpoints."
    echo "    Downloads fresh data by default, with --cache for smart caching."
    echo "    IP mode traces specific IP addresses across endpoints."
    echo ""
    echo -e "\033[33mARGUMENTS:\033[0m"
    echo -e "    \033[36mendpoint\033[0m     API endpoint(s) to filter. Use comma-separated for multiple:"
    echo -e "                   Single: /api, /burn, /marketplace"
    echo -e "                   Multiple: /marketplace,/cart,/burn"
    echo -e "    \033[35mminutes\033[0m      Number of minutes back to search (required for all modes)"
    echo -e "    \033[31m--ip\033[0m         IP address to trace (IP mode only)"
    echo ""
    echo -e "\033[33mOPTIONS:\033[0m"
    echo -e "    \033[31m--env\033[0m        Environment: \033[32mprod\033[0m (default), \033[33mstaging\033[0m, \033[34mdev\033[0m"
    echo -e "    \033[31m--cache\033[0m      Use smart caching (downloads only missing data)"
    echo -e "    \033[31m--fresh\033[0m      Force fresh download (ignore cache completely)"
    echo ""
    echo -e "\033[33mOUTPUT COLUMNS:\033[0m"
    echo -e "    \033[31mEDT Time\033[0m         Request timestamp in your local timezone"
    echo -e "    \033[91mClient_IP\033[0m        Source IP address (colorized)"
    echo -e "    \033[32mELB_Status\033[0m       Load balancer status code (colorized)"
    echo -e "    \033[35mTarget_Status\033[0m    Target application status code - what the backend actually returned (colorized)"
    echo -e "    \033[33mReq_Proc_Time\033[0m    Request processing time - time from LB receiving request to sending to target"
    echo -e "    \033[36mTarget_Proc_Time\033[0m Target processing time - time from LB sending request to target starting response"
    echo -e "    \033[34mReceived_Bytes\033[0m   Request size in bytes"
    echo -e "    \033[36mEndpoint\033[0m         API endpoint path (colorized)"
    echo -e "    \033[92mUser_Agent\033[0m       Browser/client user agent (truncated, colorized)"
    echo ""
    echo -e "\033[33mSTATUS COLORS:\033[0m"
    echo -e "    \033[32m\033[1m200/201/204\033[0m Success responses"
    echo -e "    \033[34m304\033[0m         Not modified"
    echo -e "    \033[33m401/403\033[0m     Authentication/authorization errors"
    echo -e "    \033[31m\033[1m4xx/5xx\033[0m     Other client/server errors"
    echo ""
    echo -e "\033[33mEXAMPLES:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m/burn\033[0m \033[35m60\033[0m                   # Single endpoint: /burn requests (last 60 minutes)"
    echo -e "    \033[32m$0\033[0m \033[36m/marketplace,/cart\033[0m \033[35m30\033[0m        # Multiple endpoints: marketplace + cart (30 min)"
    echo -e "    \033[32m$0\033[0m \033[36m/api,/auth,/burn\033[0m \033[35m120\033[0m \033[31m--cache\033[0m  # Three endpoints with caching (2 hours)"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[91m64.252.70.194\033[0m \033[36m/marketplace\033[0m \033[35m60\033[0m # Trace IP on endpoint (last 60 min)"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[91m10.0.0.50\033[0m \033[36m/api,/auth,/burn\033[0m \033[35m30\033[0m \033[31m--cache\033[0m # Trace IP across multiple endpoints"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[91m64.252.70.194\033[0m \033[36m/marketplace\033[0m \033[35m30\033[0m \033[31m--cache\033[0m        # Trace IP for specific time range (30 min)"
    echo ""
    echo -e "\033[33mENVIRONMENTS:\033[0m"
    echo -e "    \033[32mprod\033[0m     - Production logs (default)"
    echo -e "    \033[33mstaging\033[0m  - Staging environment logs"  
    echo -e "    \033[34mdev\033[0m      - Development environment logs"
    echo ""
    echo -e "\033[33mNOTES:\033[0m"
    echo "    - Requires AWS CLI configured with S3 access"
    echo "    - Downloads fresh data by default for accuracy"
    echo "    - Smart cache downloads only missing time ranges"
    echo "    - Times automatically converted from UTC to local timezone"
    echo "    - Results sorted chronologically"
    echo "    - Rainbow headers and colorized output for easy reading"
    echo "    - Multiple endpoints show combined results with endpoint column"
    echo "    - IP mode processes most selective filter first for optimal performance"
    echo ""
    echo -e "\033[33mCACHE BEHAVIOR:\033[0m"
    echo "    - Cache files stored as alb_logs_<env>_cache.log"
    echo "    - --cache: Use cached data when available, download missing ranges"
    echo "    - --fresh: Force complete fresh download, update cache"
    echo "    - No flag: Use existing cache if available, smart caching by default"
    echo "    - Status shows: 'cached', 'smart cache', or 'fresh data'"
    echo ""
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Parse arguments
IP_MODE=false
IP_ADDRESS=""
ENDPOINT=""
MINUTES_BACK=""
ENV="prod"
USE_CACHE=false
FORCE_FRESH=false

if [ "$1" = "--ip" ]; then
    IP_MODE=true
    IP_ADDRESS="$2"
    ENDPOINT="$3"
    MINUTES_BACK="$4"
    shift 4
else
    ENDPOINT="$1"
    MINUTES_BACK="$2"
    shift 2
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV="$2"
            shift 2
            ;;
        --cache)
            USE_CACHE=true
            shift
            ;;
        --fresh)
            FORCE_FRESH=true
            shift
            ;;
        *)
            echo "Error: Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

if [ "$IP_MODE" = true ]; then
    if [ -z "$IP_ADDRESS" ] || [ -z "$MINUTES_BACK" ] || ! [[ "$MINUTES_BACK" =~ ^[0-9]+$ ]]; then
        echo "Error: IP mode requires --ip <address> <endpoint> <minutes>"
        show_help
        exit 1
    fi
else
    if [ -z "$ENDPOINT" ] || [ -z "$MINUTES_BACK" ] || ! [[ "$MINUTES_BACK" =~ ^[0-9]+$ ]]; then
        echo "Error: Regular mode requires <endpoint> <minutes>"
        show_help
        exit 1
    fi
fi

#!/bin/bash

# Load configuration
if [ -f "alb_logs.conf" ]; then
    source alb_logs.conf
fi

# Set S3 bucket based on environment
case $ENV in
    prod)
        S3_BUCKET="$PROD_S3_BUCKET"
        S3_PATH="$PROD_S3_PATH"
        ;;
    staging)
        S3_BUCKET="$STAGING_S3_BUCKET"
        S3_PATH="$STAGING_S3_PATH"
        ;;
    dev)
        S3_BUCKET="$DEV_S3_BUCKET"
        S3_PATH="$DEV_S3_PATH"
        ;;
    *)
        echo "Error: Invalid environment. Use: prod, staging, or dev"
        exit 1
        ;;
esac

# Default cache file
CACHE_FILE="alb_logs_${ENV}_cache.log"

# Set time variables when needed
if [ "$IP_MODE" = false ] || [ -n "$MINUTES_BACK" ]; then
    MINUTES_AGO=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y-%m-%dT%H:%M:%S')
fi

TODAY=$(date -u '+%Y/%m/%d')
LOCAL_TZ=$(date +%Z)

# Handle cache logic
if [ "$FORCE_FRESH" = true ]; then
    # Force fresh download, ignore cache completely
    USE_CACHE=false
elif [ -f "$CACHE_FILE" ]; then
    # Cache exists, use smart caching
    USE_CACHE=true
    # Smart cache mode
    CACHE_NEEDS_UPDATE=false
    
    # Check if cache file exists and has content
    if [ ! -f "$CACHE_FILE" ] || [ ! -s "$CACHE_FILE" ]; then
        echo "📥 Cache empty or missing, downloading fresh data..."
        CACHE_NEEDS_UPDATE=true
        CACHE_MODE="fresh data"
    else
        # Get oldest and newest timestamps in cache
        CACHE_OLDEST=$(awk 'NR==1 {print $2}' "$CACHE_FILE" | head -1)
        CACHE_NEWEST=$(tail -1 "$CACHE_FILE" | awk '{print $2}')
        CURRENT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%S')
        
        # Check if cache covers requested time range and is recent enough
        if [[ "$CACHE_OLDEST" > "$MINUTES_AGO" ]] || [[ "$CACHE_NEWEST" < "$MINUTES_AGO" ]]; then
            echo "📥 Cache doesn't cover requested time range, downloading additional data..."
            CACHE_NEEDS_UPDATE=true
            CACHE_MODE="smart cache"
        else
            echo "📂 Using cache: $CACHE_FILE ($ENV environment)"
            CACHE_MODE="cached"
        fi
    fi
    
    if [ "$CACHE_NEEDS_UPDATE" = true ]; then
        # Download and append/create cache
        CUTOFF_TIME=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y%m%d%H%M')
        
        LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ | awk -v cutoff="$CUTOFF_TIME" '{
            if (match($4, /[0-9]{8}T[0-9]{4}Z/)) {
                timestamp = substr($4, RSTART, 13)
                file_time = substr(timestamp, 1, 8) substr(timestamp, 10, 4)
                if (file_time >= cutoff) print $4
            }
        }')
        
        TOTAL_FILES=$(echo "$LOG_FILES" | wc -l)
        echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
        
        # Download new data and merge with existing cache
        TEMP_DIR=$(mktemp -d)
        TEMP_FILE=$(mktemp)
        
        # Download files in parallel to temp directory
        echo "$LOG_FILES" | xargs -I {} -P 20 sh -c 'aws s3 cp s3://$1/$2/$3/{} $4/{} --no-progress >/dev/null 2>&1' _ "$S3_BUCKET" "$S3_PATH" "$TODAY" "$TEMP_DIR" &
        
        # Show progress while downloading
        DOWNLOAD_PID=$!
        while kill -0 $DOWNLOAD_PID 2>/dev/null; do
            printf "\r📥 Downloading %d files in parallel..." "$TOTAL_FILES" >&2
            sleep 0.5
        done
        wait $DOWNLOAD_PID
        printf "\r📥 Downloaded %d files                    \n" "$TOTAL_FILES" >&2
        
        # Decompress and concatenate files sequentially
        for file in "$TEMP_DIR"/*; do
            [ -f "$file" ] && zcat "$file" 2>/dev/null >> "$TEMP_FILE"
        done
        rm -rf "$TEMP_DIR"
        
        # Merge with existing cache, remove duplicates, sort by timestamp
        if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
            cat "$CACHE_FILE" "$TEMP_FILE" | sort -u -k2,2 > "${CACHE_FILE}.tmp"
        else
            sort -k2,2 "$TEMP_FILE" > "${CACHE_FILE}.tmp"
        fi
        
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        rm -f "$TEMP_FILE"
        echo "" >&2
    fi
    
    if [ "$IP_MODE" = true ]; then
        echo -e "🔍 Tracing IP \033[91m$IP_ADDRESS\033[0m across \033[36m$ENDPOINT\033[0m from \033[31m$MINUTES_AGO\033[0m to now (\033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
    else
        echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
    fi
else
    # Fresh mode (default when no cache exists)
    CACHE_MODE="fresh data"
    if [ "$IP_MODE" = true ]; then
        echo -e "🔍 Tracing IP \033[91m$IP_ADDRESS\033[0m across \033[36m$ENDPOINT\033[0m from \033[31m$MINUTES_AGO\033[0m to now (\033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
    else
        echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
    fi
    echo "📊 Downloading fresh ALB logs from S3..."
fi

# Print headers before processing data
echo -e "• \033[31mEDT Time\033[0m: Local timestamp"
echo -e "• \033[91mClient_IP\033[0m: Source IP address"
echo -e "• \033[32mELB_Status\033[0m: Load balancer status code"
echo -e "• \033[35mTarget_Status\033[0m: Target application status code - what the backend actually returned"
echo -e "• \033[33mReq_Proc_Time\033[0m: Request processing time - time from LB receiving request to sending to target"
echo -e "• \033[36mTarget_Proc_Time\033[0m: Target processing time - time from LB sending request to target starting response"
echo -e "• \033[34mReceived_Bytes\033[0m: Request size in bytes"
echo -e "• \033[36mEndpoint\033[0m: API endpoint path"
echo -e "• \033[92mUser_Agent\033[0m: Browser info (truncated)"
echo -e "Status Colors: \033[32m\033[1m200/201/204\033[0m \033[34m304\033[0m \033[33m401/403\033[0m \033[31m\033[1m4xx/5xx\033[0m"
echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[91mClient_IP\033[0m   | \033[32mELB\033[0m | \033[35mTgt\033[0m | \033[33mReq_T\033[0m | \033[36mTgt_T\033[0m  | \033[34mBytes\033[0m | \033[36mEndpoint\033[0m                  | \033[92mUser_Agent\033[0m"
echo "---------|-------------|-----|-----|-------|--------|------|---------------------------|------------"

if [ "$USE_CACHE" = false ]; then
    # Fresh mode - download and create cache for future use
    CUTOFF_TIME=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y%m%d%H%M')
    # Fresh download
    LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ | awk -v cutoff="$CUTOFF_TIME" '{
        if (match($4, /[0-9]{8}T[0-9]{4}Z/)) {
            timestamp = substr($4, RSTART, 13)
            file_time = substr(timestamp, 1, 8) substr(timestamp, 10, 4)
            if (file_time >= cutoff) print $4
        }
    }')
    
    TOTAL_FILES=$(echo "$LOG_FILES" | wc -l)
    echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
    
    if [ "$TOTAL_FILES" -eq 0 ]; then
        echo "⚠️  No recent log files found."
        exit 0
    fi
    
    # Download and create cache file for future use
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE=$(mktemp)
    
    # Download files in parallel to temp directory
    echo "$LOG_FILES" | xargs -I {} -P 20 sh -c 'aws s3 cp s3://$1/$2/$3/{} $4/{} --no-progress >/dev/null 2>&1' _ "$S3_BUCKET" "$S3_PATH" "$TODAY" "$TEMP_DIR" &
    
    # Show progress while downloading
    DOWNLOAD_PID=$!
    while kill -0 $DOWNLOAD_PID 2>/dev/null; do
        printf "\r📥 Downloading %d files in parallel..." "$TOTAL_FILES" >&2
        sleep 0.5
    done
    wait $DOWNLOAD_PID
    printf "\r📥 Downloaded %d files                    \n" "$TOTAL_FILES" >&2
    
    # Decompress and concatenate files sequentially
    for file in "$TEMP_DIR"/*; do
        [ -f "$file" ] && zcat "$file" 2>/dev/null >> "$TEMP_FILE"
    done
    rm -rf "$TEMP_DIR"
    
    # Create cache file and process
    sort -k2,2 "$TEMP_FILE" > "$CACHE_FILE"
    
    if [ "$IP_MODE" = true ]; then
        # IP mode with both endpoint and time filtering (both required)
        ENDPOINT_PATTERN=$(build_endpoint_pattern "$ENDPOINT")
        grep " $IP_ADDRESS:" "$CACHE_FILE" | grep -E "$ENDPOINT_PATTERN" | awk -v start="$MINUTES_AGO" '$2 >= start' | process_logs
    else
        # Regular mode: endpoints first, then time filter
        ENDPOINT_PATTERN=$(build_endpoint_pattern "$ENDPOINT")
        grep -E "$ENDPOINT_PATTERN" "$CACHE_FILE" | awk -v start="$MINUTES_AGO" '$2 >= start' | process_logs
    fi
    
    rm -f "$TEMP_FILE"
    
    echo "" >&2
    echo "✅ Processing complete" >&2
else
    # Use cached data
    if [ "$IP_MODE" = true ]; then
        # IP mode with both endpoint and time filtering (both required)
        ENDPOINT_PATTERN=$(build_endpoint_pattern "$ENDPOINT")
        grep " $IP_ADDRESS:" "$CACHE_FILE" | grep -E "$ENDPOINT_PATTERN" | awk -v start="$MINUTES_AGO" '$2 >= start' | process_logs
    else
        # Regular mode: endpoints first, then time filter
        ENDPOINT_PATTERN=$(build_endpoint_pattern "$ENDPOINT")
        grep -E "$ENDPOINT_PATTERN" "$CACHE_FILE" | awk -v start="$MINUTES_AGO" '$2 >= start' | process_logs
    fi
fi

