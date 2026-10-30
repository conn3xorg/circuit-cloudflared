variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "cloudflared_version" {
  type        = string
  default     = "2026.10.6"
  description = "cloudflared release to install, such as \"2026.10.6\". Change checksums with it."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cloudflared_version))
    error_message = "cloudflared_version must look like \"2026.10.6\", without a leading v."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the release binary for each architecture, from the release's notes. Change these with cloudflared_version."
  default = {
    amd64 = "1d356dac769d0dbf62ebe588c4034824bbff98d5790c2f844cc99e0e2f57462d"
    arm64 = "0ae0e179475b2c77651a718d2b376e0151f4fca5954702a84f02843a4d5fcac0"
  }

  validation {
    condition     = alltrue([for c in values(var.checksums) : can(regex("^[0-9a-f]{64}$", c))])
    error_message = "Each of checksums must be a SHA-256 in lowercase hex."
  }
}

variable "tunnel_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Token of the remotely managed tunnel to run, from the Cloudflare dashboard or API. Required on every plan and apply, unless quick_tunnel_url is set."

  validation {
    condition     = var.quick_tunnel_url != null || can(regex("^[A-Za-z0-9+/_=-]+$", var.tunnel_token))
    error_message = "Set tunnel_token to the tunnel's token, one base64 string, or set quick_tunnel_url."
  }
}

variable "quick_tunnel_url" {
  type        = string
  default     = null
  description = "Local URL to serve through a temporary trycloudflare.com Quick Tunnel instead of a named tunnel, such as \"http://localhost:8080\". Cloudflare offers Quick Tunnels for testing and development only. Takes the place of tunnel_token."

  validation {
    condition     = var.quick_tunnel_url == null || can(regex("^https?://[A-Za-z0-9.:_\\[\\]-]+(/[A-Za-z0-9._~/-]*)?$", coalesce(var.quick_tunnel_url, "-")))
    error_message = "quick_tunnel_url must be an http or https URL such as \"http://localhost:8080\"."
  }
}

variable "extra_args" {
  type        = list(string)
  default     = []
  description = "More flags for cloudflared tunnel, such as [\"--protocol=http2\"]. They land in the systemd unit, so they can't carry a token."

  validation {
    condition     = alltrue([for a in var.extra_args : can(regex("^--[a-z0-9-]+(=[A-Za-z0-9_.,:/@+=-]*)?$", a))])
    error_message = "Each of extra_args must be one flag such as \"--protocol=http2\", without spaces or quotes."
  }

  # The unit sits in the plan and state, where a secret mustn't go.
  validation {
    condition     = alltrue([for a in var.extra_args : !can(regex("^--(token|credentials-contents|url|hello-world)", a))])
    error_message = "extra_args can't set --token, --token-file, --credentials-contents, --url or --hello-world. Use tunnel_token or quick_tunnel_url."
  }
}
