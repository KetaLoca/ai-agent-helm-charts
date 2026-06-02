#!/usr/bin/env bash
# Negative tests: each case MUST fail to render (a safety invariant is enforced).
# If `helm template` succeeds for any of them, a guard regressed.
set -uo pipefail

rc=0

assert_rejected() {
  local chart="$1" desc="$2"; shift 2
  if helm template rel "${chart}" "$@" >/dev/null 2>&1; then
    echo "FAIL (expected rejection, but it rendered): [${chart}] ${desc}"
    rc=1
  else
    echo "ok  (correctly rejected): [${chart}] ${desc}"
  fi
}

H="charts/hermes-agent"
assert_rejected "$H" "persistence.enabled + replicaCount>1" \
  --set persistence.enabled=true --set replicaCount=2
assert_rejected "$H" "ingress.enabled without hosts" \
  --set ingress.enabled=true
assert_rejected "$H" "dashboard.insecure without acknowledgement" \
  --set dashboard.enabled=true --set dashboard.insecure=true
assert_rejected "$H" "strategy RollingUpdate with persistence (RWO)" \
  --set persistence.enabled=true --set strategy.type=RollingUpdate

O="charts/openclaw-instance"
assert_rejected "$O" "networking.ingress.enabled without hosts" \
  --set networking.ingress.enabled=true

if [ "${rc}" -eq 0 ]; then
  echo "All negative tests passed (all invariants enforced)."
fi
exit "${rc}"
