defmodule EventManagerWeb.Resolvers.Events do
  @moduledoc """
    Resolvers for Event objects and related queries
  """

  alias Absinthe.Relay.Connection
  alias EventManager.Events
  alias EventManager.Users
  alias Phoenix.PubSub

  import EventManagerWeb.Gettext

  @items_per_page Application.get_env(:event_manager, :pagination, []) |> Keyword.get(:items_per_page, 25)
  @max_per_page Application.get_env(:event_manager, :pagination, []) |> Keyword.get(:max_per_page, 50)

  def get_event(params, _info) do
    do_get_event(params, &Events.get_event/1)
  end

  def events(%{before: _before, first: _first} = args, _info), do: {:error, dgettext("errors", "`before` can only be paired with `last`")}
  def events(%{after: _before, last: _last} = args, _info), do: {:error, dgettext("errors", "`after` can only be paired with `first`")}
  def events(%{before: _before} = args, info), do: Map.put_new(args, :last, @items_per_page) |> do_events()
  def events(%{after: _after} = args, info), do: Map.put_new(args, :first, @items_per_page) |> do_events()
  def events(args, _info), do: {:error, dgettext("errors", "unexpected pagination arguments: %{args}", args: args)}

  defp do_events(args) do
    {:ok, offset, limit} = Connection.offset_and_limit_for_query(args, max: @items_per_page)
    Events.list_events(limit, offset)
    |> Connection.from_slice(offset)
  end

  @spec create_event(
          %{event: :invalid | %{optional(:__struct__) => none, optional(atom | binary) => any}},
          any
        ) :: {:error, any} | {:ok, any}
  def create_event(_args, %{context: %{current_user: nil}}) do
    {:error, dgettext("errors", "unauthorized")}
  end

  def create_event(%{event: event}, %{context: %{current_user: current_user}}) do
    case Map.put(event, :status, :draft)
         |> Map.put(:creator, current_user)
         |> Events.create_event() do
      {:ok, created} ->
        created |> Ecto.assoc(:creator)
        PubSub.broadcast(EventManager.PubSub, "event:created", {:event_created, created})
        {:ok, created}

      {:error, changeset} ->
        {:error, changeset.errors}
    end
  end

  @spec delete_event(
          %{event: :invalid | %{optional(:__struct__) => none, optional(atom | binary) => any}},
          any
        ) :: {:error, any} | {:ok, any}
  def delete_event(_args, %{context: %{current_user: nil}}) do
    {:error, dgettext("errors", "unauthorized")}
  end

  def delete_event(params, %{context: %{current_user: current_user}}) do
    with {:ok, event} <- do_get_event(params, &Users.get_created_event(current_user, &1)),
         {:ok, deleted} <- do_delete(event) do
      {:ok, deleted}
    else
      {:error, errors} -> {:error, errors}
    end
  end

  def event_creator(event, _, _) do
    creator = EventManager.Events.get_event_creator(event)
    {:ok, creator}
  end

  defp do_delete(%Events.Event{status: :draft} = event) do
    case Events.delete_event(event) do
      {:ok, deleted} -> {:ok, deleted}
      {:error, changeset} -> {:error, changeset.errors}
    end
  end

  defp do_delete(%Events.Event{status: status}),
    do:
      {:error,
       dgettext("errors", "only drafted events can be deleted. Current status: %{status}",
         status: status
       )}

  defp do_get_event(%{id: ""}, _) do
    {:error, "event.not_found"}
  end

  #  @spec do_get_event(Map.t(), )
  defp do_get_event(%{id: id}, get_fun) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         event when not is_nil(event) <- get_fun.(uuid) do
      {:ok, event}
    else
      _ -> {:error, dgettext("errors", "event not found by id %{id}", id: id)}
    end
  end
end
