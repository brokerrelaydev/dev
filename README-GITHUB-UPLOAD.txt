BrokerRelay GitHub-ready upgrade v4 — NO LOCAL TERMINAL REQUIRED

1. Open https://github.com/arunapadmal/BrokerRelay/tree/development
2. GitHub > Add file > Upload files. Drag in the FILES from this extracted ZIP, preserving the directory paths listed below. GitHub's browser uploader may not preserve folder paths if files are selected individually; upload folders together or navigate into each parent folder and create the named file via Add file > Create new file.

CORE dashboard fix files:
  .github/workflows/prepare-csv-dashboard-fix.yml
  scripts/apply_csv_dashboard_fix.py

IMPORTANT: these two files DO NOT immediately overwrite your dashboard. Once committed on development, GitHub Actions should create a separate feature branch automatically. Go to Actions > Prepare BrokerRelay CSV Dashboard Fix; open the run and check its summary for a compare link. Review and merge the feature branch into development only after verifying the changes. Netlify then needs to deploy development.

If Actions does not run: GitHub > Settings > Actions > General (check repository workflow permissions). If GitHub disallows Actions or token write access, do not try to work around it by granting broad unrelated permissions; instead use GitHub's web editor to patch existing code manually.

OPTIONAL birthday CSV upgrade (if not already uploaded):
  app/clients/import/page.tsx
  supabase/migrations/20261115000000_import_historical_clients_birthday.sql
  docs/example_clients_with_birthday.csv

Upload app/clients/import/page.tsx only if you have not already deployed the birthday v3 page. The SQL file is included FOR SOURCE CONTROL; copying it to GitHub will NOT execute it in Supabase. Only run the SQL in brokerrelay-dev if birthday v3 has not already been applied. Do not execute twice unless reviewed.

The workflow does not alter Supabase, deploy Netlify, or publish a mobile app.

WHY: Your previous zip contained only a Python patch and was intended to run in a locally checked-out Git repository. The current workflow instead checks out the development branch on GitHub and patches it on the GitHub runner, then produces full updated source files in a review branch.
