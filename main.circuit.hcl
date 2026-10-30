# Facts give each host's architecture, which picks the release binary.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  goarch = { x86_64 = "amd64", aarch64 = "arm64" }
  arch   = { for name, f in data.conn3x_host.facts : name => local.goarch[f.arch] }

  # Each release keeps its own path, so changing the version changes the unit
  # and restarts the service on the new binary.
  bin  = "/opt/cloudflared/${var.cloudflared_version}/cloudflared"
  link = "/usr/local/bin/cloudflared"

  token_file = "/etc/cloudflared/token"
  quick      = var.quick_tunnel_url != null

  # The token stays out of the unit, and so out of the process list, the plan
  # and state: cloudflared reads it from the file. --no-autoupdate keeps the
  # binary at the pinned version.
  exec_start = join(" ", concat(
    [local.bin, "--no-autoupdate", "tunnel"],
    var.extra_args,
    local.quick ? ["--url", var.quick_tunnel_url] : ["run", "--token-file", local.token_file],
  ))
}

circuit "cloudflared" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Minimal images can lack these. cloudflared checks its connections to
  # Cloudflare and any https origin against the system's CA bundle.
  step "tools" {
    for_each = toset(["curl", "ca-certificates"])
    package {
      name = item.value
    }
  }

  step "user" {
    user {
      name   = "cloudflared"
      system = true
      home   = "/var/lib/cloudflared"
      shell  = "/usr/sbin/nologin"
    }
  }

  step "binary" {
    download {
      url    = "https://github.com/cloudflare/cloudflared/releases/download/${var.cloudflared_version}/cloudflared-linux-${local.arch[each.key]}"
      sha256 = var.checksums[local.arch[each.key]]
      dest   = local.bin
      mode   = "0755"
    }
  }

  step "link" {
    link {
      path   = local.link
      target = local.bin
    }
  }

  step "token_dir" {
    for_each = local.quick ? toset([]) : toset(["token"])
    directory {
      path  = "/etc/cloudflared"
      owner = "cloudflared"
      mode  = "0700"
    }
  }

  step "token" {
    for_each = local.quick ? toset([]) : toset(["token"])
    file {
      path       = local.token_file
      content_wo = var.tunnel_token
      owner      = "cloudflared"
      mode       = "0600"
      # Moving to a Quick Tunnel removes the step, and with it the token.
      on_remove = "delete"
    }
    notify = [handler.restart]
  }

  # Close to the unit cloudflared service install writes, but as its own user
  # rather than root. Type=notify holds the start until the tunnel has a
  # connection to Cloudflare, so an apply fails when the tunnel can't connect.
  # Upstream allows 15 seconds, which is tight on a slow first connection.
  step "unit" {
    file {
      path    = "/etc/systemd/system/cloudflared.service"
      content = <<-EOT
        [Unit]
        Description=Cloudflare Tunnel client
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=notify
        User=cloudflared
        Group=cloudflared
        ExecStart=${local.exec_start}
        TimeoutStartSec=60
        Restart=on-failure
        RestartSec=5s
        NoNewPrivileges=true
        ProtectSystem=strict
        ProtectHome=true
        PrivateTmp=true

        [Install]
        WantedBy=multi-user.target
      EOT
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "cloudflared"
      state   = "started"
      enabled = true
    }
  }

  handler "restart" {
    service {
      name = "cloudflared"
    }
  }
}
