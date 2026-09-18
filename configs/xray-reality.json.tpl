{
  "inbounds": [
    {
      "port": "<PORT>",
      "protocol": "vless",
      "settings": {"clients": [{"id": "<UUID>", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "<SNI>:443", "serverNames": ["<SNI>"], "privateKey": "<PRIVATE_KEY>", "shortIds": ["<SHORT_ID>"]}}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
