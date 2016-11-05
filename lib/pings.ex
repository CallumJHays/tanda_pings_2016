defmodule Pings do
  use Application
  require Logger
  @moduledoc """
  The base of the application. Supervises database connection and  the logger
  """

  @doc """
  Application start callback.
  Where the boilerplate ends and the code begins.
  """
  def start(_type, _args) do
    # import statements are scoped in elixir. Functions within the
    # Supervisor.Spec module will be accessable without calling it from the
    # module directly, but only within the scope of this function
    import Supervisor.Spec

    IO.puts("Starting Pings")

    # The root of our supervisor tree
    children = [
      # A dynamic supervisor for tasks. Usedto keep track of the server
      # request/response loop Task
      supervisor(Task.Supervisor, [[name: Pings.TaskSupervisor]]),
      # Start the database server pool
      worker(Pings.Service.Database, []),
      # Server request/response loop Task. Runs concurrently to this process.
      # telling it to run the accept function in the Pings module
      worker(Task, [Pings, :accept, [3000]])
    ]

    # the one_for_one strategy restarts a process from scratch
    # every time it crashes
    opts = [strategy: :one_for_one, name: Pings.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Begins the request/response loop on the provided port
  """
  def accept(port) do
    IO.puts("Setting up socket connection acceptor on port #{port}")
    # TODO: change reuseaddr here
    {:ok, socket} = :gen_tcp.listen(port,
                      [:list, packet: :http, active: false, reuseaddr: true])
    loop_acceptor(socket)
  end

  # Recursively accept new connections for clients over the supplied socket.
  # Elixir implements tail call optimization to prevent the stack from growing
  # too large with infinite recursion
  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    # get our head supervisor to oversee a seperate concurrent task
    # serving the client
    {:ok, pid} = Task.Supervisor.start_child(
      Pings.TaskSupervisor, fn -> serve(client) end)
    # let :gen_tcp know all process messages should be directed toward pid
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  # Intepret requests from the socket as they come in recursively
  defp serve(socket) do
    req = get_request(socket)

    IO.puts("#{req.method} #{req.uri}")
    res = 
      try do
        Pings.Router.route_and_get_response(req)
      rescue
        # internal server error
        _ -> %Pings.Struct.HTTPResponse{status_code: 500}
      end

    if res != nil do
      send_response(socket, res, req.headers[:"Accept-Encoding"])
    end

    :gen_tcp.close(socket)
    exit(:normal)
  end

  defp send_response(socket, res, formats) do
    res =
      if res.body != nil and formats != nil do
        formats = formats |> to_string
        # Only support gzip
        {compressed, encoding} =
          cond do
            formats |> String.contains?("gzip") ->
              {:zlib.gzip(res.body), "gzip"}
            :fallback -> {res.body, "none"}
          end

        # check that the compressed payload is smaller than the original
        if compressed && byte_size(compressed) < byte_size(res.body),
          do: %{res | encoding: encoding, body: compressed},
          else: res
      else
        res
      end

    packet = res |> String.Chars.to_string
    :gen_tcp.send(socket, packet)
  end

  # populate a request struct
  # NOTE: Does not currently include request body (Form data, cookies)
  defp get_request(socket) do
    req = get_request_loop(socket, [])

    # extract and format http headers
    headers =
      req
      |> Enum.filter(fn(req_line) -> elem(req_line, 0) == :http_header end)
      |> Enum.map(fn(req_header) ->
            {:http_header, _, key, _, value} = req_header
            {key, value}
        end)
    # extract request method and URL for the router
    {_, method, {:abs_path, url}, _} =
      Enum.find(req, &(elem(&1, 0) == :http_request))

    # convert URL to URI + query string keyword list
    [uri | regex_result] = url |> String.Chars.to_string |> String.split("?")

    # generate a keyword list from the query string
    query = get_query_keyword_list(regex_result)

    %Pings.Struct.HTTPRequest{
      method: method,
      uri: uri,
      headers: headers,
      params: [], # params will be generated (if applicable) by the router
      query: query
    }
  end

  # converts query array (regex result) in the form of [query_str]
  # to keyword list.
  # In retrospect, Elixir had a function for this inbuilt,
  # http://elixir-lang.org/docs/stable/elixir/URI.html
  defp get_query_keyword_list(regex_result) do
    if Enum.empty?(regex_result) do
      []
    else
      [query_str] = regex_result
      query_str
      |> String.split("&")
      |> Enum.map(fn(constraint) ->
        [key, val_str] = String.split(constraint, "=")
        val =
          if String.contains?(val_str, ",") do
            String.split(val_str, ",")
          else
            val_str
          end
        {String.to_atom(key), val}
      end)
    end
  end

  # recursively populate a request object until end of header
  defp get_request_loop(socket, request) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} -> request
      {:ok, packet} -> get_request_loop(socket, [packet | request])
      {:error, :closed} -> exit(:shutdown)
      {:error, reason} -> exit(reason)
    end
  end
end
