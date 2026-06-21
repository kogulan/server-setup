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
$host_name = $_SERVER['HTTP_HOST'];
$clean_host = explode(':', $host_name)[0];
$proto = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http';
$access_choice = getenv('ACCESS_CHOICE') ?: '';


// Database Credentials from Environment
$mariadb_host = 'mariadb-db';
$mariadb_user = 'web_app_user';
$mariadb_pass = getenv('WEB_DB_PASS') ?: 'password';
$mariadb_db   = 'web_app_db';

$postgres_host = 'postgres-db';
$postgres_user = 'admin';
$postgres_pass = getenv('POSTGRES_PASSWORD') ?: 'password';
$postgres_db   = 'postgres';

$mariadb_status = get_db_status('mariadb', $mariadb_host, $mariadb_user, $mariadb_pass, $mariadb_db);
$postgres_status = get_db_status('postgres', $postgres_host, $postgres_user, $postgres_pass, $postgres_db);

// Prefer the installer-selected access mode so the landing page matches the
// generated nginx configuration. Fall back to host detection for older installs
// that have not yet passed ACCESS_CHOICE into the PHP container.
$is_port_access = $access_choice === '2';
if ($access_choice !== '1' && $access_choice !== '2') {
    $is_port_access = (strpos($host_name, ':') !== false) || preg_match('/^\d+\.\d+\.\d+\.\d+$/', explode(':', $host_name)[0]);
}

function get_service_url($base_proto, $clean_host, $port, $subdomain) {
    global $is_port_access;
    if ($is_port_access) {
        return "$base_proto://$clean_host:$port";
    }

    return "$base_proto://$subdomain.$clean_host";
}

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
        .links a { margin-right: 15px; color: #007bff; text-decoration: none; font-weight: bold; display: inline-block; margin-bottom: 10px; }
        .links a:hover { text-decoration: underline; }
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
            <span class="label">MariaDB (Web App):</span>
            <span class="value"><?php echo $mariadb_status; ?></span>
        </div>
        <div class="status-item">
            <span class="label">PostgreSQL (Shared):</span>
            <span class="value"><?php echo $postgres_status; ?></span>
        </div>

        <div class="links">
            <strong>Tools & Services:</strong><br><br>
            <a href="<?php echo get_service_url($proto, $clean_host, '8080', 'db'); ?>" target="_blank">Adminer (DB)</a>
            <a href="<?php echo get_service_url($proto, $clean_host, '5678', 'n8n'); ?>" target="_blank">n8n</a>
            <a href="<?php echo get_service_url($proto, $clean_host, '8081', 'ap'); ?>" target="_blank">Activepieces</a>
            <a href="<?php echo get_service_url($proto, $clean_host, '3000', 'huginn'); ?>" target="_blank">Huginn</a>
        </div>
        <hr>
        <p><small>Generated passwords and SFTP details can be retrieved by running <code>sudo /opt/deploy/scripts/show_credentials.sh</code> on the server.</small></p>
    </div>
</body>
</html>
