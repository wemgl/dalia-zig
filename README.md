dalia
-----

A small command-line utility for creating shell aliases to change directories without needing to type `cd`.

### Documentation Quick Links
* [Configuration](#configuration)
* [Custom Alias Names](#custom-alias-names)
* [Configuration File Example](#configuration-file-example)
* [Installation](#installation)
* [Customization](#customization)

## Configuration

Dalia requires a configuration file in order to run properly. Dalia expects the configuration file to be at
`$HOME/.dalia`
by default. The file should be called "config" and contain a list of absolute paths, and any optional custom names at
the start of the line, to create all aliases. Finally, all configured paths must be absolute paths&mdash;anything else
is invalid.

### Custom Alias Names

Aliases can have a custom name assigned to them, just surround whatever text you want with square brackets (`[` & `]`)
and include it at the beginning of the line before the file path. If dalia doesn't find a custom name for a particular
directory, then the alias will be the lowercase basename of the absolute path (e.g. `/some/absolute/path` yields an
alias named `path`).

#### Configuration File Example

Here's an example of a configuration file that `dalia` would load from `$HOME/.dalia/config`:

```
[workspace]~/Documents/workspace
~/Desktop
[icloud]~/Library/Mobile\ Documents/com~apple~CloudDocs
/Users/johnappleseed/Music
[photos] /Users/johnappleseed/Pictures
```

This configuration file will create the following aliases:

```
workspace='cd ~/Documents/workspace'
desktop='cd ~/Desktop'
icloud='cd '~/Library/Mobile\ Documents/com~apple~CloudDocs'
music='cd /Users/johnappleseed/Music'
photos='cd /Users/johnappleseed/Pictures'
```

Once `dalia` loads you can change directories with either `workspace`, `icloud`, or any other configured alias
right from your shell.

## Installation

Archives of precompiled binaries are available for download
via [GitHub Releases](https://github.com/wemgl/dalia-zig/releases) for macOS, Windows, and Linux.

You can also download and build the code from source using the Zig build system. First,
install [Zig](https://ziglang.org/download/). Next, run:

```
$ zig build --release=safe
```

to install `dalia` in the `zig-out/` directory. Then, add the built executable to your path. Finally, add the
following line to your shell's configuration file to initialize all aliases:

```
$ eval "$(/path/to/cmd/dalia aliases)"
```

This line will generate and output an alias command for each configured path in the current terminal session.
It's a good idea to include it in whichever configuration file your shell runs at the start of each session so
that the aliases are always available.

## Customization

Dalia expects to find its configuration, in a file named `config`, in the directory `$HOME/.dalia`, but
that location can be changed by setting the `DALIA_CONFIG_PATH` environment variable to somewhere
else and putting the `config` file in there instead.
