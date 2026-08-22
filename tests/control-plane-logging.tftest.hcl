run "creates_control_plane_logging" {
  command = apply

  module {
    source = "./examples/control-plane-logging"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "OKE cluster must be created"
  }
  assert {
    condition     = output.control_plane_log_group_id != null
    error_message = "Control-plane log group must be created"
  }
  assert {
    condition     = length(output.control_plane_log_ids) == 2
    error_message = "Both enabled control-plane log categories must have a log created"
  }
}
