# backup of all github repositories

    # verify integrity of the archive: check GPG signature
    gpg --verify backup.tar.xz.sig backup.tar.xz
    # unpack .tar.bz2 into separate directory
    tar -xf backup.tar.xz

Generated with `backup-github` function from `.zshrc` of `paulmillr/dotfiles`

Mirrors: https://github.com/paulmillr/backup, https://gitlab.com/paulmillr/backup

## checksums

`old`-prefixed archives contain archived, unmaintained projects.

75d2c36d9c666959babe15ebb251fe71e7f9ace809c9a326922f1ea5b5926d2d  2023.02.19-old.tar.xz
ed36369562e4672e1c320e65ef92b76efe84e5475b6fc72bc471f729338234b8  2023.02.19-old.tar.xz.sig
a8a84ab5ad67a919e434880f8d0ede685223df806994ba9a6f5739075d96ca34  2023.02.19.tar.xz
59abd249997ec0f410c949d0187e844758ce7cef845dfb397a23934e916d96eb  2023.02.19.tar.xz.sig
