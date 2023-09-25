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

```
75d2c36d9c666959babe15ebb251fe71e7f9ace809c9a326922f1ea5b5926d2d  2023.02.19-old.tar.xz
ed36369562e4672e1c320e65ef92b76efe84e5475b6fc72bc471f729338234b8  2023.02.19-old.tar.xz.sig
a8a84ab5ad67a919e434880f8d0ede685223df806994ba9a6f5739075d96ca34  2023.02.19.tar.xz
59abd249997ec0f410c949d0187e844758ce7cef845dfb397a23934e916d96eb  2023.02.19.tar.xz.sig
1126d5b8e4e8583cb6cb6c1ae8ad5bc2ba390627088fe970946bede5feb2f91c  2023.09.25-noble-scure.tar.xz
934aaa4b54714a5e9e93b607f5031aaddd63ee22d61c9e0ba260a8cf9289fbeb  2023.09.25-noble-scure.tar.xz.sig
467e4676164ead6f97e082e8b295b254b92f1228be706dc859ed50cada1e16a8  2023.09.25.tar.xz
994017fa29e46d8756727a2cbef57e7eac0007bf675c685ea9e5081367480d1e  2023.09.25.tar.xz.sig
```

## Creating archive

Clone repos:

```js
const USER = 'paulmillr';
const DO_NOT_CLONE = new Set(['backup', 'qr-code-vectors', 'unused-test-repo', 'paulmillr', 'paulmillr.github.io']);
(async () => {
  const reqs = await Promise.all([1, 2, 3].map(function getPage(page) {
    return fetch(`https://api.github.com/users/${USER}/repos?page=${page}`).then(r => r.json());
  }));
  const repos = reqs.flat().filter(repo => !repo.archived && !repo.fork && !(DO_NOT_CLONE.has(repo.name)));
  console.log(repos.map(r => r.name))
  const isNobleScure = r => (r.name.startsWith('noble') || r.name.startsWith('scure'))
  const printCloneUrls = (repos) => repos.forEach(r => console.log(`git clone ${r.ssh_url}`))
  const general = repos.filter(r => !isNobleScure(r))
  const nobleScure = repos.filter(r => isNobleScure(r));

  console.log('# general')
  printCloneUrls(general)

  console.log('# noble and scure')
  printCloneUrls(nobleScure)
})()
```

Create and sign .tar.xz:

```sh
title='2024.01.30'
XZ_OPT=-9 tar -Jcvjf "$title.tar.xz" "$title" # create .tar.xz
gpg --detach-sign --sign ${title}.tar.xz # sign archive
```