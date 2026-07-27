# PLG Digest Scoring — Change Request

**Date:** 2026-07-27
**From:** Yan Yang (Head of APAC Marketing, ex-Japan)
**For:** owner of the APAC Tenants Monitor / PLG digest scoring job (谢玉洁 / 刘昉)
**Status:** proposal — Phase 1 is low-risk and requested first

---

## So what

**~15 new non-individual APAC tenants sign up every weekday. None of them can reach the daily digest's Top 10 — ever — regardless of company quality.** The score is a pure function of accumulated usage, so a company that signed up yesterday is mathematically locked out during exactly the window when outreach converts.

Workato (Series E, $100M–250M revenue, iPaaS — a textbook ICP account) signed up on 2026-07-17 and has never once appeared in the digest. Meanwhile Definition's Org, running at QPS 0.029, has appeared every single day.

The visible symptom is that the digest card reads almost identically day after day. That is not a rendering bug and not a quiet market — it is the intended behaviour of the current formula.

---

## Evidence

From the 2026-07-21 *APAC Tenants Monitor Daily Summary* (the only place the raw scoring inputs are exposed):

| Tenant | clusters | QPS | credit card | plan | score |
|---|---:|---:|---|---|---:|
| PT. Tri Adi Bersama | 9 | 114.3 | no | on_demand | **82** |
| KickAss Products | 4 | 106.6 | yes | on_demand | **70** |
| Verdent AI | 1548 | N/A | no | on_demand | **65** |
| CUPPASOFT LTD | 4 | 0.829 | no | on_demand | **57** |
| Definition's Org | 3 | **0.029** | no | on_demand | **57** |
| Coupang / Navi / Bizgital | 1 | 0 | no | poc | **40** |
| SpaceKey / Airwallex | 1 | 0 | yes | on_demand | **35** |
| Games24x7 | 0 | 0 | no | poc | **30** |

**Top-10 cutoff on 2026-07-27: 57 points.**

A day-1 tenant has 0–1 clusters and 0 QPS. Its ceiling is **40**. It cannot clear 57. There is no firmographic term in the formula at all — revenue, funding stage, vertical and employee count carry **zero** weight, even though the New Tenant Monitor bot already resolves all four via AI enrichment with "high" confidence.

Note also that Coupang, Airwallex, Navi and Games24x7 — all on the HubSpot target-account list — score 30–40 and are therefore invisible in the same way.

The 2026-07-24 recency gate helped in one direction (it demoted dormant tenants) but did not change the candidate pool, so the vacated slots were refilled from the same accumulated-usage cohort.

---

## Phase 1 — reserved slots (requested first)

**Do not re-tune the weights.** Change the *selection*, not the score. The digest emits two lists instead of one:

| Block | Size | Ranking |
|---|---|---|
| Top by score | 7 | existing formula, unchanged |
| New signups ≤72h | 5 | non-individual only, ranked by ICP fit (revenue → funding stage → vertical) |

Rationale: guarantees daily turnover, needs no re-calibration of a live score, and cannot regress the existing P0/P1 semantics. Deduplicate — if a tenant qualifies for both, keep it in the score block.

Filter for the new-signup block: exclude free-mail domains (gmail, outlook, qq, 163, ntesmail, duck.com …) and `AI Confidence Level: low` rows with no resolved company name. Report those as a tally.

**Effort: one additional SELECT plus a UNION in the digest query. No scoring change.**

---

## Phase 2 — add the missing terms to the score

Only if Phase 1 proves insufficient. All inputs below already exist in the pipeline.

**A. Firmographic / ICP block (cap +25)**

| Input | Points |
|---|---:|
| Annual revenue ≥ $50M | +15 |
| Annual revenue $10M–$50M | +10 |
| Annual revenue $1M–$10M | +5 |
| < $1M / unknown | 0 |
| Funding Series C+ / IPO | +10 |
| Series A / B | +7 |
| Seed | +3 |
| Bootstrapped / unknown | 0 |
| ICP vertical (fintech, gaming, logistics, e-comm, AI infra, data-heavy SaaS) | +5 |

**B. New-signup recency boost (decaying, non-individual domains only)**

| Age since signup | Points |
|---|---:|
| ≤ 24h | +20 |
| ≤ 48h | +15 |
| ≤ 72h | +10 |
| ≤ 7d | +5 |
| > 7d | 0 |

**C. Target-account match: +10 flat** — already computed by the monitor job (`match=portal_id / email_domain / official_website`), simply not fed into the score.

**Guard:** cap the combined A+B+C bonus so a zero-usage tenant cannot outrank a live production account. Suggested ceiling — bonus block may not lift a tenant above 65 on its own; anything ≥70 must be earned by real usage.

Worked example: Workato at signup would score 40 (base) + 10 (revenue $100–250M) + 10 (Series E) + 5 (enterprise automation) + 20 (≤24h) = **85, capped to 65** → clears the 57 bar and surfaces on day 1, without displacing the genuine QPS-114 accounts above it.

---

## Two side issues found while diagnosing

1. **Owner routing is stale.** The monitor summary still shows `sales_owner=kevinliu@pingcap.com`, `sree.v@pingcap.com`, `rashi.khemka@pingcap.com` on PLG tenants. As of 2026-07-27 **all PLG leads route to Kenneth Lee.** Please update the upstream mapping; the downstream digest-enrichment job has already been changed.

2. **The Tenants Monitor Daily Summary is not daily.** Only two exist (Jul 14 and Jul 21) and both were posted by hand. It is currently the only exposed source of the HubSpot target-account map, so anything built on it inherits that staleness. Worth automating on the same cadence as the digest.

---

## Ask

- Confirm whether Phase 1 can ship this week.
- Confirm the owner-routing fix (Kenneth Lee for all PLG).
- Confirm whether the Tenants Monitor summary can be automated daily.
