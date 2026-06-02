#!/usr/bin/env bash
# Negative tests: each of these MUST fail to render (the chart enforces a safety
# invariant). If `helm template` succeeds for any of them, the guard regressed.
set -uo pipefail

CHART="charts/hermes-agent"
rc=0

assert_rejected() {
  local desc="$1"; shift
  if helm template rel "${CHART}" "$@" >/dev/null 2>&1; then
    echo "FAIL (expected rejection, but it rendered): ${desc}"
    rc=1
  else
    echo "ok  (correctly rejected): ${desc}"
  fi
}

assert_rejected "persistence.enabled + replicaCount>1" \
  --set persistence.enabled=true --set replicaCount=2
assert_rejected "ingress.enabled without hosts" \
  --set ingress.enabled=true
assert_rejected "dashboard.insecure without acknowledgement" \
  --set dashboard.enabled=true --set dashboard.insecure=true
assert_rejected "strategy RollingUpdate with persistence (RWO)" \
  --set persistence.enabled=true --set strategy.type=RollingUpdate

if [ "${rc}" -eq 0 ]; then
  echo "All negative tests passed (all invariants enforced)."
fi
exit "${rc}"
