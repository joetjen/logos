defmodule Logos.NamespaceLoadingTest do
  @moduledoc """
  End-to-end tests for real file-based namespace loading -- `require`/
  `use` resolving a namespace not already in-memory against
  `Logos.Runtime`'s `:load_paths`, see `Logos.Primitives`' private
  `load_ns!/2`. Each test writes its own tiny `.logos` fixture tree into
  a fresh temp dir (cleaned up via `on_exit`) rather than checking in
  fixture files, since the whole point here is exercising real
  `File.read/1` disk access end to end.
  """
  use ExUnit.Case, async: true

  alias Logos.{Namespace, Runtime}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "logos_ns_loading_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write_ns_file!(dir, relative_path, source) do
    full = Path.join(dir, relative_path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, source)
  end

  defp runtime(dir), do: Logos.new_runtime(load_paths: [dir])

  test "require resolves a munged dotted+hyphenated namespace name to its file", %{dir: dir} do
    write_ns_file!(dir, "my_app/core.logos", """
    (ns my-app.core)
    (defn greet [] "hi")
    """)

    rt = runtime(dir)
    assert {:ok, _, _} = Logos.eval_string("(require 'my-app.core)", rt)
    assert Namespace.has_var?(rt, "my-app.core", "greet")
  end

  test "a required file that itself requires a second file loads both, transitively", %{
    dir: dir
  } do
    write_ns_file!(dir, "app/a.logos", """
    (ns app.a
      (:require [app.b :as b]))
    (defn a-plus-one [x] (b/inc-it x))
    """)

    write_ns_file!(dir, "app/b.logos", """
    (ns app.b)
    (defn inc-it [x] (+ x 1))
    """)

    rt = runtime(dir)
    assert {:ok, _, _} = Logos.eval_string("(require 'app.a)", rt)
    assert Namespace.has_var?(rt, "app.a", "a-plus-one")
    assert Namespace.has_var?(rt, "app.b", "inc-it")
  end

  test "a genuine circular require pair fails with {:circular_require, _} instead of hanging",
       %{dir: dir} do
    write_ns_file!(dir, "circ/a.logos", """
    (ns circ.a
      (:require circ.b))
    """)

    write_ns_file!(dir, "circ/b.logos", """
    (ns circ.b
      (:require circ.a))
    """)

    rt = runtime(dir)
    assert {:error, {:circular_require, "circ.a"}} = Logos.eval_string("(require 'circ.a)", rt)
  end

  test "a missing file fails with {:namespace_not_loaded, _}", %{dir: dir} do
    rt = runtime(dir)

    assert {:error, {:namespace_not_loaded, "does.not.exist"}} =
             Logos.eval_string("(require 'does.not.exist)", rt)
  end

  test "a file that evaluates but never defines the expected namespace fails with {:ns_file_missing_ns, _, _}",
       %{dir: dir} do
    write_ns_file!(dir, "oops/wrong.logos", """
    (ns oops.actually-different)
    """)

    rt = runtime(dir)

    assert {:error, {:ns_file_missing_ns, "oops.wrong", path}} =
             Logos.eval_string("(require 'oops.wrong)", rt)

    assert path == Path.join(dir, "oops/wrong.logos")
  end

  test "the requiring process's current namespace is restored after a load that switches ns internally",
       %{dir: dir} do
    write_ns_file!(dir, "switches/ns.logos", """
    (ns switches.ns)
    (defn hello [] :hi)
    """)

    rt = runtime(dir)
    assert Runtime.current_ns(rt) == "user"

    assert {:ok, _, _} = Logos.eval_string("(require 'switches.ns)", rt)

    assert Runtime.current_ns(rt) == "user"
    assert Namespace.has_var?(rt, "switches.ns", "hello")
  end
end
