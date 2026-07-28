defmodule Logos.Fn do
  @moduledoc """
  A Logos closure: `%Logos.Fn{params, variadic?, body, env, clauses}`.
  `env` is the lexically-captured defining `Logos.Env` -- capturing it is
  the whole point of `fn`: it lets the closure see the bindings visible
  at its definition site even after that scope has otherwise returned,
  which is what makes it a closure rather than a plain function pointer.

  ## Multi-arity support

  To support `(fn ([a] body1) ([a b] body2))` multi-arity dispatch, this
  struct has a `clauses` field: `[%{params: [String.t()], variadic?:
  boolean(), body: [Logos.Form.t()]}]`, always populated (one entry for
  an ordinary single-arity `fn`, several for multi-arity). `params`/
  `variadic?`/`body` at the top level always mirror `hd(clauses)`, kept
  around so single-arity introspection/pattern-matching against the
  simple `%Logos.Fn{params:, variadic?:, body:}` shape still works;
  `Logos.Eval`'s applier always dispatches through `clauses`, never the
  mirrored top-level fields.

  `params` is a list of bare parameter name strings (already stripped of
  the `&` rest marker read by `Logos.Eval`'s `fn` handling); when
  `variadic?` is `true`, the *last* entry of `params` is the rest
  parameter, bound to a (possibly empty) list of the trailing args.
  """

  @type clause :: %{params: [String.t()], variadic?: boolean(), body: [Logos.Form.t()]}

  @type t :: %__MODULE__{
          params: [String.t()] | nil,
          variadic?: boolean() | nil,
          body: [Logos.Form.t()] | nil,
          env: Logos.Env.t(),
          clauses: [clause()]
        }

  defstruct params: nil, variadic?: nil, body: nil, env: nil, clauses: []
end
