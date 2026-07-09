# valkey-apt (gh-pages)

This branch is the published static APT repository for
[valkey-apt](https://github.com/phlpdtrt/valkey-apt), served via GitHub
Pages at https://phlpdtrt.github.io/valkey-apt/.

Do not edit this branch by hand - it is maintained entirely by the
`publish` job in `.github/workflows/build.yml` (see `bin/publish-repo.sh`
on `main`). This initial commit only seeds the branch with:

- `.nojekyll` - tells GitHub Pages to serve files as-is (no Jekyll
  processing), which matters for extensionless files like `Release`/
  `InRelease` and dotfiles.
- `public.key` - the OpenPGP public key (binary/dearmored) used to verify
  packages signed with the repo's private key
  (`APT_SIGNING_KEY` GitHub Actions secret on `main`). Fingerprint:
  `A5A2 39DC 5CBD 2E85 AB24  3DC3 77FD 2DDE 5E03 0EA1`.

`dists/` and `pool/` are created on demand by the first real publish run.
