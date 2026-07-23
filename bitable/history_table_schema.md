# Bitable — "PLG Digest History"

Lives inside the SDR-facing base "APAC GTM Signal Queue".

- Base: `PtJDb7NtYavifMsMRDAjLVd6pne`
- Table: `tblIZha3B45t8Myw`
- URL: https://pingcap.jp.feishu.cn/base/PtJDb7NtYavifMsMRDAjLVd6pne?table=tblIZha3B45t8Myw

The daily 09:00 task appends one row per Top-10 entry (deduped by Date +
tenant_id). SDRs edit **SDR Owner** and **Status** in place; the task must never
overwrite hand edits.

## Fields

> Field *names* are Chinese (kept stable so existing views/rows don't break);
> field *values* are written in English as of 2026-07-23.

| Field name (key) | Type | Notes |
|---|---|---|
| `日期` (Date) | text | YYYY-MM-DD |
| `tenant_id` | text | 19-digit unique id from the digest |
| `公司名` (Company) | text | |
| `域名` (Domain) | text | |
| `分数` (Score) | number | |
| `级` (Tier) | select | `P0` / `P1` |
| `环比` (Trend) | text | ▲New / ↑67→82 / ↓ / = |
| `信号` (Signals) | text | reason column from the digest |
| `分类` (Category) | select | Net-new / Open opp / Win-back / Account no opp / Partner-Verify / Active customer |
| `Reo摘要` (Reo Summary) | text | one-line firmographic |
| `Nexus Owner` | text | account owner from NexusCRM |
| `SDR Owner` | text | **SDR-editable**; Net-new auto-set to "Kenneth Lee" |
| `状态` (Status) | select | Open / Working / Contacted / To Partner / Dropped |
| `备注` (Notes) | text | |
| `Email` | text | most relevant contact from NexusCRM Lead |

## lark-cli gotchas (v1.0.48)

- `base +field-create` select options go at the **top level** as
  `"options":[{"name":"…"}]` (not nested under `property`).
- `base +table-create` with a `--fields` payload that fails validation still
  leaves a half-created empty table behind.
- `base +record-batch-create` returns a null-ish jq shape on success — **verify
  via `record-search`, don't blindly retry** (retrying double-inserts).
- Per-row updates: `base +record-upsert --record-id <id> --json '{...}'`
  (batch-update applies one patch to all rows).
- Field/record types must be discriminator strings: `text`, `number`, `select`,
  `datetime`, `checkbox`, … (not integers).
