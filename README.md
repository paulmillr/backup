# paulmillr/backup

Backup of all my relevant projects in a single signed file.

Mirrors:

* https://github.com/paulmillr/backup
* https://gitlab.com/paulmillr/backup
* https://codeberg.org/paulmillr/backup

## checksums

    shasum -a 256 *

```
cb1e2ff979567c3f4282f9ebcc39522f81683cacacdda3dd51daaa597804ef40  2024.07.03-noble-scure.tar.xz
89125022829985deefec784726cbb9b94a227d75f4a9684b421fe74a29056146  2024.07.03-noble-scure.tar.xz.sig
8eeb95bd3c9a744b5f01d79eabf87b031000e01e50b7b04a544042132bb91a80  2024.07.03.tar.xz
0b25ed634c39219252c1d76ca58d6956389d38846e2d5529751d5a3fe87c541e  2024.07.03.tar.xz.sig
```

`old`-prefixed archives contain archived, unmaintained projects.

## Verify integrity, unpack

```sh
title='2024.07.03'
# verify integrity of the archive: check GPG signature
gpg --verify $title.tar.xz.sig $title.tar.xz
# unpack into separate directory
tar -xf $title.tar.xz
```

## Create archive

Clone repos:

    node list-clonable-repos.js

Create and sign .tar.xz:

```sh
title='2024.07.03'
XZ_OPT=-9 tar -Jcvf "$title.tar.xz" "$title" # create .tar.xz
gpg --detach-sign --sign ${title}.tar.xz # sign archive
```