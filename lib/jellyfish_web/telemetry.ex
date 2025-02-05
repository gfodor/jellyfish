defmodule JellyfishWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics
  require Logger

  @ice_received_event [Membrane.ICE, :ice, :payload, :received]
  @ice_sent_event [Membrane.ICE, :ice, :payload, :sent]
  @http_request_event [:jellyfish_web, :request]
  @http_response_event [:jellyfish_web, :response]

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    metrics_ip = Application.fetch_env!(:jellyfish, :metrics_ip)
    metrics_port = Application.fetch_env!(:jellyfish, :metrics_port)

    Logger.info(
      "Starting prometheus metrics endpoint at: http://#{:inet.ntoa(metrics_ip)}:#{metrics_port}"
    )

    metrics_opts = [
      metrics: metrics(&last_value/2),
      port: metrics_port,
      plug_cowboy_opts: [ip: metrics_ip]
    ]

    children = [{TelemetryMetricsPrometheus, metrics_opts}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Phoenix by default uses the `summary` metric type in `LiveDashboard`,
  # but `TelemetryMetricsPrometheus` doesn't support it, so we have to use `last_value` instead.
  #
  # The metrics, events and measurements are named according to the Prometheus guidelines.
  # For more information, refer to these links:
  #   - https://prometheus.io/docs/practices/naming/
  #   - https://hexdocs.pm/telemetry_metrics_prometheus_core/1.0.0/TelemetryMetricsPrometheus.Core.html#module-naming
  def metrics(metric_type \\ &summary/2) do
    [
      # Phoenix Metrics
      metric_type.("phoenix.endpoint.start.system_time.seconds",
        event_name: [:phoenix, :endpoint, :start],
        measurement: :system_time,
        unit: {:native, :second}
      ),
      metric_type.("phoenix.endpoint.stop.duration.seconds",
        event_name: [:phoenix, :endpoint, :stop],
        measurement: :duration,
        unit: {:native, :second}
      ),
      metric_type.("phoenix.router_dispatch.start.system_time.seconds",
        event_name: [:phoenix, :router_dispatch, :start],
        measurement: :system_time,
        tags: [:route],
        unit: {:native, :second}
      ),
      metric_type.("phoenix.router_dispatch.exception.duration.seconds",
        event_name: [:phoenix, :router_dispatch, :exception],
        measurement: :duration,
        tags: [:route],
        unit: {:native, :second}
      ),
      metric_type.("phoenix.router_dispatch.stop.duration.seconds",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        tags: [:route],
        unit: {:native, :second}
      ),
      metric_type.("phoenix.socket_connected.duration.seconds",
        event_name: [:phoenix, :socket_connected],
        measurement: :duration,
        unit: {:native, :second}
      ),
      metric_type.("phoenix.channel_join.duration.seconds",
        event_name: [:phoenix, :channel_join],
        measurement: :duration,
        unit: {:native, :second}
      ),
      metric_type.("phoenix.channel_handled_in.duration.seconds",
        event_name: [:phoenix, :channel_handled_in],
        measurement: :duration,
        tags: [:event],
        unit: {:native, :second}
      ),

      # VM Metrics
      metric_type.("vm.memory.total.bytes",
        event_name: [:vm, :memory],
        measurement: :total
      ),
      metric_type.("vm.total_run_queue_lengths.total", []),
      metric_type.("vm.total_run_queue_lengths.cpu", []),
      metric_type.("vm.total_run_queue_lengths.io", [])
    ] ++
      [
        # Jellyfish Metrics

        # FIXME: At the moment, the traffic metrics track:
        #   - Most HTTP traffic (Jellyfish API, HLS)
        #   - ICE events (WebRTC)
        #
        # which means they don't count:
        #   - WebSocket traffic
        #   - RTP events (RTSP components don't use ICE)
        #   - HTTP traffic related to metrics (not handled by Phoenix)
        sum("jellyfish.traffic.ingress.webrtc.total.bytes",
          event_name: @ice_received_event,
          description: "Total WebRTC traffic received (bytes)"
        ),
        sum("jellyfish.traffic.egress.webrtc.total.bytes",
          event_name: @ice_sent_event,
          description: "Total WebRTC traffic sent (bytes)"
        ),
        sum("jellyfish.traffic.ingress.http.total.bytes",
          event_name: @http_request_event,
          description: "Total HTTP traffic received (bytes)"
        ),
        sum("jellyfish.traffic.egress.http.total.bytes",
          event_name: @http_response_event,
          description: "Total HTTP traffic sent (bytes)"
        ),
        last_value("jellyfish.rooms",
          description: "Amount of rooms currently present in Jellyfish"
        ),

        # FIXME: Prometheus warns about using labels to store dimensions with high cardinality,
        # such as UUIDs. For more information refer here: https://prometheus.io/docs/practices/naming/#labels
        last_value("jellyfish.room.peers",
          tags: [:room_id],
          description: "Amount of peers currently present in a given room"
        ),
        sum("jellyfish.room.peer_time.total.seconds",
          event_name: [:jellyfish, :room],
          measurement: :peer_time_total,
          tags: [:room_id],
          description: "Total peer time accumulated for a given room (seconds)"
        )
      ]
  end

  def default_webrtc_metrics() do
    :telemetry.execute(
      [Membrane.ICE, :ice, :payload, :sent],
      %{
        bytes: 0
      }
    )

    :telemetry.execute(
      [Membrane.ICE, :ice, :payload, :received],
      %{
        bytes: 0
      }
    )
  end
end
