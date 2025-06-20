# paulmillr/backup

Backup of all my relevant projects in a single signed file.

Mirrors:

- https://github.com/paulmillr/backup
- https://gitlab.com/paulmillr/backup
- https://codeberg.org/paulmillr/backup

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
title='2025.06.20'
tar -xf $title.tar.xz

# Create archive
node list-clonable-repos.js
# clone ...
XZ_OPT=-9 tar -Jcvf "$title.tar.xz" "$title"
```
