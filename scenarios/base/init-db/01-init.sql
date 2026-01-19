-- ============================================================================
-- VTCS Cyber Range - Database Initialization
-- ============================================================================
-- Creates tables and sample data for the vulnerable web application
-- ============================================================================

-- Users table (intentionally insecure - plain text passwords for demo)
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    role VARCHAR(20) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2),
    stock INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    product_id INT,
    quantity INT,
    total DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample users (plain text passwords - intentionally insecure!)
INSERT INTO users (username, password, email, role) VALUES
    ('admin', 'admin123', 'admin@vtcslab.local', 'admin'),
    ('user1', 'password1', 'user1@vtcslab.local', 'user'),
    ('user2', 'password2', 'user2@vtcslab.local', 'user'),
    ('guest', 'guest', 'guest@vtcslab.local', 'guest');

-- Insert sample products
INSERT INTO products (name, description, price, stock) VALUES
    ('Laptop Pro', 'High-performance laptop for professionals', 1299.99, 10),
    ('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 50),
    ('USB-C Hub', '7-in-1 USB-C hub with HDMI', 49.99, 30),
    ('Mechanical Keyboard', 'RGB mechanical keyboard', 89.99, 25),
    ('Monitor 27"', '4K IPS monitor', 399.99, 15),
    ('Webcam HD', '1080p webcam with microphone', 59.99, 40),
    ('Headset Pro', 'Noise-canceling headset', 149.99, 20),
    ('SSD 1TB', 'NVMe solid state drive', 99.99, 35);

-- Secret table (for SQL injection discovery training)
CREATE TABLE IF NOT EXISTS secrets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    flag VARCHAR(255),
    hint TEXT
);

INSERT INTO secrets (flag, hint) VALUES
    ('FLAG{sql_injection_master}', 'You found the secret table!'),
    ('FLAG{union_select_champion}', 'Nice UNION SELECT skills!');
