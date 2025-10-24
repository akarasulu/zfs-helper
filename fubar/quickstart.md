# Project Quickstart

Follow this guide after you fork the upstream repository to prepare it for your project.

## 1. Fork the Repository

1. Visit the upstream project on GitHub.
2. Click **Fork** and choose the owner where your template should live.

## 2. Run the Preparation Script

> ⚠️ Always review scripts before piping them to `bash`.

```bash
curl -sSL https://raw.githubusercontent.com/<your-account>/<your-repo-name>/main/prepare-template.sh | \
  bash -s -- git@github.com:<your-account>/<your-repo-name>.git
```

The script performs the following:

- Clones your fork into a fresh directory.
- Replaces MkDocs content with placeholders ready for customization.
- Clears the generated `docs/` output (including the old APT repository layout).
- Rebuilds the site using the placeholder content.
- Prompts you to pick one of your local GPG keys and exports it to `keys/apt-repo-pubkey.asc` and `docs/apt/apt-repo-pubkey.asc`.

You can pass an optional second argument to choose the target directory name:

```bash
bash prepare-template.sh https://github.com/<your-account>/<your-repo-name>.git my-project-docs
```

## 3. Customize the Template

- Replace each placeholder page in `mkdocs/` with real project documentation.
- Add or adjust packages under `pkgs/` as needed.
- Regenerate the docs with `./scripts/mkdocs.sh` and build the APT repo with `./scripts/mkrepo.sh`.

## 4. Commit and Push

```bash
cd <clone-directory>
git status
git add .
git commit -m "Prepare template for <project-name>"
git push origin main
```

Your fork is now ready for project-specific work. Continue updating documentation, packages, and automation as your needs evolve.
