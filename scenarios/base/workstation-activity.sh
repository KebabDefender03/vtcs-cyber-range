#!/bin/bash
# ============================================================================
# Workstation Activity Simulator
# ============================================================================
# Simulates realistic user activity on the workstation container.
# This generates network traffic and application logs for blue team analysis.
# ============================================================================

set -euo pipefail

# Configuration
WEBAPP_URL="http://webapp"
DB_HOST="database"
DB_USER="dvwa"
DB_PASS="dvwa"
DB_NAME="dvwa"

# Activity intervals (in seconds)
MIN_INTERVAL=10
MAX_INTERVAL=30

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Initialize
log_info "🔄 Workstation Activity Simulator started"
log_info "   Webapp: $WEBAPP_URL"
log_info "   Database: $DB_HOST"
echo ""

# Activity functions
activity_web_browse() {
    log_info "🌐 Browsing webapp..."
    curl -s -A "Mozilla/5.0 (X11; Linux x86_64)" "$WEBAPP_URL/" > /dev/null 2>&1 || true
    curl -s "$WEBAPP_URL/index.php" > /dev/null 2>&1 || true
}

activity_login_attempt() {
    log_info "🔐 Attempting login..."
    curl -s -X POST "$WEBAPP_URL/login.php" \
        -d "username=admin&password=password&user_token=dummy" \
        > /dev/null 2>&1 || true
}

activity_sql_injection_vulnerable() {
    log_info "🔍 Accessing vulnerable pages..."
    curl -s "$WEBAPP_URL/vulnerabilities/sqli/" > /dev/null 2>&1 || true
    curl -s "$WEBAPP_URL/vulnerabilities/sqli_blind/" > /dev/null 2>&1 || true
}

activity_xss_page() {
    log_info "📄 Viewing user profile (XSS vulnerable)..."
    curl -s "$WEBAPP_URL/vulnerabilities/xss_r/" > /dev/null 2>&1 || true
}

activity_admin_panel() {
    log_info "⚙️  Accessing admin panel..."
    curl -s "$WEBAPP_URL/admin.php" > /dev/null 2>&1 || true
}

activity_db_query() {
    log_info "📊 Running database query..."
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "SELECT id, user, email FROM users LIMIT 5;" \
        > /dev/null 2>&1 || true
}

activity_file_upload() {
    log_info "📁 File operations..."
    touch /tmp/workstation_activity_$RANDOM.txt
    rm -f /tmp/workstation_activity_*.txt
}

activity_network_check() {
    log_info "🔗 Network connectivity check..."
    ping -c 1 webapp > /dev/null 2>&1 || true
    ping -c 1 database > /dev/null 2>&1 || true
}

# Main activity loop
random_activity() {
    activities=(
        activity_web_browse
        activity_login_attempt
        activity_sql_injection_vulnerable
        activity_xss_page
        activity_admin_panel
        activity_db_query
        activity_file_upload
        activity_network_check
    )
    
    # Select random activity
    selected=$((RANDOM % ${#activities[@]}))
    ${activities[$selected]}
}

# Run activities indefinitely
while true; do
    random_activity
    
    # Random sleep between activities
    sleep_time=$((RANDOM % (MAX_INTERVAL - MIN_INTERVAL) + MIN_INTERVAL))
    log_info "⏳ Next activity in ${sleep_time}s..."
    echo ""
    sleep "$sleep_time"
done
