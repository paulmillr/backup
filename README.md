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
```

## Creating archive

```sh
user='paulmillr'
title='backup'
function dlpage() {
    echo "\nDownloading page $1...\n"
    curl -s https://api.github.com/users/${user}/repos\?page\=${1} | grep \"clone_url\" | awk '{print $2}' | sed -e 's/"//g' -e 's/,//g' | xargs -n1 git clone
}
echo "Backing up all github repos for user ${user} into dir '$title'"
mkdir $title && cd $title
dlpage 1; dlpage 2; dlpage 3
cd ..

XZ_OPT=-9 tar -Jcvjf "$title.tar.xz" "$title" # create .tar.xz
gpg --detach-sign --sign ${title}.tar.xz # sign archive
```