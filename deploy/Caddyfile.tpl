__DOMAIN__ {

    encode gzip

    reverse_proxy app:8000

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Strict-Transport-Security "max-age=31536000;"
        X-XSS-Protection "1; mode=block"
    }
}

__KUMA_DOMAIN__ {

    encode gzip

    reverse_proxy uptime-kuma:3001 {
        flush_interval -1
    }

    header {
        X-Content-Type-Options nosniff
        Strict-Transport-Security "max-age=31536000;"
    }
}
