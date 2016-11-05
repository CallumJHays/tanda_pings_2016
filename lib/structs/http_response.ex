defmodule Pings.Struct.HTTPResponse do
  @moduledoc """
  A light-weight and simplified HTTP Response object to be passed around
  relevant controllers in the application
  """
  defstruct([
    status_code: nil, 
    content_type: nil, 
    body: nil,
    encoding: nil
  ])
end

# Implement the String.Chars protocol to encode the struct in http easily
defimpl String.Chars, for: Pings.Struct.HTTPResponse do
  def to_string(res) do
    status_code_reason =
      case res.status_code do
        200 -> "OK"
        201 -> "Created"
        202 -> "Accepted"
        204 -> "No Content"
        400 -> "Bad Request"
        403 -> "Forbidden"
        404 -> "Not Found"
        500 -> "Internal Server Error"
      end

    content_type =
      case res.content_type do
        :json -> "application/json"
        :html -> "text/html"
        nil -> "text/html"
      end

    res = 
      if res.body |> is_nil,
        do: %{res | body: ""},
        else: res

    content_encoding_header =
      if res.encoding == nil,
        do: "",
        else: "\nContent-Encoding: #{res.encoding}"

    """
    HTTP/1.1 #{res.status_code} #{status_code_reason}#{content_encoding_header}
    Content-Length: #{byte_size(res.body)}
    Content-Type: #{content_type}

    #{res.body}
    """
  end
end