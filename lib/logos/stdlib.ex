defmodule Logos.Stdlib do
  @moduledoc """
  Loads `stdlib.lisp` -- the standard library's Layer 2: macros and
  functions written in Logos itself, layered on top of the
  Elixir-implemented Layer-1 primitives -- into a `Logos.Runtime`'s
  `logos.core` namespace. This runs the whole reader -> macroexpand ->
  eval pipeline over `stdlib.lisp`'s actual source text (real dogfooding,
  not a shortcut that bypasses the normal evaluation path), so a broken
  `defmacro` bootstrap or a broken `if`/`let`/`when`/`unless`/`and`/`or`/
  `defn` fails loudly right here, not silently later.

  `stdlib.lisp` lives as a real file at `lib/logos/stdlib.lisp` (not an
  embedded Elixir string constant). `@external_resource` is the standard
  Elixir idiom for "this module's compiled artifact depends on a
  non-`.ex` file's contents" -- it makes Mix recompile this module
  whenever `stdlib.lisp` changes, the same way changing a `.ex` file
  would.
  """

  alias Logos.{Env, Eval, Macroexpand, Namespace, Reader, Runtime}

  @stdlib_path Path.join(__DIR__, "stdlib.lisp")
  @external_resource @stdlib_path
  @stdlib_source File.read!(@stdlib_path)

  @doc "The raw `stdlib.lisp` source text, embedded at compile time."
  @spec source() :: String.t()
  def source, do: @stdlib_source

  @doc """
  Reads, macroexpands, and evaluates every top-level form in `stdlib.lisp`
  against `runtime`, interning everything into `logos.core` (the current
  namespace is temporarily switched to `logos.core` for the duration of
  the load, then restored). Raises if any form fails to read/expand/eval
  -- a broken stdlib is a startup-time failure, not a `{:error, _}}` a
  caller is expected to recover from. Returns `runtime` for pipelining
  (`Logos.Runtime.new() |> Logos.Stdlib.load!()`, exactly what
  `Logos.new_runtime/0` does).
  """
  @spec load!(Runtime.t()) :: Runtime.t()
  def load!(runtime) do
    Namespace.ensure!(runtime, "logos.core")
    previous_ns = Runtime.current_ns(runtime)
    Runtime.set_current_ns!(runtime, "logos.core")

    try do
      {:ok, forms} = Reader.read_all(@stdlib_source, runtime)
      env = Env.new()
      locals = Env.bound_names(env)

      Enum.each(forms, fn form ->
        expanded = Macroexpand.expand(form, locals, runtime)

        case Eval.eval(expanded, env, runtime) do
          {:ok, _value} ->
            :ok

          {:error, reason} ->
            raise "stdlib.lisp failed to load: #{inspect(reason)} while evaluating #{inspect(form)}"
        end
      end)
    after
      Runtime.set_current_ns!(runtime, previous_ns)
    end

    runtime
  end
end
