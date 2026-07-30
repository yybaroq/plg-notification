---
name: plg-digest-crm-check
description: Weekday 11:15 — enrich the same-day 11:00 PLG digest with CRM+Reo+day-over-day, PLUS a 🆕 new-tenant (72h) section and 🎯 target-account tagging; write Bitable history + post English card to Feishu (Mon–Fri)
schedule: "15 11 * * 1-5"  # cron, local time (GMT+8); actual dispatch has a few-minute jitter
platform: Cowork scheduled task (Feishu/Lark + NexusCRM + Reo MCP tools)
---

# Enrichment task prompt (verbatim)

> This is the exact prompt executed each weekday. It is intentionally
> self-contained (a fresh session runs it with no prior context). Resource IDs
> are inline; move to config when productionizing. Stable rules live in
> PLG-Digest-Enrichment-Rules.md (workspace folder); a mirror of that doc is
> appended at the bottom of this file.
>
> Change log:
> - **2026-07-30** — Added **R17 staleness/repeat-row handling**: STEP 6 now
>   computes consecutive-appearance streaks for actionable rows from Bitable
>   history; Day 3–6 unchanged rows compress to one ⏳ line, Day ≥7 demote to a
>   "Stale — awaiting SDR action" rollup with Monday TL;DR escalation. STEP 7
>   prefixes 备注 with [STALE Day N]; STEP 9 reports stale-row count.
> - **2026-07-29** — R16 new-tenant ICP filter (below-bar/TBV signups with no
>   priority signal are tallied, not listed/written). Rules externalized to
>   PLG-Digest-Enrichment-Rules.md.
> - **2026-07-27** — Step 1 reads *every* digest since the last run (Bytek miss);
>   added new-tenant section + target-account tagging; all actionable rows route
>   to Kenneth Lee; anti-fabrication branches for every named field.
> - **2026-07-24** — FACTUALITY RULE, CHURN-RISK RULE, domain-mismatch
>   lead-company bridge, NET-NEW GUARD, NAME RESOLUTION.

You enrich the daily TiDB APAC PLG digest for Yan (yan.yang@pingcap.com). Runs weekdays 11:15 GMT+8. A watchdog (plg-card-watchdog, 11:50) checks that you posted a card — but do not rely on it: alert early yourself.

**STEP 0 — SETUP + EARLY ALERTS (do this FIRST, before any analysis):**
a. Read PLG-Digest-Enrichment-Rules.md in the workspace folder — ALL rules (factuality R2, no-fabrication R3, bridge R5, churn R6, net-new guard R7, names R8, routing R9, gates R10, Bitable R11, card R12, target accounts R13, baselines R14, constraints R15, new-tenant ICP filter R16, staleness/repeat-row R17) live there and BIND this run. If the file is missing/unreadable → DM Yan (`im +messages-send --user-id ou_ed2c2b9891991642be5283f26f704cef --as bot` via lark_run_command; the lark_send_message email param is broken on lark-cli 1.0.48) and STOP.
b. Nexus auth check: run_soql `SELECT Id FROM Lead LIMIT 1`. On needs_auth attempt hands-free reconnect ONCE: Glob '**/nexus_connect.mjs' (rpm/plugin_* dirs, .remote-plugins) → `node <path> auth` via workspace bash, ~90s timeout → retry the check once. Still failing → continue WITHOUT the CRM layer under rule R7's outage guard, and note it prominently on the card. Never loop auth more than once.
c. If ANY tool in this step errors unexpectedly, DM Yan with the error before attempting to continue. Dying silently is the worst outcome (it happened 2026-07-28).

**STEP 1 — DIGESTS.** lark_search_messages "TiDB APAC PLG Daily Digest" in chat oc_e31cc48f07e15c78d8f544068284d69d. Newest digest = today's list; newest from the previous calendar day = baseline; every digest strictly between = source of OFF-CYCLE ENTRANTS (tenants not in today's list — the Bytek miss, 2026-07-24: an off-cycle debug digest was the only appearance and was never captured). Enrich off-cycle entrants like normal rows, show in "⏱️ Seen between runs", write per R11 (score/tier omitted — stale by definition; historical value in 备注). Absence from today's list → "verify current telemetry" per R2's QPS caveat, never "churned/cooled". Newest digest >26h old → DM Yan, stop. Search itself errors → DM Yan, stop. No baseline → R3.

**STEP 2 — NEW TENANTS (72h; 96h Monday, window anchored to the digest timestamp).** lark_search_messages "New non-individual tenant" in chat oc_f9e7a1c219d663d4f3e6bc0e12ff8d98. Search errors OR returns zero cards of any age → print "🆕 monitor feed unavailable or empty — not checked" + DM Yan (do NOT report "no new signups" — false negative). Filter free-mail + low-confidence-no-name (tally only). Dedupe vs digest rows (keep in digest group, append "(also a new signup <date>)"). ICP read + caveats per R10; list/write gate per R16. Cap 8 listed.

**STEP 3 — CRM (skip whole step under outage guard).** Three merged queries over ALL domains (digest + new tenants + off-cycle): (a) Account via Website LIKE, fallback Name LIKE, then R5 bridge; (b) Opportunity IN on matched AccountIds incl. bridge finds (StageName/ARR_Amount_USD__c/Launch_Date__c/Owner.Name/LastModifiedDate) — apply R6; (c) Lead (Name,Email,Company,Status,ConvertedAccountId,CreatedDate,LeadSource) by email domain, ORDER BY CreatedDate DESC — feeds the bridge; contact pick + missing-email handling per R3/R15.

**STEP 4 — TARGET ACCOUNTS** per R13.

**STEP 5 — REO.** reo_get_account_firmographic per non-active-customer domain. **A failed call = "Reo lookup failed — no firmographic data" and nothing more (R3). Never reuse old cards' descriptors as if fresh.**

**STEP 6 — CLASSIFY + ROUTE** per R7 (guard), R8 (names), R9 (Kenneth-only), R10 (gates). Day-over-day diff: ▲New / ↑Up (67→82) / ↓Down / =Flat; keep flat rows terse. **Then apply R17 staleness:** for each actionable row (✨/⚪/🟠), search the Bitable for its tenant_id across prior dates to compute the consecutive-appearance streak with unchanged 分类; Day 3–6 → compress to one line with "⏳ Day N · lead <Status> <age>" prefix (full detail only if something material changed that day); Day ≥7 → demote to the "⏳ Stale — awaiting SDR action" rollup section; Monday + non-empty rollup → bold escalation line in the TL;DR.

**STEP 7 — WRITE BITABLE** per R11 (dedupe first; separate batch for score-less rows). Stale rows still get rows; prefix 备注 with "[STALE Day N]" per R17.

**STEP 8 — POST CARD** per R12 (msg_type/card envelope!), with R17 section ordering (stale rollup sits after the main groups, before the history link). Webhook fail → plain text; fail again → DM Yan.

**STEP 9 — REPLY** one short paragraph: rows written/skipped, new tenants found/filtered, off-cycle entrants, CRM layer on/off, stale-row count, anomalies (queue jumps, feed silence ≥48h — flag both).

Keep the GitHub mirror (automation/plg-digest-crm-check.md in yybaroq/plg-notification) in sync when this prompt or the rules doc changes.

---

# Rules doc mirror — PLG-Digest-Enrichment-Rules.md (as of 2026-07-30)

## R1. Language
ALL output (card text AND Bitable values) in ENGLISH. Company names, emails, IDs stay as-is.

## R2. FACTUALITY (2026-07-24, Kissflow; amended 2026-07-28, Bytek)
Only state what a signal literally supports.
- `POC` label = billing plan is 'poc' — a STATIC attribute, NOT a live POC. `N-clusters` = static count, may be years old. `旧POC` = confirmed dormant legacy plan.
- Never write "reopened POC" / "dev reopened" / "restarted evaluation" or any event narrative without a corroborating fresh signal. Without one: "legacy PoC plan/clusters — verify recency".
- **QPS caveat (2026-07-28, Bytek incident): `tenant_avg_qps` is a 1-HOUR Prometheus rate and may include non-user traffic (pending IT confirmation of what it counts). QPS > 0 is NOT proof of user activity, and QPS = 0 at digest time is NOT proof of dormancy. Describe it only as "cluster-side query rate (1h window)". Do NOT use it to declare a win-back "reopened" or a tenant "active" — say "cluster-side QPS observed — verify against gateway activity before treating as user usage". Signup recency (24h-new / 48h-new) remains a valid fresh signal.**
- Anything inferred beyond literal signals must be marked "possibly …, verify".

## R3. NEVER FABRICATE
Every field (email, owner, score, tier, signals, trend, Reo data) has an if-missing branch below. Omitting a value is always correct; inventing one never is.
- **Reo call fails or returns nothing → write "Reo lookup failed — no firmographic data" and NOTHING else about that company's size/industry/activity. No dates, no descriptors, no carry-over from old cards presented as fresh (2026-07-27 incident: fabricated Reo dates).**
- No Lead email → "📧 none in Nexus Lead", Bitable Email blank. Never construct an address from a domain.
- Net-new rows have no Nexus Owner → leave blank, no owner label.
- No prior digest → Trend "no baseline"; never invent deltas or mark rows ▲New.
- If data used is from a previous day's verified query (e.g. CRM skipped today), label it with its date ("as of YYYY-MM-DD, not re-verified today") on card and in 备注.

## R4. KNOWN BLIND SPOT (2026-07-27)
The upstream score is accumulated usage only (clusters+QPS+card+AI category), zero firmographic weight; top-10 cutoff ~57, a day-1 tenant caps at ~40 → new signups can never enter the top 10, and the roster is stable by construction. A flat day is the formula working as written — say "structurally stable", point at the new-tenant section, never "market cooled". Fix pending: docs/scoring_change_request_2026-07-27.md + gateway-based admission gate (Bytek doc).

## R5. DOMAIN-MISMATCH BRIDGE (2026-07-24, DigiPlus; again 2026-07-27, MEGAHARD)
Login domain often ≠ CRM Account website/legal name. For ANY tenant with no Website/Name hit: from the Lead query for that domain collect distinct Lead.Company + ConvertedAccountId, re-query Account by those (Name LIKE / direct Id) BEFORE calling it net-new. A bridge match is a REAL account — tag "(matched via lead-company bridge, verify)", use its Nexus Owner, include in the opportunity query. Owner ALWAYS from Nexus; Reo crm_owner only as a hint tagged "(Reo mapping, verify)".

## R6. CHURN-RISK (2026-07-24, DigiPlus)
Negative ARR_Amount_USD__c = PROPOSED reduction, not churn. 🔴 churn-risk ONLY if later stage (Negotiation / Deal Closed) AND LastModifiedDate ≤ ~30d. Prospecting / stale / past Launch_Date = ⚠️ "possible renewal contraction — verify". Always state stage + freshness; never size as % without the ARR base. Closed Lost on a negative-ARR opp is ambiguous — never count as churn unconfirmed.

## R7. NET-NEW GUARD + CRM-OUTAGE GUARD
✨ Net-new ONLY if: no Nexus Account (incl. via R5 bridge) AND no Lead on the domain with Status IN ('Open Opportunity','Converted'). Account resolves → classify by opp state. Open-opp leads but no account after bridge → "⚠️ Verify — existing open-opp leads, confirm account/owner".
**CRM unavailable → nothing may be classified Net-new or Win-back** (the guard's condition is vacuously true). Such rows: "⚠️ Unverified — CRM unavailable", SDR blank, 分类=["Partner/Verify"].

## R8. NAME RESOLUTION (2026-07-24)
Display the best REAL company name: CRM Account Name > New-Tenant-Monitor Company Name > Reo account_name > digest org handle. Real name first, raw handle in parens. Nothing resolves → bare handle + "(unresolved tenant name)". Applies to card and 公司名.

## R9. SDR ROUTING (2026-07-27; SCORING.md §7 is aligned)
All ACTIONABLE rows → "Kenneth Lee": ✨ Net-new, ⚪ Account no opp, 🟠 Win-back, 🆕 new tenants, ⏱️ off-cycle entrants. BLANK SDR: ⚠️ Partner/Verify, 🟢 Active customer, 🔵 Open opp (show Nexus Owner as AE). NEVER Ratna / Kevin Liu / Sree / Rashi — upstream sales_owner is legacy. 🆕/⏱️ are section markers, not categories: category decides SDR. Nexus Owner is a separate factual field — never overwrite with Kenneth.

## R10. SEMANTIC GATES (SCORING.md)
SI/services firm → ⚠️ Partner/Verify (own-use vs client project); active customer → 🟢 + suggest exclusion; AI co with no funding data → "funding TBV" (bar: Series A+/$1M); below-ICP size → note it; clusters >500 → "likely serverless batch, verify". Below size bar + strong behavioural trail (old Engaged lead + sustained activity from a VERIFIED source) → "below ICP on size but behaviour-led — worth a short look"; state which leg the case rests on. ICP read for new tenants — three exclusive branches: Revenue ≥$1M OR ≥Series A → "meets ICP bar"; bootstrapped or <$1M → "below ICP bar"; neither present → "funding TBV". Monitor card vs Reo conflicts on revenue/size/country → name both sources, never silently pick. Clears revenue floor but obviously not a database buyer → "clears revenue floor, weak technical fit".

## R11. BITABLE SPEC
Base `PtJDb7NtYavifMsMRDAjLVd6pne`, table `tblIZha3B45t8Myw`. Dedupe first: record-search digest date + tenant_id; existing → skip (null-ish jq from batch-create ≠ failure — verify by search, never blind-retry). Create via `base +record-batch-create --base-token <t> --table-id <t> --json @<relative-file>.json`. Chinese field keys, ENGLISH values: 日期(YYYY-MM-DD)/tenant_id/公司名/域名/分数(number)/级/环比/信号/分类/Reo摘要/Nexus Owner/SDR Owner/状态/备注/Email. Selects are single-element arrays; ONLY existing options (unknown → api_error not_found): 级=["P0"]/["P1"]; 状态=["未处理"]; 分类=["净新"]/["在途商机"]/["win-back"]/["待认领"]/["Partner/Verify"]/["现役客户"]. Any ⚠️ Verify variant → ["Partner/Verify"] + reason in 备注. P2-demoted digest row → omit 级, note "P2 (demoted)". New-tenant / off-cycle rows: SEPARATE batch-create with 分数 AND 级 OMITTED entirely; 日期 = digest date (dedupe key); signup date / off-cycle timestamp + historical score in 备注 only, prefixed "[NEW TENANT 72h]" / "[OFF-CYCLE]"; 信号 = monitor card verbatim or blank for new tenants, off-cycle reason + timestamp for off-cycle. Never overwrite SDR hand edits.

## R12. CARD SPEC
Webhook `api POST https://open.feishu.cn/open-apis/bot/v2/hook/c4914675-f48f-4913-b062-7e37c105857f --data @<relative-file>.json`. **Payload MUST be {"msg_type":"interactive","card":{...}} — bare card fails 19024 "Key Words Not Found".** Success = ROOT {code:0}; never re-POST in one run. Header contains "TiDB": "🔍 TiDB PLG Digest × CRM Check <date>", blue (orange if degraded). Order: ① bold "📊 vs yesterday" TL;DR (≤2 sentences; flat day → say so + point to new tenants) ② queue stats ③ 🆕 New tenants (last 72h) — header "N signups · M meet ICP bar · K filtered", N counts deduped ones, list caps at 8 ranked meets-ICP→TBV→below ④ hr ⑤ digest groups ✨→🔵→🟠→⚪→⚠️→🟢, hr between, 🎯 prefix + as-of date for target accounts ⑥ ⏱️ Seen between runs (omit if none) ⑦ history link https://pingcap.jp.feishu.cn/base/PtJDb7NtYavifMsMRDAjLVd6pne?table=tblIZha3B45t8Myw ⑧ note = stats + sources + routing line. Rows: **Name** · Tier Score (trend) · domain / └ Signals + interpretation + CRM info / └ **📧 email-or-none · 🆔 full tenant_id**. OWNER-LABEL RULE: owner names shown must equal the per-row Nexus Owner written THIS run. Webhook fail → plain text; fail again → DM Yan.

## R13. TARGET-ACCOUNT MAP (2026-07-27)
Source: latest "APAC Tenants Monitor Daily Summary" card in group `oc_a3d2252841c435991c57ea521aa21497`, its "HubSpot Target Accounts" block. Manual + irregular — always print its date; ≤10d → "🎯 Target Account (as of <date>)"; >10d → append "— stale, re-verify"; none found → omit 🎯, note "map unavailable". Use ONLY for membership; never quote its score/qps/clusters/plan as current. NEVER display its sales_owner (legacy). Secondary: any Nexus Account with an Owner = known/covered. Optional HubSpot lists 19544/19867 if authorized — never block on it.

## R14. BASELINE HINTS (STALE — re-verify against live Nexus; divergence → report + flag)
anteraja = active customer, owner Angelyn Olivia, 🎯 target list · verdent = open opp · trickle = account-no-opp, acct 001RC00001H74fhYAB, Nexus Owner Kenneth Lee (Reo crm_owner stale, ignore) · codediva = SI, two tenants · tabgraf = below-ICP · kissflow = dormant legacy PoC (renewal Closed Lost 2025-08) · loadshare = win-back candidate, verify recency · digiplus (tbu.net) = ACTIVE "AB Leisure Exponent Inc" 001RC000000vX0tYAE, owner Andy Hsu, bridge-only; renewal opp Launched as of 07-27, -$2.5M FY27Q1 change stale at Prospecting = possible contraction NOT churn · wow's Org (sytidba.com) = ACTIVE "MEGAHARD LIMITED" 001RC00001GBvMDYA1, owner Andy Hsu, 20+ opps, bridge-only, never net-new · Bytek (bytek.org, 1372813089209320477) = 4-person Vietnam software studio, Partner/Verify, gateway-inactive since 2026-04-17 pending IT metric confirmation, do NOT work; if it reappears treat as known row · PQ Talent (pqtalent.au) = Melbourne events/talent agency, below ICP, recommend exclusion.

## R17. STALENESS / REPEAT-ROW HANDLING (2026-07-30, CUPPASOFT/Definition Lab repeat fatigue)
The digest's design assumes appear → claimed → disappear; when the "claimed" step stalls, the same actionable rows repeat daily with zero new information and drown out real signals. Fix: track and surface staleness instead of re-printing full detail.
- **Streak tracking:** for every ACTIONABLE row (✨ Net-new, ⚪ Account no opp, 🟠 Win-back), before writing the card, search the Bitable for the tenant_id across prior 日期 values and count consecutive daily appearances with unchanged 分类 (weekends/skipped runs don't break the streak). Today = day N.
- **Day 3–6 unchanged:** keep the row in its group but compress to ONE line and prefix a staleness marker: "⏳ Day N · lead <Status> <age>" (e.g. "⏳ Day 5 · lead OPEN 4.8mo"). Full multi-line detail ONLY if something material changed that day (tier change, QPS anomaly, new lead, CRM change) — the change is then the headline, streak still shown.
- **Day ≥7 unchanged:** demote out of the main groups into a single "⏳ Stale — awaiting SDR action" rollup near the bottom: one line each (name · tier score · day count · lead status+age · SDR). These rows still get Bitable rows per R11 (history continuity), and 备注 gets "[STALE Day N]" prefix.
- **Escalation:** on Mondays, if the stale rollup is non-empty, add a bold escalation line to the TL;DR ("N actionable rows have sat unworked ≥7 days — SDR follow-up needed") so it reaches Yan weekly without daily nagging.
- **Streak resets** when 分类 changes, an Account/Opportunity appears, the tenant leaves the top10 (re-entry starts a new streak; note "returning — last seen <date>" per existing behavior), or the SDR marks the Bitable row 状态 ≠ 未处理.
- **TL;DR priority:** genuinely new movement (new entrants, tier jumps, CRM changes) always leads; "roster flat" phrasing must reference the stale section instead of re-describing stale rows.

## R16. NEW-TENANT ICP FILTER (2026-07-29, Grateful Prints / JoyTree Global)
New-tenant signups that read "below ICP bar" or "funding TBV" AND carry no other priority signal (no target-account match, no notable agent_tag like "ready to buy", no meaningfully large revenue/employee footprint) → tally only. Do NOT list them individually in the card's 🆕 section and do NOT write a Bitable row for them — let them incubate; re-surface only if a fresh signal appears (funding round, revenue disclosure, expansion activity, a Nexus lead converting, etc.). Only list/write new-tenant rows that either meet the ICP bar (Revenue ≥$1M OR ≥Series A) or carry an explicit priority signal despite ambiguous funding data. Card header becomes "N signups · M meet ICP bar/priority · K incubating (filtered)". The free-mail/low-confidence-no-name filter (STEP 2) still applies first and separately.

## R15. CONSTRAINTS
NexusCRM read-only; SOQL LIMIT≤200, no LAST_N_DAYS, single aggregate per SELECT. Reo firmographic only. HubSpot often rate-limited — emails ALWAYS from Nexus Lead. No internal file paths in messages. Free-mail list: gmail/outlook/qq/163/ntesmail/duck.com etc. Lead query includes LeadSource + Status; surface "Engaged"/old Direct-Traffic (real journey) and UNQUALIFIED (check why) when they carry signal. Reo first_activity_date may corroborate a Lead CreatedDate — only when Reo data was ACTUALLY retrieved this run.
