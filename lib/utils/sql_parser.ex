defmodule Pings.Util.SQLParser do
  require Logger
  @moduledoc """
  Parses SQL responses into an array of maps for each table row.
  Format parsed as the specification here:
  https://www.postgresql.org/docs/9.3/static/protocol-message-formats.html
  """

  # message types from database
  @__row_description__ "T"
  @__data_row__ "D"
  @__command_complete__ "C"
  @__error__ "E"
  @__ready_for_query__ "Z"

  # field types that the application uses
  # these were found by running the query
  # "SELECT (typname, oid) FROM pg_type WHERE 
  #   (typname = 'varchar' OR typname = 'int8')"
  @__varchar__ 1043
  @__int8__ 20

  @doc """
  Parses an sql result
  """
  @spec parse_query_res(port, binary) :: list(map)
  def parse_query_res(socket, data) do
    loop_get_messages(socket, data)
  end

  #-----------------------------------------------------------------------------
  #------------------------ PRIVATE FUNCTIONS ----------------------------------
  #-----------------------------------------------------------------------------

  defp loop_get_messages(socket, data, message_map \\ %{})

  defp loop_get_messages(_, "", message_map) do
    message_map
  end

  defp loop_get_messages(socket, data, message_map) do
    # all messages come in the form:
    # type: 1 byte char
    # msg_len: 32 bit signed integer
    # data: the payload with different formats for different messages
    # if there is a MatchError, try getting more data to complete the header
    {type, msg_len, data} = 
      try do
        <<
          type :: binary-size(1),
          msg_len :: signed-integer-size(32),
          data :: binary
        >> = data
        {type, msg_len, data}
      rescue
        MatchError -> 
          <<
            type :: binary-size(1),
            msg_len :: signed-integer-size(32),
            data :: binary
          >> = data <> get_more_data(socket)
          {type, msg_len, data}
      end

    data = 
      if byte_size(data) + 4 < msg_len do
        data <> get_more_data(socket)
      else
        data
      end
    
    {message_map, data} = parse_message(type, data, message_map)
    loop_get_messages(socket, data, message_map)
  end

  #-----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------

  defp parse_message(@__row_description__, data, message_map) do
    <<num_fields :: signed-integer-size(16), data :: binary>> = data
    {fields, data} = loop_get_fields(data, num_fields)
    {Map.put(message_map, :fields, fields), data}
  end

  defp parse_message(@__data_row__, data, message_map) do
    <<_ :: size(16), data :: binary>> = data
    {row, data} = loop_get_values(data, Enum.reverse(message_map[:fields]))
    rows = 
      if Map.has_key?(message_map, :rows),
        do: [row | message_map[:rows]],
        else: [row]
    {Map.put(message_map, :rows, rows), data}
  end

  defp parse_message(@__command_complete__, data, message_map) do
    [command_tag, data] = String.split(data, <<0>>, parts: 2)
    {Map.put(message_map, :command, command_tag), data}
  end

  defp parse_message(@__ready_for_query__, data, message_map) do
    <<status :: binary-size(1), data :: binary>> = data
    {Map.put(message_map, :status, status), data}
  end

  defp parse_message(@__error__, data, message_map) do
    <<type :: binary-size(1), data :: binary>> = data
    {Map.put(message_map, :error, type), data}
  end

  #-----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------

  defp loop_get_fields(data, fields_left, fields \\ [])
  
  defp loop_get_fields(data, 0, fields) do
    {fields, data}
  end

  defp loop_get_fields(data, fields_left, fields) do
    [field_name, data] = String.split(data, <<0>>, parts: 2)
    <<
      _ :: size(48), # don't need the first 48 bits
      field_type :: signed-integer-size(32),
      _ :: size(64), # or the last 64 bits
      data :: binary
    >> = data

    fields = [{String.to_atom(field_name), field_type} | fields]
    loop_get_fields(data, fields_left - 1, fields)
  end

  #-----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------

  defp loop_get_values(data, fields, values \\ {})

  defp loop_get_values(data, [], values) do
    {values, data}
  end

  defp loop_get_values(data, fields, values) do
    <<
      value_size :: signed-integer-size(32),
      value :: binary-size(value_size),
      data :: binary
    >> = data
    [{_field_name, field_type} | fields] = fields

    value = convert_binary_to_type(value, field_type)
    loop_get_values(data, fields, Tuple.append(values, value))
  end

  #-----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------

  defp convert_binary_to_type(bin, type) do
    case type do
      @__varchar__ ->
        bin
      @__int8__ ->
        # it is interesting to me that postgres chose to transport is_integer
        # data as a string of characters. Wouldn't this waste bandwidth?
        String.to_integer(bin)
      _ -> # unknown
        bin
    end
  end

  defp get_more_data(socket) do
    {:ok, packet} = :gen_tcp.recv(socket, 0)
    packet
  end
end