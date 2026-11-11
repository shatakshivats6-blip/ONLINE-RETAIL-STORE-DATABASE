DROP DATABASE IF EXISTS retail_db;
CREATE DATABASE retail_db;
USE retail_db;
-- ---------- TABLES ----------
CREATE TABLE customers (
  customer_id INT AUTO_INCREMENT PRIMARY KEY,
  first_name  VARCHAR(50) NOT NULL,
  last_name   VARCHAR(50) NOT NULL,
  email       VARCHAR(100) NOT NULL UNIQUE,
  phone       VARCHAR(20),
  address     VARCHAR(255),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(80) NOT NULL UNIQUE,
  parent_id   INT NULL,
  FOREIGN KEY (parent_id) REFERENCES categories(category_id) ON DELETE SET NULL
);
CREATE TABLE products (
  product_id  INT AUTO_INCREMENT PRIMARY KEY,
  sku         VARCHAR(30) NOT NULL UNIQUE,
  name        VARCHAR(150) NOT NULL,
  category_id INT,
  price       DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  cost        DECIMAL(10,2) DEFAULT 0,
  is_active   BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE SET NULL
);
CREATE TABLE inventory (
  product_id       INT PRIMARY KEY,
  quantity_on_hand INT NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  reorder_level    INT DEFAULT 5,
  last_restock     DATE,
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
);
CREATE TABLE orders (
  order_id     INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NOT NULL,
  order_date   DATETIME DEFAULT CURRENT_TIMESTAMP,
  status       ENUM('PENDING','PAID','SHIPPED','DELIVERED','CANCELLED') DEFAULT 'PENDING',
  total_amount DECIMAL(12,2) DEFAULT 0,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  INDEX idx_orders_customer (customer_id)
);
CREATE TABLE order_items (
  order_item_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id      INT NOT NULL,
  product_id    INT NOT NULL,
  quantity      INT NOT NULL CHECK (quantity > 0),
  unit_price    DECIMAL(10,2) NOT NULL,
  UNIQUE KEY uq_order_product (order_id, product_id),
  FOREIGN KEY (order_id)   REFERENCES orders(order_id)   ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(product_id)
);
CREATE TABLE payments (
  payment_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT NOT NULL,
  amount     DECIMAL(12,2) NOT NULL,
  method     ENUM('CARD','CASH','UPI','NETBANKING') NOT NULL,
  status     ENUM('SUCCESS','FAILED','REFUNDED') DEFAULT 'SUCCESS',
  paid_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);
CREATE TABLE shipments (
  shipment_id     INT AUTO_INCREMENT PRIMARY KEY,
  order_id        INT NOT NULL,
  carrier         VARCHAR(60),
  tracking_number VARCHAR(60),
  shipped_date    DATE,
  delivered_date  DATE,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);
-- ---------- TRIGGERS ----------
DELIMITER $ 
CREATE TRIGGER trg_order_item_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  UPDATE inventory
     SET quantity_on_hand = quantity_on_hand - NEW.quantity
   WHERE product_id = NEW.product_id;
  UPDATE orders
     SET total_amount = total_amount + (NEW.quantity * NEW.unit_price)
   WHERE order_id = NEW.order_id;
END $
CREATE TRIGGER trg_payment_after_insert
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
  DECLARE paid DECIMAL(12,2);
  DECLARE ord_total DECIMAL(12,2);
  SELECT COALESCE(SUM(amount),0) INTO paid
    FROM payments WHERE order_id = NEW.order_id AND status='SUCCESS';
  SELECT total_amount INTO ord_total FROM orders WHERE order_id = NEW.order_id;
  IF paid >= ord_total THEN
    UPDATE orders SET status='PAID' WHERE order_id = NEW.order_id;
  END IF;
END$$
DELIMITER ;
-- ---------- VIEWS ----------
CREATE VIEW v_product_stock AS
SELECT p.product_id, p.name, p.price, i.quantity_on_hand, i.reorder_level,
CASE WHEN i.quantity_on_hand <= i.reorder_level THEN 'REORDER' ELSE 'OK' END AS stock_status
FROM products p JOIN inventory i ON p.product_id = i.product_id;
CREATE VIEW v_order_summary AS
SELECT o.order_id, CONCAT(c.first_name,' ',c.last_name) AS customer,
o.order_date, o.status, o.total_amount,
(SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.order_id) AS item_count
FROM orders o JOIN customers c ON o.customer_id = c.customer_id;
-- ---------- SAMPLE DATA ----------
INSERT INTO customers (first_name,last_name,email,phone) VALUES
('Ayesha','Malik','ayesha@mail.com','0311-111'),
('Bilal','Raza','bilal@mail.com','0311-222'),
('Chen','Lee','chen@mail.com','0311-333');
INSERT INTO categories (name, parent_id) VALUES
('Electronics',NULL),('Books',NULL),('Laptops',1),('Fiction',2);
INSERT INTO products (sku,name,category_id,price,cost) VALUES
('SKU-001','Dell Inspiron 15',3,850.00,700.00),
('SKU-002','HP Pavilion 14',3,780.00,650.00),
('SKU-003','Clean Code Book',4,45.00,25.00),
('SKU-004','Wireless Mouse',1,25.00,10.00);
INSERT INTO inventory VALUES
(1,10,3,'2024-01-01'),(2,5,3,'2024-01-01'),
(3,50,10,'2024-01-05'),(4,100,20,'2024-01-05');
INSERT INTO orders (customer_id, status) VALUES (1,'PENDING'),(2,'PENDING');
INSERT INTO order_items (order_id,product_id,quantity,unit_price) VALUES
(1,1,1,850.00),(1,3,2,45.00),
(2,4,3,25.00);
INSERT INTO payments (order_id,amount,method) VALUES
(1,940.00,'CARD'),(2,75.00,'UPI');
INSERT INTO shipments (order_id,carrier,tracking_number,shipped_date) VALUES
(1,'DHL','DHL123','2024-02-10'),(2,'TCS','TCS456','2024-02-11');
-- ---------- SAMPLE QUERIES ----------
SELECT * FROM v_product_stock WHERE stock_status='REORDER';
SELECT * FROM v_order_summary;
SELECT c.customer_id, CONCAT(c.first_name,' ',c.last_name) AS customer,
SUM(o.total_amount) AS lifetime_value
FROM customers c JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id ORDER BY lifetime_value DESC;
SELECT p.name, SUM(oi.quantity) AS units_sold, SUM(oi.quantity*oi.unit_price) AS revenue
FROM order_items oi JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_id ORDER BY revenue DESC;
SELECT DATE_FORMAT(order_date,'%Y-%m') AS month, COUNT(*) AS orders, SUM(total_amount) AS revenue
FROM orders GROUP BY month ORDER BY month;
