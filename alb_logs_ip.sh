#!/bin/bash

# Configuration file
CONFIG_FILE="./alb_logs.conf"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi
source "$CONFIG_FILE"

show_help() {
    echo -e "\033[1m\033[36mALB Log Analysis Tool\033[0m"
    echo ""
    echo -e "\033[33mUSAGE:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m<endpoint>\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--fresh\033[0m]"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[36m<ip_address>\033[0m \033[35m<endpoint1>\033[0m [\033[35mendpoint2\033[0m ...] [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--fresh\033[0m]"
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
    echo -e "    \033[31m--ip\033[0m         Trace all requests from specific IP across endpoints"
    echo -e "    \033[31m--env\033[0m        Environment: \033[32mprod\033[0m (default), \033[33mstaging\033[0m, \033[34mdev\033[0m"
    echo -e "    \033[31m--fresh\033[0m      Force fresh download from S3 (bypasses cache)"
    echo ""
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Parse arguments
IP_MODE=false
TARGET_IP=""
ENDPOINTS=()
ENDPOINT=""
MINUTES_BACK=""
ENV="$DEFAULT_ENV"
USE_FRESH=false

if [ "$1" = "--ip" ]; then
    IP_MODE=true
    TARGET_IP="$2"
    shift 2
    # Collect all endpoints
    while [[ $# -gt 0 ]] && [[ "$1" != "--env" ]] && [[ "$1" != "--fresh" ]]; do
        ENDPOINTS+=("$1")
        shift
    done
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

if [ "$IP_MODE" = true ]; then
    if [ -z "$TARGET_IP" ] || [ ${#ENDPOINTS[@]} -eq 0 ]; then
        echo "Error: IP mode requires IP address and at least one endpoint"
        show_help
        exit 1
    fi
    MINUTES_BACK=60  # Default to 60 minutes for IP tracing
else
    if [ -z "$ENDPOINT" ] || [ -z "$MINUTES_BACK" ]; then
        echo "Error: Missing required arguments"
        show_help
        exit 1
    fi
fi

# Set environment-specific variables
case $ENV in
    prod)
        S3_BUCKET="$PROD_S3_BUCKET"
        S3_PATH="$PROD_S3_PATH"
        ENV_NAME="prod"
        ;;
    staging)
        S3_BUCKET="$STAGING_S3_BUCKET"
        S3_PATH="$STAGING_S3_PATH"
        ENV_NAME="staging"
        ;;
    dev)
        S3_BUCKET="$DEV_S3_BUCKET"
        S3_PATH="$DEV_S3_PATH"
        ENV_NAME="dev"
        ;;
    *)
        echo "Error: Invalid environment '$ENV'. Use: prod, staging, dev"
        exit 1
        ;;
esac

# Create cache directory
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/alb_logs_${ENV}_cache.log"

# Calculate time range
MINUTES_AGO=$(date -d "$MINUTES_BACK minutes ago" '+%Y-%m-%dT%H:%M:%S')
TODAY=$(date '+%Y/%m/%d')
CUTOFF_TIME=$(date -d "$MINUTES_BACK minutes ago" '+%Y%m%dT%H%M')
LOCAL_TZ=$(date '+%Z')

# Download and process logs
if [ "$USE_FRESH" = true ] || [ ! -f "$CACHE_FILE" ]; then
    echo "📥 Creating cache file: $CACHE_FILE"
    echo "📊 Downloading ALB logs from S3..."
    
    LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/$TODAY/ 2>/dev/null | \
        awk -v cutoff="$CUTOFF_TIME" '{
            if ($4 ~ /\.log\.gz$/) {
                match($4, /_([0-9]{8}T[0-9]{4})Z_/, arr)
                if (arr[1] >= cutoff) print $4
            }
        }')
    
    if [ -z "$LOG_FILES" ]; then
        echo "📁 Found 0 relevant log files (timestamp >= $CUTOFF_TIME)"
    else
        TOTAL_FILES=$(echo "$LOG_FILES" | wc -l)
        if [ $TOTAL_FILES -gt 20 ]; then
            echo "📁 Found $TOTAL_FILES log files, limiting to most recent 20 for performance"
            LOG_FILES=$(echo "$LOG_FILES" | tail -20)
            TOTAL_FILES=20
        else
            echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
        fi
        
        CURRENT=0
        echo "$LOG_FILES" | while read -r file; do
            [ -z "$file" ] && continue
            CURRENT=$((CURRENT + 1))
            echo "📥 Downloading $CURRENT/$TOTAL_FILES: $(basename "$file")"
            aws s3 cp s3://$S3_BUCKET/$S3_PATH/$TODAY/$file - 2>/dev/null
        done | zcat 2>/dev/null > "$CACHE_FILE"
        echo ""
    fi
    
    if [ "$IP_MODE" = true ]; then
        echo -e "🔍 Tracing IP \033[91m$TARGET_IP\033[0m across endpoints: \033[36m${ENDPOINTS[*]}\033[0m (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV_NAME\033[0m environment):"
    else
        echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV_NAME\033[0m environment):"
    fi
    
    echo -e "• \033[31mEDT Time\033[0m: Local timestamp"
    echo -e "• \033[33mReq_Proc_Time\033[0m: Request processing time"
    echo -e "• \033[32mELB_Status\033[0m: Load balancer status code"
    echo -e "• \033[36mTarget_Proc_Time\033[0m: Target processing time"
    echo -e "• \033[93mTarget_Status\033[0m: Target application status code"
    echo -e "• \033[35mReceived_Bytes\033[0m: Request size in bytes"
    echo -e "• \033[91mClient_IP\033[0m: Source IP address"
    if [ "$IP_MODE" = true ]; then
        echo -e "• \033[96mEndpoint\033[0m: API endpoint accessed"
    fi
    echo -e "• \033[92mUser_Agent\033[0m: Browser info (truncated)"
    echo -e "Status Colors: \033[32m\033[1m200/201/204\033[0m \033[34m304\033[0m \033[33m401/403\033[0m \033[31m\033[1m4xx/5xx\033[0m"
    
    if [ "$IP_MODE" = true ]; then
        echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[33mReq_Proc_Time\033[0m | \033[32mELB_Status\033[0m | \033[36mTarget_Proc_Time\033[0m | \033[93mTarget_Status\033[0m | \033[35mReceived_Bytes\033[0m | \033[91mClient_IP\033[0m | \033[96mEndpoint\033[0m | \033[92mUser_Agent\033[0m"
    else
        echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[33mReq_Proc_Time\033[0m | \033[32mELB_Status\033[0m | \033[36mTarget_Proc_Time\033[0m | \033[93mTarget_Status\033[0m | \033[35mReceived_Bytes\033[0m | \033[91mClient_IP\033[0m | \033[92mUser_Agent\033[0m"
    fi
    echo "--------------------------------------------------------------------------------------------------------"
    
    if [ "$IP_MODE" = true ]; then
        # IP tracing mode - search for IP across multiple endpoints
        ENDPOINT_PATTERN=""
        for ep in "${ENDPOINTS[@]}"; do
            if [ -z "$ENDPOINT_PATTERN" ]; then
                ENDPOINT_PATTERN="$ep"
            else
                ENDPOINT_PATTERN="$ENDPOINT_PATTERN|$ep"
            fi
        done
        
        awk -v start="$MINUTES_AGO" -v target_ip="$TARGET_IP" -v pattern="$ENDPOINT_PATTERN" '$2 >= start' "$CACHE_FILE" | \
        awk -v target_ip="$TARGET_IP" -v pattern="$ENDPOINT_PATTERN" '{
            split($4, ip_parts, ":")
            client_ip = ip_parts[1]
            if (client_ip == target_ip && $0 ~ pattern) print $0
        }' | \
        awk -F'"' '{
            time = substr($1, index($1, " ") + 1)
            utc_time = substr(time, 1, 19)
            
            cmd = "date -d \"" utc_time " UTC\" \"+%H:%M:%S\""
            cmd | getline local_time
            close(cmd)
            
            split($1, fields, " ")
            req_proc_time = fields[6]
            target_proc_time = fields[7]
            elb_status = fields[9]
            target_status = fields[10] 
            received_bytes = fields[11]
            client_ip = fields[4]
            split(client_ip, ip_parts, ":")
            client_ip = ip_parts[1]
            
            # Extract endpoint from request
            request = $2
            split(request, req_parts, " ")
            if (length(req_parts) >= 2) {
                endpoint = req_parts[2]
                split(endpoint, path_parts, "?")
                endpoint = path_parts[1]
            } else {
                endpoint = "unknown"
            }
            
            user_agent = $4
            if (length(user_agent) > 40) {
                user_agent = substr(user_agent, 1, 37) "..."
            }
            
            # Color status codes
            if (elb_status == "200" || elb_status == "201" || elb_status == "204") {
                elb_color = "\033[32m\033[1m" elb_status "\033[0m"
            } else if (elb_status == "304") {
                elb_color = "\033[34m" elb_status "\033[0m"
            } else if (elb_status == "401" || elb_status == "403") {
                elb_color = "\033[33m" elb_status "\033[0m"
            } else if (elb_status >= "400") {
                elb_color = "\033[31m\033[1m" elb_status "\033[0m"
            } else {
                elb_color = elb_status
            }
            
            if (target_status == "200" || target_status == "201" || target_status == "204") {
                target_color = "\033[32m\033[1m" target_status "\033[0m"
            } else if (target_status == "304") {
                target_color = "\033[34m" target_status "\033[0m"
            } else if (target_status == "401" || target_status == "403") {
                target_color = "\033[33m" target_status "\033[0m"
            } else if (target_status >= "400") {
                target_color = "\033[31m\033[1m" target_status "\033[0m"
            } else {
                target_color = target_status
            }
            
            printf "%s | %s | %s | %s | %s | %s | %s | %s | %s\n", "\033[31m" local_time "\033[0m", "\033[33m" req_proc_time "\033[0m", elb_color, "\033[36m" target_proc_time "\033[0m", target_color, "\033[35m" received_bytes "\033[0m", "\033[91m" client_ip "\033[0m", "\033[96m" endpoint "\033[0m", "\033[92m" user_agent "\033[0m"
        }' | sort
    else
        # Regular endpoint mode
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
          elb_status = fields[9]
          target_status = fields[10] 
          received_bytes = fields[11]
          client_ip = fields[4]
          split(client_ip, ip_parts, ":")
          client_ip = ip_parts[1]
          
          user_agent = $4
          if (length(user_agent) > 50) {
            user_agent = substr(user_agent, 1, 47) "..."
          }
          
          # Color status codes
          if (elb_status == "200" || elb_status == "201" || elb_status == "204") {
            elb_color = "\033[32m\033[1m" elb_status "\033[0m"
          } else if (elb_status == "304") {
            elb_color = "\033[34m" elb_status "\033[0m"
          } else if (elb_status == "401" || elb_status == "403") {
            elb_color = "\033[33m" elb_status "\033[0m"
          } else if (elb_status >= "400") {
            elb_color = "\033[31m\033[1m" elb_status "\033[0m"
          } else {
            elb_color = elb_status
          }
          
          if (target_status == "200" || target_status == "201" || target_status == "204") {
            target_color = "\033[32m\033[1m" target_status "\033[0m"
          } else if (target_status == "304") {
            target_color = "\033[34m" target_status "\033[0m"
          } else if (target_status == "401" || target_status == "403") {
            target_color = "\033[33m" target_status "\033[0m"
          } else if (target_status >= "400") {
            target_color = "\033[31m\033[1m" target_status "\033[0m"
          } else {
            target_color = target_status
          }
          
          printf "%s | %s | %s | %s | %s | %s | %s | %s\n", "\033[31m" local_time "\033[0m", "\033[33m" req_proc_time "\033[0m", elb_color, "\033[36m" target_proc_time "\033[0m", target_color, "\033[35m" received_bytes "\033[0m", "\033[91m" client_ip "\033[0m", "\033[92m" user_agent "\033[0m"
        }' | sort
    fi
fi

echo ""
echo "✅ Processing complete"
