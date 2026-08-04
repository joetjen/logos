# `mix logos.gen_docs`

Regenerates `guides/language/stdlib/*.md` -- an overview page, one
special-forms page, and one page per stdlib namespace, all built from
`Logos.StdlibDocs.documents/0` (every entry paired with a real,
freshly-evaluated example). Those files are checked in and generated;
**never hand-edit them** -- edit the stdlib docstrings/`@examples` they're
generated from instead (see each generated file's own header comment and
`Logos.StdlibDocs`'s moduledoc).

## Usage

```sh
MIX_ENV=dev mix logos.gen_docs
```

`MIX_ENV=dev` matters: `Logos.StdlibDocs` and its dependencies for
generating docs live in the `:dev` environment, not `:test` or `:prod`.

## When to run it

Run this whenever a stdlib docstring or example changes -- a new
`defn`/`defmacro`/`import`, an edit to an existing docstring, or a
new/changed `@examples` entry. `mix test`
(`test/logos/stdlib_docs_test.exs`) fails if any checked-in file under
`guides/language/stdlib/` has drifted from what
`Logos.StdlibDocs.documents/0` currently produces -- so a stdlib change
that needs a regen and skips it is caught by `mix precommit`, not
silently merged.

## What gets written

One file per entry in `Logos.StdlibDocs.documents/0`'s output, into
`guides/language/stdlib/` (created if it doesn't exist): an overview
page, a special-forms reference, and one page per stdlib namespace
(`logos.core`, `logos.seq`, `logos.concurrency`, `logos.multimethod`,
`logos.set`, `logos.walk`, `logos.string`, `logos.test`, plus the
primitives-only `logos.map`). Each write is unconditional (the file is
always rewritten, unlike `mix logos.format`'s byte-comparison skip) and
reported to stdout.

## Example

```sh
$ MIX_ENV=dev mix logos.gen_docs
wrote guides/language/stdlib/OVERVIEW.md
wrote guides/language/stdlib/SPECIAL_FORMS.md
wrote guides/language/stdlib/CORE.md
wrote guides/language/stdlib/SEQ.md
wrote guides/language/stdlib/CONCURRENCY.md
wrote guides/language/stdlib/MULTIMETHOD.md
wrote guides/language/stdlib/SET.md
wrote guides/language/stdlib/WALK.md
wrote guides/language/stdlib/STRING.md
wrote guides/language/stdlib/TEST.md
```

Then verify nothing drifted (this is exactly what `mix precommit` checks
via `mix test`):

```sh
$ git status --short guides/language/stdlib/
$ mix test test/logos/stdlib_docs_test.exs
```

An empty `git status` output means the checked-in files were already
current; any listed files mean this run picked up a real doc change that
now needs to be committed alongside the stdlib edit that caused it.

## See also

- `Logos.StdlibDocs`'s moduledoc -- how each page is assembled and how
  the `@examples` are evaluated for real rather than hand-typed.
- `CONTRIBUTING.md` -- where this task fits into the overall contribution
  workflow.
