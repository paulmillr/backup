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
