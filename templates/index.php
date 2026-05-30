<?php
header('Content-Type: text/html; charset=utf-8');

function get_db_status($type, $host, $user, $pass, $db) {
    try {
        if ($type === 'mariadb') {
            $conn = new mysqli($host, $user, $pass, $db);
            if ($conn->connect_error) return "❌ Error: " . $conn->connect_error;
            $version = $conn->server_info;
            $conn->close();
            return "✅ Connected (Version: $version)";
        } else {
            $dsn = "pgsql:host=$host;port=5432;dbname=$db;";
            $pdo = new PDO($dsn, $user, $pass);
            $version = $pdo->getAttribute(PDO::ATTR_SERVER_VERSION);
            return "✅ Connected (Version: $version)";
        }
    } catch (Exception $e) {
        return "❌ Error: " . $e->getMessage();
    }
}

$web_server_version = $_SERVER['SERVER_SOFTWARE'];
$php_version = PHP_VERSION;

// Credentials from Environment
$mariadb_host = 'mariadb-db';
$mariadb_user = 'root';
$mariadb_pass = getenv('MARIADB_ROOT_PASSWORD') ?: 'password';
$mariadb_db   = 'mysql';

$postgres_host = 'postgres-db';
$postgres_user = 'admin';
$postgres_pass = getenv('POSTGRES_PASSWORD') ?: 'password';
$postgres_db   = 'postgres';

$mariadb_status = get_db_status('mariadb', $mariadb_host, $mariadb_user, $mariadb_pass, $mariadb_db);
$postgres_status = get_db_status('postgres', $postgres_host, $postgres_user, $postgres_pass, $postgres_db);

?>
<!DOCTYPE html>
<html>
<head>
    <title>OCI Deployment Status</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 20px; background: #f4f4f9; }
        .card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        .status-item { margin-bottom: 15px; }
        .label { font-weight: bold; width: 200px; display: inline-block; }
        .value { color: #555; }
        .links { margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; }
        .links a { margin-right: 15px; color: #007bff; text-decoration: none; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <h1>OCI Deployment Status</h1>
        <div class="status-item">
            <span class="label">Web Server:</span>
            <span class="value"><?php echo $web_server_version; ?></span>
        </div>
        <div class="status-item">
            <span class="label">PHP Version:</span>
            <span class="value"><?php echo $php_version; ?></span>
        </div>
        <div class="status-item">
            <span class="label">MariaDB Status:</span>
            <span class="value"><?php echo $mariadb_status; ?></span>
        </div>
        <div class="status-item">
            <span class="label">PostgreSQL Status:</span>
            <span class="value"><?php echo $postgres_status; ?></span>
        </div>

        <div class="links">
            <strong>Tools & Services:</strong><br><br>
            <a href="/adminer" target="_blank">Adminer (DB Management)</a>
            <a href="/n8n" target="_blank">n8n</a>
            <a href="/ap" target="_blank">Activepieces</a>
            <a href="/huginn" target="_blank">Huginn</a>
        </div>
        <p><small>Note: If using Port-based access, use the specific ports (8080, 5678, 8081, 3000) instead of these links.</small></p>
    </div>
</body>
</html>
