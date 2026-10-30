variable "port" {
  type    = number
  default = 2222
}

variable "tunnel_token" {
  type      = string
  default   = null
  ephemeral = true
  sensitive = true
}

# Null runs the named tunnel that tunnel_token belongs to.
variable "quick_tunnel_url" {
  type    = string
  default = "http://localhost:8080"
}

module "cloudflared" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  quick_tunnel_url = var.quick_tunnel_url
  tunnel_token     = var.tunnel_token
}

output "binary" {
  value = module.cloudflared.binary
}
