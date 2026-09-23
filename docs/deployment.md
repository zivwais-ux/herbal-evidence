# deployment

_Full deployment guide to be written in a later phase. See docs/decisions.md D-013 for the phase plan._

## Supabase projects

| Env | Project name | Project ref | Region | API URL | Status |
|-----|--------------|-------------|--------|---------|--------|
| dev | `herbal-evidence-dev` | `prfamfzsepxespdncjfk` | `eu-central-1` (Frankfurt) | `https://prfamfzsepxespdncjfk.supabase.co` | created 2026-09-23 |
| production | `herbal-evidence-prod` | — | — | — | not created yet |

Both live in the organization `zivwais-ux's Org` (free plan). See D-014 for why this differs from D-007.

Only public values belong in this table. The publishable key is in the Supabase dashboard (Project Settings → API Keys). The secret key (`SUPABASE_SECRET_KEY`) is never committed; it goes in the Railway backend service variables and a local `backend/.env`.

### Linking the local CLI to the dev project

```sh
npx supabase login
npx supabase link --project-ref prfamfzsepxespdncjfk
npx supabase db push        # apply supabase/migrations/* to the dev project
```
