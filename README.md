# NAAC Point-5 Data Collection & AI Summary Portal

A React/TypeScript application built on the Sites vinext starter. Cloudflare D1 stores records and R2 preserves original evidence. Separate panels cover Annexures 5.1–5.13 (5.9 has course and seminar panels), assessment, grievance redressal, and gender equality.

## Source mapping

The supplied Word files were read individually. Annexures 5.1, 5.3, 5.4, 5.6, and 5.7 retain the original column labels. Notable fields include broader subject area, flipped-learning support, seminar-report/PPT preservation, concept implementation, paid/unpaid internship status, previous/present grades, and student/faculty signature evidence. Other annexures are explicitly marked as based on the written requirements because no original templates were provided. Signature fields require an uploaded signed image/document; typing a name is not treated as a signature.

## Run locally

Node 22.13+ is required. Run `npm ci`, `npm run db:generate`, apply migrations to local D1, then `npm run dev`. Preview authorization uses trusted identity headers only; there is no production authentication bypass. The public shell includes an explicit session-only demo containing fictional data. Demo records never enter the database and file uploads are disabled there.

## Private deployment and initial administrator

Deploy with Sites using `.openai/hosting.json`. Set `ADMIN_EMAIL` to the exact email of the intended first administrator in the server environment. The user must sign in through the hosting dispatcher. An exact match provisions administrator membership; all other accounts must be added through Administration. Never accept identity headers from a directly exposed untrusted proxy. Private hosting access remains owner-only until its access policy is deliberately changed. Adding an application user does not change the hosting access policy.

Configure `OPENAI_API_KEY` and `OPENAI_MODEL` on the server to enable optional AI summaries. Do not place secrets in `NEXT_PUBLIC_*` variables or source control. The Responses API implementation follows https://developers.openai.com/api/docs/guides/text and requests structured sections with record IDs. `store:false` is set. Count-based summaries do not call an AI service. AI reports require human verification; valid source IDs do not establish semantic accuracy.

## Workflow

Save a draft, upload its original evidence, and submit. Submitted records become immutable until returned for correction. Each submission preserves a version snapshot and its evidence metadata. Evidence downloads and all write/review operations enforce server-side membership and department/owner permissions. Coordinators verify evidence and approve departmental records; administrators give final approval. Report snapshots preserve source data independently of later corrections. Report edits never alter submissions.

Expected responses means one collection slot per panel, department, and academic year, not a promised number of individual respondents. Each panel can contain multiple records. Counts represent activity records, not deduplicated students. No real institutional data is seeded.

CSV and Excel export current filtered records. PDF and Word export the report with draft/approval status and source IDs. Browser Print is available. Database metadata backup excludes original R2 bytes; download evidence separately for a complete backup.

## Data architecture

The prototype uses a shared submissions table with panel-specific validated JSON, plus relational users, departments, academic years, evidence, immutable submission revisions, coordinator reviews, report snapshots, and audit logs. This intentionally differs from a separate table per activity; the schema preserves exact heterogeneous annexure labels. It can be normalized further without changing the forms. Sample data is in `lib/demo.ts`.

## Verification

`npm run build` compiles the Cloudflare-compatible site. `npx tsc --noEmit` checks types. Tests cover panel-source mapping and report counts/scope; integration checks verify anonymous access rejection and data lifecycle with local D1/R2. Evidence files are downloaded as attachments with MIME sniffing disabled. File size is limited to 20 MB. Production operations should additionally configure institutional retention, object-store backups, malware scanning, and periodic access reviews.

## Mechanical Engineering access (GitHub Pages / Supabase)

The sole owner identity is preserved in `naac_owner`. Only the owner can view
submitted responses, history, reports, summaries, exports, and the full roster.
RPC authorization and database/storage RLS enforce these restrictions.

Migration `202609190006_mechanical_disclaimer.sql` removes the student approval
requirement. Any verified Google account can immediately open the forms. A disclaimer
at the beginning asks only Mechanical Engineering students to submit; department
eligibility is self-declared, not verified by the application. New records are still
stored under Mechanical Engineering. Legacy approval flags do not control access.

Students can save their own drafts, attach evidence, and resubmit returned forms.
Submitted responses remain private to the owner. Existing records are preserved;
the institutional gender-equality panel remains owner-only. Administration lists
portal accounts without approval or revocation controls.

There is no 100-student application cap. Google OAuth audience settings and Supabase
plan quotas are separate from application enrollment limits. Run
`tests/mechanical-access.sql` through the Supabase database query CLI for rollback-only
checks of immediate access, draft isolation, owner privacy, and privilege restrictions.
