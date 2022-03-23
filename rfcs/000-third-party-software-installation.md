- Topic Name: `third-party-software-installation`
- Start Date: 2022-03-22
- RFC PR: [vlang/rfcs#0000](https://github.com/vlang/rfcs/pull/22)
  <!-- - V Issue: [vlang/v#00000](https://github.com/vlang/v/issues/00000) -->

# Summary

Allow installation of third-party V software.
This goes beyond just placing the source code in `VMODULES`.
It allows building the software from source locally and adding it to path for the user to uses from anywhere.

Additionally, we propose the use of `~/.v` and the relevant subfolders (like `~/.v/modules`, `~/.v/bin`) to store the source code, built binaries, etc.

# Motivation

Currently, V only allows downloading the source code for V modules in the `VMODULES` directory through the `v install` command.
This is good for making modules globally available. There is currently no streamlined way of _installing_ or _obtaining_ third-party software written in V.

# Guide-level explanation

Take [_klonol_](https://github.com/hungrybluedev/klonol) for example.
It is a command-line tool written in V that helps to maintain a local copy of all git repositories on GitHub and Gitea.
If you want to install it, you have to clone the source yourself, run `v build.vsh` and then add the `bin` folder to `PATH`.
A nice thing to have is a `v obtain <repo>` or `v install -g <repo>` command (or something else, please comment) that will clone the repo and build it for you.

Only once, like when V is install, for example, the user needs to add `~/.v/bin` to `PATH`.
This will make all third-party applications installed using `v obtain <repo>` available from anywhere.

# Reference-level explanation

It will piggyback off of `v install`.
The act of installing the software is done through the following additional steps:

1. Running `v build.vsh` or some other specified build script in the root of the repo.
2. This will create an executable, along with all other
   relevant files (like templates, etc) in the `bin` directory of the repo. Ideally, the resources will be embedded in the executable to allow for only one executable to be enough.
3. The executable will be added to `~/.v/bin` for the user to call from anywhere.
   TODO.
   An additional **suggestion** is to have the `~/.vmodules` directory be replaced in favour of `~/.v/modules`.

If there is another script (other than `build.vsh`) that generates the executable

A sample `build.vsh` script is:

```text
println('Removing old artifacts...')
rmdir_all('bin') or {}
println('Done removing "bin" directory.')

println('\nCreating new output directory "bin"...')
mkdir('bin') ?
println('Done creating "bin" directory.')

println('\nChecking if everything is formatted correctly...')
execute_or_panic('v fmt -verify .')
println('Done checking formatting.')

println('\nCompiling and building executable...')
execute_or_panic('v -prod . -o bin/klonol')
println('Done compiling and placing executable in "bin".')
```

Taken from [klonol](https://github.com/hungrybluedev/klonol/blob/6e36e5676542aae40e0124de13055643484bb015/build.vsh).

Users will have to add `~/.v/bin` to their `PATH` once.

We also make use of the `bin` directory to keep the other files in the root of the repository out of the search path.

# Drawbacks

- Security concerns. Perhaps users should take some extra steps to install software from third-party sources.
- It will confuse users between the `v install` and `v obtain` or `v install --global` commands.
- Users need to tinker with their `PATH`.
- Third-party projects with the same name will cause namespace collision.

# Rationale and alternatives

- The alternative is to clone each project separately, build them and add their `bin` folders to `PATH`.
- It is preferable to have a simpler system.

# Prior art

Rust's `cargo` also allows users to install third-party software. Same for `npm`.

`cargo` asks the user to update their `PATH`.

# Unresolved questions

- How do we handle the versions of third-party software?

  See discussion in the Pull Request: [here](https://github.com/vlang/rfcs/pull/22#issuecomment-1075975185)

- How do we allow for multiple versions?

  See discussion in the Pull Request: [here](https://github.com/vlang/rfcs/pull/22#issuecomment-1075975185)

- How do we handle namespace collisions?

  See discussion in the Pull Request: [here](https://github.com/vlang/rfcs/pull/22#issuecomment-1075975185)

- How do we allow for local environments? Like Python's Virtual Environment?

  Probably needs to be discussed in a separate RFC.

# Future possibilities

We should keep the tentative location of `VHOME` customisable.
This will ease in supporting local environments.
A separate RFC will be made for this.
