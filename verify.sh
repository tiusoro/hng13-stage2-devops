#!/bin/bash
set -e

# Configuration
NGINX_URL="http://44.192.99.207:8080/version"
BLUE_CHAOS_URL="http://44.192.99.207:8081/chaos"
TIMEOUT=10
RETRIES=20
EXPECTED_POOL="blue"
EXPECTED_RELEASE="blue-release-1"

# Function to check response
check_response() {
    local url=$1
    local expected_pool=$2
    local expected_release=$3
    local response
    local status
    local app_pool
    local release_id

    response=$(curl -s -i -m $TIMEOUT "$url")
    status=$(echo "$response" | head -n1 | grep -o "[0-9]\{3\}")
    app_pool=$(echo "$response" | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    release_id=$(echo "$response" | grep -i "X-Release-Id" | awk '{print $2}' | tr -d '\r')

    if [ "$status" != "200" ]; then
        echo "Error: Expected status 200, got $status"
        exit 1
    fi
    if [ "$app_pool" != "$expected_pool" ]; then
        echo "Error: Expected X-App-Pool $expected_pool, got $app_pool"
        exit 1
    fi
    if [ "$release_id" != "$expected_release" ]; then
        echo "Error: Expected X-Release-Id $expected_release, got $release_id"
        exit 1
    fi
}

# Test 1: Baseline (Blue active)
echo "Testing baseline (Blue active)..."
for i in $(seq 1 5); do
    check_response "$NGINX_URL" "blue" "blue-release-1"
    echo "Baseline request $i: OK"
done

# Test 2: Induce downtime on Blue
echo "Inducing chaos on Blue..."
curl -s -X POST "$BLUE_CHAOS_URL/start?mode=error" -m $TIMEOUT
sleep 2  # Allow failover to occur

# Test 3: Verify failover to Green
echo "Testing failover to Green..."
check_response "$NGINX_URL" "green" "green-release-1"
echo "Failover request: OK"

# Test 4: Stability under failure
echo "Testing stability under failure..."
success_count=0
green_count=0
for i in $(seq 1 $RETRIES); do
    response=$(curl -s -i -m $TIMEOUT "$NGINX_URL")
    status=$(echo "$response" | head -n1 | grep -o "[0-9]\{3\}")
    app_pool=$(echo "$response" | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    
    if [ "$status" != "200" ]; then
        echo "Error: Non-200 status $status on request $i"
        exit 1
    fi
    if [ "$app_pool" = "green" ]; then
        green_count=$((green_count + 1))
    fi
    success_count=$((success_count + 1))
    echo "Stability request $i: OK (Pool: $app_pool)"
done

# Verify ≥95% Green responses
green_percent=$((green_count * 100 / RETRIES))
if [ $green_percent -lt 95 ]; then
    echo "Error: Only $green_percent% responses from Green, expected ≥95%"
    exit 1
fi

echo "All tests passed! $success_count/$RETRIES requests successful, $green_percent% from Green."

