# `mix logos.format`

Formats Logos source files, or checks that they're already formatted.
Built on `Logos.Format`, which formats from Ichor's raw token stream
(position- and text-preserving, so comments survive) plus a simple
paren-nesting-depth indentation rule -- `--check-formatted` mirrors `mix
format --check-formatted`'s own contract exactly.

## Usage

```sh
mix logos.format path/to/file.logos path/to/other.logos
mix logos.format "lib/**/*.logos"
mix logos.format --check-formatted path/to/file.logos
```

Each argument is expanded as a glob (`Path.wildcard/1`) -- a plain
literal path (no glob metacharacters) still works, since `Path.wildcard/1`
returns `[path]` unchanged when `path` exists and contains no glob
syntax, or `[]` when it doesn't exist at all (reported as an error, same
as a glob matching nothing). Quote glob arguments so the shell doesn't
expand them first.

## Modes

- **Without `--check-formatted`** (the default): every matched file is
  formatted via `Logos.Format.format/1` and written back in place. A file
  that's already exactly formatted is left untouched -- no spurious mtime
  bump -- determined by comparing bytes before writing.
- **With `--check-formatted`**: nothing is written. Every matched file is
  checked via `Logos.Format.formatted?/1`; if any file is not already
  formatted, their paths are listed on stderr and the task exits nonzero.
  This is the form to run in CI.

## Examples

Format everything under `priv/stdlib` in place:

```sh
$ mix logos.format "priv/stdlib/*.logos"
```

Check formatting without writing (as `mix precommit` and CI do):

```sh
$ mix logos.format --check-formatted "priv/stdlib/*.logos"
$ echo $?
0
```

When a file isn't formatted, the check lists it and fails:

```sh
$ mix logos.format --check-formatted "priv/stdlib/*.logos"
The following files are not formatted:
  priv/stdlib/core.logos
$ echo $?
1
```

A glob that matches nothing is an error, not a silent no-op:

```sh
$ mix logos.format "nonexistent/*.logos"
** (Mix) no files matched: nonexistent/*.logos
```

## See also

- [Cheatsheet](../CHEATSHEET.md) -- one-line quick reference.
- `CONTRIBUTING.md` -- `mix logos.format --check-formatted
  "priv/stdlib/*.logos"` is part of the project's own precommit checks
  for `.logos` sources (Elixir sources go through `mix format` instead).
