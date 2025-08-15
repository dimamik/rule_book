defmodule RuleBook.Engine do
  @moduledoc false
  alias RuleBook.Types

  defmodule Memory do
    @moduledoc false
    defstruct seq: 0, by_id: %{}, index: %{}
    @type t :: %__MODULE__{seq: non_neg_integer(), by_id: map(), index: map()}

    def new, do: %__MODULE__{}

    @doc "Return all facts in working memory."
    def facts(%__MODULE__{by_id: by_id}), do: Map.values(by_id)

    @doc "Assert a fact, returning updated memory and list of changed ids."
    def assert(%__MODULE__{} = m, fact) do
      id = fact_id(fact)

      if Map.has_key?(m.by_id, id) do
        {m, []}
      else
        m = put_fact(m, id, fact)
        RuleBook.Telemetry.exec([:rule_book, :memory, :assert], %{}, %{id: id})
        {m, [id]}
      end
    end

    @doc "Insert or update a fact, returning updated memory and changed ids."
    def upsert(%__MODULE__{} = m, fact) do
      id = fact_id(fact)

      case Map.fetch(m.by_id, id) do
        {:ok, existing} ->
          if existing == fact do
            {m, []}
          else
            m = put_fact(m, id, fact)
            RuleBook.Telemetry.exec([:rule_book, :memory, :upsert], %{}, %{id: id, updated: true})
            {m, [id]}
          end

        :error ->
          m = put_fact(m, id, fact)
          RuleBook.Telemetry.exec([:rule_book, :memory, :upsert], %{}, %{id: id, inserted: true})
          {m, [id]}
      end
    end

    @doc "Retract a fact by id, returning updated memory and changed ids."
    # Retract by composite key directly
    def retract(%__MODULE__{} = m, {_, _} = key) do
      if Map.has_key?(m.by_id, key) do
        m = %__MODULE__{m | by_id: Map.delete(m.by_id, key)}
        # expose just the second element as id for compatibility
        RuleBook.Telemetry.exec([:rule_book, :memory, :retract], %{}, %{id: elem(key, 1)})
        {m, [elem(key, 1)]}
      else
        {m, []}
      end
    end

    # Retract by simple id (integer/binary/atom) for backward compatibility
    def retract(%__MODULE__{} = m, id) when is_integer(id) or is_binary(id) or is_atom(id) do
      key =
        Enum.find(Map.keys(m.by_id), fn
          {_, ^id} -> true
          other when other == id -> true
          _ -> false
        end)

      if key do
        m = %__MODULE__{m | by_id: Map.delete(m.by_id, key)}
        RuleBook.Telemetry.exec([:rule_book, :memory, :retract], %{}, %{id: id})
        {m, [id]}
      else
        {m, []}
      end
    end

    def retract(%__MODULE__{} = m, fact) do
      retract(m, fact_id(fact))
    end

    defp put_fact(%__MODULE__{} = m, id, fact) do
      %__MODULE__{m | by_id: Map.put(m.by_id, id, fact)}
    end

    # Composite id function prevents collisions across different struct types.
    # For structs with an :id field, use {StructModule, id}
    # For plain maps with :id, use {:map, id}; otherwise hash the term.
    defp fact_id(%{__struct__: mod, id: id}) when not is_nil(id), do: {mod, id}
    defp fact_id(%{id: id}) when not is_nil(id), do: {:map, id}
    defp fact_id(fact), do: {:term, :erlang.phash2(fact)}
  end

  @doc "Build agenda from rules and memory. Optionally restrict by changed_ids."
  def build_agenda(rules, %Memory{} = memory, tokens, once_tokens, _changed_ids, options) do
    facts = Memory.facts(memory)
    start = System.monotonic_time()

    rules
    |> Enum.flat_map(fn %Types.Rule{} = rule ->
      match_rule(rule, facts)
      |> Enum.map(fn bindings ->
        token = {rule.name, bindings}

        %{
          rule: rule.name,
          bindings: bindings,
          salience: rule.salience,
          once: rule.once,
          token: token
        }
      end)
    end)
    |> filter_fired_tokens(tokens, once_tokens)
    |> apply_conflict_resolution(options)
    |> tap(fn acts ->
      duration = System.monotonic_time() - start

      RuleBook.Telemetry.exec([:rule_book, :agenda, :build], %{duration: duration}, %{
        count: length(acts)
      })
    end)
  end

  @doc false
  defp match_rule(%Types.Rule{patterns: patterns}, facts) do
    # AND across patterns with unification and per-pattern guards
    Enum.reduce(patterns, [%{}], fn pattern, acc ->
      extend_bindings_for_pattern(pattern, facts, acc)
    end)
  end

  defp extend_bindings_for_pattern(%Types.Pattern{} = pattern, facts, acc_bindings_list) do
    Enum.reduce(acc_bindings_list, [], fn binding, acc ->
      matches = match_pattern_with_facts(pattern, facts, binding)
      acc ++ matches
    end)
  end

  defp match_pattern_with_facts(%Types.Pattern{} = pattern, facts, binding) do
    Enum.reduce(facts, [], fn fact, acc ->
      case match_and_unify(pattern, fact, binding) do
        {:ok, merged} -> [merged | acc]
        :skip -> acc
      end
    end)
  end

  defp match_and_unify(%Types.Pattern{matcher: m, guard: g}, fact, binding) do
    with {:ok, b2} <- m.(fact),
         {:ok, merged} <- unify(binding, b2),
         true <- guard_passes?(g, merged) do
      {:ok, merged}
    else
      _ -> :skip
    end
  end

  defp guard_passes?(nil, _merged), do: true
  defp guard_passes?(g, merged) when is_function(g, 1), do: g.(merged)

  defp unify(a, b) when a == %{}, do: {:ok, b}
  defp unify(a, b) when b == %{}, do: {:ok, a}

  defp unify(a, b) do
    conflict = :__rb_conflict__
    merged = Map.merge(a, b, fn _k, v1, v2 -> if v1 == v2, do: v1, else: conflict end)
    if Enum.any?(merged, fn {_k, v} -> v == conflict end), do: :conflict, else: {:ok, merged}
  end

  @doc false
  defp filter_fired_tokens(acts, tokens, once_tokens) do
    Enum.reject(acts, fn act ->
      MapSet.member?(tokens, act[:token]) or
        (act[:once] == true and MapSet.member?(once_tokens, act[:token]))
    end)
  end

  @doc false
  defp apply_conflict_resolution(acts, options) do
    recency =
      cond do
        is_list(options) -> Keyword.get(options, :recency, :lifo)
        is_map(options) -> Map.get(options, :recency, :lifo)
        true -> :lifo
      end

    sorted =
      acts
      |> Enum.sort_by(fn a -> {-a.salience, a.rule} end)

    case recency do
      :lifo -> sorted
      :fifo -> sorted
      _ -> sorted
    end
  end

  @doc "Fire an activation: call the action with a context and apply effects if not in pure mode."
  def fire_activation(%{rules: rules} = rb, %{rule: name, bindings: bindings} = _act) do
    start = System.monotonic_time()
    rule = Enum.find(rules, &(&1.name == name))
    ctx = %{rb: rb, binding: bindings, effects: []}
    res = do_action(rule.action, ctx)

    rb_with_token = add_activation_tokens(rb, rule.name, bindings, rule.once)

    effs = normalize_effects(res)

    {rb2, effects} = apply_effects_based_on_mode(rb_with_token, effs)

    duration = System.monotonic_time() - start

    RuleBook.Telemetry.exec([:rule_book, :activation, :fire], %{duration: duration}, %{
      rule: name,
      effects: length(effects)
    })

    {rb2, effects}
  end

  defp add_activation_tokens(rb, rule_name, bindings, once?) do
    token = {rule_name, bindings}
    rb = Map.update!(rb, :tokens, fn set -> MapSet.put(set, token) end)
    if once?, do: Map.update!(rb, :once_tokens, fn set -> MapSet.put(set, token) end), else: rb
  end

  defp normalize_effects(res) do
    case res do
      {:effects, effs} -> effs
      %{} = new_ctx when is_map(new_ctx) -> Map.get(new_ctx, :effects, [])
      other -> List.wrap(other)
    end
  end

  defp apply_effects_based_on_mode(rb, effs) do
    effs = List.wrap(effs)
    if pure?(rb), do: {rb, effs}, else: apply_effects(rb, effs)
  end

  defp do_action({m, f, a}, ctx), do: apply(m, f, [ctx | a])
  defp do_action(fun, ctx) when is_function(fun, 1), do: fun.(ctx)

  defp pure?(%{options: opts}) do
    cond do
      is_map(opts) -> Map.get(opts, :pure, false)
      is_list(opts) -> Keyword.get(opts, :pure, false)
      true -> false
    end
  end

  @doc false
  defp apply_effects(rb, effects) do
    Enum.reduce(effects, {rb, []}, &handle_effect/2)
  end

  # Separate effect handlers to keep nesting shallow for Credo
  defp handle_effect({:assert, fact}, {acc_rb, acc_effs}) do
    RuleBook.Telemetry.exec([:rule_book, :effect, :assert], %{}, %{})

    # Use internal effect application that preserves tokens (do not clear per-state tokens mid-activation)
    {RuleBook.apply_effect(acc_rb, {:assert, fact}), [{:assert, fact} | acc_effs]}
  end

  defp handle_effect({:retract, id_or_fact}, {acc_rb, acc_effs}) do
    RuleBook.Telemetry.exec([:rule_book, :effect, :retract], %{}, %{})
    {RuleBook.apply_effect(acc_rb, {:retract, id_or_fact}), [{:retract, id_or_fact} | acc_effs]}
  end

  defp handle_effect({:emit, name, payload}, {acc_rb, acc_effs}) do
    {acc_rb, [{:emit, name, payload} | acc_effs]}
  end

  defp handle_effect({:log, _lvl, _msg} = eff, {acc_rb, acc_effs}) do
    {acc_rb, [eff | acc_effs]}
  end

  defp handle_effect(_other, acc), do: acc
end
