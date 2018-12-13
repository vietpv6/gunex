defmodule GunEx do
  # defp get_response(connPid, sRef, data \\ %{}) do
  #   receive do
  #     {:gun_response, ^connPid, ^sRef, :fin, status, header} ->
  #       m = %{status: status, header: header, body: ""}
  #       Map.merge(data, m)
  #     {:gun_response, ^connPid, ^sRef, :nofin, status, header} ->
  #       IO.inspect(header)
  #       m = %{status: status, header: header}
  #       get_response(connPid, sRef, Map.merge(data, m))
  #     {:gun_data, ^connPid, ^sRef, :nofin, msg} ->
  #       IO.inspect(msg)
  #       body = Map.get(data, :body, "") <> msg
  #       get_response(connPid, sRef, Map.put(data, :body, body))
  #     {:gun_data, ^connPid, ^sRef, :fin, msg} ->
  #       IO.inspect(msg)
  #       :gun.close(connPid)
  #       body = Map.get(data, :body, "") <> msg
  #       Map.put(data, :body, body)
  #     error ->
  #       IO.inspect(error)
  #       :gun.close(connPid)
  #       data
  #   end

  # end

  defp connect(uri, options) do
    proxy =
      case :proplists.get_value(:proxy, options) do
        url when is_binary(url) ->
          proxy = URI.parse(url)
          {proxy.host, proxy.port}
        {proxyhost, proxyport} ->
          {proxyhost, proxyport}
        {:socks5, proxyhost, proxyport} ->
          {proxyhost, proxyport}
        {:connect, proxyhost, proxyport} ->
          {proxyhost, proxyport}
        _ -> nil
      end
    {host, port} =
      case proxy do
        nil ->
          {:erlang.binary_to_list(uri.host), uri.port}
        {proxy_host, proxy_port} when is_tuple(proxy_host) ->
          proxy_host = Enum.join(:erlang.tuple_to_list(proxy_host), ".") |> :erlang.binary_to_list
          {proxy_host, proxy_port}
        {proxy_host, proxy_port} when is_binary(proxy_host) ->
          {:erlang.binary_to_list(proxy_host), proxy_port}
        {proxy_host, proxy_port} ->
          {proxy_host, proxy_port}
      end
    {:ok, p} = :gun.open(host, port)
    try do
      {:ok, _} = :gun.await_up(p)
      if proxy != nil do
        transport = if uri.scheme == "https", do: :tls, else: :tcp
        streamRef =
          case :proplists.get_value(:proxy_auth, options) do
            :undefined -> :gun.connect(p, %{host: uri.host, port: uri.port, transport: transport})
            {user, pass} -> :gun.connect(p, %{host: uri.host, port: uri.port, username: user, password: pass, transport: transport})
          end
        {:response, :fin, 200, _} = :gun.await(p, streamRef)
        :gun.flush(streamRef)
      end
      p
    catch
      _, reason ->
        :gun.close(p)
        throw({:change_ip, reason})
    end
  end

  def http_get(url, header, body, options) do
    uri = URI.parse(url)
    connPid = connect(uri, options)
    path =
      case uri.path do
        nil -> '/'
        path -> :erlang.binary_to_list(path)
      end
    sref = :gun.request(connPid, "GET", path, header, body)
    resp =
      case :gun.await(connPid, sref) do
        {:response, :fin, status, header} ->
          %{status: status, headers: header, body: ""}
        {:response, :nofin, status, header} ->
          {:ok, body} = :gun.await_body(connPid, sref)
          body =
            case :proplists.get_value("content-encoding", header) do
              "gzip" -> :zlib.gunzip(body)
              _ -> body
            end
          %{status: status, headers: header, body: body}
        {:error, err} ->
          {:error, err}
      end
    :gun.flush(sref)
    :gun.close(connPid)
    resp
  end

  # def test() do
  #   {:ok, connPid} = :gun.open('96.9.77.157', 48776)
  #   {:ok, _http} = :gun.await_up(connPid)
  #   streamRef = :gun.connect(connPid, %{
  #       host: "canyouseeme.org",
  #       port: 80
  #   })
  #   IO.inspect(streamRef)
  #   {:response, :fin, 200, _} = :gun.await(connPid, streamRef)
  #   :gun.flush(streamRef)
  #   streamRef = :gun.request(connPid, "GET", "/", [])
  #   case :gun.await(connPid, streamRef) do
  #     {:response, :fin, status, header} ->
  #       :gun.close(connPid)
  #       %{status: status, header: header, body: ""}
  #     {:response, :nofin, status, header} ->
  #       {:ok, body} = :gun.await_body(connPid, streamRef)
  #       :gun.close(connPid)
  #       %{status: status, header: header, body: body}
  #   end
  # end
end
