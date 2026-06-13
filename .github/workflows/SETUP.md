# Auto-deploy setup (one time)

The workflow `deploy-web.yml` builds Flutter web and deploys it to Vercel on
every push to `main`. It needs 3 GitHub secrets.

## 1. Get a Vercel token
Vercel → top-right avatar → **Account Settings → Tokens** → **Create Token**
(name it e.g. `github-actions`, scope: Full Account) → copy it.
→ this is `VERCEL_TOKEN`.

## 2. Get the org id and project id
In the app folder run once:

```powershell
cd C:\Users\user\sigma_social_app
npx vercel link
```
Pick the existing **sigma-social-app** project. This creates
`.vercel/project.json`. Open it:

```powershell
type .vercel\project.json
```
You'll see:
```json
{ "orgId": "team_xxx...", "projectId": "prj_xxx..." }
```
→ `orgId` is `VERCEL_ORG_ID`, `projectId` is `VERCEL_PROJECT_ID`.

## 3. Add the secrets to GitHub
GitHub repo → **Settings → Secrets and variables → Actions → New repository
secret**. Add all three:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

## 4. Stop Vercel from trying to build Flutter itself
Because the workflow uploads the already-built `build/web`, Vercel must NOT try
to build the repo on its own (it doesn't know Flutter and would fail).

Vercel → project **sigma-social-app** → **Settings → Git** → **Disconnect**
the GitHub repo. From now on only GitHub Actions deploys.

(Optional: Settings → Build & Output → Framework Preset = "Other", build
command empty — only matters if Git stays connected.)

## Done
Push to `main` → check the repo's **Actions** tab → the job builds + deploys →
https://sigma-social-app.vercel.app/ updates automatically.
You can also trigger it manually: Actions tab → "Deploy web to Vercel" → Run
workflow.
