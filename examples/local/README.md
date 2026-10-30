# Local example

Applies circuit-cloudflared to a throwaway Rocky Linux 10 container with systemd, running a Quick Tunnel so you don't need a Cloudflare account. You need Conn3x and Podman.

Rootful Podman is simplest. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` The tunnel points at port 8080 in the container, where nothing is listening yet, so give it something to serve and ask the service for its address:

```sh
alias box='ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1'
box 'dnf -qy install python3; mkdir -p /srv/origin; echo hello > /srv/origin/index.html; nohup python3 -m http.server 8080 -d /srv/origin >/dev/null 2>&1 &'
box journalctl -u cloudflared | grep trycloudflare.com
```

Open that URL and you get `hello`. It can take a few seconds to resolve. The address changes whenever the service restarts.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

To run a named tunnel instead, write `quick_tunnel_url = null` to a file such as `token.tfvars`, and pass your token at run time. `-var quick_tunnel_url=null` won't do, as that's the text "null":

```sh
export TF_VAR_tunnel_token=...
conn3x apply -var-file=token.tfvars
```

`./down.sh` removes the container, its volumes, the key and the state.
