# PLG Daily Digest — Notification Pipeline

Daily PLG (product-led growth) lead notification for TiDB APAC. Scores active
TiDB Cloud tenants from product telemetry, pushes a ranked P0/P1 digest to
Feishu, then enriches it against NexusCRM + Reo and posts an SDR-ready card with
a persistent history table.

Intended home: **`pql_modeling`** repo (this is the notification/delivery layer
that sits on top of the PQL scoring model).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  TiDB: regional_support.apac_active_tenants (product telemetry)│
└───────────────────────────────┬───────────────────────────────┘
                                 │
              ① Anycross workflow  (daily 11:00 GMT+8)
              cron trigger → MySQL scoring SQL → custom-bot webhook
                                 │
                                 ▼
        ┌───────────────────────────────────────────┐
        │  Feishu group "TiDB Bots"                    │
        │  📊 digest text (name|score|tier|domain|     │
        │     reason|tenant_id) — the data transport   │
        └───────────────────────────┬──────────────────┘
                                     │
       ② Cowork scheduled task  (daily 11:15, reads same-day 11:00 digest)
       parse → NexusCRM SOQL (Account/Opp/Lead) → Reo firmographic
       → SCORING.md semantic gates → day-over-day diff
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                  ▼
    ┌───────────────────────────┐      ┌──────────────────────────────┐
    │ Feishu "TiDB Bots"         │      │ Bitable "PLG Digest History"  │
    │ 🔍 interactive card         │      │ append row/day, SDR edits      │
    │ (grouped by account state)  │      │ Owner + Status in place        │
    └───────────────────────────┘      └──────────────────────────────┘
```

Design principle: **the SQL layer only computes what telemetry can express;
semantic judgement (customer exclusion, SI classification, funding gate, owner
routing) lives in the enrichment task where it has CRM / Reo / SCORING context.**

---

## Repo layout

| Path | What it is |
|---|---|
| `sql/plg_daily_digest.sql` | The scoring + digest-text SQL run by the Anycross MySQL node. Source of truth for the PQL telemetry model (Activity/Fit/Urgency → P0/P1/P2). |
| `workflow/anycross_workflow.md` | The 3-node Anycross workflow config (trigger / MySQL / custom-bot) and how to edit it. |
| `automation/plg-digest-crm-check.md` | The daily-11:15 enrichment task prompt (verbatim). Produces the card + writes the Bitable history. |
| `bitable/history_table_schema.md` | Field schema of the "PLG Digest History" table + write/dedupe rules. |
| `docs/scoring_model.md` | The P0/P1/P2 formula reference (act/fit/urg breakdown, trigger reasons). |
| `docs/runbook.md` | Ops: editing the SQL, deploying, token recovery, known traps. |

---

## Scoring model (summary)

`my_score = act + fit + urg`, each computed from tenant telemetry:

| Dimension | Cap | Signals |
|---|---|---|
| Activity | 40 | QPS tier, cluster count (1/3/10 bands), credit card on file |
| Fit | 30 | AI category (ai_core 30 / ai_related 20 / enterprise-domain non-AI 15 / individual 0) |
| Urgency | 30 | 24h/48h new signup × AI category, POC plan (recency-gated), QPS≥50, multi-cluster no-card (recency-gated), error |

Priority is **rule-triggered**, not a pure score threshold (see `sql/` and
`docs/scoring_model.md`). This is the EMEA PQL Signal Model port — **distinct
from** the firmographic PLG formula in `SCORING.md §4b`; they are two legs, mapped
via `SCORING.md §7` (Tier A↔P0/P1, B↔P1, C↔P2).

Each digest row carries a **reason** column exposing the actual signals that
fired (e.g. `QPS491·4-clusters`, `AI-core·POC`).

---

## Live resource IDs (as deployed, 2026-07)

> Kept here for reference; move to env/secrets when the repo goes live. The
> webhook is a group-bound Feishu custom-bot hook, not a broad credential.

| Resource | ID |
|---|---|
| Anycross workflow | `7661478774365522886` (integration `7661478093248285654`) |
| MySQL credential | "TiDB APAC RO" (default DB `information_schema`; table referenced as `regional_support.apac_active_tenants`) |
| Source table | `regional_support.apac_active_tenants` |
| Feishu group | "TiDB Bots" `oc_e31cc48f07e15c78d8f544068284d69d` |
| Custom-bot webhook | `.../bot/v2/hook/c4914675-f48f-4913-b062-7e37c105857f` (keyword filter: message must contain "TiDB") |
| Bitable history | base `PtJDb7NtYavifMsMRDAjLVd6pne`, table `tblIZha3B45t8Myw` |
| Scheduled task | `plg-digest-crm-check` (cron `15 11 * * *`) |

---

## Language state

Card + Bitable values are **English** (as of 2026-07-23). The digest-text SQL
still emits **Chinese** column labels (`队列`, `名称`, `分`, `原因`…) because it is
the machine transport read by the enrichment task, not a human-facing surface.
To fully English-ify the digest, edit the `CONCAT(...)` labels in
`sql/plg_daily_digest.sql` and re-publish the workflow (one-line change; see
`docs/runbook.md`).

---

## Not yet automated / open items

- Active-customer exclusion is applied at the **card layer only** (flag +
  suggestion), not in the SQL. To hard-suppress, maintain an exclusion domain
  list refreshed from CRM and add it to the SQL WHERE.
- Cluster-count is uncapped in scoring → serverless batch creation can inflate
  Urgency (e.g. Verdent 1558 clusters). Consider a cap.
- Emails are sourced from NexusCRM Lead (HubSpot is frequently rate-limited).
- ~~Static signals (poc plan, cluster count) score without any recency check~~
  **Fixed 2026-07-24**: recency gates + dormancy demotion in the SQL (see
  `docs/scoring_model.md`, Kissflow case study). Remaining nice-to-have: per-
  cluster `created_at` in the source table for a "cluster created ≤14d" gate.
