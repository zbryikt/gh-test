require! <[fs fs-extra path child_process @plotdb/colors]>

make-github-release = ->
  exec = (opt = {}) -> new Promise (res, rej) ->
    if Array.isArray(opt) => [cmd, input] = [opt, null]
    else {cmd, input} = opt
    out = []
    proc = child_process.spawn(
      cmd.0
      cmd.slice(1)
      {stdio: if input => <[pipe pipe pipe]> else <[ignore pipe pipe]>}
    )
    proc.stdout.on \data, -> out.push it.toString!
    proc.stderr.on \data, -> out.push it.toString!
    if input => proc.stdin.end input
    proc.on \error, rej
    proc.on \exit, (code) ->
      if code == 0 => res out.join ''
      else rej new Error "Command failed: #{cmd.join ' '}\noutput:\n#{out.join('')}"

  get-version = -> require("./package.json").version

  parse-changelog = ({version, filename = "CHANGELOG.md"}) ->
    if !fs.exists-sync(filename) => return "release for version #version"
    lines = fs.read-file-sync(filename).toString!split(\\n)
    [log, hit, start, end] = [[], false, 0, -1]
    for line in lines =>
      if !hit and ~line.indexOf(version) => hit = true; continue
      else if hit == true and /#+\s+v?\d+\.\d+\.\d+/.exec(line) => hit = false; break
      else if hit => log.push line
    log = log.map -> it.trim!
    for i from 0 til log.length => if !log[i] => continue else start = i; break
    for i from log.length - 1 to 0 by -1 => if !log[i] => continue else end = i + 1; break
    return log.slice(start, end).join(\\n).trim!

  make-release = ({branch = "release"} = {}) ->
    version = get-version!
    release-note = parse-changelog {version}
    if !(version and /^\d+\.\d+\.\d+$/.exec(version)) =>
      console.error "invalid version string #version. exit.".red
      process.exit!
    if !release-note =>
      console.log "no available release note for version #version from CHANGELOG.md.".yellow
      console.log "Generate from commits instead.".yellow
    release-note = release-note.replace /"/gm, '\\"'
    cmd = (
      <[gh release create]> ++ ["v#version"] ++
      [ "--target", branch, "--title", version] ++
      (if !release-note => ["--generate-notes" ] else ["--notes-file", "-"])
    )
    exec({cmd, input: release-note})

  is-git-work-tree = ->
    (ret = "") <- exec(<[git rev-parse --is-inside-work-tree]>) .then _
    if ret.trim! != \true => return Promise.reject new Error("not a git repository")

  ensure-release-branch = ({remote = "origin", branch = "release"} = {}) ->
    <- is-git-work-tree!then _
    (working-branch) <- exec <[git rev-parse --abbrev-ref HEAD]> .then _
    working-branch = working-branch.trim!
    Promise.resolve!
      .then -> exec(<[git show-ref --verify --quiet]> ++ ["refs/heads/#branch"])
      .catch ->
        console.log "no branch #branch for releasing. creating one from current branch...".yellow
        <- exec(<[git checkout -b]> ++ [branch]).then _
        <- exec(<[git checkout]> ++ [working-branch]).then _
      .then ->
        (ret = "") <- exec(<[git ls-remote --heads]> ++ [remote, branch]).then _
        if !!~ret.indexOf("refs\/heads\/#branch") => return
        console.log "no remote branch #branch for releasing. creating one from current branch...".yellow
        <- exec(<[git checkout]> ++ [branch]).then _
        <- exec(<[git push --force]> ++ [remote, branch]).then _
        <- exec(<[git checkout]> ++ [working-branch]).then _

  update-release-branch = ({remote = "origin", branch = "release", work-folder = ".fedep/publish"} = {}) ->
    release-folder = ".fedep/_public"
    if !/^[.0-9a-zA-Z\/]+$/.exec(remote) => return Promise.reject("invalid remote #remote")
    if !/^[.0-9a-zA-Z\/]+$/.exec(branch) => return Promise.reject("invalid branch #branch")
    if !fs.exists-sync work-folder => return Promise.reject("work folder #work-folder doesn't exist")
    if fs.exists-sync release-folder => fs-extra.remove-sync release-folder
    <- exec <[git worktree add --force]> ++ [release-folder, branch] .then _
    fs-extra.copy-sync work-folder, release-folder, {overwrite: true}
    cmd = "cd .fedep/_public && git add * && git commit -m \"regen\" && git push -u #remote #branch"
    (res, rej) <- new Promise _
    (e, sout, serr = "") <- child_process.exec cmd, _
    if e => return rej new Error([sout, serr].map(->(it or '').trim!).filter(->it).join(\\n))
    return res!

  gh-status = ->
    <- exec <[gh status]> .catch _
    return Promise.reject new Error("gh status failed. run 'gh auth login' if necessary.")

  Promise.resolve!
    .then ->
      console.log "check gh status ...".yellow
      gh-status!
    .then ->
      console.log "check work tree status ...".yellow
      is-git-work-tree!
    .then ->
      console.log "prepare release branch...".yellow
      ensure-release-branch!
    .then ->
      console.log "update release branch...".yellow
      update-release-branch!
    .then ->
      console.log "make github release ...".yellow
      make-release!
    .then ->
      console.log "finish. ".green
    .catch (e) ->
      console.log "failed: ".red, e

