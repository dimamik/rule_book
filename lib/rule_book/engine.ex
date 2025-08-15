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
  def retract(%__MODULE__{} = m, id) when is_integer(id) or is_binary(id) or is_atom(id) do
      if Map.has_key?(m.by_id, id) do
    m = %__MODULE__{m | by_id: Map.delete(m.by_id, id)}
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

    # trivial id function; users can define structs with id, or we use the term itself
    defp fact_id(%{id: id}) when not is_nil(id), do: id
    defp fact_id(fact), do: :erlang.phash2(fact)
  end

  @doc "Build agenda from rules and memory. Optionally restrict by changed_ids."
  def build_agenda(rules, %Memory{} = memory, tokens, _changed_ids, options) do
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
    |> filter_fired_tokens(tokens)
    |> apply_conflict_resolution(options)
    |> tap(fn acts ->
      duration = System.monotonic_time() - start
      RuleBook.Telemetry.exec([:rule_book, :agenda, :build], %{duration: duration}, %{count: length(acts)})
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
  defp filter_fired_tokens(acts, tokens) do
    Enum.reject(acts, fn act -> MapSet.member?(tokens, act[:token]) end)
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

    token = {rule.name, bindings}

    rb_with_token = %{
      rb
      | tokens: MapSet.put(rb.tokens, token)
    }

    {rb2, effects} =
      case res do
        {:effects, effs} ->
          apply_effects(rb_with_token, effs)

        %{} = new_ctx when is_map(new_ctx) ->
          apply_effects(rb_with_token, Map.get(new_ctx, :effects, []))

        other ->
          apply_effects(rb_with_token, List.wrap(other))
      end

  duration = System.monotonic_time() - start
  RuleBook.Telemetry.exec([:rule_book, :activation, :fire], %{duration: duration}, %{rule: name, effects: length(effects)})
  {rb2, effects}
  end

  defp do_action({m, f, a}, ctx), do: apply(m, f, [ctx | a])
  defp do_action(fun, ctx) when is_function(fun, 1), do: fun.(ctx)

  @doc false
  defp apply_effects(rb, effects) do
    Enum.reduce(effects, {rb, []}, fn eff, {acc_rb, acc_effs} ->
      case eff do
        {:assert, fact} ->
          RuleBook.Telemetry.exec([:rule_book, :effect, :assert], %{}, %{})
          {RuleBook.assert(acc_rb, fact), [eff | acc_effs]}
        {:retract, id_or_fact} ->
          RuleBook.Telemetry.exec([:rule_book, :effect, :retract], %{}, %{})
          {RuleBook.retract(acc_rb, id_or_fact), [eff | acc_effs]}
        {:emit, name, payload} -> {acc_rb, [{:emit, name, payload} | acc_effs]}
        {:log, _lvl, _msg} -> {acc_rb, [eff | acc_effs]}
        _ -> {acc_rb, acc_effs}
      end
    end)
  end
end
