<?php
// Railway healthcheck: 200 only when PHP runs, the database answers and the install created the admin user.
// Anything else is 503, so the deploy is not reported healthy while the first-boot install is still running.
$url = parse_url(getenv('DATABASE_URL') ?: '');
try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%d;dbname=%s', $url['host'], $url['port'] ?? 3306, ltrim($url['path'], '/')),
        urldecode($url['user']),
        urldecode($url['pass']),
        [PDO::ATTR_TIMEOUT => 3, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $n = (int) $pdo->query('SELECT COUNT(*) FROM `user`')->fetchColumn();
    http_response_code($n > 0 ? 200 : 503);
    header('Content-Type: text/plain');
    echo $n > 0 ? "ok\n" : "installing\n";
} catch (Throwable $e) {
    http_response_code(503);
    header('Content-Type: text/plain');
    echo "unavailable\n";
}
