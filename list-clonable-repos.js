const USER = 'paulmillr';
const DO_NOT_CLONE = new Set([
  'backup', 'test-repo', 'unused-test-repo', 'paulmillr', 'paulmillr.github.io',

  'acvp-vectors',
  'eth-vectors',
  'qr-code-vectors',
  'noble-hashes-vectors',
  'post-quantum-vectors',

  'dotfiles-vsix',
]);
(async () => {
  const reqs = await Promise.all([1, 2, 3].map(function getPage(page) {
    return fetch(`https://api.github.com/users/${USER}/repos?page=${page}`).then(r => r.json());
  }));
  const repos = reqs.flat().filter(repo => !repo.archived && !repo.fork && !(DO_NOT_CLONE.has(repo.name)));
  console.log(repos.map(r => r.name))
  const isNoble = r => (r.name.startsWith('noble'))
  const printCloneUrls = (repos) => repos.forEach(r => console.log(`git clone ${r.ssh_url}`))
  const general = repos.filter(r => !isNoble(r))
  const nob = repos.filter(r => isNoble(r));

  console.log('# general')
  printCloneUrls(general)

  console.log('# noble')
  printCloneUrls(nob)
})()
