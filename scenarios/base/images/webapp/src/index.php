<?php
// ============================================================================
// VTCS Cyber Range - Vulnerable Web Application
// ============================================================================
// INTENTIONALLY VULNERABLE - FOR TRAINING PURPOSES ONLY
// DO NOT DEPLOY IN PRODUCTION
// ============================================================================

session_start();

$db_host = getenv('DB_HOST') ?: 'database';
$db_name = getenv('DB_NAME') ?: 'labdb';
$db_user = getenv('DB_USER') ?: 'labuser';
$db_pass = getenv('DB_PASS') ?: 'labpass123';

// Database connection (error handling intentionally weak)
try {
    $pdo = new PDO("mysql:host=$db_host;dbname=$db_name", $db_user, $db_pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    // Intentionally verbose error (information disclosure)
    die("Database connection failed: " . $e->getMessage());
}

$page = isset($_GET['page']) ? $_GET['page'] : 'home';
$message = '';

// Handle login (intentionally vulnerable to SQL injection)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) {
    $username = $_POST['username'];
    $password = $_POST['password'];
    
    // VULNERABLE: SQL Injection - uses string concatenation instead of prepared statements
    $query = "SELECT * FROM users WHERE username = '$username' AND password = '$password'";
    
    try {
        $result = $pdo->query($query);
        $user = $result->fetch(PDO::FETCH_ASSOC);
        
        if ($user) {
            $_SESSION['user'] = $user['username'];
            $_SESSION['role'] = $user['role'];
            $message = '<div class="alert success">Welcome, ' . $user['username'] . '!</div>';
        } else {
            // VULNERABLE: Username enumeration possible
            $message = '<div class="alert error">Invalid credentials</div>';
        }
    } catch (PDOException $e) {
        // VULNERABLE: Detailed error messages
        $message = '<div class="alert error">Query error: ' . $e->getMessage() . '</div>';
    }
}

// Handle search (intentionally vulnerable to XSS)
$search_results = [];
if (isset($_GET['search'])) {
    $search = $_GET['search'];
    // VULNERABLE: Reflected XSS - no output encoding
    $message = '<div class="alert info">Search results for: ' . $search . '</div>';
    
    // Also vulnerable to SQL injection
    $query = "SELECT * FROM products WHERE name LIKE '%$search%'";
    try {
        $result = $pdo->query($query);
        $search_results = $result->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $e) {
        $message .= '<div class="alert error">Search error: ' . $e->getMessage() . '</div>';
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VTCS Shop - Vulnerable Demo App</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: Arial, sans-serif; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        header { background: #2c3e50; color: white; padding: 20px; margin-bottom: 20px; }
        header h1 { margin-bottom: 10px; }
        nav a { color: white; margin-right: 15px; text-decoration: none; }
        nav a:hover { text-decoration: underline; }
        .alert { padding: 15px; margin-bottom: 20px; border-radius: 4px; }
        .alert.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert.info { background: #cce5ff; color: #004085; border: 1px solid #b8daff; }
        .card { background: white; padding: 20px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        form input, form button { padding: 10px; margin: 5px 0; width: 100%; max-width: 300px; }
        form button { background: #3498db; color: white; border: none; cursor: pointer; }
        form button:hover { background: #2980b9; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        .warning-banner { background: #e74c3c; color: white; padding: 10px; text-align: center; }
    </style>
</head>
<body>
    <div class="warning-banner">
        ⚠️ INTENTIONALLY VULNERABLE APPLICATION - FOR TRAINING ONLY ⚠️
    </div>
    
    <header>
        <h1>VTCS Shop</h1>
        <nav>
            <a href="?page=home">Home</a>
            <a href="?page=products">Products</a>
            <a href="?page=login">Login</a>
            <?php if (isset($_SESSION['user'])): ?>
                <a href="?page=admin">Admin</a>
                <a href="?logout=1">Logout (<?php echo htmlspecialchars($_SESSION['user']); ?>)</a>
            <?php endif; ?>
        </nav>
    </header>
    
    <div class="container">
        <?php echo $message; ?>
        
        <?php if ($page === 'home'): ?>
            <div class="card">
                <h2>Welcome to VTCS Shop</h2>
                <p>This is a deliberately vulnerable web application for security training.</p>
                <br>
                <h3>Search Products</h3>
                <form method="GET">
                    <input type="hidden" name="page" value="home">
                    <input type="text" name="search" placeholder="Search...">
                    <button type="submit">Search</button>
                </form>
                
                <?php if (!empty($search_results)): ?>
                    <h3>Results:</h3>
                    <table>
                        <tr><th>ID</th><th>Name</th><th>Price</th></tr>
                        <?php foreach ($search_results as $product): ?>
                            <tr>
                                <td><?php echo $product['id']; ?></td>
                                <td><?php echo $product['name']; ?></td>
                                <td>$<?php echo $product['price']; ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </table>
                <?php endif; ?>
            </div>
            
        <?php elseif ($page === 'login'): ?>
            <div class="card">
                <h2>Login</h2>
                <form method="POST">
                    <input type="text" name="username" placeholder="Username" required><br>
                    <input type="password" name="password" placeholder="Password" required><br>
                    <button type="submit" name="login">Login</button>
                </form>
                <br>
                <p><small>Hint: Try SQL injection on the login form</small></p>
            </div>
            
        <?php elseif ($page === 'admin'): ?>
            <div class="card">
                <h2>Admin Panel</h2>
                <?php if (isset($_SESSION['user'])): ?>
                    <p>Welcome, <?php echo $_SESSION['user']; ?>!</p>
                    <p>Role: <?php echo $_SESSION['role'] ?? 'user'; ?></p>
                    
                    <?php if (($_SESSION['role'] ?? '') === 'admin'): ?>
                        <h3>User List</h3>
                        <table>
                            <tr><th>ID</th><th>Username</th><th>Role</th></tr>
                            <?php
                            $users = $pdo->query("SELECT id, username, role FROM users")->fetchAll();
                            foreach ($users as $u):
                            ?>
                            <tr>
                                <td><?php echo $u['id']; ?></td>
                                <td><?php echo htmlspecialchars($u['username']); ?></td>
                                <td><?php echo htmlspecialchars($u['role']); ?></td>
                            </tr>
                            <?php endforeach; ?>
                        </table>
                    <?php else: ?>
                        <p>Access denied. Admin role required.</p>
                    <?php endif; ?>
                <?php else: ?>
                    <p>Please <a href="?page=login">login</a> first.</p>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        
        <div class="card">
            <h3>Known Vulnerabilities (Training)</h3>
            <ul>
                <li><strong>SQL Injection:</strong> Login form, search functionality</li>
                <li><strong>Cross-Site Scripting (XSS):</strong> Search results display</li>
                <li><strong>Information Disclosure:</strong> Verbose error messages</li>
                <li><strong>Weak Authentication:</strong> Plain text passwords in database</li>
            </ul>
        </div>
    </div>
</body>
</html>
<?php
// Handle logout
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: ?page=home');
    exit;
}
?>
