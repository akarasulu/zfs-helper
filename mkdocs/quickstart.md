# GH-Repos Quickstart

Use this guide to reset your fork and prepare it for a brand-new project.

## 1. Fork the Repository

1. Open the upstream repository on GitHub.
2. Click **Fork** and select the destination account or organization.

## 2. Run the Preparation Script

> ⚠️ Review scripts before piping them to `bash`.

```bash
curl -sSL https://raw.githubusercontent.com/<your-account>/gh-repos/main/prepare-template.sh | \
  bash -s -- git@github.com:<your-account>/gh-repos.git
```

What the script does:

- Clones your fork into a clean working directory.
- Replaces MkDocs source files with placeholder content.
- Removes the generated `docs/` output, including the previous APT repository.
- Rebuilds the site from the placeholder documentation.
- Lists your local GPG private keys so you can export one to `keys/apt-repo-pubkey.asc` and `docs/apt/apt-repo-pubkey.asc`.

You can pass an optional second argument to name the clone directory explicitly:

```bash
bash prepare-template.sh https://github.com/<your-account>/gh-repos.git my-company-repo
```

## 3. Customize the Template

- Replace each placeholder page in `mkdocs/` with project-specific content.
- Add, remove, or tweak packages in `pkgs/` as required.
- Regenerate docs with `./scripts/mkdocs.sh` and rebuild the APT repository with `./scripts/mkrepo.sh`.

## 4. Commit and Push

```bash
cd <clone-directory>
git status
git add .
git commit -m "Prepare template for <project-name>"
git push origin main
```

Your fork is now ready for customization and deployment. Iterate on documentation, automation, and packages as your project evolves.
