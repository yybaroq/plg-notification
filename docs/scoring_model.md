# PQL Scoring Model (digest layer)

`my_score = act + fit + urg` (0–100), computed per tenant from
`regional_support.apac_active_tenants`. Priority is **rule-triggered**, not a
simple score cut, so a lead can be P0 on a single decisive signal.

This is the **EMEA PQL Signal Model** port. It is a separate leg from the
firmographic PLG formula in `SCORING.md §4b` (Vertical/BizModel/Funding/
SignupIntent/AIConf). The two are reconciled via `SCORING.md §7`:
Tier A ↔ P0/P1, B ↔ P1, C ↔ P2, D ↔ suppress.

## Inputs (normalized in layer 1)

| Alias | Source column | Meaning |
|---|---|---|
| `cat`  | `entity_ai_category` | `company_ai_core` / `company_ai_related` / `company_non_ai` / `institution_non_ai` / `individual` |
| `qps`  | `tenant_avg_qps` | average QPS |
| `cc`   | `cluster_count` | number of clusters |
| `card` | `has_credit_card` | credit card on file (0/1) |
| `pl`   | `plan` | plan string; `poc` is a strong urgency signal |
| `err`  | `error_message` | non-empty → 1 (CS/risk signal) |
| `n24` / `n48` | `created_at` | signed up within 24h / 48h |
| `ent`  | `email_domain` | corporate (non-freemail) domain |
| `freem`| `email_domain` | known free-mail domain |

## Activity (cap 40)

| Condition | Points |
|---|---|
| QPS ≥ 1 | 25 |
| 0.001 ≤ QPS < 1 | 12 |
| clusters ≥ 1 / ≥ 3 / ≥ 10 | +10 / +8 / +5 (cumulative) |
| credit card on file | +10 |
| QPS ≥ 1 and no card | +5 |

## Fit (cap 30)

| Category | Points |
|---|---|
| company_ai_core | 30 |
| company_ai_related | 20 |
| company_non_ai + enterprise domain | 15 |
| company_non_ai + freemail | 5 |
| company_non_ai (other) | 3 |
| institution_non_ai | 8 |
| individual | 0 |

## Urgency (cap 30)

| Condition | Points |
|---|---|
| 24h-new AND ai_core | 20 |
| 48h-new AND ai_related | 15 |
| plan = poc **AND (QPS ≥ 0.001 OR ≤48h-new)** | 15 |
| QPS ≥ 50 | 15 |
| clusters ≥ 3 AND no card AND not individual **AND QPS ≥ 0.001** | 12 |
| error present | 10 |

## Priority rules

**Dormancy gate (evaluated first, added 2026-07-24):** `QPS < 0.001 AND not
≤48h-new AND no error` → force **P2**, regardless of static score. Static
inventory (old clusters, lingering poc plan, card on file) cannot hold a
P0/P1 slot. Re-entry is automatic the moment the tenant shows QPS again —
that re-entry IS the true "win-back reopened" trigger.

**P0** if any of: `QPS≥50` · `QPS≥10 & ai_core` · `24h-new & ai_core` ·
`POC & (ai_core|ai_related) & (QPS≥0.001 | ≤48h-new)` · `total≥75 & not individual`.

**P1** if any of: `total≥45` · `48h-new & ai_related` · `24h-new & non_ai & enterprise` ·
`clusters≥3 & no card & not individual & QPS≥0.001` · `error`.

Else **P2**.

## Reason column

Each Top-10 row shows the signals that fired, `·`-joined. Mapping
(Chinese label in current digest → meaning):

| Label | Meaning |
|---|---|
| `QPSxx` / `低QPS` | QPS value / sub-1 QPS |
| `AI-core` / `AI-rel` | AI category |
| `24h新注册` / `48h新注册` | signup recency |
| `POC` | plan = poc AND alive (QPS/≤48h) |
| `旧POC` | plan = poc but dormant (legacy PoC leftover) |
| `N集群` | cluster count ≥ 3 |
| `绑卡` | credit card on file |
| `报错` | error message present |

## Known limitations

1. Cluster count is **uncapped** as an input signal, so serverless batch creation
2. can inflate Activity/Urgency (observed: Verdent 1558 clusters). Enrichment layer
3. flags `clusters > 500` as "likely serverless batch, verify"; a hard cap in the
4. SQL is a candidate fix.
5. 2. `tenant_avg_qps` is the only activity field in the source table — there is no
   3. per-cluster creation date, so the recency gates use QPS + tenant signup age.
   4. If per-cluster `created_at` becomes available, prefer "cluster created ≤14d"
   5. as an additional POC-liveness condition.
  
   6. ## Case study: the Kissflow false positive (fixed 2026-07-24)
  
   7. Kissflow dev Org scored 60 → P1 for three straight days on `POC·3集群` with
   8. **zero QPS**: Activity 18 (3 legacy clusters) + Fit 15 + Urgency 27 (lingering
   9. poc plan +15, 3-clusters-no-card +12). All 60 points were static — the three
   10. starter clusters dated from the 2023–2025 PoC and the poc plan was never
   11. reset. Under the gates above it scores 33 and the dormancy rule holds it at
   12. P2 until real QPS returns.
   13. 
