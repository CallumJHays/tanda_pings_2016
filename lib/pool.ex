defmodule Pings.Pool do
  use GenServer
  @moduledoc """
  Module for managing a pool of servers
  """

  # CLIENT INTERFACE

  @doc """
  Starts the thread pool and configures strategies.
  # Possible options are:
  :size: The number of workers in the pool
  :server: The module that should be thread pooled
  :server_opts: Keyword list of options to be passed to each pooled server.
  """
  def start_link(name, opts) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Calls the first free server in the pool it can find with a message.
  """
  def call(pool, message) do
    perform_server_action(pool, fn(server) ->
      GenServer.call(server, message, :infinity)
    end)
  end

  @doc """
  Casts a message to the first free server in the pool
  """
  def cast(pool, message) do
    perform_server_action(pool, fn(server) ->
      GenServer.cast(server, message)
    end)
  end

  # obfuscates searching for an idle server and pool interface
  defp perform_server_action(pool, action) do
    # Get an idle server
    server =
      case GenServer.call(pool, :request_server) do
        nil -> # server could not be found, wait for turn in queue
          receive do {:server, server} -> server end
        server -> server
      end
    # perform an action with the server
    reply = action.(server)
    # let the pool know the server is now idle
    GenServer.cast(pool, {:status_update, :idle, server})
    reply # return reply to client
  end

  # SERVER CALLBACKS

  def init(state) do
    size = state[:size] || 1

    # dynamically construct and monitor workers
    workers = 
      for _ <- 1..size do
        start_new_server(state[:server], state[:server_opts])
      end

    # map server process id to server status
    servers_status =
      Enum.reduce(workers, %{}, fn(worker, map) ->
        Map.put(map, worker, :idle)
      end)

    state =
      state
      |> Enum.into(%{})
      |> Map.put(:servers_status, servers_status)
      |> Map.put(:queue, [])

    {:ok, state}
  end

  defp start_new_server(server, opts) do
    {:ok, pid} = server.start(opts)
    Process.monitor(pid)
    pid
  end

  # callback for when a server encounters an error and crashes
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # start another server in its place
    new_pid = start_new_server(state.server, state.server_opts || [])

    # remove the dead process from the servers_status and add new one
    servers_status =
      state.servers_status
      |> Map.delete(pid) # remove it from the map
      |> Map.put(new_pid, :idle)

    {:noreply, %{state | servers_status: servers_status}}
  end

  # finds an idle server for a client if one exists.
  def handle_call(:request_server, {client, _}, state) do
    case find_idle_server(state.servers_status) do
      nil ->
        queue = List.insert_at(state.queue, -1, client)
        {:reply, nil, %{state | queue: queue}}

      server ->
        # the client will now be using the server. Set status to busy.
        state = put_in(state, [:servers_status, server], :busy)
        {:reply, server, state}
    end
  end

  def handle_cast({:status_update, new_status, server}, state) do
    if not Enum.empty?(state.queue) and new_status == :idle do
      [client | queue] = state.queue # get the client at the front of the queue
      send(client, {:server, server}) # send the database server to the client
      {:noreply, %{state | queue: queue}} # updates the state with the new queue
    else
      state = put_in(state, [:servers_status, server], new_status)
      {:noreply, state}
    end
  end

  defp find_idle_server(servers_status) do
    server =
      Enum.find(servers_status, fn({_pid, status}) -> status == :idle end)
    if server == nil do
      nil
    else
      {pid, status} = server
      pid
    end
  end
end
