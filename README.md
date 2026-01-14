# paulmillr/backup

Backup of all my relevant projects in a single signed file.

Mirrors:

- https://github.com/paulmillr/backup
- https://gitlab.com/paulmillr/backup
- https://codeberg.org/paulmillr/backup

## Excluded projects

Test vectors & some dotfiles are excluded (>100MB git file limit), clone manually:

```sh
git clone git@github.com:paulmillr/acvp-vectors.git
git clone git@github.com:paulmillr/eth-vectors.git
git clone git@github.com:paulmillr/qr-code-vectors.git
git clone git@github.com:paulmillr/noble-hashes-vectors.git
git clone git@github.com:paulmillr/post-quantum-vectors.git

git clone git@github.com:paulmillr/dotfiles-vsix.git
```

## Usage

```sh
# Verify checksums
cat shasum.txt
gpg --verify shasum.txt.asc

# Calculate checksums, sign
rm shasum.txt shasum.txt.asc
shasum -a 256 *.xz* > shasum.txt
gpg --detach-sign --armor --sign shasum.txt

## Archives
## --------

# Verify, unpack into separate directory
title='2026.01.14'
tar -xf $title.tar.xz

# Create archive
node list-clonable-repos.js
# clone ...
XZ_OPT=-9 tar -Jcvf "$title.tar.xz" "$title"
```
