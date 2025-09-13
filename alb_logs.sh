#!/bin/bash

show_help() {
    echo -e "\033[1m\033[36mALB Log Analysis Tool\033[0m"
    echo ""
    echo -e "\033[33mUSAGE:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m<endpoint>\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--fresh\033[0m]"
    echo ""
    echo -e "\033[33mDESCRIPTION:\033[0m"
    echo "    Analyzes AWS Application Load Balancer logs for specific API endpoints."
    echo "    Uses local cache by default, with --fresh to force S3 download."
    echo ""
    echo -e "\033[33mARGUMENTS:\033[0m"
    echo -e "    \033[36mendpoint\033[0m     API endpoint to filter (e.g., /api, /burn, /cart)"
    echo -e "    \033[35mminutes\033[0m      Number of minutes back to search"
    echo ""
    echo -e "\033[33mOPTIONS:\033[0m"
    echo -e "    \033[31m--env\033[0m        Environment: \033[32mprod\033[0m (default), \033[33mstaging\033[0m, \033[34mdev\033[0m"
    echo -e "    \033[31m--fresh\033[0m      Force fresh download from S3 (bypasses cache)"
    echo ""
    echo -e "\033[33mOUTPUT COLUMNS:\033[0m"
    echo -e "    \033[31mEDT Time\033[0m         Request timestamp in your local timezone"
    echo -e "    \033[33mReq_Proc_Time\033[0m    Request processing time - time from LB receiving request to sending to target"
    echo -e "    \033[32mELB_Status\033[0m       Load balancer status code (colorized)"
    echo -e "    \033[36mTarget_Proc_Time\033[0m Target processing time - time from LB sending request to target starting response"
    echo -e "    \033[35mTarget_Status\033[0m    Target application status code - what the backend actually returned (colorized)"
    echo -e "    \033[34mReceived_Bytes\033[0m   Request size in bytes"
    echo -e "    \033[91mClient_IP\033[0m        Source IP address (colorized)"
    echo -e "    \033[92mUser_Agent\033[0m       Browser/client user agent (truncated, colorized)"
    echo ""
    echo -e "\033[33mSTATUS COLORS:\033[0m"
    echo -e "    \033[32m\033[1m200/201/204\033[0m Success responses"
    echo -e "    \033[34m304\033[0m         Not modified"
    echo -e "    \033[33m401/403\033[0m     Authentication/authorization errors"
    echo -e "    \033[31m\033[1m4xx/5xx\033[0m     Other client/server errors"
    echo ""
    echo -e "\033[33mEXAMPLES:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m/burn\033[0m \033[35m60\033[0m                   # Show /burn requests from prod (last 60 minutes)"
    echo -e "    \033[32m$0\033[0m \033[36m/cart\033[0m \033[35m30\033[0m \033[31m--env\033[0m \033[33mstaging\033[0m     # Show /cart requests from staging (last 30 min)"
    echo -e "    \033[32m$0\033[0m \033[36m/pay\033[0m \033[35m15\033[0m \033[31m--fresh\033[0m            # Show /pay requests, force fresh download (15 min)"
    echo -e "    \033[32m$0\033[0m \033[36m/notifications\033[0m \033[35m360\033[0m \033[31m--env\033[0m \033[34mdev\033[0m \033[31m--fresh\033[0m  # Dev environment, fresh data (6 hours)"
    echo ""
    echo -e "\033[33mENVIRONMENTS:\033[0m"
    echo -e "    \033[32mprod\033[0m     - Production logs (default)"
    echo -e "    \033[33mstaging\033[0m  - Staging environment logs"  
    echo -e "    \033[34mdev\033[0m      - Development environment logs"
    echo ""
    echo -e "\033[33mNOTES:\033[0m"
    echo "    - Requires AWS CLI configured with S3 access"
    echo "    - Uses local cache by default for faster repeated queries"
    echo "    - Times automatically converted from UTC to local timezone"
    echo "    - Results sorted chronologically"
    echo "    - Rainbow headers and colorized output for easy reading"
    echo ""
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Parse arguments
ENDPOINT="$1"
MINUTES_BACK="$2"
ENV="prod"
USE_FRESH=false

shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV="$2"
            shift 2
            ;;
        --fresh)
            USE_FRESH=true
            shift
            ;;
        *)
            echo "Error: Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$ENDPOINT" ] || [ -z "$MINUTES_BACK" ]; then
    echo "Error: Missing required arguments"
    show_help
    exit 1
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

MINUTES_AGO=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y-%m-%dT%H:%M:%S')
TODAY=$(date -u '+%Y/%m/%d')
LOCAL_TZ=$(date +%Z)

if [ "$USE_FRESH" = false ]; then
    # Cache mode (default)
    NEED_UPDATE=false
    
    if [ ! -f "$CACHE_FILE" ]; then
        echo "📥 Creating cache file: $CACHE_FILE"
        NEED_UPDATE=true
    else
        # Check if cache covers the requested time range
        CACHE_AGE_SECONDS=$((($(date +%s) - $(stat -c %Y "$CACHE_FILE"))))
        REQUESTED_SECONDS=$((MINUTES_BACK * 60))
        
        if [ $CACHE_AGE_SECONDS -gt $REQUESTED_SECONDS ]; then
            echo "📥 Cache too old ($(($CACHE_AGE_SECONDS / 60))min), updating..."
            NEED_UPDATE=true
        else
            echo "📂 Using fresh cache: $CACHE_FILE ($ENV environment)"
        fi
    fi
    
    if [ "$NEED_UPDATE" = true ]; then
        # Get new logs and append/create
        echo "📊 Downloading ALB logs from S3..."
        
        # Filter files by timestamp in filename with minute-level precision
        CUTOFF_TIME=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y%m%d%H%M')
        
        LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ | awk -v cutoff="$CUTOFF_TIME" '{
            # Extract timestamp from filename (e.g., 20250913T1445Z -> 202509131445)
            if (match($4, /[0-9]{8}T[0-9]{4}Z/)) {
                timestamp = substr($4, RSTART, 13)
                file_time = substr(timestamp, 1, 8) substr(timestamp, 10, 4)  # YYYYMMDDHHMM
                if (file_time >= cutoff) print $4
            }
        }')
        
        if [ -z "$LOG_FILES" ]; then
            TOTAL_FILES=0
        else
            TOTAL_FILES=$(echo "$LOG_FILES" | wc -l)
        fi
        echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
        CURRENT=0
        
        echo "$LOG_FILES" | while read -r file; do
            [ -z "$file" ] && continue
            CURRENT=$((CURRENT + 1))
            printf "\r📥 Progress: %d/%d files - %s                    " "$CURRENT" "$TOTAL_FILES" "$(basename "$file")"
            aws s3 cp s3://$S3_BUCKET/$S3_PATH/$TODAY/$file - 2>/dev/null
        done | zcat 2>/dev/null > "$CACHE_FILE"
        echo ""
    fi
    
    echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV\033[0m environment):"
    echo -e "• \033[31mEDT Time\033[0m: Local timestamp"
    echo -e "• \033[33mReq_Proc_Time\033[0m: Request processing time - time from LB receiving request to sending to target"
    echo -e "• \033[32mELB_Status\033[0m: Load balancer status code"
    echo -e "• \033[36mTarget_Proc_Time\033[0m: Target processing time - time from LB sending request to target starting response"
    echo -e "• \033[35mTarget_Status\033[0m: Target application status code - what the backend actually returned"
    echo -e "• \033[34mReceived_Bytes\033[0m: Request size in bytes"
    echo -e "• \033[91mClient_IP\033[0m: Source IP address"
    echo -e "• \033[92mUser_Agent\033[0m: Browser info (truncated)"
    echo -e "Status Colors: \033[32m\033[1m200/201/204\033[0m \033[34m304\033[0m \033[33m401/403\033[0m \033[31m\033[1m4xx/5xx\033[0m"
    echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[33mReq_Proc_Time\033[0m | \033[32mELB_Status\033[0m | \033[36mTarget_Proc_Time\033[0m | \033[35mTarget_Status\033[0m | \033[34mReceived_Bytes\033[0m | \033[91mClient_IP\033[0m | \033[92mUser_Agent\033[0m"
    echo "--------------------------------------------------------------------------------------------------------"
    
    awk -v start="$MINUTES_AGO" '$2 >= start' "$CACHE_FILE" | grep "$ENDPOINT" | \
    awk -F'"' '{
      time = substr($1, index($1, " ") + 1)
      utc_time = substr(time, 1, 19)
      
      cmd = "date -d \"" utc_time " UTC\" \"+%H:%M:%S\""
      cmd | getline local_time
      close(cmd)
      
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
      
      # Color IP addresses
      ip_color = salmon client_ip reset
      
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
      
      printf "%s | %s | %s | %s | %s | %s | %s | %s\n", local_time, req_proc_time, elb_color, time_color, target_status_color, purple received_bytes reset, ip_color, green user_agent reset
    }' | sort
else
    # Fresh mode (force S3 download)
    echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV\033[0m environment, \033[35mfresh data\033[0m):"
    echo "📊 Downloading fresh ALB logs from S3..."
    
    # Filter files by timestamp in filename with minute-level precision
    CUTOFF_TIME=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y%m%d%H%M')
    
    LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ | awk -v cutoff="$CUTOFF_TIME" '{
        # Extract timestamp from filename (e.g., 20250913T1445Z -> 202509131445)
        if (match($4, /[0-9]{8}T[0-9]{4}Z/)) {
            timestamp = substr($4, RSTART, 13)
            file_time = substr(timestamp, 1, 8) substr(timestamp, 10, 4)  # YYYYMMDDHHMM
            if (file_time >= cutoff) print $4
        }
    }')
    
    if [ -z "$LOG_FILES" ]; then
        TOTAL_FILES=0
    else
        TOTAL_FILES=$(echo "$LOG_FILES" | wc -l)
    fi
    echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
    
    if [ "$TOTAL_FILES" -eq 0 ]; then
        echo "⚠️  No recent log files found. Most recent files are from:"
        aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ | tail -3 | awk '{print "   " $1 " " $2 " " $4}'
        echo ""
        exit 0
    fi
    
    echo -e "• \033[31mEDT Time\033[0m: Local timestamp"
    echo -e "• \033[33mReq_Proc_Time\033[0m: Request processing time - time from LB receiving request to sending to target"
    echo -e "• \033[32mELB_Status\033[0m: Load balancer status code"
    echo -e "• \033[36mTarget_Proc_Time\033[0m: Target processing time - time from LB sending request to target starting response"
    echo -e "• \033[35mTarget_Status\033[0m: Target application status code - what the backend actually returned"
    echo -e "• \033[34mReceived_Bytes\033[0m: Request size in bytes"
    echo -e "• \033[91mClient_IP\033[0m: Source IP address"
    echo -e "• \033[92mUser_Agent\033[0m: Browser info (truncated)"
    echo -e "Status Colors: \033[32m\033[1m200/201/204\033[0m \033[34m304\033[0m \033[33m401/403\033[0m \033[31m\033[1m4xx/5xx\033[0m"
    echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[33mReq_Proc_Time\033[0m | \033[32mELB_Status\033[0m | \033[36mTarget_Proc_Time\033[0m | \033[35mTarget_Status\033[0m | \033[34mReceived_Bytes\033[0m | \033[91mClient_IP\033[0m | \033[92mUser_Agent\033[0m"
    echo "--------------------------------------------------------------------------------------------------------"
    
    CURRENT=0
    echo "$LOG_FILES" | while read -r file; do
        [ -z "$file" ] && continue
        CURRENT=$((CURRENT + 1))
        echo "📥 Downloading $CURRENT/$TOTAL_FILES: $file" >&2
        aws s3 cp s3://$S3_BUCKET/$S3_PATH/$TODAY/$file - 2>/dev/null
    done | zcat 2>/dev/null | awk -v start="$MINUTES_AGO" '$2 >= start' | grep "$ENDPOINT" | \
    awk -F'"' '{
      time = substr($1, index($1, " ") + 1)
      utc_time = substr(time, 1, 19)
      
      cmd = "date -d \"" utc_time " UTC\" \"+%H:%M:%S\""
      cmd | getline local_time
      close(cmd)
      
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
      
      # Color IP addresses
      ip_color = salmon client_ip reset
      
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
      
      printf "%s | %s | %s | %s | %s | %s | %s | %s\n", local_time, req_proc_time, elb_color, time_color, target_status_color, purple received_bytes reset, ip_color, green user_agent reset
    }' | sort
    
    echo "" >&2
    echo "✅ Processing complete" >&2
fi
