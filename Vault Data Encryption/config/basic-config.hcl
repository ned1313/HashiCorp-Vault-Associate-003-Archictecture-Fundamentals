ui = true
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}

api_addr = "http://vault-basic:8200"
disable_mlock = true