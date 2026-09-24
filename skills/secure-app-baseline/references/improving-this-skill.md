# Improving This Skill

Source repository: https://github.com/CristianGarcia7/aws-security-skill
Skill path in the repo: `skills/secure-app-baseline/`

This skill is public and meant for everyone. Improvements found while using it
should flow back to the repository, but only with the user's explicit approval.

## When to propose an improvement

Propose one at the end of a task when you observed any of these:

- A rule was missing for a real risk you had to handle (new AWS service, new
  attack pattern, new framework).
- A rule was wrong, outdated, or contradicted current AWS documentation.
- A rule was ambiguous and you had to guess.
- A script or asset failed, gave a false positive/negative, or had a bug.
- A reference was missing an example that would have prevented a mistake.

Do not propose cosmetic rewording, personal style preferences, or rules that
only apply to one company, one account, or one project.

## How to propose

1. Finish the user's task first. Never interrupt the main work for this.
2. Ask ONE question, then stop and wait:

   > I found a possible improvement for the `secure-app-baseline` skill:
   > **<one-line summary>**. Why: <one or two lines of evidence>.
   > Do you want me to contribute it to the skill repository? (yes / no)

3. On "no": drop it. Do not ask again for the same improvement in this session.
4. On "yes": continue with the contribution flow below.

## Privacy scrub (mandatory before anything leaves the machine)

The repository is public. Before writing an issue, commit, or PR, remove:

- Account IDs, ARNs with real IDs, instance/SG/VPC/bucket names, hostnames.
- IP addresses (except documentation ranges or generic CIDRs like `0.0.0.0/0`).
- Access keys, tokens, passwords, `.env` values, even partially masked.
- Company, client, project, and people names; costs or incident amounts.
- Source code copied from the user's project. Write a generic example instead.

If the improvement cannot be explained without private data, do not submit it.
Tell the user why.

## Contribution flow

Check the user's access first:

```bash
gh repo view CristianGarcia7/aws-security-skill --json viewerPermission -q .viewerPermission
```

| Access | Action |
|---|---|
| `ADMIN`, `MAINTAIN`, or `WRITE` (maintainer) | Branch, edit, commit, push, open a PR. Do not merge; the maintainer decides. |
| Anything else, `gh` installed and logged in | Fork, branch, edit, open a PR from the fork. |
| No `gh` or not logged in | Give the user the ready-to-paste issue text and the link `https://github.com/CristianGarcia7/aws-security-skill/issues/new`. |

Rules for the change itself:

- Keep `SKILL.md` body under 1000 tokens. Put detail in `references/` or `assets/`.
- Keep assets with placeholders only (`<ACCOUNT_ID>`, `<BUCKET>`, `<REGION>`).
- Bump `metadata.version` in `SKILL.md` (minor for new rules, patch for fixes).
- Use a Conventional Commit message, e.g. `feat(skill): add ECR image scanning rule`.
- PR body: what changed, why (generic evidence), how it was verified.
- Show the user the final diff and PR/issue text before pushing or creating it.

After the PR is merged, the user updates their install with:

```bash
cd ~/aws-security-skill && git pull && ./install.sh
```
