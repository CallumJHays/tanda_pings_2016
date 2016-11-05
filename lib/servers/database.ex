defmodule Pings.Server.Database do
  use GenServer
  require Logger
  @moduledoc ~S"""
  A module for interfacing with the database.
  Designed to be implemented as a part of a server pool.
  See `Pings.Service.Database` for simplified usage.
  
  Message protocols used for database interface are described here:
  https://www.postgresql.org/docs/9.5/static/protocol-message-formats.html
  """

  # Postgresql protocol codes, compile-time constants
  @__STARTUP__ ""
  @__RESPONSE__ "R"
  @__PASSWORD__ "p"
  @__QUERY__ "Q"

  @doc """
  client initialization function

  Possible options:
  :prepare_plans => List of bitstrings of prepare statements to send to postgresql
  """
  def start(opts \\ []) do
    GenServer.start(__MODULE__, opts, opts)
  end

  @doc """
  GenServer initial callback to define initial state
  """
  def init(opts) do
    plans = opts[:prepare_plans] || []
    socket = connect_and_auth(plans)
    {:ok, socket}
  end

  defp connect_and_auth(plans) do
    db = Application.fetch_env!(:pings, :database_conn)
    db = Map.put(db, :socket, nil)
    connect_and_auth(db, plans)
  end

  defp connect_and_auth(db, plans) do
    # begin a connection to the database
    opts = [:binary, active: false]
    {:ok, socket} = :gen_tcp.connect(db.host, db.port, opts)
    db = %{db | socket: socket}
    salt = init_contact_and_get_salt(db)
    :ok = auth_connection(db, salt)
    prepare(socket, plans)
    IO.puts("New database connection ready!")
    socket
  end

  defp init_contact_and_get_salt(db) do
    # initiate start message handshake authentication
    ## startup message
    ### protocol version number, 16 bits -> major, 16 bits -> minor
    major = 3
    minor = 0
    version = <<major :: size(16), minor :: size(16)>>

    # null terminator
    nt = <<0>>
    ### connection parameters as per spec
    params = "user" <> nt <> db.username <> nt <>
             "database" <> nt <> db.dbname <> nt

    setup_message = version <> params
    # assert that the response is a md5 password request, providing salt
    res = converse(db.socket, @__STARTUP__, setup_message)
    <<@__RESPONSE__, 12 :: size(32), 5:: size(32), salt :: binary>> = res
    salt
  end

  # pipe-able hash function 
  defp hash_n_salt_pass(pass, salt) do
    :crypto.hash(:md5, pass <> salt)
    |> Base.encode16
    |> String.downcase
  end

  defp auth_connection(db, salt) do
    # password hashing as described in 
    # https://www.postgresql.org/docs/9.2/static/protocol-flow.html
    # append username as pepper first, hash,
    # then append salt, then prepend "md5"
    hashed_password =
      db.password
      |> hash_n_salt_pass(db.username) # pepper n hash with username
      |> hash_n_salt_pass(salt) # salt n hash
      |> (fn(pass) -> "md5" <> pass end).() # append md5

    # authenticate, then
    # assert that the authentication was OK and discard login message
    <<@__RESPONSE__, _rest :: binary>> = converse(db.socket, @__PASSWORD__, hashed_password)
    :ok
  end

  defp prepare(socket, plans) do
    Enum.each(plans, fn(plan) ->
      <<"C", _ :: binary>> = converse(socket, @__QUERY__, plan)
    end)
  end

  def handle_call({:query, sql}, _from, socket) do
    result = converse(socket, @__QUERY__, sql)
    result = Pings.Util.SQLParser.parse_query_res(socket, result)
    {:reply, result, socket}
  end

  # sends a message, waits and returns the result from the server
  defp converse(socket, type, message) do
    send_message(socket, type, message)
    {:ok, res} = :gen_tcp.recv(socket, 0)
    res
  end

  defp send_message(socket, type, message) do
    # + 5 because includes itself, which is 4 bytes + null terminator
    checksum = byte_size(message) + 5
    packet = type <> <<checksum :: size(32)>> <> message <> <<0>>

    :ok = :gen_tcp.send(socket, packet)
  end
end