# Releasing

Use scripts/release.sh locally. Requirements:
- git configured for signed tags (your YubiKey/GPG available locally)
- gpg installed
- dpkg-dev (for dpkg-scanpackages)
- optional: gh (GitHub CLI) if you want `gh release` integration

Example:

```bash
# build and publish release (creates tag, tarball, deb, apt tree, GitHub Release, and pushes apt to gh-pages)
./scripts/release.sh 1.2.0 release-notes.md
```

Notes:
- The script creates a GPG-signed annotated tag and signs the tarball locally with your key.
- The APT repo produced is a static tree suitable for publishing to GitHub Pages (gh-pages branch). Distribute your GPG public key to clients to verify Release files.