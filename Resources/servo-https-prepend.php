<?php

// Servo terminates TLS in Caddy and forwards the request to PHP on loopback.
// Reflect the original scheme before the application bootstraps so frameworks
// generate secure asset, route, form, and WebSocket URLs.
if (strtolower($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
