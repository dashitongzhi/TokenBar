#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/verify_minimax_ccswitch_fallback_audit.sh"
"$ROOT_DIR/script/verify_ccswitch_database.sh"
"$ROOT_DIR/script/verify_json_document_store.sh"
"$ROOT_DIR/script/verify_provider_status_severity.sh"
"$ROOT_DIR/script/verify_local_api_provider_health_quotas.sh"
"$ROOT_DIR/script/verify_local_api_application.sh"
"$ROOT_DIR/script/verify_smart_routing_production_stats.sh"
"$ROOT_DIR/script/verify_smart_routing_cost_metrics.sh"
"$ROOT_DIR/script/verify_provider_model_catalog_endpoint_policy.sh"
"$ROOT_DIR/script/verify_workspace_budget_periods.sh"
ruby "$ROOT_DIR/script/verify_offline_policy_monthly_budget.rb"
