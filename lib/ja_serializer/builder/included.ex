defmodule JaSerializer.Builder.Included do
  @moduledoc false

  alias JaSerializer.Builder.ResourceObject

  def build(%{model: models} = context, primary_resources) when is_list(models) do
    do_build(models, context, [], List.wrap(primary_resources))
  end

  def build(context, primary_resources) do
    context
    |> Map.put(:model, [context.model])
    |> build(primary_resources)
  end

  defp do_build([], _context, included, _known_resources), do: included
  defp do_build([model | models], context, included, known) do
    context = Map.put(context, :model, model)

    new = context
          |> relationships_with_include
          |> Enum.flat_map(&resources_for_relationship(&1, context, included, known))
          |> Enum.uniq(&({&1.id, &1.type}))
          |> reject_known(included, known)

    # Call for next model
    do_build(models, context, (new ++ included), known)
  end

  defp resource_objects_for(models, conn, serializer) do
    ResourceObject.build(%{model: models, conn: conn, serializer: serializer})
    |> List.wrap
  end

  # Find relationships that should be included.
  defp relationships_with_include(context) do
    context.serializer.__relations
    # This filter is where we would test for opts[:include]
    # OR
    # opts[:optional_include] AND user specified this relationship should be included
    |> Enum.filter(fn({_t, _n, opts}) ->
      %{:serializer => serializer, :include => include} = normalize_relation_opts(opts, true)
      include == true
    end)
  end

  # Find resources for relationship & parent_context
  defp resources_for_relationship({_, name, opts}, context, included, known) do
    %{:serializer => serializer} = normalize_relation_opts(opts)
    new = apply(context.serializer, name, [context.model, context.conn])
          |> List.wrap
          |> resource_objects_for(context.conn, serializer)
          |> reject_known(included, known)

    child_context = Map.put(context, :serializer, serializer)

    new
    |> Enum.map(&(&1.model))
    |> do_build(child_context, (new ++ included), known)
  end

  defp reject_known(resources, included, primary) do
    Enum.reject(resources, &(&1 in included || &1 in primary))
  end

  defp normalize_relation_opts(opts, trigger_deprecation \\ false) do
    include = opts[:include]

    case is_boolean(include) or is_nil(include) do
      true -> %{serializer: opts[:serializer], include: opts[:include]}
      false ->
        if trigger_deprecation do
          IO.write :stderr, "[warning] specifying a non-boolean as the `include` " <>
            "option is deprecated.\n" <>
            "[warning] If you are specifying the serializer for this relation, " <> "
            use the new `serializer` option instead.\n" <>
            "[warning] To always side-load the relationship, provide the `include` " <>
            "option with a value of `true` in addition to `serializer.\n"
        end

        %{serializer: include, include: true}
    end
  end
end
