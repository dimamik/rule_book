defmodule RuleBook.Rules do
  @moduledoc """
  Rules DSL for defining forward-chaining rules with `defrule`.

  - Use in your module with `use RuleBook.Rules` and define one or more `defrule`.
  - Patterns support Elixir pattern matching and optional guards via `when`.
  - Variables unify across patterns by name; conflicts cause the match to fail.
  - Actions are pure functions that return effects; side-effects are applied by the engine.

  Example:

      defmodule MyRules do
        use RuleBook.Rules

        defmodule Order do
          defstruct [:id, :total]
        end

        defrule :vip_large_order,
          when: [
            %Order{id: id, total: total} when total > 1000,
            %{user: %{status: :vip, id: user_id}}
          ],
          then: fn ctx -> ctx end,
          salience: 10,
          once: true
      end
  """

  defmacro __using__(_opts) do
    quote do
      import RuleBook.Rules, only: [defrule: 2]
      Module.register_attribute(__MODULE__, :__rulebook_rules__, accumulate: true)
      @before_compile RuleBook.Rules
    end
  end

  @doc """
  Define a rule with patterns and an action.

  - `when:` is a list of patterns. Each pattern can be a struct/map pattern and may include an Elixir guard using `when`.
  - Variables bound in earlier patterns will be unified with later ones by name. If a later pattern binds the same variable, it must have the same value.
  - Guards are evaluated against the merged bindings so far.
  - `then:` is a 1-arity function receiving a context map: `%{rb: RuleBook.t, binding: map, effects: list}`. Use `RuleBook.Action` helpers to produce effects.
  - Options: `:salience`, `:once`, `:mode`, `:throttle`.
  """
  defmacro defrule(name, opts) when is_list(opts) do
    {patterns_ast, action_ast, meta} = extract_opts(opts)

    # Build private matcher and guard functions and collect their names
    {matcher_defs, matcher_names, guard_names} = build_matchers(name, patterns_ast)

    action_fun_name = action_fun_name(name)
    action_def = build_action_def(action_fun_name, action_ast)

    patterns_list_ast =
      matcher_names
      |> Enum.zip(guard_names)
      |> Enum.map(fn {m_fun, g_fun} ->
        quote do
          %RuleBook.Types.Pattern{
            matcher: &(__MODULE__.unquote(m_fun) / 1),
            guard:
              unquote(
                if g_fun do
                  quote do: &(__MODULE__.unquote(g_fun) / 1)
                else
                  nil
                end
              )
          }
        end
      end)

    quote do
      unquote_splicing(matcher_defs)
      unquote(action_def)

      rule = %RuleBook.Types.Rule{
        name: unquote(name),
        patterns: unquote(patterns_list_ast),
        action: &(__MODULE__.unquote(action_fun_name) / 1),
        salience: unquote(Macro.escape(meta[:salience])),
        once: unquote(Macro.escape(meta[:once])),
        mode: unquote(Macro.escape(meta[:mode])),
        throttle: unquote(Macro.escape(meta[:throttle]))
      }

      @__rulebook_rules__ rule
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __rulebook_rules__, do: @__rulebook_rules__ |> Enum.reverse()
    end
  end

  defp extract_opts(opts) do
    patterns = Keyword.fetch!(opts, :when)
    action = Keyword.fetch!(opts, :then)

    meta = [
      salience: Keyword.get(opts, :salience, 0),
      once: Keyword.get(opts, :once, false),
      mode:
        if(Keyword.get(opts, :once, false), do: :once, else: Keyword.get(opts, :mode, :per_fact)),
      throttle: Keyword.get(opts, :throttle)
    ]

    {patterns, action, meta}
  end

  # Turn patterns into private matcher functions (and optional guard functions)
  # and return {defs, matcher_names, guard_names}
  defp build_matchers(rule_name, patterns_ast) do
    patterns_ast
    |> Enum.with_index()
    |> Enum.map(fn {pat_ast, idx} ->
      fun_name = matcher_fun_name(rule_name, idx)
      pat_only = strip_when(pat_ast)
      guard_ast = extract_guard(pat_ast)
      var_names = collect_vars(pat_only)
      bindings_map_ast = build_bindings_map(var_names)

      def_ast =
        quote do
          def unquote(fun_name)(fact) do
            case fact do
              unquote(pat_only) -> {:ok, unquote(bindings_map_ast)}
              _ -> :nomatch
            end
          end
        end

      {guard_def, guard_fun_name_or_nil} =
        build_guard(rule_name, idx, guard_ast)

      {quote do
         unquote(def_ast)
         unquote(guard_def)
       end, fun_name, guard_fun_name_or_nil}
    end)
    |> Enum.reduce({[], [], []}, fn {def_ast, m_fun, g_fun}, {defs, ms, gs} ->
      {[def_ast | defs], [m_fun | ms], [g_fun | gs]}
    end)
    |> then(fn {defs, ms, gs} -> {Enum.reverse(defs), Enum.reverse(ms), Enum.reverse(gs)} end)
  end

  defp matcher_fun_name(rule_name, idx),
    do: String.to_atom("__rb_match_" <> to_string(rule_name) <> "_" <> Integer.to_string(idx))

  defp action_fun_name(rule_name), do: String.to_atom("__rb_action_" <> to_string(rule_name))

  defp build_action_def(fun_name, action_ast) do
    quote do
      def unquote(fun_name)(ctx), do: unquote(action_ast).(ctx)
    end
  end

  @doc false
  defp strip_when({:when, _m, [pat, _guard]}), do: pat
  defp strip_when(other), do: other

  @doc false
  defp extract_guard({:when, _m, [_pat, guard]}), do: guard
  defp extract_guard(_other), do: nil

  # Collect variable names from a quoted AST, excluding `_` and pinned vars.
  @doc false
  defp collect_vars(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, MapSet.new(), fn
        {var, _m, ctx} = node, acc when is_atom(var) and is_atom(ctx) ->
          {node, MapSet.put(acc, var)}

        {:^, _, [_inner]} = node, acc ->
          {node, acc}

        {:\\, _, [inner, _default]} = node, acc ->
          {node, elem(Macro.prewalk(inner, acc, &collector/2), 1)}

        node, acc ->
          {node, acc}
      end)

    MapSet.to_list(acc)
    |> Enum.reject(&(&1 == :_))
  end

  @doc false
  defp collector({var, _m, ctx} = node, acc) when is_atom(var) and is_atom(ctx),
    do: {node, MapSet.put(acc, var)}

  defp collector(node, acc), do: {node, acc}

  @doc false
  defp build_bindings_map(var_names) do
    kvs = Enum.map(var_names, fn v -> {v, {v, [], nil}} end)
    {:%{}, [], kvs}
  end

  @doc false
  defp guard_fun_name(rule_name, idx),
    do: String.to_atom("__rb_guard_" <> to_string(rule_name) <> "_" <> Integer.to_string(idx))

  @doc false
  defp build_guard(_rule_name, _idx, nil), do: {quote(do: nil), nil}

  defp build_guard(rule_name, idx, guard_ast) do
    vars = collect_vars(guard_ast)

    assigns =
      Enum.map(vars, fn v ->
        quote do
          unquote(Macro.var(v, nil)) = Map.fetch!(bindings, unquote(v))
        end
      end)

    gname = guard_fun_name(rule_name, idx)

    def_ast =
      quote do
        def unquote(gname)(bindings) when is_map(bindings) do
          try do
            unquote_splicing(assigns)
            !!unquote(guard_ast)
          rescue
            _ -> false
          end
        end
      end

    {def_ast, gname}
  end
end
