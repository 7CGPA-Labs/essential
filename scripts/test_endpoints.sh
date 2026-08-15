#!/bin/bash
# Kingdom AI Server — Endpoint Verification Test Suite
# Usage: bash scripts/test_endpoints.sh [host] [port]
# Example: bash scripts/test_endpoints.sh localhost 8080

HOST=${1:-localhost}
PORT=${2:-8080}
BASE="http://$HOST:$PORT"
PASS=0
FAIL=0

# Helper functions
check() {
  if [ $? -eq 0 ]; then
    echo "✅ PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local response="$1"
  local expected="$2"
  if [[ "$response" == *"$expected"* ]]; then
    return 0
  else
    return 1
  fi
}

echo "Testing Kingdom AI Server at $BASE"
echo "------------------------------------------------"

# 1. Health check: GET /health
echo "Running Test 1: Health check"
RES=$(curl -s $BASE/health)
assert_contains "$RES" "ok"
check "GET /health"

# 2. Models list: GET /v1/models
echo "Running Test 2: Models list"
RES=$(curl -s $BASE/v1/models)
assert_contains "$RES" "data"
check "GET /v1/models"

# 3. Chat completion (non-streaming): POST /v1/chat/completions
echo "Running Test 3: Chat completion (non-streaming)"
RES=$(curl -s -X POST $BASE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-1.5b","messages":[{"role":"user","content":"test"}],"stream":false}')
assert_contains "$RES" "content"
check "POST /v1/chat/completions (non-streaming)"

# 4. Chat completion (streaming SSE): POST /v1/chat/completions with stream:true
echo "Running Test 4: Chat completion (streaming)"
RES=$(curl -s -X POST $BASE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-1.5b","messages":[{"role":"user","content":"test"}],"stream":true}')
assert_contains "$RES" "data:"
check "POST /v1/chat/completions (streaming)"

# 5. Fast autocomplete: POST /v1/completions
echo "Running Test 5: Fast autocomplete"
RES=$(curl -s -X POST $BASE/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-code-128m","prompt":"def test():","max_tokens":10}')
assert_contains "$RES" "text"
check "POST /v1/completions"

# 6. Embeddings: POST /v1/embeddings
echo "Running Test 6: Embeddings"
RES=$(curl -s -X POST $BASE/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"bge-small-en-v1.5","input":"test string"}')
assert_contains "$RES" "embedding"
check "POST /v1/embeddings"

# 7. Invalid endpoint 404: GET /v1/invalid
echo "Running Test 7: Invalid endpoint"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/v1/invalid)
if [ "$HTTP_STATUS" -eq 404 ]; then
  check "GET /v1/invalid returns 404"
else
  (exit 1)
  check "GET /v1/invalid returns 404"
fi

echo "------------------------------------------------"
echo "Summary: $PASS Passed, $FAIL Failed"
exit $FAIL
