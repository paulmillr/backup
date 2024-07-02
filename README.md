# Backup of all my projects in a single signed file

```sh
title='2023.02.19'
# verify integrity of the archive: check GPG signature
gpg --verify $title.tar.xz.sig $title.tar.xz
# unpack into separate directory
tar -xf $title.tar.xz
```

Mirrors: https://github.com/paulmillr/backup, https://gitlab.com/paulmillr/backup

## checksums

`old`-prefixed archives contain archived, unmaintained projects.
Created with `shasum -a 256 *`

```
75d2c36d9c666959babe15ebb251fe71e7f9ace809c9a326922f1ea5b5926d2d  2023.02.19-old.tar.xz
ed36369562e4672e1c320e65ef92b76efe84e5475b6fc72bc471f729338234b8  2023.02.19-old.tar.xz.sig
a8a84ab5ad67a919e434880f8d0ede685223df806994ba9a6f5739075d96ca34  2023.02.19.tar.xz
59abd249997ec0f410c949d0187e844758ce7cef845dfb397a23934e916d96eb  2023.02.19.tar.xz.sig
1126d5b8e4e8583cb6cb6c1ae8ad5bc2ba390627088fe970946bede5feb2f91c  2023.09.25-noble-scure.tar.xz
934aaa4b54714a5e9e93b607f5031aaddd63ee22d61c9e0ba260a8cf9289fbeb  2023.09.25-noble-scure.tar.xz.sig
467e4676164ead6f97e082e8b295b254b92f1228be706dc859ed50cada1e16a8  2023.09.25.tar.xz
994017fa29e46d8756727a2cbef57e7eac0007bf675c685ea9e5081367480d1e  2023.09.25.tar.xz.sig
ac417d8e604e2dce8a6d482d64ca79c953e083ecbd813533c785315397ffcc0f  2024.01.03-noble-scure.tar.xz
9b3c245dfe433ecba52250d71218975ca2740079442843ee9089497eda0d9eb6  2024.01.03-noble-scure.tar.xz.sig
582413828a2c201792f8b2f37af33feb62bb76f1108a590cfceff98b02e66ecc  2024.01.03.tar.xz
f0fb4a8c193811907e09e689a41697073593cf40cf242d6b8dc65cc12fc46e0c  2024.01.03.tar.xz.sig
cb1e2ff979567c3f4282f9ebcc39522f81683cacacdda3dd51daaa597804ef40  2024.07.03-noble-scure.tar.xz
89125022829985deefec784726cbb9b94a227d75f4a9684b421fe74a29056146  2024.07.03-noble-scure.tar.xz.sig
8eeb95bd3c9a744b5f01d79eabf87b031000e01e50b7b04a544042132bb91a80  2024.07.03.tar.xz
0b25ed634c39219252c1d76ca58d6956389d38846e2d5529751d5a3fe87c541e  2024.07.03.tar.xz.sig
```

## Creating archive

Clone repos:

    node list-clonable-repos.js

Create and sign .tar.xz:

```sh
title='2024.01.03'
XZ_OPT=-9 tar -Jcvf "$title.tar.xz" "$title" # create .tar.xz
gpg --detach-sign --sign ${title}.tar.xz # sign archive
```
