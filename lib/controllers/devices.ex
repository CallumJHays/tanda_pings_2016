defmodule Pings.Controller.Devices do
  alias Pings.Struct.HTTPResponse, as: Res
  alias Pings.Service.Database, as: DB
  import Pings.Util.JSONEncoder
  @moduledoc """
  A controller for serving information related to devices.
  """

  @__gregorian_to_unix_offset__ -62_167_219_200
  @__seconds_in_a_day__ 86_400

  @__STATUS_OK__ 200
  @__STATUS_BADARG__ 400
  
  defp json_encode_response(data) do
    %Res{
      status_code: @__STATUS_OK__, 
      content_type: :json, 
      body: json_encode(data)
    }
  end

  @doc """
  Adds an epoch time ping registry to devices
  """
  def ping(req) do
    res = DB.query("EXECUTE ping('#{req.params[:device_id]}',#{req.params[:epoch_time]})")
    if res[:error] == nil,
      do: %Res{status_code: @__STATUS_OK__},
      else: %Res{status_code: @__STATUS_BADARG__}
  end

  @doc """
  Gets all pings occuring on a day
  """
  def get_all_pings_on_day(req) do
    device_pings_map = 
      get_device_pings_map_between_times(
        req.params[:date], 
        req.params[:date],
        true
      )

    json_encode_response(device_pings_map)
  end

  @doc """
  Gets all pings occuring between two times
  """
  def get_all_pings_between_times(req) do
    device_pings_map = 
      get_device_pings_map_between_times(req.params[:from], req.params[:to])

    json_encode_response(device_pings_map)
  end

  @doc """
  Get all devices
  """
  def get_all_devices(_req) do
    result = DB.query("SELECT DISTINCT device_id FROM pings")
    device_ids = 
      if result[:rows] != nil,
        do: Enum.map(result[:rows], fn(device) -> elem(device, 0) end),
        else: []
    json_encode_response(device_ids)
  end

  @doc """
  Gets all pings from a device that occurred on the supplied date
  """
  def get_device_pings_on_day(req) do
    device_pings_map = 
      get_device_pings_map_between_times(
        req.params[:date], 
        req.params[:date],
        true,
        req.params[:device_id]
      )
    
    json_encode_response(device_pings_map)
  end

  @doc """
  Gets all pings from a device between two times
  """
  def get_device_pings_between_times(req) do
    device_pings_map =
      get_device_pings_map_between_times(
        req.params[:from],
        req.params[:to],
        false,
        req.params[:device_id]
      )

    json_encode_response(device_pings_map)
  end

  @doc """
  Removes all the devices and pings
  """
  def remove_all_devices_and_pings(_req) do
    res = DB.query("DELETE FROM pings *")
    if res[:error] == nil,
      do: %Res{status_code: @__STATUS_OK__},
      else: %Res{status_code: @__STATUS_BADARG__}
  end

  # Private functions

  @spec get_device_pings_map_between_times(integer | String.t(), integer | String.t(), String.t()) :: map
  defp get_device_pings_map_between_times(from, to, same_date \\ false, device_id \\ nil) do
    time_from_epoch = to_epoch(from) # inclusive
    time_to_epoch = to_epoch(to, same_date) - 1 # exclusive

    sql = 
      if device_id == nil,
        do: "EXECUTE all_pings_between_times(#{time_from_epoch},#{time_to_epoch});",
        else: "EXECUTE device_pings_between_times('#{device_id}',#{time_from_epoch},#{time_to_epoch});"

    res = DB.query(sql)

    if res[:rows] !== nil do
      if device_id !== nil do # if a single device was specified
        Enum.map(res[:rows], fn(ping) -> elem(ping, 0) end)
      else
        Enum.reduce(res[:rows], %{}, fn(ping, map) ->
          # ping data in the form of {device_id, epoch_time}
          {device_id, epoch_time} = ping
          if map[device_id] === nil,
            do: Map.put(map, device_id, [epoch_time]),
            else: Map.put(map, device_id, [epoch_time | map[device_id]])
        end)
      end
    else
      %{}
    end
  end
  
  defp date_to_epoch(date, add_a_day) do
    date
    |> (fn(date) -> 
          {:ok, date_time} = NaiveDateTime.new(date, ~T[00:00:00])
          date_time
        end).()
    |> NaiveDateTime.to_erl
    |> :calendar.datetime_to_gregorian_seconds
    |> (fn(greg_secs) -> 
          greg_secs = 
            if add_a_day,
              do: greg_secs + @__seconds_in_a_day__,
              else: greg_secs
          greg_secs + @__gregorian_to_unix_offset__
        end).()
  end

  @spec to_epoch(integer | String.t(), boolean) :: integer
  defp to_epoch(time, add_a_day_if_date \\ false) do
    case Date.from_iso8601(time) do
      {:ok, date} -> date_to_epoch(date, add_a_day_if_date)
      {:error, _} ->
        {epoch, leftover} = Integer.parse(time)
        if leftover == "",
          do: epoch,
          else: raise(ArgumentError, "Time is neither an ISO date or an epoch")
    end
  end
end
