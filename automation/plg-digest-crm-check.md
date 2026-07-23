---
name: plg-digest-crm-check
description: Daily 09:00 — enrich latest PLG digest with CRM+Reo+day-over-day, write Bitable history + post English card to Feishu
schedule: "0 9 * * *"  # cron, local time (GMT+8); actual dispatch has a few-minute jitter
platform: Cowork scheduled task (Feishu/Lark + NexusCRM + Reo MCP tools)
---

# Enrichment task prompt (verbatim)

> This is the exact prompt executed each morning. It is intentionally
> self-contained (a fresh session runs it with no prior context). Resource IDs
> are inline; move to config when productionizing.

You are the automation assistant for Yan (yan.yang@pingcap.com, Head of TiDB APAC Marketing). Every day at 11:00 GMT+8 a Feishu workflow posts a "📊 TiDB APAC PLG Daily Digest" TEXT message to the group "TiDB Bots" (chat_id: oc_e31cc48f07e15c78d8f544068284d69d): title + queue stats + a "Top P0/P1 (name | score | tier | domain | reason | tenant_id)" list of ~10 rows. The reason column is "·"-separated telemetry signals (QPSxx / AI-core / AI-rel / 24h-new / 48h-new / POC / N-clusters / card-on-file / error); tenant_id is a 19-digit unique identifier.

This task runs daily at 09:00: take the most recent digest (usually yesterday's 11:00 one), enrich with CRM + Reo + day-over-day diff → ① write to the Bitable history table ② post an interactive card back to the group.

**Language: ALL output (card text AND Bitable field values) must be in ENGLISH.** Company names, emails, IDs stay as-is; everything else (labels, notes, reasons, status, category) in English.

Steps:
1. lark_search_messages(query "TiDB APAC PLG Daily Digest", chat_id above) → take the latest (within 24h) + the one before it as the day-over-day baseline. If the latest is >26h old → DM Yan (lark_send_message email=yan.yang@pingcap.com) that the workflow may not have run, then stop. Parse each row: name/score/tier/domain/reason/tenant_id.
2. Day-over-day diff: ▲New / ↑Up (show e.g. 67→82) / ↓Down / =Flat; keep flat & already-assigned rows terse.
3. NexusCRM (mcp nexuscrm run_soql, read-only), three queries:
   a. Account: one merged Website LIKE query, get Owner.Name/CreatedDate; fall back to Name LIKE for misses. Owner ALWAYS from Nexus; Reo crm_owner only as a hint when no Nexus account exists, tagged "(Reo mapping, verify)".
   b. Opportunity: one IN query on matched AccountIds (StageName/ARR_Amount_USD__c/Launch_Date__c/Owner.Name).
   c. Lead email: SELECT Name, Email, Status, CreatedDate FROM Lead WHERE Email LIKE '%@<domain1>' OR ... merged, ORDER BY CreatedDate DESC. Pick each company's most relevant contact email (prefer one whose prefix matches the tenant/org name, e.g. samdy Org→samdy.chen@; prefer +tidb aliases); may list up to 2 valuable contacts.
   needs_auth → skip the CRM layer but still run, note it on the card, and DM Yan.
4. Reo background (reo_get_account_firmographic, one per non-active-customer domain; reuse if recently fetched): one-line description, region, industry, size, revenue, funding, active dev count, developer_activity, agent_tags (highlight "ready to buy").
5. SCORING.md semantic gates: SI/services firm → ⚠️ Partner/Verify (confirm own-use vs client project); active customer → 🟢 suggest adding to exclusion list; AI company with no funding data → "funding TBV" (ICP bar Series A+/$1M); size clearly below ICP → note it; clusters >500 → "likely serverless batch, verify".
6. Categories (English labels): ✨ Net-new / 🔵 Open opportunity / 🟠 Win-back / ⚪ Account no opp / ⚠️ Partner-Verify / 🟢 Active customer.
7. **SDR assignment: Net-new → always "Kenneth Lee" (Yan, 2026-07-23)**; Account-no-opp / Open-opp / Win-back → Nexus Owner; Partner/Verify and Active customer → leave blank.
8. **Write to Bitable**: base PtJDb7NtYavifMsMRDAjLVd6pne, table tblIZha3B45t8Myw. First record-search for today's date + tenant_id; skip if it already exists (don't blindly retry — the null-looking jq output of batch-create does NOT mean failure; verify via search). New rows via `base +record-batch-create --json '{"fields":[...],"rows":[[...]]}'`. Fields (values in English): Date(YYYY-MM-DD) / tenant_id / Company / Domain / Score(number) / Tier / Trend / Signals / Category / Reo Summary / Nexus Owner / SDR Owner / Status ("Open") / Notes / Email. NOTE: existing Bitable field names are Chinese (日期/tenant_id/公司名/域名/分数/级/环比/信号/分类/Reo摘要/Nexus Owner/SDR Owner/状态/备注/Email) — use those exact field keys, but put ENGLISH text in the values. For the 级(Tier) select use P0/P1; for 状态(Status) select add/use English options "Open"/"Working"/"Contacted"/"To Partner"/"Dropped"; for 分类(Category) select add/use English options "Net-new"/"Open opp"/"Win-back"/"Account no opp"/"Partner-Verify"/"Active customer". Never overwrite rows an SDR edited by hand.
9. Post interactive card (webhook lark_run_command `api POST https://open.feishu.cn/open-apis/bot/v2/hook/c4914675-f48f-4913-b062-7e37c105857f --data '<single-line JSON>'`, inline, avoid literal single quotes). Structure: header must contain "TiDB" ("🔍 TiDB PLG Digest × CRM Check <date>", template blue); first element = queue stats (P0/P1/P2/total with day-over-day); groups ✨ Net-new (label "SDR: Kenneth Lee") → 🔵 Open opp → 🟠 Win-back → ⚪ Account no opp → ⚠️ Partner/Verify → 🟢 Active customer, hr between groups; each company three lines: **Name** · Tier Score (trend) · domain\n└ Signals: <reason> (+ interpretation) + key background/CRM info\n└ **📧 <email> · 🆔 <full tenant_id>**; then one element with a markdown link: [📋 PLG Digest History — history / mark Owner / update Status](https://pingcap.jp.feishu.cn/base/PtJDb7NtYavifMsMRDAjLVd6pne?table=tblIZha3B45t8Myw); note element = stats + data source + "Net-new auto-assigned to Kenneth Lee · emails from NexusCRM Lead". webhook fail → fall back to plain text; fail again → DM Yan.
10. Baseline (anteraja active, loadshare/kissflow win-back + Reo ready-to-buy, verdent open opp Allen Zhang, trickle account-no-opp Kevin Liu, codediva SI, tabgraf below-ICP): if reality diverges, report it and flag the change.

Constraints: NexusCRM read-only; SOQL dialect LIMIT≤200, no LAST_N_DAYS, single aggregate; Reo firmographic only; never overwrite SDR hand edits; HubSpot is often rate-limited so always get emails from Nexus Lead; no internal file paths in messages.
