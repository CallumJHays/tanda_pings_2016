defmodule Pings.Service.Database do
  @moduledoc """
  Implements a server pool of database connections to allow for multiple
  concurrent database connections.

  This module is designed to be used as a singleton object throughout client-
  serving processes in the application, and called globally.
  """

  @__DB_POOL_NAME__ Pings.Pool.DatabasePool
  @__POOL_SIZE__ 10

  @doc """
  Starts a link with the database service, initializing the database server
  pool and authenticating all connections.
  """
  def start_link do
    Pings.Pool.start_link(
      @__DB_POOL_NAME__,
      [
        server: Pings.Server.Database, 
        size: @__POOL_SIZE__, 
        server_opts: [
          # parametize queries with inputs to prevent sql injection
          prepare_plans: [
            "PREPARE ping (varchar(40), bigint) AS 
              INSERT INTO pings VALUES ($1, $2);",

            "PREPARE all_pings_between_times (bigint, bigint) AS 
              SELECT device_id, epoch_time FROM pings 
              WHERE (epoch_time BETWEEN $1 AND $2);",

            "PREPARE device_pings_between_times (varchar(40), bigint, bigint) 
              AS SELECT epoch_time FROM pings 
              WHERE (device_id = $1 AND epoch_time BETWEEN $2 AND $3);"
          ]
        ]
      ]
    )
  end

  @doc """
  Runs a command in the database.
  """
  def query(sql) do
    Pings.Pool.call(@__DB_POOL_NAME__, {:query, sql})
  end
end