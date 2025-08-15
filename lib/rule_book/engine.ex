defmodule RuleBook.Engine do
  @moduledoc false
  alias RuleBook.Types

  defmodule Memory do
    @moduledoc false
    defstruct seq: 0, by_id: %{}, index: %{}
    @type t :: %__MODULE__{seq: non_neg_integer(), by_id: map(), index: map()}

    def new, do: %__MODULE__{}

    def facts(%__MODULE__{by_id: by_id}), do: Map.values(by_id)

    def assert(%__MODULE__{} = m, fact) do
      id = fact_id(fact)

      if Map.has_key?(m.by_id, id) do
        {m, []}
      else
        m = put_fact(m, id, fact)
        {m, [id]}
      end
    end

    def upsert(%__MODULE__{} = m, fact) do
      id = fact_id(fact)

      case Map.fetch(m.by_id, id) do
        {:ok, existing} ->
          if existing == fact do
            {m, []}
          else
            m = put_fact(m, id, fact)
            {m, [id]}
          end

        :error ->
          m = put_fact(m, id, fact)
          {m, [id]}
      end
    end

    def retract(%__MODULE__{} = m, id) when is_integer(id) or is_binary(id) or is_atom(id) do
      if Map.has_key?(m.by_id, id) do
        m = %__MODULE__{m | by_id: Map.delete(m.by_id, id)}
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
  def build_agenda(rules, %Memory{} = memory, tokens, changed_ids, options) do
    facts = Memory.facts(memory)

    rules
    |> Enum.flat_map(fn %Types.Rule{} = rule ->
      match_rule(rule, facts)
      |> Enum.map(fn bindings ->
        %{rule: rule.name, bindings: bindings, salience: rule.salience}
      end)
    end)
    |> apply_conflict_resolution(options)
  end

  defp match_rule(%Types.Rule{patterns: patterns}, facts) do
    # naive AND across patterns where each pattern must match at least one fact
    Enum.reduce(patterns, [%{}], fn %Types.Pattern{matcher: m}, acc ->
      for b <- acc, f <- facts, reduce: [] do
        bs ->
          case m.(f) do
            {:ok, b2} -> [Map.merge(b, b2) | bs]
            :nomatch -> bs
          end
      end
    end)
  end

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
    rule = Enum.find(rules, &(&1.name == name))
    ctx = %{rb: rb, binding: bindings, effects: []}
    res = do_action(rule.action, ctx)

    {rb2, effects} =
      case res do
        {:effects, effs} -> apply_effects(rb, effs)
        %{} = new_ctx when is_map(new_ctx) -> apply_effects(rb, Map.get(new_ctx, :effects, []))
        other -> apply_effects(rb, List.wrap(other))
      end

    {rb2, effects}
  end

  defp do_action({m, f, a}, ctx), do: apply(m, f, [ctx | a])
  defp do_action(fun, ctx) when is_function(fun, 1), do: fun.(ctx)

  defp apply_effects(rb, effects) do
    Enum.reduce(effects, {rb, []}, fn eff, {acc_rb, acc_effs} ->
      case eff do
        {:assert, fact} -> {RuleBook.assert(acc_rb, fact), [eff | acc_effs]}
        {:retract, id_or_fact} -> {RuleBook.retract(acc_rb, id_or_fact), [eff | acc_effs]}
        {:emit, name, payload} -> {acc_rb, [{:emit, name, payload} | acc_effs]}
        {:log, _lvl, _msg} -> {acc_rb, [eff | acc_effs]}
        _ -> {acc_rb, acc_effs}
      end
    end)
  end
end
