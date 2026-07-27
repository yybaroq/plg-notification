# Runbook

## Daily cadence
- **11:00 GMT+8** — Anycross workflow runs the scoring SQL and posts the 📊 digest
  text to "TiDB Bots". This is the data transport.
- **11:15 GMT+8** — `plg-digest-crm-check` reads the *same-day* 11:00 digest,
  enriches, writes the Bitable row, posts the 🔍 card. (Moved from 09:00 on
  2026-07-24 so the card always reflects the fresh digest.)

The card note always states the digest timestamp used.

## Editing the scoring / digest
See `workflow/anycross_workflow.md`. Short version: preview → click node → 「编辑」
→ edit SQL via CodeMirror `cmView.view.dispatch` → 「完成」→「调试」(three green +
test message) →「发布」.

## Editing the enrichment / card
Edit the `plg-digest-crm-check` scheduled task prompt
(`automation/plg-digest-crm-check.md` is the mirror). Tool approvals are stored on
the task after the first run; if you add a new connector, "Run now" once to
pre-approve so future runs don't stall on a permission prompt.

## NexusCRM token
~1h lifetime, no refresh token. On `needs_auth` the task degrades gracefully (posts
the card without the CRM layer, notes it, DMs Yan). To restore, run the connector's
auth helper in a terminal where Chrome is signed in to NexusCRM, then re-run.

## Feishu webhook send
`lark_run_command 'api POST <hook-url> --data "<single-line JSON>"'`.
- `--data @file` only accepts a **host relative path** — inline the JSON instead.
- Avoid literal single quotes in the content (shell-escaping pain).
- Sending as the user via `lark_send_message` to a group needs the
  `im:message.send_as_user` scope (not granted) — that's why everything goes
  through the webhook.

## Known traps
- **Bitable batch-create returns null-ish jq on success** — verify via
  `record-search`, never blind-retry (double-inserts).
- **Owner source**: always NexusCRM Account/Opp owner. Reo's `crm_owner` can be
  stale (Trickle showed Qing Liu in Reo; actual Nexus owner is Kenneth Lee,
  corrected 2026-07-23 — an earlier note here said Kevin Liu, also stale).
- **GROUP_CONCAT truncation**: the `SET_VAR(group_concat_max_len=4096)` hint on the
  outer SELECT is required; without it the 10-row list truncates ~1024 chars.
- **HubSpot rate limits** frequently — source emails from NexusCRM Lead.
- Old test messages from the webhook bot **cannot be deleted** programmatically.

## Reconciliation flags the task raises
- Active customer appearing in P0/P1 (e.g. Anteraja) → suggests exclusion.
- Reo "ready to buy" on a win-back → reactivation candidate, but it is an INTENT
  tag (web/research activity), not product usage — never treat it as a live POC.
  (Kissflow lesson 2026-07-24: 3 dormant 2023-2025 starter clusters + lingering
  poc plan were misread as "reopened POC". Only fresh QPS reopens a win-back.)
- Lead status vs category mismatch (e.g. Trickle Lead = "Open Opportunity" but
  account shows no opp) → surfaced for the owner to check.
- **Domain mismatch → existing customer misread as net-new (DigiPlus, 2026-07-24):**
  a tenant's login/signup domain can differ from its CRM Account website/legal
  name (tenant `tbu.net` vs Account website `digiplus.com.ph`, legal name
  "AB Leisure Exponent Inc", owner Andy Hsu, 16 opps incl. an open renewal in
  Negotiation + a -$2.5M FY27Q1 ARR change = churn risk). Website-LIKE and
  Name-LIKE both miss, so it fell into net-new. Fix (in the task Step 3a +
  Step 7): if a domain has no Account hit, bridge via the `@domain` Leads'
  Company / ConvertedAccountId and re-query Account; and a domain with any
  Lead Status IN ('Open Opportunity','Converted') can NEVER be net-new.

## Upstream feeds the enrichment task also reads (added 2026-07-27)

| Feed | Where | Used for |
|---|---|---|
| 📊 PLG Daily Digest | group "TiDB Bots" `oc_e31cc48f07e15c78d8f544068284d69d` | the Top-10 list (data transport) |
| APAC New Tenant Monitor | group `oc_f9e7a1c219d663d4f3e6bc0e12ff8d98`, query "New non-individual tenant" | 🆕 new-signup section (Step 1b) |
| APAC Tenants Monitor Daily Summary | group `oc_a3d2252841c435991c57ea521aa21497` | 🎯 target-account map + the only view of raw scoring inputs (Step 3d) |

⚠️ The Tenants Monitor Daily Summary is posted **manually and irregularly** (only
two existed as of 2026-07-27: Jul 14 and Jul 21). Anything built on it inherits
that staleness — the task prints its as-of date and marks it stale past 10 days.
Automating it on the digest cadence is an open ask.

## Known traps (continued)

- **Feishu webhook needs the message envelope.** `--data @file` where the file is
  the bare card object fails with `code 19024 "Key Words Not Found"` — a
  misleading error that looks like the bot's keyword filter. The payload must be
  `{"msg_type":"interactive","card":{ …config/header/elements… }}`. (Note: unlike
  the older note above, `--data @file` **does** work — it needs a path relative to
  the outputs dir. Inlining the JSON is no longer required.)
- **Off-cycle digests are invisible to a once-a-day reader (Bytek, 2026-07-27).**
  The workflow sometimes posts extra digests (debug runs, re-runs after a scoring
  change). Bytek entered the Top 10 at 60/P1 on the **14:35** off-cycle digest of
  2026-07-24, was never in any 11:00 digest, and so never reached the Bitable at
  all — it showed on that afternoon's cards but not in the table, which is exactly
  how it was noticed. Fix: Step 1 now reads *every* digest since the previous run
  and reports non-recurring entrants in an "⏱️ Seen between runs" block. Never
  write an off-cycle score into 分数/级 — it is stale by definition.
- **Second domain-mismatch case (sytidba.com → MEGAHARD LIMITED, 2026-07-27).**
  Same shape as DigiPlus: login domain `sytidba.com`, CRM Account "MEGAHARD
  LIMITED" (`001RC00001GBvMDYA1`, website megahardlimited.com, owner Andy Hsu,
  20+ opps incl. Megahard MSP $740K launched). Only the lead-company bridge finds
  it. Treat the bridge as the norm, not the exception, for gaming/platform
  accounts using per-brand login domains.
- **A stale select option or a guessed score corrupts the history table.** 级 only
  has P0/P1 options and 状态 only 未处理; writing anything else returns
  `api_error not_found`. For rows with no current score (new tenants, off-cycle
  entrants, P2-demoted rows) omit the field entirely rather than coercing a value.

## Routing

**All actionable PLG rows go to Kenneth Lee** (Yan, 2026-07-27) — Net-new,
Account-no-opp, Win-back, new tenants, off-cycle entrants. Partner/Verify and
Active-customer rows stay unassigned; Open-opp rows show the Nexus Owner as AE.
The upstream `sales_owner` field in the Tenants Monitor summary still points at
kevinliu@ / sree.v@ / rashi.khemka@ — that mapping is **legacy** and must never
reach the SDR Owner column. Fixing it upstream is an open ask.
