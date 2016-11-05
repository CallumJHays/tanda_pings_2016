defmodule Pings.Router do
  @moduledoc """
  Route Pings.HTTPRequests to their correct controller
  """

  @doc """
  Routes a request to it's correct controller.
  Returns the response from that controller.
  """
  def route_and_get_response(req) do
    import Pings.Macro.Route
    alias Pings.Controller.Devices, as: Devices

    valid_methods = [:GET, :POST, :DELETE, :PUT]
    unless Enum.member?(valid_methods, req.method),
      do: raise "HTTP request does not have a valid method"

    # Note: The order in which these route cases are defined in the
    # block below MATTERS. The route keyword is implemented as a custom macro,
    # for mostly educational purposes, and compiles down to more native code
    # at compile time. Please see Pings.Macro.Route in macros/route.ex
    # for more information if you want to check it out.
    # it will always go along the route that it first matches
    # Modifies the request, by extracting uri parameters, and pipes
    # the new request into the first argument of the provided function.

    # TODO: Add support for regex patterns and named captures as well
    route req do
      GET: "/all/:date"               -> Devices.get_all_pings_on_day
      GET: "/all/:from/:to"           -> Devices.get_all_pings_between_times
      GET: "/devices"                 -> Devices.get_all_devices
      GET: "/:device_id/:date"        -> Devices.get_device_pings_on_day
      GET: "/:device_id/:from/:to"    -> Devices.get_device_pings_between_times
      POST: "/clear_data"             -> Devices.remove_all_devices_and_pings
      POST: "/:device_id/:epoch_time" -> Devices.ping
      :not_found                      -> not_found_response # fallback to 404
    end
  end

  defp not_found_response(req) do
    %Pings.Struct.HTTPResponse{
      status_code: 404,
      content_type: :html,
      body: "#{req.method} #{req.uri} Not found"
    }
  end
end
